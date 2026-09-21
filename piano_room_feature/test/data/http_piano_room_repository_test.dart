import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:piano_room_feature/piano_room_feature.dart';
import 'package:piano_room_feature/piano_room_remote.dart';
import 'package:piano_room_feature/src/domain/piano_room_failure.dart';

import '../support.dart';

typedef Handler = FutureOr<http.Response> Function(http.Request request);

// answers each request from a handler and keeps what it was sent
class FakeClient extends http.BaseClient {
  FakeClient(this.handler);
  Handler handler;
  final List<http.Request> sent = [];
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final captured = request as http.Request;
    sent.add(captured);
    final response = await handler(captured);
    return http.StreamedResponse(
      Stream.value(utf8.encode(response.body)),
      response.statusCode,
    );
  }
}

Matcher failure(PianoRoomFailureCode code) =>
    isA<PianoRoomFailure>().having((e) => e.code, 'code', code);

String instant(DateTime value) =>
    value.toUtc().toIso8601String().replaceAll('.000Z', 'Z');

String day(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

const serverTime = '2026-09-20T16:15:00Z';

http.Response ok(Object data, {int status = 200}) => http.Response(
  jsonEncode({
    'data': data,
    'meta': {'request_id': 'r', 'server_time': serverTime},
  }),
  status,
);

http.Response error(int status, String code) => http.Response(
  jsonEncode({
    'error': {'code': code, 'message': 'internal text', 'request_id': 'r'},
  }),
  status,
);

Map<String, Object?> bookingWire(PianoRoomBooking booking) => {
  'id': booking.id,
  'slotId': booking.slotId,
  'start': instant(booking.start),
  'end': instant(booking.end),
  'status': switch (booking.status) {
    BookingStatus.noShow => 'no_show',
    final other => other.name,
  },
};

// the shape the service sends, built from the same rules the client checks
Map<String, Object?> weekWire(PianoRoomWeek week, {String? timezone}) => {
  'monday': day(week.monday),
  'timezone': timezone ?? 'Asia/Almaty',
  'window': week.window.name,
  'quota': {
    'booked': week.quota.booked,
    'limit': week.quota.limit,
    'defaultLimit': week.quota.defaultLimit,
  },
  'days': [
    for (final d in week.days)
      {
        'date': day(d.date),
        'slots': [
          for (final slot in d.slots)
            {
              'id': slot.id,
              'start': instant(slot.start),
              'end': instant(slot.end),
              'availability': slot.availability.name,
              'eligible': slot.isEligible,
              'bookingId': slot.bookingId,
            },
        ],
      },
  ],
  'bookings': [for (final b in week.bookings) bookingWire(b)],
};

void main() {
  final p = testPolicy();
  final monday = p.date(2026, 9, 21);
  final now = p.date(2026, 9, 20, 21, 15);
  String slot(int hour) => p.date(2026, 9, 21, hour).toUtc().toIso8601String();

  PianoRoomWeek sampleWeek({List<PianoRoomBooking> bookings = const []}) =>
      p.schedule(
        monday: monday,
        now: now,
        studentId: student.studentId,
        bookings: bookings,
        effectiveLimit: 2,
      );

  late FakeClient client;
  late DateTime device;
  HttpPianoRoomRepository repository() => HttpPianoRoomRepository(
    baseUri: Uri.parse('https://api.example.edu/'),
    accessToken: 'token-value',
    policy: p,
    session: student,
    client: client,
    deviceNow: () => device,
    timeout: const Duration(milliseconds: 50),
  );

  setUp(() {
    client = FakeClient((_) => ok(weekWire(sampleWeek())));
    device = DateTime.utc(2026, 9, 23, 8);
  });

  test('a week is read, checked and owned by the session', () async {
    final own = testBooking(p, hour: 10);
    final other = testBooking(p, hour: 12, owner: 'someone-else');
    final wire = weekWire(sampleWeek(bookings: [own, other]))
      ..['bookings'] = [bookingWire(own)];
    client.handler = (_) => ok(wire);

    final week = await repository().loadWeek(p.date(2026, 9, 23));

    final request = client.sent.single;
    expect(request.method, 'GET');
    expect(request.url.path, '/api/v1/weeks/2026-09-21');
    expect(request.headers['Authorization'], 'Bearer token-value');
    expect(week.monday, monday);
    expect(week.window, BookingWindowStatus.open);
    expect(week.quota.booked, 1);
    expect(week.bookings.single.studentId, student.studentId);
    final slots = week.days.first.slots;
    expect(slots[1].availability, SlotAvailability.own);
    expect(slots[1].bookingId, own.id);
    expect(slots[3].availability, SlotAvailability.unavailable);
    expect(slots.first.start, p.date(2026, 9, 21, 9));
  });

  test('the ui clock follows the server, not the device', () async {
    final repo = repository();
    expect(repo.now(), p.local(device));
    await repo.synchronizeClock();
    expect(client.sent.single.url.path, '/api/v1/clock');
    expect(repo.now(), p.local(DateTime.parse(serverTime)));
    device = device.add(const Duration(minutes: 5));
    expect(
      repo.now(),
      p.local(DateTime.parse(serverTime)).add(const Duration(minutes: 5)),
    );
  });

  test('booking sends the slot and keeps the request id for retries', () async {
    final booking = testBooking(p, hour: 10);
    client.handler = (_) => ok(bookingWire(booking), status: 201);

    final result = await repository().book(
      slotId: booking.slotId,
      requestId: 'request-key-0001',
    );

    final request = client.sent.single;
    expect(request.url.path, '/api/v1/bookings');
    expect(request.headers['Idempotency-Key'], 'request-key-0001');
    expect(jsonDecode(request.body), {'slotId': booking.slotId});
    expect(result.id, booking.id);
    expect(result.status, BookingStatus.confirmed);
  });

  test('a booking for a slot that was not asked for is refused', () async {
    client.handler = (_) => ok(bookingWire(testBooking(p, hour: 11)));
    await expectLater(
      repository().book(slotId: slot(10), requestId: 'request-key-0001'),
      throwsA(failure(PianoRoomFailureCode.invalidRequest)),
    );
  });

  test('release posts to the booking and escapes its id', () async {
    client.handler = (_) =>
        ok(bookingWire(testBooking(p, status: BookingStatus.released)));
    await repository().release('a/b');
    expect(
      client.sent.single.url.toString(),
      'https://api.example.edu/api/v1/bookings/a%2Fb/release',
    );
  });

  test(
    'server error codes become localized failures, never raw text',
    () async {
      final cases = {
        error(409, 'slot_taken'): PianoRoomFailureCode.conflict,
        error(409, 'quota_exceeded'): PianoRoomFailureCode.quota,
        error(409, 'booking_window_closed'): PianoRoomFailureCode.windowClosed,
        error(409, 'slot_in_past'): PianoRoomFailureCode.past,
        error(409, 'release_deadline_passed'):
            PianoRoomFailureCode.releaseDeadline,
        error(422, 'idempotency_key_reused'):
            PianoRoomFailureCode.invalidRequest,
        error(404, 'booking_not_found'): PianoRoomFailureCode.unavailable,
        error(401, 'token_invalid'): PianoRoomFailureCode.unavailable,
        error(500, 'internal_error'): PianoRoomFailureCode.unavailable,
        http.Response('<html>bad gateway</html>', 502):
            PianoRoomFailureCode.offline,
      };
      for (final entry in cases.entries) {
        client.handler = (_) => entry.key;
        await expectLater(
          repository().book(slotId: slot(10), requestId: 'request-key-0001'),
          throwsA(failure(entry.value)),
          reason: entry.key.body,
        );
      }
    },
  );

  test('a lost connection or a slow server reads as offline', () async {
    client.handler = (_) => throw http.ClientException('connection reset');
    await expectLater(
      repository().loadWeek(monday),
      throwsA(failure(PianoRoomFailureCode.offline)),
    );
    client.handler = (_) => Completer<http.Response>().future;
    await expectLater(
      repository().loadWeek(monday),
      throwsA(failure(PianoRoomFailureCode.offline)),
    );
  });

  test('a response that does not hold together is rejected', () async {
    final leaking = weekWire(
      sampleWeek(bookings: [testBooking(p, hour: 12, owner: 'someone-else')]),
    );
    ((leaking['days'] as List).first['slots'] as List)[3]['bookingId'] =
        'their-booking';
    final responses = {
      http.Response('not json', 200): PianoRoomFailureCode.unavailable,
      ok({'timezone': 'Asia/Almaty', 'monday': 7}):
          PianoRoomFailureCode.unavailable,
      ok(weekWire(sampleWeek(), timezone: 'UTC')):
          PianoRoomFailureCode.invalidRequest,
      ok(leaking): PianoRoomFailureCode.invalidRequest,
    };
    for (final entry in responses.entries) {
      client.handler = (_) => entry.key;
      await expectLater(
        repository().loadWeek(monday),
        throwsA(failure(entry.value)),
      );
    }
    final unknownStatus = bookingWire(testBooking(p, hour: 10))
      ..['status'] = 'teleported';
    client.handler = (_) => ok(unknownStatus);
    await expectLater(
      repository().book(slotId: slot(10), requestId: 'request-key-0001'),
      throwsA(failure(PianoRoomFailureCode.invalidRequest)),
    );
  });

  test('statuses from attendance are read back', () async {
    for (final status in BookingStatus.values) {
      final booking = testBooking(p, hour: 10, status: status);
      client.handler = (_) => ok(bookingWire(booking));
      final result = await repository().book(
        slotId: booking.slotId,
        requestId: 'request-key-0001',
      );
      expect(result.status, status);
    }
  });

  group('remote dependencies', () {
    test('refuse plain http unless it is this machine in debug', () {
      expect(
        () => PianoRoomRemote(
          baseUri: Uri.parse('http://api.example.edu/'),
          accessToken: 't',
          studentId: 's',
          allowInsecure: true,
        ),
        throwsArgumentError,
      );
      expect(
        () => PianoRoomRemote(
          baseUri: Uri.parse('http://127.0.0.1:8000'),
          accessToken: 't',
          studentId: 's',
        ),
        throwsArgumentError,
      );
      expect(
        () => PianoRoomRemote(
          baseUri: Uri.parse('https://api.example.edu/'),
          accessToken: '',
          studentId: 's',
        ),
        throwsArgumentError,
      );
    });

    test('mount against the service under a path prefix', () async {
      final remote = PianoRoomRemote(
        baseUri: Uri.parse('http://127.0.0.1:8000/clavis'),
        accessToken: 'token-value',
        studentId: 'student-a',
        allowInsecure: true,
        client: client,
        deviceNow: () => device,
      );
      await remote.repository.synchronizeClock();
      expect(
        client.sent.single.url.toString(),
        'http://127.0.0.1:8000/clavis/api/v1/clock',
      );
      expect(remote.session.studentId, 'student-a');
      expect(remote.policy.timezone, 'Asia/Almaty');
      expect(remote.now(), p.local(DateTime.parse(serverTime)));
    });
  });
}
