import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oxitalk/src/matrix/api/matrix.dart';
import 'package:oxitalk/src/matrix/fakes/fakes.dart';

import 'support/app.dart';

const _wide = Size(1200, 800);

const _acme = '@me:acme.com';
const _globex = '@me:globex.org';

FakeSession _acmeSession() => FakeSession(
  userId: _acme,
  rooms: const [
    Room(
      id: '!a1:acme.com',
      name: 'Acme team',
      unreadCount: 2,
      unreadNotifications: 2,
    ),
    Room(id: '!a2:acme.com', name: 'Acme support'),
  ],
);

FakeSession _globexSession() => FakeSession(
  userId: _globex,
  rooms: const [
    Room(
      id: '!g1:globex.org',
      name: 'Globex board',
      unreadCount: 5,
      unreadNotifications: 5,
    ),
    Room(
      id: '!g2:globex.org',
      name: 'Globex invite',
      membership: Membership.invited,
    ),
  ],
);

Future<FakeMatrixClientFactory> _twoAccounts(
  WidgetTester tester, {
  Size size = _wide,
  FakeSession? acme,
  FakeSession? globex,
}) async {
  final factory = FakeMatrixClientFactory(
    saved: [acme ?? _acmeSession(), globex ?? _globexSession()],
    active: _acme,
  );
  await pumpApp(tester, factory, size: size);
  return factory;
}

Future<void> _press(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool shift = false,
}) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'the rail shows every account; tapping one brings it to the front',
    (tester) async {
      final factory = await _twoAccounts(tester);
      expect(find.byKey(const Key('account.$_acme')), findsOneWidget);
      expect(find.byKey(const Key('account.$_globex')), findsOneWidget);
      expect(find.text('Acme team'), findsOneWidget);
      expect(find.text('Globex board'), findsNothing);
      // Unread messages plus the invite.
      expect(find.text('6'), findsOneWidget);

      await tester.tap(find.byKey(const Key('account.$_globex')));
      await tester.pumpAndSettle();
      expect(find.text('Globex board'), findsOneWidget);
      expect(find.text('Acme team'), findsNothing);
      expect(factory.active, _globex);
    },
  );

  testWidgets('the account in front last time comes back in front', (
    tester,
  ) async {
    final factory = FakeMatrixClientFactory(
      saved: [_acmeSession(), _globexSession()],
      active: _globex,
    );
    await pumpApp(tester, factory, size: _wide);
    expect(find.text('Globex board'), findsOneWidget);
  });

  testWidgets(
    'Ctrl+number jumps to an account, Ctrl+Shift+arrows step through',
    (tester) async {
      final factory = await _twoAccounts(tester);

      await _press(tester, LogicalKeyboardKey.digit2);
      expect(factory.active, _globex);
      expect(find.text('Globex board'), findsOneWidget);

      await _press(tester, LogicalKeyboardKey.digit1);
      expect(factory.active, _acme);

      // There is no third account.
      await _press(tester, LogicalKeyboardKey.digit3);
      expect(factory.active, _acme);

      await _press(tester, LogicalKeyboardKey.arrowDown, shift: true);
      expect(factory.active, _globex);
      await _press(tester, LogicalKeyboardKey.arrowDown, shift: true);
      expect(factory.active, _acme);
      await _press(tester, LogicalKeyboardKey.arrowUp, shift: true);
      expect(factory.active, _globex);
    },
  );

  testWidgets('the hotkeys work while typing a message', (tester) async {
    final factory = await _twoAccounts(tester);
    await tester.tap(find.text('Acme support'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('composer.text')), 'draft');

    await _press(tester, LogicalKeyboardKey.digit2);
    expect(factory.active, _globex);
  });

  testWidgets('each account comes back to its open chat', (tester) async {
    await _twoAccounts(tester);
    await tester.tap(find.text('Acme support'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('composer.text')), findsOneWidget);

    await _press(tester, LogicalKeyboardKey.digit2);
    expect(find.byKey(const Key('welcome')), findsOneWidget);

    await _press(tester, LogicalKeyboardKey.digit1);
    expect(find.byKey(const Key('composer.text')), findsOneWidget);
    expect(find.text('Acme support'), findsWidgets);
  });

  testWidgets('another account is added from the rail', (tester) async {
    final factory = await _twoAccounts(tester);
    await tester.tap(find.byKey(const Key('account.add')));
    await tester.pumpAndSettle();
    expect(find.text('Add another Matrix account'), findsOneWidget);

    // An account that is already in the app is refused.
    await tester.enterText(find.byKey(const Key('login.server')), 'acme.com');
    await tester.enterText(find.byKey(const Key('login.username')), 'me');
    await tester.enterText(find.byKey(const Key('login.password')), 'secret');
    await tester.tap(find.byKey(const Key('login.submit')));
    await tester.pumpAndSettle();
    expect(find.text('$_acme is already signed in.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('login.server')), 'initech.io');
    await tester.tap(find.byKey(const Key('login.submit')));
    await tester.pumpAndSettle();
    expect(factory.active, '@me:initech.io');
    expect(find.byKey(const Key('account.@me:initech.io')), findsOneWidget);
    expect(find.text('No chats yet'), findsOneWidget);

    await _press(tester, LogicalKeyboardKey.digit3);
    expect(factory.active, '@me:initech.io');
  });

  testWidgets('adding an account can be cancelled', (tester) async {
    await _twoAccounts(tester);
    await tester.tap(find.byKey(const Key('account.add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('login.cancel')));
    await tester.pumpAndSettle();
    expect(find.text('Acme team'), findsOneWidget);
  });

  testWidgets('on a phone the account dropdown switches accounts', (
    tester,
  ) async {
    final factory = await _twoAccounts(tester, size: const Size(400, 800));
    expect(find.byKey(const Key('account.$_acme')), findsNothing);

    await tester.tap(find.byKey(const Key('account.dropdown')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('accountMenu.$_globex')), findsOneWidget);
    expect(find.text('Add account'), findsOneWidget);
    // No rail on a phone: Settings and About are here.
    expect(find.text('Settings'), findsOneWidget);

    await tester.tap(find.byKey(const Key('accountMenu.$_globex')));
    await tester.pumpAndSettle();
    expect(factory.active, _globex);
    expect(find.text('Globex board'), findsOneWidget);
  });

  testWidgets('logging out of one account keeps the others', (tester) async {
    final acme = _acmeSession();
    final factory = await _twoAccounts(tester, acme: acme);

    await pickFromAccountMenu(tester, 'accountMenu.logout');

    expect(acme.loggedOut, isTrue);
    expect(factory.active, _globex);
    expect(find.text('Globex board'), findsOneWidget);
    expect(find.byKey(const Key('account.$_acme')), findsNothing);
  });

  testWidgets(
    'a rejected account drops out; the last one returns to the login',
    (tester) async {
      final acme = _acmeSession();
      final globex = _globexSession();
      await _twoAccounts(tester, acme: acme, globex: globex);

      globex.expire();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('account.$_globex')), findsNothing);
      expect(find.text('Acme team'), findsOneWidget);

      acme.expire();
      await tester.pumpAndSettle();
      expect(find.text('Sign in'), findsOneWidget);
    },
  );

  testWidgets(
    'an unverified account is marked and asks to verify when in front',
    (tester) async {
      final globex = _globexSession()
        ..verification.value = VerificationStatus.unverified;
      final factory = await _twoAccounts(tester, globex: globex);
      expect(find.text('!'), findsOneWidget);

      await _press(tester, LogicalKeyboardKey.digit2);
      expect(find.text('Confirm it’s you'), findsOneWidget);
      expect(find.text(_globex), findsOneWidget);

      // The other account is still a keystroke away.
      await _press(tester, LogicalKeyboardKey.digit1);
      expect(factory.active, _acme);
      expect(find.text('Acme team'), findsOneWidget);
    },
  );
}
