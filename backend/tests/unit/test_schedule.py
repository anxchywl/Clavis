from __future__ import annotations

from datetime import UTC, date, datetime, timedelta

import pytest

from app.domain.errors import ValidationError
from app.domain.schedule import (
    AttendanceTooEarlyError,
    Availability,
    Booking,
    BookingNotConfirmedError,
    BookingStatus,
    BookingWindowClosedError,
    QuotaExceededError,
    ReleaseDeadlineError,
    RoomPolicy,
    SlotInPastError,
    SlotInvalidError,
    SlotTakenError,
    WeekInvalidError,
    WindowStatus,
    slot_id,
)
from tests.conftest import WINDOW_OPEN, almaty, slot

policy = RoomPolicy()
MONDAY = date(2026, 9, 21)


def booking(
    day: int = 21,
    hour: int = 10,
    subject: str = "student-a",
    status: BookingStatus = BookingStatus.confirmed,
    booking_id: str = "b-1",
) -> Booking:
    return Booking(
        id=booking_id,
        subject=subject,
        start=almaty(day, hour).astimezone(UTC),
        status=status,
    )


def test_a_week_starts_on_the_local_monday() -> None:
    # 23:30 utc on sunday is already monday in almaty
    assert policy.monday_of(datetime(2026, 9, 20, 19, 30, tzinfo=UTC)) == MONDAY
    assert policy.monday_of(almaty(27, 23)) == MONDAY
    with pytest.raises(WeekInvalidError):
        policy.require_monday(date(2026, 9, 22))


def test_a_day_has_thirteen_hourly_slots_from_nine() -> None:
    starts = policy.slot_starts(MONDAY)
    assert len(starts) == 13
    assert starts[0] == almaty(21, 9)
    assert starts[-1] == almaty(21, 21)


@pytest.mark.parametrize(
    ("now", "status"),
    [
        (almaty(20, 20, 59), WindowStatus.upcoming),
        (almaty(20, 21), WindowStatus.open),
        (almaty(20, 21, 59), WindowStatus.open),
        (almaty(20, 22), WindowStatus.closed),
    ],
)
def test_the_window_opens_at_21_and_closes_at_22_on_sunday(
    now: datetime,
    status: WindowStatus,
) -> None:
    assert policy.window(MONDAY, now) is status


def test_a_slot_id_round_trips_only_when_it_is_a_real_slot() -> None:
    assert policy.parse_slot(slot(21, 9)) == almaty(21, 9)
    for invalid in [
        "not-a-date",
        "2026-09-21T04:00:00",
        "2026-09-21T04:00:00Z",
        "2026-09-21T03:00:00.000Z",
        "2026-09-21T04:30:00.000Z",
        slot_id(almaty(21, 22)),
    ]:
        with pytest.raises(SlotInvalidError):
            policy.parse_slot(invalid)


def test_released_bookings_do_not_count_and_a_limit_is_capped() -> None:
    bookings = [
        booking(hour=9, status=BookingStatus.confirmed),
        booking(hour=10, status=BookingStatus.released),
        booking(hour=11, status=BookingStatus.no_show),
        booking(hour=12, subject="student-b"),
        booking(day=28, hour=9),
    ]
    quota = policy.quota(bookings, "student-a", MONDAY, 5)
    assert (quota.booked, quota.limit, quota.remaining) == (2, 2, 0)
    assert policy.quota([], "student-a", MONDAY, -1).limit == 0


def test_booking_checks_run_in_the_order_the_client_expects() -> None:
    open_quota = policy.quota([], "student-a", MONDAY, 2)
    full_quota = policy.quota([], "student-a", MONDAY, 0)
    future = almaty(22, 10)
    with pytest.raises(SlotInPastError):
        policy.validate_booking(
            almaty(20, 12), taken=False, quota=open_quota, now=WINDOW_OPEN
        )
    with pytest.raises(BookingWindowClosedError):
        policy.validate_booking(
            future, taken=False, quota=open_quota, now=almaty(20, 22)
        )
    with pytest.raises(SlotTakenError):
        policy.validate_booking(future, taken=True, quota=full_quota, now=WINDOW_OPEN)
    with pytest.raises(QuotaExceededError):
        policy.validate_booking(future, taken=False, quota=full_quota, now=WINDOW_OPEN)
    policy.validate_booking(future, taken=False, quota=open_quota, now=WINDOW_OPEN)


def test_release_is_allowed_until_exactly_ten_minutes_before() -> None:
    held = booking(hour=10)
    deadline = held.start - timedelta(minutes=10)
    assert policy.release(held, deadline).status is BookingStatus.released
    with pytest.raises(ReleaseDeadlineError):
        policy.release(held, deadline + timedelta(seconds=1))
    with pytest.raises(BookingNotConfirmedError):
        policy.release(booking(status=BookingStatus.no_show), WINDOW_OPEN)


def test_attendance_is_recorded_only_after_the_slot_starts() -> None:
    held = booking(hour=10)
    with pytest.raises(AttendanceTooEarlyError):
        policy.record_attendance(held, BookingStatus.no_show, almaty(21, 9, 59))
    marked = policy.record_attendance(held, BookingStatus.no_show, almaty(21, 10))
    assert marked.status is BookingStatus.no_show
    with pytest.raises(ValidationError):
        policy.record_attendance(held, BookingStatus.released, almaty(21, 11))
    with pytest.raises(BookingNotConfirmedError):
        policy.record_attendance(marked, BookingStatus.completed, almaty(21, 11))


def test_a_schedule_hides_who_holds_another_students_slot() -> None:
    week = policy.schedule(
        monday=MONDAY,
        now=WINDOW_OPEN,
        subject="student-a",
        bookings=[
            booking(hour=10, booking_id="own"),
            booking(hour=12, subject="student-b", booking_id="theirs"),
            booking(hour=14, status=BookingStatus.released, booking_id="gone"),
        ],
        limit=2,
    )
    slots = {item.start: item for item in week.days[0].slots}
    own = slots[almaty(21, 10)]
    theirs = slots[almaty(21, 12)]
    freed = slots[almaty(21, 14)]
    assert (own.availability, own.booking_id, own.eligible) == (
        Availability.own,
        "own",
        False,
    )
    assert (theirs.availability, theirs.booking_id) == (Availability.unavailable, None)
    assert (freed.availability, freed.eligible) == (Availability.available, True)
    assert [item.id for item in week.bookings] == ["own", "gone"]
    assert week.window is WindowStatus.open
    assert len(week.days) == 7
    assert week.days[6].date == date(2026, 9, 27)


def test_nothing_is_eligible_outside_the_window() -> None:
    week = policy.schedule(
        monday=MONDAY,
        now=almaty(20, 22),
        subject="student-a",
        bookings=[],
        limit=2,
    )
    assert not any(item.eligible for day in week.days for item in day.slots)
