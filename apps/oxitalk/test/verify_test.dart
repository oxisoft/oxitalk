import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oxitalk/src/matrix/api/matrix.dart';
import 'package:oxitalk/src/matrix/fakes/fakes.dart';

import 'support/app.dart';

const _rooms = [Room(id: '!team:example.org', name: 'Team')];

FakeSession _unverified() =>
    FakeSession(rooms: _rooms)
      ..verification.value = VerificationStatus.unverified;

void main() {
  testWidgets('an unverified device sees only the verification screen', (
    tester,
  ) async {
    final session = _unverified();
    await pumpApp(tester, FakeMatrixClientFactory(saved: [session]));
    expect(find.text('Confirm it’s you'), findsOneWidget);
    expect(find.text('Team'), findsNothing);

    await tester.tap(find.text('Log out'));
    await tester.pumpAndSettle();
    expect(session.loggedOut, isTrue);
    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('a fresh login of an unverified device asks to verify', (
    tester,
  ) async {
    await pumpApp(
      tester,
      FakeMatrixClientFactory(
        rooms: _rooms,
        loginVerification: VerificationStatus.unverified,
      ),
    );
    await tester.enterText(find.byKey(const Key('login.username')), 'alice');
    await tester.enterText(find.byKey(const Key('login.password')), 'secret');
    await tester.tap(find.byKey(const Key('login.submit')));
    await tester.pumpAndSettle();
    expect(find.text('Confirm it’s you'), findsOneWidget);
  });

  testWidgets('the recovery key verifies; a wrong one says so', (tester) async {
    await pumpApp(tester, FakeMatrixClientFactory(saved: [_unverified()]));
    await tester.tap(find.byKey(const Key('verify.recoveryKey')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('verify.key')), 'nope');
    await tester.tap(find.byKey(const Key('verify.keySubmit')));
    await tester.pumpAndSettle();
    expect(find.text('That recovery key isn’t right.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('verify.key')),
      ' the recovery key ',
    );
    await tester.tap(find.byKey(const Key('verify.keySubmit')));
    await tester.pumpAndSettle();
    expect(find.text('Team'), findsOneWidget);
  });

  testWidgets('an account without recovery points to another device', (
    tester,
  ) async {
    final session = _unverified()..recoveryKey = null;
    await pumpApp(tester, FakeMatrixClientFactory(saved: [session]));
    await tester.tap(find.byKey(const Key('verify.recoveryKey')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('verify.key')), 'anything');
    await tester.tap(find.byKey(const Key('verify.keySubmit')));
    await tester.pumpAndSettle();
    expect(find.textContaining('no recovery key'), findsOneWidget);
  });

  group('with another device', () {
    Future<FakeVerification> start(
      WidgetTester tester,
      FakeSession session,
    ) async {
      await pumpApp(tester, FakeMatrixClientFactory(saved: [session]));
      await tester.tap(find.byKey(const Key('verify.otherDevice')));
      // The waiting step spins, so the frames never settle.
      await tester.pump();
      await tester.pump();
      expect(find.text('Waiting for your other device'), findsOneWidget);
      return session.lastVerification!..showEmoji();
    }

    testWidgets('matching emoji verify the device', (tester) async {
      final session = _unverified();
      await start(tester, session);
      await tester.pumpAndSettle();
      expect(find.text('Compare emoji'), findsOneWidget);
      expect(find.text('🐶'), findsOneWidget);
      expect(find.text('Anchor'), findsOneWidget);

      await tester.tap(find.byKey(const Key('verify.match')));
      await tester.pumpAndSettle();
      expect(session.verification.value, VerificationStatus.verified);
      expect(find.text('Team'), findsOneWidget);
    });

    testWidgets('a mismatch cancels and goes back to the choice', (
      tester,
    ) async {
      await start(tester, _unverified());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('verify.mismatch')));
      await tester.pumpAndSettle();
      expect(find.text('Verification cancelled'), findsOneWidget);

      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm it’s you'), findsOneWidget);
    });
  });

  testWidgets('a request from another device opens a dialog to verify it', (
    tester,
  ) async {
    final session = FakeSession(rooms: _rooms);
    await pumpApp(tester, FakeMatrixClientFactory(saved: [session]));

    session.receiveVerificationRequest(
      const VerificationRequest(
        flowId: 'flow',
        deviceId: 'PHONE',
        deviceName: 'Element on Android',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Element on Android'), findsOneWidget);
    expect(find.text('Verification request'), findsOneWidget);

    await tester.tap(find.text('Accept'));
    await tester.pump();
    await tester.pump();
    final verification = session.lastVerification!;
    expect(verification.accepted, isTrue);

    verification.showEmoji();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('verify.match')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('verify.done')));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(verification.closed, isTrue);
    expect(find.text('Team'), findsOneWidget);
  });
}
