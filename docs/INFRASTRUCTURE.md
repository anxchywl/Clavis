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

## CI and deployment

`CI` runs on every push to `main` and every pull request. It checks the backend (format, lint, types, bandit, tests with a 90 percent floor) and the Flutter packages (format, analyze, tests, 85 percent feature floor). It also builds a debug APK and shellchecks the deploy scripts. It validates both production compose shapes, builds the image, and scans the full history with gitleaks and both lockfiles with osv-scanner. Actions are pinned to commit SHAs. `backend/tests/unit/test_ci_policy.py` fails the build if a pin, a permission block, a scan, or a deployment guard is removed.

A tag matching `v*.*.*` deploys. `Deploy` stops before touching anything if a secret is missing or CI has not passed on that exact commit. It connects over SSH with a pinned host key and runs `deploy/deploy.sh` in the checkout on the host. Then it checks `/health/ready` from outside. Running the workflow by hand with an older commit is the rollback.

| Name | Kind, in the `production` environment | Value |
|---|---|---|
| `SSH_HOST` | secret | the shared host |
| `SSH_USER` | secret | `deploy`, which owns the checkout and may run docker |
| `SSH_PRIVATE_KEY` | secret | a key used only by this repository's workflow |
| `SSH_KNOWN_HOSTS` | secret | `ssh-keyscan` output for the host |
| `DEPLOY_PATH` | secret | `/home/deploy/clavis/repo` |
| `CLAVIS_API_DOMAIN` | variable | `clavis.anxchywl.dev` |

`deploy/deploy.sh` runs `deploy/preflight.sh`, builds the image for the commit, starts it, and waits for `/health/ready` over HTTPS. If any step fails, it restores the previous image. Preflight refuses a dirty tree, development tokens, a development clock, API docs, a missing issuer or key, or a missing backup directory.

The host keeps `.env.production` next to the checkout, readable only by `deploy`. There is no separate host app yet, so the token issuer is this service's own HS256 secret, generated on the host and stored only in that file. When a real host app exists, move to RS256 and keep only its public key here.

Another project's Caddy owns ports 80 and 443 on the host. The service joins that proxy's network and publishes no port. Its site block lives in the wished repository's `infra/caddy/Caddyfile.production` and proxies to `clavis-api:8000`.

The container runs as uid 10001 on a read-only root file system. The volume is its only writable path. `clavis-backup` takes an online SQLite backup once a day into `/var/backups/clavis` on the host, keeps the newest `BACKUP_KEEP` copies, and checks each copy's integrity. To restore one, stop `clavis-api`, copy the file over `/data/clavis.sqlite3` in the `clavis_clavis-data` volume, and start it again. The backups stay on the same disk, so they cover mistakes, not a lost host.

The service is one process with one connection. A second replica needs a shared database first.

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
