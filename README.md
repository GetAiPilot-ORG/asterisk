# OmniDim Voice AI Platform (Asterisk & AudioSocket Integration)

An enterprise Voice AI platform integrating **FastAPI**, **Asterisk PBX via AudioSocket**, **Supabase**, and a modern **React / TanStack Router** frontend.

---

## 🏗 System Architecture

```text
               +-----------------------------+
               | Telecom Provider SIP Trunk  | (Airtel, Jio, Tata, etc.)
               +--------------+--------------+
                              | SIP / RTP
                              v
               +-----------------------------+
               | Asterisk PBX Server         | (Live VPS: 72.60.202.148)
               |  - PJSIP Trunk Endpoint     |
               |  - extensions.conf Dialplan |
               +--------------+--------------+
                              |
              AudioSocket TCP | HTTP Inbound Webhook
              Stream (:9092)  | (:8000/api/webhooks/asterisk/inbound)
                              v
               +-----------------------------+
               | FastAPI AI Engine (Backend) |
               |  - AudioSocket Protocol     |
               |  - Deepgram STT (Streaming) |
               |  - OpenAI LLM Orchestration |
               |  - Deepgram / Sarvam TTS    |
               |  - Call Admission Control   |
               +--------------+--------------+
                              |
               +--------------+--------------+
               |                             |
               v                             v
+-----------------------------+  +-----------------------------+
| Supabase (DB, Auth, Storage)|  | Vite + TanStack Frontend    |
|  - Profiles & Workspaces    |  |  - Dashboard & Analytics    |
|  - Agents, Prompts, Trunks  |  |  - Live Call Monitoring     |
|  - Call Logs & CDR Billing  |  |  - Audio Waveforms & Audio  |
+-----------------------------+  +-----------------------------+
```

---

## ⚡ Quick Start

### 1. Prerequisites
- **Node.js**: v18+ (tested on Node v24)
- **Python**: 3.10+ (tested on Python 3.14)
- **npm** or **bun**

### 2. Environment Variables Configuration

Both **Backend** and **Frontend** need an active `.env` file. Ready-to-use `.env.example` templates are provided in both directories.

#### Backend (`backend/.env`):
```bash
# Copy template
cp backend/.env.example backend/.env
```
Ensure your Supabase keys, OpenAI API key, and Deepgram API key are defined.

#### Frontend (`frontend/.env`):
```bash
# Copy template
cp frontend/.env.example frontend/.env
```
Ensure `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` match your Supabase project.

---

## 🚀 Running the Project

### Root Scripts (Unified)

From the project root directory (`/`):

| Command | Action |
|---|---|
| `npm run dev` | Runs the frontend Vite dev server |
| `npm run build` | Builds the production frontend bundle |
| `npm run backend:dev` | Runs the FastAPI backend with uvicorn (port 8000, reload enabled) |
| `npm run backend:diagnostics` | Runs connectivity checks for Supabase, OpenAI, AudioSocket, & Asterisk |
| `npm run backend:install` | Installs/updates backend Python dependencies |

---

### Manual Setup (Step-by-Step)

#### Backend:
```bash
cd backend

# Create virtual environment
python -m venv .venv

# Activate virtual environment
# Windows PowerShell:
.venv\Scripts\Activate.ps1
# Linux / macOS:
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Run local health & connection diagnostics
python app/scripts/local_diagnostics.py

# Launch development server
uvicorn app.main:app --host 127.0.0.1 --port 8000 --reload
```

Backend will be active at:
- **API URL**: [http://127.0.0.1:8000](http://127.0.0.1:8000)
- **Swagger Documentation**: [http://127.0.0.1:8000/docs](http://127.0.0.1:8000/docs)
- **AudioSocket TCP Server**: `127.0.0.1:9092`
- **Health Check**: [http://127.0.0.1:8000/health](http://127.0.0.1:8000/health)
- **Supabase DB Health**: [http://127.0.0.1:8000/health/db](http://127.0.0.1:8000/health/db)
- **AudioSocket Health**: [http://127.0.0.1:8000/api/health/asterisk](http://127.0.0.1:8000/api/health/asterisk)

#### Frontend:
```bash
cd frontend

# Install packages
npm install

# Start development server
npm run dev

# Build for production
npm run build
```

Frontend will be active at:
- **Local Dev Server**: [http://localhost:5173](http://localhost:5173)

---

## 📞 Asterisk & AudioSocket Setup

For detailed instructions on configuring Asterisk PBX with Airtel/Jio/Tata SIP trunks and routing calls via AudioSocket to the Voice AI backend, see:
- [docs/ASTERISK_SIP_TRUNK_SETUP.md](file:///docs/ASTERISK_SIP_TRUNK_SETUP.md)
