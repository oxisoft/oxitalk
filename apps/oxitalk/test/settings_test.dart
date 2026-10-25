import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oxitalk/src/app/diagnostics.dart';
import 'package:oxitalk/src/app/router.dart';
import 'package:oxitalk/src/app/ui_prefs.dart';
import 'package:oxitalk/src/matrix/fakes/fakes.dart';

import 'support/app.dart';

const _wide = Size(1400, 900);

const _sections = [
  'account',
  'appearance',
  'messages',
  'notifications',
  'media',
  'diagnostics',
];

FakeMatrixClientFactory _factory() =>
    FakeMatrixClientFactory(saved: [FakeSession(rooms: const [])]);

/// Goes to [location] as a link would.
Future<void> _go(WidgetTester tester, String location) async {
  ProviderScope.containerOf(tester.element(find.byType(MaterialApp)))
      .read(routerProvider)
      .go(location);
  await tester.pumpAndSettle();
}

Finder _pane(String slug) => find.byKey(Key('settings.pane.$slug'));

bool _selected(WidgetTester tester, String slug) => tester
    .widget<ListTile>(
      find.descendant(
        of: find.byKey(Key('settings.$slug')),
        matching: find.byType(ListTile),
      ),
    )
    .selected;

void main() {
  testWidgets('logs are turned on and off in the settings', (tester) async {
    final diagnostics = MemoryDiagnostics();
    await pumpApp(tester, _factory(), diagnostics: diagnostics);
    await pickFromAccountMenu(tester, 'accountMenu.settings');
    expect(find.text('Logs off'), findsOneWidget);
    await openSettingsSection(tester, 'diagnostics');
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

    await tester.tap(find.byKey(const Key('settings.collectLogs')));
    await tester.pumpAndSettle();
    // Back to the menu, which tells the new state; back again leaves Settings.
    await tester.tap(find.byKey(const Key('settings.back')));
    await tester.pumpAndSettle();
    expect(find.text('Logs on'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsNothing);
  });

  testWidgets('the theme is automatic, or chosen light or dark', (
    tester,
  ) async {
    final ui = MemoryUiPrefs();
    await pumpApp(tester, _factory(), ui: ui);
    ThemeMode mode() =>
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode!;
    Brightness brightness() =>
        Theme.of(tester.element(find.byKey(const Key('settings.theme'))))
            .brightness;
    expect(mode(), ThemeMode.system);

    await pickFromAccountMenu(tester, 'accountMenu.settings');
    await openSettingsSection(tester, 'appearance');
    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(mode(), ThemeMode.light);
    expect(ui.theme, 'light');
    expect(brightness(), Brightness.light);

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(ui.theme, 'dark');
    expect(brightness(), Brightness.dark);

    await tester.tap(find.text('Automatic'));
    await tester.pumpAndSettle();
    expect(mode(), ThemeMode.system);
    expect(ui.theme, 'system');
  });

  group('wide', () {
    testWidgets('the menu, and beside it the first section', (tester) async {
      await pumpApp(tester, _factory(), size: _wide);
      await tester.tap(find.byKey(const Key('rail.settings')));
      await tester.pumpAndSettle();
      for (final slug in [..._sections, 'about']) {
        expect(find.byKey(Key('settings.$slug')), findsOneWidget);
      }
      expect(_pane('account'), findsOneWidget);
      expect(find.byKey(const Key('settings.logout')), findsOneWidget);
      expect(_selected(tester, 'account'), isTrue);
      expect(_selected(tester, 'appearance'), isFalse);
      // Beside the menu, not over it: no way back but the menu's.
      expect(find.byKey(const Key('settings.back')), findsNothing);
      expect(find.byType(BackButton), findsOneWidget);
    });

    testWidgets('picking a section shows it in place of the other', (
      tester,
    ) async {
      await pumpApp(tester, _factory(), size: _wide);
      await tester.tap(find.byKey(const Key('rail.settings')));
      await tester.pumpAndSettle();
      for (final slug in _sections.skip(1)) {
        await openSettingsSection(tester, slug);
        expect(_pane(slug), findsOneWidget);
        expect(_selected(tester, slug), isTrue);
        expect(_pane('account'), findsNothing);
        expect(_selected(tester, 'account'), isFalse);
      }
      await openSettingsSection(tester, 'account');
      expect(_pane('account'), findsOneWidget);

      // Back leaves Settings, whichever section is open.
      await openSettingsSection(tester, 'media');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('settings.account')), findsNothing);
    });

    testWidgets('a link opens its section beside the menu', (tester) async {
      await pumpApp(tester, _factory(), size: _wide);
      await _go(tester, Routes.notificationSettings);
      expect(find.byKey(const Key('settings.account')), findsOneWidget);
      expect(_pane('notifications'), findsOneWidget);
      expect(find.byKey(const Key('settings.device.enabled')), findsOneWidget);
      expect(_selected(tester, 'notifications'), isTrue);
    });
  });

  group('narrow', () {
    testWidgets('the menu alone; a section is a page over it', (tester) async {
      await pumpApp(tester, _factory());
      await pickFromAccountMenu(tester, 'accountMenu.settings');
      expect(find.byKey(const Key('settings.messages')), findsOneWidget);
      for (final slug in _sections) {
        expect(_pane(slug), findsNothing);
      }

      await openSettingsSection(tester, 'messages');
      expect(_pane('messages'), findsOneWidget);
      expect(find.byKey(const Key('settings.markdown')), findsOneWidget);
      expect(find.byKey(const Key('settings.messages')), findsNothing);

      // Its back button returns to the menu…
      await tester.tap(find.byKey(const Key('settings.back')));
      await tester.pumpAndSettle();
      expect(_pane('messages'), findsNothing);
      expect(find.byKey(const Key('settings.messages')), findsOneWidget);

      // …and so does the system's.
      await openSettingsSection(tester, 'media');
      expect(_pane('media'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(_pane('media'), findsNothing);
      expect(find.byKey(const Key('settings.media')), findsOneWidget);
    });

    testWidgets('a link opens its section as a page over the menu', (
      tester,
    ) async {
      await pumpApp(tester, _factory());
      await _go(tester, Routes.notificationSettings);
      expect(_pane('notifications'), findsOneWidget);
      expect(find.byKey(const Key('settings.device.enabled')), findsOneWidget);
      await tester.tap(find.byKey(const Key('notificationSettings.back')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('settings.notifications')), findsOneWidget);
      expect(_pane('notifications'), findsNothing);
    });

    testWidgets('an unknown section is the menu', (tester) async {
      await pumpApp(tester, _factory());
      await _go(tester, '${Routes.settings}/nonsense');
      expect(find.byKey(const Key('settings.account')), findsOneWidget);
      for (final slug in _sections) {
        expect(_pane(slug), findsNothing);
      }
    });
  });
}
