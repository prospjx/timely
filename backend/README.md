# Kairos Backend

Async FastAPI backend for task parsing, scheduling, diagnostics logging, and daily brief delivery.

## What is Implemented
- FastAPI app entrypoint with async lifespan in `app/main.py`
- MongoDB connection with `motor`
- Pydantic request/response models
- Services:
  - Gemini task parsing + brief generation (`app/services/gemini_service.py`)
  - ElevenLabs TTS (`app/services/elevenlabs_service.py`)
  - Scheduling engine with conflict detection (`app/services/scheduling_engine.py`)
  - Firebase notifications (`app/services/notification_service.py`)
- Routers:
  - `POST /api/v1/tasks/process`
  - `GET /api/v1/schedule/today`
  - `POST /api/v1/diagnostics/log`
  - `POST /api/v1/brief/trigger`
- APScheduler daily cron hook (`app/scheduler/jobs.py`)

## Quick Start
1. Create and activate a Python virtual environment.
2. Install dependencies:
   - `pip install -r requirements.txt`
3. Copy env file:
   - `copy .env.example .env`
4. Fill in credentials in `.env`.
5. Run API:
   - `uvicorn app.main:app --reload --port 8000`

## Auth / User Context for now
This scaffold uses request headers to identify users until Firebase Auth middleware is added.

Required/optional headers:
- `X-Firebase-Uid` (optional, default: `demo-user`)
- `X-Timezone` (optional, default: `UTC`)

## Notes
- If Gemini keys are missing, task parsing and brief generation fall back to deterministic local behavior.
- If ElevenLabs or Firebase are not configured, brief endpoint still succeeds but may skip audio or push delivery.
- `/audio/*` is served from local generated files. Use `AUDIO_PUBLIC_BASE_URL` if this backend is exposed externally.
