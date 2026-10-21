import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oxitalk/src/matrix/api/matrix.dart';
import 'package:oxitalk/src/matrix/fakes/fakes.dart';

import 'support/app.dart';

const _me = '@me:acme.com';

Room _room(FakeSession session, String id) =>
    session.roomList.firstWhere((room) => room.id == id);

void main() {
  group('settings', () {
    Future<FakeSession> openSettings(
      WidgetTester tester, {
      NotificationSettings settings = const NotificationSettings(
        roomMentions: true,
        invites: true,
      ),
    }) async {
      final session = FakeSession(
        userId: _me,
        rooms: const [
          Room(id: '!bob', name: 'Bob', isDm: true, isOneToOne: true),
          Room(id: '!read', name: 'Read'),
        ],
      )..notificationState.value = settings;
      await pumpApp(
        tester,
        FakeMatrixClientFactory(saved: [session]),
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
      return session;
    }

    testWidgets('defaults, @room, invitations and keywords', (tester) async {
      final session = await openSettings(tester);
      expect(
        find.byKey(const Key('settings.notifications.inconsistent')),
        findsNothing,
      );
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('settings.notifications.group')),
          matching: find.text('Mentions and keywords'),
        ),
      );
      await tester.pumpAndSettle();
      expect(session.notificationCalls, ['default group mentionsAndKeywords']);
      expect(
        tester
            .widget<SegmentedButton<NotificationMode>>(
              find.byKey(const Key('settings.notifications.group')),
            )
            .selected,
        {NotificationMode.mentionsAndKeywords},
      );
      // The group chats in the list follow it; the direct ones don't.
      expect(
        _room(session, '!read').defaultNotificationMode,
        NotificationMode.mentionsAndKeywords,
      );
      expect(
        _room(session, '!bob').defaultNotificationMode,
        NotificationMode.allMessages,
      );

      await tester.tap(
        find.byKey(const Key('settings.notifications.roomMentions')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings.notifications.invites')));
      await tester.pumpAndSettle();
      expect(session.notificationCalls.skip(1), [
        'roomMentions false',
        'invites false',
      ]);

      await tester.tap(
        find.byKey(const Key('settings.notifications.newKeyword')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('settings.notifications.keyword')),
        ' pineapple ',
      );
      await tester.tap(
        find.byKey(const Key('settings.notifications.addKeyword')),
      );
      await tester.pumpAndSettle();
      expect(session.notificationCalls.last, 'keyword+ pineapple');
      expect(find.byKey(const Key('keyword.pineapple')), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('keyword.pineapple')),
          matching: find.byType(Icon),
        ),
      );
      await tester.pumpAndSettle();
      expect(session.notificationCalls.last, 'keyword- pineapple');
      expect(find.byKey(const Key('keyword.pineapple')), findsNothing);
    });

    testWidgets('inconsistent defaults show a warning with a fix', (
      tester,
    ) async {
      final session = await openSettings(
        tester,
        settings: const NotificationSettings(inconsistent: true),
      );
      expect(
        find.byKey(const Key('settings.notifications.inconsistent')),
        findsOneWidget,
      );
      // Without the rules on the server, their switches can't be used.
      expect(
        tester
            .widget<SwitchListTile>(
              find.byKey(const Key('settings.notifications.invites')),
            )
            .onChanged,
        isNull,
      );
      await tester.tap(find.byKey(const Key('settings.notifications.fix')));
      await tester.pumpAndSettle();
      expect(session.notificationCalls, ['fix']);
      expect(
        find.byKey(const Key('settings.notifications.inconsistent')),
        findsNothing,
      );

      await tester.tap(find.byKey(const Key('notificationSettings.back')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('settings.notifications')), findsOneWidget);
    });
  });
}
