import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

Iterable<File> sources(String directory) => Directory(directory)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'));
void main() {
  test('layers enforce one-way dependencies for imports and exports', () {
    for (final layer in ['domain', 'application', 'presentation']) {
      for (final file in sources('lib/src/$layer')) {
        final directives = file.readAsLinesSync().where(
          (line) => RegExp(r'^\s*(import|export|part) ').hasMatch(line),
        );
        for (final line in directives) {
          if (layer != 'domain') {
            expect(line, isNot(contains('/data/')), reason: file.path);
          }
          if (layer == 'domain') {
            for (final forbidden in [
              'flutter',
              'app_ui',
              'dart:io',
              'http',
              'shared_preferences',
              '/application/',
              '/data/',
              '/presentation/',
            ]) {
              expect(line, isNot(contains(forbidden)), reason: file.path);
            }
          }
        }
      }
    }
  });
  test(
    'feature UI has no raw styles colors spacing or literal display text',
    () {
      for (final file in sources('lib/src/presentation')) {
        final text = file.readAsStringSync();
        for (final pattern in [
          r'TextStyle\(',
          r'Color\(',
          // material colours are banned, the kit's AppColors tokens are not
          r'(?<!App)Colors\.',
          r'EdgeInsets\.[a-zA-Z]+\(\s*\d',
          r'SizedBox\((?:height|width):\s*\d',
          r"(?:Text|SelectableText)\(\s*'[A-Za-z]",
        ]) {
          expect(
            RegExp(pattern).hasMatch(text),
            isFalse,
            reason: '${file.path}: $pattern',
          );
        }
      }
    },
  );
  test('three locales have matching message keys', () {
    Set<String> keys(String locale) =>
        (jsonDecode(File('lib/src/l10n/arb/app_$locale.arb').readAsStringSync())
                as Map<String, dynamic>)
            .keys
            .where((key) => !key.startsWith('@'))
            .toSet();
    expect(keys('ru'), keys('en'));
    expect(keys('kk'), keys('en'));
  });
}
