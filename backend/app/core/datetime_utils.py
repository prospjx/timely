from __future__ import annotations

from datetime import date, datetime, timezone
from zoneinfo import ZoneInfo


def ensure_aware(value: datetime, *, assume_tz: ZoneInfo | None = None) -> datetime:
    """Treat naive datetimes from MongoDB as UTC, then align to assume_tz if given."""
    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    if assume_tz is not None:
        return value.astimezone(assume_tz)
    return value


def local_date_key(value: date | datetime) -> str:
    if isinstance(value, datetime):
        return value.date().isoformat()
    return value.isoformat()


def start_of_local_day(value: date | datetime, timezone_name: str) -> datetime:
    zone = ZoneInfo(timezone_name)
    if isinstance(value, datetime):
        local = ensure_aware(value, assume_tz=zone)
        day = local.date()
    else:
        day = value
    return datetime.combine(day, datetime.min.time(), tzinfo=zone)
