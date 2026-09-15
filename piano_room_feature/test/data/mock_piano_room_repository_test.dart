import 'package:flutter_test/flutter_test.dart';
import 'package:piano_room_feature/piano_room_feature.dart';
import 'package:piano_room_feature/piano_room_development.dart';
import 'package:piano_room_feature/src/domain/piano_room_failure.dart';
import '../support.dart';

Matcher failure(PianoRoomFailureCode code) =>
    isA<PianoRoomFailure>().having((e) => e.code, 'code', code);
void main() {
  final p = testPolicy();
  final monday = p.date(2026, 9, 21);
  String slot(int hour) => p.date(2026, 9, 21, hour).toUtc().toIso8601String();
  test(
    'booking confirms once and retry after lost acknowledgement returns same booking',
    () async {
      final repo = testRepository(p)..failAfterNextCommit = true;
      await expectLater(
        repo.book(slotId: slot(9), requestId: 'retry'),
        throwsA(failure(PianoRoomFailureCode.offline)),
      );
      final booking = await repo.book(slotId: slot(9), requestId: 'retry');
      expect(
        (await repo.book(slotId: slot(9), requestId: 'retry')).id,
        booking.id,
      );
      expect((await repo.loadWeek(monday)).quota.booked, 1);
      await expectLater(
        repo.book(slotId: slot(10), requestId: 'retry'),
        throwsA(failure(PianoRoomFailureCode.invalidRequest)),
      );
    },
  );
  test('concurrent different requests cannot occupy the same slot', () async {
    final repo = testRepository(p);
    final one = repo.book(slotId: slot(9), requestId: 'one');
    final two = repo.book(slotId: slot(9), requestId: 'two');
    await expectLater(two, throwsA(failure(PianoRoomFailureCode.conflict)));
    await one;
    expect((await repo.loadWeek(monday)).quota.booked, 1);
  });
  test(
    'limit two allows second booking and rejects third; penalized limit rejects second',
    () async {
      for (final limit in [1, 2]) {
        final repo = testRepository(p, limit: limit);
        for (var i = 0; i < limit; i++) {
          await repo.book(slotId: slot(9 + i), requestId: 'r$i');
        }
        await expectLater(
          repo.book(slotId: slot(11), requestId: 'excess'),
          throwsA(failure(PianoRoomFailureCode.quota)),
        );
      }
    },
  );
  test(
    'repository rejects past and closed-window writes regardless of UI',
    () async {
      var now = p.date(2026, 9, 20, 20);
      final repo = testRepository(p, now: () => now);
      await expectLater(
        repo.book(slotId: slot(9), requestId: 'early'),
        throwsA(failure(PianoRoomFailureCode.windowClosed)),
      );
      now = p.date(2026, 9, 20, 22);
      await expectLater(
        repo.book(slotId: slot(9), requestId: 'closed'),
        throwsA(failure(PianoRoomFailureCode.windowClosed)),
      );
      now = p.date(2026, 9, 21, 9);
      await expectLater(
        repo.book(slotId: slot(9), requestId: 'past'),
        throwsA(failure(PianoRoomFailureCode.past)),
      );
    },
  );
  test('offline load and submission fail without a new booking', () async {
    final repo = testRepository(p)..offline = true;
    await expectLater(
      repo.loadWeek(monday),
      throwsA(failure(PianoRoomFailureCode.offline)),
    );
    await expectLater(
      repo.book(slotId: slot(9), requestId: 'offline'),
      throwsA(failure(PianoRoomFailureCode.offline)),
    );
    repo.offline = false;
    expect((await repo.loadWeek(monday)).bookings, isEmpty);
  });
  test(
    'conflict records competing booking and refreshed slot is unavailable',
    () async {
      final repo = testRepository(p)..conflictOnNextBooking = true;
      await expectLater(
        repo.book(slotId: slot(9), requestId: 'conflict'),
        throwsA(failure(PianoRoomFailureCode.conflict)),
      );
      final week = await repo.loadWeek(monday);
      expect(
        week.days.first.slots.first.availability,
        SlotAvailability.unavailable,
      );
      expect(week.bookings, isEmpty);
    },
  );
  test('release restores quota and repeated release is harmless', () async {
    var now = p.date(2026, 9, 20, 21);
    final repo = testRepository(p, now: () => now);
    final booking = await repo.book(slotId: slot(9), requestId: 'one');
    now = p.date(2026, 9, 21, 8, 50);
    await repo.release(booking.id);
    await repo.release(booking.id);
    final week = await repo.loadWeek(monday);
    expect(week.quota.booked, 0);
    expect(week.days.first.slots.first.isEligible, isFalse);
    expect(week.bookings.single.status, BookingStatus.released);
  });
  test('late and foreign releases are refused', () async {
    final repo = testRepository(
      p,
      seed: [
        testBooking(p),
        testBooking(p, owner: 'other', hour: 10),
      ],
      now: () => p.date(2026, 9, 21, 8, 51),
    );
    await expectLater(
      repo.release('seed-9'),
      throwsA(failure(PianoRoomFailureCode.releaseDeadline)),
    );
    await expectLater(
      repo.release('seed-10'),
      throwsA(failure(PianoRoomFailureCode.notOwner)),
    );
    await expectLater(
      repo.release('absent'),
      throwsA(failure(PianoRoomFailureCode.unavailable)),
    );
  });
  test('invalid slots and empty request ids are rejected', () async {
    final repo = testRepository(p);
    for (final id in [
      'garbage',
      p.date(2026, 9, 21, 8).toUtc().toIso8601String(),
    ]) {
      await expectLater(
        repo.book(slotId: id, requestId: 'r'),
        throwsA(isA<PianoRoomFailure>()),
      );
    }
    await expectLater(
      repo.book(slotId: slot(9), requestId: ''),
      throwsA(isA<PianoRoomFailure>()),
    );
    repo.emptySchedule = true;
    expect((await repo.loadWeek(monday)).days, isEmpty);
    await expectLater(
      repo.book(slotId: slot(9), requestId: 'r'),
      throwsA(isA<PianoRoomFailure>()),
    );
  });
  test(
    'development restart restores deterministic data and scenarios stay explicit',
    () async {
      final first = PianoRoomSample();
      await first.repository.book(slotId: slot(9), requestId: 'temporary');
      final restarted = PianoRoomSample();
      expect((await restarted.repository.loadWeek(monday)).quota.booked, 1);
      for (final scenario in SampleScenario.values) {
        final sample = PianoRoomSample(scenario: scenario);
        expect(sample.session.studentId, restarted.session.studentId);
        if (scenario == SampleScenario.offline) {
          await expectLater(
            sample.repository.loadWeek(monday),
            throwsA(isA<PianoRoomFailure>()),
          );
        } else {
          final week = await sample.repository.loadWeek(monday);
          expect(week.quota.limit, scenario == SampleScenario.penalty ? 1 : 2);
        }
      }
    },
  );
}
