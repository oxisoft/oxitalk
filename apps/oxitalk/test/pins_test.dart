import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oxitalk/src/matrix/api/matrix.dart';
import 'package:oxitalk/src/matrix/fakes/fakes.dart';

import 'support/app.dart';

const _wide = Size(1400, 900);
const _me = '@me:acme.com';
const _bob = '@bob:acme.com';
const _room = '!team:acme.com';

MessageEntry _message(int i, {String? body}) => MessageEntry(
  id: 'm$i',
  sender: _bob,
  senderName: 'Bob',
  time: DateTime(2026, 10, 20, 12).add(Duration(minutes: i)),
  body: body ?? 'message $i',
  meta: EventMeta(eventId: '\$m$i'),
);

/// The chat with 60 messages, opened; [pins] are its pins, and the pinned timeline holds
/// [pinned].
Future<(FakeSession, FakePinnedEvents)> _open(
  WidgetTester tester, {
  RoomPins pins = const RoomPins(canPin: true),
  List<TimelineEntry> pinned = const [],
}) async {
  final session = FakeSession(
    userId: _me,
    rooms: const [Room(id: _room, name: 'Team')],
  );
  session.timelines[_room] = FakeTimeline(
    ownUserId: _me,
    entries: [for (var i = 0; i < 60; i++) _message(i)],
  );
  final fakePins = FakePinnedEvents(pins);
  session.pins[_room] = fakePins;
  session.pinnedTimelines[_room] = FakeTimeline(
    ownUserId: _me,
    entries: pinned,
  );
  await pumpApp(tester, FakeMatrixClientFactory(saved: [session]), size: _wide);
  await tester.tap(find.text('Team'));
  await tester.pumpAndSettle();
  return (session, fakePins);
}

/// A mouse for hovering over messages; one per test.
Future<TestGesture> _mouse(WidgetTester tester) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  return mouse;
}

/// Opens the message menu of the message with [text] through its hover toolbar.
Future<void> _openMenu(
  WidgetTester tester,
  TestGesture mouse,
  String text,
) async {
  await mouse.moveTo(tester.getCenter(_inTimeline(text)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('hover.more')).hitTestable().first);
  await tester.pumpAndSettle();
}

/// [text] in the timeline (not in the banner).
Finder _inTimeline(String text) => find.descendant(
  of: find.byWidgetPredicate((widget) => widget is ListView && widget.reverse),
  matching: find.text(text),
);

Finder get _banner => find.byKey(const Key('pins.banner'));

Finder _bannerText(String text) =>
    find.descendant(of: _banner, matching: find.text(text));

Finder get _highlighted => find.byKey(const Key('message.highlight'));

void main() {
  testWidgets('the menu pins and unpins a message when the user may; the '
      'banner shows the last pin', (tester) async {
    final (session, pins) = await _open(tester, pinned: [_message(59)]);
    expect(_banner, findsNothing);

    final mouse = await _mouse(tester);
    await _openMenu(tester, mouse, 'message 59');
    expect(find.text('Unpin'), findsNothing);
    await tester.tap(find.text('Pin'));
    await tester.pumpAndSettle();
    expect(pins.state.eventIds, [r'$m59']);
    expect(_banner, findsOneWidget);
    expect(_bannerText('Pinned message'), findsOneWidget);
    expect(_bannerText('message 59'), findsOneWidget);

    await _openMenu(tester, mouse, 'message 59');
    expect(find.text('Pin'), findsNothing);
    await tester.tap(find.text('Unpin'));
    await tester.pumpAndSettle();
    expect(pins.state.eventIds, isEmpty);
    expect(_banner, findsNothing);
    // Without pins, the timeline of pinned messages is closed.
    expect(session.pinnedTimelines[_room]!.closed, isTrue);
  }, variant: desktop);

  testWidgets('without the power level the menu has no Pin and the list no '
      'Unpin', (tester) async {
    await _open(
      tester,
      pins: const RoomPins(eventIds: [r'$m3']),
      pinned: [_message(3)],
    );
    expect(_bannerText('message 3'), findsOneWidget);
    await _openMenu(tester, await _mouse(tester), 'message 59');
    expect(find.text('Pin'), findsNothing);
    expect(find.text('Unpin'), findsNothing);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('pins.viewAll')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key(r'pins.item.$m3')), findsOneWidget);
    expect(find.byKey(const Key(r'pins.unpin.$m3')), findsNothing);
  }, variant: desktop);

  testWidgets('a tap on the banner scrolls to the pin, highlights it a moment '
      'and moves the banner to the pin before', (tester) async {
    await _open(
      tester,
      pins: const RoomPins(eventIds: [r'$m50', r'$m2'], canPin: true),
      pinned: [_message(2), _message(50)],
    );
    // The last pinned first.
    expect(_bannerText('Pinned message 1 of 2'), findsOneWidget);
    expect(_bannerText('message 2'), findsOneWidget);
    // The chat opens at its newest message; the old one isn't built.
    expect(_inTimeline('message 2'), findsNothing);

    await tester.tap(_banner);
    await tester.pumpAndSettle();
    expect(_inTimeline('message 2'), findsOneWidget);
    expect(
      find.descendant(of: _highlighted, matching: find.text('message 2')),
      findsOneWidget,
    );
    expect(_bannerText('Pinned message 2 of 2'), findsOneWidget);
    expect(_bannerText('message 50'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(_highlighted, findsNothing);

    await tester.tap(_banner);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: _highlighted, matching: find.text('message 50')),
      findsOneWidget,
    );
    expect(_bannerText('message 2'), findsOneWidget);
  });

  testWidgets('a pin that isn\'t loaded opens the chat around it, and Jump to '
      'latest goes back', (tester) async {
    final old = _message(-500, body: 'from long ago');
    final (session, _) = await _open(
      tester,
      pins: const RoomPins(eventIds: [r'$m-500'], canPin: true),
      pinned: [old],
    );
    session.timelinesAt[r'$m-500'] = FakeTimeline(
      ownUserId: _me,
      entries: [_message(-501), old, _message(-499)],
    );
    await tester.tap(_banner);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: _highlighted, matching: find.text('from long ago')),
      findsOneWidget,
    );
    expect(_inTimeline('message 59'), findsNothing);
    final toLatest = find.byKey(const Key('chat.toLatest'));
    expect(toLatest, findsOneWidget);

    await tester.tap(toLatest);
    await tester.pumpAndSettle();
    expect(toLatest, findsNothing);
    expect(_inTimeline('message 59'), findsOneWidget);
    expect(_inTimeline('from long ago'), findsNothing);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('the list shows every pin, unpins, and a tap jumps to the '
      'message; the chat info counts the pins', (tester) async {
    final (_, pins) = await _open(
      tester,
      pins: const RoomPins(eventIds: [r'$m1', r'$m40'], canPin: true),
      pinned: [_message(1), _message(40)],
    );
    await tester.tap(find.byKey(const Key('chat.title')));
    await tester.pumpAndSettle();
    final row = find.byKey(const Key('info.pins'));
    expect(find.descendant(of: row, matching: find.text('2')), findsOneWidget);
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.text('Pinned messages (2)'), findsOneWidget);
    // The last pinned first.
    final items = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('pins.item.'),
    );
    expect(
      tester.widgetList(items).map((w) => (w.key! as ValueKey<String>).value),
      [r'pins.item.$m40', r'pins.item.$m1'],
    );

    await tester.tap(find.byKey(const Key(r'pins.unpin.$m40')));
    await tester.pumpAndSettle();
    expect(pins.state.eventIds, [r'$m1']);
    expect(find.text('Pinned messages (1)'), findsOneWidget);

    await tester.tap(find.byKey(const Key(r'pins.item.$m1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pins.list')), findsNothing);
    expect(find.byKey(const Key('info.pins')), findsNothing);
    expect(
      find.descendant(of: _highlighted, matching: find.text('message 1')),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 4));
  });
}
