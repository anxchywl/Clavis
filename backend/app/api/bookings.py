from __future__ import annotations

from datetime import date
from typing import Annotated

from fastapi import APIRouter, Header, Path, Request, Response

from app.api.errors import request_id_of
from app.api.headers import require_idempotency_key
from app.api.schemas import BookingRequest, booking_payload, instant, week_payload
from app.application.booking_service import BookingService
from app.dependencies import CurrentIdentity

router = APIRouter(prefix="/api/v1", tags=["bookings"])

BookingId = Annotated[str, Path(min_length=1, max_length=64)]


def _service(request: Request) -> BookingService:
    service: BookingService = request.app.state.booking_service
    return service


def _meta(request: Request, service: BookingService) -> dict[str, object]:
    return {
        "request_id": request_id_of(request),
        "server_time": instant(service.now()),
    }


# the client never decides what time it is, it asks
@router.get("/clock")
async def clock(request: Request, identity: CurrentIdentity) -> dict[str, object]:
    service = _service(request)
    return {"data": {"now": instant(service.now())}, "meta": _meta(request, service)}


@router.get("/weeks/{monday}")
async def week(
    request: Request,
    identity: CurrentIdentity,
    monday: date,
) -> dict[str, object]:
    service = _service(request)
    result = await service.week(subject=identity.external_subject, monday=monday)
    return {
        "data": week_payload(result, service.timezone),
        "meta": _meta(request, service),
    }


@router.post("/bookings", status_code=201)
async def book(
    request: Request,
    response: Response,
    identity: CurrentIdentity,
    body: BookingRequest,
    idempotency_key: Annotated[str | None, Header(alias="Idempotency-Key")] = None,
) -> dict[str, object]:
    service = _service(request)
    outcome = await service.book(
        subject=identity.external_subject,
        slot=body.slot_id,
        idempotency_key=require_idempotency_key(idempotency_key),
    )
    if outcome.replayed:
        response.status_code = 200
        response.headers["Idempotent-Replayed"] = "true"
    return {
        "data": booking_payload(outcome.booking),
        "meta": _meta(request, service),
    }


# a post rather than a delete: the booking stays, only its status changes
@router.post("/bookings/{booking_id}/release")
async def release(
    request: Request,
    identity: CurrentIdentity,
    booking_id: BookingId,
) -> dict[str, object]:
    service = _service(request)
    booking = await service.release(
        subject=identity.external_subject,
        booking_id=booking_id,
    )
    return {"data": booking_payload(booking), "meta": _meta(request, service)}
