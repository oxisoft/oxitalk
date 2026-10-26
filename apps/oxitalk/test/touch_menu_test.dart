import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oxitalk/src/app/file_actions.dart';
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

final _touch = TargetPlatformVariant({
  TargetPlatform.android,
  TargetPlatform.iOS,
});

Future<(FakeTimeline, FakeFileActions)> _open(
  WidgetTester tester, {
  required List<TimelineEntry> entries,
}) async {
  final session = FakeSession(
    userId: _me,
    rooms: const [Room(id: _room, name: 'Team')],
  );
  final timeline = FakeTimeline(ownUserId: _me, entries: entries);
  session.timelines[_room] = timeline;
  final files = FakeFileActions();
  await pumpApp(
    tester,
    FakeMatrixClientFactory(saved: [session]),
    files: files,
  );
  await tester.tap(find.text('Team'));
  await tester.pumpAndSettle();
  return (timeline, files);
}

/// The message's row: its bubble, and on desktop the room kept for the toolbar.
Rect _row(WidgetTester tester, String text) => tester.getRect(
  find
      .descendant(
        of: find.ancestor(
          of: find.text(text),
          matching: find.byType(MessageBubble),
        ),
        matching: find.byType(Row),
      )
      .first,
);

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

final _sheet = find.byKey(const Key('messageSheet'));

void main() {
  final entries = [_message('hi', 'Hi'), _message('mine', 'Mine', sender: _me)];

  /// The room beside each message, away from the sender's picture: on the right of Bob's
  /// (whose picture is on its left), on the left of the user's own.
  List<double> room(WidgetTester tester) => [
    _row(tester, 'Hi').right - _bubble(tester, 'Hi').right,
    _bubble(tester, 'Mine').left - _row(tester, 'Mine').left,
  ];

  testWidgets('on a touch screen no room is kept beside messages for the '
      'hover toolbar', (tester) async {
    await _open(tester, entries: entries);
    expect(room(tester), [
      moreOrLessEquals(0, epsilon: 0.5),
      moreOrLessEquals(0, epsilon: 0.5),
    ]);
    expect(find.byKey(const Key('hover.react')), findsNothing);
  }, variant: _touch);

  testWidgets('on desktop the room for the hover toolbar is still kept', (
    tester,
  ) async {
    await _open(tester, entries: entries);
    expect(room(tester), [greaterThanOrEqualTo(40), greaterThanOrEqualTo(40)]);
    // A tap only selects; there is no sheet on desktop.
    await tester.tap(find.text('Hi'));
    await tester.pumpAndSettle();
    expect(_sheet, findsNothing);
  }, variant: desktop);

  testWidgets('a tap on a message opens its sheet: reactions, then the '
      'actions; Reply answers it', (tester) async {
    await _open(tester, entries: entries);
    await tester.tap(find.text('Hi'));
    await tester.pumpAndSettle();
    expect(_sheet, findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('messageSheet.preview')),
        matching: find.text('Bob'),
      ),
      findsOneWidget,
    );
    for (final emoji in ['👍', '❤️', '😂', '😮', '😢', '🙏']) {
      expect(find.byKey(Key('messageSheet.react.$emoji')), findsOneWidget);
    }
    expect(find.byKey(const Key('messageSheet.react.more')), findsOneWidget);
    // The menus' actions, React… aside, as the reactions stand for it.
    final ids = [
      for (final element
          in find
              .byWidgetPredicate(
                (widget) =>
                    widget is ListTile &&
                    widget.key is ValueKey<String> &&
                    (widget.key! as ValueKey<String>).value.startsWith(
                      'messageSheet.',
                    ),
              )
              .evaluate())
        (element.widget.key! as ValueKey<String>).value,
    ];
    expect(ids, [
      'messageSheet.reply',
      'messageSheet.thread',
      'messageSheet.copy',
      'messageSheet.forward',
      // Someone else's message.
      'messageSheet.report',
    ]);

    await tester.tap(find.byKey(const Key('messageSheet.reply')));
    await tester.pumpAndSettle();
    expect(_sheet, findsNothing);
    expect(find.text('Replying to Bob'), findsOneWidget);
  }, variant: _touch);

  testWidgets('the user’s own message offers Edit and a red Delete', (
    tester,
  ) async {
    await _open(tester, entries: entries);
    await tester.tap(find.text('Mine'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('messageSheet.edit')), findsOneWidget);
    final delete = find.byKey(const Key('messageSheet.delete'));
    expect(delete, findsOneWidget);
    final label = tester.widget<Text>(
      find.descendant(of: delete, matching: find.text('Delete')),
    );
    final normal = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const Key('messageSheet.edit')),
        matching: find.text('Edit'),
      ),
    );
    expect(label.style?.color, isNot(normal.style?.color));

    await tester.tap(find.byKey(const Key('messageSheet.edit')));
    await tester.pumpAndSettle();
    expect(_sheet, findsNothing);
    expect(find.text('Editing'), findsOneWidget);
  }, variant: _touch);

  testWidgets('a quick reaction in the sheet reacts, and ＋ opens every '
      'emoji', (tester) async {
    final (timeline, _) = await _open(tester, entries: entries);
    await tester.tap(find.text('Hi'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('messageSheet.react.👍')));
    await tester.pumpAndSettle();
    expect(_sheet, findsNothing);
    expect(timeline.calls.where((call) => call.startsWith('react ')), [
      'react \$hi 👍',
    ]);
    expect(find.byKey(const Key('reactionChip.👍')), findsOneWidget);
    // The chip takes its own tap: it takes the reaction back, no sheet.
    await tester.tap(find.byKey(const Key('reactionChip.👍')));
    await tester.pumpAndSettle();
    expect(_sheet, findsNothing);
    expect(find.byKey(const Key('reactionChip.👍')), findsNothing);

    await tester.tap(find.text('Hi'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('messageSheet.react.more')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: _sheet, matching: find.byType(EmojiPicker)),
      findsOneWidget,
    );
  }, variant: _touch);

  testWidgets('a link in a message opens, without the sheet; a long press '
      'still selects', (tester) async {
    final (_, files) = await _open(
      tester,
      entries: [_message('p', 'Look at https://example.org/a, now.')],
    );
    await tester.tapOnText(find.textRange.ofSubstring('https://example.org/a'));
    await tester.pumpAndSettle();
    expect(files.launched, [Uri.parse('https://example.org/a')]);
    expect(_sheet, findsNothing);

    await tester.longPress(find.textContaining('Look at'));
    await tester.pumpAndSettle();
    expect(_sheet, findsNothing);
    expect(find.byType(AdaptiveTextSelectionToolbar), findsOneWidget);
  }, variant: _touch);
}
