import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oxitalk/src/app/window_controls.dart';
import 'package:oxitalk/src/matrix/api/matrix.dart';
import 'package:oxitalk/src/matrix/fakes/fakes.dart';

import 'support/app.dart';
import 'support/rust_core.dart';

const _wide = Size(1200, 800);
const _phone = Size(400, 800);
const _me = '@me:acme.com';

/// A window whose title bar the app draws; remembers what was asked of it.
final class _FakeWindow implements WindowControls {
  final calls = <String>[];

  @override
  bool get drawsTitleBar => true;

  @override
  Future<void> startDragging() async => calls.add('drag');

  @override
  Future<void> minimize() async => calls.add('minimize');

  @override
  Future<void> toggleMaximize() async => calls.add('maximize');

  @override
  Future<void> close() async => calls.add('close');
}

FakeSession _session() =>
    FakeSession(
        userId: _me,
        rooms: const [Room(id: '!team', name: 'Team')],
      )
      ..timelines['!team'] = FakeTimeline(
        ownUserId: _me,
        entries: [
          MessageEntry(
            id: 'm0',
            sender: '@bob:acme.com',
            senderName: 'Bob',
            time: DateTime(2026, 10, 19, 12),
            body: 'The server is at 10.10.33.177',
          ),
        ],
      );

void main() {
  // About shows the core's version.
  setUpAll(initRustCore);

  testWidgets('the app’s own title bar moves the window and has its buttons', (
    tester,
  ) async {
    final window = _FakeWindow();
    await pumpApp(
      tester,
      FakeMatrixClientFactory(saved: [_session()]),
      size: _wide,
      window: window,
    );
    await tester.tap(find.byKey(const Key('window.minimize')));
    await tester.tap(find.byKey(const Key('window.maximize')));
    await tester.tap(find.byKey(const Key('window.close')));
    await tester.drag(find.text('OxiTalk'), const Offset(100, 20));
    await tester.pumpAndSettle();
    expect(window.calls, ['minimize', 'maximize', 'close', 'drag']);

    // The headers under the strip still work.
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    expect(find.text('Log out'), findsOneWidget);
  });

  testWidgets('the open chat’s header leaves room for the window buttons', (
    tester,
  ) async {
    await pumpApp(
      tester,
      FakeMatrixClientFactory(saved: [_session()]),
      size: _wide,
      window: _FakeWindow(),
    );
    await tester.tap(find.text('Team'));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byType(WindowButtonsSpace)).width,
      greaterThanOrEqualTo(120),
    );
  });

  testWidgets('without its own title bar the app draws no window buttons', (
    tester,
  ) async {
    await pumpApp(
      tester,
      FakeMatrixClientFactory(saved: [_session()]),
      size: _wide,
    );
    expect(find.byKey(const Key('window.close')), findsNothing);
  });

  testWidgets('Settings and About are at the bottom of the rail, '
      'not in the account menu', (tester) async {
    await pumpApp(
      tester,
      FakeMatrixClientFactory(saved: [_session()]),
      size: _wide,
    );
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsNothing);
    expect(find.text('About'), findsNothing);
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('rail.about')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Rust core'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('rail.settings')));
    await tester.pumpAndSettle();
    expect(find.text('Collect logs'), findsOneWidget);
  });

  testWidgets('on a phone, without a rail, they stay in the menu', (
    tester,
  ) async {
    await pumpApp(
      tester,
      FakeMatrixClientFactory(saved: [_session()]),
      size: _phone,
    );
    expect(find.byKey(const Key('rail.settings')), findsNothing);
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('About'), findsOneWidget);
  });

  group('copying', () {
    String? copied;

    setUp(() => copied = null);

    Future<void> openChat(WidgetTester tester) async {
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
      await pumpApp(
        tester,
        FakeMatrixClientFactory(saved: [_session()]),
        size: _wide,
      );
      await tester.tap(find.text('Team'));
      await tester.pumpAndSettle();
    }

    testWidgets('a right-click on a message copies all of it', (tester) async {
      await openChat(tester);
      await tester.tap(
        find.text('The server is at 10.10.33.177'),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy message'));
      await tester.pumpAndSettle();
      expect(copied, 'The server is at 10.10.33.177');
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('selected text is copied with Ctrl+C, without the time', (
      tester,
    ) async {
      await openChat(tester);
      final text = find.text('The server is at 10.10.33.177');
      final start = tester.getTopLeft(text) + const Offset(2, 8);
      final end = tester.getTopRight(text) + const Offset(-2, 8);
      final gesture = await tester.startGesture(
        start,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveTo(end);
      await gesture.up();
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(copied, isNotNull);
      expect('The server is at 10.10.33.177', contains(copied!.trim()));
      expect(copied!.length, greaterThan(20));
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('a long-press on a phone offers to copy the message', (
      tester,
    ) async {
      await openChat(tester);
      await tester.longPress(find.text('The server is at 10.10.33.177'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy message'));
      await tester.pumpAndSettle();
      expect(copied, 'The server is at 10.10.33.177');
    });
  });
}
