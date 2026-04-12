from __future__ import annotations

import uuid
from pathlib import Path

import httpx
from gtts import gTTS

from app.core.config import get_settings


def _audio_output_path() -> tuple[Path, str]:
    filename = f"brief_{uuid.uuid4().hex}.mp3"
    audio_dir = Path(__file__).resolve().parents[2] / "generated_audio"
    audio_dir.mkdir(parents=True, exist_ok=True)
    return audio_dir / filename, filename


def _public_audio_url(filename: str) -> str:
    settings = get_settings()
    if settings.audio_public_base_url:
        return f"{settings.audio_public_base_url.rstrip('/')}/{filename}"
    return f"/audio/{filename}"


def _generate_fallback_tts(text: str) -> str | None:
    try:
        file_path, filename = _audio_output_path()
        # Fallback voice path when ElevenLabs is unavailable.
        gTTS(text=text, lang="en").save(str(file_path))
        return _public_audio_url(filename)
    except Exception:
        return None


async def generate_audio(text: str) -> str | None:
    settings = get_settings()
    if not settings.elevenlabs_api_key or not settings.elevenlabs_voice_id:
        return _generate_fallback_tts(text)

    url = f"https://api.elevenlabs.io/v1/text-to-speech/{settings.elevenlabs_voice_id}"
    headers = {
        "xi-api-key": settings.elevenlabs_api_key,
        "Content-Type": "application/json",
        "Accept": "audio/mpeg",
    }
    payload = {
        "text": text,
        "model_id": "eleven_multilingual_v2",
        "voice_settings": {"stability": 0.45, "similarity_boost": 0.75},
    }

    try:
        async with httpx.AsyncClient(timeout=30) as client:
            response = await client.post(url, headers=headers, json=payload)
            response.raise_for_status()
            audio_bytes = response.content
    except Exception:
        return _generate_fallback_tts(text)

    file_path, filename = _audio_output_path()
    file_path.write_bytes(audio_bytes)
    return _public_audio_url(filename)
