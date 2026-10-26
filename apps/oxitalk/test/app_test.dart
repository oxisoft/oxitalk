import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oxitalk/src/matrix/api/matrix.dart';
import 'package:oxitalk/src/matrix/fakes/fakes.dart';

import 'support/app.dart';

final _now = DateTime.now();

const _rooms = [
  Room(
    id: '!team:example.org',
    name: 'Team',
    lastMessage: 'Standup at 10',
    unreadCount: 3,
    unreadNotifications: 3,
  ),
  Room(
    id: '!bob:example.org',
    name: 'Bob',
    isDm: true,
    isEncrypted: true,
    lastMessage: 'See you',
  ),
  Room(id: '!new:example.org', name: 'Carol', membership: Membership.invited),
];

FakeSession _session() => FakeSession(rooms: _rooms);

void main() {
  group('login', () {
    testWidgets('a wrong password shows an error and stays on the form', (
      tester,
    ) async {
      await pumpApp(tester, FakeMatrixClientFactory());
      expect(find.text('Sign in'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'matrix.org'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('login.username')), 'alice');
      await tester.enterText(find.byKey(const Key('login.password')), 'wrong');
      await tester.tap(find.byKey(const Key('login.submit')));
      await tester.pumpAndSettle();

      expect(find.text('Wrong username or password.'), findsOneWidget);
    });

    testWidgets('the right password opens the chat list', (tester) async {
      final factory = FakeMatrixClientFactory(rooms: _rooms);
      await pumpApp(tester, factory);

      await tester.enterText(find.byKey(const Key('login.username')), 'alice');
      await tester.enterText(find.byKey(const Key('login.password')), 'secret');
      await tester.tap(find.byKey(const Key('login.submit')));
      await tester.pumpAndSettle();

      expect(factory.lastLogin?.userId, '@alice:matrix.org');
      expect(find.text('Team'), findsOneWidget);
      expect(find.byKey(const Key('account.dropdown')), findsOneWidget);
    });

    testWidgets('an account that could not be opened is named, can be tried again, and signing '
        'in to it again replaces it', (tester) async {
      final factory = FakeMatrixClientFactory(rooms: _rooms)
        ..unopened.add('@alice:matrix.org');
      await pumpApp(tester, factory);
      expect(
        find.byKey(const Key('login.unopened.@alice:matrix.org')),
        findsOneWidget,
      );

      // Opens this time.
      factory
        ..unopened.clear()
        ..saved.add(FakeSession(userId: '@alice:matrix.org', rooms: _rooms));
      await tester.tap(find.byKey(const Key('login.unopened.retry')));
      await tester.pumpAndSettle();
      expect(find.text('Team'), findsOneWidget);
    });

    testWidgets(
      'signing in to an account that could not be opened clears the notice',
      (tester) async {
        final factory = FakeMatrixClientFactory(rooms: _rooms)
          ..unopened.add('@alice:matrix.org');
        await pumpApp(tester, factory);

        await tester.enterText(
          find.byKey(const Key('login.username')),
          'alice',
        );
        await tester.enterText(
          find.byKey(const Key('login.password')),
          'secret',
        );
        await tester.tap(find.byKey(const Key('login.submit')));
        await tester.pumpAndSettle();

        expect(factory.unopened, isEmpty);
        expect(find.text('Team'), findsOneWidget);
      },
    );
  });

  group('chat list', () {
    testWidgets('a saved session skips the login', (tester) async {
      await pumpApp(tester, FakeMatrixClientFactory(saved: [_session()]));
      expect(find.text('Sign in'), findsNothing);
      expect(find.text('Team'), findsOneWidget);
      expect(find.text('Standup at 10'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('Invitation — tap to join'), findsOneWidget);
    });

    testWidgets('the title shows the connection', (tester) async {
      final session = _session()..status.value = SyncStatus.offline;
      await pumpApp(tester, FakeMatrixClientFactory(saved: [session]));
      expect(find.text('Waiting for network…'), findsOneWidget);

      session.status.value = SyncStatus.connecting;
      await tester.pumpAndSettle();
      expect(find.text('Connecting…'), findsOneWidget);

      session
        ..roomList = null
        ..status.value = SyncStatus.online;
      // The list spins until the rooms arrive, so the frames never settle.
      await tester.pump();
      await tester.pump();
      expect(find.text('Updating…'), findsOneWidget);
    });

    testWidgets('tapping an invite joins and opens the chat', (tester) async {
      final session = _session();
      await pumpApp(tester, FakeMatrixClientFactory(saved: [session]));

      await tester.tap(find.text('Carol'));
      await tester.pumpAndSettle();

      expect(
        session.roomList
            .firstWhere((room) => room.id == '!new:example.org')
            .membership,
        Membership.joined,
      );
      expect(find.byKey(const Key('composer.text')), findsOneWidget);
    });

    testWidgets('a new chat starts a DM with a typed user ID', (tester) async {
      final session = _session();
      await pumpApp(tester, FakeMatrixClientFactory(saved: [session]));

      await tester.tap(find.byKey(const Key('newMenu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('newMenu.chat')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('newChat.search')), 'dave');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      // Not a full ID, and no one by that name: nothing to pick.
      expect(find.byKey(const Key('newChat.typed')), findsNothing);
      expect(find.byKey(const Key('newChat.none')), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('newChat.search')),
        '@dave:example.org',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('newChat.typed')));
      await tester.pumpAndSettle();
      expect(session.roomList.first.name, '@dave:example.org');
      expect(find.byKey(const Key('composer.text')), findsOneWidget);
    });

    testWidgets('log out returns to the login and logs the session out', (
      tester,
    ) async {
      final session = _session();
      await pumpApp(tester, FakeMatrixClientFactory(saved: [session]));

      await pickFromAccountMenu(tester, 'accountMenu.logout');

      expect(session.loggedOut, isTrue);
      expect(find.text('Sign in'), findsOneWidget);
    });

    testWidgets('a rejected session returns to the login', (tester) async {
      final session = _session();
      await pumpApp(tester, FakeMatrixClientFactory(saved: [session]));

      session.expire();
      await tester.pumpAndSettle();

      expect(find.text('Sign in'), findsOneWidget);
    });
  });

  group('chat', () {
    Future<FakeSession> openBob(
      WidgetTester tester, {
      Size size = const Size(400, 800),
    }) async {
      final session = _session();
      session.timelines['!bob:example.org'] = FakeTimeline(
        ownUserId: session.userId,
        entries: [
          DayDivider(id: 'd1', day: _now),
          MessageEntry(
            id: 'm1',
            sender: '@bob:example.org',
            time: _now,
            body: 'Hi there',
          ),
          UndecryptableEntry(id: 'u1', sender: '@bob:example.org', time: _now),
          MessageEntry(
            id: 'm2',
            sender: session.userId,
            time: _now,
            body: 'Hello Bob',
            isOwn: true,
            sendState: SendState.sending,
          ),
        ],
      );
      await pumpApp(
        tester,
        FakeMatrixClientFactory(saved: [session]),
        size: size,
      );
      await tester.tap(find.text('Bob'));
      await tester.pumpAndSettle();
      return session;
    }

    testWidgets('shows messages, day dividers and undecryptable messages', (
      tester,
    ) async {
      await openBob(tester);
      expect(find.text('Hi there'), findsOneWidget);
      expect(find.text('Hello Bob'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Waiting for this message…'), findsOneWidget);
      expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);
      expect(find.text('end-to-end encrypted'), findsOneWidget);
    });

    testWidgets(
      'sending puts the message in the timeline and clears the composer',
      (tester) async {
        final session = await openBob(tester);
        await tester.enterText(
          find.byKey(const Key('composer.text')),
          '  How are you?  ',
        );
        // The microphone gives way to Send once there is text.
        await tester.pump();
        await tester.tap(find.byKey(const Key('composer.send')));
        await tester.pumpAndSettle();

        expect(find.text('How are you?'), findsOneWidget);
        expect(
          (session.timelines['!bob:example.org']!.entryList.last
                  as MessageEntry)
              .body,
          'How are you?',
        );
        final composer = tester.widget<TextField>(
          find.byKey(const Key('composer.text')),
        );
        expect(composer.controller!.text, isEmpty);
      },
    );

    testWidgets('a short timeline loads older messages', (tester) async {
      final session = await openBob(tester);
      expect(session.timelines['!bob:example.org']!.olderLoads, 1);
    });

    testWidgets('back returns to the chat list on a phone', (tester) async {
      await openBob(tester);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('composer.text')), findsNothing);
      expect(find.text('Team'), findsOneWidget);
    });

    testWidgets('a wide window shows the list and the chat side by side', (
      tester,
    ) async {
      await openBob(tester, size: const Size(1200, 800));
      expect(find.text('Team'), findsOneWidget);
      expect(find.text('Hi there'), findsOneWidget);
      expect(find.byType(BackButton), findsNothing);
    });

    testWidgets('a wide window without a chat welcomes and asks to pick one', (
      tester,
    ) async {
      await pumpApp(
        tester,
        FakeMatrixClientFactory(saved: [_session()]),
        size: const Size(1200, 800),
      );
      expect(find.byKey(const Key('welcome')), findsOneWidget);
      expect(find.text('Pick a chat on the left to start.'), findsOneWidget);
    });
  });
}
