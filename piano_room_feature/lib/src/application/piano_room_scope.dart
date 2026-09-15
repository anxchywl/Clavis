import 'package:flutter/widgets.dart';
import 'piano_room_controller.dart';

class PianoRoomScope extends InheritedWidget {
  const PianoRoomScope({
    super.key,
    required this.controller,
    required super.child,
  });
  final PianoRoomController controller;
  static PianoRoomController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PianoRoomScope>()!.controller;
  @override
  bool updateShouldNotify(PianoRoomScope oldWidget) =>
      controller != oldWidget.controller;
}
