import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets('a loading primary button still says what it is doing', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(AppPrimaryButton(text: 'Saving', isLoading: true, onPressed: () {})),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    // a spinner alone leaves the control with no accessible name
    expect(find.text('Saving'), findsOneWidget);
  });

  testWidgets('a loading secondary button still says what it is doing', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        AppSecondaryButton(text: 'Reading', isLoading: true, onPressed: () {}),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Reading'), findsOneWidget);
  });

  testWidgets('a loading button refuses the tap it is already serving', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      host(
        AppSecondaryButton(
          text: 'Reading',
          isLoading: true,
          onPressed: () => taps++,
        ),
      ),
    );

    await tester.tap(find.text('Reading'), warnIfMissed: false);
    await tester.pump();

    expect(taps, 0);
  });

  testWidgets('a button that is not loading shows no spinner', (tester) async {
    await tester.pumpWidget(
      host(AppSecondaryButton(text: 'Fill in', onPressed: () {})),
    );

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Fill in'), findsOneWidget);
  });
}
