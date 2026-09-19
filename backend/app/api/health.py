from __future__ import annotations

from fastapi import APIRouter, Request

from app.api.errors import request_id_of
from app.application.booking_service import BookingService
from app.domain.errors import ServiceUnavailableError

router = APIRouter(tags=["health"])


@router.get("/health/live")
async def live(request: Request) -> dict[str, object]:
    return {
        "data": {"status": "ok"},
        "meta": {"request_id": request_id_of(request)},
    }


# bookings live in the database, so a service that cannot reach it is not ready
@router.get("/health/ready")
async def ready(request: Request) -> dict[str, object]:
    service: BookingService = request.app.state.booking_service
    try:
        await service.ready()
    except Exception as error:
        raise ServiceUnavailableError(
            "database_unavailable",
            "The service is not ready.",
        ) from error
    return {
        "data": {"status": "ready"},
        "meta": {"request_id": request_id_of(request)},
    }
