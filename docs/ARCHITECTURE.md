# Architecture

## Packages

`piano_room_app -> piano_room_feature -> app_ui`, and the feature talks to `backend/` over HTTP.

The host owns identity, theme, locale, clock, policy, and repository setup. The feature does not create a `MaterialApp` or handle authentication.

`app_ui` comes from the Gradus fork at commit `2bcc62067d2c89b0b0fcd1cd5d40ac515f526cc4`. Piano Room code must not be added to it. Its only generic change is optional `AppAppBar.toolbarHeight` support for large text.

## Layers

- Domain is pure Dart. It contains models, policy, timezone rules, failures, validation, and the repository interface.
- Application contains the controller and scope. It depends only on domain interfaces.
- Data contains the HTTP repository, the mock repository, and demo fixtures. `piano_room_remote.dart` and `piano_room_development.dart` are the two factories a host can import.
- Presentation contains the schedule and sheets. It never imports data code.

`PianoRoomFeature` creates and disposes the controller. It replaces the controller when the session, policy, or repository changes. Old responses cannot update another week or session. Loads run one at a time, and rapid navigation keeps only the latest selected week.

Repository results are checked before the UI uses them. The check covers the requested week, day and slot order, IDs, booking references, quota, and student privacy.

## Mutations

Booking is not optimistic. The UI waits for repository confirmation.

A booking request keeps the same secure random request ID after an unclear network failure. The server stores it as the `Idempotency-Key`. Reusing that ID with another slot is rejected. Release retries are safe.

The backend checks and writes inside one database transaction, backed by a unique index on active slots. The mock does the same without an asynchronous gap, which only models one process.

## Time, loading, and refresh

Calendar rules use IANA data for Asia/Almaty on both sides. The host provides the clock. In remote mode that clock is the device time corrected by the offset from the last response, and every rule is decided again on the server with its own time.

The first load shows a static skeleton with one loading announcement. Cached content stays visible during refresh. A refresh failure keeps that content and shows a retry action.

Automatic refresh runs every 30 seconds only while the booking window is open. It pauses when the app is not active and refreshes once when the app resumes. Closed and upcoming windows update time-based UI without a network request.

The schedule uses existing app_ui tokens. Sheets are scrollable and safe-area aware. Large text is not clamped. Nonessential animation is disabled.

## Backend

`backend/app` has the same layers as Gradus's service:

- `domain` holds the room rules, booking model, and typed errors. It imports no framework and no database.
- `application` holds the booking service and the store and clock protocols. It does not import the web layer or the store.
- `infrastructure` holds the SQLite store, the clocks, and the token resolvers.
- `api` holds the routes, request schemas, and the error envelope. It never names the store.

Boundary tests enforce these rules. SQLite suits one process on one host. A second replica would need a shared database behind the same store protocol.

