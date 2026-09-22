# Development and verification

This repository was tested with Flutter 3.38.5, Dart 3.10.4, Python 3.12, and `uv` 0.11. The sample mode needs no service or credential.

## Run the demo on sample data

```sh
cd piano_room_feature
flutter pub get
flutter gen-l10n
cd ../piano_room_app
flutter pub get
flutter run -d chrome
```

Standalone access works only in debug mode. Set `ENABLE_DEV_ACCESS=false` to close it in debug. Profile and release builds always show the localized closed screen.

Use `PIANO_LOCALE=en`, `ru`, or `kk` to set the language. Without it, the app uses the device locale and falls back to English.

Use `PIANO_SCENARIO` with one of these values:

`normal`, `offline`, `conflict`, `penalty`, `empty`, `closed`, `upcoming`, `dropped`, `noShow`

Unknown values fail instead of loading a default fixture. The demo runs at a fixed time, and its data resets on restart.

## Run against the backend

Copy `.env.example` to `.env` at the repository root, and set `DEVELOPMENT_AUTH_TOKEN` and `DEVELOPMENT_OPERATOR_AUTH_TOKEN` to two different random values. Set `DEVELOPMENT_CLOCK=2026-09-20T21:15:00+05:00` to try booking outside Sunday evening.

```sh
uv sync --project backend --extra dev
uv run --project backend uvicorn app.main:create_app --factory --app-dir backend --reload --port 8000
```

Then run the app with the same student token:

```sh
cd piano_room_app
flutter run \
  --dart-define=PIANO_BACKEND=remote \
  --dart-define=PIANO_API_BASE_URL=http://127.0.0.1:8000 \
  --dart-define=PIANO_ACCESS_TOKEN=<DEVELOPMENT_AUTH_TOKEN> \
  --dart-define=PIANO_STUDENT_ID=student-a
```

Plain HTTP is accepted only for `localhost`, `127.0.0.1`, `::1`, or `10.0.2.2`, and only in a debug build. The Android emulator reaches this machine at `10.0.2.2`. A missing or malformed value shows the localized misconfiguration screen. It never falls back to sample data.

`docker compose --env-file .env -f docker/docker-compose.yml up --build` runs the same service in a container, with the database on a named volume.

## Settings

The service reads its settings from the environment. `.env.example` lists them with comments. The main rules:

- `APP_ENV` defaults to `production`, which refuses the development adapter, `DEVELOPMENT_CLOCK`, API docs, wildcard CORS, and plain HTTP origins.
- `DATABASE_PATH` points at one SQLite file. In a container it is `/data/clavis.sqlite3` on a volume.
- `/health/live` answers if the process is up. `/health/ready` also checks the database.

## Deploy

`deploy/deploy.sh` runs `deploy/preflight.sh`, builds the image for the current commit, starts it, and waits for `/health/ready` over HTTPS. If any step fails, it restores the previous image. Preflight refuses a dirty tree, development tokens, a development clock, API docs, or a missing issuer or key.

On a host where another project's Caddy owns ports 80 and 443, the service joins that proxy's network and publishes no port. Add a site for `CLAVIS_API_DOMAIN` to that proxy.

The container runs as a non-root user on a read-only root file system. The volume is its only writable path. Back up the SQLite file on the volume. The service is one process with one connection. A second replica needs a shared database first.

## Verify changes

From the repository root:

```sh
./scripts/verify.sh
cd piano_room_app
flutter build web --debug
flutter build apk --debug
```

The script checks the backend with ruff, mypy, bandit, and pytest with a 90 percent coverage floor. It then generates localization files, checks formatting, analyzes all Flutter packages, runs their tests, checks layer boundaries on both sides, and requires at least 85 percent feature line coverage.

Backend tests cover the booking rules, the window edges, quota and penalties, idempotent retries, double booking at the database, release deadlines, attendance, privacy between students, token verification, configuration guards, and error envelopes. Feature tests cover the HTTP client's parsing, error mapping, clock offset, timeouts, and HTTPS rule. They also cover policy boundaries, privacy, conflicts, stale data, lifecycle changes, responsive layouts, large text, light and dark themes, all locales, labels, contrast, and target sizes.

These tests do not replace a physical-device profile run or a manual TalkBack and VoiceOver review.
