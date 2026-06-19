from __future__ import annotations

from datetime import datetime
from zoneinfo import ZoneInfo

from bson import ObjectId
from fastapi import APIRouter, Depends, HTTPException, status

from app.core.datetime_utils import ensure_aware
from app.db.mongo import mongo
from app.models.common import mongo_to_dict
from app.models.schemas import (
    DeadlineCreateRequest,
    EventCreateRequest,
    ScheduleBlockOut,
    TaskCompleteRequest,
    TaskProcessRequest,
    TaskStatus,
)
from app.routers.deps import get_current_user
from app.services import gemini_service, scheduling_engine


router = APIRouter(prefix="/tasks", tags=["tasks"])


async def _persist_task_and_block(user_doc: dict, task_document: dict) -> dict:
    tasks = mongo.collection("tasks")
    schedule_blocks = mongo.collection("schedule_blocks")

    task_insert = await tasks.insert_one(task_document)
    task_document["_id"] = task_insert.inserted_id

    try:
        block_document = await scheduling_engine.schedule_task(user_doc, task_document)
        block_document["title"] = task_document["title"]
        block_document["priority"] = task_document["priority"]
        zone = ZoneInfo(user_doc.get("timezone", "UTC"))
        block_document["start_time"] = ensure_aware(block_document["start_time"], assume_tz=zone)
        block_document["end_time"] = ensure_aware(block_document["end_time"], assume_tz=zone)
    except ValueError as exc:
        await tasks.update_one(
            {"_id": task_document["_id"]},
            {"$set": {"status": TaskStatus.pending.value}},
        )
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc)) from exc

    block_insert = await schedule_blocks.insert_one(block_document)
    block_document["_id"] = block_insert.inserted_id

    await tasks.update_one(
        {"_id": task_document["_id"]},
        {"$set": {"status": TaskStatus.scheduled.value}},
    )

    return mongo_to_dict(block_document)


@router.post("/events", response_model=ScheduleBlockOut)
async def create_event(payload: EventCreateRequest, user_doc: dict = Depends(get_current_user)):
    if payload.end_time <= payload.start_time:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Event end_time must be after start_time",
        )

    estimated_minutes = int((payload.end_time - payload.start_time).total_seconds() // 60)
    task_document = {
        "user_id": user_doc["_id"],
        "raw_input": payload.title,
        "title": payload.title,
        "priority": payload.priority.value,
        "deadline": payload.start_time,
        "estimated_minutes": max(15, estimated_minutes),
        "fixed_day": True,
        "status": TaskStatus.pending.value,
        "kind": "event",
    }
    return await _persist_task_and_block(user_doc, task_document)


@router.post("/deadlines", response_model=ScheduleBlockOut)
async def create_deadline(payload: DeadlineCreateRequest, user_doc: dict = Depends(get_current_user)):
    timezone = user_doc.get("timezone", "UTC")
    now_local = datetime.now(ZoneInfo(timezone))
    if payload.deadline <= now_local:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Deadline must be in the future",
        )

    task_document = {
        "user_id": user_doc["_id"],
        "raw_input": payload.title,
        "title": payload.title,
        "priority": payload.priority.value,
        "deadline": payload.deadline,
        "estimated_minutes": payload.estimated_minutes,
        "fixed_day": False,
        "status": TaskStatus.pending.value,
        "kind": "deadline",
    }
    return await _persist_task_and_block(user_doc, task_document)


@router.post("/{task_id}/complete")
async def complete_task(task_id: str, payload: TaskCompleteRequest, user_doc: dict = Depends(get_current_user)):
    tasks = mongo.collection("tasks")
    try:
        object_id = ObjectId(task_id)
    except Exception as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Task not found") from exc

    task_doc = await tasks.find_one({"_id": object_id, "user_id": user_doc["_id"]})
    if task_doc is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Task not found")

    update = {"status": TaskStatus.completed.value if payload.completed else TaskStatus.scheduled.value}
    if payload.completed:
        update["completed_at"] = datetime.now(ZoneInfo(user_doc.get("timezone", "UTC")))

    await tasks.update_one({"_id": task_doc["_id"]}, {"$set": update})

    schedule_blocks = mongo.collection("schedule_blocks")
    if payload.completed:
        await schedule_blocks.delete_many({"user_id": user_doc["_id"], "task_id": task_doc["_id"]})
    else:
        existing = await schedule_blocks.find_one({"user_id": user_doc["_id"], "task_id": task_doc["_id"]})
        if existing is None:
            try:
                block_document = await scheduling_engine.schedule_task(user_doc, task_doc)
                block_document["title"] = task_doc["title"]
                block_document["priority"] = task_doc["priority"]
                await schedule_blocks.insert_one(block_document)
            except ValueError:
                pass

    return {"success": True}


@router.post("/process", response_model=ScheduleBlockOut)
async def process_task(payload: TaskProcessRequest, user_doc: dict = Depends(get_current_user)):
    parsed = await gemini_service.parse_task(payload.raw_text, timezone=user_doc.get("timezone", "UTC"))

    task_document = {
        "user_id": user_doc["_id"],
        "raw_input": payload.raw_text,
        "title": parsed.title,
        "priority": parsed.priority.value,
        "deadline": parsed.deadline,
        "estimated_minutes": parsed.estimated_minutes,
        "fixed_day": parsed.fixed_day,
        "status": TaskStatus.pending.value,
    }

    return await _persist_task_and_block(user_doc, task_document)
