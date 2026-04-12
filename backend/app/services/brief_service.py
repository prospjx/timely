from __future__ import annotations

from datetime import datetime, timedelta
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from app.models.common import mongo_to_dict
from app.services import elevenlabs_service, gemini_service, notification_service


def _schedule_signature(item: dict) -> tuple:
    return (
        str(item.get("user_id")),
        str(item.get("task_id")),
        str(item.get("title")),
        str(item.get("type")),
        item.get("start_time"),
        item.get("end_time"),
    )


def _dedupe_schedule_items(items: list[dict]) -> list[dict]:
    deduped: list[dict] = []
    seen: set[tuple] = set()
    for item in items:
        signature = _schedule_signature(item)
        if signature in seen:
            continue
        seen.add(signature)
        deduped.append(item)
    return deduped


async def trigger_brief_for_user(
    user_doc: dict,
    schedule_collection,
    diagnostics_collection,
    client_local_time_iso: str | None = None,
    client_time_display: str | None = None,
) -> dict:
    timezone = user_doc.get("timezone", "UTC")
    try:
        zone = ZoneInfo(timezone)
    except ZoneInfoNotFoundError:
        timezone = "UTC"
        zone = ZoneInfo("UTC")

    now = datetime.now(zone)

    day_start = now.replace(hour=0, minute=0, second=0, microsecond=0)
    day_end = day_start + timedelta(days=1)
    yesterday_start = day_start - timedelta(days=1)

    schedule_cursor = schedule_collection.find(
        {
            "user_id": user_doc["_id"],
            "start_time": {"$gte": day_start, "$lt": day_end},
        }
    )
    schedule_items = _dedupe_schedule_items([mongo_to_dict(item) async for item in schedule_cursor])

    diagnostics_cursor = diagnostics_collection.find(
        {
            "user_id": user_doc["_id"],
            "timestamp": {"$gte": yesterday_start, "$lt": day_start},
        }
    )
    diagnostics = [mongo_to_dict(item) async for item in diagnostics_cursor]

    weather_summary = "No weather provider connected"
    user_name = user_doc.get("name") or user_doc.get("display_name") or "Prosper"
    text = await gemini_service.generate_brief(
        schedule_items,
        diagnostics,
        weather_summary,
        timezone=timezone,
        user_name=user_name,
        client_local_time_iso=client_local_time_iso,
        client_time_display=client_time_display,
    )
    try:
        audio_url = await elevenlabs_service.generate_audio(text)
    except Exception:
        audio_url = None

    try:
        delivered = await notification_service.send_brief_to_phone(user_doc, text, audio_url)
    except Exception:
        delivered = False

    return {"success": True, "text": text, "audio_url": audio_url, "notification_sent": delivered}
