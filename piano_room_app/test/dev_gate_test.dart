import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:piano_room_app/main.dart';
import 'package:piano_room_feature/piano_room_remote.dart';

void main() {
  test('release builds never allow standalone access', () {
    expect(developmentAccessAllowed(debug: false, requested: true), isFalse);
    expect(developmentAccessAllowed(debug: false, requested: false), isFalse);
    expect(developmentAccessAllowed(debug: true, requested: false), isFalse);
    expect(developmentAccessAllowed(debug: true, requested: true), isTrue);
  });
  test('the backend define picks sample or a checked remote', () {
    PianoRoomRemote? resolve(String backend, String url, {bool debug = true}) =>
        resolveRemote(
          backend: backend,
          apiBaseUrl: url,
          accessToken: 'token',
          studentId: 'student-a',
          debug: debug,
        );
    expect(resolve('sample', ''), isNull);
    final remote = resolve('remote', 'http://127.0.0.1:8000');
    expect(remote?.session.studentId, 'student-a');
    expect(resolve('remote', 'https://clavis.example.edu'), isNotNull);
    expect(
      resolve('remote', '')?.repository.baseUri,
      Uri.parse('$productionApiBaseUrl/'),
    );
    expect(() => resolve('remote', 'not a url'), throwsArgumentError);
    expect(
      () => resolve('remote', 'http://127.0.0.1:8000', debug: false),
      throwsArgumentError,
    );
    expect(() => resolve('mock', ''), throwsArgumentError);
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
