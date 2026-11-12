// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:oxitalk/src/app/file_actions.dart';
import 'package:oxitalk/src/app/link_inbox.dart';
import 'package:oxitalk/src/app/matrix_link.dart';
import 'package:oxitalk/src/app/providers.dart';
import 'package:oxitalk/src/app/router.dart';
import 'package:oxitalk/src/features/chat/jump.dart';
import 'package:oxitalk/src/features/people/user_profile.dart';
import 'package:oxitalk/src/features/share/share_inbox.dart';
import 'package:oxitalk/src/matrix/api/matrix.dart';
import 'package:oxitalk/src/matrix/fakes/fakes.dart';

import 'support/app.dart';

const _me = '@me:acme.com';
const _work = '@me:globex.org';
const _lab = '@me:initech.io';
const _team = '!team:acme.com';
const _bobDm = '!bob:acme.com';

FakeSession _session({
  String userId = _me,
  List<Room> rooms = const [
    Room(id: _team, name: 'Team'),
    Room(id: _bobDm, name: 'Robert', isDm: true),
  ],
  List<TimelineEntry> entries = const [],
}) {
  final session = FakeSession(userId: userId, rooms: rooms);
  for (final room in rooms) {
    session.timelines[room.id] = FakeTimeline(
      ownUserId: userId,
      entries: room.id == _team ? entries : const [],
    );
  }
  return session;
}

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));

GoRouterState _route(WidgetTester tester) =>
    _container(tester).read(routerProvider).state;

/// The open room's ID, `null` on the chat list and elsewhere.
String? _openRoom(WidgetTester tester) =>
    _route(tester).pathParameters['roomId'];

String? _active(WidgetTester tester) =>
    _container(tester).read(activeAccountProvider);

/// Lets a link be opened: that waits for the room lists, then shows its dialog.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pumpAndSettle();
}

void main() {
  group('the command line', () {
    test('a link is opened, not shared', () {
      final args = [
        'matrix:r/team:acme.com',
        'https://matrix.to/#/%23team%3Aacme.com',
        'https://oxitalk.com',
      ];
      expect(linkFromArgs(args), 'matrix:r/team:acme.com');
      expect(sharedFromArgs(args).text, 'https://oxitalk.com');
    });
  });

  group('a link from outside', () {
    testWidgets('to a joined room opens it', (tester) async {
      final links = FakeLinkSource()
        ..openedBeforeStart(
          'https://matrix.to/#/%21team%3Aacme.com?via=acme.com',
        );
      await pumpApp(
        tester,
        FakeMatrixClientFactory(saved: [_session()]),
        links: links,
      );
      await _settle(tester);
      expect(_openRoom(tester), _team);
      expect(find.byKey(const Key('composer.text')), findsOneWidget);
    });

    testWidgets('by the room\'s address opens the room it names', (
      tester,
    ) async {
      final session = _session()
        ..mentionRoomList = [
          const MentionRoom(
            roomId: _team,
            name: 'Team',
            alias: '#team:acme.com',
          ),
        ];
      final links = FakeLinkSource();
      await pumpApp(
        tester,
        FakeMatrixClientFactory(saved: [session]),
        links: links,
      );
      await _settle(tester);
      expect(_openRoom(tester), isNull);
      // While the app runs, as matrix.to's page hands it over.
      links.open('matrix:r/team%3Aacme.com?action=join&via=acme.com');
      await _settle(tester);
      expect(_openRoom(tester), _team);
    });

    testWidgets('to a room not joined asks, then joins through via', (
      tester,
    ) async {
      const link = RoomLink('!new:other.org', via: ['other.org', 'x.org']);
      final session = _session();
      session.addresses[link.address] = const Room(
        id: '!new:other.org',
        name: 'New',
      );
      session.timelines['!new:other.org'] = FakeTimeline(ownUserId: _me);
      final links = FakeLinkSource()
        ..openedBeforeStart(
          'https://matrix.to/#/!new:other.org?via=other.org&via=x.org',
        );
      await pumpApp(
        tester,
        FakeMatrixClientFactory(saved: [session]),
        links: links,
      );
      await _settle(tester);
      expect(find.byKey(const Key('link.joinDialog')), findsOneWidget);
      expect(find.text('Join !new:other.org?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('link.join')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('link.joinDialog')), findsNothing);
      expect(_openRoom(tester), '!new:other.org');
    });

    testWidgets('a join cancelled leaves everything as it was', (tester) async {
      final links = FakeLinkSource()
        ..openedBeforeStart('matrix:roomid/new%3Aother.org?action=join');
      await pumpApp(
        tester,
        FakeMatrixClientFactory(saved: [_session()]),
        links: links,
      );
      await _settle(tester);
      await tester.tap(find.byKey(const Key('link.joinCancel')));
      await tester.pumpAndSettle();
      expect(_openRoom(tester), isNull);
      expect(find.text('Team'), findsOneWidget);
    });

    testWidgets('a join that fails says so', (tester) async {
      final links = FakeLinkSource()
        ..openedBeforeStart('https://matrix.to/#/#gone:other.org');
      await pumpApp(
        tester,
        FakeMatrixClientFactory(saved: [_session()]),
        links: links,
      );
      await _settle(tester);
      await tester.tap(find.byKey(const Key('link.join')));
      await tester.pumpAndSettle();
      expect(find.text('That isn’t a room OxiTalk can join'), findsOneWidget);
      expect(_openRoom(tester), isNull);
    });

    testWidgets(
      'with two accounts, the join dialog joins with the one picked',
      (tester) async {
        const link = RoomLink('#new:other.org');
        final home = _session();
        final work = _session(userId: _work, rooms: const []);
        work.addresses[link.address] = const Room(id: '!new:x', name: 'New');
        final links = FakeLinkSource()
          ..openedBeforeStart('matrix:r/new:other.org');
        await pumpApp(
          tester,
          FakeMatrixClientFactory(saved: [home, work]),
          links: links,
        );
        await _settle(tester);
        expect(find.byKey(const Key('link.joinAs.$_work')), findsOneWidget);
        await tester.tap(find.byKey(const Key('link.joinAs.$_work')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('link.join')));
        await tester.pumpAndSettle();
        expect(_active(tester), _work);
        expect(_openRoom(tester), '!new:x');
      },
    );

    testWidgets('a room only another account is in opens in that account', (
      tester,
    ) async {
      final home = _session(rooms: const []);
      final work = _session(userId: _work);
      final links = FakeLinkSource()
        ..openedBeforeStart('https://matrix.to/#/!team:acme.com');
      await pumpApp(
        tester,
        FakeMatrixClientFactory(saved: [home, work]),
        links: links,
      );
      await _settle(tester);
      expect(_active(tester), _work);
      expect(_openRoom(tester), _team);
    });

    testWidgets(
      'a room several accounts are in opens in the active one if it is among them',
      (tester) async {
        final links = FakeLinkSource()
          ..openedBeforeStart('https://matrix.to/#/!team:acme.com');
        await pumpApp(
          tester,
          FakeMatrixClientFactory(
            saved: [
              _session(),
              _session(userId: _work),
            ],
          ),
          links: links,
        );
        await _settle(tester);
        expect(find.byKey(const Key('link.pickAccount')), findsNothing);
        expect(_active(tester), _me);
        expect(_openRoom(tester), _team);
      },
    );

    testWidgets('else the user picks the account', (tester) async {
      final links = FakeLinkSource()
        ..openedBeforeStart('https://matrix.to/#/!team:acme.com');
      await pumpApp(
        tester,
        FakeMatrixClientFactory(
          saved: [
            _session(rooms: const []),
            _session(userId: _work),
            _session(userId: _lab),
          ],
        ),
        links: links,
      );
      await _settle(tester);
      expect(find.byKey(const Key('link.pickAccount')), findsOneWidget);
      await tester.tap(find.byKey(const Key('link.account.$_lab')));
      await tester.pumpAndSettle();
      expect(_active(tester), _lab);
      expect(_openRoom(tester), _team);
    });

    testWidgets('waits for the sign-in, then opens', (tester) async {
      final links = FakeLinkSource()
        ..openedBeforeStart('https://matrix.to/#/!team:acme.com');
      await pumpApp(
        tester,
        FakeMatrixClientFactory(
          rooms: const [Room(id: _team, name: 'Team')],
        ),
        links: links,
      );
      await _settle(tester);
      expect(find.text('Sign in'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('login.username')), 'me');
      await tester.enterText(find.byKey(const Key('login.password')), 'secret');
      await tester.tap(find.byKey(const Key('login.submit')));
      await tester.pumpAndSettle();
      expect(_openRoom(tester), _team);
    });

    testWidgets('waits while the account is unverified', (tester) async {
      final session = _session();
      session.verification.value = VerificationStatus.unverified;
      final links = FakeLinkSource()
        ..openedBeforeStart('https://matrix.to/#/!team:acme.com');
      await pumpApp(
        tester,
        FakeMatrixClientFactory(saved: [session]),
        links: links,
      );
      await _settle(tester);
      expect(_route(tester).matchedLocation, Routes.verify);
      session.verification.value = VerificationStatus.verified;
      await tester.pumpAndSettle();
      expect(_openRoom(tester), _team);
    });

    testWidgets('to a message opens its room at it', (tester) async {
      final links = FakeLinkSource()
        ..openedBeforeStart(
          r'https://matrix.to/#/!team:acme.com/$e2?via=acme.com',
        );
      await pumpApp(
        tester,
        FakeMatrixClientFactory(saved: [_session()]),
        links: links,
      );
      await _settle(tester);
      expect(_openRoom(tester), _team);
      final jump = _container(tester).read(chatJumpProvider((_me, _team)));
      expect(jump.highlight, r'$e2');
    });

    testWidgets('to a person opens their profile', (tester) async {
      final links = FakeLinkSource()
        ..openedBeforeStart('matrix:u/carol:acme.com');
      await pumpApp(
        tester,
        FakeMatrixClientFactory(saved: [_session()]),
        links: links,
      );
      await _settle(tester);
      expect(find.byType(UserProfileView), findsOneWidget);
      expect(find.text('@carol:acme.com'), findsWidgets);
    });

    testWidgets('action=chat opens the direct chat there is', (tester) async {
      final session = _session()..dms['@bob:acme.com'] = _bobDm;
      final links = FakeLinkSource()
        ..openedBeforeStart('matrix:u/bob%3Aacme.com?action=chat');
      await pumpApp(
        tester,
        FakeMatrixClientFactory(saved: [session]),
        links: links,
      );
      await _settle(tester);
      expect(find.byType(UserProfileView), findsNothing);
      expect(_openRoom(tester), _bobDm);
    });

    testWidgets('action=chat without one offers it from the profile', (
      tester,
    ) async {
      final links = FakeLinkSource()
        ..openedBeforeStart('matrix:u/carol%3Aacme.com?action=chat');
      await pumpApp(
        tester,
        FakeMatrixClientFactory(saved: [_session()]),
        links: links,
      );
      await _settle(tester);
      expect(find.byType(UserProfileView), findsOneWidget);
    });

    testWidgets('one OxiTalk can\'t open says so, nothing else', (
      tester,
    ) async {
      final links = FakeLinkSource()
        ..openedBeforeStart('https://matrix.to/#/+group:acme.com');
      await pumpApp(
        tester,
        FakeMatrixClientFactory(saved: [_session()]),
        links: links,
      );
      await _settle(tester);
      expect(find.text('OxiTalk can’t open this link'), findsOneWidget);
      expect(_openRoom(tester), isNull);
    });
  });

  testWidgets('a matrix.to link tapped in a message opens in the app', (
    tester,
  ) async {
    final files = FakeFileActions();
    final session = _session(
      rooms: const [
        Room(id: _team, name: 'Team'),
        Room(id: '!ops:acme.com', name: 'Ops'),
      ],
      entries: [
        MessageEntry(
          id: r'$m1',
          sender: '@bob:acme.com',
          time: DateTime(2026, 11, 11, 9),
          body: 'See https://matrix.to/#/!ops:acme.com there',
        ),
      ],
    );
    final links = FakeLinkSource()
      ..openedBeforeStart('https://matrix.to/#/!team:acme.com');
    await pumpApp(
      tester,
      FakeMatrixClientFactory(saved: [session]),
      links: links,
      files: files,
    );
    await _settle(tester);
    expect(_openRoom(tester), _team);
    await tester.tapOnText(
      find.textRange.ofSubstring('https://matrix.to/#/!ops:acme.com'),
    );
    await tester.pumpAndSettle();
    expect(files.launched, isEmpty);
    expect(_openRoom(tester), '!ops:acme.com');
  });

  group('Settings › Messages on Android', () {
    testWidgets('tells whether matrix.to links open here and leads there', (
      tester,
    ) async {
      final settings = FakeLinkSettings(opens: false);
      await pumpApp(
        tester,
        FakeMatrixClientFactory(saved: [_session()]),
        linkSettings: settings,
      );
      await _settle(tester);
      _container(tester).read(routerProvider).go(Routes.settings);
      await tester.pumpAndSettle();
      await openSettingsSection(tester, 'messages');
      expect(find.text('Open matrix.to links in OxiTalk'), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('settings.matrixToLinks.state')))
            .data,
        'Off',
      );
      await tester.ensureVisible(
        find.byKey(const Key('settings.matrixToLinks')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings.matrixToLinks')));
      await tester.pumpAndSettle();
      expect(settings.opened, 1);
    });

    testWidgets('not elsewhere', (tester) async {
      await pumpApp(
        tester,
        FakeMatrixClientFactory(saved: [_session()]),
        size: const Size(1200, 800),
        linkSettings: FakeLinkSettings(opens: true),
      );
      await _settle(tester);
      _container(tester).read(routerProvider).go(Routes.settings);
      await tester.pumpAndSettle();
      await openSettingsSection(tester, 'messages');
      expect(find.byKey(const Key('settings.matrixToLinks')), findsNothing);
    }, variant: desktop);
  });
}
