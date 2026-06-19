from __future__ import annotations

from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.cron import CronTrigger

from app.core.config import get_settings
from app.db.mongo import mongo
from app.services.brief_service import trigger_brief_for_user
from app.services.diagnostics_analysis_service import local_day_bounds, summarize_day
from app.services.notification_service import send_task_moved_notification
from app.services.scheduling_engine import reshuffle_incomplete_deadlines


scheduler = AsyncIOScheduler()


async def run_daily_briefs() -> None:
    users = mongo.collection("users")
    schedule_collection = mongo.collection("schedule_blocks")
    diagnostics_collection = mongo.collection("diagnostic_logs")

    async for user_doc in users.find({}):
        await trigger_brief_for_user(user_doc, schedule_collection, diagnostics_collection)


async def run_daily_time_analysis() -> None:
    users = mongo.collection("users")
    interactions = mongo.collection("notification_interactions")
    reports = mongo.collection("daily_time_analysis")

    async for user_doc in users.find({}):
        tz_name = user_doc.get("timezone", "UTC")
        local_today = datetime.now(ZoneInfo(tz_name)).date()
        target_date = local_today - timedelta(days=1)
        start, end = local_day_bounds(target_date, tz_name)

        cursor = interactions.find(
            {
                "user_id": user_doc["_id"],
                "timestamp": {"$gte": start, "$lt": end},
            },
        )
        entries = [item async for item in cursor]
        report = summarize_day(user_id=user_doc["_id"], target_date=target_date, entries=entries)

        await reports.update_one(
            {"user_id": user_doc["_id"], "local_date": target_date},
            {"$set": report},
            upsert=True,
        )


async def run_auto_reshuffle() -> None:
    users = mongo.collection("users")

    async for user_doc in users.find({}):
        moved = await reshuffle_incomplete_deadlines(user_doc)
        for item in moved:
            await send_task_moved_notification(
                user_doc,
                task_title=item["title"],
                new_start_time_iso=item["new_start_time"].isoformat(),
            )


def start_scheduler() -> None:
    settings = get_settings()
    if scheduler.running:
        return

    scheduler.add_job(
        run_daily_briefs,
        CronTrigger(hour=settings.brief_cron_hour_utc, minute=0),
        id="daily_briefs",
        replace_existing=True,
    )
    scheduler.add_job(
        run_daily_time_analysis,
        CronTrigger(hour=settings.analysis_cron_hour_utc, minute=settings.analysis_cron_minute_utc),
        id="daily_time_analysis",
        replace_existing=True,
    )
    scheduler.add_job(
        run_auto_reshuffle,
        "interval",
        minutes=15,
        id="auto_reshuffle",
        replace_existing=True,
    )
    scheduler.start()


def stop_scheduler() -> None:
    if scheduler.running:
        scheduler.shutdown(wait=False)
