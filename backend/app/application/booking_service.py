from __future__ import annotations

import asyncio
from dataclasses import dataclass
from datetime import date, datetime
from uuid import uuid4

from app.application.ports import BookingStore, Clock, RememberedRequest
from app.domain.errors import ValidationError
from app.domain.schedule import (
    Booking,
    BookingNotFoundError,
    BookingStatus,
    IdempotencyKeyReusedError,
    RoomPolicy,
    Week,
)


@dataclass(frozen=True, slots=True)
class BookingOutcome:
    booking: Booking
    replayed: bool


# sqlite blocks, so each use case runs on a worker thread and holds its
# transaction for exactly as long as the rules take to check
class BookingService:
    def __init__(self, *, store: BookingStore, clock: Clock, policy: RoomPolicy):
        self._store = store
        self._clock = clock
        self._policy = policy

    @property
    def timezone(self) -> str:
        return self._policy.timezone

    def now(self) -> datetime:
        return self._clock.now()

    async def week(self, *, subject: str, monday: date) -> Week:
        return await asyncio.to_thread(self._week, subject, monday)

    def _week(self, subject: str, monday: date) -> Week:
        self._policy.require_monday(monday)
        start, end = self._policy.week_bounds(monday)
        with self._store.read() as tx:
            bookings = tx.bookings_between(start, end)
            limit = self._limit_of(tx.weekly_limit(subject))
        return self._policy.schedule(
            monday=monday,
            now=self._clock.now(),
            subject=subject,
            bookings=bookings,
            limit=limit,
        )

    async def book(
        self,
        *,
        subject: str,
        slot: str,
        idempotency_key: str,
    ) -> BookingOutcome:
        return await asyncio.to_thread(self._book, subject, slot, idempotency_key)

    def _book(self, subject: str, slot: str, key: str) -> BookingOutcome:
        start = self._policy.parse_slot(slot)
        with self._store.write() as tx:
            previous = tx.remembered(subject, key)
            if previous is not None:
                # a retry is the same request, so a key reused for another
                # slot is a client bug rather than a second booking
                if previous.slot_start != start:
                    raise IdempotencyKeyReusedError(
                        "idempotency_key_reused",
                        "The Idempotency-Key was used for another slot.",
                    )
                booking = tx.booking(previous.booking_id)
                if booking is None:  # pragma: no cover - rows are never deleted
                    raise BookingNotFoundError("booking_not_found", "No such booking.")
                return BookingOutcome(booking=booking, replayed=True)

            monday = self._policy.monday_of(start)
            week_start, week_end = self._policy.week_bounds(monday)
            quota = self._policy.quota(
                tx.bookings_between(week_start, week_end),
                subject,
                monday,
                self._limit_of(tx.weekly_limit(subject)),
            )
            self._policy.validate_booking(
                start,
                taken=tx.slot_is_taken(start),
                quota=quota,
                now=self._clock.now(),
            )
            booking = Booking(
                id=str(uuid4()),
                subject=subject,
                start=start,
                status=BookingStatus.confirmed,
            )
            tx.insert(booking)
            tx.remember(
                subject,
                key,
                RememberedRequest(slot_start=start, booking_id=booking.id),
            )
        return BookingOutcome(booking=booking, replayed=False)

    async def release(self, *, subject: str, booking_id: str) -> Booking:
        return await asyncio.to_thread(self._release, subject, booking_id)

    def _release(self, subject: str, booking_id: str) -> Booking:
        with self._store.write() as tx:
            booking = tx.booking(booking_id)
            # another student's booking is reported as absent, not as forbidden
            if booking is None or booking.subject != subject:
                raise BookingNotFoundError("booking_not_found", "No such booking.")
            if booking.status is BookingStatus.released:
                return booking
            released = self._policy.release(booking, self._clock.now())
            tx.update_status(released)
        return released

    async def bookings_for_operator(self, *, monday: date) -> list[Booking]:
        return await asyncio.to_thread(self._bookings_for_operator, monday)

    def _bookings_for_operator(self, monday: date) -> list[Booking]:
        self._policy.require_monday(monday)
        start, end = self._policy.week_bounds(monday)
        with self._store.read() as tx:
            return sorted(tx.bookings_between(start, end), key=lambda b: b.start)

    async def record_attendance(
        self,
        *,
        booking_id: str,
        outcome: BookingStatus,
    ) -> Booking:
        return await asyncio.to_thread(self._record_attendance, booking_id, outcome)

    def _record_attendance(self, booking_id: str, outcome: BookingStatus) -> Booking:
        with self._store.write() as tx:
            booking = tx.booking(booking_id)
            if booking is None:
                raise BookingNotFoundError("booking_not_found", "No such booking.")
            if booking.status is outcome:
                return booking
            recorded = self._policy.record_attendance(
                booking,
                outcome,
                self._clock.now(),
            )
            tx.update_status(recorded)
        return recorded

    async def set_weekly_limit(self, *, subject: str, limit: int) -> int:
        return await asyncio.to_thread(self._set_weekly_limit, subject, limit)

    def _set_weekly_limit(self, subject: str, limit: int) -> int:
        if not 0 <= limit <= self._policy.default_limit:
            raise ValidationError(
                "weekly_limit_invalid",
                "The weekly limit is out of range.",
            )
        with self._store.write() as tx:
            tx.set_weekly_limit(subject, limit)
        return limit

    async def ready(self) -> None:
        await asyncio.to_thread(self._store.ping)

    def _limit_of(self, stored: int | None) -> int:
        return self._policy.default_limit if stored is None else stored
