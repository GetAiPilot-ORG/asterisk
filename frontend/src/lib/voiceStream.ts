/**
 * Minimum-latency voice streaming client.
 *
 * Flow:
 *   connect() → send config → stream PCM audio (binary) →
 *   receive transcript events + MP3 audio binary frames →
 *   queue audio for gapless playback
 *
 * Barge-in: detected via analyser node volume spike during playback;
 * sends {"type":"barge_in"} and stops all queued audio immediately.
 */

export interface VoiceStreamConfig {
  wsUrl: string;          // e.g. "wss://host/ws/voice"
  voiceId: string;
  voiceGender?: string;
  systemPrompt: string;
  model: string;
  knowledgeBase?: string;
  language?: string;
  ttsProvider?: string;
}

export interface VoiceStreamCallbacks {
  onReady?: () => void;
  onTranscript?: (text: string, isFinal: boolean, speechFinal: boolean) => void;
  onLlmText?: (text: string) => void;
  onTurnEnd?: () => void;
  onLatency?: (data: LatencySummary) => void;
  onStopAudio?: () => void;
  onError?: (msg: string) => void;
  onVolumeChange?: (volume: number) => void;
  onAudioSent?: (framesCount: number) => void;
  onSpeechStarted?: () => void;
  onSpeechEnded?: () => void;
}

export interface LatencySummary {
  stt_eot_ms: number | null;
  llm_first_token_ms: number | null;
  tts_first_byte_ms: number | null;
  total_perceived_ms: number | null;
}

// ─────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────
const SAMPLE_RATE = 16000;   // Deepgram expects 16 kHz
const PCM_CHUNK_SIZE = 4096; // samples per ScriptProcessor callback
const SPEECH_THRESHOLD = 0.012;
const SILENCE_THRESHOLD = 0.005;
const BARGE_IN_VOLUME_THRESHOLD = 0.04;

function downsampleBuffer(buffer: Float32Array, inputRate: number, outputRate: number): Float32Array {
  if (inputRate === outputRate) return buffer;
  const ratio = inputRate / outputRate;
  const newLength = Math.round(buffer.length / ratio);
  const result = new Float32Array(newLength);
  for (let i = 0; i < newLength; i++) {
    const originIndex = i * ratio;
    const index = Math.floor(originIndex);
    const decimal = originIndex - index;
    const nextIndex = Math.min(index + 1, buffer.length - 1);
    result[i] = buffer[index] * (1 - decimal) + buffer[nextIndex] * decimal;
  }
  return result;
}

export class VoiceStreamClient {
  private ws: WebSocket | null = null;
  private recordingCtx: AudioContext | null = null;
  private playbackCtx: AudioContext | null = null;
  private stream: MediaStream | null = null;
  private sourceNode: MediaStreamAudioSourceNode | null = null;
  private processor: ScriptProcessorNode | null = null;
  private analyser: AnalyserNode | null = null;
  private isRecording = false;
  private isPlaying = false;
  private activeSources: AudioBufferSourceNode[] = [];
  private nextPlayTime = 0;
  private callbacks: VoiceStreamCallbacks;

  constructor(callbacks: VoiceStreamCallbacks) {
    this.callbacks = callbacks;
  }

  // ── Connection ──────────────────────────────────────────────

  async connect(cfg: VoiceStreamConfig, deviceId?: string): Promise<void> {
    if (this.ws?.readyState === WebSocket.OPEN) return;

    // 1. Acquire mic and AudioContext synchronously in user gesture
    await this._startMic(deviceId);

    // 2. Unlock playback AudioContext in user gesture so mobile Chrome allows audio output
    await this._initPlaybackAudio();

    // 3. Open WebSocket
    this.ws = new WebSocket(cfg.wsUrl);
    this.ws.binaryType = "arraybuffer";

    await new Promise<void>((resolve, reject) => {
      this.ws!.onopen = () => resolve();
      this.ws!.onerror = () => reject(new Error("WS connect failed"));
    });

    this.ws.onmessage = (e) => this._handleMessage(e);
    this.ws.onclose = () => {
      this.callbacks.onError?.("Connection closed");
      this._stopRecording();
    };

    // 3. Send session config
    this._sendJson({
      type: "config",
      voice_id: cfg.voiceId,
      voice_gender: cfg.voiceGender,
      system_prompt: cfg.systemPrompt,
      model: cfg.model,
      knowledge_base: cfg.knowledgeBase ?? "",
      language: cfg.language ?? "en-US",
      tts_provider: cfg.ttsProvider ?? "deepgram",
    });
  }

  disconnect(): void {
    this._sendJson({ type: "end_session" });
    this._stopRecording();
    this._stopAllAudio();
    this.ws?.close();
    this.ws = null;
    this.playbackCtx?.close();
    this.playbackCtx = null;
  }

  bargeIn(): void {
    this._sendJson({ type: "barge_in" });
    this._stopAllAudio();
  }

  getAnalyser(): AnalyserNode | null {
    return this.analyser;
  }

  // ── Microphone ──────────────────────────────────────────────

  private async _startMic(deviceId?: string): Promise<void> {
    if (!navigator?.mediaDevices?.getUserMedia) {
      const isHttps = typeof window !== "undefined" && window.location.protocol === "https:";
      if (!isHttps) {
        throw new Error(
          "Microphone access blocked: Chrome on mobile blocks mic on insecure HTTP (http://192.168...). Please open https://192.168.1.34:5173 (tap 'Advanced' -> 'Proceed') or test on PC at http://localhost:5173"
        );
      }
      throw new Error("Microphone API (getUserMedia) not supported in this browser.");
    }

    const constraints: MediaStreamConstraints = {
      audio: {
        echoCancellation: true,
        noiseSuppression: true,
        autoGainControl: true,
      },
    };
    if (deviceId && deviceId !== "default" && deviceId.trim() !== "") {
      (constraints.audio as MediaTrackConstraints).deviceId = { ideal: deviceId };
    }

    try {
      this.stream = await navigator.mediaDevices.getUserMedia(constraints);
    } catch (err: any) {
      if (err.name === "NotAllowedError" || err.name === "PermissionDeniedError") {
        throw new Error("Microphone permission was denied. Please allow microphone access in your browser settings.");
      }
      throw err;
    }

    // Use native hardware AudioContext rate (48k/44.1k/etc.) to avoid mobile audio driver failures
    const AudioCtxClass = window.AudioContext || (window as any).webkitAudioContext;
    this.recordingCtx = new AudioCtxClass();
    if (this.recordingCtx.state === "suspended") {
      await this.recordingCtx.resume();
    }

    const inputSampleRate = this.recordingCtx.sampleRate;

    // Retain sourceNode on class instance to prevent V8 garbage collector from cutting audio
    this.sourceNode = this.recordingCtx.createMediaStreamSource(this.stream);

    // Analyser for volume / barge-in detection
    this.analyser = this.recordingCtx.createAnalyser();
    this.analyser.fftSize = 256;
    this.sourceNode.connect(this.analyser);

    this.processor = this.recordingCtx.createScriptProcessor(PCM_CHUNK_SIZE, 1, 1);
    this.sourceNode.connect(this.processor);

    // CRITICAL FOR MOBILE: Connect through a muted gain node (gain=0) to destination.
    // If connected directly, phone audio HAL activates hardware echo cancellation and completely zeros out the mic input!
    const muteGain = this.recordingCtx.createGain();
    muteGain.gain.value = 0;
    this.processor.connect(muteGain);
    muteGain.connect(this.recordingCtx.destination);

    let speaking = false;
    let framesSent = 0;

    this.processor.onaudioprocess = (e) => {
      const channelData = e.inputBuffer.getChannelData(0);

      // Volume calculation
      let sum = 0;
      for (let i = 0; i < channelData.length; i++) sum += channelData[i] ** 2;
      const vol = Math.sqrt(sum / channelData.length);
      this.callbacks.onVolumeChange?.(vol);

      // Speech activity tracking
      if (vol > SPEECH_THRESHOLD && !speaking) {
        speaking = true;
        this.callbacks.onSpeechStarted?.();
      } else if (vol < SILENCE_THRESHOLD && speaking) {
        speaking = false;
        this.callbacks.onSpeechEnded?.();
      }

      // Resample down to 16 kHz for Deepgram
      const resampled = downsampleBuffer(channelData, inputSampleRate, SAMPLE_RATE);

      // Convert float32 → int16 PCM and send to WebSocket
      if (this.ws?.readyState === WebSocket.OPEN) {
        const pcm = new Int16Array(resampled.length);
        for (let i = 0; i < resampled.length; i++) {
          const s = Math.max(-1, Math.min(1, resampled[i]));
          pcm[i] = s < 0 ? s * 0x8000 : s * 0x7fff;
        }
        this.ws.send(pcm.buffer);
        framesSent++;
        this.callbacks.onAudioSent?.(framesSent);
      }
    };

    this.isRecording = true;
  }

  private _stopRecording(): void {
    this.processor?.disconnect();
    this.processor = null;
    this.sourceNode?.disconnect();
    this.sourceNode = null;
    this.analyser?.disconnect();
    this.analyser = null;
    this.stream?.getTracks().forEach((t) => t.stop());
    this.stream = null;
    this.recordingCtx?.close();
    this.recordingCtx = null;
    this.isRecording = false;
  }

  // ── Audio playback ──────────────────────────────────────────

  private async _initPlaybackAudio(): Promise<void> {
    const AudioCtxClass = window.AudioContext || (window as any).webkitAudioContext;
    if (!this.playbackCtx || this.playbackCtx.state === "closed") {
      this.playbackCtx = new AudioCtxClass();
    }
    if (this.playbackCtx.state === "suspended") {
      try {
        await this.playbackCtx.resume();
      } catch {}
    }
    // Prime the audio output hardware with a 1-sample silent buffer during user gesture
    try {
      const dummy = this.playbackCtx.createBuffer(1, 1, 22050);
      const src = this.playbackCtx.createBufferSource();
      src.buffer = dummy;
      src.connect(this.playbackCtx.destination);
      src.start(0);
    } catch {}
  }

  private async _playAudioBytes(data: ArrayBuffer): Promise<void> {
    if (!this.playbackCtx || this.playbackCtx.state === "closed") {
      await this._initPlaybackAudio();
    }
    const ctx = this.playbackCtx!;
    if (ctx.state === "suspended") {
      try {
        await ctx.resume();
      } catch {}
    }
    
    // Parse raw 16-bit signed PCM (mono, 16 kHz)
    const pcmData = new Int16Array(data);
    if (pcmData.length === 0) return;

    // Convert to float32 PCM [-1.0, 1.0]
    const float32Data = new Float32Array(pcmData.length);
    for (let i = 0; i < pcmData.length; i++) {
      float32Data[i] = pcmData[i] / 32768.0;
    }

    // Create AudioBuffer
    const buffer = ctx.createBuffer(1, float32Data.length, SAMPLE_RATE);
    buffer.copyToChannel(float32Data, 0);

    const source = ctx.createBufferSource();
    source.buffer = buffer;
    source.connect(ctx.destination);
    this.activeSources.push(source);
    source.onended = () => {
      const idx = this.activeSources.indexOf(source);
      if (idx !== -1) this.activeSources.splice(idx, 1);
      if (this.activeSources.length === 0) {
        this.isPlaying = false;
        this.nextPlayTime = 0;
      }
    };

    // Gapless: schedule back-to-back with drift protection
    const now = ctx.currentTime;
    if (this.nextPlayTime < now || this.nextPlayTime > now + 1.0) {
      this.nextPlayTime = now;
    }
    const start = Math.max(now, this.nextPlayTime);
    source.start(start);
    this.nextPlayTime = start + buffer.duration;
    this.isPlaying = true;
  }

  private _stopAllAudio(): void {
    const sources = [...this.activeSources];
    sources.forEach((s) => {
      try { s.stop(); } catch { /* already stopped */ }
    });
    this.activeSources = [];
    this.isPlaying = false;
    this.nextPlayTime = 0;
    this.callbacks.onStopAudio?.();
  }

  // ── Message handler ─────────────────────────────────────────

  private _handleMessage(e: MessageEvent): void {
    if (e.data instanceof ArrayBuffer) {
      // MP3 audio frame — queue for playback
      void this._playAudioBytes(e.data);
      return;
    }

    let msg: Record<string, unknown>;
    try {
      msg = JSON.parse(e.data as string);
    } catch {
      return;
    }

    switch (msg.type) {
      case "ready":
        this.callbacks.onReady?.();
        break;
      case "transcript":
        this.callbacks.onTranscript?.(
          msg.text as string,
          msg.is_final as boolean,
          msg.speech_final as boolean,
        );
        break;
      case "llm_text":
        this.callbacks.onLlmText?.(msg.text as string);
        break;
      case "turn_end":
        this.callbacks.onTurnEnd?.();
        break;
      case "latency":
        this.callbacks.onLatency?.(msg as unknown as LatencySummary);
        break;
      case "stop_audio":
        this._stopAllAudio();
        break;
      case "error":
        this.callbacks.onError?.(msg.message as string);
        break;
    }
  }

  // ── Helpers ─────────────────────────────────────────────────

  private _sendJson(data: unknown): void {
    if (this.ws?.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify(data));
    }
  }
}
