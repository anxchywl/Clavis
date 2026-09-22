# Clavis

A booking app for the NU Piano Room (Block D6, Room 055). Students see the
week's one-hour slots, book up to two a week, and release a slot they cannot
use.

> **Work in progress.** The app and its backend run, and the booking rules are
> enforced on the server. Sign-in still comes from a host that does not exist
> yet, so the standalone app uses development tokens. [Limits](#limits) says
> more.

## Features

- A week at a glance: seven days in one row, with a mark on the days you have
  booked
- Thirteen slots a day from 09:00 to 22:00, with taken slots shown only as
  unavailable
- Booking and releasing from a bottom sheet, each confirmed before it counts
- The weekly limit shown under the week, and swiping between weeks
- Booking for next week opens on Sunday from 21:00 to 22:00, Almaty time
- English, Russian and Kazakh, in light and dark mode
- A backend that commits each booking atomically, replays retries safely and
  decides every rule with server time
- Operator endpoints for attendance and penalties

## Getting started

Flutter 3.38.5, Python 3.12, `uv`, and Docker for the container. The app runs
on iOS, Android and web.

On sample data, with no backend:

```bash
cd piano_room_feature && flutter pub get && flutter gen-l10n
cd ../piano_room_app && flutter pub get && flutter run
```

Add `--dart-define=PIANO_LOCALE=ru` or `kk` to change the language, and
`--dart-define=PIANO_SCENARIO=conflict` to load another sample case.

Against the backend:

```bash
cp .env.example .env    # then set the two development tokens
uv sync --project backend --extra dev
uv run --project backend uvicorn app.main:create_app --factory --app-dir backend --reload --port 8000
```

```bash
cd piano_room_app && flutter run --dart-define=PIANO_BACKEND=remote \
  --dart-define=PIANO_API_BASE_URL=http://127.0.0.1:8000 \
  --dart-define=PIANO_ACCESS_TOKEN=<token> --dart-define=PIANO_STUDENT_ID=student-a
```

```bash
./scripts/verify.sh    # the backend and app checks, tests and coverage floors
```

Settings, sample cases and deployment are in
[docs/INFRASTRUCTURE.md](docs/INFRASTRUCTURE.md).

## Structure

`piano_room_app -> piano_room_feature -> app_ui`

| Package | Holds |
|---|---|
| `piano_room_app` | The development host: theme, locale, and a sample or remote session |
| `piano_room_feature` | The feature itself: domain rules, controller, screen, strings and the HTTP client |
| `app_ui` | The shared design kit, the same one Gradus uses |
| `backend` | The FastAPI service: booking rules, SQLite store, token verification |
| `docker`, `deploy` | Compose files and the preflight and deploy scripts |

## Documentation

| File | Owns |
|---|---|
| [docs/PRODUCT.md](docs/PRODUCT.md) | Booking rules and what the demo leaves out |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Layers and how they depend on each other |
| [docs/API.md](docs/API.md) | Endpoints, wire shapes, error codes and the security contract |
| [docs/INFRASTRUCTURE.md](docs/INFRASTRUCTURE.md) | Toolchain, sample cases, settings, checks and deployment |
| [AGENTS.md](AGENTS.md) | Coding rules for anyone working here |

## Limits

- **No real accounts yet.** The backend verifies tokens from a host, but no
  host issues them, so the standalone app uses development tokens. The access
  list and `@nu.edu.kz` sign-in are not checked.
- **One server process.** Bookings live in one SQLite file. That is enough for
  one room, but a second replica would need a shared database.
- **No operator screen.** Attendance and penalties go through the operator
  endpoints only.
