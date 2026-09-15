import 'package:flutter_test/flutter_test.dart';
import 'package:piano_room_feature/piano_room_feature.dart';
import 'package:piano_room_feature/src/domain/piano_room_failure.dart';
import 'package:piano_room_feature/src/domain/piano_room_snapshot_validator.dart';

import '../support.dart';

void main() {
  final policy = testPolicy();
  final monday = policy.date(2026, 9, 21);

  PianoRoomWeek validWeek({List<PianoRoomBooking> bookings = const []}) =>
      policy.schedule(
        monday: monday,
        now: policy.date(2026, 9, 20, 21, 15),
        studentId: student.studentId,
        bookings: bookings,
        effectiveLimit: 2,
      );

  void validate(PianoRoomWeek week) => validatePianoRoomWeek(
    week,
    requestedMonday: monday,
    studentId: student.studentId,
    policy: policy,
  );

  test('accepts a complete privacy-filtered week', () {
    expect(
      () => validate(validWeek(bookings: [testBooking(policy)])),
      returnsNormally,
    );
  });

  test('rejects missing, duplicate, and out-of-order days or slots', () {
    final valid = validWeek();
    for (final days in [
      valid.days.take(6).toList(),
      [valid.days.first, valid.days.first, ...valid.days.skip(2)],
      valid.days.reversed.toList(),
    ]) {
      expect(
        () => validate(
          PianoRoomWeek(
            monday: valid.monday,
            days: days,
            bookings: valid.bookings,
            quota: valid.quota,
            window: valid.window,
          ),
        ),
        throwsA(isA<PianoRoomFailure>()),
      );
    }
    final firstDay = valid.days.first;
    final duplicateSlotDay = PianoRoomDay(
      date: firstDay.date,
      slots: [firstDay.slots.first, ...firstDay.slots.take(12)],
    );
    final reversedSlotDay = PianoRoomDay(
      date: firstDay.date,
      slots: firstDay.slots.reversed.toList(),
    );
    for (final malformedDay in [duplicateSlotDay, reversedSlotDay]) {
      expect(
        () => validate(
          PianoRoomWeek(
            monday: valid.monday,
            days: [malformedDay, ...valid.days.skip(1)],
            bookings: valid.bookings,
            quota: valid.quota,
            window: valid.window,
          ),
        ),
        throwsA(isA<PianoRoomFailure>()),
      );
    }
  });

  test('rejects foreign data, unknown references, and contradictory quota', () {
    final foreign = validWeek(
      bookings: [testBooking(policy, owner: 'another-student')],
    );
    final foreignBooking = testBooking(policy, owner: 'another-student');
    expect(
      () => validate(
        PianoRoomWeek(
          monday: foreign.monday,
          days: foreign.days,
          bookings: [foreignBooking],
          quota: const WeeklyQuota(booked: 1, limit: 2, defaultLimit: 2),
          window: foreign.window,
        ),
      ),
      throwsA(isA<PianoRoomFailure>()),
    );

    final valid = validWeek(bookings: [testBooking(policy)]);
    final unknown = PianoRoomBooking(
      id: 'unknown-slot',
      slotId: policy.date(2026, 9, 21, 23).toUtc().toIso8601String(),
      studentId: student.studentId,
      start: policy.date(2026, 9, 21, 23),
      end: policy.date(2026, 9, 22),
    );
    for (final bookings in [
      [unknown],
      [valid.bookings.single, valid.bookings.single],
    ]) {
      expect(
        () => validate(
          PianoRoomWeek(
            monday: valid.monday,
            days: valid.days,
            bookings: bookings,
            quota: WeeklyQuota(
              booked: bookings.length,
              limit: 2,
              defaultLimit: 2,
            ),
            window: valid.window,
          ),
        ),
        throwsA(isA<PianoRoomFailure>()),
      );
    }

    expect(
      () => validate(
        PianoRoomWeek(
          monday: valid.monday,
          days: valid.days,
          bookings: valid.bookings,
          quota: const WeeklyQuota(booked: 0, limit: 2, defaultLimit: 2),
          window: valid.window,
        ),
      ),
      throwsA(isA<PianoRoomFailure>()),
    );
  });
}
