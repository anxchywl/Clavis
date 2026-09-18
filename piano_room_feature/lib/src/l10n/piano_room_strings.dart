import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'generated/piano_room_localizations.dart';
export 'generated/piano_room_localizations.dart';

class PianoRoomStringsScope extends StatelessWidget {
  const PianoRoomStringsScope({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final language = Localizations.maybeLocaleOf(context)?.languageCode;
    return Localizations.override(
      context: context,
      locale: Locale({'en', 'ru', 'kk'}.contains(language) ? language! : 'en'),
      delegates: const [
        PianoRoomLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      child: child,
    );
  }
}
