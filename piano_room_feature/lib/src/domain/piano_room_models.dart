enum BookingStatus { confirmed, released, completed, dropped, noShow }

enum BookingWindowStatus { upcoming, open, closed, unavailable }

enum SlotAvailability { available, unavailable, own }

class PianoRoomSession {
  const PianoRoomSession({
    required this.studentId,
    required this.displayName,
    this.email,
  });
  final String studentId;
  final String displayName;
  final String? email;
}

class PianoRoomBooking {
  const PianoRoomBooking({
    required this.id,
    required this.slotId,
    required this.studentId,
    required this.start,
    required this.end,
    this.status = BookingStatus.confirmed,
  });
  final String id;
  final String slotId;
  final String studentId;
  final DateTime start;
  final DateTime end;
  final BookingStatus status;
  PianoRoomBooking withStatus(BookingStatus value) => PianoRoomBooking(
    id: id,
    slotId: slotId,
    studentId: studentId,
    start: start,
    end: end,
    status: value,
  );
}

class PianoRoomSlot {
  const PianoRoomSlot({
    required this.id,
    required this.localDate,
    required this.start,
    required this.end,
    required this.availability,
    required this.isEligible,
    required this.timezone,
    this.bookingId,
  });
  final String id;
  final DateTime localDate;
  final DateTime start;
  final DateTime end;
  final SlotAvailability availability;
  final bool isEligible;
  final String timezone;
  final String? bookingId;
  bool get belongsToCurrentStudent => availability == SlotAvailability.own;
}

class PianoRoomDay {
  PianoRoomDay({required this.date, required List<PianoRoomSlot> slots})
    : slots = List.unmodifiable(slots);
  final DateTime date;
  final List<PianoRoomSlot> slots;
  int get availableCount => slots
      .where((slot) => slot.availability == SlotAvailability.available)
      .length;
}

class WeeklyQuota {
  const WeeklyQuota({
    required this.booked,
    required this.limit,
    required this.defaultLimit,
  });
  final int booked;
  final int limit;
  final int defaultLimit;
  int get remaining => (limit - booked).clamp(0, limit);
  bool get isPenalized => limit < defaultLimit;
  int afterBooking({required bool alreadyCounted}) =>
      booked + (alreadyCounted ? 0 : 1);
}

class PianoRoomWeek {
  PianoRoomWeek({
    required this.monday,
    required List<PianoRoomDay> days,
    required List<PianoRoomBooking> bookings,
    required this.quota,
    required this.window,
  }) : days = List.unmodifiable(days),
       bookings = List.unmodifiable(bookings);
  final DateTime monday;
  final List<PianoRoomDay> days;
  final List<PianoRoomBooking> bookings;
  final WeeklyQuota quota;
  final BookingWindowStatus window;
}
