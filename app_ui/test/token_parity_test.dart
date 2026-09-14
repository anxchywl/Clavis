import 'dart:io';

import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// drift in the token surface is what made the previous copy diverge unnoticed
List<String> _publicMembersOf(String path) {
  final declaration = RegExp(
    r'static\s+(?:const\s+|final\s+)?[\w<>, ?]+\s+(?:get\s+)?(\w+)',
  );
  return File(path)
      .readAsLinesSync()
      .map((line) => declaration.firstMatch(line)?.group(1))
      .whereType<String>()
      .where((name) => !name.startsWith('_'))
      .toList()
    ..sort();
}

double _contrast(Color foreground, Color background) {
  final one = foreground.computeLuminance();
  final other = background.computeLuminance();
  final lighter = one > other ? one : other;
  final darker = one > other ? other : one;
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  test('spacing scale is the one documented scale', () {
    final spacing = _publicMembersOf('lib/tokens/app_spacing.dart');
    expect(spacing, contains('df'));
    expect(spacing, contains('radiusDf'));
    // a second scale is what the fork removed; it must not come back
    expect(
      File('lib/tokens/app_spacing.dart').readAsStringSync(),
      isNot(contains('HomeSpacing')),
    );
  });

  test('no compatibility aliases in the colour tokens', () {
    final source = File('lib/tokens/app_colors.dart').readAsStringSync();
    expect(source, isNot(contains('backward compatibility')));
    expect(source, isNot(contains('balanceCardBackground')));
  });

  test('kit carries no product concepts', () {
    final forbidden = [
      'bank',
      'job',
      'premium',
      'reward',
      'level_ring',
      'gpa',
      'gradus',
      'course',
      'grade',
      'transcript',
    ];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    for (final file in files) {
      final name = file.path.toLowerCase();
      for (final word in forbidden) {
        expect(
          name.contains(word),
          isFalse,
          reason: '${file.path} names a product concept; the kit stays generic',
        );
      }
    }
  });

  test('a destructive label is readable on the surface it sits on', () {
    // contrast AA for a 14pt label, which is what a destructive menu item is
    expect(_contrast(AppColors.errorText, AppColors.white), greaterThan(4.5));
    expect(
      _contrast(AppColors.errorTextDark, AppColors.surfaceDark),
      greaterThan(4.5),
    );
  });

  test('a progress track is visible on the surface it sits on', () {
    final source = File(
      'lib/indicators/app_progress_bar.dart',
    ).readAsStringSync();
    expect(
      source,
      isNot(contains('AppColors.surfaceDark')),
      reason:
          'a dark card is painted with surfaceDark, so a track of the same '
          'colour is an invisible control on every consumer',
    );
  });
}
