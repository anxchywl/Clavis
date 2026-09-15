import 'dart:math';

import 'package:flutter/foundation.dart';

import '../domain/piano_room_failure.dart';
import '../domain/piano_room_models.dart';
import '../domain/piano_room_policy.dart';
import '../domain/piano_room_repository.dart';
import '../domain/piano_room_snapshot_validator.dart';

enum SchedulePhase { loading, ready, empty, failed }

class PianoRoomController extends ChangeNotifier {
  PianoRoomController({
    required this.repository,
    required this.policy,
    required this.session,
    required this.now,
  }) : selectedWeek = policy.initialWeek(now());

  final PianoRoomRepository repository;
  final PianoRoomPolicy policy;
  final PianoRoomSession session;
  final DateTime Function() now;

  DateTime selectedWeek;
  int selectedDay = 0;
  PianoRoomWeek? week;
  SchedulePhase phase = SchedulePhase.loading;
  PianoRoomFailureCode? loadFailure;
  PianoRoomFailureCode? mutationFailure;
  PianoRoomBooking? confirmedBooking;
  bool submitting = false;
  bool refreshing = false;

  int _generation = 0;
  bool _disposed = false;
  bool _loadRunning = false;
  bool _loadQueued = false;
  DateTime? _loadingWeek;
  Future<void>? _loadCycle;
  final Map<String, String> _requests = {};

  BookingWindowStatus get window => policy.window(selectedWeek, now());
  bool get hasStaleData => week != null && loadFailure != null;

  bool eligible(PianoRoomSlot slot) =>
      phase == SchedulePhase.ready &&
      !submitting &&
      slot.isEligible &&
      slot.start.isAfter(now()) &&
      window == BookingWindowStatus.open;

  bool canRelease(PianoRoomBooking booking) =>
      !submitting &&
      phase == SchedulePhase.ready &&
      policy.canRelease(booking, session.studentId, now());

  void selectDay(int index) {
    if (index < 0 || index > 6 || index == selectedDay) return;
    selectedDay = index;
    notifyListeners();
  }

  Future<void> moveWeek(int offset) async {
    if (offset == 0 || _disposed) return;
    selectedWeek = policy.shiftDays(selectedWeek, offset * 7);
    _generation++;
    confirmedBooking = null;
    mutationFailure = null;
    await load(preserveData: false);
  }

  Future<void> load({bool preserveData = true}) {
    if (_disposed) return Future.value();
    final hasSelectedWeek = week?.monday == selectedWeek;
    if (preserveData && hasSelectedWeek) {
      refreshing = true;
      loadFailure = null;
    } else {
      week = null;
      phase = SchedulePhase.loading;
      loadFailure = null;
      refreshing = false;
    }
    notifyListeners();

    if (_loadRunning) {
      if (_loadingWeek != selectedWeek) _loadQueued = true;
      return _loadCycle!;
    }

    late final Future<void> cycle;
    cycle = _runLoadCycle().whenComplete(() {
      if (identical(_loadCycle, cycle)) _loadCycle = null;
    });
    _loadCycle = cycle;
    return cycle;
  }

  Future<void> _runLoadCycle() async {
    _loadRunning = true;
    try {
      do {
        _loadQueued = false;
        final monday = selectedWeek;
        _loadingWeek = monday;
        await _loadWeek(monday);
      } while (!_disposed && (_loadQueued || _loadingWeek != selectedWeek));
    } finally {
      _loadRunning = false;
      _loadingWeek = null;
    }
  }

  Future<void> _loadWeek(DateTime monday) async {
    try {
      final result = await repository.loadWeek(monday);
      validatePianoRoomWeek(
        result,
        requestedMonday: monday,
        studentId: session.studentId,
        policy: policy,
      );
      if (_disposed || monday != selectedWeek) return;
      week = result;
      phase = result.days.isEmpty ? SchedulePhase.empty : SchedulePhase.ready;
      loadFailure = null;
    } on PianoRoomFailure catch (failure) {
      _applyLoadFailure(monday, failure.code);
    } catch (_) {
      _applyLoadFailure(monday, PianoRoomFailureCode.unavailable);
    }
    if (!_disposed && monday == selectedWeek) {
      refreshing = false;
      notifyListeners();
    }
  }

  void _applyLoadFailure(DateTime monday, PianoRoomFailureCode code) {
    if (_disposed || monday != selectedWeek) return;
    loadFailure = code;
    refreshing = false;
    if (week?.monday != monday) {
      week = null;
      phase = SchedulePhase.failed;
    }
  }

  void timeChanged() {
    if (!_disposed) notifyListeners();
  }

  int projectedBooked(String slotId) => week!.quota.afterBooking(
    alreadyCounted: week!.bookings.any(
      (booking) =>
          booking.slotId == slotId && policy.countsTowardQuota(booking.status),
    ),
  );

  bool get canRetryMutation =>
      mutationFailure == null ||
      mutationFailure == PianoRoomFailureCode.offline;

  void clearOutcome() {
    mutationFailure = null;
    confirmedBooking = null;
  }

  Future<bool> book(PianoRoomSlot slot) async {
    if (submitting || _disposed) return false;
    final request = _requests.putIfAbsent(
      slot.id,
      () => List.generate(
        24,
        (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join(),
    );
    return _mutate(() => repository.book(slotId: slot.id, requestId: request));
  }

  Future<bool> release(PianoRoomBooking booking) => _mutate(() async {
    await repository.release(booking.id);
    _requests.remove(booking.slotId);
    return null;
  });

  Future<bool> _mutate(Future<PianoRoomBooking?> Function() operation) async {
    if (submitting || _disposed) return false;
    final generation = _generation;
    submitting = true;
    clearOutcome();
    notifyListeners();
    var succeeded = false;
    try {
      final booking = await operation();
      if (_disposed || generation != _generation) return false;
      confirmedBooking = booking;
      succeeded = true;
    } on PianoRoomFailure catch (failure) {
      if (!_disposed && generation == _generation) {
        mutationFailure = failure.code;
      }
    } catch (_) {
      if (!_disposed && generation == _generation) {
        mutationFailure = PianoRoomFailureCode.unavailable;
      }
    } finally {
      if (!_disposed) {
        submitting = false;
        if (generation == _generation) {
          await load();
        } else {
          notifyListeners();
        }
      }
    }
    return succeeded && !_disposed && generation == _generation;
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
