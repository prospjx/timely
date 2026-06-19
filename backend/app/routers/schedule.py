from __future__ import annotations

import random
from datetime import datetime, timedelta
import re
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from bson import ObjectId
from fastapi import APIRouter, Depends, HTTPException, status

from app.db.mongo import mongo
from app.models.common import mongo_to_dict
from app.models.schemas import (
    CalendarImportRequest,
    CalendarImportResponse,
    ConflictResolveRequest,
    ConflictResolveResponse,
    DeleteResponse,
    ReshuffleResponse,
    ScheduleBlockOut,
    ScheduleBlockUpdateRequest,
)
from app.routers.deps import get_current_user
from app.services import google_calendar_service
from app.services.notification_service import send_task_moved_notification
from app.services.scheduling_engine import (
    auto_resolve_day_conflicts,
    delete_schedule_block,
    reshuffle_incomplete_deadlines,
    update_schedule_block,
)


router = APIRouter(prefix="/schedule", tags=["schedule"])


def _resolve_zone(timezone: str) -> ZoneInfo:
    try:
        return ZoneInfo(timezone)
    except ZoneInfoNotFoundError:
        return ZoneInfo("UTC")


def _clean_title(title: str | None, fallback: str | None) -> str:
    if not title:
        return fallback or "Task"
    cleaned = re.split(r"\.\s*priority\b", title, flags=re.IGNORECASE, maxsplit=1)[0].strip()
    return cleaned or (fallback or "Task")


def _demo_priority_for_type(block_type: str, rng: random.Random) -> str:
    if block_type == "Task":
        return rng.choice(["High", "Medium", "Low"])
    if block_type == "Meeting":
        return "Medium"
    return "Low"


async def _attach_task_titles(blocks: list[dict]) -> list[dict]:
    tasks_collection = mongo.collection("tasks")

    for block in blocks:
        task_id = block.get("task_id")
        if task_id is None:
            block["title"] = _clean_title(block.get("title"), block.get("type"))
            block.setdefault("priority", None)
            continue

        task_doc = await tasks_collection.find_one({"_id": task_id})
        block["title"] = _clean_title(
            block.get("title") or (task_doc or {}).get("title"),
            block.get("type"),
        )
        block["priority"] = (task_doc or {}).get("priority")

    return blocks


def _block_signature(block: dict) -> tuple:
    return (
        str(block.get("user_id")),
        str(block.get("task_id")),
        str(block.get("title")),
        str(block.get("priority")),
        str(block.get("type")),
        block.get("start_time"),
        block.get("end_time"),
    )


def _dedupe_blocks(blocks: list[dict]) -> list[dict]:
    deduped: list[dict] = []
    seen: set[tuple] = set()
    for block in blocks:
        signature = _block_signature(block)
        if signature in seen:
            continue
        seen.add(signature)
        deduped.append(block)
    return deduped


@router.get("/today", response_model=list[ScheduleBlockOut])
async def get_today_schedule(user_doc: dict = Depends(get_current_user)):
    timezone = user_doc.get("timezone", "UTC")
    now = datetime.now(_resolve_zone(timezone))
    start_of_day = now.replace(hour=0, minute=0, second=0, microsecond=0)
    end_of_day = start_of_day + timedelta(days=1)

    cursor = mongo.collection("schedule_blocks").find(
        {
            "user_id": user_doc["_id"],
            "start_time": {"$gte": start_of_day, "$lt": end_of_day},
        }
    ).sort("start_time", 1)

    blocks = [item async for item in cursor]
    enriched = await _attach_task_titles(blocks)
    deduped = _dedupe_blocks(enriched)
    return [mongo_to_dict(item) for item in deduped]


@router.get("/month", response_model=list[ScheduleBlockOut])
async def get_month_schedule(
    year: int,
    month: int,
    user_doc: dict = Depends(get_current_user),
):
    timezone = user_doc.get("timezone", "UTC")
    zone = _resolve_zone(timezone)
    month_start = datetime(year, month, 1, tzinfo=zone)
    next_month = datetime(
        month_start.year + (1 if month_start.month == 12 else 0),
        1 if month_start.month == 12 else month_start.month + 1,
        1,
        tzinfo=zone,
    )

    cursor = mongo.collection("schedule_blocks").find(
        {
            "user_id": user_doc["_id"],
            "start_time": {"$gte": month_start, "$lt": next_month},
        }
    ).sort("start_time", 1)

    blocks = [item async for item in cursor]
    enriched = await _attach_task_titles(blocks)
    deduped = _dedupe_blocks(enriched)
    return [mongo_to_dict(item) for item in deduped]


@router.post("/seed-demo")
async def seed_demo_schedule(
    year: int,
    month: int,
    user_doc: dict = Depends(get_current_user),
):
    timezone = user_doc.get("timezone", "UTC")
    zone = _resolve_zone(timezone)

    month_start = datetime(year, month, 1, tzinfo=zone)
    next_month = datetime(
        month_start.year + (1 if month_start.month == 12 else 0),
        1 if month_start.month == 12 else month_start.month + 1,
        1,
        tzinfo=zone,
    )
    days_in_month = (next_month - timedelta(days=1)).day

    schedule_collection = mongo.collection("schedule_blocks")
    await schedule_collection.delete_many(
        {
            "user_id": user_doc["_id"],
            "source": "demo",
            "start_time": {"$gte": month_start, "$lt": next_month},
        }
    )

    seed = f"{user_doc['_id']}-{year:04d}-{month:02d}"
    rng = random.Random(seed)
    titles = [
        "Security+ Practice Exam",
        "Deep Work: Network Hardening",
        "Review IAM Policies",
        "Threat Modeling Session",
        "Cloud Lab: AWS IAM",
        "Incident Response Drill",
        "Read NIST Notes",
        "Focus Block: CompTIA Review",
    ]

    blocks: list[dict] = []

    # Always include two events on today's local date when this month is current.
    now = datetime.now(zone)
    if now.year == year and now.month == month:
        day = now.day
        blocks.append(
            {
                "user_id": user_doc["_id"],
                "title": "Morning Focus Session",
                "priority": "High",
                "start_time": datetime(year, month, day, 9, 0, tzinfo=zone),
                "end_time": datetime(year, month, day, 10, 0, tzinfo=zone),
                "type": "Task",
                "source": "demo",
            }
        )
        blocks.append(
            {
                "user_id": user_doc["_id"],
                "title": "Afternoon Planning",
                "priority": "Medium",
                "start_time": datetime(year, month, day, 15, 0, tzinfo=zone),
                "end_time": datetime(year, month, day, 16, 0, tzinfo=zone),
                "type": "Meeting",
                "source": "demo",
            }
        )

    for i in range(10):
        day = rng.randint(1, days_in_month)
        start_hour = rng.choice([8, 9, 10, 11, 13, 14, 15, 16, 17])
        duration_hours = rng.choice([1, 1, 2])
        start_time = datetime(year, month, day, start_hour, 0, tzinfo=zone)
        end_time = start_time + timedelta(hours=duration_hours)
        block_type = rng.choice(["Task", "Meeting", "Break"])
        priority = _demo_priority_for_type(block_type, rng)

        blocks.append(
            {
                "user_id": user_doc["_id"],
                "title": titles[rng.randrange(len(titles))],
            "priority": priority,
                "start_time": start_time,
                "end_time": end_time,
                "type": block_type,
                "source": "demo",
            }
        )

    unique_blocks: list[dict] = []
    seen_signatures: set[tuple] = set()
    for block in blocks:
        signature = (
            str(block.get("user_id")),
            str(block.get("title")),
            str(block.get("priority")),
            str(block.get("type")),
            block.get("start_time"),
            block.get("end_time"),
        )
        if signature in seen_signatures:
            continue
        seen_signatures.add(signature)
        unique_blocks.append(block)

    if unique_blocks:
        await schedule_collection.insert_many(unique_blocks)

    return {"success": True, "inserted": len(unique_blocks), "year": year, "month": month}


@router.post("/calendar/import", response_model=CalendarImportResponse)
async def import_calendar_events(payload: CalendarImportRequest, user_doc: dict = Depends(get_current_user)):
    schedule_collection = mongo.collection("schedule_blocks")
    inserted = 0

    for event in payload.events:
        if event.end_time <= event.start_time:
            continue

        conflict = await schedule_collection.find_one(
            {
                "user_id": user_doc["_id"],
                "start_time": {"$lt": event.end_time},
                "end_time": {"$gt": event.start_time},
                "source": "calendar_sync",
                "title": event.title,
            }
        )
        if conflict is not None:
            continue

        await schedule_collection.insert_one(
            {
                "user_id": user_doc["_id"],
                "title": event.title,
                "priority": "Medium",
                "start_time": event.start_time,
                "end_time": event.end_time,
                "type": "Meeting",
                "source": "calendar_sync",
            }
        )
        inserted += 1

    return {"success": True, "imported": inserted}


@router.post("/reshuffle", response_model=ReshuffleResponse)
async def reshuffle_overdue_deadlines(user_doc: dict = Depends(get_current_user)):
    moved = await reshuffle_incomplete_deadlines(user_doc)

    for item in moved:
        await send_task_moved_notification(
            user_doc,
            task_title=item["title"],
            new_start_time_iso=item["new_start_time"].isoformat(),
        )

    return {"success": True, "moved_count": len(moved)}


@router.patch("/blocks/{block_id}", response_model=ScheduleBlockOut)
async def update_schedule_block_endpoint(
    block_id: str,
    payload: ScheduleBlockUpdateRequest,
    user_doc: dict = Depends(get_current_user),
):
    if not any([payload.title, payload.priority, payload.start_time, payload.end_time]):
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="At least one field must be provided",
        )

    try:
        object_id = ObjectId(block_id)
    except Exception as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Schedule block not found") from exc

    blocks = mongo.collection("schedule_blocks")
    block = await blocks.find_one({"_id": object_id, "user_id": user_doc["_id"]})
    if block is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Schedule block not found")

    new_title = payload.title if payload.title is not None else (block.get("title") or "Event")
    new_start = payload.start_time if payload.start_time is not None else block["start_time"]
    new_end = payload.end_time if payload.end_time is not None else block["end_time"]

    if block.get("source") == "calendar_sync":
        google_event_id = block.get("google_event_id")
        if not google_event_id:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="This Google Calendar event cannot be edited because it has no linked event id",
            )
        user_key = str(user_doc.get("firebase_uid") or user_doc.get("_id"))
        try:
            updated_google = await google_calendar_service.update_calendar_event(
                user_key,
                google_event_id,
                title=new_title,
                start_time=new_start,
                end_time=new_end,
                user_timezone=str(user_doc.get("timezone") or "UTC"),
                all_day=bool(block.get("all_day")),
            )
        except Exception as exc:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc

        await blocks.update_one(
            {"_id": object_id},
            {
                "$set": {
                    "title": updated_google.get("summary") or new_title,
                    "start_time": new_start,
                    "end_time": new_end,
                    "google_html_link": updated_google.get("htmlLink") or block.get("google_html_link"),
                }
            },
        )
        updated = await blocks.find_one({"_id": object_id})
    else:
        try:
            updated = await update_schedule_block(
                user_doc,
                object_id,
                title=payload.title,
                priority=payload.priority.value if payload.priority is not None else None,
                start_time=payload.start_time,
                end_time=payload.end_time,
            )
        except ValueError as exc:
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc)) from exc

    enriched = await _attach_task_titles([updated])
    return mongo_to_dict(enriched[0])


@router.delete("/blocks/{block_id}", response_model=DeleteResponse)
async def delete_schedule_block_endpoint(
    block_id: str,
    user_doc: dict = Depends(get_current_user),
):
    try:
        object_id = ObjectId(block_id)
    except Exception as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Schedule block not found") from exc

    blocks = mongo.collection("schedule_blocks")
    block = await blocks.find_one({"_id": object_id, "user_id": user_doc["_id"]})
    if block is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Schedule block not found")

    if block.get("source") == "calendar_sync":
        google_event_id = block.get("google_event_id")
        if not google_event_id:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="This Google Calendar event cannot be deleted because it has no linked event id",
            )
        user_key = str(user_doc.get("firebase_uid") or user_doc.get("_id"))
        try:
            await google_calendar_service.delete_calendar_event(user_key, google_event_id)
        except Exception as exc:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc

    try:
        await delete_schedule_block(user_doc, object_id)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc

    return {"success": True}


@router.post("/resolve-conflicts", response_model=ConflictResolveResponse)
async def resolve_schedule_conflicts(
    payload: ConflictResolveRequest,
    user_doc: dict = Depends(get_current_user),
):
    moved, unresolved = await auto_resolve_day_conflicts(
        user_doc,
        year=payload.year,
        month=payload.month,
        day=payload.day,
        priority_block_ids=payload.priority_block_ids,
    )
    enriched = await _attach_task_titles(moved)
    return {
        "success": True,
        "moved_count": len(moved),
        "moved": [mongo_to_dict(item) for item in enriched],
        "unresolved": unresolved,
    }
