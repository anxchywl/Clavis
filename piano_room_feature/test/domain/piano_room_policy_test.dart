import 'package:flutter_test/flutter_test.dart';
import 'package:piano_room_feature/piano_room_feature.dart';
import 'package:piano_room_feature/src/domain/piano_room_failure.dart';
import '../support.dart';

void main() {
  final p = testPolicy();
  final monday = p.date(2026, 9, 21);
  final open = p.date(2026, 9, 20, 21);
  test('seven days contain exactly thirteen contiguous room-local hours', () {
    final week = p.schedule(
      monday: monday,
      now: open,
      studentId: student.studentId,
      bookings: [],
      effectiveLimit: 2,
    );
    expect(week.days, hasLength(7));
    expect(week.days.last.date.weekday, DateTime.sunday);
    final ids = <String>{};
    for (final day in week.days) {
      expect(day.slots, hasLength(13));
      for (var i = 0; i < 13; i++) {
        final slot = day.slots[i];
        expect(slot.start.hour, 9 + i);
        expect(slot.end.hour, 10 + i);
        expect(slot.timezone, 'Asia/Almaty');
        expect(slot.localDate, day.date);
        expect(slot.end.difference(slot.start), const Duration(hours: 1));
        expect(slot.isEligible, isTrue);
        ids.add(slot.id);
      }
    }
    expect(ids, hasLength(91));
    expect(() => week.days.clear(), throwsUnsupportedError);
  });
  test('booking window is inclusive at 21 and exclusive at 22', () {
    for (final row in [
      (
        open.subtract(const Duration(microseconds: 1)),
        BookingWindowStatus.upcoming,
      ),
      (open, BookingWindowStatus.open),
      (open.add(const Duration(minutes: 59)), BookingWindowStatus.open),
      (open.add(const Duration(hours: 1)), BookingWindowStatus.closed),
      (open.add(const Duration(hours: 2)), BookingWindowStatus.closed),
    ]) {
      expect(p.window(monday, row.$1), row.$2);
    }
  });
  test(
    'ISO week boundaries cross years and use Almaty instead of device time',
    () {
      expect(p.mondayOf(p.date(2027, 1, 3)), p.date(2026, 12, 28));
      expect(p.mondayOf(p.date(2027, 1, 4)), p.date(2027, 1, 4));
      expect(p.local(DateTime.utc(2026, 9, 20, 19)).day, 21);
      expect(p.mondayOf(DateTime.utc(2026, 9, 20, 19)), monday);
      expect(
        p.window(monday, DateTime.utc(2026, 9, 20, 16)),
        BookingWindowStatus.open,
      );
      expect(p.initialWeek(open), monday);
      expect(
        p.initialWeek(open.subtract(const Duration(seconds: 1))),
        p.date(2026, 9, 14),
      );
      expect(p.shiftDays(monday, -7), p.date(2026, 9, 14));
    },
  );
  test(
    'released bookings restore quota; completed dropped and no-show count',
    () {
      for (final status in BookingStatus.values) {
        final quota = p.quota(
          [testBooking(p, status: status)],
          student.studentId,
          monday,
          2,
        );
        expect(quota.booked, status == BookingStatus.released ? 0 : 1);
        expect(quota.remaining, status == BookingStatus.released ? 2 : 1);
      }
      expect(
        p
            .quota(
              [testBooking(p, owner: 'other')],
              student.studentId,
              monday,
              2,
            )
            .booked,
        0,
      );
      expect(
        p
            .quota(
              [testBooking(p)],
              student.studentId,
              p.shiftDays(monday, 7),
              2,
            )
            .booked,
        0,
      );
      final quota = p.quota([testBooking(p)], student.studentId, monday, 1);
      expect(quota.isPenalized, isTrue);
      expect(quota.remaining, 0);
      expect(p.quota([], student.studentId, monday, -1).limit, 0);
    },
  );
  test(
    'release allowed exactly ten minutes before, denied afterwards and for another account',
    () {
      final b = testBooking(p);
      final deadline = b.start.subtract(const Duration(minutes: 10));
      expect(p.canRelease(b, student.studentId, deadline), isTrue);
      expect(
        p.canRelease(
          b,
          student.studentId,
          deadline.add(const Duration(microseconds: 1)),
        ),
        isFalse,
      );
      expect(p.canRelease(b, 'other', open), isFalse);
      expect(
        p
            .transition(
              b,
              BookingStatus.released,
              studentId: student.studentId,
              now: deadline,
            )
            .status,
        BookingStatus.released,
      );
      expect(
        () => p.transition(
          b,
          BookingStatus.released,
          studentId: student.studentId,
          now: b.start,
        ),
        throwsA(isA<PianoRoomFailure>()),
      );
      expect(
        () => p.transition(
          b,
          BookingStatus.released,
          studentId: 'other',
          now: open,
        ),
        throwsA(isA<PianoRoomFailure>()),
      );
    },
  );
  test('attendance transitions require explicit administrative signals', () {
    final b = testBooking(p);
    for (final status in [
      BookingStatus.dropped,
      BookingStatus.noShow,
      BookingStatus.completed,
    ]) {
      expect(
        () => p.transition(b, status, studentId: student.studentId, now: b.end),
        throwsA(isA<PianoRoomFailure>()),
      );
      final updated = p.transition(
        b,
        status,
        studentId: student.studentId,
        now: b.end,
        administrativeSignal: true,
      );
      expect(updated.status, status);
      expect(p.canRelease(updated, student.studentId, open), isFalse);
      expect(
        () => p.transition(
          updated,
          BookingStatus.released,
          studentId: student.studentId,
          now: open,
        ),
        throwsA(isA<PianoRoomFailure>()),
      );
    }
    expect(b.status, BookingStatus.confirmed);
  });
  test('schedule never exposes another student identity or booking id', () {
    final week = p.schedule(
      monday: monday,
      now: open,
      studentId: student.studentId,
      bookings: [
        testBooking(p, owner: 'other'),
        testBooking(p, hour: 10),
      ],
      effectiveLimit: 2,
    );
    expect(week.bookings, hasLength(1));
    expect(week.days.first.slots.first.bookingId, isNull);
    expect(week.days.first.slots.first.isEligible, isFalse);
    expect(week.days.first.slots[1].belongsToCurrentStudent, isTrue);
    expect(week.days.first.availableCount, 11);
  });
}
