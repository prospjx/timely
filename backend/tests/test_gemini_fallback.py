from __future__ import annotations

import pytest

from app.models.schemas import TaskPriority
from app.services.gemini_service import _fallback_parse_task, _extract_title


def test_extract_title_from_structured_quick_add() -> None:
    raw = "Finish lab report. Priority High (A). Schedule mode Deadline. Deadline 2026-06-25 17:00."
    assert _extract_title(raw) == "Finish lab report"


@pytest.mark.asyncio
async def test_parse_task_uses_fallback_without_api_key(monkeypatch: pytest.MonkeyPatch) -> None:
    from app.services import gemini_service

    monkeypatch.setattr(gemini_service, "_get_model", lambda: None)
    parsed = await gemini_service.parse_task(
        "Study for exam tomorrow high priority 2 hours",
        timezone="America/New_York",
    )
    assert parsed.title
    assert parsed.priority == TaskPriority.high
    assert parsed.estimated_minutes == 120


def test_fallback_parse_task_event_mode() -> None:
    parsed = _fallback_parse_task(
        "Team standup. Priority Medium (B). Schedule mode Event. Event date 2026-06-25 09:00. "
        "Keep this on that day only.",
        timezone="America/New_York",
    )
    assert parsed.fixed_day is True
    assert parsed.title == "Team standup"
