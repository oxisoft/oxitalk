import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oxitalk/src/app/file_actions.dart';
import 'package:oxitalk/src/app/ui_prefs.dart';
import 'package:oxitalk/src/matrix/api/matrix.dart';
import 'package:oxitalk/src/matrix/fakes/fakes.dart';
import 'package:oxitalk/src/ui/rich_text_view.dart';

import 'support/app.dart';

const _wide = Size(1400, 900);
const _me = '@me:acme.com';
const _room = '!team:acme.com';

/// The battery report from bkv's screenshot, as the core gives it.
const _report = [
  RichBlock(ParagraphBlock(), [
    RichSpan('Battery low:', bold: true),
    RichSpan(' at '),
    RichSpan('20 %', italic: true),
  ]),
  RichBlock(ListItemBlock(), [RichSpan('first')]),
  RichBlock(ListItemBlock(number: 3, depth: 2), [RichSpan('third')]),
  RichBlock(HeadingBlock(2), [RichSpan('Readings')]),
  RichBlock(ParagraphBlock(), [RichSpan('quoted')], quoteDepth: 1),
  RichBlock(CodeBlock('rust'), [RichSpan('fn main() {}')]),
  RichBlock(RuleBlock(), []),
  RichBlock(ParagraphBlock(), [
    RichSpan('Bob', mention: '@bob:acme.com'),
    RichSpan(' see '),
    RichSpan('docs', link: 'https://oxisoft.io/docs'),
    RichSpan(' '),
    RichSpan('code', code: true),
    RichSpan(' '),
    RichSpan('secret', spoiler: true),
    RichSpan(' '),
    RichSpan('gone', strike: true),
    RichSpan(' '),
    RichSpan('red', color: '#ff0000'),
  ]),
];

Future<(FakeTimeline, FakeFileActions)> _open(
  WidgetTester tester, {
  List<TimelineEntry> entries = const [],
  MemoryUiPrefs? ui,
}) async {
  final timeline = FakeTimeline(ownUserId: _me, entries: entries);
  final session = FakeSession(
    userId: _me,
    rooms: const [Room(id: _room, name: 'Team')],
  );
  session.timelines[_room] = timeline;
  final files = FakeFileActions();
  await pumpApp(
    tester,
    FakeMatrixClientFactory(saved: [session]),
    size: _wide,
    files: files,
    ui: ui,
  );
  await tester.tap(find.text('Team'));
  await tester.pumpAndSettle();
  return (timeline, files);
}

/// The style of the run [text] in the rich text that contains it.
TextStyle? _styleOf(WidgetTester tester, String text) {
  for (final widget in tester.widgetList<RichText>(find.byType(RichText))) {
    TextStyle? found;
    widget.text.visitChildren((span) {
      if (span is TextSpan && span.text == text) found = span.style;
      return found == null;
    });
    if (found != null) return found;
  }
  return null;
}

void main() {
  testWidgets('a formatted message shows its formatting, not markdown', (
    tester,
  ) async {
    await _open(
      tester,
      entries: [
        MessageEntry(
          id: 'r',
          sender: '@bot:acme.com',
          time: DateTime(2026, 10, 20, 9),
          body: '**Battery low:** at *20 %*',
          formatted: _report,
        ),
      ],
    );
    expect(find.textContaining('**'), findsNothing);
    expect(_styleOf(tester, 'Battery low:')?.fontWeight, FontWeight.w700);
    expect(_styleOf(tester, '20 %')?.fontStyle, FontStyle.italic);
    expect(find.text('•'), findsOneWidget);
    expect(find.text('3.'), findsOneWidget);
    expect(find.byKey(const Key('rich.code')), findsOneWidget);
    expect(_styleOf(tester, 'gone')?.decoration, TextDecoration.lineThrough);
    expect(_styleOf(tester, 'red')?.color, const Color(0xFFFF0000));
    expect(_styleOf(tester, 'code')?.fontFamily, 'monospace');
    expect(_styleOf(tester, 'Bob')?.fontWeight, FontWeight.w700);
    // A spoiler hides its text until clicked.
    expect(_styleOf(tester, 'secret')?.color, Colors.transparent);
  });

  testWidgets('links open, in formatted and in plain text', (tester) async {
    final (_, files) = await _open(
      tester,
      entries: [
        MessageEntry(
          id: 'r',
          sender: '@bot:acme.com',
          time: DateTime(2026, 10, 20, 9),
          body: 'docs',
          formatted: const [
            RichBlock(ParagraphBlock(), [
              RichSpan('docs', link: 'https://oxisoft.io/docs'),
            ]),
          ],
        ),
        MessageEntry(
          id: 'p',
          sender: '@bot:acme.com',
          time: DateTime(2026, 10, 20, 9, 1),
          body: 'Look at https://example.org/a, now.',
        ),
      ],
    );
    await tester.tapOnText(find.textRange.ofSubstring('docs'));
    await tester.pumpAndSettle();
    await tester.tapOnText(find.textRange.ofSubstring('https://example.org/a'));
    await tester.pumpAndSettle();
    expect(files.launched, [
      Uri.parse('https://oxisoft.io/docs'),
      Uri.parse('https://example.org/a'),
    ]);
  });

  testWidgets('messages go as markdown, unless turned off in Settings', (
    tester,
  ) async {
    final ui = MemoryUiPrefs();
    final (timeline, _) = await _open(tester, ui: ui);
    await tester.enterText(find.byKey(const Key('composer.text')), '**hi**');
    // The microphone gives way to Send once there is text.
    await tester.pump();
    await tester.tap(find.byKey(const Key('composer.send')));
    await tester.pumpAndSettle();
    expect(timeline.lastSentAsMarkdown, isTrue);

    await tester.tap(find.byKey(const Key('rail.settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings.markdown')));
    await tester.pumpAndSettle();
    expect(ui.useMarkdown, isFalse);
    // Back returns to the chat.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('composer.text')), '**hi**');
    // The microphone gives way to Send once there is text.
    await tester.pump();
    await tester.tap(find.byKey(const Key('composer.send')));
    await tester.pumpAndSettle();
    expect(timeline.lastSentAsMarkdown, isFalse);
  });

  group('a code block’s copy button', () {
    String? copied;
    final entries = [
      MessageEntry(
        id: 'c',
        sender: '@bot:acme.com',
        time: DateTime(2026, 10, 20, 9),
        body: '```\nls -la\ncd /tmp\n```',
        formatted: const [
          RichBlock(CodeBlock('sh'), [RichSpan('ls -la\ncd /tmp')]),
        ],
      ),
    ];

    Future<void> open(WidgetTester tester) async {
      copied = null;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied =
                (call.arguments as Map<Object?, Object?>)['text'] as String?;
          }
          return null;
        },
      );
      await _open(tester, entries: entries);
    }

    testWidgets('shows on hover on desktop and copies the whole block', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        await open(tester);
        final copy = find.byKey(const Key('rich.code.copy'));
        expect(copy, findsNothing);
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        addTearDown(mouse.removePointer);
        await mouse.moveTo(
          tester.getCenter(find.byKey(const Key('rich.code'))),
        );
        await tester.pumpAndSettle();
        expect(copy, findsOneWidget);
        await tester.tap(copy);
        await tester.pump();
        expect(copied, 'ls -la\ncd /tmp');
        expect(find.text('Code copied'), findsOneWidget);
        expect(find.byIcon(Icons.check_rounded), findsOneWidget);
        // Leaving hides it again once the tick is gone.
        await mouse.moveTo(Offset.zero);
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();
        expect(copy, findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('is always there on a touch screen', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await open(tester);
        await tester.tap(find.byKey(const Key('rich.code.copy')));
        await tester.pump();
        expect(copied, 'ls -la\ncd /tmp');
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  test('CSS colours are read', () {
    expect(parseCssColor('#f00'), const Color(0xFFFF0000));
    expect(parseCssColor('#00ff00'), const Color(0xFF00FF00));
    expect(parseCssColor('red'), isNull);
    expect(parseCssColor(null), isNull);
  });
}
