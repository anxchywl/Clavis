# API and security contract

The backend in `backend/` is a FastAPI service. `HttpPianoRoomRepository` is the client for it, and `PianoRoomRepository` is still the boundary the feature depends on.

## Envelope

Every response is JSON. A success is `{"data": ..., "meta": {"request_id", "server_time"}}`. A failure is `{"error": {"code", "message", "request_id", "details"?}}`.

The client chooses its message from `code` alone. It never shows `message`, which is for logs and tools.

Times are UTC ISO 8601 with a `Z` suffix. A slot id is its start time in the form `2026-09-21T04:00:00.000Z`. Dates such as `monday` are `YYYY-MM-DD` in Asia/Almaty.

## Authentication

Every `/api/v1` route needs `Authorization: Bearer <token>`. The service verifies the token and reads the student from it. It never reads a student, quota, role, or time from the request.

- `AUTH_ADAPTER=host` verifies a JWT from the host: issuer, expiry, optional audience, and a signature from an allowed algorithm. The subject claim identifies the student. Operator access comes only from `HOST_OPERATOR_CLAIM` matching `HOST_OPERATOR_VALUE`.
- `AUTH_ADAPTER=development` accepts two fixed tokens, one student and one operator. Startup refuses it in production.
- With no issuer and key, the host adapter rejects every token.

## Student endpoints

| Method and path | Does |
|---|---|
| `GET /api/v1/clock` | Returns the server time as `data.now` |
| `GET /api/v1/weeks/{monday}` | Returns the week: window, quota, seven days of thirteen slots, and the student's own bookings |
| `POST /api/v1/bookings` | Books `{"slotId"}`. Needs `Idempotency-Key`. Returns `201`, or `200` with `Idempotent-Replayed: true` on a retry |
| `POST /api/v1/bookings/{id}/release` | Releases the student's own booking. Repeating it returns `200` |

A slot has `availability` of `available`, `unavailable`, or `own`. `bookingId` is set only on `own`. Another student's name, subject, and booking id are never returned.

## Operator endpoints

| Method and path | Does |
|---|---|
| `GET /api/v1/operator/weeks/{monday}/bookings` | Lists every booking that week, with its subject |
| `POST /api/v1/operator/bookings/{id}/attendance` | Records `completed`, `dropped`, or `no_show` once the slot has started |
| `PUT /api/v1/operator/students/{subject}/weekly-limit` | Sets a student's limit from 0 to 2 |

## Error codes

| Code | Status | Client failure |
|---|---|---|
| `slot_taken` | 409 | conflict |
| `quota_exceeded` | 409 | quota |
| `booking_window_closed` | 409 | windowClosed |
| `slot_in_past` | 409 | past |
| `release_deadline_passed` | 409 | releaseDeadline |
| `booking_not_confirmed` | 409 | invalidRequest |
| `slot_invalid`, `week_invalid`, `idempotency_key_invalid`, `idempotency_key_reused`, `request_validation_failed` | 422 | invalidRequest |
| `booking_not_found` | 404 | unavailable |
| `token_missing`, `token_invalid`, `host_auth_unconfigured` | 401 | unavailable |
| `operator_required`, `account_suspended` | 403 | unavailable |
| `attendance_too_early`, `attendance_invalid`, `weekly_limit_invalid` | 409, 422 | operator only |
| `request_body_too_large` | 413 | unavailable |
| `database_unavailable` | 503 | offline |
| `internal_error` | 500 | unavailable |

A connection failure, a timeout, or a 502, 503 or 504 counts as offline. Another student's booking returns `booking_not_found`, not a 403, so a request cannot confirm that a booking id exists.

## How a booking is committed

A booking runs in one SQLite write transaction (`BEGIN IMMEDIATE`). It checks, in this order: the idempotency key, the slot's place in the grid, past start, booking window, whether the slot is taken, then quota. After that it inserts the booking and records the key.

A partial unique index allows only one booking per slot that is not released, so a double booking fails even if a check above it is wrong. The key is stored with the student and slot, so a retry returns the first booking, and a reused key for another slot is refused.

Server time decides every rule. The client learns the offset from `meta.server_time` and uses it only to move the UI between responses.

## Client checks

The client:

- keeps tokens out of the feature and out of logs
- validates each returned week before showing it
- sends one request id per slot and reuses it after an unclear failure
- maps codes to localized text and never shows server text
- requires HTTPS, except for loopback from a debug build

These are safeguards. The server is the authority.

## Platform boundary

The Android main manifest requests no permissions. Debug and profile manifests request internet for Flutter tooling. A release build that talks to the backend needs internet added by the production host.

The standalone host is a demo. `kDebugMode` blocks access in profile and release builds. A production host must provide a verified session and must not import `piano_room_development.dart`.
