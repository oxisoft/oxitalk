import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oxitalk/src/app/ui_prefs.dart';
import 'package:oxitalk/src/app/window_controls.dart';
import 'package:oxitalk/src/features/accounts/account_switcher.dart';
import 'package:oxitalk/src/features/chat_info/chat_info.dart';
import 'package:oxitalk/src/features/chats/chats_screen.dart';
import 'package:oxitalk/src/matrix/api/matrix.dart';
import 'package:oxitalk/src/matrix/fakes/fakes.dart';

import 'support/app.dart';
import 'support/rust_core.dart';

const _wide = Size(1200, 800);
const _me = '@me:acme.com';

/// A window whose title bar the app draws, laid out as asked; remembers what it was asked.
final class _FakeWindow implements WindowControls {
  _FakeWindow({
    this.leftButtons = const [],
    this.rightButtons = const [WindowButton.close],
  });

  final calls = <String>[];

  @override
  bool get drawsTitleBar => true;

  @override
  final List<WindowButton> leftButtons;

  @override
  final List<WindowButton> rightButtons;

  @override
  Future<void> startDragging() async => calls.add('drag');

  @override
  Future<void> doubleClick() async => calls.add('doubleClick');

  @override
  Future<void> showMenu() async => calls.add('menu');

  @override
  Future<void> press(WindowButton button) async => calls.add(button.name);
}

FakeSession _session() =>
    FakeSession(
        userId: _me,
        profile: const Profile(displayName: 'Bob K'),
        rooms: const [
          Room(id: '!team', name: 'Team'),
          Room(
            id: '!news',
            name: 'News',
            unreadCount: 3,
            unreadNotifications: 3,
          ),
        ],
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

Future<void> _open(
  WidgetTester tester, {
  Size size = _wide,
  WindowControls? window,
  MemoryUiPrefs? ui,
  FakeSession? session,
}) => pumpApp(
  tester,
  FakeMatrixClientFactory(saved: [session ?? _session()]),
  size: size,
  window: window,
  ui: ui,
);

void main() {
  // About shows the core's version.
  setUpAll(initRustCore);

  group('title bar', () {
    testWidgets('only the buttons GNOME is set to show, where it shows them', (
      tester,
    ) async {
      final window = _FakeWindow();
      await _open(tester, window: window);
      final close = find.descendant(
        of: find.byKey(const Key('titleBar')),
        matching: find.byKey(const Key('window.close')),
      );
      expect(close, findsOneWidget);
      expect(find.byKey(const Key('window.minimize')), findsNothing);
      await tester.tap(close);
      expect(window.calls, ['close']);
    });

    testWidgets('buttons on the left go to the left of the app name', (
      tester,
    ) async {
      final window = _FakeWindow(
        leftButtons: const [WindowButton.close, WindowButton.minimize],
        rightButtons: const [],
      );
      await _open(tester, window: window);
      final close = tester.getCenter(find.byKey(const Key('window.close')));
      final app = tester.getCenter(find.byKey(const Key('titleBar.app')));
      expect(close.dx, lessThan(app.dx));
      expect(find.byKey(const Key('window.maximize')), findsNothing);
    });

    testWidgets('a bar of its own above every pane, with the app name and '
        'the open chat', (tester) async {
      await _open(tester, window: _FakeWindow());
      expect(find.byKey(const Key('titleBar.app')), findsOneWidget);
      expect(find.byKey(const Key('titleBar.room')), findsNothing);

      await tester.tap(find.text('Team'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('titleBar.room'))).data,
        'Team',
      );
      final bar = tester.getRect(find.byKey(const Key('titleBar')));
      expect(bar.width, _wide.width);
      expect(
        tester.getTopLeft(find.byKey(const Key('chat.title'))).dy,
        greaterThanOrEqualTo(bar.bottom),
      );

      // A thread beside the chat leaves the window buttons where they are.
      await tester.tap(find.byKey(const Key('chat.threads')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('window.close')), findsOneWidget);
      expect(
        tester.getCenter(find.byKey(const Key('window.close'))).dy,
        lessThan(bar.bottom),
      );

      await tester.tap(find.text('News'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('titleBar.room'))).data,
        'News',
      );
    });

    testWidgets('the name, the chat and the buttons sit in the middle of '
        'the bar', (tester) async {
      await _open(tester, window: _FakeWindow());
      await tester.tap(find.text('Team'));
      await tester.pumpAndSettle();
      final middle = tester.getCenter(find.byKey(const Key('titleBar'))).dy;
      for (final key in ['titleBar.app', 'titleBar.room', 'window.close']) {
        expect(
          tester.getCenter(find.byKey(Key(key))).dy,
          moreOrLessEquals(middle, epsilon: 1),
          reason: key,
        );
      }
    });

    testWidgets('the title bar drags, double-clicks and right-clicks as '
        'the desktop does; the chat title stays a button', (tester) async {
      final window = _FakeWindow();
      await _open(tester, window: window);
      await tester.tap(find.text('Team'));
      await tester.pumpAndSettle();

      final empty =
          tester.getTopLeft(find.byKey(const Key('titleBar'))) +
          const Offset(200, 19);
      await tester.dragFrom(empty, const Offset(60, 10));
      await tester.pumpAndSettle();
      await tester.tapAt(empty);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(empty);
      await tester.pumpAndSettle();
      await tester.tapAt(empty, buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(window.calls, ['drag', 'doubleClick', 'menu']);

      await tester.tap(find.byKey(const Key('chat.title')));
      await tester.pumpAndSettle();
      expect(find.byType(ChatInfoPane), findsOneWidget);
    });

    testWidgets('without its own title bar the app draws none', (tester) async {
      await _open(tester);
      expect(find.byKey(const Key('titleBar')), findsNothing);
      expect(find.byKey(const Key('window.close')), findsNothing);
    });

    test('GNOME’s button layout and double-click setting are read', () {
      final layout = parseButtonLayout('appmenu:close');
      expect(layout.left, isEmpty);
      expect(layout.right, [WindowButton.close]);
      final mac = parseButtonLayout('close,minimize,maximize:');
      expect(mac.left, [
        WindowButton.close,
        WindowButton.minimize,
        WindowButton.maximize,
      ]);
      expect(mac.right, isEmpty);
      expect(parseButtonLayout(':minimize,spacer,maximize,close').right, [
        WindowButton.minimize,
        WindowButton.maximize,
        WindowButton.close,
      ]);
      expect(
        parseDoubleClick('toggle-maximize'),
        TitleBarDoubleClick.toggleMaximize,
      );
      expect(parseDoubleClick('minimize'), TitleBarDoubleClick.minimize);
      expect(parseDoubleClick('menu'), TitleBarDoubleClick.menu);
      expect(parseDoubleClick('none'), TitleBarDoubleClick.none);
      expect(parseDoubleClick(null), TitleBarDoubleClick.toggleMaximize);
    });
  });

  group('where it left off', () {
    testWidgets('the chat open last time opens again', (tester) async {
      await _open(tester, ui: MemoryUiPrefs(lastRooms: {_me: '!team'}));
      expect(find.text('The server is at 10.10.33.177'), findsOneWidget);
    });

    testWidgets('opening a chat is remembered', (tester) async {
      final ui = MemoryUiPrefs();
      await _open(tester, ui: ui);
      await tester.tap(find.text('News'));
      await tester.pumpAndSettle();
      expect(ui.lastRooms, {_me: '!news'});

      // Settings and back return to it.
      await tester.tap(find.byKey(const Key('rail.settings')));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('composer.text')), findsOneWidget);
      expect(ui.lastRooms, {_me: '!news'});
    });

    testWidgets('a chat that is gone gives the welcome instead', (
      tester,
    ) async {
      await _open(tester, ui: MemoryUiPrefs(lastRooms: {_me: '!left'}));
      expect(find.byKey(const Key('welcome')), findsOneWidget);
      expect(find.textContaining(', Bob K'), findsOneWidget);
      expect(find.byKey(const Key('welcome.line')), findsOneWidget);
    });

    test('the greeting follows the time of day', () {
      expect(greeting(3), 'Good night');
      expect(greeting(9), 'Good morning');
      expect(greeting(14), 'Good afternoon');
      expect(greeting(20), 'Good evening');
      expect(greeting(23), 'Good night');
    });
  });

  group('list and rail', () {
    testWidgets('the list narrows to pictures and short names, and back', (
      tester,
    ) async {
      final ui = MemoryUiPrefs();
      await _open(tester, ui: ui);
      final listWidth = tester.getSize(find.byType(ChatListPane)).width;

      await tester.tap(find.byKey(const Key('list.narrow')));
      await tester.pumpAndSettle();
      expect(ui.narrowList, isTrue);
      expect(
        tester.getSize(find.byType(ChatListPane)).width,
        lessThan(listWidth / 3),
      );
      // The unread count shows on the picture.
      expect(
        find.descendant(
          of: find.byType(ChatListPane),
          matching: find.text('3'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Team'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('composer.text')), findsOneWidget);

      await tester.tap(find.byKey(const Key('list.widen')));
      await tester.pumpAndSettle();
      expect(ui.narrowList, isFalse);
      expect(tester.getSize(find.byType(ChatListPane)).width, listWidth);
    });

    testWidgets('a narrowed list stays narrow after a restart', (tester) async {
      await _open(tester, ui: MemoryUiPrefs(narrowList: true));
      expect(find.byKey(const Key('list.widen')), findsOneWidget);
    });

    testWidgets('the rail hides and comes back; hidden, the account menu '
        'has Settings and About', (tester) async {
      final ui = MemoryUiPrefs();
      await _open(tester, ui: ui);
      await tester.tap(find.byKey(const Key('rail.hide')));
      await tester.pumpAndSettle();
      expect(ui.railHidden, isTrue);
      expect(find.byType(AccountRail), findsNothing);

      await pickFromAccountMenu(tester, 'accountMenu.about');
      expect(find.textContaining('Rust core'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('rail.show')));
      await tester.pumpAndSettle();
      expect(ui.railHidden, isFalse);
      expect(find.byType(AccountRail), findsOneWidget);
    });

    testWidgets('with the rail shown, the account menu has no Settings', (
      tester,
    ) async {
      await _open(tester);
      await tester.tap(find.byKey(const Key('account.dropdown')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('accountMenu.settings')), findsNothing);
      expect(find.byKey(const Key('accountMenu.logout')), findsOneWidget);
    });

    testWidgets('Settings and About are at the bottom of the rail', (
      tester,
    ) async {
      await _open(tester);
      await tester.tap(find.byKey(const Key('rail.about')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Rust core'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('rail.settings')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Collect logs'), 200);
      expect(find.text('Collect logs'), findsOneWidget);
    });
  });

  group('log out', () {
    testWidgets('from Settings', (tester) async {
      final session = _session();
      await _open(tester, session: session);
      await tester.tap(find.byKey(const Key('rail.settings')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings.logout')));
      await tester.pumpAndSettle();
      expect(session.loggedOut, isTrue);
      expect(find.text('Sign in'), findsOneWidget);
    });

    testWidgets('from a right-click on the account in the rail', (
      tester,
    ) async {
      final session = _session();
      await _open(tester, session: session);
      await tester.tap(
        find.byKey(const Key('account.$_me')),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('railMenu.logout')));
      await tester.pumpAndSettle();
      expect(session.loggedOut, isTrue);
    });
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
