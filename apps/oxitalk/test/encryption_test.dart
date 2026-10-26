import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oxitalk/src/app/file_actions.dart';
import 'package:oxitalk/src/app/router.dart';
import 'package:oxitalk/src/matrix/api/matrix.dart';
import 'package:oxitalk/src/matrix/fakes/fakes.dart';

import 'support/app.dart';

const _wide = Size(1400, 900);

const _firstKey = 'EsTj 3yST y93F SLpB jJsz eAXc 2XzA ygD3 w69H fGaN TKBj jXEd';
const _secondKey =
    'EsUA nz8p Zg5k pT3c 9iHv Ab2Q rDxW m4Lq Ve7Y sKa1 Nf6B uP2G';

/// Settings › Account of [session], on a wide window, scrolled to Encryption.
Future<void> _openAccount(
  WidgetTester tester,
  FakeSession session, {
  FakeFileActions? files,
}) async {
  await pumpApp(
    tester,
    FakeMatrixClientFactory(saved: [session]),
    size: _wide,
    files: files,
  );
  ProviderScope.containerOf(tester.element(find.byType(MaterialApp)))
      .read(routerProvider)
      .go(Routes.settingsAccount(session.userId));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(const Key('encryption.recovery')));
  await tester.pumpAndSettle();
}

Finder _recoveryRow(Finder matching) => find.descendant(
  of: find.byKey(const Key('encryption.recovery')),
  matching: matching,
);

/// What the app put on the clipboard.
List<String> _watchClipboard(WidgetTester tester) {
  final copied = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return copied;
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

bool _enabled(WidgetTester tester, String key) =>
    tester.widget<ButtonStyleButton>(find.byKey(Key(key))).onPressed != null;

void main() {
  testWidgets(
    'recovery off shows with the key backup and offers to set it up',
    (tester) async {
      final session = FakeSession(rooms: const []);
      await _openAccount(tester, session);

      expect(find.text('Encryption'), findsOneWidget);
      expect(_recoveryRow(find.text('Recovery is off')), findsOneWidget);
      expect(find.byKey(const Key('encryption.setUp')), findsOneWidget);
      expect(find.text('Key backup is on'), findsOneWidget);

      // It follows the account as it changes elsewhere.
      session.encryption.value = const EncryptionStatus(
        recovery: RecoveryState.enabled,
      );
      await tester.pumpAndSettle();
      expect(_recoveryRow(find.text('Recovery is on')), findsOneWidget);
      expect(find.byKey(const Key('encryption.change')), findsOneWidget);
      expect(find.byKey(const Key('encryption.setUp')), findsNothing);
      expect(find.text('Key backup is off'), findsOneWidget);
    },
  );

  testWidgets(
    'setting recovery up shows the new key once and Done waits for its last group',
    (tester) async {
      final session = FakeSession(rooms: const [])
        ..recoveryGate = Completer<void>();
      final files = FakeFileActions()..savePath = '/home/me/key.txt';
      final copied = _watchClipboard(tester);
      await _openAccount(tester, session, files: files);

      await tester.tap(find.byKey(const Key('encryption.setUp')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Set up recovery'), findsWidgets);
      expect(
        find.text('Backing up your message keys: 3 of 10'),
        findsOneWidget,
      );

      session.recoveryGate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Save your recovery key'), findsOneWidget);
      expect(find.text(_firstKey), findsOneWidget);
      expect(find.textContaining('can’t be shown again'), findsOneWidget);
      expect(find.text('Your old recovery key no longer works.'), findsNothing);

      await _tap(tester, 'recovery.copy');
      expect(copied, [_firstKey]);
      await _tap(tester, 'recovery.save');
      expect(files.written['/home/me/key.txt'], contains(_firstKey));

      await _tap(tester, 'recovery.continue');
      expect(find.text('Check your recovery key'), findsOneWidget);
      expect(find.text(_firstKey), findsNothing);
      expect(_enabled(tester, 'recovery.done'), isFalse);
      await tester.enterText(find.byKey(const Key('recovery.check')), 'TKBj');
      await tester.pump();
      expect(_enabled(tester, 'recovery.done'), isFalse);
      // Case doesn't matter, as the key reads it.
      await tester.enterText(find.byKey(const Key('recovery.check')), 'jxed');
      await tester.pump();
      expect(_enabled(tester, 'recovery.done'), isTrue);
      await _tap(tester, 'recovery.done');

      expect(find.text('Check your recovery key'), findsNothing);
      expect(find.text(_firstKey), findsNothing);
      expect(_recoveryRow(find.text('Recovery is on')), findsOneWidget);
    },
  );

  testWidgets(
    'the key can be shown again before Done, and leaving asks first',
    (tester) async {
      final session = FakeSession(rooms: const []);
      await _openAccount(
        tester,
        session,
        files: FakeFileActions()..canSave = false,
      );

      await _tap(tester, 'encryption.setUp');
      // No save dialog on this platform: copying is the way.
      expect(find.byKey(const Key('recovery.save')), findsNothing);
      expect(find.byKey(const Key('recovery.copy')), findsOneWidget);
      await _tap(tester, 'recovery.continue');
      await _tap(tester, 'recovery.showAgain');
      expect(find.text(_firstKey), findsOneWidget);

      await _tap(tester, 'recovery.close');
      expect(find.text('Leave without the key?'), findsOneWidget);
      await tester.tap(find.text('Stay'));
      await tester.pumpAndSettle();
      expect(find.text(_firstKey), findsOneWidget);
      await _tap(tester, 'recovery.close');
      await _tap(tester, 'recovery.leave');
      expect(find.text('Save your recovery key'), findsNothing);
      expect(find.text(_firstKey), findsNothing);
    },
  );

  testWidgets('changing the key warns that the old one stops working', (
    tester,
  ) async {
    final session = FakeSession(rooms: const [])
      ..encryption.value = const EncryptionStatus(
        recovery: RecoveryState.enabled,
        backupEnabled: true,
      )
      ..newRecoveryKeys.removeAt(0);
    await _openAccount(tester, session);

    await _tap(tester, 'encryption.change');
    expect(find.text('Change the recovery key?'), findsOneWidget);
    await _tap(tester, 'encryption.confirmChange');

    expect(find.text('Change recovery key'), findsWidgets);
    expect(find.text(_secondKey), findsOneWidget);
    expect(find.text('Your old recovery key no longer works.'), findsOneWidget);
    await _tap(tester, 'recovery.continue');
    await tester.enterText(find.byKey(const Key('recovery.check')), 'uP2G');
    await tester.pump();
    await _tap(tester, 'recovery.done');
    expect(session.recoveryKey, _secondKey);
  });

  testWidgets('an incomplete device enters the recovery key from there', (
    tester,
  ) async {
    final session = FakeSession(rooms: const [])
      ..encryption.value = const EncryptionStatus(
        recovery: RecoveryState.incomplete,
        backupEnabled: false,
      );
    await _openAccount(tester, session);
    expect(
      _recoveryRow(find.text('Recovery is incomplete on this device')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('encryption.change')), findsNothing);

    await _tap(tester, 'encryption.enterKey');
    await tester.enterText(find.byKey(const Key('verify.key')), 'wrong');
    await _tap(tester, 'verify.keySubmit');
    expect(find.text('That recovery key isn’t right.'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('verify.key')),
      'the recovery key',
    );
    await _tap(tester, 'verify.keySubmit');

    expect(find.byKey(const Key('verify.key')), findsNothing);
    expect(_recoveryRow(find.text('Recovery is on')), findsOneWidget);
  });

  group('logging out', () {
    Future<void> logOut(WidgetTester tester) async {
      await tester.ensureVisible(find.byKey(const Key('settings.logout')));
      await tester.pumpAndSettle();
      await _tap(tester, 'settings.logout');
    }

    testWidgets('of the last device without recovery warns first', (
      tester,
    ) async {
      final session = FakeSession(rooms: const [])..lastDevice = true;
      await _openAccount(tester, session);

      await logOut(tester);
      expect(find.text('You’ll lose your encrypted messages'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(session.loggedOut, isFalse);

      // Setting recovery up from there doesn't log out.
      await logOut(tester);
      await _tap(tester, 'logout.setUpRecovery');
      expect(find.text('Save your recovery key'), findsOneWidget);
      await _tap(tester, 'recovery.continue');
      await tester.enterText(find.byKey(const Key('recovery.check')), 'jXEd');
      await tester.pump();
      await _tap(tester, 'recovery.done');
      expect(session.loggedOut, isFalse);
      expect(_recoveryRow(find.text('Recovery is on')), findsOneWidget);

      // With recovery on, nothing is lost: no warning.
      await logOut(tester);
      expect(find.text('You’ll lose your encrypted messages'), findsNothing);
      expect(session.loggedOut, isTrue);
    });

    testWidgets('anyway logs out', (tester) async {
      final session = FakeSession(rooms: const [])..lastDevice = true;
      await _openAccount(tester, session);

      await logOut(tester);
      await _tap(tester, 'logout.anyway');
      expect(session.loggedOut, isTrue);
    });

    testWidgets('with other devices left needs no warning', (tester) async {
      final session = FakeSession(rooms: const []);
      await _openAccount(tester, session);

      await logOut(tester);
      expect(find.text('You’ll lose your encrypted messages'), findsNothing);
      expect(session.loggedOut, isTrue);
    });
  });
}
