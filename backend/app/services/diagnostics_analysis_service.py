from __future__ import annotations

from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo


def local_day_bounds(target_date: date, timezone_name: str) -> tuple[datetime, datetime]:
    tz = ZoneInfo(timezone_name)
    day_start = datetime.combine(target_date, datetime.min.time(), tzinfo=tz)
    day_end = day_start + timedelta(days=1)
    return day_start, day_end


def summarize_day(*, user_id: str, target_date: date, entries: list[dict]) -> dict:
    total = len(entries)
    completion = 0
    snoozes = 0
    distractions = 0
    deep_work = 0

    for entry in entries:
        action_id = str(entry.get("action_id", "")).lower()
        if entry.get("is_completion") or action_id == "task_due":
            completion += 1
        if entry.get("is_snooze") or action_id == "snooze":
            snoozes += 1
        if entry.get("is_distraction") or action_id == "scrolling":
            distractions += 1
        if action_id == "task_due":
            deep_work += 1

    distraction_ratio = (distractions / total) if total else 0.0

    base_score = 75
    score = base_score + (completion * 4) + (deep_work * 2) - (distractions * 6) - (snoozes * 3)
    score = max(0, min(100, score))

    if total == 0:
        summary = "No interaction data today yet. Start by responding to activity prompts."
    else:
        summary = (
            f"{completion} focused completions, {distractions} distraction signals, "
            f"and {snoozes} snoozes recorded from {total} check-ins."
        )

    return {
        "user_id": user_id,
        "local_date": target_date,
        "total_interactions": total,
        "completion_count": completion,
        "snooze_count": snoozes,
        "distraction_count": distractions,
        "deep_work_checkins": deep_work,
        "distraction_ratio": round(distraction_ratio, 3),
        "focus_score": score,
        "summary": summary,
    }
