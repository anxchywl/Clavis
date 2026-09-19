from __future__ import annotations

from datetime import date
from typing import Annotated

from fastapi import APIRouter, Path, Request

from app.api.errors import request_id_of
from app.api.schemas import (
    AttendanceRequest,
    WeeklyLimitRequest,
    operator_booking_payload,
)
from app.application.booking_service import BookingService
from app.dependencies import OperatorIdentity
from app.domain.schedule import BookingStatus

router = APIRouter(prefix="/api/v1/operator", tags=["operator"])

BookingId = Annotated[str, Path(min_length=1, max_length=64)]
Subject = Annotated[str, Path(min_length=1, max_length=255)]


def _service(request: Request) -> BookingService:
    service: BookingService = request.app.state.booking_service
    return service


@router.get("/weeks/{monday}/bookings")
async def week_bookings(
    request: Request,
    identity: OperatorIdentity,
    monday: date,
) -> dict[str, object]:
    bookings = await _service(request).bookings_for_operator(monday=monday)
    return {
        "data": [operator_booking_payload(booking) for booking in bookings],
        "meta": {"request_id": request_id_of(request)},
    }


@router.post("/bookings/{booking_id}/attendance")
async def attendance(
    request: Request,
    identity: OperatorIdentity,
    booking_id: BookingId,
    body: AttendanceRequest,
) -> dict[str, object]:
    booking = await _service(request).record_attendance(
        booking_id=booking_id,
        outcome=BookingStatus(body.status),
    )
    return {
        "data": operator_booking_payload(booking),
        "meta": {"request_id": request_id_of(request)},
    }


# a penalty lowers the limit, and only an operator can set it back
@router.put("/students/{subject}/weekly-limit")
async def weekly_limit(
    request: Request,
    identity: OperatorIdentity,
    subject: Subject,
    body: WeeklyLimitRequest,
) -> dict[str, object]:
    limit = await _service(request).set_weekly_limit(subject=subject, limit=body.limit)
    return {
        "data": {"subject": subject, "limit": limit},
        "meta": {"request_id": request_id_of(request)},
    }
