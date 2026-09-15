import 'piano_room_failure.dart';
import 'piano_room_models.dart';
import 'piano_room_policy.dart';

void validatePianoRoomWeek(
  PianoRoomWeek week, {
  required DateTime requestedMonday,
  required String studentId,
  required PianoRoomPolicy policy,
}) {
  void reject() {
    throw const PianoRoomFailure(PianoRoomFailureCode.invalidRequest);
  }

  if (week.monday != policy.mondayOf(requestedMonday) ||
      week.quota.limit < 0 ||
      week.quota.limit > week.quota.defaultLimit ||
      week.quota.booked < 0 ||
      week.quota.booked > week.quota.defaultLimit) {
    reject();
  }

  if (week.days.isEmpty) {
    if (week.bookings.isNotEmpty || week.quota.booked != 0) reject();
    return;
  }
  if (week.days.length != 7) reject();

  final slotIds = <String>{};
  for (var dayIndex = 0; dayIndex < week.days.length; dayIndex++) {
    final day = week.days[dayIndex];
    if (day.date != policy.shiftDays(week.monday, dayIndex) ||
        day.slots.length != 13) {
      reject();
    }
    for (var slotIndex = 0; slotIndex < day.slots.length; slotIndex++) {
      final slot = day.slots[slotIndex];
      final expectedStart = policy.date(
        day.date.year,
        day.date.month,
        day.date.day,
        9 + slotIndex,
      );
      final parsedId = DateTime.tryParse(slot.id);
      if (slot.id.isEmpty ||
          parsedId == null ||
          slot.start != expectedStart ||
          parsedId.toUtc() != slot.start.toUtc() ||
          slot.timezone != policy.timezone ||
          slot.localDate != day.date ||
          !slot.end.isAfter(slot.start) ||
          slot.end.difference(slot.start) != const Duration(hours: 1) ||
          !slotIds.add(slot.id) ||
          (slot.availability != SlotAvailability.own &&
              slot.bookingId != null)) {
        reject();
      }
    }
  }

  final bookingIds = <String>{};
  final activeSlotIds = <String>{};
  var counted = 0;
  for (final booking in week.bookings) {
    if (booking.id.isEmpty ||
        booking.studentId != studentId ||
        !slotIds.contains(booking.slotId) ||
        !bookingIds.add(booking.id) ||
        !booking.end.isAfter(booking.start) ||
        booking.end.difference(booking.start) != const Duration(hours: 1)) {
      reject();
    }
    if (policy.countsTowardQuota(booking.status)) {
      if (!activeSlotIds.add(booking.slotId)) reject();
      counted++;
    }
  }
  if (counted != week.quota.booked) reject();
}
