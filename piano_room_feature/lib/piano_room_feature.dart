library;

import 'dart:async';
import 'package:flutter/widgets.dart';
import 'src/application/piano_room_controller.dart';
import 'src/application/piano_room_scope.dart';
import 'src/domain/piano_room_models.dart';
import 'src/domain/piano_room_policy.dart';
import 'src/domain/piano_room_repository.dart';
import 'src/l10n/piano_room_strings.dart';
import 'src/presentation/piano_room_screen.dart';

export 'src/domain/piano_room_models.dart';
export 'src/domain/piano_room_policy.dart';
export 'src/domain/piano_room_repository.dart';
export 'src/l10n/piano_room_strings.dart';

class PianoRoomFeature extends StatefulWidget {
  const PianoRoomFeature({
    super.key,
    required this.session,
    required this.repository,
    required this.policy,
    required this.now,
    this.refreshInterval = const Duration(seconds: 30),
  });
  final PianoRoomSession session;
  final PianoRoomRepository repository;
  final PianoRoomPolicy policy;
  final DateTime Function() now;
  final Duration refreshInterval;
  @override
  State<PianoRoomFeature> createState() => _PianoRoomFeatureState();
}

class _PianoRoomFeatureState extends State<PianoRoomFeature>
    with WidgetsBindingObserver {
  late PianoRoomController _controller;
  Timer? _timer;
  DateTime? _lastTick;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _create();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(widget.refreshInterval, (_) => _tick());
  }

  void _tick({bool resumed = false}) {
    final instant = widget.now();
    if (!resumed && instant == _lastTick) return;
    _lastTick = instant;
    if (_controller.submitting || _controller.phase == SchedulePhase.loading) {
      return;
    }
    if (resumed ||
        (_controller.window == BookingWindowStatus.open &&
            !_controller.hasStaleData)) {
      unawaited(_controller.load());
    } else {
      _controller.timeChanged();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startTimer();
      _tick(resumed: true);
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _create() {
    _lastTick = widget.now();
    _controller = PianoRoomController(
      repository: widget.repository,
      policy: widget.policy,
      session: widget.session,
      now: widget.now,
    );
    unawaited(_controller.load());
  }

  @override
  void didUpdateWidget(PianoRoomFeature oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.studentId != widget.session.studentId ||
        oldWidget.repository != widget.repository ||
        oldWidget.policy != widget.policy) {
      _controller.dispose();
      _create();
    }
    if (oldWidget.refreshInterval != widget.refreshInterval) _startTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PianoRoomStringsScope(
    child: PianoRoomScope(
      key: ValueKey(widget.session.studentId),
      controller: _controller,
      child: Navigator(
        key: ObjectKey(_controller),
        onGenerateRoute: (_) => PageRouteBuilder<void>(
          pageBuilder: (context, animation, secondaryAnimation) =>
              const PianoRoomScreen(),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        ),
      ),
    ),
  );
}
