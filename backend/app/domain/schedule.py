from __future__ import annotations

from dataclasses import dataclass, replace
from datetime import UTC, date, datetime, time, timedelta
from enum import StrEnum
from zoneinfo import ZoneInfo

from app.domain.errors import ConflictError, NotFoundError, ValidationError

ROOM_TIMEZONE = "Asia/Almaty"
OPENING_HOUR = 9
SLOTS_PER_DAY = 13
SLOT_LENGTH = timedelta(hours=1)
DEFAULT_WEEKLY_LIMIT = 2
WINDOW_OPENS_HOUR = 21
WINDOW_LENGTH = timedelta(hours=1)
RELEASE_NOTICE = timedelta(minutes=10)


class BookingStatus(StrEnum):
    confirmed = "confirmed"
    released = "released"
    completed = "completed"
    dropped = "dropped"
    no_show = "no_show"


ATTENDANCE_OUTCOMES = frozenset(
    {BookingStatus.completed, BookingStatus.dropped, BookingStatus.no_show}
)


class WindowStatus(StrEnum):
    upcoming = "upcoming"
    open = "open"
    closed = "closed"


class Availability(StrEnum):
    available = "available"
    unavailable = "unavailable"
    own = "own"


@dataclass(frozen=True, slots=True)
class Booking:
    id: str
    subject: str
    start: datetime
    status: BookingStatus

    @property
    def end(self) -> datetime:
        return self.start + SLOT_LENGTH

    def with_status(self, status: BookingStatus) -> Booking:
        return replace(self, status=status)


@dataclass(frozen=True, slots=True)
class Quota:
    booked: int
    limit: int
    default_limit: int

    @property
    def remaining(self) -> int:
        return max(self.limit - self.booked, 0)


@dataclass(frozen=True, slots=True)
class Slot:
    start: datetime
    availability: Availability
    eligible: bool
    booking_id: str | None

    @property
    def id(self) -> str:
        return slot_id(self.start)

    @property
    def end(self) -> datetime:
        return self.start + SLOT_LENGTH


@dataclass(frozen=True, slots=True)
class Day:
    date: date
    slots: tuple[Slot, ...]


@dataclass(frozen=True, slots=True)
class Week:
    monday: date
    window: WindowStatus
    quota: Quota
    days: tuple[Day, ...]
    bookings: tuple[Booking, ...]


class SlotInvalidError(ValidationError):
    code = "slot_invalid"


class SlotInPastError(ConflictError):
    code = "slot_in_past"


class BookingWindowClosedError(ConflictError):
    code = "booking_window_closed"


class SlotTakenError(ConflictError):
    code = "slot_taken"


class QuotaExceededError(ConflictError):
    code = "quota_exceeded"


class BookingNotFoundError(NotFoundError):
    code = "booking_not_found"


class BookingNotConfirmedError(ConflictError):
    code = "booking_not_confirmed"


class ReleaseDeadlineError(ConflictError):
    code = "release_deadline_passed"


class AttendanceTooEarlyError(ConflictError):
    code = "attendance_too_early"


class IdempotencyKeyReusedError(ValidationError):
    code = "idempotency_key_reused"


class WeekInvalidError(ValidationError):
    code = "week_invalid"


# the same text the client derives from a slot start, so ids compare as strings
def slot_id(start: datetime) -> str:
    return start.astimezone(UTC).strftime("%Y-%m-%dT%H:%M:%S.000Z")


def counts_toward_quota(status: BookingStatus) -> bool:
    return status is not BookingStatus.released


class RoomPolicy:
    def __init__(
        self,
        *,
        timezone: str = ROOM_TIMEZONE,
        default_limit: int = DEFAULT_WEEKLY_LIMIT,
    ) -> None:
        self.zone = ZoneInfo(timezone)
        self.default_limit = default_limit

    @property
    def timezone(self) -> str:
        return self.zone.key

    def at(self, day: date, hour: int = 0) -> datetime:
        return datetime.combine(day, time(hour), tzinfo=self.zone)

    def local_date(self, instant: datetime) -> date:
        return instant.astimezone(self.zone).date()

    def monday_of(self, instant: datetime) -> date:
        day = self.local_date(instant)
        return day - timedelta(days=day.weekday())

    def require_monday(self, day: date) -> date:
        if day.weekday() != 0:
            raise WeekInvalidError("week_invalid", "A week starts on a Monday.")
        return day

    def slot_starts(self, day: date) -> list[datetime]:
        return [self.at(day, OPENING_HOUR + index) for index in range(SLOTS_PER_DAY)]

    def week_bounds(self, monday: date) -> tuple[datetime, datetime]:
        return self.at(monday), self.at(monday + timedelta(days=7))

    # booking for a week opens the sunday before it, from 21:00 until 22:00
    def opens_at(self, monday: date) -> datetime:
        return self.at(monday - timedelta(days=1), WINDOW_OPENS_HOUR)

    def window(self, monday: date, now: datetime) -> WindowStatus:
        opens = self.opens_at(monday)
        if now < opens:
            return WindowStatus.upcoming
        if now < opens + WINDOW_LENGTH:
            return WindowStatus.open
        return WindowStatus.closed

    # only an id this policy would itself have issued names a slot
    def parse_slot(self, value: str) -> datetime:
        try:
            parsed = datetime.fromisoformat(value)
        except ValueError as error:
            raise SlotInvalidError("slot_invalid", "No such slot.") from error
        if parsed.tzinfo is None:
            raise SlotInvalidError("slot_invalid", "No such slot.")
        start = parsed.astimezone(self.zone)
        if slot_id(start) != value or start not in self.slot_starts(start.date()):
            raise SlotInvalidError("slot_invalid", "No such slot.")
        return start.astimezone(UTC)

    def quota(
        self,
        bookings: list[Booking],
        subject: str,
        monday: date,
        limit: int,
    ) -> Quota:
        booked = sum(
            1
            for booking in bookings
            if booking.subject == subject
            and self.monday_of(booking.start) == monday
            and counts_toward_quota(booking.status)
        )
        return Quota(
            booked=booked,
            limit=min(max(limit, 0), self.default_limit),
            default_limit=self.default_limit,
        )

    def validate_booking(
        self,
        start: datetime,
        *,
        taken: bool,
        quota: Quota,
        now: datetime,
    ) -> None:
        if start <= now:
            raise SlotInPastError("slot_in_past", "The slot has already started.")
        if self.window(self.monday_of(start), now) is not WindowStatus.open:
            raise BookingWindowClosedError(
                "booking_window_closed",
                "Booking for this week is not open.",
            )
        if taken:
            raise SlotTakenError("slot_taken", "The slot is already booked.")
        if quota.remaining == 0:
            raise QuotaExceededError(
                "quota_exceeded",
                "The weekly booking limit is reached.",
            )

    def release(self, booking: Booking, now: datetime) -> Booking:
        if booking.status is not BookingStatus.confirmed:
            raise BookingNotConfirmedError(
                "booking_not_confirmed",
                "Only a confirmed booking can change.",
            )
        if now > booking.start - RELEASE_NOTICE:
            raise ReleaseDeadlineError(
                "release_deadline_passed",
                "The booking can no longer be released.",
            )
        return booking.with_status(BookingStatus.released)

    # attendance is recorded once the slot has begun, never predicted before it
    def record_attendance(
        self,
        booking: Booking,
        outcome: BookingStatus,
        now: datetime,
    ) -> Booking:
        if outcome not in ATTENDANCE_OUTCOMES:
            raise ValidationError(
                "attendance_invalid",
                "The attendance outcome is not valid.",
            )
        if booking.status is not BookingStatus.confirmed:
            raise BookingNotConfirmedError(
                "booking_not_confirmed",
                "Only a confirmed booking can change.",
            )
        if now < booking.start:
            raise AttendanceTooEarlyError(
                "attendance_too_early",
                "Attendance is recorded after the slot starts.",
            )
        return booking.with_status(outcome)

    def schedule(
        self,
        *,
        monday: date,
        now: datetime,
        subject: str,
        bookings: list[Booking],
        limit: int,
    ) -> Week:
        quota = self.quota(bookings, subject, monday, limit)
        window = self.window(monday, now)
        active = {
            booking.start: booking
            for booking in bookings
            if counts_toward_quota(booking.status)
        }
        days: list[Day] = []
        for offset in range(7):
            day = monday + timedelta(days=offset)
            slots: list[Slot] = []
            for start in self.slot_starts(day):
                holder = active.get(start)
                if holder is None:
                    availability = Availability.available
                elif holder.subject == subject:
                    availability = Availability.own
                else:
                    availability = Availability.unavailable
                slots.append(
                    Slot(
                        start=start.astimezone(UTC),
                        availability=availability,
                        # another student's booking id is never handed out
                        booking_id=holder.id
                        if availability is Availability.own and holder
                        else None,
                        eligible=availability is Availability.available
                        and start > now
                        and window is WindowStatus.open
                        and quota.remaining > 0,
                    )
                )
            days.append(Day(date=day, slots=tuple(slots)))
        return Week(
            monday=monday,
            window=window,
            quota=quota,
            days=tuple(days),
            bookings=tuple(
                booking
                for booking in sorted(bookings, key=lambda item: item.start)
                if booking.subject == subject
                and self.monday_of(booking.start) == monday
            ),
        )
