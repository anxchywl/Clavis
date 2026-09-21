import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../domain/piano_room_failure.dart';
import '../domain/piano_room_models.dart';
import '../domain/piano_room_policy.dart';
import '../domain/piano_room_repository.dart';
import '../domain/piano_room_snapshot_validator.dart';

// hosts a debug build may reach over plain http: this machine, and this
// machine as the android emulator sees it
const Set<String> loopbackHosts = {'localhost', '127.0.0.1', '::1', '10.0.2.2'};

class HttpPianoRoomRepository implements PianoRoomRepository {
  HttpPianoRoomRepository({
    required this.baseUri,
    required this.accessToken,
    required this.policy,
    required this.session,
    http.Client? client,
    DateTime Function()? deviceNow,
    this.timeout = const Duration(seconds: 15),
  }) : _client = client ?? http.Client(),
       _deviceNow = deviceNow ?? DateTime.now;
  final Uri baseUri;
  final String accessToken;
  final PianoRoomPolicy policy;
  final PianoRoomSession session;
  final Duration timeout;
  final http.Client _client;
  final DateTime Function() _deviceNow;
  Duration _offset = Duration.zero;

  // the server decides every rule; the device clock only moves the ui between
  // responses, corrected by the offset the last response revealed
  DateTime now() => policy.local(_deviceNow().add(_offset));

  Future<void> synchronizeClock() async {
    await _send('GET', 'api/v1/clock');
  }

  @override
  Future<PianoRoomWeek> loadWeek(DateTime monday) async {
    final start = policy.mondayOf(monday);
    final data = await _send('GET', 'api/v1/weeks/${_day(start)}');
    final week = _parse(() => _week(data));
    validatePianoRoomWeek(
      week,
      requestedMonday: monday,
      studentId: session.studentId,
      policy: policy,
    );
    return week;
  }

  @override
  Future<PianoRoomBooking> book({
    required String slotId,
    required String requestId,
  }) async {
    final data = await _send(
      'POST',
      'api/v1/bookings',
      body: {'slotId': slotId},
      idempotencyKey: requestId,
    );
    final booking = _parse(() => _booking(data));
    if (booking.slotId != slotId) {
      throw const PianoRoomFailure(PianoRoomFailureCode.invalidRequest);
    }
    return booking;
  }

  @override
  Future<void> release(String bookingId) async {
    await _send(
      'POST',
      'api/v1/bookings/${Uri.encodeComponent(bookingId)}/release',
    );
  }

  Future<Object?> _send(
    String method,
    String path, {
    Map<String, Object?>? body,
    String? idempotencyKey,
  }) async {
    final request = http.Request(method, baseUri.resolve(path))
      ..headers.addAll({
        'Authorization': 'Bearer $accessToken',
        'Accept': 'application/json',
        'Idempotency-Key': ?idempotencyKey,
      });
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _client.send(request).timeout(timeout),
      ).timeout(timeout);
    } on http.ClientException {
      throw const PianoRoomFailure(PianoRoomFailureCode.offline);
    } on TimeoutException {
      throw const PianoRoomFailure(PianoRoomFailureCode.offline);
    }
    final decoded = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw PianoRoomFailure(_failureOf(response.statusCode, decoded));
    }
    if (decoded is! Map<String, dynamic>) {
      throw const PianoRoomFailure(PianoRoomFailureCode.unavailable);
    }
    _learnOffset(decoded['meta']);
    return decoded['data'];
  }

  void _learnOffset(Object? meta) {
    if (meta is! Map<String, dynamic>) return;
    final value = meta['server_time'];
    final server = value is String ? DateTime.tryParse(value) : null;
    if (server != null) _offset = server.difference(_deviceNow());
  }

  Object? _decode(String body) {
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }

  // raw server text is never shown; only the code decides which message the
  // ui picks, and an unknown code is a generic failure
  PianoRoomFailureCode _failureOf(int status, Object? decoded) {
    final error = decoded is Map<String, dynamic> ? decoded['error'] : null;
    final code = error is Map<String, dynamic> ? error['code'] : null;
    return switch (code) {
      'slot_taken' => PianoRoomFailureCode.conflict,
      'quota_exceeded' => PianoRoomFailureCode.quota,
      'booking_window_closed' => PianoRoomFailureCode.windowClosed,
      'slot_in_past' => PianoRoomFailureCode.past,
      'release_deadline_passed' => PianoRoomFailureCode.releaseDeadline,
      'booking_not_confirmed' ||
      'idempotency_key_reused' ||
      'idempotency_key_invalid' ||
      'slot_invalid' ||
      'week_invalid' ||
      'request_validation_failed' => PianoRoomFailureCode.invalidRequest,
      _ =>
        status == 502 || status == 503 || status == 504
            ? PianoRoomFailureCode.offline
            : PianoRoomFailureCode.unavailable,
    };
  }

  T _parse<T>(T Function() read) {
    try {
      return read();
    } on PianoRoomFailure {
      rethrow;
    } catch (_) {
      throw const PianoRoomFailure(PianoRoomFailureCode.unavailable);
    }
  }

  String _day(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  DateTime _date(Object? value) {
    final parsed = DateTime.parse(value as String);
    return policy.date(parsed.year, parsed.month, parsed.day);
  }

  DateTime _instant(Object? value) =>
      policy.local(DateTime.parse(value as String));

  PianoRoomWeek _week(Object? data) {
    final map = data as Map<String, dynamic>;
    if (map['timezone'] != policy.timezone) {
      throw const PianoRoomFailure(PianoRoomFailureCode.invalidRequest);
    }
    final quota = map['quota'] as Map<String, dynamic>;
    return PianoRoomWeek(
      monday: _date(map['monday']),
      window: switch (map['window']) {
        'upcoming' => BookingWindowStatus.upcoming,
        'open' => BookingWindowStatus.open,
        'closed' => BookingWindowStatus.closed,
        _ => BookingWindowStatus.unavailable,
      },
      quota: WeeklyQuota(
        booked: quota['booked'] as int,
        limit: quota['limit'] as int,
        defaultLimit: quota['defaultLimit'] as int,
      ),
      days: [for (final day in map['days'] as List<dynamic>) _dayOf(day)],
      bookings: [
        for (final booking in map['bookings'] as List<dynamic>)
          _booking(booking),
      ],
    );
  }

  PianoRoomDay _dayOf(Object? value) {
    final map = value as Map<String, dynamic>;
    final date = _date(map['date']);
    return PianoRoomDay(
      date: date,
      slots: [
        for (final slot in map['slots'] as List<dynamic>)
          _slot(slot as Map<String, dynamic>, date),
      ],
    );
  }

  PianoRoomSlot _slot(Map<String, dynamic> map, DateTime date) => PianoRoomSlot(
    id: map['id'] as String,
    localDate: date,
    start: _instant(map['start']),
    end: _instant(map['end']),
    timezone: policy.timezone,
    availability: switch (map['availability']) {
      'available' => SlotAvailability.available,
      'own' => SlotAvailability.own,
      _ => SlotAvailability.unavailable,
    },
    isEligible: map['eligible'] as bool,
    bookingId: map['bookingId'] as String?,
  );

  // the server lists only this student's bookings, so ownership is the session's
  PianoRoomBooking _booking(Object? value) {
    final map = value as Map<String, dynamic>;
    return PianoRoomBooking(
      id: map['id'] as String,
      slotId: map['slotId'] as String,
      studentId: session.studentId,
      start: _instant(map['start']),
      end: _instant(map['end']),
      status: switch (map['status']) {
        'confirmed' => BookingStatus.confirmed,
        'released' => BookingStatus.released,
        'completed' => BookingStatus.completed,
        'dropped' => BookingStatus.dropped,
        'no_show' => BookingStatus.noShow,
        _ => throw const PianoRoomFailure(PianoRoomFailureCode.invalidRequest),
      },
    );
  }
}

// the dependencies a host needs to mount the feature against the service
class PianoRoomRemote {
  PianoRoomRemote({
    required Uri baseUri,
    required String accessToken,
    required String studentId,
    bool allowInsecure = false,
    http.Client? client,
    DateTime Function()? deviceNow,
  }) {
    if (baseUri.scheme != 'https' &&
        !(allowInsecure &&
            baseUri.scheme == 'http' &&
            loopbackHosts.contains(baseUri.host))) {
      throw ArgumentError.value(baseUri, 'baseUri', 'must use HTTPS');
    }
    if (accessToken.isEmpty || studentId.isEmpty) {
      throw ArgumentError('an access token and a student id are required');
    }
    tzdata.initializeTimeZones();
    policy = PianoRoomPolicy(location: tz.getLocation('Asia/Almaty'));
    session = PianoRoomSession(studentId: studentId, displayName: studentId);
    repository = HttpPianoRoomRepository(
      // a base without a trailing slash would lose its last segment on resolve
      baseUri: baseUri.path.endsWith('/')
          ? baseUri
          : baseUri.replace(path: '${baseUri.path}/'),
      accessToken: accessToken,
      policy: policy,
      session: session,
      client: client,
      deviceNow: deviceNow,
    );
  }
  late final PianoRoomPolicy policy;
  late final PianoRoomSession session;
  late final HttpPianoRoomRepository repository;
  DateTime now() => repository.now();
}
