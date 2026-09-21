# Product rules

## Schedule and booking

The Piano Room is in Block D6, Room 055. It is open from 09:00 to 22:00 in the Asia/Almaty timezone. Each day has thirteen one-hour slots. The normal weekly limit is two bookings per student.

A week runs from Monday to Sunday. Booking for the next week opens on Sunday at 21:00 and closes at 22:00. Exactly 21:00 is open. Exactly 22:00 is closed. Other weeks can be viewed, but they cannot be booked.

The app opens on the current week before Sunday at 21:00. From 21:00, it opens on the next week. Quota belongs to the week of the booked slot.

Past slots cannot be booked. A reduced quota can only come from the repository. The client cannot restore it.

## Releasing a booking

A student can release their own confirmed booking until exactly ten minutes before it starts. Release returns one booking to that week's quota. It is allowed even after the weekly booking window closes.

Confirmed, completed, dropped, and no-show bookings count toward quota. Released bookings do not. Penalties and attendance changes require an administrator. The client never guesses attendance.

## Access and room rules

Students must be on the room access list. The current spreadsheet accepts only `@nu.edu.kz` accounts. The demo does not verify either rule.

Collect the key at reception and leave your ID card. Switch off the lights, lock the door, and leave the room clean. Do not move the piano close to heaters. Report damage to the Piano Room group or `pianoclub@nu.edu.kz`.

If you cannot attend, release the slot in the app at least ten minutes before it starts. Booking and cancelling do not go through the Piano Room group.

## User experience

The schedule shows seven days, thirteen slots for the selected day, quota, and the student's own bookings. Another student's booking appears only as unavailable. Their name, ID, booking ID, and history are never shown.

Booking success appears only after repository confirmation. A conflict refreshes the selected week. If a request may have committed before the connection failed, retry uses the same request ID.

All visible and semantic text is available in English, Russian, and Kazakh. Dates and times always use the room timezone.

## Demo limits

The default demo time is 20 September 2026 at 21:15 in Almaty. The host also includes offline, conflict, empty, closed, upcoming, penalty, dropped, and no-show scenarios.

The sample quota and penalties are only fixtures. There is no real authentication, backend, email verification, cross-device locking, attendance system, or group notification.
