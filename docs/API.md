# Repository and security contract

There is no HTTP API yet. `PianoRoomRepository` is the boundary that a future remote adapter must implement.

## Operations

- `loadWeek(monday)` returns room-local days and slots, the current student's bookings, effective quota, and booking-window state.
- `book(slotId, requestId)` checks the window, future start, availability, and quota. It returns only after the booking is committed.
- `release(bookingId)` checks ownership, status, and the release deadline. Repeating a successful release is safe.

Repository failures use typed codes. The UI maps those codes to localized text. It never displays raw server messages.

## Client checks

The current client:

- keeps tokens out of the feature
- binds the mock repository to one session
- checks ownership before release
- hides other students' details
- validates returned schedules before showing them
- prevents duplicate submission and overlapping loads
- keeps request IDs in memory for safe retry
- maps unexpected errors to a generic localized failure
- writes no tokens, emails, booking IDs, or response bodies to logs

These checks improve safety, but they are not production authorization.

## Server requirements

The server must resolve identity from a verified session. It must not trust a client-supplied student ID, email, quota, penalty, ownership flag, booking window, availability result, or device time.

Each booking or release must atomically enforce:

- ownership and access
- slot uniqueness
- quota and penalty state
- booking window and cancellation deadline
- server-authoritative time
- durable idempotency tied to the account and request payload

Responses must not expose another student's name, ID, booking ID, or history. Logs and error responses must not include tokens, emails, booking IDs, or sensitive bodies.

Use normal platform TLS validation for future network requests. Certificate pinning, custom cryptography, and obfuscation do not replace server authorization.

## Platform and development boundary

The Android main manifest requests no permissions. Debug and profile manifests request internet for Flutter tooling. Web deployment headers such as CSP and HSTS belong to the future host.

The standalone host is a demo. `kDebugMode` blocks access in profile and release builds, even when a compile-time flag asks to enable it. A future production host must not import `piano_room_development.dart` or create sample dependencies.

## Next step

Define how the host provides a verified session. Then implement authenticated week reads and atomic booking behind `PianoRoomRepository`. Run the existing privacy, conflict, foreign-release, changed-payload, and lost-acknowledgement tests against that adapter.
