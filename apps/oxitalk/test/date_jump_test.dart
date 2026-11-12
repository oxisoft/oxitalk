// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oxitalk/src/features/chat/date_jump.dart';
import 'package:oxitalk/src/matrix/api/matrix.dart';
import 'package:oxitalk/src/matrix/fakes/fakes.dart';
import 'package:oxitalk/src/ui/format.dart';

import 'support/app.dart';

const _wide = Size(1400, 900);
const _me = '@me:acme.com';
const _bob = '@bob:acme.com';
const _room = '!team:acme.com';

/// The messages' month: last month, so every day of it is before today.
final _month = () {
  final now = DateTime.now();
  return DateTime(now.year, now.month - 1);
}();

DateTime _day(int day, [int hour = 0, int minute = 0]) =>
    DateTime(_month.year, _month.month, day, hour, minute);

String _label(int day) => dayLabel(_day(day));

MessageEntry _message(int day, int i) => MessageEntry(
  id: 'd${day}m$i',
  sender: _bob,
  senderName: 'Bob',
  time: _day(day, 9, i * 10),
  body: 'day $day message $i',
  meta: EventMeta(eventId: '\$d${day}m$i'),
);

/// 20 messages on each of [days], each day after its divider.
List<TimelineEntry> _days(List<int> days) => [
  for (final day in days) ...[
    DayDivider(id: 'day$day', day: _day(day)),
    for (var i = 0; i < 20; i++) _message(day, i),
  ],
];

/// The chat with messages on the 10th, 11th, 12th and 15th of last month, opened at its
/// newest.
Future<(FakeSession, FakeTimeline)> _open(
  WidgetTester tester, {
  List<TimelineEntry>? entries,
}) async {
  final session = FakeSession(
    userId: _me,
    rooms: const [Room(id: _room, name: 'Team')],
  );
  final timeline = FakeTimeline(
    ownUserId: _me,
    entries: entries ?? _days([10, 11, 12, 15]),
  );
  session.timelines[_room] = timeline;
  await pumpApp(tester, FakeMatrixClientFactory(saved: [session]), size: _wide);
  await tester.tap(find.text('Team'));
  await tester.pumpAndSettle();
  return (session, timeline);
}

Finder get _row => find.byKey(const Key('chat.dateRow'));

/// The date row's text, if it shows.
String? get _rowText {
  final label = find.byKey(const Key('chat.dateRow.label')).evaluate();
  return label.isEmpty ? null : (label.single.widget as Text).data;
}

Finder get _timeline =>
    find.byWidgetPredicate((widget) => widget is ListView && widget.reverse);

Finder get _highlight => find.byKey(const Key('message.highlight'));

/// Opens the calendar from the date row and taps [day] in it.
Future<void> _pick(WidgetTester tester, int day) async {
  await tester.tap(_row);
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('dateJump.dialog')), findsOneWidget);
  await tester.tap(
    find.descendant(
      of: find.byKey(const Key('dateJump.calendar')),
      matching: find.text('$day'),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _go(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('dateJump.go')));
  await tester.pumpAndSettle();
}

/// Lets the highlight fade, so no timer is left.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 4));
  await tester.pumpAndSettle();
}

void _expectHighlighted(String text) => expect(
  find.descendant(of: _highlight, matching: find.text(text)),
  findsOneWidget,
);

void main() {
  testWidgets('the row under the header shows the top message’s day and '
      'follows the scroll', (tester) async {
    await _open(tester);
    expect(_row, findsOneWidget);
    expect(_rowText, _label(15));

    // Up to the first messages.
    await tester.drag(_timeline, const Offset(0, 20000));
    await tester.pumpAndSettle();
    expect(_rowText, _label(10));

    // And back down to the newest.
    await tester.drag(_timeline, const Offset(0, -20000));
    await tester.pumpAndSettle();
    expect(_rowText, _label(15));
  });

  testWidgets('an empty chat has no date row', (tester) async {
    await _open(tester, entries: const []);
    expect(_row, findsNothing);
  });

  testWidgets('picking a day only selects it; Scroll to date goes to its first '
      'message, at the top, highlighted', (tester) async {
    final (session, _) = await _open(tester);
    await _pick(tester, 11);
    // Still the calendar, nothing moved.
    expect(find.byKey(const Key('dateJump.dialog')), findsOneWidget);
    expect(_highlight, findsNothing);
    expect(_rowText, _label(15));

    await _go(tester);
    expect(find.byKey(const Key('dateJump.dialog')), findsNothing);
    _expectHighlighted('day 11 message 0');
    expect(_rowText, _label(11));
    final top = tester.getTopLeft(_timeline).dy;
    expect(
      tester.getTopLeft(find.text('day 11 message 0')).dy - top,
      lessThan(120),
    );
    // The loaded messages told; nothing asked of the server.
    expect(session.messageSinceAsked, isEmpty);
    await _settle(tester);
    expect(_highlight, findsNothing);
  });

  testWidgets('Cancel leaves the chat where it was', (tester) async {
    await _open(tester);
    await _pick(tester, 11);
    await tester.tap(find.byKey(const Key('dateJump.cancel')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dateJump.dialog')), findsNothing);
    expect(_highlight, findsNothing);
    expect(_rowText, _label(15));
  });

  testWidgets('a day without messages goes to the next day with some and says '
      'so', (tester) async {
    await _open(tester);
    await _pick(tester, 13);
    await _go(tester);
    expect(
      find.text('No messages on ${_label(13)}; showing ${_label(15)}'),
      findsOneWidget,
    );
    _expectHighlighted('day 15 message 0');
    await _settle(tester);
  });

  testWidgets('a day after the last message goes to the newest', (
    tester,
  ) async {
    await _open(tester);
    await tester.drag(_timeline, const Offset(0, 20000));
    await tester.pumpAndSettle();
    expect(_rowText, _label(10));
    await _pick(tester, 16);
    await _go(tester);
    expect(find.text('No messages since ${_label(16)}'), findsOneWidget);
    expect(find.text('day 15 message 19'), findsOneWidget);
    expect(_rowText, _label(15));
  });

  testWidgets('a day before the loaded messages is asked of the server, and '
      'the room opens around its first message', (tester) async {
    final (session, _) = await _open(tester);
    session.messageSince = (_) => MessageFound('\$old', _day(4, 10));
    session.timelinesAt['\$old'] = FakeTimeline(
      ownUserId: _me,
      entries: [
        DayDivider(id: 'day4', day: _day(4)),
        MessageEntry(
          id: 'old',
          sender: _bob,
          senderName: 'Bob',
          time: _day(4, 10),
          body: 'the old message',
          meta: const EventMeta(eventId: '\$old'),
        ),
      ],
    );
    await _pick(tester, 3);
    await _go(tester);
    expect(session.messageSinceAsked, [_day(3)]);
    expect(
      find.text('No messages on ${_label(3)}; showing ${_label(4)}'),
      findsOneWidget,
    );
    _expectHighlighted('the old message');
    expect(_rowText, _label(4));
    expect(find.byKey(const Key('chat.toLatest')), findsOneWidget);
    await _settle(tester);
  });

  testWidgets('without the server’s help, older messages are loaded until '
      'they reach the day', (tester) async {
    final (session, timeline) = await _open(tester);
    // The fake session answers MessageSinceUnsupported by default.
    await _pick(tester, 3);
    await _go(tester);
    expect(session.messageSinceAsked, [_day(3)]);
    expect(timeline.olderLoads, greaterThan(0));
    // The fake's start is reached at once: the room's first message is the 10th's.
    expect(
      find.text('No messages on ${_label(3)}; showing ${_label(10)}'),
      findsOneWidget,
    );
    _expectHighlighted('day 10 message 0');
    await _settle(tester);
  });

  group('loadedDayStart', () {
    final entries = _days([10, 12]);

    test('finds the day’s first message when the messages reach back', () {
      expect(
        loadedDayStart(
          entries,
          _day(12),
          reachedStart: false,
          reachedEnd: true,
        ),
        isA<LoadedFound>().having((f) => f.eventId, 'eventId', '\$d12m0'),
      );
      expect(
        loadedDayStart(
          entries,
          _day(11),
          reachedStart: false,
          reachedEnd: true,
        ),
        isA<LoadedFound>().having((f) => f.eventId, 'eventId', '\$d12m0'),
      );
    });

    test('doesn’t tell when the messages start after the day began', () {
      expect(
        loadedDayStart(
          entries,
          _day(10),
          reachedStart: false,
          reachedEnd: true,
        ),
        isA<NotLoaded>(),
      );
      expect(
        loadedDayStart(entries, _day(10), reachedStart: true, reachedEnd: true),
        isA<LoadedFound>().having((f) => f.eventId, 'eventId', '\$d10m0'),
      );
    });

    test('none after only when the newest message is loaded', () {
      expect(
        loadedDayStart(
          entries,
          _day(13),
          reachedStart: false,
          reachedEnd: true,
        ),
        isA<LoadedNoneAfter>(),
      );
      expect(
        loadedDayStart(
          entries,
          _day(13),
          reachedStart: false,
          reachedEnd: false,
        ),
        isA<NotLoaded>(),
      );
    });
  });
}
