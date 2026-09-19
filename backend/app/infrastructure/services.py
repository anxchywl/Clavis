from __future__ import annotations

from collections.abc import Callable

from app.application.booking_service import BookingService
from app.application.ports import Clock
from app.config import Settings
from app.domain.schedule import RoomPolicy
from app.infrastructure.clock import FixedClock, SystemClock
from app.infrastructure.store import SqliteBookingStore


def create_booking_service(
    settings: Settings,
) -> tuple[BookingService, Callable[[], None]]:
    store = SqliteBookingStore(settings.database_path)
    clock: Clock = (
        FixedClock(settings.development_clock)
        if settings.development_clock is not None
        else SystemClock()
    )
    service = BookingService(store=store, clock=clock, policy=RoomPolicy())
    return service, store.close
