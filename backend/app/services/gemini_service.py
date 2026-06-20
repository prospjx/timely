from __future__ import annotations

import json
import re
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

from pydantic import BaseModel, Field

from app.core.config import get_settings
from app.core.datetime_utils import ensure_aware
from app.models.schemas import ParsedTask, TaskPriority


class DeadlineSlotSuggestion(BaseModel):
    start_time: datetime
    reason: str = Field(default="", max_length=280)

try:
    import google.generativeai as genai
except ImportError:  # pragma: no cover
    genai = None


_PRIORITY_MAP = {
    "urgent": TaskPriority.high,
    "important": TaskPriority.high,
    "high": TaskPriority.high,
    "medium": TaskPriority.medium,
    "normal": TaskPriority.medium,
    "low": TaskPriority.low,
}

_WEEKDAY_MAP = {
    "monday": 0,
    "tuesday": 1,
    "wednesday": 2,
    "thursday": 3,
    "friday": 4,
    "saturday": 5,
    "sunday": 6,
}


def _extract_title(raw_text: str) -> str:
    text = raw_text.strip()

    # Structured quick-add format: "<title>. Priority ... Deadline ..."
    split_match = re.split(r"\.\s*priority\b", text, flags=re.IGNORECASE, maxsplit=1)
    if split_match and split_match[0].strip():
        return split_match[0].strip()

    # Alternative explicit format: "Task title: <title>."
    explicit_match = re.search(r"task\s*title\s*:\s*(.+?)(?:\.|$)", text, flags=re.IGNORECASE)
    if explicit_match:
        return explicit_match.group(1).strip()

    return text


def _extract_explicit_datetime(raw_text: str, timezone: str, mode: str) -> datetime | None:
    if mode == "event":
        pattern = r"event\s+date\s+(\d{4}-\d{2}-\d{2})(?:[\sT](\d{1,2}):(\d{2}))?"
    else:
        pattern = r"deadline\s+(\d{4}-\d{2}-\d{2})(?:[\sT](\d{1,2}):(\d{2}))?"

    explicit = re.search(pattern, raw_text, flags=re.IGNORECASE)
    if not explicit:
        return None

    date_part = explicit.group(1)
    hour = int(explicit.group(2) or 17)
    minute = int(explicit.group(3) or 0)
    parsed_date = datetime.strptime(date_part, "%Y-%m-%d")
    return parsed_date.replace(hour=hour, minute=minute, second=0, microsecond=0, tzinfo=ZoneInfo(timezone))


def _fallback_parse_task(raw_text: str, timezone: str = "UTC") -> ParsedTask:
    lower = raw_text.lower()
    fixed_day = "schedule mode event" in lower or "keep this on that day only" in lower

    priority = TaskPriority.medium
    for token, mapped in _PRIORITY_MAP.items():
        if token in lower:
            priority = mapped
            break

    estimated_minutes = 60
    hour_match = re.search(r"(\d+)\s*(h|hr|hrs|hour|hours)", lower)
    minute_match = re.search(r"(\d+)\s*(m|min|mins|minute|minutes)", lower)
    if hour_match:
        estimated_minutes = max(5, min(600, int(hour_match.group(1)) * 60))
    elif minute_match:
        estimated_minutes = max(5, min(600, int(minute_match.group(1))))

    now = datetime.now(ZoneInfo(timezone))
    deadline = now + timedelta(hours=8)

    explicit_deadline = re.search(
        r"deadline\s+(\d{4}-\d{2}-\d{2})(?:[\sT](\d{1,2}):(\d{2}))?",
        raw_text,
        flags=re.IGNORECASE,
    )
    if explicit_deadline:
        date_part = explicit_deadline.group(1)
        hour = int(explicit_deadline.group(2) or 17)
        minute = int(explicit_deadline.group(3) or 0)
        parsed_date = datetime.strptime(date_part, "%Y-%m-%d")
        deadline = parsed_date.replace(hour=hour, minute=minute, second=0, microsecond=0, tzinfo=ZoneInfo(timezone))

    weekday_match = re.search(r"\b(on\s+)?(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b", lower)
    if weekday_match and not explicit_deadline:
        target_weekday = _WEEKDAY_MAP[weekday_match.group(2)]
        delta_days = (target_weekday - now.weekday()) % 7
        if delta_days == 0:
            delta_days = 7
        deadline = (now + timedelta(days=delta_days)).replace(hour=17, minute=0, second=0, microsecond=0)

    by_time_match = re.search(r"by\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?", lower)
    if by_time_match:
        hour = int(by_time_match.group(1))
        minute = int(by_time_match.group(2) or 0)
        meridiem = by_time_match.group(3)
        if meridiem == "pm" and hour != 12:
            hour += 12
        if meridiem == "am" and hour == 12:
            hour = 0
        candidate = now.replace(hour=hour, minute=minute, second=0, microsecond=0)
        if "tomorrow" in lower or candidate <= now:
            candidate = candidate + timedelta(days=1)
        deadline = candidate
    elif "tomorrow" in lower:
        deadline = (now + timedelta(days=1)).replace(hour=17, minute=0, second=0, microsecond=0)

    title = _extract_title(raw_text)
    return ParsedTask(
        title=title[:120],
        priority=priority,
        deadline=deadline,
        estimated_minutes=estimated_minutes,
        fixed_day=fixed_day,
    )


def _get_model():
    settings = get_settings()
    if not settings.gemini_api_key or genai is None:
        return None
    genai.configure(api_key=settings.gemini_api_key)
    return genai.GenerativeModel(settings.gemini_model)


async def parse_task(raw_text: str, timezone: str = "UTC") -> ParsedTask:
    model = _get_model()
    lower = raw_text.lower()
    force_event_mode = "schedule mode event" in lower or "keep this on that day only" in lower
    force_deadline_mode = "schedule mode deadline" in lower
    forced_event_date = _extract_explicit_datetime(raw_text, timezone, mode="event")
    forced_deadline = _extract_explicit_datetime(raw_text, timezone, mode="deadline")

    if model is None:
        parsed = _fallback_parse_task(raw_text, timezone)
        if force_event_mode:
            parsed = parsed.model_copy(update={"fixed_day": True})
            if forced_event_date is not None:
                parsed = parsed.model_copy(update={"deadline": forced_event_date})
        elif force_deadline_mode and forced_deadline is not None:
            parsed = parsed.model_copy(update={"fixed_day": False, "deadline": forced_deadline})
        return parsed

    now = datetime.now(ZoneInfo(timezone)).isoformat()
    prompt = (
        "You are a strict parser. Convert this user task into JSON with exactly these keys: "
        "title, priority (High|Medium|Low), deadline (ISO 8601), estimated_minutes (integer), fixed_day (boolean). "
        f"Current user-local datetime is {now}. User input: {raw_text}"
    )

    try:
        response = await model.generate_content_async(
            prompt,
            generation_config={"response_mime_type": "application/json"},
        )
        payload = json.loads(response.text)
        parsed = ParsedTask.model_validate(payload)

        # User mode/date inputs from the app should take precedence over model drift.
        if force_event_mode:
            parsed = parsed.model_copy(update={"fixed_day": True})
            if forced_event_date is not None:
                parsed = parsed.model_copy(update={"deadline": forced_event_date})
        elif force_deadline_mode:
            parsed = parsed.model_copy(update={"fixed_day": False})
            if forced_deadline is not None:
                parsed = parsed.model_copy(update={"deadline": forced_deadline})

        return parsed
    except Exception:
        parsed = _fallback_parse_task(raw_text, timezone)
        if force_event_mode:
            parsed = parsed.model_copy(update={"fixed_day": True})
            if forced_event_date is not None:
                parsed = parsed.model_copy(update={"deadline": forced_event_date})
        elif force_deadline_mode and forced_deadline is not None:
            parsed = parsed.model_copy(update={"fixed_day": False, "deadline": forced_deadline})
        return parsed


async def suggest_deadline_slot(
    *,
    task: dict,
    availability: dict,
    timezone: str,
) -> DeadlineSlotSuggestion | None:
    """Pick a start time for a deadline task using calendar availability context."""
    model = _get_model()
    if model is None:
        return None

    now_iso = datetime.now(ZoneInfo(timezone)).isoformat()
    prompt = (
        "You are Timely's scheduling assistant. Place a flexible deadline task on the user's calendar.\n"
        "Rules:\n"
        "- The work block must fit entirely before the task deadline (start + duration <= deadline).\n"
        "- start_time must fall inside one of the provided free windows.\n"
        "- Prefer days with more free time when the deadline is far away.\n"
        "- When the deadline is soon (within ~2 days), schedule earlier even if that day is busier.\n"
        "- Higher priority tasks should be scheduled sooner when the deadline is tight.\n"
        "- Return JSON with exactly: start_time (ISO 8601 with timezone offset), reason (one short sentence).\n"
        f"Current user-local datetime: {now_iso}\n"
        f"Task and availability JSON:\n{json.dumps(availability, default=str)}"
    )

    try:
        response = await model.generate_content_async(
            prompt,
            generation_config={"response_mime_type": "application/json"},
        )
        payload = json.loads(response.text)
        suggestion = DeadlineSlotSuggestion.model_validate(payload)
        zone = ZoneInfo(timezone)
        start = ensure_aware(suggestion.start_time, assume_tz=zone)
        return suggestion.model_copy(update={"start_time": start})
    except Exception:
        return None


async def generate_brief(
    schedule_items: list[dict],
    diagnostics: list[dict],
    weather_summary: str,
    timezone: str = "UTC",
    user_name: str = "Prosper",
    client_local_time_iso: str | None = None,
    client_time_display: str | None = None,
) -> str:
    # Keep the brief deterministic and personal-assistant-like for consistent UX.
    return _assistant_style_brief(
        schedule_items,
        timezone=timezone,
        user_name=user_name,
        client_local_time_iso=client_local_time_iso,
        client_time_display=client_time_display,
    )


def _fallback_brief(schedule_items: list[dict], diagnostics: list[dict]) -> str:
    task_count = len(schedule_items)
    avg_energy = None
    if diagnostics:
        avg_energy = sum(item.get("energy_score", 3) for item in diagnostics) / len(diagnostics)

    if avg_energy is not None and avg_energy <= 2.5:
        tone = "I recommend a lighter pace today. Focus on one priority at a time and take a short reset after each block."
    else:
        tone = "You are set for a productive day. Start with the first block and keep transitions short to stay on track."

    base = f"Good morning. You have {task_count} scheduled blocks today. {tone}"
    return _ensure_agenda_section(base, schedule_items)


def _assistant_style_brief(
    schedule_items: list[dict],
    timezone: str,
    user_name: str,
    client_local_time_iso: str | None = None,
    client_time_display: str | None = None,
) -> str:
    now = datetime.now(ZoneInfo(timezone))
    display_name = (user_name or "Prosper").strip() or "Prosper"

    if client_time_display and client_time_display.strip():
        time_now = client_time_display.strip()
    elif client_local_time_iso:
        parsed = client_local_time_iso.replace("Z", "+00:00")
        try:
            client_dt = datetime.fromisoformat(parsed)
            time_now = client_dt.strftime("%I:%M %p").lstrip("0")
        except ValueError:
            time_now = now.strftime("%I:%M %p").lstrip("0")
    else:
        time_now = now.strftime("%I:%M %p").lstrip("0")

    count = len(schedule_items)
    task_label = "task" if count == 1 else "tasks"
    intro = (
        f"Good morning {display_name}, The time is currently {time_now}, "
        f"and you have {count} scheduled {task_label} for the day."
    )

    if count == 0:
        return intro + " Have a great day."

    clauses = _task_clauses(schedule_items)
    if len(clauses) == 1:
        agenda = clauses[0] + "."
    elif len(clauses) == 2:
        agenda = f"{clauses[0]}, and {clauses[1]}."
    else:
        agenda = ", ".join(clauses[:-1]) + f", and {clauses[-1]}."

    return f"{intro} {agenda} Have a great day."


def _task_clauses(schedule_items: list[dict], limit: int = 3) -> list[str]:
    items = _sorted_by_priority_then_time(schedule_items)[:limit]
    clauses: list[str] = []
    for item in items:
        start = _parse_start(item)
        time_label = start.strftime("%I%p").lstrip("0").lower() if start != datetime.min else "that time"
        title = str(item.get("title") or item.get("type") or "your task").strip()
        clauses.append(f"At {time_label} you have to {title}")
    return clauses


def _ensure_agenda_section(text: str, schedule_items: list[dict]) -> str:
    agenda = _agenda_lines(schedule_items)
    if not agenda:
        return text

    suffix = " Today's agenda: " + "; ".join(agenda) + "."
    if text.endswith("."):
        return text + suffix
    return text + "." + suffix


def _agenda_lines(schedule_items: list[dict], limit: int = 3) -> list[str]:
    if not schedule_items:
        return []

    sorted_items = _sorted_by_priority_then_time(schedule_items)
    lines: list[str] = []
    for item in sorted_items[:limit]:
        start = _parse_start(item)
        time_label = start.strftime("%H:%M") if start != datetime.min else "--:--"
        title = str(item.get("title") or item.get("type") or "Task").strip()
        lines.append(f"{time_label} {title}")
    return lines


def _parse_start(item: dict) -> datetime:
    value = item.get("start_time")
    if isinstance(value, datetime):
        return value
    if isinstance(value, str):
        try:
            return datetime.fromisoformat(value)
        except ValueError:
            pass
    return datetime.min


def _priority_rank(item: dict) -> int:
    priority = str(item.get("priority") or "").strip().lower()
    if priority in {"high", "a"} or "priority a" in priority:
        return 0
    if priority in {"medium", "b"} or "priority b" in priority:
        return 1
    if priority in {"low", "c"} or "priority c" in priority:
        return 2
    return 3


def _sorted_by_priority_then_time(schedule_items: list[dict]) -> list[dict]:
    return sorted(schedule_items, key=lambda item: (_priority_rank(item), _parse_start(item)))
