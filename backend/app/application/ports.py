from __future__ import annotations

from contextlib import AbstractContextManager
from dataclasses import dataclass
from datetime import datetime
from typing import Protocol

from app.domain.schedule import Booking


@dataclass(frozen=True, slots=True)
class RememberedRequest:
    slot_start: datetime
    booking_id: str


class BookingTransaction(Protocol):
    def bookings_between(self, start: datetime, end: datetime) -> list[Booking]: ...

    def booking(self, booking_id: str) -> Booking | None: ...

    def slot_is_taken(self, start: datetime) -> bool: ...

    def insert(self, booking: Booking) -> None: ...

    def update_status(self, booking: Booking) -> None: ...

    def remembered(self, subject: str, key: str) -> RememberedRequest | None: ...

    def remember(
        self,
        subject: str,
        key: str,
        request: RememberedRequest,
    ) -> None: ...

    def weekly_limit(self, subject: str) -> int | None: ...

    def set_weekly_limit(self, subject: str, limit: int) -> None: ...


class BookingStore(Protocol):
    # a write transaction holds the only writer lock until it ends, so every
    # check made inside it still holds when its insert commits
    def write(self) -> AbstractContextManager[BookingTransaction]: ...

    def read(self) -> AbstractContextManager[BookingTransaction]: ...

    def ping(self) -> None: ...


class Clock(Protocol):
    def now(self) -> datetime: ...
