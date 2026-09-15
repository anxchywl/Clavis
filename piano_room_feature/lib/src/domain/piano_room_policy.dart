import 'package:timezone/timezone.dart' as tz;

import 'piano_room_failure.dart';
import 'piano_room_models.dart';

class PianoRoomPolicy {
  PianoRoomPolicy({required this.location, this.defaultLimit = 2});
  final tz.Location location;
  final int defaultLimit;
  String get timezone => location.name;
  DateTime local(DateTime instant) => tz.TZDateTime.from(instant, location);
  DateTime date(int year, int month, int day, [int hour = 0, int minute = 0]) =>
      tz.TZDateTime(location, year, month, day, hour, minute);
  DateTime mondayOf(DateTime instant) {
    final day = local(instant);
    return date(day.year, day.month, day.day - day.weekday + 1);
  }

  DateTime shiftDays(DateTime value, int days) =>
      date(value.year, value.month, value.day + days);
  DateTime opensAt(DateTime monday) =>
      date(monday.year, monday.month, monday.day - 1, 21);
  BookingWindowStatus window(DateTime monday, DateTime now) {
    final opens = opensAt(monday);
    if (now.isBefore(opens)) return BookingWindowStatus.upcoming;
    if (now.isBefore(opens.add(const Duration(hours: 1)))) {
      return BookingWindowStatus.open;
    }
    return BookingWindowStatus.closed;
  }

  DateTime initialWeek(DateTime now) {
    final current = mondayOf(now);
    return !now.isBefore(opensAt(shiftDays(current, 7)))
        ? shiftDays(current, 7)
        : current;
  }

  bool countsTowardQuota(BookingStatus status) =>
      status != BookingStatus.released;
  WeeklyQuota quota(
    Iterable<PianoRoomBooking> bookings,
    String studentId,
    DateTime monday,
    int effectiveLimit,
  ) => WeeklyQuota(
    booked: bookings
        .where(
          (booking) =>
              booking.studentId == studentId &&
              mondayOf(booking.start) == monday &&
              countsTowardQuota(booking.status),
        )
        .length,
    limit: effectiveLimit.clamp(0, defaultLimit),
    defaultLimit: defaultLimit,
  );
  bool canRelease(PianoRoomBooking booking, String studentId, DateTime now) =>
      booking.studentId == studentId &&
      booking.status == BookingStatus.confirmed &&
      !now.isAfter(booking.start.subtract(const Duration(minutes: 10)));
  void validateBooking(PianoRoomSlot slot, WeeklyQuota quota, DateTime now) {
    if (!slot.start.isAfter(now)) {
      throw const PianoRoomFailure(PianoRoomFailureCode.past);
    }
    if (window(mondayOf(slot.start), now) != BookingWindowStatus.open) {
      throw const PianoRoomFailure(PianoRoomFailureCode.windowClosed);
    }
    if (slot.availability != SlotAvailability.available) {
      throw const PianoRoomFailure(PianoRoomFailureCode.conflict);
    }
    if (quota.remaining == 0) {
      throw const PianoRoomFailure(PianoRoomFailureCode.quota);
    }
  }

  PianoRoomBooking transition(
    PianoRoomBooking booking,
    BookingStatus next, {
    required String studentId,
    required DateTime now,
    bool administrativeSignal = false,
  }) {
    if (booking.studentId != studentId) {
      throw const PianoRoomFailure(PianoRoomFailureCode.notOwner);
    }
    if (booking.status != BookingStatus.confirmed) {
      throw const PianoRoomFailure(PianoRoomFailureCode.invalidRequest);
    }
    if (next == BookingStatus.released) {
      if (!canRelease(booking, studentId, now)) {
        throw const PianoRoomFailure(PianoRoomFailureCode.releaseDeadline);
      }
    } else if (!administrativeSignal ||
        !{
          BookingStatus.completed,
          BookingStatus.dropped,
          BookingStatus.noShow,
        }.contains(next)) {
      throw const PianoRoomFailure(PianoRoomFailureCode.invalidRequest);
    }
    return booking.withStatus(next);
  }

  PianoRoomWeek schedule({
    required DateTime monday,
    required DateTime now,
    required String studentId,
    required List<PianoRoomBooking> bookings,
    required int effectiveLimit,
  }) {
    final weeklyQuota = quota(bookings, studentId, monday, effectiveLimit);
    final status = window(monday, now);
    return PianoRoomWeek(
      monday: monday,
      window: status,
      quota: weeklyQuota,
      bookings: bookings
          .where((b) => b.studentId == studentId && mondayOf(b.start) == monday)
          .toList(),
      days: List.generate(7, (dayIndex) {
        final day = shiftDays(monday, dayIndex);
        return PianoRoomDay(
          date: day,
          slots: List.generate(13, (hourIndex) {
            final start = date(day.year, day.month, day.day, 9 + hourIndex);
            final end = date(day.year, day.month, day.day, 10 + hourIndex);
            final id = start.toUtc().toIso8601String();
            final matches = bookings.where(
              (b) => b.slotId == id && b.status != BookingStatus.released,
            );
            final booking = matches.isEmpty ? null : matches.first;
            final availability = booking == null
                ? SlotAvailability.available
                : booking.studentId == studentId
                ? SlotAvailability.own
                : SlotAvailability.unavailable;
            return PianoRoomSlot(
              id: id,
              localDate: day,
              start: start,
              end: end,
              timezone: timezone,
              availability: availability,
              bookingId: booking?.studentId == studentId ? booking?.id : null,
              isEligible:
                  availability == SlotAvailability.available &&
                  start.isAfter(now) &&
                  status == BookingWindowStatus.open &&
                  weeklyQuota.remaining > 0,
            );
          }),
        );
      }),
    );
  }
}
