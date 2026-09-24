import 'package:app_ui/app_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:piano_room_feature/piano_room_feature.dart';
import 'package:piano_room_feature/piano_room_development.dart';
import 'package:piano_room_feature/piano_room_remote.dart';

bool developmentAccessAllowed({required bool debug, required bool requested}) =>
    debug && requested;

const String productionApiBaseUrl = 'https://clavis.anxchywl.dev';

// sample runs on fixtures in memory; remote talks to production unless a base
// url names another backend, and its token comes from the developer, never
// from a sign-in this host does not have
@visibleForTesting
PianoRoomRemote? resolveRemote({
  required String backend,
  required String apiBaseUrl,
  required String accessToken,
  required String studentId,
  required bool debug,
}) {
  switch (backend) {
    case 'sample':
      return null;
    case 'remote':
      final uri = Uri.tryParse(
        apiBaseUrl.isEmpty ? productionApiBaseUrl : apiBaseUrl,
      );
      if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
        throw ArgumentError.value(apiBaseUrl, 'PIANO_API_BASE_URL');
      }
      // plain http is for a backend on this machine, from a debug build only
      return PianoRoomRemote(
        baseUri: uri,
        accessToken: accessToken,
        studentId: studentId,
        allowInsecure: debug,
      );
    default:
      // a mistyped define must not quietly fall back to sample data
      throw ArgumentError.value(backend, 'PIANO_BACKEND');
  }
}

void main() => runApp(const PianoRoomApp());

class PianoRoomApp extends StatefulWidget {
  const PianoRoomApp({super.key});
  @override
  State<PianoRoomApp> createState() => _PianoRoomAppState();
}

class _PianoRoomAppState extends State<PianoRoomApp> {
  late final PianoRoomSample sample = PianoRoomSample(
    scenario: SampleScenario.values.firstWhere(
      (value) =>
          value.name ==
          const String.fromEnvironment(
            'PIANO_SCENARIO',
            defaultValue: 'normal',
          ),
    ),
  );
  PianoRoomRemote? _remote;
  Future<void>? _clock;
  bool _misconfigured = false;

  @override
  void initState() {
    super.initState();
    try {
      _remote = resolveRemote(
        backend: const String.fromEnvironment(
          'PIANO_BACKEND',
          defaultValue: 'sample',
        ),
        apiBaseUrl: const String.fromEnvironment('PIANO_API_BASE_URL'),
        accessToken: const String.fromEnvironment('PIANO_ACCESS_TOKEN'),
        studentId: const String.fromEnvironment('PIANO_STUDENT_ID'),
        debug: kDebugMode,
      );
    } on ArgumentError {
      _misconfigured = true;
    }
    // the first week shown depends on the time, so ask the server first; a
    // failure still mounts the feature, which then reports it
    _clock = _remote?.repository.synchronizeClock().catchError((Object _) {});
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    onGenerateTitle: (context) => PianoRoomLocalizations.of(context).title,
    theme: AppTheme.lightTheme,
    darkTheme: AppTheme.darkTheme,
    locale: const String.fromEnvironment('PIANO_LOCALE').isEmpty
        ? null
        : Locale(const String.fromEnvironment('PIANO_LOCALE')),
    localizationsDelegates: PianoRoomLocalizations.localizationsDelegates,
    supportedLocales: PianoRoomLocalizations.supportedLocales,
    home: Builder(
      builder: (context) {
        final strings = PianoRoomLocalizations.of(context);
        if (!developmentAccessAllowed(
          debug: kDebugMode,
          requested: const bool.fromEnvironment(
            'ENABLE_DEV_ACCESS',
            defaultValue: true,
          ),
        )) {
          return _Closed(strings.developmentClosed);
        }
        if (_misconfigured) return _Closed(strings.developmentMisconfigured);
        final remote = _remote;
        if (remote == null) {
          return PianoRoomFeature(
            session: sample.session,
            repository: sample.repository,
            policy: sample.policy,
            now: () => sample.instant,
          );
        }
        return FutureBuilder<void>(
          future: _clock,
          builder: (context, snapshot) =>
              snapshot.connectionState != ConnectionState.done
              ? const Scaffold()
              : PianoRoomFeature(
                  session: remote.session,
                  repository: remote.repository,
                  policy: remote.policy,
                  now: remote.now,
                ),
        );
      },
    ),
  );
}

class _Closed extends StatelessWidget {
  const _Closed(this.message);
  final String message;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: Padding(padding: AppSpacing.screenPadding, child: Text(message)),
      ),
    ),
  );
}
