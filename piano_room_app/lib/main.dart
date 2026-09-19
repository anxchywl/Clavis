import 'package:app_ui/app_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:piano_room_feature/piano_room_feature.dart';
import 'package:piano_room_feature/piano_room_development.dart';

bool developmentAccessAllowed({required bool debug, required bool requested}) =>
    debug && requested;

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
        if (!developmentAccessAllowed(
          debug: kDebugMode,
          requested: const bool.fromEnvironment(
            'ENABLE_DEV_ACCESS',
            defaultValue: true,
          ),
        )) {
          return Scaffold(
            body: SafeArea(
              child: Center(
                child: Padding(
                  padding: AppSpacing.screenPadding,
                  child: Text(
                    PianoRoomLocalizations.of(context).developmentClosed,
                  ),
                ),
              ),
            ),
          );
        }
        return PianoRoomFeature(
          session: sample.session,
          repository: sample.repository,
          policy: sample.policy,
          now: () => sample.instant,
        );
      },
    ),
  );
}
