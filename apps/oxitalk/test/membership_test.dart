import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oxitalk/src/matrix/api/matrix.dart';
import 'package:oxitalk/src/matrix/fakes/fakes.dart';

import 'support/app.dart';

const _wide = Size(1400, 900);
const _me = '@me:acme.com';
const _alice = '@alice:acme.com';

const _invite = Room(
  id: '!inv:acme.com',
  name: 'Design',
  membership: Membership.invited,
);
const _team = Room(id: '!team:acme.com', name: 'Team');
const _dm = Room(id: '!dm:acme.com', name: 'Bob', isDm: true);

FakeSession _session({List<Room> rooms = const [_invite, _team, _dm]}) =>
    FakeSession(userId: _me, rooms: rooms)
      ..inviteDetailsById[_invite.id] = const InviteDetails(
        roomId: '!inv:acme.com',
        name: 'Design',
        topic: 'Logos, icons and the brand',
        alias: '#design:acme.com',
        inviterId: _alice,
        inviterName: 'Alice',
      );

Future<void> _rightClick(WidgetTester tester, String room) async {
  await tester.tap(find.text(room).first, buttons: kSecondaryMouseButton);
  await tester.pumpAndSettle();
}

void main() {
  group('invitations', () {
    testWidgets('tapping one shows a preview, without joining', (tester) async {
      final session = _session();
      await pumpApp(
        tester,
        FakeMatrixClientFactory(saved: [session]),
        size: _wide,
      );
      await tester.tap(find.text('Invitation — tap to see it'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('invite.preview')), findsOneWidget);
      expect(find.byKey(const Key('invite.topic')), findsOneWidget);
      expect(find.text('Logos, icons and the brand'), findsOneWidget);
      expect(find.text('#design:acme.com'), findsOneWidget);
      expect(find.text('Room invitation'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('invite.inviter')),
          matching: find.textContaining('Alice'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('invited you to join'), findsOneWidget);
      expect(find.text(_alice), findsOneWidget);
      // No composer: nothing is joined.
      expect(find.byKey(const Key('composer.text')), findsNothing);
      expect(
        session.roomList.firstWhere((r) => r.id == _invite.id).membership,
        Membership.invited,
      );
    });

    testWidgets('a direct chat invitation says so', (tester) async {
      final session =
          FakeSession(
              userId: _me,
              rooms: const [
                Room(
                  id: '!new:acme.com',
                  name: 'Alice',
                  isDm: true,
                  membership: Membership.invited,
                ),
              ],
            )
            ..inviteDetailsById['!new:acme.com'] = const InviteDetails(
              roomId: '!new:acme.com',
              name: 'Alice',
              isDm: true,
              inviterId: _alice,
              inviterName: 'Alice',
            );
      await pumpApp(
        tester,
        FakeMatrixClientFactory(saved: [session]),
        size: _wide,
      );
      await tester.tap(find.text('Invitation — tap to see it'));
      await tester.pumpAndSettle();
      expect(find.text('Chat invitation'), findsOneWidget);
      expect(find.textContaining('wants to chat with you'), findsOneWidget);
    });

    testWidgets('Accept joins and opens the chat', (tester) async {
      final session = _session();
      await pumpApp(
        tester,
        FakeMatrixClientFactory(saved: [session]),
        size: _wide,
      );
      await tester.tap(find.text('Invitation — tap to see it'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('invite.accept')));
      await tester.pumpAndSettle();

      expect(
        session.roomList.firstWhere((r) => r.id == _invite.id).membership,
        Membership.joined,
      );
      expect(find.byKey(const Key('invite.preview')), findsNothing);
      expect(find.byKey(const Key('composer.text')), findsOneWidget);
    });

    testWidgets('Decline asks, then leaves and goes back to the list', (
      tester,
    ) async {
      final session = _session();
      await pumpApp(
        tester,
        FakeMatrixClientFactory(saved: [session]),
        size: _wide,
      );
      await tester.tap(find.text('Invitation — tap to see it'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('invite.decline')));
      await tester.pumpAndSettle();
      expect(find.text('Decline the invitation?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('decline.cancel')));
      await tester.pumpAndSettle();
      expect(session.left, isEmpty);

      await tester.tap(find.byKey(const Key('invite.decline')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('decline.confirm')));
      await tester.pumpAndSettle();
      expect(session.left, [_invite.id]);
      expect(find.byKey(const Key('invite.preview')), findsNothing);
      expect(find.text('Design'), findsNothing);
      expect(find.byKey(const Key('welcome')), findsOneWidget);
    });

    testWidgets('the menu of an invitation accepts or declines it', (
      tester,
    ) async {
      final session = _session();
      await pumpApp(
        tester,
        FakeMatrixClientFactory(saved: [session]),
        size: _wide,
      );
      await _rightClick(tester, 'Design');
      expect(find.text('Move to section…'), findsNothing);
      await tester.tap(find.byKey(const Key('roomMenu.decline')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('decline.confirm')));
      await tester.pumpAndSettle();
      expect(session.left, [_invite.id]);

      session.roomList = [...session.roomList, _invite];
      await tester.pumpAndSettle();
      await _rightClick(tester, 'Design');
      await tester.tap(find.byKey(const Key('roomMenu.accept')));
      await tester.pumpAndSettle();
      expect(
        session.roomList.firstWhere((r) => r.id == _invite.id).membership,
        Membership.joined,
      );
      expect(find.byKey(const Key('composer.text')), findsOneWidget);
    });
  });

  group('leaving', () {
    testWidgets('from the chat list menu: asks, leaves, the room is gone', (
      tester,
    ) async {
      final session = _session();
      await pumpApp(
        tester,
        FakeMatrixClientFactory(saved: [session]),
        size: _wide,
      );
      await _rightClick(tester, 'Team');
      await tester.tap(find.byKey(const Key('roomMenu.leave')));
      await tester.pumpAndSettle();
      expect(find.text('Leave “Team”?'), findsOneWidget);
      expect(find.text('You can join it again later.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('leave.cancel')));
      await tester.pumpAndSettle();
      expect(session.left, isEmpty);
      expect(find.text('Team'), findsOneWidget);

      await _rightClick(tester, 'Team');
      await tester.tap(find.byKey(const Key('roomMenu.leave')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('leave.confirm')));
      await tester.pumpAndSettle();
      expect(session.left, [_team.id]);
      expect(find.text('Team'), findsNothing);
    });

    testWidgets('warns about no way back and the last admin', (tester) async {
      final session = _session()
        ..leaveInfos[_team.id] = const LeaveInfo(
          needsInviteToRejoin: true,
          lastAdmin: true,
        );
      await pumpApp(
        tester,
        FakeMatrixClientFactory(saved: [session]),
        size: _wide,
      );
      await _rightClick(tester, 'Team');
      await tester.tap(find.byKey(const Key('roomMenu.leave')));
      await tester.pumpAndSettle();
      expect(find.textContaining('only admin'), findsOneWidget);
      expect(find.textContaining('without a new invite'), findsOneWidget);
      expect(find.text('You can join it again later.'), findsNothing);
    });

    testWidgets('warns the last one in the room', (tester) async {
      final session = _session()
        ..leaveInfos[_team.id] = const LeaveInfo(
          needsInviteToRejoin: true,
          onlyMember: true,
        );
      await pumpApp(
        tester,
        FakeMatrixClientFactory(saved: [session]),
        size: _wide,
      );
      await _rightClick(tester, 'Team');
      await tester.tap(find.byKey(const Key('roomMenu.leave')));
      await tester.pumpAndSettle();
      expect(find.textContaining('only one here'), findsOneWidget);
      expect(find.byKey(const Key('leave.warning.1')), findsNothing);
    });

    testWidgets('from the chat info: back to the list, the chat gone', (
      tester,
    ) async {
      final session = _session();
      await pumpApp(
        tester,
        FakeMatrixClientFactory(saved: [session]),
        size: _wide,
      );
      await tester.tap(find.text('Bob'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('chat.title')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('info.leave')));
      await tester.pumpAndSettle();
      expect(find.text('Leave this chat?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('leave.confirm')));
      await tester.pumpAndSettle();

      expect(session.left, [_dm.id]);
      expect(find.text('Chat info'), findsNothing);
      expect(find.byKey(const Key('welcome')), findsOneWidget);
    });

    testWidgets('a failure says so and keeps the room', (tester) async {
      final session = _session()
        ..leaveFailure = const MatrixFailure(FailureKind.network);
      await pumpApp(
        tester,
        FakeMatrixClientFactory(saved: [session]),
        size: _wide,
      );
      await _rightClick(tester, 'Team');
      await tester.tap(find.byKey(const Key('roomMenu.leave')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('leave.confirm')));
      await tester.pumpAndSettle();
      expect(find.text('Can’t leave: network'), findsOneWidget);
      expect(find.text('Team'), findsOneWidget);
    });
  });
}
