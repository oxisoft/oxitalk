import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oxitalk/src/app/window_controls.dart';
import 'package:oxitalk/src/features/chats/badges.dart';
import 'package:oxitalk/src/matrix/api/matrix.dart';
import 'package:oxitalk/src/matrix/fakes/fakes.dart';

import 'support/app.dart';

const _wide = Size(1200, 800);
const _me = '@me:acme.com';

/// A window whose title bar the app draws, with only a Close button.
final class _TitleBarWindow implements WindowControls {
  @override
  bool get drawsTitleBar => true;

  @override
  List<WindowButton> get leftButtons => const [];

  @override
  List<WindowButton> get rightButtons => const [WindowButton.close];

  @override
  Future<void> startDragging() async {}

  @override
  Future<void> doubleClick() async {}

  @override
  Future<void> showMenu() async {}

  @override
  Future<void> press(WindowButton button) async {}
}

/// One room of each kind the badges tell apart.
FakeSession _session() => FakeSession(
  userId: _me,
  rooms: const [
    Room(id: '!loud', name: 'Loud', unreadCount: 3, unreadNotifications: 3),
    Room(
      id: '!quiet',
      name: 'Quiet',
      unreadCount: 5,
      notificationMode: NotificationMode.mentionsAndKeywords,
    ),
    Room(
      id: '!muted',
      name: 'Muted',
      unreadCount: 4,
      notificationMode: NotificationMode.mute,
    ),
    Room(
      id: '!ping',
      name: 'Ping',
      unreadCount: 2,
      unreadNotifications: 1,
      unreadMentions: 1,
      notificationMode: NotificationMode.mentionsAndKeywords,
    ),
    Room(id: '!read', name: 'Read'),
  ],
);

Future<FakeSession> _open(
  WidgetTester tester, {
  WindowControls? window,
  Size size = _wide,
}) async {
  final session = _session();
  await pumpApp(
    tester,
    FakeMatrixClientFactory(saved: [session]),
    size: size,
    window: window,
  );
  return session;
}

Future<void> _rightClick(WidgetTester tester, String room) async {
  await tester.tap(find.text(room), buttons: kSecondaryMouseButton);
  await tester.pumpAndSettle();
}

Room _room(FakeSession session, String id) =>
    session.roomList.firstWhere((room) => room.id == id);

void main() {
  group('badges', () {
    test('follow Element X: mention, count, dot, nothing when muted', () {
      const room = Room(id: '!r', name: 'R');
      expect(badgeOf(room).kind, BadgeKind.none);
      expect(
        badgeOf(room.copyWith(unreadCount: 2, unreadNotifications: 2)),
        isA<RoomBadge>()
            .having((b) => b.kind, 'kind', BadgeKind.notifying)
            .having((b) => b.count, 'count', 2),
      );
      expect(
        badgeOf(
          room.copyWith(
            unreadCount: 3,
            unreadNotifications: 2,
            unreadMentions: 1,
          ),
        ),
        isA<RoomBadge>()
            .having((b) => b.kind, 'kind', BadgeKind.mention)
            .having((b) => b.count, 'count', 2),
      );
      // Chatter in a room for mentions only, or a room marked unread: a dot.
      expect(badgeOf(room.copyWith(unreadCount: 5)).kind, BadgeKind.dot);
      expect(badgeOf(room.copyWith(markedUnread: true)).kind, BadgeKind.dot);
      final muted = room.copyWith(
        unreadCount: 4,
        unreadNotifications: 4,
        unreadMentions: 1,
        notificationMode: NotificationMode.mute,
      );
      expect(badgeOf(muted).kind, BadgeKind.none);
      expect(muted.notifyingCount, 0);
      expect(
        badgeOf(room.copyWith(membership: Membership.invited)).kind,
        BadgeKind.invite,
      );
    });

    test('a room follows its default until it has a mode of its own', () {
      const room = Room(
        id: '!r',
        name: 'R',
        defaultNotificationMode: NotificationMode.mentionsAndKeywords,
      );
      expect(
        room.effectiveNotificationMode,
        NotificationMode.mentionsAndKeywords,
      );
      final muted = room.copyWith(notificationMode: NotificationMode.mute);
      expect(muted.isMuted, isTrue);
      expect(muted.copyWith(notificationMode: null).isMuted, isFalse);
      expect(
        muted.copyWith(unreadCount: 1).notificationMode,
        NotificationMode.mute,
      );
    });

    testWidgets('the list shows each kind; muted rooms count for nothing', (
      tester,
    ) async {
      await _open(tester);
      expect(find.byKey(const Key('badge.notifying.!loud')), findsOneWidget);
      expect(find.byKey(const Key('badge.dot.!quiet')), findsOneWidget);
      expect(find.byKey(const Key('badge.mention.!ping')), findsOneWidget);
      expect(find.text('@ 1'), findsOneWidget);
      expect(find.byKey(const Key('muted.!muted')), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget.key is ValueKey<String> &&
              (widget.key! as ValueKey<String>).value.endsWith('.!muted') &&
              (widget.key! as ValueKey<String>).value.startsWith('badge.'),
        ),
        findsNothing,
      );
      expect(find.byKey(const Key('muted.!loud')), findsNothing);
      // The account's total in the rail: Loud's 3 and Ping's 1, not Quiet's or Muted's.
      expect(find.text('4'), findsOneWidget);
    });

    testWidgets('the narrow list shows them on the pictures', (tester) async {
      await _open(tester);
      await tester.tap(find.byKey(const Key('list.narrow')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('badge.notifying.!loud')), findsOneWidget);
      expect(find.byKey(const Key('badge.mention.!ping')), findsOneWidget);
      expect(find.byKey(const Key('badge.dot.!quiet')), findsOneWidget);
      expect(find.byKey(const Key('badge.muted.!muted')), findsOneWidget);
    });
  });

  group('room list menu', () {
    testWidgets('Notifications ▸ Mute mutes; Default goes back to it', (
      tester,
    ) async {
      final session = await _open(tester);
      await _rightClick(tester, 'Loud');
      await tester.tap(find.byKey(const Key('roomMenu.notifications')));
      await tester.pumpAndSettle();
      // The default is named with what it is, and checked.
      expect(find.text('Default (All messages)'), findsOneWidget);
      expect(
        tester
            .widget<CheckedPopupMenuItem<VoidCallback>>(
              find.byKey(const Key('notify.default')),
            )
            .checked,
        isTrue,
      );
      await tester.tap(find.byKey(const Key('notify.mute')));
      await tester.pumpAndSettle();
      expect(session.notificationCalls, ['mode !loud mute']);
      expect(find.byKey(const Key('muted.!loud')), findsOneWidget);
      expect(find.byKey(const Key('badge.notifying.!loud')), findsNothing);
      expect(find.text('1'), findsOneWidget); // The rail: Ping's 1 alone.

      await _rightClick(tester, 'Loud');
      await tester.tap(find.byKey(const Key('roomMenu.notifications')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CheckedPopupMenuItem<VoidCallback>>(
              find.byKey(const Key('notify.mute')),
            )
            .checked,
        isTrue,
      );
      await tester.tap(find.byKey(const Key('notify.default')));
      await tester.pumpAndSettle();
      expect(session.notificationCalls.last, 'mode !loud default');
      expect(find.byKey(const Key('muted.!loud')), findsNothing);
    });

    testWidgets(
      'Mark as read on an unread room, Mark as unread on a read one',
      (tester) async {
        final session = await _open(tester);
        await _rightClick(tester, 'Loud');
        expect(find.byKey(const Key('roomMenu.markUnread')), findsNothing);
        await tester.tap(find.byKey(const Key('roomMenu.markRead')));
        await tester.pumpAndSettle();
        expect(session.notificationCalls, ['markRead !loud']);
        expect(find.byKey(const Key('badge.notifying.!loud')), findsNothing);

        await _rightClick(tester, 'Read');
        await tester.tap(find.byKey(const Key('roomMenu.markUnread')));
        await tester.pumpAndSettle();
        expect(session.notificationCalls.last, 'markedUnread !read true');
        expect(find.byKey(const Key('badge.dot.!read')), findsOneWidget);
      },
    );

    testWidgets('opening a room marked unread takes the mark away', (
      tester,
    ) async {
      final session = await _open(tester);
      session.roomList = [
        for (final room in session.roomList)
          room.id == '!read' ? room.copyWith(markedUnread: true) : room,
      ];
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('badge.dot.!read')), findsOneWidget);
      await tester.tap(find.text('Read'));
      await tester.pumpAndSettle();
      expect(session.notificationCalls, ['markedUnread !read false']);
      expect(_room(session, '!read').markedUnread, isFalse);
      expect(find.byKey(const Key('badge.dot.!read')), findsNothing);
    });
  });

  group('a chat', () {
    testWidgets('a muted one has the crossed-out bell in its header and the '
        'title bar', (tester) async {
      await _open(tester, window: _TitleBarWindow());
      await tester.tap(find.text('Muted'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('chat.muted')), findsOneWidget);
      expect(find.byKey(const Key('titleBar.muted')), findsOneWidget);

      await tester.tap(find.text('Loud'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('chat.muted')), findsNothing);
      expect(find.byKey(const Key('titleBar.muted')), findsNothing);
    });

    testWidgets('its info leads to its notifications, as in Element X', (
      tester,
    ) async {
      final session = await _open(tester);
      await tester.tap(find.text('Loud'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('chat.title')));
      await tester.pumpAndSettle();
      expect(find.text('Default (All messages)'), findsOneWidget);
      await tester.tap(find.byKey(const Key('info.notifications')));
      await tester.pumpAndSettle();

      SwitchListTile matchDefault() => tester.widget<SwitchListTile>(
        find.byKey(const Key('roomNotifications.matchDefault')),
      );
      bool enabled(String mode) => tester
          .widget<RadioListTile<NotificationMode>>(
            find.byKey(Key('roomNotifications.$mode')),
          )
          .enabled!;
      expect(matchDefault().value, isTrue);
      expect(enabled('mute'), isFalse);

      // Off: the room keeps the default as a mode of its own; then one is picked.
      await tester.tap(find.byKey(const Key('roomNotifications.matchDefault')));
      await tester.pumpAndSettle();
      expect(session.notificationCalls, ['mode !loud allMessages']);
      expect(matchDefault().value, isFalse);
      expect(enabled('mute'), isTrue);
      await tester.tap(find.byKey(const Key('roomNotifications.mute')));
      await tester.pumpAndSettle();
      expect(session.notificationCalls.last, 'mode !loud mute');
      expect(_room(session, '!loud').isMuted, isTrue);

      await tester.tap(find.byKey(const Key('roomNotifications.matchDefault')));
      await tester.pumpAndSettle();
      expect(session.notificationCalls.last, 'mode !loud default');
      expect(_room(session, '!loud').notificationMode, isNull);

      await tester.tap(find.byKey(const Key('roomNotifications.back')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('info.notifications')), findsOneWidget);
    });

    testWidgets('on a phone its notifications are a page of their own', (
      tester,
    ) async {
      final session = await _open(tester, size: const Size(400, 800));
      await tester.tap(find.text('Quiet'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('chat.title')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('info.notifications')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SwitchListTile>(
              find.byKey(const Key('roomNotifications.matchDefault')),
            )
            .value,
        isFalse,
      );
      await tester.tap(find.byKey(const Key('roomNotifications.allMessages')));
      await tester.pumpAndSettle();
      expect(session.notificationCalls, ['mode !quiet allMessages']);
    });
  });
}
