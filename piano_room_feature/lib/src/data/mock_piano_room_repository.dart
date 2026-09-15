import '../domain/piano_room_failure.dart';
import '../domain/piano_room_models.dart';
import '../domain/piano_room_policy.dart';
import '../domain/piano_room_repository.dart';
import '../domain/piano_room_snapshot_validator.dart';

class MockPianoRoomRepository implements PianoRoomRepository {
  MockPianoRoomRepository({
    required this.policy,
    required this.session,
    required this.now,
    this.latency = const Duration(milliseconds: 250),
    List<PianoRoomBooking> seed = const [],
    int? effectiveLimit,
  }) : _bookings = [...seed],
       effectiveLimit = effectiveLimit ?? policy.defaultLimit;
  final PianoRoomPolicy policy;
  final PianoRoomSession session;
  final DateTime Function() now;
  final Duration latency;
  final int effectiveLimit;
  final List<PianoRoomBooking> _bookings;
  final Map<String, ({String slotId, PianoRoomBooking booking})> _requests = {};
  bool offline = false;
  bool conflictOnNextBooking = false;
  bool failAfterNextCommit = false;
  bool emptySchedule = false;
  int _sequence = 0;

  Future<void> _wait() async {
    if (latency != Duration.zero) await Future<void>.delayed(latency);
    if (offline) throw const PianoRoomFailure(PianoRoomFailureCode.offline);
  }

  PianoRoomWeek _week(DateTime monday) => policy.schedule(
    monday: monday,
    now: now(),
    studentId: session.studentId,
    bookings: _bookings,
    effectiveLimit: effectiveLimit,
  );
  @override
  Future<PianoRoomWeek> loadWeek(DateTime monday) async {
    await _wait();
    final week = _week(policy.mondayOf(monday));
    final result = !emptySchedule
        ? week
        : PianoRoomWeek(
            monday: week.monday,
            days: const [],
            bookings: const [],
            quota: WeeklyQuota(
              booked: 0,
              limit: week.quota.limit,
              defaultLimit: week.quota.defaultLimit,
            ),
            window: BookingWindowStatus.unavailable,
          );
    validatePianoRoomWeek(
      result,
      requestedMonday: monday,
      studentId: session.studentId,
      policy: policy,
    );
    return result;
  }

  @override
  Future<PianoRoomBooking> book({
    required String slotId,
    required String requestId,
  }) async {
    await _wait();
    if (requestId.isEmpty) {
      throw const PianoRoomFailure(PianoRoomFailureCode.invalidRequest);
    }
    final previous = _requests[requestId];
    if (previous != null) {
      if (previous.slotId != slotId) {
        throw const PianoRoomFailure(PianoRoomFailureCode.invalidRequest);
      }
      return _bookings.firstWhere(
        (booking) => booking.id == previous.booking.id,
      );
    }
    final instant = DateTime.tryParse(slotId);
    if (instant == null) {
      throw const PianoRoomFailure(PianoRoomFailureCode.invalidRequest);
    }
    final week = _week(policy.mondayOf(instant));
    final slots = week.days
        .expand((day) => day.slots)
        .where((slot) => slot.id == slotId);
    if (slots.isEmpty || emptySchedule) {
      throw const PianoRoomFailure(PianoRoomFailureCode.unavailable);
    }
    final slot = slots.first;
    policy.validateBooking(slot, week.quota, now());
    if (conflictOnNextBooking) {
      conflictOnNextBooking = false;
      _bookings.add(
        PianoRoomBooking(
          id: 'competing-${++_sequence}',
          slotId: slotId,
          studentId: 'synthetic-other',
          start: slot.start,
          end: slot.end,
        ),
      );
      throw const PianoRoomFailure(PianoRoomFailureCode.conflict);
    }
    final booking = PianoRoomBooking(
      id: 'booking-${++_sequence}',
      slotId: slotId,
      studentId: session.studentId,
      start: slot.start,
      end: slot.end,
    );
    _bookings.add(booking);
    _requests[requestId] = (slotId: slotId, booking: booking);
    if (failAfterNextCommit) {
      failAfterNextCommit = false;
      throw const PianoRoomFailure(PianoRoomFailureCode.offline);
    }
    return booking;
  }

  @override
  Future<void> release(String bookingId) async {
    await _wait();
    final index = _bookings.indexWhere((booking) => booking.id == bookingId);
    if (index < 0) {
      throw const PianoRoomFailure(PianoRoomFailureCode.unavailable);
    }
    final booking = _bookings[index];
    if (booking.studentId != session.studentId) {
      throw const PianoRoomFailure(PianoRoomFailureCode.notOwner);
    }
    if (booking.status == BookingStatus.released) return;
    _bookings[index] = policy.transition(
      booking,
      BookingStatus.released,
      studentId: session.studentId,
      now: now(),
    );
  }
}
