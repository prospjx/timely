from __future__ import annotations

from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Depends

from app.core.datetime_utils import ensure_aware, local_date_key
from app.db.mongo import mongo
from app.models.common import mongo_to_dict
from app.models.schemas import (
    DailyTimeAnalysisOut,
    DiagnosticsLogOut,
    DiagnosticsLogRequest,
    NotificationInteractionOut,
    NotificationInteractionRequest,
    ReflectionsMetricsOut,
)
from app.routers.deps import get_current_user
from app.services.diagnostics_analysis_service import local_day_bounds, summarize_day
from app.services.notification_service import send_activity_probe


router = APIRouter(prefix="/diagnostics", tags=["diagnostics"])


@router.post("/log", response_model=DiagnosticsLogOut)
async def log_diagnostic(payload: DiagnosticsLogRequest, user_doc: dict = Depends(get_current_user)):
    timestamp = datetime.now(ZoneInfo(user_doc.get("timezone", "UTC")))
    document = {
        "user_id": user_doc["_id"],
        "timestamp": timestamp,
        "interaction_type": payload.interaction_type,
        "energy_score": payload.energy_score,
    }

    result = await mongo.collection("diagnostic_logs").insert_one(document)
    document["_id"] = result.inserted_id
    return mongo_to_dict(document)


@router.post("/interaction/log", response_model=NotificationInteractionOut)
async def log_interaction(payload: NotificationInteractionRequest, user_doc: dict = Depends(get_current_user)):
    tz_name = user_doc.get("timezone", "UTC")
    now_local = datetime.now(ZoneInfo(tz_name))
    action_id = payload.action_id.lower()
    is_snooze = action_id == "snooze"
    is_completion = action_id == "task_due"
    is_distraction = action_id == "scrolling"

    document = {
        "user_id": user_doc["_id"],
        "timestamp": now_local,
        "local_date": local_date_key(now_local),
        "action_id": action_id,
        "action_label": payload.action_label,
        "prompt_text": payload.prompt_text,
        "source": payload.source,
        "scheduled_task_label": payload.scheduled_task_label,
        "is_snooze": is_snooze,
        "is_completion": is_completion,
        "is_distraction": is_distraction,
        "metadata": payload.metadata,
    }

    result = await mongo.collection("notification_interactions").insert_one(document)
    document["_id"] = result.inserted_id
    return mongo_to_dict(document)


@router.get("/analysis/today", response_model=DailyTimeAnalysisOut)
async def get_today_analysis(user_doc: dict = Depends(get_current_user)):
    tz_name = user_doc.get("timezone", "UTC")
    today_local = datetime.now(ZoneInfo(tz_name)).date()
    return await _build_and_store_daily_analysis(user_doc=user_doc, target_date=today_local)


@router.get("/analysis/date", response_model=DailyTimeAnalysisOut)
async def get_date_analysis(target_date: date, user_doc: dict = Depends(get_current_user)):
    return await _build_and_store_daily_analysis(user_doc=user_doc, target_date=target_date)


@router.post("/analysis/run-eod", response_model=DailyTimeAnalysisOut)
async def run_end_of_day_analysis(user_doc: dict = Depends(get_current_user)):
    tz_name = user_doc.get("timezone", "UTC")
    yesterday_local = datetime.now(ZoneInfo(tz_name)).date() - timedelta(days=1)
    return await _build_and_store_daily_analysis(user_doc=user_doc, target_date=yesterday_local)


@router.post("/prompt/push")
async def push_activity_prompt(user_doc: dict = Depends(get_current_user)):
    tz_name = user_doc.get("timezone", "UTC")
    now_local = datetime.now(ZoneInfo(tz_name))
    day_start, day_end = local_day_bounds(now_local.date(), tz_name)
    schedule = mongo.collection("schedule_blocks")

    nearest = await schedule.find_one(
        {
            "user_id": user_doc["_id"],
            "start_time": {"$gte": day_start, "$lt": day_end},
        },
        sort=[("start_time", 1)],
    )
    task_label = "Studying for an exam"
    if nearest and nearest.get("title"):
        task_label = str(nearest["title"])

    pushed = await send_activity_probe(
        user_doc,
        prompt_text="What are you doing",
        scheduled_task_label=task_label,
    )
    return {"success": pushed, "scheduled_task_label": task_label}


@router.get("/reflections/today", response_model=ReflectionsMetricsOut)
async def get_today_reflections(user_doc: dict = Depends(get_current_user)):
    tz_name = user_doc.get("timezone", "UTC")
    zone = ZoneInfo(tz_name)
    today_local = datetime.now(zone).date()
    day_start, day_end = local_day_bounds(today_local, tz_name)

    wake_time = (user_doc.get("preferences") or {}).get("wake_time", "07:00")
    sleep_time = (user_doc.get("preferences") or {}).get("sleep_time", "22:30")
    awake_start, awake_end = _wake_sleep_window(day_start, wake_time, sleep_time)

    available_minutes = int((awake_end - awake_start).total_seconds() // 60)

    schedule_cursor = mongo.collection("schedule_blocks").find(
        {
            "user_id": user_doc["_id"],
            "start_time": {"$lt": awake_end},
            "end_time": {"$gt": awake_start},
        }
    )

    scheduled_minutes = 0
    async for block in schedule_cursor:
        block_start = max(ensure_aware(block.get("start_time")), awake_start)
        block_end = min(ensure_aware(block.get("end_time")), awake_end)
        if block_end > block_start:
            scheduled_minutes += int((block_end - block_start).total_seconds() // 60)

    free_minutes = max(0, available_minutes - scheduled_minutes)
    rest_rate = round((free_minutes / available_minutes), 3) if available_minutes else 0.0

    tasks_cursor = mongo.collection("tasks").find(
        {
            "user_id": user_doc["_id"],
            "deadline": {"$gte": day_start, "$lt": day_end},
        }
    )

    tasks_due_count = 0
    tasks_completed_before_deadline = 0

    async for task in tasks_cursor:
        tasks_due_count += 1
        deadline = task.get("deadline")
        completed_at = task.get("completed_at")
        status = str(task.get("status", ""))

        completed = status.lower() == "completed"
        deadline_aware = ensure_aware(deadline) if deadline is not None else None
        completed_at_aware = ensure_aware(completed_at) if completed_at is not None else None
        completed_before_deadline = (
            completed
            and completed_at_aware is not None
            and deadline_aware is not None
            and completed_at_aware <= deadline_aware
        )

        if not completed_before_deadline and deadline_aware is not None:
            completion_hint = await mongo.collection("notification_interactions").find_one(
                {
                    "user_id": user_doc["_id"],
                    "action_id": "task_due",
                    "scheduled_task_label": task.get("title"),
                    "timestamp": {"$lte": deadline_aware},
                }
            )
            completed_before_deadline = completion_hint is not None

        if completed_before_deadline:
            tasks_completed_before_deadline += 1

    completion_rate = (
        round(tasks_completed_before_deadline / tasks_due_count, 3)
        if tasks_due_count
        else 0.0
    )

    summary = (
        f"Completed {tasks_completed_before_deadline} of {tasks_due_count} due tasks before deadline. "
        f"Free time today: {free_minutes} of {available_minutes} minutes."
    )

    return {
        "user_id": str(user_doc["_id"]),
        "local_date": today_local,
        "tasks_due_count": tasks_due_count,
        "tasks_completed_before_deadline": tasks_completed_before_deadline,
        "completion_rate_before_deadline": completion_rate,
        "available_minutes": available_minutes,
        "scheduled_minutes": scheduled_minutes,
        "free_minutes": free_minutes,
        "rest_rate": rest_rate,
        "summary": summary,
    }


def _wake_sleep_window(day_start: datetime, wake_time: str, sleep_time: str) -> tuple[datetime, datetime]:
    wake_hour, wake_minute = [int(x) for x in wake_time.split(":")]
    sleep_hour, sleep_minute = [int(x) for x in sleep_time.split(":")]

    awake_start = day_start.replace(hour=wake_hour, minute=wake_minute, second=0, microsecond=0)
    awake_end = day_start.replace(hour=sleep_hour, minute=sleep_minute, second=0, microsecond=0)
    if awake_end <= awake_start:
        awake_end = awake_end + timedelta(days=1)
    return awake_start, awake_end


async def _build_and_store_daily_analysis(*, user_doc: dict, target_date: date) -> dict:
    tz_name = user_doc.get("timezone", "UTC")
    start, end = local_day_bounds(target_date, tz_name)
    interactions = mongo.collection("notification_interactions")

    cursor = interactions.find(
        {
            "user_id": user_doc["_id"],
            "timestamp": {"$gte": start, "$lt": end},
        },
    )
    entries = [mongo_to_dict(item) async for item in cursor]

    report = summarize_day(user_id=str(user_doc["_id"]), target_date=target_date, entries=entries)
    date_key = local_date_key(target_date)

    await mongo.collection("daily_time_analysis").update_one(
        {"user_id": user_doc["_id"], "local_date": date_key},
        {"$set": {**report, "local_date": date_key}},
        upsert=True,
    )
    return report
