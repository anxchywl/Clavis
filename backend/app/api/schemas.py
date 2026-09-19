from __future__ import annotations

from datetime import UTC, datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

from app.domain.schedule import Booking, Week, slot_id


class BookingRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    slot_id: str = Field(alias="slotId", min_length=1, max_length=64)


class AttendanceRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    status: Literal["completed", "dropped", "no_show"]


class WeeklyLimitRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    limit: int = Field(ge=0, le=10)


def instant(value: datetime) -> str:
    return value.astimezone(UTC).isoformat().replace("+00:00", "Z")


# the student's own view: no subject, since every booking here is theirs
def booking_payload(booking: Booking) -> dict[str, object]:
    return {
        "id": booking.id,
        "slotId": slot_id(booking.start),
        "start": instant(booking.start),
        "end": instant(booking.end),
        "status": booking.status.value,
    }


def operator_booking_payload(booking: Booking) -> dict[str, object]:
    return {**booking_payload(booking), "subject": booking.subject}


def week_payload(week: Week, timezone: str) -> dict[str, object]:
    return {
        "monday": week.monday.isoformat(),
        "timezone": timezone,
        "window": week.window.value,
        "quota": {
            "booked": week.quota.booked,
            "limit": week.quota.limit,
            "defaultLimit": week.quota.default_limit,
        },
        "days": [
            {
                "date": day.date.isoformat(),
                "slots": [
                    {
                        "id": slot.id,
                        "start": instant(slot.start),
                        "end": instant(slot.end),
                        "availability": slot.availability.value,
                        "eligible": slot.eligible,
                        "bookingId": slot.booking_id,
                    }
                    for slot in day.slots
                ],
            }
            for day in week.days
        ],
        "bookings": [booking_payload(booking) for booking in week.bookings],
    }
