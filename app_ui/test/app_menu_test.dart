import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

enum _Action { edit, share, delete }

Widget _host({
  required List<AppMenuItem<_Action>> items,
  required void Function(_Action) onSelected,
}) => MaterialApp(
  home: Scaffold(
    body: AppMenu<_Action>(
      tooltip: 'Options',
      items: items,
      onSelected: onSelected,
    ),
  ),
);

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Options'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a destructive choice is grouped last, behind a divider', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        onSelected: (_) {},
        items: const [
          AppMenuItem(
            value: _Action.delete,
            label: 'Delete',
            isDestructive: true,
          ),
          AppMenuItem(value: _Action.edit, label: 'Edit'),
          AppMenuItem(value: _Action.share, label: 'Share'),
        ],
      ),
    );
    await _open(tester);

    expect(find.byType(PopupMenuDivider), findsOneWidget);
    final delete = tester.getTopLeft(find.text('Delete')).dy;
    expect(tester.getTopLeft(find.text('Edit')).dy, lessThan(delete));
    expect(tester.getTopLeft(find.text('Share')).dy, lessThan(delete));
  });

  testWidgets('a menu of safe choices alone carries no divider', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        onSelected: (_) {},
        items: const [
          AppMenuItem(value: _Action.edit, label: 'Edit'),
          AppMenuItem(value: _Action.share, label: 'Share'),
        ],
      ),
    );
    await _open(tester);

    expect(find.byType(PopupMenuDivider), findsNothing);
  });

  testWidgets('a disabled choice states its reason and cannot be picked', (
    tester,
  ) async {
    final picked = <_Action>[];
    await tester.pumpWidget(
      _host(
        onSelected: picked.add,
        items: const [
          AppMenuItem(value: _Action.edit, label: 'Edit'),
          AppMenuItem(
            value: _Action.delete,
            label: 'Delete',
            enabled: false,
            isDestructive: true,
            description: 'Empty it first',
          ),
        ],
      ),
    );
    await _open(tester);

    expect(find.text('Empty it first'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(picked, isEmpty);
  });
}
