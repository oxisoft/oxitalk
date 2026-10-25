import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oxitalk/src/app/theme.dart';
import 'package:oxitalk/src/app/ui_prefs.dart';
import 'package:oxitalk/src/features/chat/chat_pane.dart';
import 'package:oxitalk/src/features/chat/threads.dart';
import 'package:oxitalk/src/features/chats/chats_screen.dart';
import 'package:oxitalk/src/features/chats/pane_layout.dart';
import 'package:oxitalk/src/matrix/api/matrix.dart';
import 'package:oxitalk/src/matrix/fakes/fakes.dart';

import 'support/app.dart';

const _wide = Size(1400, 900);
const _me = '@me:acme.com';
const _bob = '@bob:acme.com';
const _room = '!team:acme.com';
const _root = r'$lunch';

/// The account rail and its line.
const _rail = 73.0;

final _list = find.byKey(const Key('divider.list'));
final _thread = find.byKey(const Key('divider.thread'));

MessageEntry _message(String id, String body, {ThreadSummary? thread}) =>
    MessageEntry(
      id: id,
      sender: _bob,
      senderName: 'Bob',
      time: DateTime(2026, 10, 20, 12),
      body: body,
      meta: EventMeta(eventId: '\$$id', thread: thread),
    );

/// The window with the Team chat open; [thread] opens Bob's thread beside it.
Future<void> _open(
  WidgetTester tester, {
  required MemoryUiPrefs ui,
  Size size = _wide,
  bool thread = false,
}) async {
  final session = FakeSession(
    userId: _me,
    rooms: const [Room(id: _room, name: 'Team')],
  );
  session.timelines[_room] = FakeTimeline(
    ownUserId: _me,
    entries: [
      _message(
        'lunch',
        'lunch?',
        thread: ThreadSummary(
          replyCount: 1,
          latest: ThreadEvent(
            sender: _bob,
            senderName: 'Bob',
            text: 'sushi',
            time: DateTime(2026, 10, 20, 12, 2),
          ),
        ),
      ),
    ],
  );
  session.threadTimelines[_root] = FakeTimeline(
    ownUserId: _me,
    entries: [_message('lunch', 'lunch?'), _message('sushi', 'sushi')],
  );
  await pumpApp(
    tester,
    FakeMatrixClientFactory(saved: [session]),
    size: size,
    ui: ui,
  );
  await tester.tap(find.text('Team'));
  await tester.pumpAndSettle();
  if (thread) {
    await tester.tap(find.byKey(const Key('thread.bar.$_root')));
    await tester.pumpAndSettle();
  }
}

double _width(WidgetTester tester, Type type) =>
    tester.getSize(find.byType(type)).width;

/// Drags [divider] by [dx] with a mouse, as on a desktop.
Future<void> _drag(WidgetTester tester, Finder divider, double dx) async {
  final mouse = await tester.startGesture(
    tester.getCenter(divider),
    kind: PointerDeviceKind.mouse,
  );
  // Past the slop first, then the rest, so the whole [dx] is dragged.
  await mouse.moveBy(Offset(dx.sign * 20, 0));
  await tester.pump();
  await mouse.moveBy(Offset(dx - dx.sign * 20, 0));
  await tester.pump();
  await mouse.up();
  await tester.pumpAndSettle();
}

Future<void> _doubleClick(WidgetTester tester, Finder divider) async {
  await tester.tap(divider, kind: PointerDeviceKind.mouse);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tap(divider, kind: PointerDeviceKind.mouse);
  await tester.pumpAndSettle();
}

void main() {
  test('the widths are kept in ui.json across starts', () async {
    final dir = Directory.systemTemp.createTempSync('ui_prefs');
    addTearDown(() => dir.deleteSync(recursive: true));
    final prefs = await FileUiPrefs.load(dir);
    expect(prefs.listWidth, isNull);
    expect(prefs.threadWidth, isNull);
    await prefs.setListWidth(420);
    await prefs.setThreadWidth(512.5);

    final again = await FileUiPrefs.load(dir);
    expect(again.listWidth, 420);
    expect(again.threadWidth, 512.5);
    await again.setListWidth(null);
    expect((await FileUiPrefs.load(dir)).listWidth, isNull);
    expect((await FileUiPrefs.load(dir)).threadWidth, 512.5);
  });

  testWidgets('dragging the line after the chat list resizes it, and the '
      'width is saved', (tester) async {
    final ui = MemoryUiPrefs();
    await _open(tester, ui: ui);
    expect(_width(tester, ChatListPane), PaneLayout.listDefault);
    // The grip lies over the line.
    expect(tester.getCenter(_list).dx, _rail + PaneLayout.listDefault + 0.5);

    await _drag(tester, _list, 100);
    expect(_width(tester, ChatListPane), 460);
    expect(ui.listWidth, 460);
    expect(tester.getCenter(_list).dx, _rail + 460 + 0.5);
    // The chat takes the rest.
    expect(_width(tester, ChatPane), _wide.width - _rail - 460 - 1);
  });

  testWidgets('the chat list keeps within its limits', (tester) async {
    final ui = MemoryUiPrefs();
    await _open(tester, ui: ui);
    await _drag(tester, _list, -400);
    expect(_width(tester, ChatListPane), PaneLayout.listMin);
    expect(ui.listWidth, PaneLayout.listMin);

    await _drag(tester, _list, 1000);
    expect(_width(tester, ChatListPane), PaneLayout.listMaxCap);
    expect(ui.listWidth, PaneLayout.listMaxCap);
  });

  testWidgets('on a smaller window the list stops at 45% of it', (
    tester,
  ) async {
    final ui = MemoryUiPrefs(railHidden: true);
    await _open(tester, ui: ui, size: const Size(1000, 800));
    await _drag(tester, _list, 1000);
    expect(_width(tester, ChatListPane), 450);
    expect(_width(tester, ChatPane), greaterThanOrEqualTo(PaneLayout.chatMin));
  });

  testWidgets('with a thread open, its line resizes the thread pane, and the '
      'width is saved', (tester) async {
    final ui = MemoryUiPrefs();
    await _open(tester, ui: ui, thread: true);
    expect(_width(tester, ThreadPane), PaneLayout.threadDefault);
    expect(
      tester.getCenter(_thread).dx,
      _wide.width - PaneLayout.threadDefault - 0.5,
    );

    // To the left makes the thread wider.
    await _drag(tester, _thread, -100);
    expect(_width(tester, ThreadPane), 500);
    expect(ui.threadWidth, 500);
    expect(_width(tester, ChatPane), _wide.width - _rail - 360 - 500 - 2);

    await _drag(tester, _thread, 1000);
    expect(_width(tester, ThreadPane), PaneLayout.threadMin);

    // Never so wide the chat gets less than its minimum.
    await _drag(tester, _thread, -2000);
    expect(_width(tester, ChatPane), PaneLayout.chatMin);
    expect(ui.threadWidth, _wide.width - _rail - 360 - 2 - PaneLayout.chatMin);
    // Nor the list.
    await _drag(tester, _list, 300);
    expect(_width(tester, ChatPane), PaneLayout.chatMin);
    expect(_width(tester, ChatListPane), 360);
  });

  testWidgets('without a thread there is no thread line', (tester) async {
    await _open(tester, ui: MemoryUiPrefs());
    expect(_list, findsOneWidget);
    expect(_thread, findsNothing);
  });

  testWidgets('a double click on a line puts its pane back to the default '
      'width', (tester) async {
    final ui = MemoryUiPrefs(listWidth: 500, threadWidth: 600);
    await _open(tester, ui: ui, thread: true);
    expect(_width(tester, ChatListPane), 500);
    // Both don't fit beside the chat: the thread gives way.
    expect(_width(tester, ThreadPane), _wide.width - _rail - 500 - 2 - 360);

    await _doubleClick(tester, _list);
    expect(_width(tester, ChatListPane), PaneLayout.listDefault);
    expect(ui.listWidth, isNull);
    expect(_width(tester, ThreadPane), 600);

    await _doubleClick(tester, _thread);
    expect(_width(tester, ThreadPane), PaneLayout.threadDefault);
    expect(ui.threadWidth, isNull);
  });

  testWidgets('saved widths come back on start', (tester) async {
    await _open(
      tester,
      ui: MemoryUiPrefs(listWidth: 420, threadWidth: 480),
      thread: true,
    );
    expect(_width(tester, ChatListPane), 420);
    expect(_width(tester, ThreadPane), 480);
  });

  testWidgets('a smaller window shrinks the side panes, not the chat below '
      'its minimum; a larger one gives the widths back', (tester) async {
    final ui = MemoryUiPrefs(listWidth: 560, threadWidth: 700);
    await _open(tester, ui: ui, thread: true, size: const Size(1700, 900));
    expect(_width(tester, ChatListPane), 560);
    expect(_width(tester, ThreadPane), 700);

    for (final width in [1200.0, 1000.0, 900.0]) {
      tester.view.physicalSize = Size(width, 900);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        _width(tester, ChatPane),
        greaterThanOrEqualTo(PaneLayout.chatMin),
        reason: '$width',
      );
      expect(
        _rail +
            _width(tester, ChatListPane) +
            _width(tester, ChatPane) +
            _width(tester, ThreadPane) +
            2,
        width,
      );
    }
    // The thread gives way first.
    tester.view.physicalSize = const Size(1400, 900);
    await tester.pumpAndSettle();
    expect(_width(tester, ChatListPane), 560);
    expect(_width(tester, ThreadPane), 1400 - _rail - 560 - 2 - 360);

    tester.view.physicalSize = const Size(1700, 900);
    await tester.pumpAndSettle();
    expect(_width(tester, ChatListPane), 560);
    expect(_width(tester, ThreadPane), 700);
    // What was dragged is kept as it was.
    expect(ui.listWidth, 560);
    expect(ui.threadWidth, 700);
  });

  testWidgets('a hidden rail moves the line with the list', (tester) async {
    final ui = MemoryUiPrefs(railHidden: true);
    await _open(tester, ui: ui);
    expect(tester.getCenter(_list).dx, PaneLayout.listDefault + 0.5);
    await _drag(tester, _list, 40);
    expect(_width(tester, ChatListPane), 400);
  });

  testWidgets('the narrowed list has no grip', (tester) async {
    await _open(tester, ui: MemoryUiPrefs(narrowList: true, listWidth: 500));
    expect(_width(tester, ChatListPane), PaneLayout.narrowList);
    expect(_list, findsNothing);
  });

  testWidgets('a phone has no lines to drag', (tester) async {
    await _open(tester, ui: MemoryUiPrefs(), size: const Size(400, 800));
    expect(_list, findsNothing);
    expect(_thread, findsNothing);
  });

  testWidgets('the lines tell a screen reader what they do, and the arrow '
      'keys move them', (tester) async {
    final ui = MemoryUiPrefs();
    await _open(tester, ui: ui, thread: true);
    expect(
      tester.getSemantics(_list),
      isSemantics(
        label: 'Resize chat list',
        value: '360 pixels',
        hasIncreaseAction: true,
        hasDecreaseAction: true,
        isFocusable: true,
      ),
    );
    expect(
      tester.getSemantics(_thread),
      isSemantics(
        label: 'Resize thread',
        value: '400 pixels',
        hasIncreaseAction: true,
        hasDecreaseAction: true,
        isFocusable: true,
      ),
    );

    Focus.of(
      tester.element(
        find.descendant(of: _list, matching: find.byType(MouseRegion)).first,
      ),
    ).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(_width(tester, ChatListPane), 376);
    expect(ui.listWidth, 376);

    Focus.of(
      tester.element(
        find.descendant(of: _thread, matching: find.byType(MouseRegion)).first,
      ),
    ).requestFocus();
    await tester.pump();
    // The thread's line to the left makes it wider.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(_width(tester, ThreadPane), 416);
    expect(ui.threadWidth, 416);
  });

  for (final (theme, lit) in [
    ('dark', OxiBrand.yellow),
    ('light', OxiBrand.ink),
  ]) {
    testWidgets('hovering a line lights it up, $theme', (tester) async {
      await _open(tester, ui: MemoryUiPrefs(theme: theme));
      Color? line() =>
          (tester
                      .widget<AnimatedContainer>(
                        find.descendant(
                          of: _list,
                          matching: find.byType(AnimatedContainer),
                        ),
                      )
                      .decoration
                  as BoxDecoration?)
              ?.color;
      expect(line(), Colors.transparent);
      expect(
        tester
            .widget<MouseRegion>(
              find.descendant(of: _list, matching: find.byType(MouseRegion)),
            )
            .cursor,
        SystemMouseCursors.resizeColumn,
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(_list));
      await tester.pumpAndSettle();
      expect(line(), lit);
      await mouse.moveTo(const Offset(700, 400));
      await tester.pumpAndSettle();
      expect(line(), Colors.transparent);
    });
  }
}
