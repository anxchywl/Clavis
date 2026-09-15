import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_room_feature/piano_room_feature.dart';
import 'package:piano_room_feature/src/application/piano_room_controller.dart';
import 'package:piano_room_feature/src/domain/piano_room_failure.dart';
import '../support.dart';

class DelayedRepository implements PianoRoomRepository {
  final loads = <Completer<PianoRoomWeek>>[];
  var activeLoads = 0;
  var maxActiveLoads = 0;
  @override
  Future<PianoRoomWeek> loadWeek(DateTime monday) {
    final pending = Completer<PianoRoomWeek>();
    loads.add(pending);
    activeLoads++;
    if (activeLoads > maxActiveLoads) maxActiveLoads = activeLoads;
    return pending.future.whenComplete(() => activeLoads--);
  }

  @override
  Future<PianoRoomBooking> book({
    required String slotId,
    required String requestId,
  }) => throw UnimplementedError();
  @override
  Future<void> release(String bookingId) => throw UnimplementedError();
}

class FailingLoadRepository implements PianoRoomRepository {
  FailingLoadRepository(this.inner);

  final PianoRoomRepository inner;
  Object? loadError;
  Object? bookError;

  @override
  Future<PianoRoomWeek> loadWeek(DateTime monday) async {
    final error = loadError;
    if (error != null) throw error;
    return inner.loadWeek(monday);
  }

  @override
  Future<PianoRoomBooking> book({
    required String slotId,
    required String requestId,
  }) {
    final error = bookError;
    if (error != null) return Future.error(error);
    return inner.book(slotId: slotId, requestId: requestId);
  }

  @override
  Future<void> release(String bookingId) => inner.release(bookingId);
}

class DelayedMutationRepository implements PianoRoomRepository {
  DelayedMutationRepository(this.inner);
  final PianoRoomRepository inner;
  final commit = Completer<void>();
  @override
  Future<PianoRoomWeek> loadWeek(DateTime monday) => inner.loadWeek(monday);
  @override
  Future<PianoRoomBooking> book({
    required String slotId,
    required String requestId,
  }) async {
    await commit.future;
    return inner.book(slotId: slotId, requestId: requestId);
  }

  @override
  Future<void> release(String bookingId) => inner.release(bookingId);
}

void main() {
  final p = testPolicy();
  final now = p.date(2026, 9, 20, 21, 15);
  PianoRoomController controller(PianoRoomRepository repo) =>
      PianoRoomController(
        repository: repo,
        policy: p,
        session: student,
        now: () => now,
      );
  test('load, book and release update quota after confirmation', () async {
    final c = controller(testRepository(p));
    expect(c.phase, SchedulePhase.loading);
    await c.load();
    expect(c.window, BookingWindowStatus.open);
    final slot = c.week!.days.first.slots.first;
    expect(c.eligible(slot), isTrue);
    expect(await c.book(slot), isTrue);
    expect(c.confirmedBooking, isNotNull);
    expect(c.week!.quota.booked, 1);
    expect(await c.book(slot), isTrue);
    expect(c.week!.quota.booked, 1);
    expect(c.canRelease(c.week!.bookings.single), isTrue);
    expect(await c.release(c.week!.bookings.single), isTrue);
    expect(c.week!.quota.booked, 0);
    expect(await c.book(c.week!.days.first.slots.first), isTrue);
    expect(c.week!.quota.booked, 1);
    c.dispose();
  });
  test('conflict refreshes slot and preserves conflict outcome', () async {
    final repo = testRepository(p)..conflictOnNextBooking = true;
    final c = controller(repo);
    await c.load();
    expect(await c.book(c.week!.days.first.slots.first), isFalse);
    expect(c.mutationFailure, PianoRoomFailureCode.conflict);
    expect(
      c.week!.days.first.slots.first.availability,
      SlotAvailability.unavailable,
    );
    expect(c.confirmedBooking, isNull);
    c.dispose();
  });
  test(
    'offline failure distinguishes availability from window status',
    () async {
      final repo = testRepository(p)..offline = true;
      final c = controller(repo);
      await c.load();
      expect(c.phase, SchedulePhase.failed);
      expect(c.window, BookingWindowStatus.open);
      repo.offline = false;
      await c.load();
      final slot = c.week!.days.first.slots.first;
      repo.offline = true;
      expect(await c.book(slot), isFalse);
      expect(c.mutationFailure, PianoRoomFailureCode.offline);
      repo.offline = false;
      expect(await c.book(slot), isTrue);
      c.dispose();
    },
  );
  test('refresh retains usable content and reports a stale failure', () async {
    final repo = FailingLoadRepository(testRepository(p));
    final c = controller(repo);
    await c.load();
    final loadedWeek = c.week;
    repo.loadError = const PianoRoomFailure(PianoRoomFailureCode.offline);
    final refresh = c.load();
    expect(c.refreshing, isTrue);
    expect(c.week, same(loadedWeek));
    expect(c.phase, SchedulePhase.ready);
    await refresh;
    expect(c.week, same(loadedWeek));
    expect(c.hasStaleData, isTrue);
    expect(c.loadFailure, PianoRoomFailureCode.offline);
    c.dispose();
  });
  test(
    'unexpected load and mutation exceptions become safe failures',
    () async {
      final repo = FailingLoadRepository(testRepository(p))
        ..loadError = StateError('sensitive backend detail');
      final c = controller(repo);
      await c.load();
      expect(c.phase, SchedulePhase.failed);
      expect(c.loadFailure, PianoRoomFailureCode.unavailable);
      repo.loadError = null;
      await c.load();
      repo.bookError = StateError('mutation detail');
      expect(await c.book(c.week!.days.first.slots.first), isFalse);
      expect(c.mutationFailure, PianoRoomFailureCode.unavailable);
      repo.bookError = null;
      repo.loadError = StateError('refresh detail');
      expect(await c.book(c.week!.days.first.slots.first), isTrue);
      expect(c.confirmedBooking, isNotNull);
      expect(c.hasStaleData, isTrue);
      expect(c.loadFailure, PianoRoomFailureCode.unavailable);
      c.dispose();
    },
  );
  test(
    'rapid navigation serializes loads and fetches only the latest week',
    () async {
      final repo = DelayedRepository();
      final c = controller(repo);
      final initialMonday = c.selectedWeek;
      final initial = c.load();
      final next = c.moveWeek(1);
      final back = c.moveWeek(-1);
      expect(c.selectedWeek, initialMonday);
      expect(repo.loads, hasLength(1));
      expect(repo.maxActiveLoads, 1);
      repo.loads.first.complete(
        p.schedule(
          monday: initialMonday,
          now: now,
          studentId: student.studentId,
          bookings: [],
          effectiveLimit: 2,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(repo.loads, hasLength(2));
      expect(repo.maxActiveLoads, 1);
      repo.loads.last.complete(
        p.schedule(
          monday: initialMonday,
          now: now,
          studentId: student.studentId,
          bookings: [],
          effectiveLimit: 2,
        ),
      );
      await Future.wait([initial, next, back]);
      expect(c.week!.monday, initialMonday);
      expect(repo.maxActiveLoads, 1);
      c.dispose();
    },
  );
  test(
    'changing weeks discards older responses and preserves selected weekday',
    () async {
      final repo = DelayedRepository();
      final c = controller(repo);
      final first = c.load();
      c.selectDay(3);
      c.selectDay(3);
      c.selectDay(-1);
      final second = c.moveWeek(1);
      final selected = c.selectedWeek;
      repo.loads[0].complete(
        p.schedule(
          monday: p.shiftDays(selected, -7),
          now: now,
          studentId: student.studentId,
          bookings: [],
          effectiveLimit: 2,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      final current = p.schedule(
        monday: selected,
        now: now,
        studentId: student.studentId,
        bookings: [],
        effectiveLimit: 2,
      );
      repo.loads[1].complete(current);
      await second;
      await first;
      expect(c.week!.monday, selected);
      expect(c.selectedDay, 3);
      expect(c.phase, SchedulePhase.ready);
      await c.moveWeek(0);
      c.dispose();
    },
  );
  test(
    'disposed session cannot publish a late response into another session',
    () async {
      final delayed = DelayedRepository();
      final old = controller(delayed);
      final pending = old.load();
      old.dispose();
      final fresh = controller(testRepository(p));
      await fresh.load();
      delayed.loads.single.complete(
        p.schedule(
          monday: old.selectedWeek,
          now: now,
          studentId: student.studentId,
          bookings: [testBooking(p)],
          effectiveLimit: 2,
        ),
      );
      await pending;
      expect(fresh.week!.bookings, isEmpty);
      fresh.dispose();
    },
  );
  test(
    'previous and next week navigation produce correct window and empty state',
    () async {
      final repo = testRepository(p);
      final c = controller(repo);
      await c.load();
      final initial = c.selectedWeek;
      await c.moveWeek(-1);
      expect(c.window, BookingWindowStatus.closed);
      await c.moveWeek(2);
      expect(c.selectedWeek, p.shiftDays(initial, 7));
      expect(c.window, BookingWindowStatus.upcoming);
      repo.emptySchedule = true;
      await c.load();
      expect(c.phase, SchedulePhase.empty);
      c.dispose();
    },
  );
  test('late mutation cannot overwrite a newly selected week', () async {
    final repo = DelayedMutationRepository(testRepository(p));
    final c = controller(repo);
    await c.load();
    final slot = c.week!.days.first.slots.first;
    final mutation = c.book(slot);
    expect(c.submitting, isTrue);
    expect(await c.book(slot), isFalse);
    await c.moveWeek(1);
    final selected = c.selectedWeek;
    repo.commit.complete();
    expect(await mutation, isFalse);
    expect(c.week!.monday, selected);
    expect(c.confirmedBooking, isNull);
    expect(c.week!.quota.booked, 0);
    await c.moveWeek(-1);
    expect(c.week!.quota.booked, 1);
    c.dispose();
  });
  test(
    'disposing during a mutation discards its presentation outcome',
    () async {
      final repo = DelayedMutationRepository(testRepository(p));
      final c = controller(repo);
      await c.load();
      final pending = c.book(c.week!.days.first.slots.first);
      c.dispose();
      repo.commit.complete();
      expect(await pending, isFalse);
    },
  );
}
