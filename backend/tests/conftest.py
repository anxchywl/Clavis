from __future__ import annotations

from datetime import UTC, datetime
from zoneinfo import ZoneInfo

ALMATY = ZoneInfo("Asia/Almaty")


def almaty(day: int, hour: int, minute: int = 0) -> datetime:
    return datetime(2026, 9, day, hour, minute, tzinfo=ALMATY)


def slot(day: int, hour: int) -> str:
    return almaty(day, hour).astimezone(UTC).strftime("%Y-%m-%dT%H:%M:%S.000Z")


# sunday 20 september, inside the window that opens the week of the 21st
WINDOW_OPEN = almaty(20, 21, 15)
