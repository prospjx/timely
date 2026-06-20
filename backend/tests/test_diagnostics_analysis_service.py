from __future__ import annotations

from datetime import date

from app.services.diagnostics_analysis_service import local_day_bounds, summarize_day


def test_local_day_bounds_span_twenty_four_hours() -> None:
    start, end = local_day_bounds(date(2026, 6, 19), "America/New_York")
    assert (end - start).total_seconds() == 86400


def test_summarize_day_empty_entries() -> None:
    report = summarize_day(user_id="user-1", target_date=date(2026, 6, 19), entries=[])
    assert report["total_interactions"] == 0
    assert report["focus_score"] == 75
    assert "No interaction data today yet" in report["summary"]


def test_summarize_day_scores_completions_and_distractions() -> None:
    entries = [
        {"action_id": "task_due", "is_completion": True, "is_snooze": False, "is_distraction": False},
        {"action_id": "scrolling", "is_completion": False, "is_snooze": False, "is_distraction": True},
        {"action_id": "snooze", "is_completion": False, "is_snooze": True, "is_distraction": False},
    ]
    report = summarize_day(user_id="user-1", target_date=date(2026, 6, 19), entries=entries)
    assert report["total_interactions"] == 3
    assert report["completion_count"] == 1
    assert report["distraction_count"] == 1
    assert report["snooze_count"] == 1
    assert report["focus_score"] < 75
