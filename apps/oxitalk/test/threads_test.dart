import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oxitalk/src/matrix/api/matrix.dart';
import 'package:oxitalk/src/matrix/fakes/fakes.dart';

import 'support/app.dart';

const _wide = Size(1400, 900);
const _narrow = Size(400, 800);
const _me = '@me:acme.com';
const _bob = '@bob:acme.com';
const _room = '!team:acme.com';
const _root = r'$lunch';

MessageEntry _message(
  String id,
  String body, {
  String sender = _bob,
  int minute = 0,
  ThreadSummary? thread,
}) => MessageEntry(
  id: id,
  sender: sender,
  senderName: sender == _bob ? 'Bob' : 'Me',
  time: DateTime(2026, 10, 20, 12, minute),
  body: body,
  isOwn: sender == _me,
  meta: EventMeta(eventId: '\$$id', thread: thread),
);

final _pizza = ThreadEvent(
  sender: _me,
  senderName: 'Me',
  text: 'pizza',
  time: DateTime(2026, 10, 20, 12, 5),
);

/// The chat, with Bob's "lunch?" starting a thread of two replies, opened; the thread's own
/// timeline holds the first message and the replies.
Future<(FakeSession, FakeTimeline)> _open(
  WidgetTester tester, {
  Size size = _wide,
}) async {
  final timeline = FakeTimeline(
    ownUserId: _me,
    entries: [
      _message(
        'lunch',
        'lunch?',
        thread: ThreadSummary(replyCount: 2, latest: _pizza),
      ),
      _message('other', 'Something else', minute: 1),
    ],
  );
  final session = FakeSession(
    userId: _me,
    rooms: const [Room(id: _room, name: 'Team')],
  );
  session.timelines[_room] = timeline;
  session.threadTimelines[_root] = FakeTimeline(
    ownUserId: _me,
    entries: [
      _message('lunch', 'lunch?'),
      _message('bobreply', 'sushi', minute: 2),
      _message('pizzareply', 'pizza', sender: _me, minute: 5),
    ],
  );
  await pumpApp(tester, FakeMatrixClientFactory(saved: [session]), size: size);
  await tester.tap(find.text('Team'));
  await tester.pumpAndSettle();
  return (session, timeline);
}

/// A mouse for hovering over messages; one per test.
Future<TestGesture> _mouse(WidgetTester tester) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  return mouse;
}

/// Moves [mouse] over the message with [text], showing its toolbar.
Future<void> _hover(WidgetTester tester, TestGesture mouse, String text) async {
  await mouse.moveTo(tester.getCenter(find.text(text).last));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a thread shows under its first message and opens beside the '
      'chat; what is written there goes into the thread', (tester) async {
    final (session, timeline) = await _open(tester);
    final bar = find.byKey(const Key('thread.bar.$_root'));
    expect(bar, findsOneWidget);
    expect(
      find.descendant(of: bar, matching: find.textContaining('2 replies')),
      findsOneWidget,
    );
    // The replies stay out of the chat.
    expect(find.text('sushi'), findsNothing);

    await tester.tap(bar);
    await tester.pumpAndSettle();
    final pane = find.byKey(const Key('thread.close'));
    expect(pane, findsOneWidget);
    // The chat stays beside it.
    expect(find.text('Something else'), findsOneWidget);
    expect(find.text('sushi'), findsOneWidget);
    expect(find.text('Reply in thread'), findsOneWidget);
    // In the thread itself its first message has no bar.
    expect(find.byKey(const Key('thread.bar.$_root')), findsOneWidget);

    final composers = find.byKey(const Key('composer.text'));
    expect(composers, findsNWidgets(2));
    await tester.enterText(composers.last, 'see you at 1');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    // The microphone gives way to Send once there is text.
    await tester.pump();
    await tester.tap(find.byKey(const Key('composer.send')).last);
    await tester.pumpAndSettle();
    final thread = session.threadTimelines[_root]!;
    expect(
      thread.entryList.whereType<MessageEntry>().last.body,
      'see you at 1',
    );
    expect(
      timeline.entryList.whereType<MessageEntry>().map((m) => m.body),
      isNot(contains('see you at 1')),
    );

    // Esc closes the thread; the chat stays open.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('thread.close')), findsNothing);
    expect(find.text('Something else'), findsOneWidget);
  });

  testWidgets('Reply in thread from the toolbar starts a thread on any '
      'message; inside a thread there is no such button', (tester) async {
    final (session, _) = await _open(tester);
    final mouse = await _mouse(tester);
    await _hover(tester, mouse, 'Something else');
    await tester.tap(find.byKey(const Key('hover.thread')).hitTestable().first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('thread.close')), findsOneWidget);
    expect(session.threadTimelines.keys, contains(r'$other'));

    await tester.tap(find.byKey(const Key('thread.bar.$_root')));
    await tester.pumpAndSettle();
    // "sushi" is only in the thread.
    await _hover(tester, mouse, 'sushi');
    expect(find.byKey(const Key('hover.reply')).hitTestable(), findsOneWidget);
    expect(find.byKey(const Key('hover.thread')).hitTestable(), findsNothing);
  });

  testWidgets('the thread list shows the room’s threads and opens one', (
    tester,
  ) async {
    final (session, _) = await _open(tester);
    session.threadLists[_room] = FakeThreadList([
      RoomThread(
        rootEventId: _root,
        root: ThreadEvent(
          sender: _bob,
          senderName: 'Bob',
          text: 'lunch?',
          time: DateTime(2026, 10, 20, 12),
        ),
        latest: _pizza,
        replyCount: 2,
      ),
    ]);
    await tester.tap(find.byKey(const Key('chat.threads')));
    await tester.pumpAndSettle();
    expect(session.threadLists[_room]!.loads, greaterThan(0));
    final tile = find.byKey(const Key('threads.thread.$_root'));
    expect(tile, findsOneWidget);
    expect(
      find.descendant(of: tile, matching: find.text('2 replies · Me: pizza')),
      findsOneWidget,
    );

    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('threads.close')), findsNothing);
    expect(find.text('sushi'), findsOneWidget);
  });

  testWidgets('an empty thread list says so', (tester) async {
    await _open(tester);
    await tester.tap(find.byKey(const Key('chat.threads')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('threads.empty')), findsOneWidget);
  });

  testWidgets('on a phone a thread is a page of its own; Back returns to the '
      'chat', (tester) async {
    await _open(tester, size: _narrow);
    await tester.tap(find.byKey(const Key('thread.bar.$_root')));
    await tester.pumpAndSettle();
    expect(find.text('sushi'), findsOneWidget);
    expect(find.text('Something else'), findsNothing);

    await tester.tap(find.byKey(const Key('thread.close')));
    await tester.pumpAndSettle();
    expect(find.text('Something else'), findsOneWidget);
    expect(find.text('sushi'), findsNothing);
  });
}
