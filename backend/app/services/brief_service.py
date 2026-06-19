from __future__ import annotations

from datetime import datetime, timedelta
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from app.models.common import mongo_to_dict
from app.services import notification_service


def _dedupe_schedule_items(items: list[dict]) -> list[dict]:
    deduped: list[dict] = []
    seen: set[tuple] = set()
    for item in items:
        signature = (
            str(item.get("user_id")),
            str(item.get("task_id")),
            str(item.get("title")),
            str(item.get("type")),
            item.get("start_time"),
            item.get("end_time"),
        )
        if signature in seen:
            continue
        seen.add(signature)
        deduped.append(item)
    return deduped


def _format_time(value: datetime) -> str:
    if not hasattr(value, "strftime"):
        return str(value)
    return value.strftime("%I:%M %p").lstrip("0")


def _brief_text_for(schedule_items: list[dict], now: datetime) -> str:
    todays = sorted(schedule_items, key=lambda item: item.get("start_time"))
    if not todays:
        return "Today is open. You have no scheduled items yet. Add an event or deadline to build your day."

    must_do: list[dict] = []
    flexible: list[dict] = []

    for item in todays:
        block_type = str(item.get("type", "Task"))
        title = str(item.get("title", block_type))
        priority = str(item.get("priority", "Medium")).lower()
        start = item.get("start_time")

        if block_type.lower() == "meeting":
            must_do.append(item)
            continue

        if priority == "high":
            must_do.append(item)
            continue

        if isinstance(start, datetime) and start.date() == now.date() and start.hour <= 13:
            must_do.append(item)
            continue

        flexible.append(item)

    must_lines = []
    for item in must_do[:4]:
        title = str(item.get("title", "Task"))
        start = item.get("start_time")
        if isinstance(start, datetime):
            must_lines.append(f"{title} at {_format_time(start)}")
        else:
            must_lines.append(title)

    flex_lines = []
    for item in flexible[:4]:
        title = str(item.get("title", "Task"))
        start = item.get("start_time")
        if isinstance(start, datetime):
            flex_lines.append(f"{title} around {_format_time(start)}")
        else:
            flex_lines.append(title)

    lead = f"You have {len(todays)} items on your plan today."
    must_section = "Must do today: " + ("; ".join(must_lines) if must_lines else "No hard commitments yet") + "."
    flex_section = "Flexible: " + ("; ".join(flex_lines) if flex_lines else "No flexible items") + "."
    return f"{lead} {must_section} {flex_section}"


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
        zone = ZoneInfo("UTC")

    now = datetime.now(zone)
    day_start = now.replace(hour=0, minute=0, second=0, microsecond=0)
    day_end = day_start + timedelta(days=1)

    schedule_cursor = schedule_collection.find(
        {
            "user_id": user_doc["_id"],
            "start_time": {"$gte": day_start, "$lt": day_end},
        }
    )
    schedule_items = _dedupe_schedule_items([mongo_to_dict(item) async for item in schedule_cursor])

    text = _brief_text_for(schedule_items, now)

    try:
        delivered = await notification_service.send_brief_to_phone(user_doc, text, None)
    except Exception:
        delivered = False

    return {"success": True, "text": text, "audio_url": None, "notification_sent": delivered}
