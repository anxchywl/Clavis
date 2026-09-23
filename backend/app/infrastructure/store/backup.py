from __future__ import annotations

import argparse
import sqlite3
from datetime import UTC, datetime
from pathlib import Path

PREFIX = "clavis-"
SUFFIX = ".sqlite3"


# sqlite's online backup copies a consistent snapshot while the service keeps
# writing, which a plain file copy of a wal database does not guarantee
def back_up(database: Path, directory: Path, *, keep: int, now: datetime) -> Path:
    directory.mkdir(parents=True, exist_ok=True)
    target = directory / f"{PREFIX}{now.astimezone(UTC):%Y%m%dT%H%M%SZ}{SUFFIX}"
    partial = target.with_suffix(".partial")
    source = sqlite3.connect(f"file:{database}?mode=ro", uri=True)
    copy = sqlite3.connect(partial)
    try:
        source.backup(copy)
        result = copy.execute("PRAGMA integrity_check").fetchone()[0]
    finally:
        copy.close()
        source.close()
    if result != "ok":
        partial.unlink()
        raise RuntimeError("the backup failed its integrity check")
    # only a complete, checked copy ever carries the final name
    partial.rename(target)
    for old in sorted(directory.glob(f"{PREFIX}*{SUFFIX}"))[:-keep]:
        old.unlink()
    return target


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description="Back up the booking database.")
    parser.add_argument("--database", type=Path, default=Path("/data/clavis.sqlite3"))
    parser.add_argument("--directory", type=Path, default=Path("/backups"))
    parser.add_argument("--keep", type=int, default=14)
    arguments = parser.parse_args(argv)
    if arguments.keep < 1:
        parser.error("--keep must be at least 1")
    target = back_up(
        arguments.database,
        arguments.directory,
        keep=arguments.keep,
        now=datetime.now(UTC),
    )
    print(f"backup written: {target.name}")


if __name__ == "__main__":  # pragma: no cover
    main()
