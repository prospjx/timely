from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, status

from app.db.mongo import mongo
from app.models.common import mongo_to_dict
from app.models.schemas import ScheduleBlockOut, TaskProcessRequest, TaskStatus
from app.routers.deps import get_current_user
from app.services import gemini_service, scheduling_engine


router = APIRouter(prefix="/tasks", tags=["tasks"])


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

    tasks = mongo.collection("tasks")
    task_insert = await tasks.insert_one(task_document)
    task_document["_id"] = task_insert.inserted_id

    try:
        block_document = await scheduling_engine.schedule_task(user_doc, task_document)
        block_document["title"] = task_document["title"]
        block_document["priority"] = task_document["priority"]
    except ValueError as exc:
        await tasks.update_one(
            {"_id": task_document["_id"]},
            {"$set": {"status": TaskStatus.pending.value}},
        )
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc)) from exc

    schedule_blocks = mongo.collection("schedule_blocks")
    block_insert = await schedule_blocks.insert_one(block_document)
    block_document["_id"] = block_insert.inserted_id

    await tasks.update_one(
        {"_id": task_document["_id"]},
        {"$set": {"status": TaskStatus.scheduled.value}},
    )

    return mongo_to_dict(block_document)
