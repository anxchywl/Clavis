from __future__ import annotations

import sqlite3
import threading
from collections.abc import Iterator
from contextlib import contextmanager
from datetime import UTC, datetime
from pathlib import Path

from app.application.ports import RememberedRequest
from app.domain.schedule import Booking, BookingStatus, SlotTakenError

SCHEMA_VERSION = 1

# the partial unique index is what makes a slot impossible to double book,
# whatever the code above it gets wrong
SCHEMA = """
CREATE TABLE IF NOT EXISTS bookings (
    id TEXT PRIMARY KEY,
    subject TEXT NOT NULL,
    slot_start TEXT NOT NULL,
    status TEXT NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS bookings_one_active_per_slot
    ON bookings (slot_start) WHERE status != 'released';
CREATE INDEX IF NOT EXISTS bookings_by_start ON bookings (slot_start);
CREATE TABLE IF NOT EXISTS booking_requests (
    subject TEXT NOT NULL,
    idempotency_key TEXT NOT NULL,
    slot_start TEXT NOT NULL,
    booking_id TEXT NOT NULL REFERENCES bookings (id),
    created_at TEXT NOT NULL,
    PRIMARY KEY (subject, idempotency_key)
);
CREATE TABLE IF NOT EXISTS weekly_limits (
    subject TEXT PRIMARY KEY,
    weekly_limit INTEGER NOT NULL,
    updated_at TEXT NOT NULL
);
"""


def _text(instant: datetime) -> str:
    # fixed width utc text sorts in time order, so range queries are string ones
    return instant.astimezone(UTC).strftime("%Y-%m-%dT%H:%M:%S+00:00")


def _instant(value: str) -> datetime:
    return datetime.fromisoformat(value).astimezone(UTC)


def _now() -> str:
    return _text(datetime.now(UTC))


class SqliteTransaction:
    def __init__(self, connection: sqlite3.Connection) -> None:
        self._db = connection

    def bookings_between(self, start: datetime, end: datetime) -> list[Booking]:
        rows = self._db.execute(
            "SELECT id, subject, slot_start, status FROM bookings "
            "WHERE slot_start >= ? AND slot_start < ? ORDER BY slot_start",
            (_text(start), _text(end)),
        ).fetchall()
        return [self._booking(row) for row in rows]

    def booking(self, booking_id: str) -> Booking | None:
        row = self._db.execute(
            "SELECT id, subject, slot_start, status FROM bookings WHERE id = ?",
            (booking_id,),
        ).fetchone()
        return None if row is None else self._booking(row)

    def slot_is_taken(self, start: datetime) -> bool:
        row = self._db.execute(
            "SELECT 1 FROM bookings WHERE slot_start = ? AND status != 'released'",
            (_text(start),),
        ).fetchone()
        return row is not None

    def insert(self, booking: Booking) -> None:
        stamp = _now()
        try:
            self._db.execute(
                "INSERT INTO bookings "
                "(id, subject, slot_start, status, created_at, updated_at) "
                "VALUES (?, ?, ?, ?, ?, ?)",
                (
                    booking.id,
                    booking.subject,
                    _text(booking.start),
                    booking.status.value,
                    stamp,
                    stamp,
                ),
            )
        except sqlite3.IntegrityError as error:
            raise SlotTakenError("slot_taken", "The slot is already booked.") from error

    def update_status(self, booking: Booking) -> None:
        self._db.execute(
            "UPDATE bookings SET status = ?, updated_at = ? WHERE id = ?",
            (booking.status.value, _now(), booking.id),
        )

    def remembered(self, subject: str, key: str) -> RememberedRequest | None:
        row = self._db.execute(
            "SELECT slot_start, booking_id FROM booking_requests "
            "WHERE subject = ? AND idempotency_key = ?",
            (subject, key),
        ).fetchone()
        if row is None:
            return None
        return RememberedRequest(slot_start=_instant(row[0]), booking_id=row[1])

    def remember(self, subject: str, key: str, request: RememberedRequest) -> None:
        self._db.execute(
            "INSERT INTO booking_requests "
            "(subject, idempotency_key, slot_start, booking_id, created_at) "
            "VALUES (?, ?, ?, ?, ?)",
            (subject, key, _text(request.slot_start), request.booking_id, _now()),
        )

    def weekly_limit(self, subject: str) -> int | None:
        row = self._db.execute(
            "SELECT weekly_limit FROM weekly_limits WHERE subject = ?",
            (subject,),
        ).fetchone()
        return None if row is None else int(row[0])

    def set_weekly_limit(self, subject: str, limit: int) -> None:
        self._db.execute(
            "INSERT INTO weekly_limits (subject, weekly_limit, updated_at) "
            "VALUES (?, ?, ?) ON CONFLICT (subject) DO UPDATE SET "
            "weekly_limit = excluded.weekly_limit, updated_at = excluded.updated_at",
            (subject, limit, _now()),
        )

    @staticmethod
    def _booking(row: tuple[str, str, str, str]) -> Booking:
        return Booking(
            id=row[0],
            subject=row[1],
            start=_instant(row[2]),
            status=BookingStatus(row[3]),
        )


# one connection, one process, one replica. a second replica needs a database
# both can reach, and this is the class to replace when that day comes
class SqliteBookingStore:
    def __init__(self, path: str) -> None:
        if path != ":memory:":
            Path(path).parent.mkdir(parents=True, exist_ok=True)
        self._db = sqlite3.connect(
            path,
            isolation_level=None,
            check_same_thread=False,
        )
        self._lock = threading.Lock()
        with self._lock:
            self._db.execute("PRAGMA foreign_keys = ON")
            self._db.execute("PRAGMA busy_timeout = 5000")
            if path != ":memory:":
                self._db.execute("PRAGMA journal_mode = WAL")
            self._migrate()

    def _migrate(self) -> None:
        version = int(self._db.execute("PRAGMA user_version").fetchone()[0])
        if version > SCHEMA_VERSION:
            raise RuntimeError("the database was written by a newer service")
        self._db.executescript(SCHEMA)
        # pragmas take no parameters; the value is a module constant
        self._db.execute(f"PRAGMA user_version = {SCHEMA_VERSION}")  # noqa: S608

    @contextmanager
    def write(self) -> Iterator[SqliteTransaction]:
        with self._lock:
            self._db.execute("BEGIN IMMEDIATE")
            try:
                yield SqliteTransaction(self._db)
            except BaseException:
                self._db.execute("ROLLBACK")
                raise
            self._db.execute("COMMIT")

    @contextmanager
    def read(self) -> Iterator[SqliteTransaction]:
        with self._lock:
            self._db.execute("BEGIN")
            try:
                yield SqliteTransaction(self._db)
            finally:
                self._db.execute("ROLLBACK")

    def ping(self) -> None:
        with self._lock:
            self._db.execute("SELECT 1").fetchone()

    def close(self) -> None:
        with self._lock:
            self._db.close()
