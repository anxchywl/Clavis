from __future__ import annotations

from datetime import UTC, datetime, timedelta
from pathlib import Path

import pytest

from app.domain.schedule import Booking, BookingStatus
from app.infrastructure.store import SqliteBookingStore
from app.infrastructure.store.backup import back_up, main
from tests.conftest import almaty

START = datetime(2026, 9, 21, 3, 0, tzinfo=UTC)


def _database(tmp_path: Path) -> Path:
    path = tmp_path / "data" / "clavis.sqlite3"
    store = SqliteBookingStore(str(path))
    with store.write() as tx:
        tx.insert(
            Booking(
                id="kept",
                subject="student-a",
                start=almaty(21, 10).astimezone(UTC),
                status=BookingStatus.confirmed,
            )
        )
    # left open on purpose: the service keeps writing while a backup runs
    return path


def test_a_backup_is_a_readable_copy_of_the_live_database(tmp_path: Path) -> None:
    database = _database(tmp_path)

    target = back_up(database, tmp_path / "backups", keep=3, now=START)

    assert target.name == "clavis-20260921T030000Z.sqlite3"
    restored = SqliteBookingStore(str(target))
    with restored.read() as tx:
        assert tx.booking("kept") is not None


def test_only_the_newest_backups_are_kept(tmp_path: Path) -> None:
    database = _database(tmp_path)
    backups = tmp_path / "backups"
    for day in range(5):
        back_up(database, backups, keep=3, now=START + timedelta(days=day))

    names = sorted(path.name for path in backups.iterdir())
    assert names == [
        "clavis-20260923T030000Z.sqlite3",
        "clavis-20260924T030000Z.sqlite3",
        "clavis-20260925T030000Z.sqlite3",
    ]


def test_the_command_backs_up_and_refuses_to_keep_nothing(
    tmp_path: Path,
    capsys: pytest.CaptureFixture[str],
) -> None:
    database = _database(tmp_path)
    backups = tmp_path / "backups"

    main(["--database", str(database), "--directory", str(backups), "--keep", "2"])

    assert "backup written: clavis-" in capsys.readouterr().out
    assert len(list(backups.iterdir())) == 1
    with pytest.raises(SystemExit):
        main(["--database", str(database), "--keep", "0"])


def test_a_missing_database_is_an_error_not_an_empty_backup(tmp_path: Path) -> None:
    with pytest.raises(Exception, match="unable to open"):
        back_up(tmp_path / "absent.sqlite3", tmp_path / "backups", keep=1, now=START)
    assert not list((tmp_path / "backups").glob("*.sqlite3"))
