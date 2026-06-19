from __future__ import annotations

from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

from bson import ObjectId

from app.core.datetime_utils import ensure_aware
from app.db.mongo import mongo
from app.models.schemas import ScheduleBlockType, TaskPriority


def _wake_sleep_datetimes(reference: datetime, wake_time: str, sleep_time: str) -> tuple[datetime, datetime]:
    reference = ensure_aware(reference)
    wake_hour, wake_minute = [int(x) for x in wake_time.split(":")]
    sleep_hour, sleep_minute = [int(x) for x in sleep_time.split(":")]
    day_start = reference.replace(hour=wake_hour, minute=wake_minute, second=0, microsecond=0)
    day_end = reference.replace(hour=sleep_hour, minute=sleep_minute, second=0, microsecond=0)
    if day_end <= day_start:
        day_end = day_end + timedelta(days=1)
    return day_start, day_end


async def _find_overlap(
    user_id: ObjectId,
    start_time: datetime,
    end_time: datetime,
    *,
    exclude_block_id: ObjectId | None = None,
) -> dict | None:
    blocks = mongo.collection("schedule_blocks")
    query: dict = {
        "user_id": user_id,
        "start_time": {"$lt": end_time},
        "end_time": {"$gt": start_time},
    }
    if exclude_block_id is not None:
        query["_id"] = {"$ne": exclude_block_id}
    return await blocks.find_one(query)


def _blocks_overlap(a: dict, b: dict) -> bool:
    if a.get("all_day") or b.get("all_day"):
        return False
    a_start = ensure_aware(a["start_time"])
    a_end = ensure_aware(a["end_time"])
    b_start = ensure_aware(b["start_time"])
    b_end = ensure_aware(b["end_time"])
    return a_start < b_end and a_end > b_start


def _is_reschedulable(block: dict) -> bool:
    return block.get("source") != "calendar_sync"


def _priority_rank(priority: str | None) -> int:
    return {"High": 3, "Medium": 2, "Low": 1}.get(priority or "Medium", 2)


def _pick_block_to_move(block_a: dict, block_b: dict) -> dict | None:
    a_movable = _is_reschedulable(block_a)
    b_movable = _is_reschedulable(block_b)
    if a_movable and not b_movable:
        return block_a
    if b_movable and not a_movable:
        return block_b
    if a_movable and b_movable:
        rank_a = _priority_rank(block_a.get("priority"))
        rank_b = _priority_rank(block_b.get("priority"))
        if rank_a != rank_b:
            return block_a if rank_a < rank_b else block_b
        b_start = ensure_aware(block_b["start_time"])
        a_start = ensure_aware(block_a["start_time"])
        return block_b if b_start >= a_start else block_a
    return None


async def _find_slot_on_day(
    *,
    user_id: ObjectId,
    day_start: datetime,
    day_end: datetime,
    duration: timedelta,
    not_before: datetime,
    exclude_block_id: ObjectId | None = None,
) -> tuple[datetime, datetime] | None:
    step = timedelta(minutes=15)
    cursor = max(not_before, day_start)
    while cursor + duration <= day_end:
        candidate_end = cursor + duration
        overlap = await _find_overlap(
            user_id,
            cursor,
            candidate_end,
            exclude_block_id=exclude_block_id,
        )
        if overlap is None:
            return cursor, candidate_end
        cursor = max(cursor + step, ensure_aware(overlap["end_time"], assume_tz=cursor.tzinfo))
    return None


async def update_schedule_block(
    user_doc: dict,
    block_id: ObjectId,
    *,
    title: str | None = None,
    priority: str | None = None,
    start_time: datetime | None = None,
    end_time: datetime | None = None,
) -> dict:
    blocks = mongo.collection("schedule_blocks")
    block = await blocks.find_one({"_id": block_id, "user_id": user_doc["_id"]})
    if block is None:
        raise ValueError("Schedule block not found")

    new_title = title if title is not None else block.get("title")
    new_priority = priority if priority is not None else block.get("priority")
    new_start = start_time if start_time is not None else block["start_time"]
    new_end = end_time if end_time is not None else block["end_time"]

    if new_end <= new_start:
        raise ValueError("end_time must be after start_time")

    if not block.get("all_day"):
        overlap = await _find_overlap(
            user_doc["_id"],
            new_start,
            new_end,
            exclude_block_id=block_id,
        )
        if overlap is not None:
            raise ValueError("The selected time still conflicts with another activity")

    update_fields: dict = {}
    if title is not None:
        update_fields["title"] = new_title
    if priority is not None:
        update_fields["priority"] = new_priority
    if start_time is not None or end_time is not None:
        update_fields["start_time"] = new_start
        update_fields["end_time"] = new_end
        if block.get("source") != "calendar_sync":
            update_fields["source"] = "manual"

    if update_fields:
        await blocks.update_one({"_id": block_id}, {"$set": update_fields})

    task_id = block.get("task_id")
    if task_id is not None:
        task_updates: dict = {}
        if title is not None:
            task_updates["title"] = new_title
        if priority is not None:
            task_updates["priority"] = new_priority
        if start_time is not None or end_time is not None:
            duration_minutes = int((new_end - new_start).total_seconds() // 60)
            task_updates["deadline"] = new_start
            task_updates["estimated_minutes"] = max(15, duration_minutes)
        if task_updates:
            await mongo.collection("tasks").update_one(
                {"_id": task_id, "user_id": user_doc["_id"]},
                {"$set": task_updates},
            )

    updated = await blocks.find_one({"_id": block_id})
    return updated


async def delete_schedule_block(user_doc: dict, block_id: ObjectId) -> None:
    blocks = mongo.collection("schedule_blocks")
    block = await blocks.find_one({"_id": block_id, "user_id": user_doc["_id"]})
    if block is None:
        raise ValueError("Schedule block not found")

    task_id = block.get("task_id")
    await blocks.delete_one({"_id": block_id})

    if task_id is not None:
        await mongo.collection("tasks").delete_one({"_id": task_id, "user_id": user_doc["_id"]})


async def reschedule_block(
    user_doc: dict,
    block_id: ObjectId,
    start_time: datetime,
    end_time: datetime,
) -> dict:
    if end_time <= start_time:
        raise ValueError("end_time must be after start_time")

    blocks = mongo.collection("schedule_blocks")
    block = await blocks.find_one({"_id": block_id, "user_id": user_doc["_id"]})
    if block is None:
        raise ValueError("Schedule block not found")

    overlap = await _find_overlap(
        user_doc["_id"],
        start_time,
        end_time,
        exclude_block_id=block_id,
    )
    if overlap is not None:
        raise ValueError("The selected time still conflicts with another activity")

    await blocks.update_one(
        {"_id": block_id},
        {"$set": {"start_time": start_time, "end_time": end_time, "source": "manual"}},
    )

    task_id = block.get("task_id")
    if task_id is not None:
        tasks = mongo.collection("tasks")
        duration_minutes = int((end_time - start_time).total_seconds() // 60)
        await tasks.update_one(
            {"_id": task_id, "user_id": user_doc["_id"]},
            {
                "$set": {
                    "deadline": start_time,
                    "estimated_minutes": max(15, duration_minutes),
                }
            },
        )

    updated = await blocks.find_one({"_id": block_id})
    return updated


async def auto_resolve_day_conflicts(
    user_doc: dict,
    *,
    year: int,
    month: int,
    day: int,
    priority_block_ids: list[str] | None = None,
) -> tuple[list[dict], list[str]]:
    timezone = user_doc.get("timezone", "UTC")
    zone = ZoneInfo(timezone)
    day_start = datetime(year, month, day, tzinfo=zone)
    day_end = day_start + timedelta(days=1)

    blocks = mongo.collection("schedule_blocks")
    cursor = blocks.find(
        {
            "user_id": user_doc["_id"],
            "start_time": {"$gte": day_start, "$lt": day_end},
            "all_day": {"$ne": True},
        }
    ).sort("start_time", 1)

    timed_blocks = [item async for item in cursor]
    priority_ids = {ObjectId(block_id) for block_id in (priority_block_ids or []) if ObjectId.is_valid(block_id)}

    moved: list[dict] = []
    unresolved: list[str] = []
    max_passes = len(timed_blocks) * 2 or 1

    for _ in range(max_passes):
        progress = False
        for i, block_a in enumerate(timed_blocks):
            for j in range(i + 1, len(timed_blocks)):
                block_b = timed_blocks[j]
                if not _blocks_overlap(block_a, block_b):
                    continue

                if block_a["_id"] in priority_ids and block_b["_id"] not in priority_ids:
                    to_move = block_b if _is_reschedulable(block_b) else None
                elif block_b["_id"] in priority_ids and block_a["_id"] not in priority_ids:
                    to_move = block_a if _is_reschedulable(block_a) else None
                else:
                    to_move = _pick_block_to_move(block_a, block_b)

                if to_move is None:
                    title_a = block_a.get("title") or block_a.get("type") or "Event"
                    title_b = block_b.get("title") or block_b.get("type") or "Event"
                    note = f"{title_a} overlaps with {title_b}"
                    if note not in unresolved:
                        unresolved.append(note)
                    continue

                duration = ensure_aware(to_move["end_time"]) - ensure_aware(to_move["start_time"])
                anchor_end = max(
                    ensure_aware(block_a["end_time"]),
                    ensure_aware(block_b["end_time"]),
                )
                slot = await _find_slot_on_day(
                    user_id=user_doc["_id"],
                    day_start=day_start,
                    day_end=day_end,
                    duration=duration,
                    not_before=anchor_end,
                    exclude_block_id=to_move["_id"],
                )
                if slot is None:
                    title = to_move.get("title") or to_move.get("type") or "Event"
                    note = f"No open slot today for {title}"
                    if note not in unresolved:
                        unresolved.append(note)
                    continue

                new_start, new_end = slot
                await blocks.update_one(
                    {"_id": to_move["_id"]},
                    {"$set": {"start_time": new_start, "end_time": new_end, "source": "manual"}},
                )
                task_id = to_move.get("task_id")
                if task_id is not None:
                    duration_minutes = int(duration.total_seconds() // 60)
                    await mongo.collection("tasks").update_one(
                        {"_id": task_id, "user_id": user_doc["_id"]},
                        {
                            "$set": {
                                "deadline": new_start,
                                "estimated_minutes": max(15, duration_minutes),
                            }
                        },
                    )

                updated = await blocks.find_one({"_id": to_move["_id"]})
                if updated is not None:
                    moved.append(updated)
                    to_move["start_time"] = new_start
                    to_move["end_time"] = new_end
                    progress = True
                    break
            if progress:
                break
        if not progress:
            break

    return moved, unresolved


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
        cursor = max(cursor + step, ensure_aware(overlap["end_time"], assume_tz=cursor.tzinfo))
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
    timezone_name = user_doc.get("timezone", "UTC")
    zone = ZoneInfo(timezone_name)
    deadline = ensure_aware(deadline, assume_tz=zone)
    starts_not_before = ensure_aware(starts_not_before, assume_tz=zone)
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
    zone = ZoneInfo(user_doc.get("timezone", "UTC"))
    start_time = ensure_aware(task_doc["deadline"], assume_tz=zone)
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
    zone = ZoneInfo(timezone)
    now_local = datetime.now(zone)
    deadline = ensure_aware(task_doc["deadline"], assume_tz=zone)
    earliest_start = ensure_aware(starts_not_before, assume_tz=zone) if starts_not_before else now_local
    earliest = max(now_local, earliest_start)
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

        deadline = task_doc.get("deadline")
        if deadline is None or ensure_aware(deadline, assume_tz=ZoneInfo(timezone)) <= now_local:
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
