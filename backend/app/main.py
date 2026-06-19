from __future__ import annotations

from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles

from app.core.config import get_settings
from app.db.mongo import mongo
from app.routers import brief, diagnostics, schedule, tasks, google_auth
from app.scheduler.jobs import start_scheduler, stop_scheduler


@asynccontextmanager
async def lifespan(_app: FastAPI):
    settings = get_settings()
    await mongo.connect(settings.mongodb_uri, settings.mongodb_db_name)
    start_scheduler()
    try:
        yield
    finally:
        stop_scheduler()
        await mongo.disconnect()


settings = get_settings()
app = FastAPI(title=settings.app_name, lifespan=lifespan)

app.include_router(tasks.router, prefix=settings.api_prefix)
app.include_router(schedule.router, prefix=settings.api_prefix)
app.include_router(diagnostics.router, prefix=settings.api_prefix)
app.include_router(brief.router, prefix=settings.api_prefix)
app.include_router(google_auth.router, prefix=settings.api_prefix)


audio_dir = Path(__file__).resolve().parents[1] / "generated_audio"
audio_dir.mkdir(parents=True, exist_ok=True)
app.mount("/audio", StaticFiles(directory=str(audio_dir)), name="audio")


@app.get("/health")
async def health() -> dict:
    return {"status": "ok"}
