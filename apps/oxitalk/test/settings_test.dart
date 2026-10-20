import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oxitalk/src/app/diagnostics.dart';
import 'package:oxitalk/src/app/ui_prefs.dart';
import 'package:oxitalk/src/matrix/fakes/fakes.dart';

import 'support/app.dart';

void main() {
  testWidgets('logs are turned on and off in the settings', (tester) async {
    final diagnostics = MemoryDiagnostics();
    await pumpApp(
      tester,
      FakeMatrixClientFactory(saved: [FakeSession(rooms: const [])]),
      diagnostics: diagnostics,
    );
    await pickFromAccountMenu(tester, 'accountMenu.settings');
    // Below the account on a phone.
    await tester.scrollUntilVisible(find.text(diagnostics.logDir), 200);
    expect(find.text('Collect logs'), findsOneWidget);
    expect(find.text(diagnostics.logDir), findsOneWidget);

    await tester.tap(find.byKey(const Key('settings.collectLogs')));
    await tester.pumpAndSettle();
    expect(diagnostics.collectLogs, isTrue);
    expect(
      tester
          .widget<SwitchListTile>(find.byKey(const Key('settings.collectLogs')))
          .value,
      isTrue,
    );

    await tester.tap(find.byKey(const Key('settings.collectLogs')));
    await tester.pumpAndSettle();
    expect(diagnostics.collectLogs, isFalse);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsNothing);
  });

  testWidgets('the theme is automatic, or chosen light or dark', (
    tester,
  ) async {
    final ui = MemoryUiPrefs();
    await pumpApp(
      tester,
      FakeMatrixClientFactory(saved: [FakeSession(rooms: const [])]),
      ui: ui,
    );
    ThemeMode mode() =>
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode!;
    expect(mode(), ThemeMode.system);

    await pickFromAccountMenu(tester, 'accountMenu.settings');
    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(mode(), ThemeMode.light);
    expect(ui.theme, 'light');
    expect(
      Theme.of(tester.element(find.text('Settings'))).brightness,
      Brightness.light,
    );

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(ui.theme, 'dark');
    expect(
      Theme.of(tester.element(find.text('Settings'))).brightness,
      Brightness.dark,
    );

    await tester.tap(find.text('Automatic'));
    await tester.pumpAndSettle();
    expect(mode(), ThemeMode.system);
    expect(ui.theme, 'system');
  });
}
