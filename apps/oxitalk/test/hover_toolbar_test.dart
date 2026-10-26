import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oxitalk/src/features/chat/chat_pane.dart';
import 'package:oxitalk/src/matrix/api/matrix.dart';
import 'package:oxitalk/src/matrix/fakes/fakes.dart';

import 'support/app.dart';

const _me = '@me:acme.com';
const _bob = '@bob:acme.com';
const _room = '!team:acme.com';

MessageEntry _message(String id, String body, {String sender = _bob}) =>
    MessageEntry(
      id: id,
      sender: sender,
      senderName: sender == _bob ? 'Bob' : 'Me',
      time: DateTime(2026, 10, 20, 9),
      body: body,
      isOwn: sender == _me,
      meta: EventMeta(eventId: '\$$id', isEditable: sender == _me),
    );

const _buttons = ['hover.react', 'hover.reply', 'hover.thread', 'hover.more'];

Future<void> _open(
  WidgetTester tester, {
  required List<TimelineEntry> entries,
  Size size = const Size(1400, 900),
}) async {
  final session = FakeSession(
    userId: _me,
    rooms: const [Room(id: _room, name: 'Team')],
  );
  session.timelines[_room] = FakeTimeline(ownUserId: _me, entries: entries);
  await pumpApp(tester, FakeMatrixClientFactory(saved: [session]), size: size);
  await tester.tap(find.text('Team'));
  await tester.pumpAndSettle();
}

Future<TestGesture> _mouse(WidgetTester tester) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  return mouse;
}

Rect _rect(WidgetTester tester, String key) =>
    tester.getRect(find.byKey(Key(key)).hitTestable());

/// The toolbar's outline: from its first button to its last.
Rect _toolbar(WidgetTester tester) =>
    _rect(tester, 'hover.react').expandToInclude(_rect(tester, 'hover.more'));

/// The bubble's painted box around [text].
Rect _bubble(WidgetTester tester, String text) => tester.getRect(
  find
      .ancestor(
        of: find.text(text),
        matching: find.descendant(
          of: find.byType(MessageBubble),
          matching: find.byType(DecoratedBox),
        ),
      )
      .first,
);

void main() {
  testWidgets('the toolbar is one narrow column, beside the message, its '
      'bottom at the message’s bottom; the message doesn’t grow', (
    tester,
  ) async {
    await _open(
      tester,
      entries: [
        _message('hi', 'Hi'),
        _message('mine', 'Mine', sender: _me),
      ],
    );
    final before = _bubble(tester, 'Hi');
    for (final key in _buttons) {
      expect(find.byKey(Key(key)).hitTestable(), findsNothing);
    }
    final mouse = await _mouse(tester);
    await mouse.moveTo(tester.getCenter(find.text('Hi')));
    await tester.pumpAndSettle();

    final rects = [for (final key in _buttons) _rect(tester, key)];
    for (final (index, rect) in rects.indexed.skip(1)) {
      // Stacked top to bottom, in one column.
      expect(rect.top, greaterThanOrEqualTo(rects[index - 1].bottom - 0.01));
      expect(rect.center.dx, moreOrLessEquals(rects.first.center.dx));
    }
    final toolbar = _toolbar(tester);
    expect(toolbar.width, lessThanOrEqualTo(44));
    expect(toolbar.height, greaterThan(toolbar.width * 3));

    // Bob's message: the toolbar on its right, bottoms level.
    final bubble = _bubble(tester, 'Hi');
    expect(bubble, before, reason: 'the message neither moves nor grows');
    expect(bubble.height, lessThan(toolbar.height));
    expect(toolbar.left, greaterThanOrEqualTo(bubble.right - 0.01));
    expect(toolbar.bottom, moreOrLessEquals(bubble.bottom, epsilon: 6));

    // The user's own: on its left.
    await mouse.moveTo(tester.getCenter(find.text('Mine')));
    await tester.pumpAndSettle();
    final own = _toolbar(tester);
    expect(own.right, lessThanOrEqualTo(_bubble(tester, 'Mine').left + 0.01));
  }, variant: desktop);

  testWidgets('a long message keeps nearly all the width: only one button’s '
      'room is kept beside it', (tester) async {
    final long = List.filled(80, 'word').join(' ');
    await _open(tester, entries: [_message('long', long)]);
    final bubble = tester.getRect(
      find
          .ancestor(
            of: find.textContaining('word word'),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    final chat = tester.getRect(find.byType(TimelineView));
    // The room kept for the toolbar plus the list's padding, about one button.
    expect(chat.right - bubble.right, lessThan(60));
  }, variant: desktop);

  testWidgets('moving onto the toolbar keeps it; its buttons work; leaving '
      'both hides it', (tester) async {
    await _open(tester, entries: [_message('hi', 'Hi')]);
    final mouse = await _mouse(tester);
    await mouse.moveTo(tester.getCenter(find.text('Hi')));
    await tester.pumpAndSettle();
    await mouse.moveTo(_rect(tester, 'hover.reply').center);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('hover.reply')).hitTestable(), findsOneWidget);
    await mouse.down(_rect(tester, 'hover.reply').center);
    await mouse.up();
    await tester.pumpAndSettle();
    expect(find.text('Replying to Bob'), findsOneWidget);

    await mouse.moveTo(const Offset(5, 450));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('hover.reply')).hitTestable(), findsNothing);
  }, variant: desktop);

  testWidgets('tooltips show beside the buttons, not over them', (
    tester,
  ) async {
    await _open(
      tester,
      entries: [
        _message('hi', 'Hi'),
        _message('mine', 'Mine', sender: _me),
      ],
    );
    final mouse = await _mouse(tester);
    for (final (text, left) in [('Hi', false), ('Mine', true)]) {
      await mouse.moveTo(tester.getCenter(find.text(text)));
      await tester.pumpAndSettle();
      final button = _rect(tester, 'hover.reply');
      await mouse.moveTo(button.center);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      final tip = tester.getRect(find.text('Reply'));
      expect(tip.overlaps(_toolbar(tester)), isFalse, reason: text);
      if (left) {
        expect(tip.right, lessThanOrEqualTo(button.left));
      } else {
        expect(tip.left, greaterThanOrEqualTo(button.right));
      }
      expect(tip.center.dy, moreOrLessEquals(button.center.dy, epsilon: 2));
      await mouse.moveTo(const Offset(5, 450));
      await tester.pumpAndSettle();
    }
  }, variant: desktop);

  testWidgets('near the top of the chat the toolbar moves down to stay '
      'inside it, never under the header', (tester) async {
    await _open(
      tester,
      size: const Size(1400, 500),
      entries: [for (var i = 0; i < 40; i++) _message('m$i', 'Message $i')],
    );
    final chat = tester.getRect(
      find
          .descendant(
            of: find.byType(TimelineView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    // The highest message whose bottom shows, close under the chat's top.
    final near =
        [
              for (var i = 0; i < 40; i++)
                if (find.text('Message $i').evaluate().isNotEmpty)
                  (i, _bubble(tester, 'Message $i')),
            ]
            .where((e) => e.$2.bottom > chat.top + 10)
            .reduce((a, b) => a.$2.bottom < b.$2.bottom ? a : b);
    expect(near.$2.bottom - chat.top, lessThan(100));
    final mouse = await _mouse(tester);
    await mouse.moveTo(
      Offset(near.$2.center.dx, (near.$2.bottom + chat.top) / 2 + 3),
    );
    await tester.pumpAndSettle();
    final toolbar = _toolbar(tester);
    expect(toolbar.top, greaterThanOrEqualTo(chat.top));
    expect(toolbar.bottom, lessThanOrEqualTo(chat.bottom));

    // At the bottom, the newest stays above the message box.
    await mouse.moveTo(tester.getCenter(find.text('Message 39')));
    await tester.pumpAndSettle();
    final composer = tester.getRect(find.byKey(const Key('composer.text')));
    expect(_toolbar(tester).bottom, lessThanOrEqualTo(composer.top));
  }, variant: desktop);
}
