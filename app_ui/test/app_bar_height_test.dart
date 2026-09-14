import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('custom toolbar height sizes both the scaffold and toolbar', (
    tester,
  ) async {
    const height = AppSpacing.appBarHeight * 2;
    const bar = AppAppBar(toolbarHeight: height, title: 'Large title');
    expect(bar.preferredSize.height, height);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(appBar: bar)));
    expect(tester.widget<AppBar>(find.byType(AppBar)).toolbarHeight, height);
    expect(tester.getSize(find.byType(AppBar)).height, height);
    expect(const AppAppBar().preferredSize.height, AppSpacing.appBarHeight);
  });
}
