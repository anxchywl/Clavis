from __future__ import annotations

from datetime import UTC, datetime


class SystemClock:
    def now(self) -> datetime:
        return datetime.now(UTC)


# development only: config refuses it in production, and it never moves, so
# the sunday booking window can be tried on any day of the week
class FixedClock:
    def __init__(self, instant: datetime) -> None:
        self._instant = instant.astimezone(UTC)

    def now(self) -> datetime:
        return self._instant
