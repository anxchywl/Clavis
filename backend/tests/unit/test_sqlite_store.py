from __future__ import annotations

import sqlite3
from datetime import UTC
from pathlib import Path

import pytest

from app.application.ports import RememberedRequest
from app.domain.schedule import Booking, BookingStatus, SlotTakenError
from app.infrastructure.store import SqliteBookingStore
from tests.conftest import almaty


def _booking(booking_id: str, hour: int = 10) -> Booking:
    return Booking(
        id=booking_id,
        subject="student-a",
        start=almaty(21, hour).astimezone(UTC),
        status=BookingStatus.confirmed,
    )


def test_the_database_refuses_a_second_active_booking_for_a_slot() -> None:
    # the service checks first; this is the guard for when a check is wrong
    store = SqliteBookingStore(":memory:")
    with store.write() as tx:
        tx.insert(_booking("first"))
    with pytest.raises(SlotTakenError), store.write() as tx:
        tx.insert(_booking("second"))
    with store.write() as tx:
        tx.update_status(_booking("first").with_status(BookingStatus.released))
        tx.insert(_booking("second"))
    with store.read() as tx:
        assert tx.slot_is_taken(almaty(21, 10))
        assert [b.id for b in tx.bookings_between(almaty(21, 0), almaty(22, 0))] == [
            "first",
            "second",
        ]


def test_a_failed_transaction_leaves_nothing_behind() -> None:
    store = SqliteBookingStore(":memory:")
    with pytest.raises(RuntimeError), store.write() as tx:
        tx.insert(_booking("first"))
        tx.remember(
            "student-a",
            "request-key-0001",
            RememberedRequest(slot_start=almaty(21, 10), booking_id="first"),
        )
        raise RuntimeError("interrupted before commit")
    with store.read() as tx:
        assert tx.booking("first") is None
        assert tx.remembered("student-a", "request-key-0001") is None


def test_a_weekly_limit_is_stored_and_replaced() -> None:
    store = SqliteBookingStore(":memory:")
    with store.write() as tx:
        assert tx.weekly_limit("student-a") is None
        tx.set_weekly_limit("student-a", 1)
        tx.set_weekly_limit("student-a", 0)
    with store.read() as tx:
        assert tx.weekly_limit("student-a") == 0


def test_a_database_from_a_newer_service_is_not_touched(tmp_path: Path) -> None:
    path = tmp_path / "nested" / "clavis.sqlite3"
    SqliteBookingStore(str(path)).close()
    with sqlite3.connect(path) as connection:
        connection.execute("PRAGMA user_version = 99")
    with pytest.raises(RuntimeError, match="newer service"):
        SqliteBookingStore(str(path))
