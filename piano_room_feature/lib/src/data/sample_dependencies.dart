import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../domain/piano_room_models.dart';
import '../domain/piano_room_policy.dart';
import 'mock_piano_room_repository.dart';

enum SampleScenario {
  normal,
  offline,
  conflict,
  penalty,
  empty,
  closed,
  upcoming,
  dropped,
  noShow,
}

class PianoRoomSample {
  PianoRoomSample({this.scenario = SampleScenario.normal}) {
    tzdata.initializeTimeZones();
    policy = PianoRoomPolicy(location: tz.getLocation('Asia/Almaty'));
    instant = switch (scenario) {
      SampleScenario.closed ||
      SampleScenario.dropped ||
      SampleScenario.noShow => policy.date(2026, 9, 22, 12),
      SampleScenario.upcoming => policy.date(2026, 9, 20, 20),
      _ => policy.date(2026, 9, 20, 21, 15),
    };
    final monday = policy.date(2026, 9, 21);
    PianoRoomBooking seed(
      String id,
      int day,
      int hour,
      String student, [
      BookingStatus status = BookingStatus.confirmed,
    ]) {
      final start = policy.date(
        monday.year,
        monday.month,
        monday.day + day,
        hour,
      );
      return PianoRoomBooking(
        id: id,
        slotId: start.toUtc().toIso8601String(),
        studentId: student,
        start: start,
        end: start.add(const Duration(hours: 1)),
        status: status,
      );
    }

    repository =
        MockPianoRoomRepository(
            policy: policy,
            session: session,
            now: () => instant,
            effectiveLimit: scenario == SampleScenario.penalty ? 1 : 2,
            seed: [
              seed('sample-own', 0, 10, session.studentId, switch (scenario) {
                SampleScenario.dropped => BookingStatus.dropped,
                SampleScenario.noShow => BookingStatus.noShow,
                _ => BookingStatus.confirmed,
              }),
              seed('sample-other', 0, 12, 'synthetic-other'),
              seed('sample-other-2', 2, 17, 'synthetic-other'),
            ],
          )
          ..offline = scenario == SampleScenario.offline
          ..conflictOnNextBooking = scenario == SampleScenario.conflict
          ..emptySchedule = scenario == SampleScenario.empty;
  }
  final SampleScenario scenario;
  final PianoRoomSession session = const PianoRoomSession(
    studentId: 'piano-development-student',
    displayName: 'Development Student',
    email: 'piano-development@nu.edu.kz',
  );
  late final PianoRoomPolicy policy;
  late final MockPianoRoomRepository repository;
  late final DateTime instant;
}
