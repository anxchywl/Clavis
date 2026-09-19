import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:piano_room_app/main.dart';

void main() {
  test('release builds never allow standalone access', () {
    expect(developmentAccessAllowed(debug: false, requested: true), isFalse);
    expect(developmentAccessAllowed(debug: false, requested: false), isFalse);
    expect(developmentAccessAllowed(debug: true, requested: false), isFalse);
    expect(developmentAccessAllowed(debug: true, requested: true), isTrue);
  });
  testWidgets('development host mounts the localized sample feature', (
    tester,
  ) async {
    await tester.pumpWidget(const PianoRoomApp());
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(find.text('Piano Room'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
