import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oxitalk/src/app/theme.dart';
import 'package:oxitalk/src/app/ui_prefs.dart';
import 'package:oxitalk/src/features/chat/read_receipts.dart';
import 'package:oxitalk/src/matrix/api/matrix.dart';
import 'package:oxitalk/src/matrix/fakes/fakes.dart';

import 'support/app.dart';

const _wide = Size(1200, 800);
const _me = '@me:acme.com';
const _bob = ReadReceipt(userId: '@bob:acme.com', displayName: 'Bob');

MessageEntry _own(int i, {SendState state = SendState.sent}) => MessageEntry(
  id: 'm$i',
  sender: _me,
  isOwn: true,
  sendState: state,
  time: DateTime(2026, 10, 30, 12, i),
  body: 'mine $i',
  meta: EventMeta(eventId: state == SendState.sent ? '\$m$i' : null),
);

MessageEntry _theirs(int i, {List<ReadReceipt> readBy = const []}) =>
    MessageEntry(
      id: 'm$i',
      sender: '@bob:acme.com',
      senderName: 'Bob',
      time: DateTime(2026, 10, 30, 12, i),
      body: 'theirs $i',
      meta: EventMeta(eventId: '\$m$i', readBy: readBy),
    );

/// Opens the chat [room] with [entries], in [theme].
Future<FakeTimeline> _open(
  WidgetTester tester,
  Room room,
  List<TimelineEntry> entries, {
  String theme = 'dark',
}) async {
  final timeline = FakeTimeline(ownUserId: _me, entries: entries);
  final session = FakeSession(userId: _me, rooms: [room]);
  session.timelines[room.id] = timeline;
  await pumpApp(
    tester,
    FakeMatrixClientFactory(saved: [session]),
    size: _wide,
    ui: MemoryUiPrefs(theme: theme),
  );
  await tester.tap(find.text(room.name).first);
  await tester.pumpAndSettle();
  return timeline;
}

const _direct = Room(id: '!bob', name: 'Bob', isDm: true, joinedMembers: 2);
const _group = Room(id: '!team', name: 'Team', joinedMembers: 14);

Finder _key(String key) => find.byKey(Key(key));

Color? _iconColor(WidgetTester tester, String key) =>
    tester.widget<Icon>(_key(key).first).color;

void main() {
  testWidgets('in a chat of two, the user\'s messages show a clock, one tick, '
      'two once read, and the failed mark', (tester) async {
    final timeline = await _open(tester, _direct, [
      _own(0),
      _own(1),
      _own(2),
      _own(3, state: SendState.sending),
      _own(4, state: SendState.failed),
    ]);
    // Nothing read yet: one tick each; no "delivered" second tick.
    expect(_key('message.sent'), findsNWidgets(3));
    expect(_key('message.read'), findsNothing);
    expect(_key('message.sending'), findsOneWidget);
    expect(_key('message.failed'), findsOneWidget);

    // Bob reads up to the second: it and everything before it are read.
    timeline.markReadBy(r'$m1', _bob);
    await tester.pumpAndSettle();
    expect(_key('message.read'), findsNWidgets(2));
    expect(_key('message.sent'), findsOneWidget);
    expect(_iconColor(tester, 'message.read'), OxiBrand.yellow);
    // Ticks, not pictures, with one other member.
    expect(_key('message.readers'), findsNothing);

    // He reads on.
    timeline.markReadBy(r'$m2', _bob);
    await tester.pumpAndSettle();
    expect(_key('message.read'), findsNWidgets(3));
    expect(_key('message.sent'), findsNothing);
    expect(_key('message.sending'), findsOneWidget);
    expect(_key('message.failed'), findsOneWidget);
  });

  testWidgets('his answer marks everything before it read', (tester) async {
    await _open(tester, _direct, [
      _own(0),
      _own(1),
      _theirs(2, readBy: const [_bob]),
      _own(3),
    ]);
    expect(_key('message.read'), findsNWidgets(2));
    expect(_key('message.sent'), findsOneWidget);
  });

  testWidgets('the read ticks are a darker amber on the light theme', (
    tester,
  ) async {
    await _open(tester, _direct, [
      _own(0),
      _theirs(1, readBy: const [_bob]),
    ], theme: 'light');
    expect(_iconColor(tester, 'message.read'), OxiPalette.readTickOnLight);
  });

  testWidgets('in a group, at most ten readers show under a message, then +N; '
      'a tap lists them all', (tester) async {
    final readers = [
      for (var i = 0; i < 12; i++)
        ReadReceipt(
          userId: '@user$i:acme.com',
          displayName: 'User $i',
          time: DateTime(2026, 10, 30, 13, 59 - i),
        ),
    ];
    await _open(tester, _group, [_own(0), _theirs(1, readBy: readers)]);
    expect(_key('message.readers'), findsOneWidget);
    for (var i = 0; i < 10; i++) {
      expect(_key('message.reader.@user$i:acme.com'), findsOneWidget);
    }
    expect(_key('message.reader.@user10:acme.com'), findsNothing);
    expect(find.text('+2'), findsOneWidget);
    // Own messages keep one tick in a group: no "read" double tick.
    expect(_key('message.read'), findsNothing);
    expect(_key('message.sent'), findsOneWidget);

    await tester.tap(_key('message.readers'));
    await tester.pumpAndSettle();
    expect(_key('readers.list'), findsOneWidget);
    expect(find.text('Read by 12'), findsOneWidget);
    expect(_key('readers.@user0:acme.com'), findsOneWidget);
    // All twelve, the list scrolling.
    await tester.scrollUntilVisible(
      _key('readers.@user11:acme.com'),
      100,
      scrollable: find.descendant(
        of: _key('readers.list'),
        matching: find.byType(Scrollable),
      ),
    );
    expect(_key('readers.@user11:acme.com'), findsOneWidget);
    await tester.scrollUntilVisible(
      _key('readers.@user0:acme.com'),
      -100,
      scrollable: find.descendant(
        of: _key('readers.list'),
        matching: find.byType(Scrollable),
      ),
    );
    expect(
      find.descendant(
        of: _key('readers.@user0:acme.com'),
        matching: find.text('13:59'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(_key('readers.list'), findsNothing);
  });

  testWidgets('ten readers show without +N; a receipt moves with the reader', (
    tester,
  ) async {
    final readers = [
      for (var i = 0; i < 10; i++)
        ReadReceipt(userId: '@user$i:acme.com', displayName: 'User $i'),
    ];
    final timeline = await _open(tester, _group, [
      _theirs(0, readBy: readers),
      _theirs(1),
    ]);
    expect(find.textContaining('+'), findsNothing);
    expect(_key('readers.m0'), findsOneWidget);
    expect(_key('readers.m1'), findsNothing);

    timeline.markReadBy(r'$m1', readers.first);
    await tester.pumpAndSettle();
    expect(_key('readers.m1'), findsOneWidget);
    expect(_key('message.reader.@user0:acme.com'), findsOneWidget);
  });

  test('read times: the time today, else the day too', () {
    final now = DateTime(2026, 10, 30, 18);
    expect(readTime(DateTime(2026, 10, 30, 9, 5), now: now), '09:05');
    expect(readTime(DateTime(2026, 10, 1, 9, 5), now: now), '01.10.26 09:05');
  });
}
