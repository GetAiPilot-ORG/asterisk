/**
 * Dynamic API Base URL resolver.
 * When accessed from a mobile device or LAN IP (e.g., 192.168.x.x),
 * resolves to the current origin (e.g., http://192.168.1.34:5173) so all
 * API requests pass through the Vite reverse proxy to the VPS backend.
 * This completely avoids browser CORS rejections on mobile devices.
 */
export function getApiUrl(): string {
  if (typeof window !== "undefined" && window.location) {
    const hostname = window.location.hostname;
    // If accessed via a local network IP (e.g. mobile phone), use current origin
    if (hostname !== "localhost" && hostname !== "127.0.0.1") {
      return window.location.origin;
    }
  }

  const envUrl = import.meta.env.VITE_API_URL || import.meta.env.VITE_API_BASE_URL;
  if (envUrl && envUrl.trim() !== "") {
    return envUrl.replace(/\/$/, "");
  }

  if (typeof window !== "undefined" && window.location?.origin) {
    return window.location.origin;
  }

  return "http://localhost:8000";
}

export const API_URL = getApiUrl();
