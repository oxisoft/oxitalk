import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oxitalk/src/app/diagnostics.dart';
import 'package:oxitalk/src/app/providers.dart';
import 'package:oxitalk/src/app/router.dart';
import 'package:oxitalk/src/app/ui_prefs.dart';
import 'package:oxitalk/src/features/settings/settings_screen.dart';
import 'package:oxitalk/src/matrix/api/matrix.dart';
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

const _alex = '@alex:oxisoft.net';
const _work = '@alex:work.example';
const _bot = '@bot:matrix.org';

/// Three accounts, the first one in front; the third isn't verified.
({FakeMatrixClientFactory factory, List<FakeSession> sessions}) _accounts() {
  final sessions = [
    FakeSession(
      userId: _alex,
      rooms: const [],
      profile: const Profile(displayName: 'Alex'),
    ),
    FakeSession(
      userId: _work,
      rooms: const [],
      profile: const Profile(displayName: 'Alex at work'),
    ),
    FakeSession(userId: _bot, rooms: const [])
      ..verification.value = VerificationStatus.unverified,
  ];
  return (
    factory: FakeMatrixClientFactory(saved: sessions, active: _alex),
    sessions: sessions,
  );
}

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));

/// The account the Account section shows the settings of.
Finder _edited(String account) => find.byKey(ValueKey(account));

/// Whether the account dropdown shows [account] as the one picked.
bool _switcherSelected(WidgetTester tester, String account) => find
    .descendant(
      of: find.byKey(const Key('settings.accounts.picker')),
      matching: find.byKey(Key('settings.accounts.picked.$account')),
    )
    .evaluate()
    .isNotEmpty;

/// Opens the account dropdown.
Future<void> _openPicker(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('settings.accounts.picker')));
  await tester.pumpAndSettle();
}

/// Picks [account] in the account dropdown.
Future<void> _pickAccount(WidgetTester tester, String account) async {
  await _openPicker(tester);
  await tester.tap(find.byKey(Key('settings.accounts.$account')));
  await tester.pumpAndSettle();
}

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

  group('accounts', () {
    testWidgets('one account: its ID under Account in the menu', (
      tester,
    ) async {
      await pumpApp(tester, _factory(), size: _wide);
      await _go(tester, Routes.settings);
      expect(find.text('@me:example.org'), findsWidgets);
      expect(_switcherSelected(tester, '@me:example.org'), isTrue);
      // The dropdown still opens, for Add account; one account is no use for "In use".
      expect(
        find.byKey(const Key('settings.accounts.active.@me:example.org')),
        findsNothing,
      );
      await _openPicker(tester);
      expect(
        find.byKey(const Key('settings.accounts.@me:example.org')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('settings.accounts.add')), findsOneWidget);
    });

    testWidgets('the dropdown shows the active account; opened, every '
        'account, the picked one checked, and Add account', (tester) async {
      await pumpApp(tester, _accounts().factory, size: _wide);
      await _go(tester, Routes.settings);
      expect(find.text('3 accounts'), findsOneWidget);
      // Closed: only the picked account, no list.
      expect(_switcherSelected(tester, _alex), isTrue);
      expect(_switcherSelected(tester, _work), isFalse);
      for (final id in [_alex, _work, _bot]) {
        expect(find.byKey(Key('settings.accounts.$id')), findsNothing);
      }
      expect(find.byKey(const Key('settings.accounts.add')), findsNothing);
      expect(_edited(_alex), findsOneWidget);
      expect(
        find.byKey(const Key('settings.accounts.active.$_alex')),
        findsOneWidget,
      );

      await _openPicker(tester);
      for (final id in [_alex, _work, _bot]) {
        expect(find.byKey(Key('settings.accounts.$id')), findsOneWidget);
      }
      expect(find.byKey(const Key('settings.accounts.add')), findsOneWidget);
      expect(
        find.byKey(const Key('settings.accounts.current.$_alex')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('settings.accounts.current.$_work')),
        findsNothing,
      );
      // Names with their full IDs; the unverified one says so.
      expect(find.text('Alex at work'), findsOneWidget);
      expect(find.textContaining('Not verified'), findsOneWidget);
    });

    testWidgets('picking another account shows its settings, the active '
        'one stays', (tester) async {
      final (:factory, :sessions) = _accounts();
      await pumpApp(tester, factory, size: _wide);
      await _go(tester, Routes.settings);
      await _pickAccount(tester, _work);
      // The dropdown closes and shows the picked account.
      expect(find.byKey(const Key('settings.accounts.add')), findsNothing);
      expect(_switcherSelected(tester, _work), isTrue);
      expect(_switcherSelected(tester, _alex), isFalse);
      expect(_edited(_work), findsOneWidget);
      expect(_edited(_alex), findsNothing);
      expect(find.byKey(const Key('settings.logout')), findsOneWidget);
      expect(_container(tester).read(activeAccountProvider), _alex);
      expect(factory.active, _alex);
      // Linkable: the pick is in the location.
      expect(
        _container(tester)
            .read(routerProvider)
            .routerDelegate
            .currentConfiguration
            .uri
            .toString(),
        Routes.settingsAccount(_work),
      );
    });

    testWidgets('logging out of another account keeps the active one', (
      tester,
    ) async {
      final (:factory, :sessions) = _accounts();
      await pumpApp(tester, factory, size: _wide);
      await _go(tester, Routes.settingsAccount(_work));
      await tester.tap(find.byKey(const Key('settings.logout')));
      await tester.pumpAndSettle();
      expect(sessions[1].loggedOut, isTrue);
      expect(sessions[0].loggedOut, isFalse);
      expect(_container(tester).read(activeAccountProvider), _alex);
      // Still in Settings, now about the active account.
      expect(_switcherSelected(tester, _work), isFalse);
      expect(_switcherSelected(tester, _alex), isTrue);
      expect(_edited(_alex), findsOneWidget);
      expect(find.text('2 accounts'), findsOneWidget);
    });

    testWidgets('Add account opens the login to add one', (tester) async {
      await pumpApp(tester, _accounts().factory, size: _wide);
      await _go(tester, Routes.settings);
      await _openPicker(tester);
      await tester.tap(find.byKey(const Key('settings.accounts.add')));
      await tester.pumpAndSettle();
      expect(
        _container(tester)
            .read(routerProvider)
            .routerDelegate
            .currentConfiguration
            .uri
            .path,
        Routes.addAccount,
      );
    });

    for (final (layout, size) in [
      ('wide', _wide),
      ('narrow', const Size(400, 800)),
    ]) {
      testWidgets('$layout: a link with a user opens that account', (
        tester,
      ) async {
        await pumpApp(tester, _accounts().factory, size: size);
        await _go(tester, Routes.settingsAccount(_bot));
        expect(_pane('account'), findsOneWidget);
        expect(_switcherSelected(tester, _bot), isTrue);
        expect(_edited(_bot), findsOneWidget);
        expect(_container(tester).read(activeAccountProvider), _alex);
      });

      testWidgets('$layout: a link with an unknown user opens the active one', (
        tester,
      ) async {
        await pumpApp(tester, _accounts().factory, size: size);
        await _go(tester, Routes.settingsAccount('@nobody:nowhere.example'));
        expect(_pane('account'), findsOneWidget);
        expect(_switcherSelected(tester, _alex), isTrue);
        expect(_edited(_alex), findsOneWidget);
      });
    }

    testWidgets('narrow: picking an account keeps the page', (tester) async {
      await pumpApp(tester, _accounts().factory);
      await _go(tester, Routes.settingsSection(SettingsSection.account));
      await _pickAccount(tester, _work);
      expect(_edited(_work), findsOneWidget);
      expect(_container(tester).read(activeAccountProvider), _alex);
      // Back still returns to the menu.
      await tester.tap(find.byKey(const Key('settings.back')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('settings.messages')), findsOneWidget);
      expect(_pane('account'), findsNothing);
    });
  });
}
