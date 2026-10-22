import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oxitalk/src/app/file_actions.dart';
import 'package:oxitalk/src/features/chat/emoji.dart';
import 'package:oxitalk/src/matrix/api/matrix.dart';
import 'package:oxitalk/src/matrix/fakes/fakes.dart';

import 'support/app.dart';
import 'support/png.dart';

const _wide = Size(1400, 900);
const _me = '@me:acme.com';
const _bob = '@bob:acme.com';
const _room = '!team:acme.com';

MessageEntry _message(
  String id,
  String body, {
  String sender = _bob,
  int minute = 0,
  EventMeta? meta,
  SendState sendState = SendState.sent,
}) => MessageEntry(
  id: id,
  sender: sender,
  senderName: sender == _bob ? 'Bob' : 'Me',
  time: DateTime(2026, 10, 20, 9, minute),
  body: body,
  isOwn: sender == _me,
  sendState: sendState,
  meta: meta ?? EventMeta(eventId: '\$$id', isEditable: sender == _me),
);

/// A chat with [entries] (by default, one message from Bob and one of the user's), opened.
Future<(FakeSession, FakeTimeline, FakeFileActions)> _open(
  WidgetTester tester, {
  List<TimelineEntry>? entries,
}) async {
  final timeline = FakeTimeline(
    ownUserId: _me,
    entries:
        entries ??
        [
          _message('hello', 'Hello there'),
          _message('mine', 'My message', sender: _me, minute: 1),
        ],
  );
  final session = FakeSession(
    userId: _me,
    rooms: const [
      Room(id: _room, name: 'Team'),
      Room(id: '!other:acme.com', name: 'Other team'),
    ],
  );
  session.timelines[_room] = timeline;
  final files = FakeFileActions();
  await pumpApp(
    tester,
    FakeMatrixClientFactory(saved: [session]),
    size: _wide,
    files: files,
  );
  await tester.tap(find.text('Team'));
  await tester.pumpAndSettle();
  return (session, timeline, files);
}

/// Moves the mouse over the message with [text], showing its toolbar.
Future<void> _hover(WidgetTester tester, String text) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  await mouse.moveTo(tester.getCenter(find.text(text)));
  await tester.pumpAndSettle();
}

/// Opens the More menu of the message with [text] and picks [item].
Future<void> _more(WidgetTester tester, String text, String item) async {
  await _hover(tester, text);
  await tester.tap(find.byKey(const Key('hover.more')).hitTestable().first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(item).last);
  await tester.pumpAndSettle();
}

void main() {
  group('reactions', () {
    testWidgets('show under the message with counts; a click gives or takes '
        'back the user’s', (tester) async {
      final (_, timeline, _) = await _open(
        tester,
        entries: [
          _message(
            'hello',
            'Hello there',
            meta: const EventMeta(
              eventId: r'$hello',
              reactions: [
                Reaction('👍', [_bob, _me], mine: true),
                Reaction('🎉', [_bob]),
              ],
            ),
          ),
        ],
      );
      // A count shows from two up only.
      expect(find.text('👍'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('🎉'), findsOneWidget);
      expect(find.byKey(const Key('reactionChip.🎉.count')), findsNothing);
      expect(find.text('1'), findsNothing);

      await tester.tap(find.byKey(const Key('reactionChip.🎉')));
      await tester.pumpAndSettle();
      expect(timeline.calls, [r'react $hello 🎉']);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('reactionChip.🎉.count')))
            .data,
        '2',
      );
    });

    testWidgets('a count is smaller and quieter than its emoji, so 3️⃣ 2 '
        'reads right; the user’s own stays highlighted', (tester) async {
      await _open(
        tester,
        entries: [
          _message(
            'hello',
            'Hello there',
            meta: const EventMeta(
              eventId: r'$hello',
              reactions: [
                Reaction('3️⃣', [_bob, _me], mine: true),
                Reaction('👀', [_bob, '@carol:acme.com']),
              ],
            ),
          ),
        ],
      );
      final emoji = tester.widget<Text>(
        find.byKey(const Key('reactionChip.3️⃣.emoji')),
      );
      final count = tester.widget<Text>(
        find.byKey(const Key('reactionChip.3️⃣.count')),
      );
      final ratio = count.style!.fontSize! / emoji.style!.fontSize!;
      expect(ratio, inInclusiveRange(0.70, 0.75));
      final theme = Theme.of(
        tester.element(find.byKey(const Key('reactionChip.3️⃣'))),
      );
      expect(count.style!.color, theme.colorScheme.onSurfaceVariant);
      expect(
        tester.getSize(find.byKey(const Key('reactionChip.3️⃣.count'))).height,
        lessThan(
          tester
              .getSize(find.byKey(const Key('reactionChip.3️⃣.emoji')))
              .height,
        ),
      );
      Color chipColor(String key) =>
          tester.widget<Material>(find.byKey(Key('reactionChip.$key'))).color!;
      expect(chipColor('3️⃣'), isNot(chipColor('👀')));
    });

    testWidgets('the toolbar’s React offers the quick ones and remembers the '
        'one used', (tester) async {
      final (session, timeline, _) = await _open(tester);
      await _hover(tester, 'Hello there');
      await tester.tap(
        find.byKey(const Key('hover.react')).hitTestable().first,
      );
      await tester.pumpAndSettle();
      for (final emoji in quickReactions) {
        expect(find.byKey(Key('reaction.$emoji')), findsOneWidget);
      }
      await tester.tap(find.byKey(const Key('reaction.❤️')));
      await tester.pumpAndSettle();
      expect(timeline.calls, [r'react $hello ❤️']);
      expect(session.recent, ['❤️']);
      expect(find.byKey(const Key('reactionChip.❤️')), findsOneWidget);
      expect(find.byKey(const Key('reactionChip.❤️.count')), findsNothing);
    });
  });

  group('reply', () {
    testWidgets('the toolbar’s Reply shows what is answered; sending replies', (
      tester,
    ) async {
      final (_, timeline, _) = await _open(tester);
      await _hover(tester, 'Hello there');
      await tester.tap(
        find.byKey(const Key('hover.reply')).hitTestable().first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Replying to Bob'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('composer.text')), 'Hi Bob');
      // The microphone gives way to Send once there is text.
      await tester.pump();
      await tester.tap(find.byKey(const Key('composer.send')));
      await tester.pumpAndSettle();
      expect(timeline.calls, [r'reply $hello Hi Bob']);
      expect(find.byKey(const Key('composer.mode')), findsNothing);
    });

    testWidgets('Esc stops replying', (tester) async {
      final (_, timeline, _) = await _open(tester);
      await _more(tester, 'Hello there', 'Reply');
      expect(find.byKey(const Key('composer.mode')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('composer.mode')), findsNothing);
      await tester.enterText(find.byKey(const Key('composer.text')), 'New');
      // The microphone gives way to Send once there is text.
      await tester.pump();
      await tester.tap(find.byKey(const Key('composer.send')));
      await tester.pumpAndSettle();
      expect(timeline.calls, isEmpty);
      expect(find.text('New'), findsOneWidget);
    });

    testWidgets('a reply shows the message it answers', (tester) async {
      await _open(
        tester,
        entries: [
          _message('hello', 'Hello there'),
          _message(
            'answer',
            'General Kenobi',
            sender: _me,
            minute: 1,
            meta: const EventMeta(
              eventId: r'$answer',
              inReplyTo: ReplyQuote(
                eventId: r'$hello',
                sender: _bob,
                senderName: 'Bob',
                text: 'Hello there',
              ),
            ),
          ),
        ],
      );
      final quote = find.byKey(const Key('message.quote'));
      expect(
        find.descendant(of: quote, matching: find.text('Hello there')),
        findsOneWidget,
      );
      await tester.tap(quote);
      await tester.pumpAndSettle();
    });
  });

  group('edit, delete, forward', () {
    testWidgets('Edit puts the text in the box; Save changes it', (
      tester,
    ) async {
      final (_, timeline, _) = await _open(tester);
      await _more(tester, 'My message', 'Edit');
      expect(find.text('Editing'), findsOneWidget);
      final box = find.byKey(const Key('composer.text'));
      expect(tester.widget<TextField>(box).controller!.text, 'My message');

      await tester.enterText(box, 'My better message');
      await tester.tap(find.byKey(const Key('composer.send')));
      await tester.pumpAndSettle();
      expect(timeline.calls, [r'edit $mine My better message']);
    });

    testWidgets('someone else’s message has no Edit and, for a member, no '
        'Delete', (tester) async {
      await _open(tester);
      await _hover(tester, 'Hello there');
      await tester.tap(find.byKey(const Key('hover.more')).hitTestable().first);
      await tester.pumpAndSettle();
      expect(find.text('Reply'), findsOneWidget);
      expect(find.text('Edit'), findsNothing);
      expect(find.text('Delete'), findsNothing);
    });

    testWidgets('Delete asks first, then deletes', (tester) async {
      final (_, timeline, _) = await _open(tester);
      await _more(tester, 'My message', 'Delete');
      expect(find.text('Delete this message?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('message.deleteConfirm')));
      await tester.pumpAndSettle();
      expect(timeline.calls, [r'redact $mine']);
    });

    testWidgets('Forward sends it to the picked chat', (tester) async {
      final (_, timeline, _) = await _open(tester);
      await _more(tester, 'Hello there', 'Forward…');
      await tester.enterText(find.byKey(const Key('forward.search')), 'other');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('forward.$_room')), findsNothing);
      await tester.tap(find.byKey(const Key('forward.!other:acme.com')));
      await tester.pumpAndSettle();
      expect(timeline.calls, [r'forward $hello !other:acme.com']);
      expect(find.text('Forwarded to Other team'), findsOneWidget);
    });

    testWidgets('deleted and edited messages say so', (tester) async {
      await _open(
        tester,
        entries: [
          RedactedEntry(
            id: 'gone',
            sender: _bob,
            time: DateTime(2026, 10, 20, 9),
            meta: const EventMeta(eventId: r'$gone'),
          ),
          _message(
            'fixed',
            'Fixed typo',
            minute: 1,
            meta: const EventMeta(eventId: r'$fixed', isEdited: true),
          ),
        ],
      );
      expect(find.text('Message deleted'), findsOneWidget);
      expect(find.text('edited'), findsOneWidget);
    });

    testWidgets('a failed message can be sent again or removed', (
      tester,
    ) async {
      final (_, timeline, _) = await _open(
        tester,
        entries: [
          _message(
            'local',
            'Lost in space',
            sender: _me,
            sendState: SendState.failed,
            meta: const EventMeta(transactionId: 'txn1'),
          ),
        ],
      );
      await tester.tap(find.byKey(const Key('message.retry')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('message.remove')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('message.deleteConfirm')));
      await tester.pumpAndSettle();
      expect(timeline.calls, ['retry txn1', 'redact txn1']);
    });
  });

  group('files', () {
    testWidgets('📎 picks files; the dialog sends them with a caption, '
        'compressed', (tester) async {
      final (_, timeline, files) = await _open(tester);
      files.picked = [
        PendingFile('beach.png', 'image/png', png),
        PendingFile('notes.txt', 'text/plain', png),
      ];
      await tester.tap(find.byKey(const Key('composer.attach')));
      await tester.pumpAndSettle();
      expect(find.text('Send 2 files'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('send.caption')), 'Holiday');
      await tester.tap(find.byKey(const Key('send.confirm')));
      await tester.pumpAndSettle();
      expect(timeline.files, {
        'beach.png': ('Holiday', true),
        'notes.txt': (null, true),
      });
    });

    testWidgets('a pasted image goes to the same dialog; Compress can be off', (
      tester,
    ) async {
      final (_, timeline, files) = await _open(tester);
      files.clipboard = png;
      await tester.tap(find.byKey(const Key('composer.text')));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(find.text('Send photo'), findsOneWidget);
      await tester.tap(find.byKey(const Key('send.compress')));
      await tester.tap(find.byKey(const Key('send.confirm')));
      await tester.pumpAndSettle();
      expect(timeline.files, {'pasted.png': (null, false)});
    });

    testWidgets('an upload shows its progress', (tester) async {
      await _open(
        tester,
        entries: [
          MediaEntry(
            id: 'up',
            sender: _me,
            time: DateTime(2026, 10, 20, 9),
            isOwn: true,
            sendState: SendState.sending,
            media: const MediaInfo(
              kind: MediaKind.file,
              source: 'local',
              filename: 'big.zip',
            ),
            meta: const EventMeta(transactionId: 'txn2', uploadPercent: 40),
          ),
        ],
      );
      final bar = tester.widget<LinearProgressIndicator>(
        find.byKey(const Key('message.upload')),
      );
      expect(bar.value, 0.4);
    });
  });

  testWidgets('a message of only emojis shows big, without a bubble', (
    tester,
  ) async {
    await _open(tester, entries: [_message('party', '🎉🎉')]);
    expect(tester.widget<Text>(find.text('🎉🎉')).style?.fontSize, 40);
  });

  test('emoji-only messages are told apart', () {
    expect(isEmojiOnly('👍'), isTrue);
    expect(isEmojiOnly('🇵🇱 ❤️'), isTrue);
    expect(isEmojiOnly('👨‍👩‍👧'), isTrue);
    expect(isEmojiOnly('1️⃣'), isTrue);
    expect(isEmojiOnly('👍👍👍👍'), isFalse);
    expect(isEmojiOnly('ok 👍'), isFalse);
    expect(isEmojiOnly('12'), isFalse);
    expect(isEmojiOnly(''), isFalse);
  });
}
