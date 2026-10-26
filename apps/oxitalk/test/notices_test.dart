import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oxitalk/src/features/chat/notice_line.dart';
import 'package:oxitalk/src/matrix/api/matrix.dart';
import 'package:oxitalk/src/matrix/fakes/fakes.dart';
import 'package:oxitalk/src/app/ui_prefs.dart';

import 'support/app.dart';

const _wide = Size(1400, 900);
const _me = '@me:acme.com';
const _bob = '@bob:acme.com';
const _room = '!team:acme.com';

var _clock = 0;

NoticeEntry _notice(
  RoomNotice notice, {
  String sender = _bob,
  String? senderName = 'Bob',
  bool isOwn = false,
  String? id,
}) {
  _clock++;
  return NoticeEntry(
    id: id ?? 'n$_clock',
    sender: sender,
    senderName: senderName,
    isOwn: isOwn,
    eventId: '\$n$_clock',
    time: DateTime(2026, 10, 20, 12).add(Duration(minutes: _clock)),
    notice: notice,
  );
}

MessageEntry _message(String id, String body) => MessageEntry(
  id: id,
  sender: _bob,
  senderName: 'Bob',
  time: DateTime(2026, 10, 20, 13),
  body: body,
  meta: EventMeta(eventId: '\$$id'),
);

MembershipNotice _member(
  String user,
  MembershipChange change, {
  String? name,
  String? reason,
  bool own = false,
}) => MembershipNotice(
  userId: user,
  userName: name,
  change: change,
  reason: reason,
  userIsOwn: own,
);

String _text(NoticeEntry entry) => noticeText(entry, ownUserId: _me);

Future<FakeSession> _open(
  WidgetTester tester,
  List<TimelineEntry> entries, {
  MemoryUiPrefs? ui,
}) async {
  final session = FakeSession(
    userId: _me,
    rooms: const [Room(id: _room, name: 'Team')],
  );
  session.timelines[_room] = FakeTimeline(ownUserId: _me, entries: entries);
  await pumpApp(
    tester,
    FakeMatrixClientFactory(saved: [session]),
    size: _wide,
    ui: ui,
  );
  await tester.tap(find.text('Team'));
  await tester.pumpAndSettle();
  return session;
}

void main() {
  group('notice text', () {
    test('membership changes name who did what, and you', () {
      expect(
        _text(_notice(_member(_bob, MembershipChange.joined, name: 'Bob'))),
        'Bob joined',
      );
      expect(
        _text(
          _notice(
            _member(_me, MembershipChange.joined, own: true),
            sender: _me,
            isOwn: true,
          ),
        ),
        'You joined',
      );
      expect(
        _text(
          _notice(
            _member('@carol:acme.com', MembershipChange.invited, name: 'Carol'),
          ),
        ),
        'Bob invited Carol',
      );
      expect(
        _text(_notice(_member(_me, MembershipChange.invited, own: true))),
        'Bob invited you',
      );
      expect(
        _text(
          _notice(
            _member(
              '@carol:acme.com',
              MembershipChange.kicked,
              name: 'Carol',
              reason: 'spam',
            ),
            sender: _me,
            isOwn: true,
          ),
        ),
        'You removed Carol: spam',
      );
      expect(
        _text(_notice(_member('@carol:acme.com', MembershipChange.banned))),
        'Bob banned carol',
      );
      expect(
        _text(_notice(_member(_bob, MembershipChange.inviteDeclined))),
        'Bob declined the invite',
      );
      expect(
        _text(_notice(_member(_bob, MembershipChange.knocked, name: 'Bob'))),
        'Bob asked to join',
      );
    });

    test('profile and room changes', () {
      expect(
        _text(
          _notice(
            const ProfileNotice(
              userId: _bob,
              oldName: 'Bob',
              newName: 'Bobby',
              nameChanged: true,
            ),
            senderName: 'Bobby',
          ),
        ),
        'Bob changed their name to Bobby',
      );
      expect(
        _text(
          _notice(
            const ProfileNotice(userId: _me, avatarChanged: true),
            sender: _me,
            isOwn: true,
          ),
        ),
        'You changed your profile picture',
      );
      expect(_text(_notice(const RoomCreatedNotice())), 'Bob created the room');
      expect(
        _text(_notice(const RoomNameNotice('Plans'))),
        'Bob changed the room name to Plans',
      );
      expect(
        _text(_notice(const RoomTopicNotice(null))),
        'Bob removed the topic',
      );
      expect(
        _text(_notice(const EncryptionNotice())),
        'Bob turned on end-to-end encryption',
      );
      expect(
        _text(_notice(const JoinRuleNotice(JoinRuleKind.invite))),
        'Bob made the room invite only',
      );
      expect(
        _text(
          _notice(const HistoryVisibilityNotice(HistoryVisibilityKind.shared)),
        ),
        'Bob made the history visible to all members',
      );
      expect(
        _text(
          _notice(
            const PowerLevelsNotice([
              PowerLevelChange('@carol:acme.com', 0, 50),
            ]),
          ),
        ),
        'Bob made carol a moderator',
      );
      expect(
        _text(_notice(const PowerLevelsNotice())),
        'Bob changed the room’s permissions',
      );
      expect(
        _text(_notice(const PinnedNotice(added: true))),
        'Bob pinned a message',
      );
    });

    test('content shown as text only', () {
      expect(
        _text(_notice(const PollNotice('Lunch?'))),
        'Bob started a poll: Lunch?',
      );
      expect(
        _text(_notice(const StickerNotice('A cat waving'))),
        'Bob sent a sticker: A cat waving',
      );
      expect(
        _text(_notice(const LocationNotice('geo:52.2,21.0'))),
        'Bob shared a location',
      );
      expect(_text(_notice(const CallNotice())), 'Bob started a call');
    });

    test('a run is summed up by what happened to how many', () {
      final run = [
        _notice(_member('@a:x', MembershipChange.joined)),
        _notice(_member('@b:x', MembershipChange.joined)),
        _notice(_member('@c:x', MembershipChange.inviteAccepted)),
        _notice(_member('@a:x', MembershipChange.left)),
      ];
      expect(noticeRunSummary(run), '3 people joined, 1 left');
      expect(
        noticeRunSummary([
          _notice(_member('@a:x', MembershipChange.invited)),
          _notice(_member('@b:x', MembershipChange.invited)),
        ]),
        '2 people were invited',
      );
    });

    test('runs are of two or more membership notices in a row', () {
      final entries = <TimelineEntry>[
        _notice(_member('@a:x', MembershipChange.joined)),
        _message('m1', 'hi'),
        _notice(_member('@b:x', MembershipChange.joined)),
        _notice(const ProfileNotice(userId: '@b:x', avatarChanged: true)),
        _notice(const RoomNameNotice('X')),
      ];
      expect(noticeRunStarts(entries), [null, null, 2, 2, null]);
    });
  });

  group('in the chat', () {
    testWidgets('notices are centred lines without bubbles or actions', (
      tester,
    ) async {
      final session = await _open(tester, [
        _notice(const RoomCreatedNotice(), id: 'created'),
        _message('m1', 'Hello'),
        _notice(const RoomTopicNotice('Plans'), id: 'topic'),
      ]);
      expect(find.text('Bob created the room'), findsOneWidget);
      expect(find.text('Bob changed the topic to “Plans”'), findsOneWidget);
      expect(find.text('Hello'), findsOneWidget);

      // No hover toolbar over a notice.
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(
        tester.getCenter(find.text('Bob changed the topic to “Plans”')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('hover.more')), findsNothing);
      // Read up to the notice like up to a message.
      expect(session.timelines[_room]!.readMarks, greaterThan(0));
    }, variant: desktop);

    testWidgets('a run of joins folds into one line that opens', (
      tester,
    ) async {
      await _open(tester, [
        _message('m1', 'Hello'),
        _notice(
          _member('@a:x', MembershipChange.joined, name: 'Ann'),
          id: 'j1',
        ),
        _notice(_member('@b:x', MembershipChange.joined, name: 'Ben')),
        _notice(_member('@c:x', MembershipChange.joined, name: 'Cid')),
        _message('m2', 'Welcome'),
      ]);
      expect(find.text('3 people joined'), findsOneWidget);
      expect(find.text('Ann joined'), findsNothing);

      await tester.tap(find.byKey(const Key('notice.run.j1')));
      await tester.pumpAndSettle();
      expect(find.text('Ann joined'), findsOneWidget);
      expect(find.text('Ben joined'), findsOneWidget);
      expect(find.text('Cid joined'), findsOneWidget);

      await tester.tap(find.byKey(const Key('notice.run.j1')));
      await tester.pumpAndSettle();
      expect(find.text('Ann joined'), findsNothing);
    });

    testWidgets('the Settings › Messages switch is saved', (tester) async {
      final ui = MemoryUiPrefs();
      await _open(tester, const [], ui: ui);
      await tester.tap(find.byKey(const Key('rail.settings')));
      await tester.pumpAndSettle();
      await openSettingsSection(tester, 'messages');
      await tester.tap(find.byKey(const Key('settings.showMembershipEvents')));
      await tester.pumpAndSettle();
      expect(ui.showMembershipEvents, isFalse);
    });

    testWidgets('Settings › Messages hides join and leave lines', (
      tester,
    ) async {
      final ui = MemoryUiPrefs(showMembershipEvents: false);
      await _open(tester, [
        _notice(_member('@a:x', MembershipChange.joined, name: 'Ann')),
        _notice(const RoomNameNotice('Plans')),
        _message('m1', 'Hello'),
      ], ui: ui);
      expect(find.text('Ann joined'), findsNothing);
      expect(find.text('Bob changed the room name to Plans'), findsOneWidget);
      expect(find.text('Hello'), findsOneWidget);
    });
  });
}
