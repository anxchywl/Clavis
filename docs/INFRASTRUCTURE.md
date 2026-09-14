# Development and verification

This repository was tested with Flutter 3.38.5 and Dart 3.10.4. It needs no service, database, or credential.

## Run the demo

```sh
cd piano_room_feature
flutter pub get
flutter gen-l10n
cd ../piano_room_app
flutter pub get
flutter run -d chrome
```

Standalone access works only in debug mode. Set `ENABLE_DEV_ACCESS=false` to close it in debug. Profile and release builds always show the localized closed screen.

Use `PIANO_LOCALE=en`, `ru`, or `kk` to set the language. Without it, the app uses the device locale and falls back to English.

Use `PIANO_SCENARIO` with one of these values:

`normal`, `offline`, `conflict`, `penalty`, `empty`, `closed`, `upcoming`, `dropped`, `noShow`

Unknown values fail instead of loading a default fixture. The demo banner shows the fixed time and explains that data resets on restart.

## Verify changes

From the repository root:

```sh
./scripts/verify.sh
cd piano_room_app
flutter build web --debug
flutter build apk --debug
```

The verification script generates localization files, checks formatting, analyzes all packages, runs all tests, checks layer boundaries, and requires at least 85 percent feature line coverage. Web and Android builds are separate checks.

Tests cover policy boundaries, privacy, idempotency, conflicts, stale data, lifecycle changes, responsive layouts, large text, light and dark themes, all locales, labels, contrast, and Android and iOS target sizes.

These tests do not replace a physical-device profile run or a manual TalkBack and VoiceOver review. A production host should measure cold start, first schedule display, navigation, scrolling, booking, refresh, frame timing, jank, and memory in profile mode.

`google_fonts` was removed because it was unused. `lucide_flutter` 1.42.0 can be upgraded to 1.47.0, but it was left unchanged because no compatibility need was found. Other package upgrades should be reviewed instead of applied automatically.
