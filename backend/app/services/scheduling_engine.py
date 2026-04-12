from __future__ import annotations

from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

from bson import ObjectId

from app.core.config import get_settings
from app.db.mongo import mongo
from app.models.schemas import ScheduleBlockType, TaskPriority
from app.services.personalization_service import build_hour_preference_map


def _day_distance_to_deadline(candidate_start: datetime, deadline: datetime) -> int:
    candidate_day = candidate_start.date()
    deadline_day = deadline.date()
    delta = (deadline_day - candidate_day).days
    return delta if delta >= 0 else 10_000


def _wake_sleep_datetimes(reference: datetime, wake_time: str, sleep_time: str) -> tuple[datetime, datetime]:
    wake_hour, wake_minute = [int(x) for x in wake_time.split(":")]
    sleep_hour, sleep_minute = [int(x) for x in sleep_time.split(":")]
    start = reference.replace(hour=wake_hour, minute=wake_minute, second=0, microsecond=0)
    end = reference.replace(hour=sleep_hour, minute=sleep_minute, second=0, microsecond=0)
    if end <= start:
        end = end + timedelta(days=1)
    return start, end


async def _has_overlap(user_id: ObjectId, start_time: datetime, end_time: datetime) -> bool:
    blocks = mongo.collection("schedule_blocks")
    overlap = await blocks.find_one(
        {
            "user_id": user_id,
            "start_time": {"$lt": end_time},
            "end_time": {"$gt": start_time},
        }
    )
    return overlap is not None


async def _find_overlap(user_id: ObjectId, start_time: datetime, end_time: datetime) -> dict | None:
    blocks = mongo.collection("schedule_blocks")
    return await blocks.find_one(
        {
            "user_id": user_id,
            "start_time": {"$lt": end_time},
            "end_time": {"$gt": start_time},
        }
    )


async def _latest_adjacent_high_priority_end(user_id: ObjectId, start_time: datetime) -> datetime | None:
    schedule_blocks = mongo.collection("schedule_blocks")
    tasks = mongo.collection("tasks")

    prev_block = await schedule_blocks.find_one(
        {"user_id": user_id, "end_time": {"$lte": start_time}, "type": ScheduleBlockType.task.value},
        sort=[("end_time", -1)],
    )
    if not prev_block or not prev_block.get("task_id"):
        return None

    task = await tasks.find_one({"_id": prev_block["task_id"]})
    if not task or task.get("priority") != TaskPriority.high.value:
        return None

    return prev_block["end_time"]


async def _day_load_minutes(user_id: ObjectId, day_start: datetime, day_end: datetime) -> int:
    schedule_blocks = mongo.collection("schedule_blocks")
    cursor = schedule_blocks.find(
        {
            "user_id": user_id,
            "start_time": {"$lt": day_end},
            "end_time": {"$gt": day_start},
        }
    )

    total = 0
    async for block in cursor:
        start = max(block["start_time"], day_start)
        end = min(block["end_time"], day_end)
        total += int((end - start).total_seconds() // 60)
    return total


async def _day_first_block_start(user_id: ObjectId, day_start: datetime, day_end: datetime) -> datetime | None:
    schedule_blocks = mongo.collection("schedule_blocks")
    first_block = await schedule_blocks.find_one(
        {
            "user_id": user_id,
            "start_time": {"$gte": day_start, "$lt": day_end},
        },
        sort=[("start_time", 1)],
    )
    if not first_block:
        return None
    return first_block.get("start_time")


def _personalization_bias(
    hour: int,
    priority: str | None,
    hour_preferences: dict[int, float],
) -> int:
    if not hour_preferences or hour not in hour_preferences:
        return 0

    signal = hour_preferences[hour]
    # Positive signal means this hour historically had more focused completions.
    # Lower score is better in candidate ranking, so invert the signal.
    base_weight = 40 if priority == TaskPriority.low.value else 25
    bias = int(round(-signal * base_weight))
    return max(-120, min(120, bias))


def _priority_intra_day_bias(
    candidate_start: datetime,
    day_start: datetime,
    priority: str | None,
) -> int:
    minutes_from_day_start = int((candidate_start - day_start).total_seconds() // 60)
    if priority == TaskPriority.high.value:
        target_minutes = 0
    elif priority == TaskPriority.medium.value:
        target_minutes = 120
    else:
        target_minutes = 240
    return abs(minutes_from_day_start - target_minutes)


async def schedule_task(user_doc: dict, task_doc: dict) -> dict:
    settings = get_settings()
    user_id = user_doc["_id"]
    timezone = user_doc.get("timezone", "UTC")
    preferences = user_doc.get("preferences", {})

    wake_time = preferences.get("wake_time", "07:00")
    sleep_time = preferences.get("sleep_time", "22:30")

    now = datetime.now(ZoneInfo(timezone))
    deadline = task_doc["deadline"]
    fixed_day = bool(task_doc.get("fixed_day", False))
    task_priority = task_doc.get("priority")
    duration = timedelta(minutes=task_doc["estimated_minutes"])

    if fixed_day:
        candidate_start = deadline
        candidate_end = candidate_start + duration

        overlap = await _find_overlap(user_id, candidate_start, candidate_end)
        if overlap is not None:
            raise ValueError(
                "Conflict detected: another activity already exists at the selected event time. "
                "Pick a different time or remove the conflicting activity."
            )

        return {
            "user_id": user_id,
            "task_id": task_doc["_id"],
            "start_time": candidate_start,
            "end_time": candidate_end,
            "type": ScheduleBlockType.task.value,
        }

    cursor = now
    step = timedelta(minutes=30)
    day_load_cache: dict[datetime, int] = {}
    day_first_block_cache: dict[datetime, datetime | None] = {}
    candidates: list[tuple[int, int, datetime, datetime]] = []
    high_priority_candidates: list[tuple[int, int, int, datetime, datetime]] = []
    hour_preferences = await build_hour_preference_map(user_doc)

    while cursor + duration <= deadline:
        day_start, day_end = _wake_sleep_datetimes(cursor, wake_time, sleep_time)
        candidate_start = max(cursor, day_start)
        candidate_end = candidate_start + duration

        if candidate_end > day_end:
            cursor = day_start + timedelta(days=1)
            continue

        if await _has_overlap(user_id, candidate_start, candidate_end):
            cursor = candidate_start + step
            continue

        if task_priority == TaskPriority.high.value:
            prev_high_end = await _latest_adjacent_high_priority_end(user_id, candidate_start)
            if prev_high_end is not None:
                continuous_minutes = int((candidate_end - prev_high_end).total_seconds() // 60)
                if continuous_minutes > settings.max_high_priority_minutes_without_break:
                    cursor = candidate_start + step
                    continue

            day_key = day_start
            if day_key not in day_first_block_cache:
                day_first_block_cache[day_key] = await _day_first_block_start(user_id, day_start, day_end)

            first_block_start = day_first_block_cache[day_key]
            is_first_event_candidate = first_block_start is None or candidate_start <= first_block_start
            first_event_penalty = 0 if is_first_event_candidate else 1
            day_gap = _day_distance_to_deadline(candidate_start, deadline)
            intra_day_bias = _priority_intra_day_bias(candidate_start, day_start, task_priority)

            high_priority_candidates.append(
                (first_event_penalty, day_gap, intra_day_bias, candidate_start, candidate_end)
            )

            cursor = candidate_start + step
            continue

        day_key = day_start
        if day_key not in day_load_cache:
            day_load_cache[day_key] = await _day_load_minutes(user_id, day_start, day_end)

        # Medium/low priorities prefer less loaded days to reduce burnout.
        load_score = day_load_cache[day_key]
        if task_priority == TaskPriority.low.value:
            load_score += 60

        load_score += _personalization_bias(
            candidate_start.hour,
            task_priority,
            hour_preferences,
        )
        load_score += _priority_intra_day_bias(candidate_start, day_start, task_priority) // 6

        day_gap = _day_distance_to_deadline(candidate_start, deadline)
        candidates.append((load_score, day_gap, candidate_start, candidate_end))

        cursor = candidate_start + step

    if high_priority_candidates:
        _, _, _, best_start, best_end = min(
            high_priority_candidates,
            key=lambda item: (item[0], item[1], item[2], item[3]),
        )
        return {
            "user_id": user_id,
            "task_id": task_doc["_id"],
            "start_time": best_start,
            "end_time": best_end,
            "type": ScheduleBlockType.task.value,
        }

    if candidates:
        _, _, best_start, best_end = min(candidates, key=lambda item: (item[0], item[1], item[2]))
        return {
            "user_id": user_id,
            "task_id": task_doc["_id"],
            "start_time": best_start,
            "end_time": best_end,
            "type": ScheduleBlockType.task.value,
        }

    raise ValueError("No available schedule slot before deadline")
