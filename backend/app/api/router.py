from __future__ import annotations

from fastapi import APIRouter

from app.api import bookings, health, operator

router = APIRouter()
router.include_router(health.router)
router.include_router(bookings.router)
router.include_router(operator.router)
