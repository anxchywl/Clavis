import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:piano_room_feature/piano_room_feature.dart';
import 'package:piano_room_feature/src/data/mock_piano_room_repository.dart';

PianoRoomPolicy testPolicy() {
  tzdata.initializeTimeZones();
  return PianoRoomPolicy(location: tz.getLocation('Asia/Almaty'));
}

const student = PianoRoomSession(
  studentId: 'student-a',
  displayName: 'Synthetic Student',
);
MockPianoRoomRepository testRepository(
  PianoRoomPolicy policy, {
  DateTime Function()? now,
  int? limit,
  List<PianoRoomBooking> seed = const [],
}) => MockPianoRoomRepository(
  policy: policy,
  session: student,
  now: now ?? () => policy.date(2026, 9, 20, 21, 15),
  latency: Duration.zero,
  effectiveLimit: limit,
  seed: seed,
);
PianoRoomBooking testBooking(
  PianoRoomPolicy policy, {
  BookingStatus status = BookingStatus.confirmed,
  String owner = 'student-a',
  int hour = 9,
}) {
  final start = policy.date(2026, 9, 21, hour);
  return PianoRoomBooking(
    id: 'seed-$hour',
    slotId: start.toUtc().toIso8601String(),
    studentId: owner,
    start: start,
    end: start.add(const Duration(hours: 1)),
    status: status,
  );
}
