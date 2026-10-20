import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oxitalk/src/features/chat_info/chat_info.dart';
import 'package:oxitalk/src/matrix/api/matrix.dart';
import 'package:oxitalk/src/matrix/fakes/fakes.dart';

import 'support/app.dart';

const _me = '@me:acme.com';
const _room = '!team:acme.com';
const _bob = '@bob:acme.com';
const _carol = '@carol:acme.com';
const _dan = '@dan:acme.com';

/// [ownLevel] `null`: the user created the room (version 12 or later), above every level.
Future<FakeSession> _open(WidgetTester tester, {int? ownLevel = 100}) async {
  final session =
      FakeSession(
          userId: _me,
          rooms: const [Room(id: _room, name: 'Team')],
        )
        ..details[_room] = RoomDetails(
          roomId: _room,
          name: 'Team',
          ownPowerLevel: ownLevel,
        )
        ..members[_room] = const [
          RoomMember(
            userId: _me,
            role: MemberRole.admin,
            powerLevel: 100,
            canChangeRole: true,
          ),
          RoomMember(
            userId: _carol,
            displayName: 'Carol',
            role: MemberRole.admin,
            powerLevel: 100,
          ),
          RoomMember(
            userId: _bob,
            displayName: 'Bob',
            canChangeRole: true,
            canRemove: true,
            canBan: true,
          ),
          RoomMember(
            userId: _dan,
            displayName: 'Dan',
            banned: true,
            canUnban: true,
          ),
        ]
        ..dms[_bob] = _room;
  await pumpApp(
    tester,
    FakeMatrixClientFactory(saved: [session]),
    size: const Size(1400, 900),
  );
  await tester.tap(find.text('Team'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('chat.title')));
  await tester.pumpAndSettle();
  return session;
}

Finder _inInfo(Finder finder) =>
    find.descendant(of: find.byType(ChatInfoPane), matching: finder);

Future<void> _menu(WidgetTester tester, String userId, String item) async {
  await tester.tap(_inInfo(find.byKey(Key('member.menu.$userId'))));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('member.$item')));
  await tester.pumpAndSettle();
}

/// The labels the menu of [userId] offers.
Future<List<String>> _items(WidgetTester tester, String userId) async {
  await tester.tap(_inInfo(find.byKey(Key('member.menu.$userId'))));
  await tester.pumpAndSettle();
  final items = [
    for (final item in tester.widgetList<PopupMenuItem<Object>>(
      find.byWidgetPredicate((widget) => widget is PopupMenuItem),
    ))
      (item.key! as ValueKey<String>).value,
  ];
  await tester.tapAt(Offset.zero);
  await tester.pumpAndSettle();
  return items;
}

void main() {
  testWidgets('each member’s menu offers only what the user may do', (
    tester,
  ) async {
    await _open(tester);
    expect(await _items(tester, _bob), [
      'member.message',
      'member.copyId',
      'member.role',
      'member.remove',
      'member.ban',
    ]);
    expect(await _items(tester, _carol), ['member.message', 'member.copyId']);
    expect(await _items(tester, _dan), [
      'member.message',
      'member.copyId',
      'member.unban',
    ]);
    expect(await _items(tester, _me), ['member.copyId', 'member.role']);
    expect(_inInfo(find.text('Banned')), findsOneWidget);
  });

  testWidgets('a role is chosen, or a custom level up to one’s own', (
    tester,
  ) async {
    final session = await _open(tester);
    await _menu(tester, _bob, 'role');
    await tester.tap(find.byKey(const Key('role.50')));
    await tester.tap(find.byKey(const Key('role.save')));
    await tester.pumpAndSettle();
    expect(session.moderated, ['setPowerLevel $_room $_bob 50']);
    expect(_inInfo(find.text('Moderator')), findsOneWidget);

    await _menu(tester, _bob, 'role');
    await tester.tap(find.byKey(const Key('role.custom')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('role.number')), '150');
    await tester.pump();
    expect(find.text('Higher than your own level'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byKey(const Key('role.save'))).onPressed,
      isNull,
    );
    await tester.enterText(find.byKey(const Key('role.number')), '75');
    await tester.pump();
    await tester.tap(find.byKey(const Key('role.save')));
    await tester.pumpAndSettle();
    expect(session.moderated.last, 'setPowerLevel $_room $_bob 75');
    expect(_inInfo(find.text('Custom (75)')), findsOneWidget);
  });

  testWidgets('a room creator may give any role', (tester) async {
    final session = await _open(tester, ownLevel: null);
    await _menu(tester, _bob, 'role');
    for (final level in [100, 50, 0]) {
      expect(
        tester
            .widget<RadioListTile<int>>(find.byKey(Key('role.$level')))
            .enabled,
        isTrue,
      );
    }
    await tester.tap(find.byKey(const Key('role.100')));
    await tester.tap(find.byKey(const Key('role.save')));
    await tester.pumpAndSettle();
    expect(session.moderated, ['setPowerLevel $_room $_bob 100']);

    // No custom level is too high for them either.
    await _menu(tester, _bob, 'role');
    await tester.tap(find.byKey(const Key('role.custom')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('role.number')), '150');
    await tester.pump();
    expect(find.text('Higher than your own level'), findsNothing);
  });

  testWidgets('lowering one’s own role asks once more', (tester) async {
    final session = await _open(tester);
    await _menu(tester, _me, 'role');
    await tester.tap(find.byKey(const Key('role.0')));
    await tester.tap(find.byKey(const Key('role.save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('role.selfWarning')), findsOneWidget);
    expect(session.moderated, isEmpty);
    await tester.tap(find.text('Lower my role'));
    await tester.pumpAndSettle();
    expect(session.moderated, ['setPowerLevel $_room $_me 0']);
  });

  testWidgets('members are removed with a reason, banned and unbanned', (
    tester,
  ) async {
    final session = await _open(tester);
    await _menu(tester, _bob, 'ban');
    await tester.enterText(find.byKey(const Key('member.reason')), 'spam');
    await tester.tap(find.byKey(const Key('member.confirm')));
    await tester.pumpAndSettle();
    expect(session.moderated, ['ban $_room $_bob:spam']);
    expect(find.text('Banned Bob'), findsOneWidget);
    expect(_inInfo(find.text('Banned')), findsNWidgets(2));

    await _menu(tester, _dan, 'unban');
    expect(session.moderated.last, 'unban $_room $_dan');
    expect(_inInfo(find.text('Dan')), findsNothing);

    // Cancelling removes no one.
    session.members[_room] = [
      ...session.members[_room]!,
      const RoomMember(userId: _dan, displayName: 'Dan', canRemove: true),
    ];
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat.title')));
    await tester.pumpAndSettle();
    await _menu(tester, _dan, 'remove');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(session.moderated.length, 2);
    await _menu(tester, _dan, 'remove');
    await tester.tap(find.byKey(const Key('member.confirm')));
    await tester.pumpAndSettle();
    expect(session.moderated.last, 'remove $_room $_dan');
  });

  testWidgets('Message opens the direct chat with them', (tester) async {
    final session = await _open(tester);
    session.roomList = [
      ...session.roomList,
      const Room(id: '!carol:acme.com', name: 'Carol', isDm: true),
    ];
    session.dms[_carol] = '!carol:acme.com';
    await _menu(tester, _carol, 'message');
    expect(find.byType(ChatInfoPane), findsNothing);
    expect(find.byKey(const Key('composer.text')), findsOneWidget);
  });
}
