import 'dart:ui' show SemanticsAction;
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_room_feature/piano_room_feature.dart';
import 'package:piano_room_feature/src/data/mock_piano_room_repository.dart';
import 'package:piano_room_feature/src/presentation/piano_room_formatting.dart';
import 'package:piano_room_feature/src/domain/piano_room_failure.dart';
import '../support.dart';

class SwitchableRepository implements PianoRoomRepository {
  SwitchableRepository(this.inner);

  final PianoRoomRepository inner;
  PianoRoomFailure? loadFailure;
  bool failLoadsAfterBook = false;
  int loadCount = 0;
  int bookCount = 0;

  @override
  Future<PianoRoomWeek> loadWeek(DateTime monday) {
    loadCount++;
    final failure = loadFailure;
    if (failure != null) return Future.error(failure);
    return inner.loadWeek(monday);
  }

  @override
  Future<PianoRoomBooking> book({
    required String slotId,
    required String requestId,
  }) async {
    bookCount++;
    final booking = await inner.book(slotId: slotId, requestId: requestId);
    if (failLoadsAfterBook) {
      loadFailure = const PianoRoomFailure(PianoRoomFailureCode.offline);
    }
    return booking;
  }

  @override
  Future<void> release(String bookingId) => inner.release(bookingId);
}

void main() {
  final p = testPolicy();
  final now = p.date(2026, 9, 20, 21, 15);
  Widget host(
    PianoRoomRepository repo, {
    Locale locale = const Locale('en'),
    bool dark = false,
    double scale = 1,
    PianoRoomSession session = student,
    DateTime Function()? clock,
    Duration refreshInterval = const Duration(seconds: 30),
  }) => MaterialApp(
    theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
    locale: locale,
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [
      Locale('en'),
      Locale('ru'),
      Locale('kk'),
      Locale('fr'),
    ],
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale), disableAnimations: true),
      child: child!,
    ),
    home: PianoRoomFeature(
      session: session,
      repository: repo,
      policy: p,
      now: clock ?? () => now,
      refreshInterval: refreshInterval,
    ),
  );
  Future<void> stop(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  testWidgets('initial skeleton is decorative with one loading announcement', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final repo = MockPianoRoomRepository(
      policy: p,
      session: student,
      now: () => now,
      latency: const Duration(milliseconds: 200),
    );
    await tester.pumpWidget(host(repo, scale: 2));
    expect(find.byKey(const ValueKey('schedule-skeleton')), findsOneWidget);
    expect(
      find.bySemanticsLabel('Loading the weekly schedule'),
      findsOneWidget,
    );
    expect(find.text('Booking status is unavailable'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
    expect(find.byKey(const ValueKey('schedule-skeleton')), findsNothing);
    semantics.dispose();
    await stop(tester);
  });

  testWidgets(
    'polling retains content and reports a non-blocking stale state',
    (tester) async {
      var clock = now;
      final repo = SwitchableRepository(testRepository(p));
      await tester.pumpWidget(
        host(
          repo,
          clock: () => clock,
          refreshInterval: const Duration(seconds: 1),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('0 of 2 weekly slots used'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Loading the weekly schedule'),
        findsNothing,
      );
      repo.loadFailure = const PianoRoomFailure(PianoRoomFailureCode.offline);
      clock = clock.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(find.text('0 of 2 weekly slots used'), findsOneWidget);
      expect(
        find.textContaining('schedule may be out of date'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('schedule-skeleton')), findsNothing);
      expect(
        find.bySemanticsLabel('Loading the weekly schedule'),
        findsNothing,
      );
      final countAfterFailure = repo.loadCount;
      clock = clock.add(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 2));
      expect(repo.loadCount, countAfterFailure);
      repo.loadFailure = null;
      await tester.tap(find.text('Try again'));
      await tester.pump();
      expect(find.text('0 of 2 weekly slots used'), findsOneWidget);
      await tester.pump();
      expect(find.textContaining('schedule may be out of date'), findsNothing);
      await stop(tester);
    },
  );

  testWidgets('lifecycle pauses polling and refreshes once on resume', (
    tester,
  ) async {
    var clock = now;
    final repo = SwitchableRepository(testRepository(p));
    await tester.pumpWidget(
      host(
        repo,
        clock: () => clock,
        refreshInterval: const Duration(seconds: 1),
      ),
    );
    await tester.pumpAndSettle();
    final initialLoads = repo.loadCount;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    clock = clock.add(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 3));
    expect(repo.loadCount, initialLoads);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();
    expect(repo.loadCount, initialLoads + 1);
    await stop(tester);
  });

  testWidgets('background refresh preserves keyboard focus', (tester) async {
    var clock = now;
    final repo = SwitchableRepository(testRepository(p));
    await tester.pumpWidget(
      host(
        repo,
        clock: () => clock,
        refreshInterval: const Duration(seconds: 1),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final focusBefore = FocusManager.instance.primaryFocus;
    expect(focusBefore, isNotNull);
    clock = clock.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(FocusManager.instance.primaryFocus, same(focusBefore));
    await stop(tester);
  });

  Future<void> showSlot(WidgetTester tester, String time) async {
    await tester.scrollUntilVisible(
      find.text(time),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  for (final width in [320.0, 430.0]) {
    for (final locale in ['en', 'ru', 'kk']) {
      for (final dark in [false, true]) {
        testWidgets(
          'no overflow at $width in $locale dark=$dark with large text',
          (tester) async {
            tester.view.physicalSize = Size(width, 900);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final repo = testRepository(p, seed: [testBooking(p, hour: 10)]);
            await tester.pumpWidget(
              host(repo, locale: Locale(locale), dark: dark, scale: 2),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            for (var i = 0; i < 14; i++) {
              await tester.drag(
                find.byType(ListView).first,
                const Offset(0, -550),
              );
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
            }
            await stop(tester);
          },
        );
      }
    }
  }
  testWidgets('window quota unavailable slots semantics and touch targets', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final repo = testRepository(
      p,
      seed: [testBooking(p, owner: 'other', hour: 10)],
    );
    await tester.pumpWidget(host(repo));
    await tester.pumpAndSettle();
    expect(find.text('Booking is open'), findsOneWidget);
    expect(find.text('0 of 2 weekly slots used'), findsOneWidget);
    expect(find.byTooltip('Previous week'), findsOneWidget);
    expect(find.byTooltip('Next week'), findsOneWidget);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    final dayNode = tester.getSemantics(
      find.bySemanticsLabel('Sep 21, 2026, 12 free slots'),
    );
    expect(dayNode.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    final slotNode = tester.getSemantics(
      find.bySemanticsLabel('Sep 21, 2026, 09:00 - 10:00, Available'),
    );
    expect(slotNode.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    await showSlot(tester, '10:00 - 11:00');
    await tester.tap(find.text('10:00 - 11:00'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm booking'), findsNothing);
    expect(find.text('other'), findsNothing);
    expect(
      find.bySemanticsLabel(RegExp('Sep 21, 2026, 10:00.*Unavailable')),
      findsOneWidget,
    );
    semantics.dispose();
    await stop(tester);
  });
  testWidgets('free slots show only their time but announce their status', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final repo = testRepository(
      p,
      seed: [
        testBooking(p),
        testBooking(p, owner: 'other', hour: 10),
      ],
    );
    await tester.pumpWidget(host(repo));
    await tester.pumpAndSettle();
    expect(find.text('Available'), findsNothing);
    expect(find.text('Your booking'), findsOneWidget);
    expect(find.text('Unavailable'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Sep 21, 2026, 11:00 - 12:00, Available'),
      findsOneWidget,
    );
    semantics.dispose();
    await stop(tester);
  });
  testWidgets(
    'confirmation waits for repository and success includes details',
    (tester) async {
      final repo = MockPianoRoomRepository(
        policy: p,
        session: student,
        now: () => now,
        latency: const Duration(milliseconds: 200),
      );
      await tester.pumpWidget(host(repo));
      expect(find.byKey(const ValueKey('schedule-skeleton')), findsOneWidget);
      expect(find.text('Booking status is unavailable'), findsNothing);
      await tester.pumpAndSettle();
      await showSlot(tester, '09:00 - 10:00');
      await tester.tap(find.text('09:00 - 10:00'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm booking'), findsOneWidget);
      expect(
        find.text('After booking: 1 of 2 weekly slots used.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Book this slot'));
      await tester.pump();
      expect(find.text('Booking confirmed'), findsNothing);
      await tester.pumpAndSettle();
      expect(find.text('Booking confirmed'), findsOneWidget);
      expect(find.text('Monday, September 21'), findsWidgets);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(
        (await tester.runAsync(
          () => repo.loadWeek(p.date(2026, 9, 21)),
        ))!.quota.booked,
        1,
      );
      await stop(tester);
    },
  );
  testWidgets('double tap submits one booking request', (tester) async {
    final repo = SwitchableRepository(
      MockPianoRoomRepository(
        policy: p,
        session: student,
        now: () => now,
        latency: const Duration(milliseconds: 100),
      ),
    );
    await tester.pumpWidget(host(repo));
    await tester.pumpAndSettle();
    await showSlot(tester, '09:00 - 10:00');
    await tester.tap(find.text('09:00 - 10:00'));
    await tester.pumpAndSettle();
    final submit = find.text('Book this slot');
    await tester.tap(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(repo.bookCount, 1);
    expect(find.text('Booking confirmed'), findsOneWidget);
    await stop(tester);
  });
  testWidgets(
    'offline submission retries same request after ambiguous commit',
    (tester) async {
      final repo = testRepository(p)..failAfterNextCommit = true;
      await tester.pumpWidget(host(repo));
      await tester.pumpAndSettle();
      await showSlot(tester, '09:00 - 10:00');
      await tester.tap(find.text('09:00 - 10:00'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Book this slot'));
      await tester.pumpAndSettle();
      expect(find.textContaining('You are offline.'), findsOneWidget);
      await tester.ensureVisible(find.text('Book this slot'));
      await tester.tap(find.text('Book this slot'));
      await tester.pumpAndSettle();
      expect(find.text('Booking confirmed'), findsOneWidget);
      expect(
        (await tester.runAsync(
          () => repo.loadWeek(p.date(2026, 9, 21)),
        ))!.quota.booked,
        1,
      );
      await stop(tester);
    },
  );
  testWidgets('accepted booking stays successful when its refresh fails', (
    tester,
  ) async {
    final repo = SwitchableRepository(testRepository(p))
      ..failLoadsAfterBook = true;
    await tester.pumpWidget(host(repo));
    await tester.pumpAndSettle();
    await showSlot(tester, '09:00 - 10:00');
    await tester.tap(find.text('09:00 - 10:00'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Book this slot'));
    await tester.pumpAndSettle();
    expect(find.text('Booking confirmed'), findsOneWidget);
    expect(find.textContaining('change was accepted'), findsOneWidget);
    expect(find.textContaining('sensitive'), findsNothing);
    await stop(tester);
  });
  testWidgets('conflict refreshes availability and never shows success', (
    tester,
  ) async {
    final repo = testRepository(p)..conflictOnNextBooking = true;
    await tester.pumpWidget(host(repo));
    await tester.pumpAndSettle();
    await showSlot(tester, '09:00 - 10:00');
    await tester.tap(find.text('09:00 - 10:00'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Book this slot'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Someone else booked'), findsOneWidget);
    expect(find.text('Booking confirmed'), findsNothing);
    await tester.ensureVisible(find.text('Cancel'));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Unavailable'), findsWidgets);
    await stop(tester);
  });
  testWidgets('own release flow restores quota and exposes released status', (
    tester,
  ) async {
    final repo = testRepository(p, seed: [testBooking(p)]);
    await tester.pumpWidget(host(repo));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byTooltip('Release slot'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Release slot'));
    await tester.pumpAndSettle();
    expect(find.text('Release this slot?'), findsOneWidget);
    await tester.tap(find.text('Release slot'));
    await tester.pumpAndSettle();
    expect(find.text('Slot released'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    // a released booking leaves the list and gives the quota back
    expect(find.text('My bookings'), findsNothing);
    expect(find.text('0 of 2 weekly slots used'), findsOneWidget);
    await stop(tester);
  });
  testWidgets('empty error retry and penalty outcomes are visible', (
    tester,
  ) async {
    final repo = testRepository(p, limit: 1, seed: [testBooking(p)])
      ..offline = true;
    await tester.pumpWidget(host(repo));
    await tester.pumpAndSettle();
    expect(find.textContaining('You are offline.'), findsOneWidget);
    expect(find.text('Booking status is unavailable'), findsNothing);
    repo.offline = false;
    repo.emptySchedule = true;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(
      find.text('No schedule is available for this week.'),
      findsOneWidget,
    );
    repo.emptySchedule = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Your weekly limit has been reduced.'),
      findsOneWidget,
    );
    await stop(tester);
  });
  testWidgets(
    'account changes and host rebuilds isolate state and locale falls back',
    (tester) async {
      final repo = testRepository(p, seed: [testBooking(p)]);
      await tester.pumpWidget(host(repo, locale: const Locale('fr')));
      await tester.pumpAndSettle();
      expect(find.text('1 of 2 weekly slots used'), findsOneWidget);
      await tester.pumpWidget(host(repo));
      await tester.pumpAndSettle();
      expect(find.text('1 of 2 weekly slots used'), findsOneWidget);
      const other = PianoRoomSession(
        studentId: 'student-b',
        displayName: 'Other',
      );
      final otherRepo = MockPianoRoomRepository(
        policy: p,
        session: other,
        now: () => now,
        latency: Duration.zero,
        seed: [testBooking(p)],
      );
      await tester.pumpWidget(host(otherRepo, session: other));
      await tester.pumpAndSettle();
      expect(find.text('0 of 2 weekly slots used'), findsOneWidget);
      await stop(tester);
    },
  );
  testWidgets('a flick turns the week and booked days are marked', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(host(testRepository(p, seed: [testBooking(p)])));
    await tester.pumpAndSettle();
    final monday = tester
        .getSemantics(find.bySemanticsLabel(RegExp(r'^Sep 21, 2026, \d+ free')))
        .getSemanticsData();
    expect(monday.value, 'Your booking');
    final tuesday = tester
        .getSemantics(find.bySemanticsLabel(RegExp(r'^Sep 22, 2026, \d+ free')))
        .getSemanticsData();
    expect(tuesday.value, isEmpty);
    await tester.fling(
      find.text('Booking is open'),
      const Offset(-300, 0),
      1000,
    );
    await tester.pumpAndSettle();
    expect(find.text('Booking has not opened yet'), findsOneWidget);
    await tester.fling(
      find.text('Booking has not opened yet'),
      const Offset(300, 0),
      1000,
    );
    await tester.pumpAndSettle();
    expect(find.text('Booking is open'), findsOneWidget);
    semantics.dispose();
    await stop(tester);
  });
  testWidgets('week and day controls change schedule', (tester) async {
    await tester.pumpWidget(host(testRepository(p)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Next week'));
    await tester.pumpAndSettle();
    expect(find.text('Booking has not opened yet'), findsOneWidget);
    await tester.tap(find.byTooltip('Previous week'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tue'));
    await tester.pumpAndSettle();
    expect(find.text('Tuesday, September 22'), findsOneWidget);
    await tester.tap(find.byTooltip('Previous week'));
    await tester.pumpAndSettle();
    expect(find.text('Booking is closed'), findsOneWidget);
    await stop(tester);
  });
  testWidgets(
    'mounted screen observes the window opening without closing a sheet',
    (tester) async {
      var clock = p.date(2026, 9, 20, 20, 59);
      final repo = SwitchableRepository(testRepository(p, now: () => clock));
      await tester.pumpWidget(
        host(
          repo,
          clock: () => clock,
          refreshInterval: const Duration(seconds: 1),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Next week'));
      await tester.pumpAndSettle();
      expect(find.text('Booking has not opened yet'), findsOneWidget);
      clock = p.date(2026, 9, 20, 21);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(find.text('Booking is open'), findsOneWidget);
      await showSlot(tester, '09:00 - 10:00');
      await tester.tap(find.text('09:00 - 10:00'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm booking'), findsOneWidget);
      clock = clock.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(find.text('Confirm booking'), findsOneWidget);
      await stop(tester);
    },
  );
  testWidgets('switching account removes an open booking sheet', (
    tester,
  ) async {
    final repo = testRepository(p);
    await tester.pumpWidget(host(repo));
    await tester.pumpAndSettle();
    await showSlot(tester, '09:00 - 10:00');
    await tester.tap(find.text('09:00 - 10:00'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm booking'), findsOneWidget);
    const other = PianoRoomSession(
      studentId: 'student-b',
      displayName: 'Other',
    );
    final next = MockPianoRoomRepository(
      policy: p,
      session: other,
      now: () => now,
      latency: Duration.zero,
    );
    await tester.pumpWidget(host(next, session: other));
    await tester.pumpAndSettle();
    expect(find.text('Confirm booking'), findsNothing);
    expect(find.text('0 of 2 weekly slots used'), findsOneWidget);
    await stop(tester);
  });
  testWidgets('past confirmed booking explains release restriction', (
    tester,
  ) async {
    final later = p.date(2026, 9, 21, 12);
    final repo = testRepository(p, now: () => later, seed: [testBooking(p)]);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: PianoRoomFeature(
          session: student,
          repository: repo,
          policy: p,
          now: () => later,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.textContaining('Release is unavailable'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byTooltip('Release slot'), findsNothing);
    expect(find.textContaining('Release is unavailable'), findsOneWidget);
    await stop(tester);
  });
  testWidgets('confirmation sheet fits a small phone with large Russian text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      host(testRepository(p), locale: const Locale('ru'), scale: 2),
    );
    await tester.pumpAndSettle();
    await showSlot(tester, '09:00 - 10:00');
    await tester.tap(find.text('09:00 - 10:00'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Записаться'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Записаться'));
    await tester.pumpAndSettle();
    expect(find.text('Запись подтверждена'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await stop(tester);
  });
  testWidgets('landscape layout supports large Kazakh text without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(720, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      host(testRepository(p), locale: const Locale('kk'), scale: 2),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(ListView).first, const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await stop(tester);
  });
  test(
    'Russian plural forms and room-local dates are formatted independently of device zone',
    () async {
      final s = await PianoRoomLocalizations.delegate.load(const Locale('ru'));
      expect(s.remaining(1), 'Осталась 1 запись');
      expect(s.remaining(2), 'Осталось 2 записи');
      expect(s.remaining(5), 'Осталось 5 записей');
      expect(s.remaining(0), 'Доступных записей нет');
      final en = await PianoRoomLocalizations.delegate.load(const Locale('en'));
      expect(
        roomDate(en, p.local(DateTime.utc(2026, 9, 20, 19))),
        'Sep 21, 2026',
      );
      for (final status in BookingStatus.values) {
        expect(bookingStatus(en, status), isNotEmpty);
      }
      for (final code in PianoRoomFailureCode.values) {
        expect(failureMessage(en, code), isNotEmpty);
      }
      expect(
        failureMessage(en, PianoRoomFailureCode.conflict, refreshed: false),
        contains('Reconnect'),
      );
    },
  );
}
