import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oxitalk/src/app/diagnostics.dart';
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
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
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
}
