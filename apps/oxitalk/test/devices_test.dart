import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oxitalk/src/app/router.dart';
import 'package:oxitalk/src/matrix/api/matrix.dart';
import 'package:oxitalk/src/matrix/fakes/fakes.dart';
import 'package:oxitalk/src/ui/format.dart';

import 'support/app.dart';

const _wide = Size(1400, 900);

const _me = '@me:example.org';

const _thisDevice = Device(
  id: 'THISDEVICE',
  name: 'OxiTalk',
  isThisDevice: true,
  verified: true,
);

/// An account on three devices: this one, an unverified phone seen 5 minutes ago, and a
/// verified laptop without a name.
FakeSession _session() =>
    FakeSession(userId: _me, rooms: const [])
      ..deviceList.value = [
        _thisDevice,
        Device(
          id: 'PHONE',
          name: 'Phone',
          lastSeen: DateTime.now().subtract(const Duration(minutes: 5)),
          lastSeenIp: '10.0.0.2',
        ),
        const Device(id: 'LAPTOP', verified: true),
      ];

/// Settings › Account of [session], on a wide window.
Future<void> _openAccount(WidgetTester tester, FakeSession session) async {
  await pumpApp(tester, FakeMatrixClientFactory(saved: [session]), size: _wide);
  ProviderScope.containerOf(tester.element(find.byType(MaterialApp)))
      .read(routerProvider)
      .go(Routes.settingsAccount(session.userId));
  await tester.pumpAndSettle();
}

Future<FakeSession> _openDevices(WidgetTester tester) async {
  final session = _session();
  await _openAccount(tester, session);
  await tester.ensureVisible(find.byKey(const Key('devices.row.THISDEVICE')));
  await tester.pumpAndSettle();
  return session;
}

Finder _row(String id) => find.byKey(Key('devices.row.$id'));

Finder _inRow(String id, Finder matching) =>
    find.descendant(of: _row(id), matching: matching);

Future<void> _menu(WidgetTester tester, String id, String item) async {
  await tester.ensureVisible(find.byKey(Key('devices.menu.$id')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('devices.menu.$id')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('devices.$item')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the account’s devices are listed with what the server tells', (
    tester,
  ) async {
    await _openDevices(tester);

    expect(find.text('Devices'), findsOneWidget);
    expect(_inRow('THISDEVICE', find.textContaining('This device')), findsOne);
    expect(_inRow('THISDEVICE', find.text('Verified')), findsOneWidget);
    expect(_inRow('PHONE', find.textContaining('Phone')), findsOneWidget);
    expect(_inRow('PHONE', find.text('PHONE')), findsOneWidget);
    expect(
      _inRow('PHONE', find.text('Last seen 5 min ago · 10.0.0.2')),
      findsOneWidget,
    );
    expect(_inRow('PHONE', find.text('Not verified')), findsOneWidget);
    // Without a name, the ID is its name.
    expect(_inRow('LAPTOP', find.text('LAPTOP')), findsNWidgets(2));
    expect(_inRow('LAPTOP', find.text('Verified')), findsOneWidget);
    // In the order the core gives: this device first.
    double top(Finder row) => tester.getTopLeft(row).dy;
    expect(top(_row('THISDEVICE')), lessThan(top(_row('PHONE'))));
    expect(top(_row('PHONE')), lessThan(top(_row('LAPTOP'))));
  });

  testWidgets('this device can be renamed but not signed out from the list', (
    tester,
  ) async {
    final session = await _openDevices(tester);

    await tester.tap(find.byKey(const Key('devices.menu.THISDEVICE')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('devices.rename')), findsOneWidget);
    expect(find.byKey(const Key('devices.signOut')), findsNothing);
    expect(find.byKey(const Key('devices.verify')), findsNothing);
    await tester.tap(find.byKey(const Key('devices.rename')));
    await tester.pumpAndSettle();

    expect(find.text('Rename device'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('devices.name')))
          .controller
          ?.text,
      'OxiTalk',
    );
    await tester.enterText(find.byKey(const Key('devices.name')), 'Laptop');
    await tester.tap(find.byKey(const Key('devices.save')));
    await tester.pumpAndSettle();

    expect(session.deviceList.value.first.name, 'Laptop');
    expect(_inRow('THISDEVICE', find.textContaining('Laptop')), findsOneWidget);
  });

  testWidgets('signing a device out asks the password and tells a wrong one', (
    tester,
  ) async {
    final session = await _openDevices(tester);

    await _menu(tester, 'PHONE', 'signOut');
    expect(find.text('Sign out of Phone?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('devices.confirmSignOut')));
    await tester.pumpAndSettle();

    // The server wants the password.
    expect(find.text('Confirm it’s you'), findsOneWidget);
    expect(find.text('Enter the password of $_me.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('devices.password')), 'nope');
    await tester.tap(find.byKey(const Key('devices.passwordSubmit')));
    await tester.pumpAndSettle();
    expect(find.text('That password isn’t right.'), findsOneWidget);
    expect(_row('PHONE'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('devices.password')),
      'the password',
    );
    await tester.tap(find.byKey(const Key('devices.passwordSubmit')));
    await tester.pumpAndSettle();

    expect(find.text('Confirm it’s you'), findsNothing);
    expect(_row('PHONE'), findsNothing);
    expect(find.text('Signed out of Phone'), findsOneWidget);
    expect(session.signOutPasswords, [null, 'nope', 'the password']);
  });

  testWidgets('a server that asks no password signs out right away', (
    tester,
  ) async {
    final session = _session()..accountPassword = null;
    await _openAccount(tester, session);

    await _menu(tester, 'LAPTOP', 'signOut');
    await tester.tap(find.byKey(const Key('devices.confirmSignOut')));
    await tester.pumpAndSettle();

    expect(find.text('Confirm it’s you'), findsNothing);
    expect(_row('LAPTOP'), findsNothing);
    expect(session.signOutPasswords, [null]);
  });

  testWidgets('all other devices are signed out at once, after confirming', (
    tester,
  ) async {
    final session = await _openDevices(tester);

    final button = find.byKey(const Key('devices.signOutOthers'));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('Sign out of all other devices?'), findsOneWidget);
    expect(find.textContaining('your 2 other devices'), findsOneWidget);

    // Cancelling signs nothing out.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(session.signOutPasswords, isEmpty);

    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('devices.confirmSignOut')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('devices.password')),
      'the password',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(session.deviceList.value.map((d) => d.id), ['THISDEVICE']);
    expect(_row('PHONE'), findsNothing);
    expect(_row('LAPTOP'), findsNothing);
    expect(button, findsNothing);
  });

  testWidgets('an unverified device is verified by emoji from the list', (
    tester,
  ) async {
    final session = await _openDevices(tester);

    // A verified one has nothing to verify.
    await tester.tap(find.byKey(const Key('devices.menu.LAPTOP')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('devices.verify')), findsNothing);
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('devices.menu.PHONE')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('devices.menu.PHONE')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('devices.verify')));
    // The waiting spinner never settles.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Verify Phone'), findsOneWidget);
    expect(find.textContaining('on Phone and accept'), findsOneWidget);

    session.lastVerification!.showEmoji();
    await tester.pumpAndSettle();
    expect(find.text('🐶'), findsOneWidget);
    await tester.tap(find.byKey(const Key('verify.match')));
    await tester.pumpAndSettle();
    expect(find.text('Device verified'), findsOneWidget);
    await tester.tap(find.byKey(const Key('verify.done')));
    await tester.pumpAndSettle();

    expect(find.text('Verify Phone'), findsNothing);
    expect(_inRow('PHONE', find.text('Verified')), findsOneWidget);
    expect(session.lastVerification!.closed, isTrue);
  });

  testWidgets('no device is offered for verifying while this one isn’t', (
    tester,
  ) async {
    final session = _session();
    session.deviceList.value = [
      const Device(id: 'THISDEVICE', isThisDevice: true),
      ...session.deviceList.value.skip(1),
    ];
    await _openAccount(tester, session);

    await _menu(tester, 'PHONE', 'rename');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('devices.menu.PHONE')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('devices.verify')), findsNothing);
    expect(find.byKey(const Key('devices.signOut')), findsOneWidget);
  });

  testWidgets('the list follows devices signing in elsewhere', (tester) async {
    final session = await _openDevices(tester);

    session.deviceList.value = [
      ...session.deviceList.value,
      const Device(id: 'TABLET', name: 'Tablet'),
    ];
    await tester.pumpAndSettle();
    expect(_row('TABLET'), findsOneWidget);
    expect(_inRow('TABLET', find.text('Not verified')), findsOneWidget);
  });

  test('last seen reads as people say it, in local time', () {
    final now = DateTime(2026, 10, 26, 15, 30);
    expect(lastSeenLabel(now, now: now), 'just now');
    expect(
      lastSeenLabel(now.subtract(const Duration(minutes: 42)), now: now),
      '42 min ago',
    );
    expect(
      lastSeenLabel(DateTime(2026, 10, 26, 9, 5), now: now),
      'today at 09:05',
    );
    expect(
      lastSeenLabel(DateTime(2026, 10, 25, 22, 0), now: now),
      'yesterday at 22:00',
    );
    expect(
      lastSeenLabel(DateTime(2026, 10, 22, 8, 0), now: now),
      'Thu at 08:00',
    );
    expect(lastSeenLabel(DateTime(2026, 9, 1, 8, 0), now: now), '1 September');
    expect(
      lastSeenLabel(DateTime(2025, 9, 1, 8, 0), now: now),
      '1 September 2025',
    );
  });
}
