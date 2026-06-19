from __future__ import annotations

from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

from bson import ObjectId

from app.db.mongo import mongo
from app.models.schemas import ScheduleBlockType, TaskPriority


def _wake_sleep_datetimes(reference: datetime, wake_time: str, sleep_time: str) -> tuple[datetime, datetime]:
    wake_hour, wake_minute = [int(x) for x in wake_time.split(":")]
    sleep_hour, sleep_minute = [int(x) for x in sleep_time.split(":")]
    day_start = reference.replace(hour=wake_hour, minute=wake_minute, second=0, microsecond=0)
    day_end = reference.replace(hour=sleep_hour, minute=sleep_minute, second=0, microsecond=0)
    if day_end <= day_start:
        day_end = day_end + timedelta(days=1)
    return day_start, day_end


async def _find_overlap(user_id: ObjectId, start_time: datetime, end_time: datetime) -> dict | None:
    blocks = mongo.collection("schedule_blocks")
    return await blocks.find_one(
        {
            "user_id": user_id,
            "start_time": {"$lt": end_time},
            "end_time": {"$gt": start_time},
        }
    )


async def _find_slot_between(
    *,
    user_id: ObjectId,
    window_start: datetime,
    window_end: datetime,
    duration: timedelta,
    step: timedelta,
) -> tuple[datetime, datetime] | None:
    cursor = window_start
    while cursor + duration <= window_end:
        candidate_end = cursor + duration
        overlap = await _find_overlap(user_id, cursor, candidate_end)
        if overlap is None:
            return cursor, candidate_end
        cursor = max(cursor + step, overlap["end_time"])
    return None


async def _next_slot_before_deadline(
    *,
    user_doc: dict,
    deadline: datetime,
    duration: timedelta,
    starts_not_before: datetime,
) -> tuple[datetime, datetime] | None:
    user_id = user_doc["_id"]
    preferences = user_doc.get("preferences", {})
    wake_time = preferences.get("wake_time", "07:00")
    sleep_time = preferences.get("sleep_time", "22:30")

    step = timedelta(minutes=15)
    day_cursor = starts_not_before

    while day_cursor < deadline:
        day_start, day_end = _wake_sleep_datetimes(day_cursor, wake_time, sleep_time)
        window_start = max(starts_not_before, day_start)
        window_end = min(deadline, day_end)

        if window_start < window_end:
            slot = await _find_slot_between(
                user_id=user_id,
                window_start=window_start,
                window_end=window_end,
                duration=duration,
                step=step,
            )
            if slot is not None:
                return slot

        day_cursor = day_start + timedelta(days=1)

    return None


async def schedule_event_block(user_doc: dict, task_doc: dict) -> dict:
    user_id = user_doc["_id"]
    start_time = task_doc["deadline"]
    duration = timedelta(minutes=task_doc["estimated_minutes"])
    end_time = start_time + duration

    overlap = await _find_overlap(user_id, start_time, end_time)
    if overlap is not None:
        raise ValueError(
            "Conflict detected: another activity already exists at the selected event time. "
            "Pick a different time or remove the conflicting activity."
        )

    return {
        "user_id": user_id,
        "task_id": task_doc["_id"],
        "start_time": start_time,
        "end_time": end_time,
        "type": ScheduleBlockType.meeting.value,
        "source": task_doc.get("source", "manual"),
        "priority": task_doc.get("priority", TaskPriority.medium.value),
    }


async def schedule_deadline_block(user_doc: dict, task_doc: dict, *, starts_not_before: datetime | None = None) -> dict:
    timezone = user_doc.get("timezone", "UTC")
    now_local = datetime.now(ZoneInfo(timezone))
    deadline = task_doc["deadline"]
    earliest = max(now_local, starts_not_before or now_local)
    duration = timedelta(minutes=task_doc["estimated_minutes"])

    slot = await _next_slot_before_deadline(
        user_doc=user_doc,
        deadline=deadline,
        duration=duration,
        starts_not_before=earliest,
    )
    if slot is None:
        raise ValueError("No available schedule slot before deadline")

    start_time, end_time = slot
    return {
        "user_id": user_doc["_id"],
        "task_id": task_doc["_id"],
        "start_time": start_time,
        "end_time": end_time,
        "type": ScheduleBlockType.task.value,
        "source": task_doc.get("source", "manual"),
        "priority": task_doc.get("priority", TaskPriority.medium.value),
    }


async def schedule_task(user_doc: dict, task_doc: dict) -> dict:
    if bool(task_doc.get("fixed_day", False)):
        return await schedule_event_block(user_doc, task_doc)
    return await schedule_deadline_block(user_doc, task_doc)


async def reshuffle_incomplete_deadlines(user_doc: dict) -> list[dict]:
    timezone = user_doc.get("timezone", "UTC")
    now_local = datetime.now(ZoneInfo(timezone))

    tasks = mongo.collection("tasks")
    blocks = mongo.collection("schedule_blocks")

    cursor = blocks.find(
        {
            "user_id": user_doc["_id"],
            "type": ScheduleBlockType.task.value,
            "end_time": {"$lte": now_local},
        }
    ).sort("end_time", 1)

    moved: list[dict] = []

    async for block in cursor:
        task_id = block.get("task_id")
        if task_id is None:
            continue

        task_doc = await tasks.find_one({"_id": task_id, "user_id": user_doc["_id"]})
        if not task_doc:
            continue

        if task_doc.get("status") == "Completed":
            continue

        if bool(task_doc.get("fixed_day", False)):
            continue

        if task_doc.get("deadline") <= now_local:
            continue

        try:
            new_block = await schedule_deadline_block(
                user_doc,
                task_doc,
                starts_not_before=now_local + timedelta(minutes=15),
            )
        except ValueError:
            continue

        await blocks.update_one(
            {"_id": block["_id"]},
            {
                "$set": {
                    "start_time": new_block["start_time"],
                    "end_time": new_block["end_time"],
                    "source": "reshuffled",
                }
            },
        )

        moved.append(
            {
                "task_id": task_id,
                "title": task_doc.get("title", "Task"),
                "new_start_time": new_block["start_time"],
                "new_end_time": new_block["end_time"],
            }
        )

    return moved
