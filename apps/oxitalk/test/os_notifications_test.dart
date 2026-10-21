import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oxitalk/src/app/notification_service.dart';
import 'package:oxitalk/src/app/os_notifications.dart';
import 'package:oxitalk/src/app/ui_prefs.dart';
import 'package:oxitalk/src/matrix/api/matrix.dart';
import 'package:oxitalk/src/matrix/fakes/fakes.dart';

import 'support/app.dart';

const _me = '@me:acme.com';
const _bob = '@bob:acme.com';
const _wide = Size(1200, 800);

MessageNotification _message(
  String room,
  String text, {
  String sender = _bob,
  String senderName = 'Bob',
  String? roomName,
  bool isDm = false,
  bool sound = true,
  String? thread,
  String? eventId,
}) => MessageNotification(
  roomId: room,
  roomName: roomName ?? room,
  senderId: sender,
  senderName: senderName,
  text: text,
  isDm: isDm,
  sound: sound,
  threadRoot: thread,
  eventId: eventId,
  time: DateTime(2026, 10, 21, 12),
);

/// The rules alone, with what the fakes say about prefs and focus.
({AccountNotifications notifications, FakeNotificationPresenter presenter})
_rules({
  DeviceNotificationPrefs prefs = const DeviceNotificationPrefs(),
  String? lookingAt,
}) {
  final presenter = FakeNotificationPresenter();
  return (
    notifications: AccountNotifications(
      account: _me,
      presenter: presenter,
      prefs: () => prefs,
      isLookingAt: (room) => room == lookingAt,
    ),
    presenter: presenter,
  );
}

void main() {
  group('the rules', () {
    test('one notification per room, updated: room name, “Sender: text”; '
        'a direct chat without the sender', () {
      final (:notifications, :presenter) = _rules();
      notifications
        ..onMessage(_message('!team', 'hello', roomName: 'Team'))
        ..onMessage(
          _message('!team', 'lunch?', roomName: 'Team', sound: false),
        );
      final id = notificationId(_me, '!team');
      expect(presenter.shown.keys, [id]);
      final shown = presenter.shown[id]!;
      expect(shown.title, 'Team');
      expect(shown.body, 'Bob: lunch?');
      expect(shown.count, 2);
      expect([for (final line in shown.lines) line.text], ['hello', 'lunch?']);
      expect(shown.sound, isFalse);
      expect(shown.group, _me);

      notifications.onMessage(
        _message('!bob', 'hi', roomName: 'Bob', isDm: true),
      );
      expect(presenter.shown[notificationId(_me, '!bob')]!.body, 'hi');
    });

    test('nothing for the user’s own message or the room they look at', () {
      final (:notifications, :presenter) = _rules(lookingAt: '!open');
      notifications
        ..onMessage(_message('!team', 'mine', sender: _me))
        ..onMessage(_message('!open', 'seen already'));
      expect(presenter.shown, isEmpty);
      notifications.onMessage(_message('!team', 'from Bob'));
      expect(presenter.shown, hasLength(1));
    });

    test('with the text hidden only “New message” shows, no sender either', () {
      final (:notifications, :presenter) = _rules(
        prefs: const DeviceNotificationPrefs(showText: false),
      );
      notifications.onMessage(_message('!team', 'the secret plan'));
      final shown = presenter.shown.values.single;
      expect(shown.body, 'New message');
      expect(shown.lines.single.text, 'New message');
      expect(shown.payload, isNot(contains('secret')));
    });

    test('turned off, or with sound off, as the device prefs say', () {
      var (:notifications, :presenter) = _rules(
        prefs: const DeviceNotificationPrefs(enabled: false),
      );
      notifications.onMessage(_message('!team', 'hello'));
      expect(presenter.shown, isEmpty);

      (:notifications, :presenter) = _rules(
        prefs: const DeviceNotificationPrefs(sound: false),
      );
      notifications.onMessage(_message('!team', 'hello'));
      expect(presenter.shown.values.single.sound, isFalse);
    });

    test(
      'taken away once the room’s count drops to 0, not before it counted',
      () {
        final (:notifications, :presenter) = _rules();
        const room = Room(id: '!team', name: 'Team');
        notifications
          ..onMessage(_message('!team', 'hello'))
          // The room list hasn't counted the message yet.
          ..onRooms(const [room]);
        expect(presenter.shown, hasLength(1));
        notifications.onRooms([
          room.copyWith(unreadCount: 1, unreadNotifications: 1),
        ]);
        expect(notifications.total, 1);
        expect(presenter.shown, hasLength(1));
        // Read here or on another device.
        notifications.onRooms(const [room]);
        expect(presenter.shown, isEmpty);
        expect(presenter.calls.last, 'cancel ${notificationId(_me, '!team')}');
        expect(notifications.total, 0);
      },
    );

    test('taken away when the room is muted, left, or opened', () {
      final (:notifications, :presenter) = _rules();
      notifications
        ..onMessage(_message('!a', 'one'))
        ..onMessage(_message('!b', 'two'))
        ..onMessage(_message('!c', 'three'))
        ..onRooms([
          const Room(
            id: '!a',
            name: 'A',
            unreadCount: 1,
            unreadNotifications: 1,
            notificationMode: NotificationMode.mute,
          ),
          const Room(id: '!c', name: 'C', unreadNotifications: 1),
        ]);
      expect(notifications.shownRooms, ['!c']);
      notifications.onLookingAt('!c');
      expect(presenter.shown, isEmpty);
    });

    test(
      'an invitation says so; the target opens account, room and thread',
      () {
        final (:notifications, :presenter) = _rules();
        notifications.onMessage(
          MessageNotification(
            roomId: '!new',
            roomName: 'New room',
            senderId: _bob,
            senderName: 'Bob',
            isInvite: true,
            time: DateTime(2026, 10, 21, 12),
          ),
        );
        expect(presenter.shown.values.single.body, 'Invited you');
        notifications.onMessage(
          _message('!team', 'in a thread', thread: r'$root'),
        );
        final target = NotificationTarget.decode(
          presenter.shown[notificationId(_me, '!team')]!.payload,
        );
        expect(
          target,
          const NotificationTarget(_me, '!team', thread: r'$root'),
        );
        expect(NotificationTarget.decode('not json'), isNull);
      },
    );

    test('a room’s ID is the same on every start and differs by account', () {
      expect(notificationId(_me, '!team'), notificationId(_me, '!team'));
      expect(
        notificationId(_me, '!team'),
        isNot(notificationId(_bob, '!team')),
      );
      expect(notificationId(_me, '!team'), inInclusiveRange(0, 0x7fffffff));
    });
  });

  group('in the app', () {
    Future<(FakeSession, FakeNotificationPresenter)> open(
      WidgetTester tester, {
      List<FakeSession>? sessions,
      MemoryUiPrefs? ui,
      FakeNotificationPresenter? presenter,
      Size size = _wide,
    }) async {
      final session = FakeSession(
        userId: _me,
        rooms: const [
          Room(id: '!team', name: 'Team'),
          Room(id: '!other', name: 'Other'),
        ],
      );
      final notifications = presenter ?? FakeNotificationPresenter();
      await pumpApp(
        tester,
        FakeMatrixClientFactory(saved: sessions ?? [session]),
        size: size,
        notifications: notifications,
        ui: ui,
      );
      return (sessions?.first ?? session, notifications);
    }

    void counted(FakeSession session, String room, int count) =>
        session.roomList = [
          for (final r in session.roomList)
            r.id == room
                ? r.copyWith(unreadCount: count, unreadNotifications: count)
                : r,
        ];

    testWidgets('starts with the app and asks for permission once enabled', (
      tester,
    ) async {
      final (_, presenter) = await open(tester);
      expect(presenter.calls.take(2), ['start', 'permission']);
    });

    testWidgets('none for the open chat while the window has the focus; '
        'opening a chat takes its notification away', (tester) async {
      final (session, presenter) = await open(tester);
      await tester.tap(find.text('Team'));
      await tester.pumpAndSettle();

      session.notificationItems.add(_message('!team', 'seen'));
      await tester.pumpAndSettle();
      expect(presenter.shown, isEmpty);

      // The window loses the focus: the open chat notifies too.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      session.notificationItems.add(_message('!team', 'while away'));
      await tester.pumpAndSettle();
      expect(presenter.shown.keys, [notificationId(_me, '!team')]);
      // Back to the window, on that chat: taken away.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(presenter.shown, isEmpty);

      session.notificationItems.add(_message('!other', 'elsewhere'));
      await tester.pumpAndSettle();
      expect(presenter.shown.keys, [notificationId(_me, '!other')]);
      await tester.tap(find.text('Other'));
      await tester.pumpAndSettle();
      expect(presenter.shown, isEmpty);
    });

    testWidgets('read elsewhere: the count drops to 0 and it goes; the badge '
        'shows the total', (tester) async {
      final (session, presenter) = await open(tester);
      session.notificationItems.add(_message('!other', 'hello'));
      counted(session, '!other', 2);
      await tester.pumpAndSettle();
      expect(presenter.shown, hasLength(1));
      expect(presenter.badge, 2);

      counted(session, '!other', 0);
      await tester.pumpAndSettle();
      expect(presenter.shown, isEmpty);
      expect(presenter.badge, 0);
    });

    testWidgets('a tap opens the account, the chat and the thread', (
      tester,
    ) async {
      final work = FakeSession(
        userId: '@me:work.com',
        rooms: const [Room(id: '!work', name: 'Work room')],
      );
      work.timelines['!work'] = FakeTimeline(ownUserId: '@me:work.com');
      final home = FakeSession(
        userId: _me,
        rooms: const [Room(id: '!team', name: 'Team')],
      );
      final (_, presenter) = await open(tester, sessions: [home, work]);
      expect(find.text('Work room'), findsNothing);

      work.notificationItems.add(
        _message('!work', 'look', roomName: 'Work room', thread: r'$root'),
      );
      await tester.pumpAndSettle();
      presenter.tap(notificationId('@me:work.com', '!work'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('chat.title')), findsOneWidget);
      expect(find.text('Work room'), findsWidgets);
      expect(find.byKey(const Key('thread.close')), findsOneWidget);
      // It is open and focused now, so the notification is gone.
      expect(presenter.shown, isEmpty);
    });

    testWidgets('Settings › Notifications: this device’s switches', (
      tester,
    ) async {
      final ui = MemoryUiPrefs();
      final presenter = FakeNotificationPresenter();
      final (session, _) = await open(
        tester,
        ui: ui,
        presenter: presenter,
        size: const Size(800, 2000),
      );
      await pickFromAccountMenu(tester, 'accountMenu.settings');
      await tester.scrollUntilVisible(
        find.byKey(const Key('settings.notifications')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('settings.notifications')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('settings.device.showText')));
      await tester.pumpAndSettle();
      expect(ui.notificationText, isFalse);
      session.notificationItems.add(_message('!other', 'the secret plan'));
      await tester.pumpAndSettle();
      expect(presenter.shown.values.single.body, 'New message');

      await tester.tap(find.byKey(const Key('settings.device.sound')));
      await tester.pumpAndSettle();
      expect(ui.notificationSound, isFalse);

      // Off takes them away; on asks for permission, and a refusal keeps it off.
      await tester.tap(find.byKey(const Key('settings.device.enabled')));
      await tester.pumpAndSettle();
      expect(ui.notificationsEnabled, isFalse);
      expect(presenter.shown, isEmpty);
      presenter
        ..grantPermission = false
        ..calls.clear();
      await tester.tap(find.byKey(const Key('settings.device.enabled')));
      await tester.pumpAndSettle();
      expect(presenter.calls, contains('permission'));
      expect(ui.notificationsEnabled, isFalse);
      expect(find.textContaining('not allowed'), findsOneWidget);
      presenter.grantPermission = true;
      await tester.tap(find.byKey(const Key('settings.device.enabled')));
      await tester.pumpAndSettle();
      expect(ui.notificationsEnabled, isTrue);
    });
  });
}
