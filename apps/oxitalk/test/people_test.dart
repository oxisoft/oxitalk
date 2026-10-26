import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oxitalk/src/app/router.dart';
import 'package:oxitalk/src/features/chat_info/chat_info.dart';
import 'package:oxitalk/src/matrix/api/matrix.dart';
import 'package:oxitalk/src/matrix/fakes/fakes.dart';

import 'support/app.dart';

const _wide = Size(1400, 900);
const _me = '@me:acme.com';
const _bob = '@bob:acme.com';
const _room = '!team:acme.com';

MessageEntry _message(String id, String body, {String sender = _bob}) =>
    MessageEntry(
      id: id,
      sender: sender,
      senderName: sender == _bob ? 'Bob' : 'Me',
      time: DateTime(2026, 10, 26, 9),
      body: body,
      formatted: body.contains('Bob,')
          ? const [
              RichBlock(ParagraphBlock(), [
                RichSpan('Bob', mention: _bob),
                RichSpan(', look'),
              ]),
            ]
          : null,
      isOwn: sender == _me,
      meta: EventMeta(eventId: '\$$id', isEditable: sender == _me),
    );

FakeSession _session() =>
    FakeSession(
        userId: _me,
        rooms: const [Room(id: _room, name: 'Team')],
      )
      ..members[_room] = const [
        RoomMember(userId: _me, displayName: 'Me'),
        RoomMember(userId: _bob, displayName: 'Bob'),
      ]
      ..profiles[_bob] = const UserProfile(
        userId: _bob,
        displayName: 'Bob Builder',
        verified: false,
      )
      ..timelines[_room] = FakeTimeline(
        ownUserId: _me,
        entries: [
          _message('hello', 'Hello there'),
          _message('pill', 'Bob, look', sender: _me),
        ],
      );

Future<FakeSession> _open(
  WidgetTester tester, {
  Size size = _wide,
  FakeSession? session,
}) async {
  final s = session ?? _session();
  await pumpApp(tester, FakeMatrixClientFactory(saved: [s]), size: size);
  await tester.tap(find.text('Team'));
  await tester.pumpAndSettle();
  return s;
}

Future<void> _openProfile(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('message.sender')).first);
  await tester.pumpAndSettle();
}

final _profile = find.byKey(const Key('profile'));

void main() {
  group('the profile', () {
    testWidgets('tapping a sender’s name shows their profile in a dialog on '
        'desktop: picture, name, ID, not verified, and the actions', (
      tester,
    ) async {
      await _open(tester);
      await _openProfile(tester);
      expect(
        find.ancestor(of: _profile, matching: find.byType(Dialog)),
        findsOneWidget,
      );
      expect(find.text('Bob Builder'), findsOneWidget);
      expect(find.text(_bob), findsOneWidget);
      expect(find.byKey(const Key('profile.verified.false')), findsOneWidget);
      for (final action in ['message', 'verify', 'ignore', 'report']) {
        expect(find.byKey(Key('profile.$action')), findsOneWidget);
      }
    }, variant: desktop);

    testWidgets('on a phone it is a sheet; the avatar opens it too', (
      tester,
    ) async {
      await _open(tester, size: const Size(400, 800));
      await tester.tap(find.byKey(const Key('senderAvatar.hello')));
      await tester.pumpAndSettle();
      expect(
        find.ancestor(of: _profile, matching: find.byType(BottomSheet)),
        findsOneWidget,
      );
      expect(find.text('Bob Builder'), findsOneWidget);
    });

    testWidgets('a mention pill in a message opens the person', (tester) async {
      await _open(tester);
      // The pill is the start of the message's text.
      final text = find.textContaining('Bob, look', findRichText: true);
      await tester.tapAt(tester.getTopLeft(text) + const Offset(8, 8));
      await tester.pumpAndSettle();
      expect(find.text('Bob Builder'), findsOneWidget);
    }, variant: desktop);

    testWidgets('a member of the chat info opens their profile', (
      tester,
    ) async {
      await _open(tester);
      await tester.tap(find.byKey(const Key('chat.title')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(ChatInfoPane),
          matching: find.byKey(const Key('member.$_bob')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Bob Builder'), findsOneWidget);
    }, variant: desktop);

    testWidgets('Send message opens the direct chat, made if there is none', (
      tester,
    ) async {
      final session = await _open(tester);
      await _openProfile(tester);
      await tester.tap(find.byKey(const Key('profile.message')));
      await tester.pumpAndSettle();
      expect(_profile, findsNothing);
      expect(session.roomList.first.name, _bob);
      expect(session.roomList.first.isDm, isTrue);
    }, variant: desktop);

    testWidgets('Copy puts the user ID on the clipboard', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      await _open(tester);
      await _openProfile(tester);
      await tester.tap(find.byKey(const Key('profile.copyId')));
      await tester.pumpAndSettle();
      expect(copied, _bob);
    }, variant: desktop);

    testWidgets('Verify asks them by emoji', (tester) async {
      final session = await _open(tester);
      await _openProfile(tester);
      await tester.tap(find.byKey(const Key('profile.verify')));
      // Waiting spins: no settling.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(session.verifiedUsers, [_bob]);
      expect(find.text('Waiting for Bob Builder'), findsOneWidget);
      await tester.tap(find.text('Cancel').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }, variant: desktop);

    testWidgets(
      'a verified person has no Verify; one without identity says so',
      (tester) async {
        final session = _session()
          ..profiles[_bob] = const UserProfile(userId: _bob, verified: true);
        await _open(tester, session: session);
        await _openProfile(tester);
        expect(find.byKey(const Key('profile.verified.true')), findsOneWidget);
        expect(find.byKey(const Key('profile.verify')), findsNothing);
      },
      variant: desktop,
    );

    testWidgets('Ignore explains first; then they are ignored and it turns '
        'into Unignore', (tester) async {
      final session = await _open(tester);
      await _openProfile(tester);
      await tester.tap(find.byKey(const Key('profile.ignore')));
      await tester.pumpAndSettle();
      expect(find.text('Ignore Bob Builder?'), findsOneWidget);
      expect(
        find.textContaining('messages and invites are hidden'),
        findsWidgets,
      );
      await tester.tap(find.byKey(const Key('ignore.confirm')));
      await tester.pumpAndSettle();
      expect(session.ignored.value, [_bob]);
      expect(find.byKey(const Key('profile.unignore')), findsOneWidget);
      expect(find.byKey(const Key('profile.ignoredNote')), findsOneWidget);

      await tester.tap(find.byKey(const Key('profile.unignore')));
      await tester.pumpAndSettle();
      expect(session.ignored.value, isEmpty);
      expect(find.byKey(const Key('profile.ignore')), findsOneWidget);
    }, variant: desktop);

    testWidgets('cancelling Ignore ignores no one', (tester) async {
      final session = await _open(tester);
      await _openProfile(tester);
      await tester.tap(find.byKey(const Key('profile.ignore')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(session.ignored.value, isEmpty);
    }, variant: desktop);

    testWidgets('Report user sends the reason and can ignore them too', (
      tester,
    ) async {
      final session = await _open(tester);
      await _openProfile(tester);
      await tester.tap(find.byKey(const Key('profile.report')));
      await tester.pumpAndSettle();
      expect(find.text('Report Bob Builder?'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('report.reason')), ' spam ');
      await tester.tap(find.byKey(const Key('report.ignore')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('report.confirm')));
      await tester.pumpAndSettle();
      expect(session.reports, ['user $_bob spam']);
      expect(session.ignored.value, [_bob]);
      expect(find.textContaining('Reported and ignored'), findsOneWidget);
    }, variant: desktop);

    testWidgets('one’s own profile has no actions', (tester) async {
      final session = _session()
        ..timelines[_room] = FakeTimeline(
          ownUserId: _me,
          entries: [_message('hello', 'Hello there')],
        );
      await _open(tester, session: session);
      await tester.tap(find.byKey(const Key('chat.title')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(ChatInfoPane),
          matching: find.byKey(const Key('member.$_me')),
        ),
      );
      await tester.pumpAndSettle();
      expect(_profile, findsOneWidget);
      expect(find.byKey(const Key('profile.message')), findsNothing);
      expect(find.byKey(const Key('profile.report')), findsNothing);
    }, variant: desktop);
  });

  group('reporting a message', () {
    Future<void> more(WidgetTester tester, String text) async {
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.text(text)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('hover.more')).hitTestable().first);
      await tester.pumpAndSettle();
    }

    testWidgets('the menu of someone else’s message has Report…: a reason, '
        'and ignoring the sender if ticked', (tester) async {
      final session = await _open(tester);
      await more(tester, 'Hello there');
      await tester.tap(find.text('Report…').last);
      await tester.pumpAndSettle();
      expect(find.text('Report this message?'), findsOneWidget);
      expect(find.text('Also ignore Bob'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('report.reason')), 'rude');
      await tester.tap(find.byKey(const Key('report.confirm')));
      await tester.pumpAndSettle();
      expect(session.reports, [r'event !team:acme.com $hello rude']);
      expect(session.ignored.value, isEmpty);
    }, variant: desktop);

    testWidgets('the user’s own message has no Report', (tester) async {
      await _open(tester);
      await more(tester, 'Bob, look');
      expect(find.text('Report…'), findsNothing);
    }, variant: desktop);

    testWidgets('on a phone the message sheet has Report, in red', (
      tester,
    ) async {
      final session = await _open(tester, size: const Size(400, 800));
      await tester.tap(find.text('Hello there'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Report…'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('report.ignore')));
      await tester.tap(find.byKey(const Key('report.confirm')));
      await tester.pumpAndSettle();
      expect(session.reports, [r'event !team:acme.com $hello null']);
      expect(session.ignored.value, [_bob]);
    });
  });

  group('Settings › Account › Ignored users', () {
    Future<FakeSession> openAccount(WidgetTester tester) async {
      final session = _session()..ignored.value = [_bob, '@eve:acme.com'];
      await pumpApp(
        tester,
        FakeMatrixClientFactory(saved: [session]),
        size: _wide,
      );
      ProviderScope.containerOf(tester.element(find.byType(MaterialApp)))
          .read(routerProvider)
          .go(Routes.settingsAccount(session.userId));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('settings.ignored')));
      await tester.pumpAndSettle();
      return session;
    }

    testWidgets('lists them, each with Unignore', (tester) async {
      final session = await openAccount(tester);
      expect(find.byKey(const Key('ignored.row.$_bob')), findsOneWidget);
      expect(
        find.byKey(const Key('ignored.row.@eve:acme.com')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('ignored.unignore.$_bob')));
      await tester.pumpAndSettle();
      expect(session.ignored.value, ['@eve:acme.com']);
      expect(find.byKey(const Key('ignored.row.$_bob')), findsNothing);

      // A change from another device shows too.
      session.ignored.value = [];
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ignored.none')), findsOneWidget);
    });
  });
}
