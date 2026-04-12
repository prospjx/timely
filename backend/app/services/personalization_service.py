from __future__ import annotations

from collections import defaultdict
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

from app.db.mongo import mongo


def _interaction_signal(entry: dict) -> float:
    action_id = str(entry.get("action_id", "")).lower()
    is_completion = bool(entry.get("is_completion")) or action_id == "task_due"
    is_distraction = bool(entry.get("is_distraction")) or action_id == "scrolling"
    is_snooze = bool(entry.get("is_snooze")) or action_id == "snooze"

    signal = 0.0
    if is_completion:
        signal += 1.4
    if is_distraction:
        signal -= 1.8
    if is_snooze:
        signal -= 0.8
    if action_id == "urgent_task":
        signal += 0.2
    return signal


def _to_local_hour(value: datetime, timezone_name: str) -> int:
    tz = ZoneInfo(timezone_name)
    if value.tzinfo is None:
        return value.replace(tzinfo=tz).hour
    return value.astimezone(tz).hour


async def build_hour_preference_map(user_doc: dict, lookback_days: int = 21) -> dict[int, float]:
    timezone_name = user_doc.get("timezone", "UTC")
    tz = ZoneInfo(timezone_name)
    window_start = datetime.now(tz) - timedelta(days=lookback_days)

    cursor = mongo.collection("notification_interactions").find(
        {
            "user_id": user_doc["_id"],
            "timestamp": {"$gte": window_start},
        }
    )

    hour_totals: dict[int, float] = defaultdict(float)
    hour_counts: dict[int, int] = defaultdict(int)

    async for item in cursor:
        timestamp = item.get("timestamp")
        if timestamp is None:
            continue

        hour = _to_local_hour(timestamp, timezone_name)
        hour_totals[hour] += _interaction_signal(item)
        hour_counts[hour] += 1

    if not hour_counts:
        return {}

    return {
        hour: (hour_totals[hour] / hour_counts[hour])
        for hour in hour_counts
    }