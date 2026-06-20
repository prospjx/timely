from __future__ import annotations

from datetime import date, datetime, timezone
from zoneinfo import ZoneInfo

from app.core.datetime_utils import ensure_aware, local_date_key, start_of_local_day


def test_ensure_aware_treats_naive_as_utc() -> None:
    naive = datetime(2026, 6, 19, 12, 0, 0)
    aware = ensure_aware(naive)
    assert aware.tzinfo == timezone.utc
    assert aware.hour == 12


def test_ensure_aware_converts_to_requested_timezone() -> None:
    naive = datetime(2026, 6, 19, 17, 0, 0)
    eastern = ensure_aware(naive, assume_tz=ZoneInfo("America/New_York"))
    assert eastern.tzinfo == ZoneInfo("America/New_York")


def test_local_date_key_from_date_and_datetime() -> None:
    assert local_date_key(date(2026, 6, 19)) == "2026-06-19"
    assert local_date_key(datetime(2026, 6, 19, 23, 59, tzinfo=timezone.utc)) == "2026-06-19"


def test_start_of_local_day() -> None:
    start = start_of_local_day(date(2026, 6, 19), "America/New_York")
    assert start.tzinfo == ZoneInfo("America/New_York")
    assert start.hour == 0 and start.minute == 0
