import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oxitalk/src/app/theme.dart';
import 'package:oxitalk/src/features/chat/chat_pane.dart';
import 'package:oxitalk/src/features/chat/message_actions.dart';
import 'package:oxitalk/src/matrix/api/matrix.dart';

final _latest = ThreadEvent(
  sender: '@carol:acme.com',
  senderName: 'Carol',
  text: 'pizza',
  time: DateTime(2026, 10, 20, 12, 5),
);

const _bar = Key('bar');

/// One message, on its own, with a thread of [replies] replies.
Future<void> _pump(
  WidgetTester tester, {
  required Widget child,
  bool isOwn = false,
  bool plain = false,
  bool edited = false,
  Widget? quote,
  bool reactions = false,
  int replies = 3,
  Size size = const Size(800, 600),
  Brightness brightness = Brightness.light,
  VoidCallback? onTap,
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: oxiTheme(brightness),
        home: Scaffold(
          body: ListView(
            children: [
              MessageBubble(
                key: const Key('message'),
                isOwn: isOwn,
                plain: plain,
                edited: edited,
                quote: quote,
                sender: isOwn ? null : 'Bob',
                time: DateTime(2026, 10, 20, 12),
                reactions: reactions
                    ? ReactionChips(
                        key: const Key('reactions'),
                        reactions: const [
                          Reaction('👍', ['@bob:acme.com']),
                        ],
                        onToggle: (_) {},
                      )
                    : null,
                thread: ThreadBar(
                  key: _bar,
                  account: '@me:acme.com',
                  thread: ThreadSummary(replyCount: replies, latest: _latest),
                  compact: plain,
                  onTap: onTap ?? () {},
                ),
                child: child,
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The bubble's painted box: the decorated container around the message.
Rect _bubbleRect(WidgetTester tester) => tester.getRect(
  find
      .ancestor(of: find.byKey(_bar), matching: find.byType(DecoratedBox))
      .first,
);

bool _contains(Rect outer, Rect inner) =>
    inner.left >= outer.left - 0.01 &&
    inner.right <= outer.right + 0.01 &&
    inner.top >= outer.top - 0.01 &&
    inner.bottom <= outer.bottom + 0.01;

void main() {
  for (final brightness in Brightness.values) {
    for (final isOwn in [false, true]) {
      testWidgets('the thread is the last row inside the bubble, full width '
          '(${brightness.name}, ${isOwn ? 'own' : 'other'})', (tester) async {
        var opened = 0;
        await _pump(
          tester,
          isOwn: isOwn,
          brightness: brightness,
          reactions: true,
          child: const Text('lunch?'),
          onTap: () => opened++,
        );
        final bubble = _bubbleRect(tester);
        final bar = tester.getRect(find.byKey(_bar));
        expect(_contains(bubble, bar), isTrue, reason: '$bar in $bubble');
        // Across the full width, at the bottom, under the message.
        expect(bar.width, moreOrLessEquals(bubble.width));
        expect(bar.bottom, moreOrLessEquals(bubble.bottom));
        expect(
          bar.top,
          greaterThan(tester.getRect(find.text('lunch?')).bottom),
        );
        // Reactions stay under the bubble.
        expect(
          tester.getRect(find.byKey(const Key('reactions'))).top,
          greaterThanOrEqualTo(bubble.bottom),
        );
        expect(
          find.descendant(of: find.byKey(_bar), matching: find.byType(Divider)),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(_bar),
            matching: find.textContaining('3 replies'),
          ),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
        expect(find.byIcon(Icons.forum_outlined), findsOneWidget);

        await tester.tap(find.byIcon(Icons.chevron_right_rounded));
        await tester.tap(find.byKey(_bar));
        expect(opened, 2);
      });
    }
  }

  testWidgets('a short message widens to fit its thread row, a long one '
      'gives the row its width', (tester) async {
    await _pump(tester, child: const Text('ok'));
    final short = _bubbleRect(tester);
    expect(
      short.width,
      moreOrLessEquals(tester.getRect(find.byKey(_bar)).width),
    );
    // Not stretched to the maximum (75% of 800).
    expect(short.width, lessThan(400));

    await _pump(
      tester,
      child: const Text(
        'A much longer message that is clearly wider than the thread row',
      ),
    );
    final long = _bubbleRect(tester);
    expect(long.width, greaterThan(short.width));
    expect(
      tester.getRect(find.byKey(_bar)).width,
      moreOrLessEquals(long.width),
    );
  });

  testWidgets('quoted, edited and media-like bubbles keep the row inside', (
    tester,
  ) async {
    await _pump(
      tester,
      edited: true,
      quote: const Text('Bob: who takes Friday?'),
      child: const SizedBox(width: 320, height: 200, child: Placeholder()),
    );
    final bubble = _bubbleRect(tester);
    final bar = tester.getRect(find.byKey(_bar));
    expect(_contains(bubble, bar), isTrue);
    expect(bar.width, moreOrLessEquals(bubble.width));
    expect(find.text('edited'), findsOneWidget);
    expect(
      bar.top,
      greaterThanOrEqualTo(tester.getRect(find.byType(Placeholder)).bottom),
    );
  });

  testWidgets('a narrow window shortens the row instead of overflowing', (
    tester,
  ) async {
    await _pump(
      tester,
      size: const Size(150, 400),
      replies: 12345,
      child: const Text('hi'),
    );
    // An overflow would have failed the pump.
    expect(tester.takeException(), isNull);
    final bubble = _bubbleRect(tester);
    expect(bubble.width, lessThanOrEqualTo(150 * 0.75 + 0.01));
    expect(_contains(bubble, tester.getRect(find.byKey(_bar))), isTrue);
  });

  testWidgets('under big emojis without a bubble, the thread is a small chip '
      'right under them', (tester) async {
    var opened = 0;
    await _pump(
      tester,
      plain: true,
      child: const Text('🎉', style: TextStyle(fontSize: 40)),
      onTap: () => opened++,
    );
    final emoji = tester.getRect(find.text('🎉'));
    final chip = tester.getRect(find.byKey(_bar));
    expect(chip.top, greaterThanOrEqualTo(emoji.bottom));
    expect(chip.top - emoji.bottom, lessThan(30));
    expect(chip.left, moreOrLessEquals(emoji.left, epsilon: 12));
    expect(chip.width, lessThan(320));
    expect(
      find.descendant(of: find.byKey(_bar), matching: find.byType(Divider)),
      findsNothing,
    );
    await tester.tap(find.byKey(_bar));
    expect(opened, 1);
  });
}
