import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:oxitalk/src/app/router.dart';
import 'package:oxitalk/src/app/title_bar.dart';
import 'package:oxitalk/src/app/ui_prefs.dart';
import 'package:oxitalk/src/app/window_controls.dart';
import 'package:oxitalk/src/features/chats/chats_screen.dart';
import 'package:oxitalk/src/features/share/share_inbox.dart';
import 'package:oxitalk/src/matrix/api/matrix.dart';
import 'package:oxitalk/src/matrix/fakes/fakes.dart';

import 'support/app.dart';

const _me = '@me:acme.com';
const _other = '@me:globex.org';
const _wide = Size(1400, 900);
const _tablet = Size(800, 1000);
const _phone = Size(360, 740);

const _acme = Space(
  id: '!acme:acme.com',
  name: 'Acme',
  alias: '#acme:acme.com',
  roomIds: {'!eng:acme.com', '!design:acme.com'},
);
const _ops = Space(
  id: '!ops:acme.com',
  name: 'Ops',
  roomIds: {'!opschat:acme.com'},
);

List<Room> _rooms() => const [
  Room(
    id: '!eng:acme.com',
    name: 'Engineering',
    unreadCount: 2,
    unreadNotifications: 2,
  ),
  Room(id: '!design:acme.com', name: 'Design'),
  Room(
    id: '!opschat:acme.com',
    name: 'Ops chat',
    unreadCount: 3,
    unreadNotifications: 3,
  ),
  Room(id: '!dm:acme.com', name: 'Bob', isDm: true),
  // Joined spaces come with the room list; they are no chats.
  Room(id: '!acme:acme.com', name: 'Acme', isSpace: true),
  Room(id: '!ops:acme.com', name: 'Ops', isSpace: true),
];

FakeSession _session({
  String userId = _me,
  List<Room>? rooms,
  List<Space>? spaces = const [_acme, _ops],
}) => FakeSession(userId: userId, rooms: rooms ?? _rooms(), spaces: spaces);

/// The app with [session] (and [others]) at [size]; returns the prefs it keeps.
Future<MemoryUiPrefs> _open(
  WidgetTester tester, {
  FakeSession? session,
  List<FakeSession> others = const [],
  Size size = _wide,
  MemoryUiPrefs? ui,
  WindowControls? window,
  FakeShareSource? share,
}) async {
  final prefs = ui ?? MemoryUiPrefs();
  await pumpApp(
    tester,
    FakeMatrixClientFactory(
      saved: [session ?? _session(), ...others],
      active: (session ?? _session()).userId,
    ),
    size: size,
    ui: prefs,
    window: window,
    share: share,
  );
  return prefs;
}

/// A window whose title bar the app draws.
final class _DrawnWindow implements WindowControls {
  @override
  bool get drawsTitleBar => true;

  @override
  List<WindowButton> get leftButtons => const [];

  @override
  List<WindowButton> get rightButtons => const [WindowButton.close];

  @override
  Future<void> startDragging() async {}

  @override
  Future<void> doubleClick() async {}

  @override
  Future<void> showMenu() async {}

  @override
  Future<void> press(WindowButton button) async {}
}

final _selector = find.byKey(const Key('spaces.selector'));

/// The chat list's rows, by name.
Finder _chat(String name) =>
    find.descendant(of: find.byType(ChatListPane), matching: find.text(name));

void _expectAllChats() {
  for (final name in ['Engineering', 'Design', 'Ops chat', 'Bob']) {
    expect(_chat(name), findsOneWidget, reason: name);
  }
}

void _expectAcmeOnly() {
  expect(_chat('Engineering'), findsOneWidget);
  expect(_chat('Design'), findsOneWidget);
  expect(_chat('Ops chat'), findsNothing);
  expect(_chat('Bob'), findsNothing);
}

Future<void> _go(WidgetTester tester, String location) async {
  GoRouter.of(tester.element(find.byType(ChatListPane).first)).go(location);
  await tester.pumpAndSettle();
}

void main() {
  group('rail visible (desktop)', () {
    testWidgets('under the accounts a line, All chats and the spaces; a space filters the list and '
        'is marked as the active account is', (tester) async {
      await _open(tester);
      expect(find.byKey(const Key('rail.spaces.separator')), findsOneWidget);
      expect(find.byKey(const Key('rail.space.all')), findsOneWidget);
      expect(find.byKey(Key('rail.space.${_acme.id}')), findsOneWidget);
      expect(find.byKey(Key('rail.space.${_ops.id}')), findsOneWidget);
      // The separator sits under Add account, the spaces under it.
      expect(
        tester.getTopLeft(find.byKey(const Key('rail.spaces.separator'))).dy,
        greaterThanOrEqualTo(
          tester.getBottomLeft(find.byKey(const Key('account.add'))).dy,
        ),
      );
      // Joined spaces aren't chats; the rail does the job, no selector row.
      _expectAllChats();
      expect(_selector, findsNothing);
      expect(find.byKey(const Key('rail.space.selected.all')), findsOneWidget);

      await tester.tap(find.byKey(Key('rail.space.${_acme.id}')));
      await tester.pumpAndSettle();
      _expectAcmeOnly();
      expect(
        find.byKey(Key('rail.space.selected.${_acme.id}')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('rail.space.selected.all')), findsNothing);
      // The end of the space's list offers its rooms.
      expect(find.byKey(const Key('spaces.browse')), findsOneWidget);

      await tester.tap(find.byKey(const Key('rail.space.all')));
      await tester.pumpAndSettle();
      _expectAllChats();
    });

    testWidgets('each space has its unread badge and a label that says it', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _open(tester);
      expect(
        find.byKey(Key('spaceBadge.notifying.${_ops.id}')),
        findsOneWidget,
      );
      expect(
        find.byKey(Key('spaceBadge.notifying.${_acme.id}')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Space Ops, 3 unread'), findsOneWidget);
      expect(find.bySemanticsLabel('Space Acme, 2 unread'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('an account without spaces has no line and no spaces', (
      tester,
    ) async {
      await _open(tester, session: _session(spaces: const []));
      expect(find.byKey(const Key('rail.spaces')), findsNothing);
      expect(find.byKey(const Key('rail.spaces.separator')), findsNothing);
      _expectAllChats();
    });

    testWidgets('rail visible and the list narrowed: nothing extra', (
      tester,
    ) async {
      await _open(tester, ui: MemoryUiPrefs(narrowList: true));
      expect(find.byKey(Key('rail.space.${_acme.id}')), findsOneWidget);
      expect(_selector, findsNothing);
      await tester.tap(find.byKey(const Key('account.dropdown')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('accountMenu.spaces')), findsNothing);
    });
  });

  group('rail hidden, list wide', () {
    for (final size in [_wide, _tablet]) {
      testWidgets(
        'at ${size.width.toInt()}x${size.height.toInt()} a selector row above the '
        'filter picks the space from a menu',
        (tester) async {
          await _open(tester, size: size, ui: MemoryUiPrefs(railHidden: true));
          expect(find.byKey(const Key('rail.spaces')), findsNothing);
          expect(_selector, findsOneWidget);
          expect(
            tester.getBottomLeft(_selector).dy,
            lessThanOrEqualTo(
              tester.getTopLeft(find.byKey(const Key('list.filter'))).dy,
            ),
          );
          expect(
            tester
                .widget<Text>(find.byKey(const Key('spaces.selector.name')))
                .data,
            'All chats',
          );
          // Nothing elsewhere: All chats shows everything.
          expect(find.byKey(const Key('spaces.selector.dot')), findsNothing);
        },
        variant: desktop,
      );
    }

    testWidgets(
      'picking a space filters the list; a red dot tells of unread chats outside it',
      (tester) async {
        await _open(tester, ui: MemoryUiPrefs(railHidden: true));
        await tester.tap(_selector);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('spaceMenu.all')), findsOneWidget);
        expect(find.byKey(const Key('spaceChoice.check.all')), findsOneWidget);
        await tester.tap(find.byKey(Key('spaceMenu.${_acme.id}')));
        await tester.pumpAndSettle();
        _expectAcmeOnly();
        expect(
          tester
              .widget<Text>(find.byKey(const Key('spaces.selector.name')))
              .data,
          'Acme',
        );
        // Ops chat has 3 unread, outside Acme.
        expect(find.byKey(const Key('spaces.selector.dot')), findsOneWidget);

        await tester.tap(_selector);
        await tester.pumpAndSettle();
        expect(
          find.byKey(Key('spaceChoice.check.${_acme.id}')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('spaceMenu.all')));
        await tester.pumpAndSettle();
        _expectAllChats();
        expect(find.byKey(const Key('spaces.selector.dot')), findsNothing);
      },
      variant: desktop,
    );

    testWidgets('no selector row for an account without spaces', (
      tester,
    ) async {
      await _open(
        tester,
        session: _session(spaces: const []),
        ui: MemoryUiPrefs(railHidden: true),
      );
      expect(_selector, findsNothing);
      expect(find.byKey(const Key('list.filter')), findsOneWidget);
    });
  });

  group('rail hidden and the list narrowed', () {
    testWidgets(
      'the account menu has a Spaces block; the header shows the space on the picture',
      (tester) async {
        await _open(
          tester,
          ui: MemoryUiPrefs(railHidden: true, narrowList: true),
        );
        expect(_selector, findsNothing);
        expect(find.byKey(const Key('account.dropdown.space')), findsNothing);
        await tester.tap(find.byKey(const Key('account.dropdown')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('accountMenu.spaces')), findsOneWidget);
        expect(find.byKey(const Key('accountMenu.space.all')), findsOneWidget);
        expect(
          find.byKey(const Key('accountMenu.space.check.all')),
          findsOneWidget,
        );
        // Between the accounts and Add account.
        final block = tester
            .getTopLeft(find.byKey(const Key('accountMenu.spaces')))
            .dy;
        expect(
          block,
          greaterThan(
            tester.getTopLeft(find.byKey(const Key('accountMenu.$_me'))).dy,
          ),
        );
        expect(
          block,
          lessThan(
            tester.getTopLeft(find.byKey(const Key('accountMenu.add'))).dy,
          ),
        );
        await tester.tap(find.byKey(Key('accountMenu.space.${_ops.id}')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('account.dropdown.space')), findsOneWidget);
        expect(find.byTooltip('Ops chat'), findsOneWidget);
        expect(find.byTooltip('Engineering'), findsNothing);
      },
      variant: desktop,
    );
  });

  group('phone', () {
    testWidgets('at 360x740 the selector opens the bottom sheet; a long-press on a space in it '
        'opens the space\'s actions', (tester) async {
      await _open(tester, size: _phone);
      expect(_selector, findsOneWidget);
      await tester.tap(_selector);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('spaceSheet')), findsOneWidget);
      await tester.tap(find.byKey(Key('spaceSheet.${_acme.id}')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('spaceSheet')), findsNothing);
      _expectAcmeOnly();
      expect(tester.takeException(), isNull);

      await tester.tap(_selector);
      await tester.pumpAndSettle();
      await tester.longPress(find.byKey(Key('spaceSheet.${_ops.id}')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('spaceContextSheet')), findsOneWidget);
      expect(find.byKey(const Key('spaceContext.browse')), findsOneWidget);
      expect(find.byKey(const Key('spaceContext.copy')), findsOneWidget);
      expect(find.byKey(const Key('spaceContext.leave')), findsOneWidget);
    });
  });

  group('selection', () {
    testWidgets('is kept per account, across starts', (tester) async {
      final prefs = await _open(
        tester,
        others: [
          _session(
            userId: _other,
            rooms: const [Room(id: '!g:globex.org', name: 'Globex board')],
            spaces: const [
              Space(
                id: '!gs:globex.org',
                name: 'Globex',
                roomIds: {'!g:globex.org'},
              ),
            ],
          ),
        ],
        ui: MemoryUiPrefs(selectedSpaces: {_me: _acme.id}),
      );
      // Started in the space kept last time.
      _expectAcmeOnly();
      await tester.tap(find.byKey(Key('rail.space.${_ops.id}')));
      await tester.pumpAndSettle();
      expect(prefs.selectedSpaces, {_me: _ops.id});

      // The other account has its own: none yet.
      await tester.tap(find.byKey(const Key('account.$_other')));
      await tester.pumpAndSettle();
      expect(_chat('Globex board'), findsOneWidget);
      expect(find.byKey(const Key('rail.space.selected.all')), findsOneWidget);
      await tester.tap(find.byKey(const Key('rail.space.!gs:globex.org')));
      await tester.pumpAndSettle();
      expect(prefs.selectedSpaces, {_me: _ops.id, _other: '!gs:globex.org'});

      await tester.tap(find.byKey(const Key('account.$_me')));
      await tester.pumpAndSettle();
      expect(_chat('Ops chat'), findsOneWidget);
      expect(_chat('Engineering'), findsNothing);
    });

    testWidgets('falls back to All chats when the space goes', (tester) async {
      final session = _session();
      final prefs = await _open(
        tester,
        session: session,
        ui: MemoryUiPrefs(selectedSpaces: {_me: _acme.id}),
      );
      _expectAcmeOnly();
      // Left in another client, or removed.
      session.spaceState.value = const [_ops];
      await tester.pumpAndSettle();
      _expectAllChats();
      expect(prefs.selectedSpaces, isEmpty);
      expect(find.byKey(const Key('rail.space.selected.all')), findsOneWidget);
    });

    testWidgets('a space left while the app was closed starts in All chats', (
      tester,
    ) async {
      final prefs = await _open(
        tester,
        ui: MemoryUiPrefs(selectedSpaces: {_me: '!gone:acme.com'}),
      );
      _expectAllChats();
      expect(prefs.selectedSpaces, isEmpty);
    });

    testWidgets(
      'opening a chat outside the space (a link, a notification) switches to All chats',
      (tester) async {
        final prefs = await _open(
          tester,
          ui: MemoryUiPrefs(selectedSpaces: {_me: _acme.id}),
        );
        _expectAcmeOnly();
        // A chat inside it keeps the space.
        await _go(tester, Routes.room('!eng:acme.com'));
        _expectAcmeOnly();
        await _go(tester, Routes.room('!dm:acme.com'));
        _expectAllChats();
        expect(prefs.selectedSpaces, isEmpty);
        // The open chat shows, highlighted.
        expect(
          tester
              .widget<RoomTile>(
                find.ancestor(
                  of: _chat('Bob'),
                  matching: find.byType(RoomTile),
                ),
              )
              .selected,
          isTrue,
        );
      },
    );

    testWidgets('the chat open at the start, outside the space, wins', (
      tester,
    ) async {
      await _open(
        tester,
        ui: MemoryUiPrefs(
          selectedSpaces: {_me: _acme.id},
          lastRooms: {_me: '!opschat:acme.com'},
        ),
      );
      _expectAllChats();
    });

    testWidgets('Ctrl+Alt+↓/↑ go to the next and previous space', (
      tester,
    ) async {
      final prefs = await _open(tester);
      Future<void> press(LogicalKeyboardKey key) async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
        await tester.sendKeyEvent(key);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
      }

      await press(LogicalKeyboardKey.arrowDown);
      expect(prefs.selectedSpaces[_me], _acme.id);
      await press(LogicalKeyboardKey.arrowDown);
      expect(prefs.selectedSpaces[_me], _ops.id);
      await press(LogicalKeyboardKey.arrowDown);
      expect(prefs.selectedSpaces[_me], isNull);
      await press(LogicalKeyboardKey.arrowUp);
      expect(prefs.selectedSpaces[_me], _ops.id);
    }, variant: desktop);
  });

  group('filter', () {
    testWidgets(
      'searches inside the space; a row tells of the matches in All chats and goes there',
      (tester) async {
        await _open(tester, ui: MemoryUiPrefs(selectedSpaces: {_me: _acme.id}));
        await tester.enterText(find.byKey(const Key('list.filter')), 'o');
        await tester.pumpAndSettle();
        // "Ops chat" and "Bob" match, both outside Acme.
        expect(find.byKey(const Key('list.filter.empty')), findsOneWidget);
        expect(find.text('2 more in All chats'), findsOneWidget);
        await tester.tap(find.byKey(const Key('spaces.moreInAll')));
        await tester.pumpAndSettle();
        expect(_chat('Ops chat'), findsOneWidget);
        expect(_chat('Bob'), findsOneWidget);
        expect(_chat('Engineering'), findsNothing);
        expect(find.byKey(const Key('spaces.moreInAll')), findsNothing);

        // Matches in the space too (Design), and the row for the rest (Ops chat).
        await tester.tap(find.byKey(Key('rail.space.${_acme.id}')));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('list.filter')), 's');
        await tester.pumpAndSettle();
        expect(_chat('Engineering'), findsNothing);
        expect(_chat('Design'), findsOneWidget);
        expect(find.text('1 more in All chats'), findsOneWidget);
      },
    );

    testWidgets(
      'Send to… lists every chat whatever the space; the chat picked shows in All chats',
      (tester) async {
        final share = FakeShareSource()
          ..sharedBeforeStart(const SharedItems(text: 'https://oxitalk.com'));
        await _open(
          tester,
          share: share,
          ui: MemoryUiPrefs(selectedSpaces: {_me: _acme.id}),
        );
        expect(find.byKey(const Key('share')), findsOneWidget);
        for (final id in [
          '!eng:acme.com',
          '!design:acme.com',
          '!opschat:acme.com',
          '!dm:acme.com',
        ]) {
          expect(find.byKey(Key('share.room.$id')), findsOneWidget, reason: id);
        }
        expect(find.byKey(Key('share.room.${_acme.id}')), findsNothing);
        await tester.tap(find.byKey(const Key('share.room.!dm:acme.com')));
        await tester.pumpAndSettle();
        _expectAllChats();
      },
    );
  });

  group('invitations', () {
    testWidgets('an invitation to a space shows among the invites, labelled; accepting it puts the '
        'space in the rail and shows it', (tester) async {
      final session = _session(
        rooms: [
          ..._rooms(),
          const Room(
            id: '!globex:globex.org',
            name: 'Globex HQ',
            membership: Membership.invited,
            isSpace: true,
          ),
        ],
      );
      await _open(tester, session: session);
      expect(_chat('Globex HQ'), findsOneWidget);
      expect(
        find.byKey(const Key('spaceLabel.!globex:globex.org')),
        findsOneWidget,
      );
      expect(find.text('Space invitation — tap to see it'), findsOneWidget);
      // A joined space is never a chat.
      expect(_chat('Acme'), findsNothing);

      await tester.tap(_chat('Globex HQ'));
      await tester.pumpAndSettle();
      expect(find.text('Space invitation'), findsOneWidget);
      await tester.tap(find.byKey(const Key('invite.accept')));
      await tester.pumpAndSettle();
      // The sync brings the space.
      session.spaceState.value = [
        _acme,
        _ops,
        const Space(id: '!globex:globex.org', name: 'Globex HQ'),
      ];
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('rail.space.selected.!globex:globex.org')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('spaces.empty')), findsOneWidget);
      expect(find.byKey(const Key('spaces.browse')), findsOneWidget);
    });
  });

  group('space actions', () {
    testWidgets(
      'leaving asks which rooms to leave with it, and leaves just those',
      (tester) async {
        final session = _session()
          ..leaveSpacePreviews[_acme.id] = const [
            SpaceLeaveRoom(id: '!eng:acme.com', name: 'Engineering'),
            SpaceLeaveRoom(
              id: '!design:acme.com',
              name: 'Design',
              lastAdmin: true,
            ),
          ];
        await _open(
          tester,
          session: session,
          ui: MemoryUiPrefs(selectedSpaces: {_me: _acme.id}),
        );
        await tester.tap(
          find.byKey(Key('rail.space.${_acme.id}')),
          buttons: kSecondaryButton,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('spaceContext.leave')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('leaveSpace.dialog')), findsOneWidget);
        expect(
          find.byKey(const Key('leaveSpace.lastAdmin.!design:acme.com')),
          findsOneWidget,
        );
        await tester.tap(
          find.byKey(const Key('leaveSpace.room.!eng:acme.com')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Leave 2'), findsOneWidget);
        await tester.tap(find.byKey(const Key('leaveSpace.confirm')));
        await tester.pumpAndSettle();
        expect(session.leftSpaces.single.$1, _acme.id);
        expect(session.leftSpaces.single.$2, ['!eng:acme.com']);
        expect(find.byKey(Key('rail.space.${_acme.id}')), findsNothing);
        expect(_chat('Engineering'), findsNothing);
        expect(_chat('Design'), findsOneWidget);
        expect(
          find.byKey(const Key('rail.space.selected.all')),
          findsOneWidget,
        );
      },
      variant: desktop,
    );

    testWidgets('cancelling the leave dialog leaves nothing', (tester) async {
      final session = _session();
      await _open(tester, session: session);
      await tester.tap(
        find.byKey(Key('rail.space.${_ops.id}')),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('spaceContext.leave')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('leaveSpace.cancel')));
      await tester.pumpAndSettle();
      expect(session.leftSpaces, isEmpty);
      expect(find.byKey(Key('rail.space.${_ops.id}')), findsOneWidget);
    }, variant: desktop);

    testWidgets('Copy link copies the space\'s address', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await _open(tester);
      await tester.tap(
        find.byKey(Key('rail.space.${_acme.id}')),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('spaceContext.copy')));
      await tester.pumpAndSettle();
      expect(copied, 'https://matrix.to/#/#acme:acme.com');
    }, variant: desktop);

    testWidgets('browsing lists the space\'s rooms, the joined ones marked; Join joins through '
        'the space\'s servers', (tester) async {
      const lobby = SpaceChild(
        id: '!lobby:other.org',
        name: 'Lobby',
        topic: 'Say hi',
        joinedMembers: 12,
        via: ['other.org', 'acme.com'],
      );
      final session = _session()
        ..spaceChildrenById[_acme.id] = const [
          SpaceChild(
            id: '!eng:acme.com',
            name: 'Engineering',
            joined: true,
            joinedMembers: 4,
          ),
          lobby,
          SpaceChild(id: '!sub:acme.com', name: 'Sub', isSpace: true),
        ]
        ..addresses[lobby.joinAddress] = const Room(
          id: '!lobby:other.org',
          name: 'Lobby',
        );
      expect(
        lobby.joinAddress,
        'https://matrix.to/#/!lobby:other.org?via=other.org&via=acme.com',
      );
      await _open(
        tester,
        session: session,
        ui: MemoryUiPrefs(selectedSpaces: {_me: _acme.id}),
      );
      await tester.tap(find.byKey(const Key('spaces.browse')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('browse.dialog')), findsOneWidget);
      expect(find.text('Rooms in Acme'), findsOneWidget);
      expect(
        find.byKey(const Key('browse.joined.!eng:acme.com')),
        findsOneWidget,
      );
      expect(find.text('12 members · Say hi'), findsOneWidget);
      expect(find.text('Space'), findsOneWidget);
      await tester.tap(find.byKey(const Key('browse.join.!lobby:other.org')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('browse.joined.!lobby:other.org')),
        findsOneWidget,
      );
      expect(session.roomList.any((room) => room.id == lobby.id), isTrue);

      // A joined room opens from there.
      await tester.tap(find.byKey(const Key('browse.child.!eng:acme.com')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('browse.dialog')), findsNothing);
      expect(
        GoRouter.of(tester.element(find.byType(ChatListPane).first))
            .state
            .uri
            .path,
        Routes.room('!eng:acme.com'),
      );
    });
  });

  group('title bar', () {
    testWidgets(
      'reads OxiTalk › account › space › chat with a space; no space for All chats',
      (tester) async {
        await _open(
          tester,
          window: _DrawnWindow(),
          ui: MemoryUiPrefs(selectedSpaces: {_me: _acme.id}),
        );
        await _go(tester, Routes.room('!eng:acme.com'));
        final space = find.byKey(const Key('titleBar.space'));
        expect(tester.widget<Text>(space).data, 'Acme');
        final x = [
          'titleBar.app',
          'titleBar.account',
          'titleBar.space',
          'titleBar.room',
        ].map((key) => tester.getCenter(find.byKey(Key(key))).dx).toList();
        expect(x, orderedEquals([...x]..sort()));
        expect(
          tester.widget<Text>(find.byKey(const Key('titleBar.room'))).data,
          'Engineering',
        );

        await tester.tap(find.byKey(const Key('rail.space.all')));
        await tester.pumpAndSettle();
        expect(space, findsNothing);
        expect(find.byKey(const Key('titleBar.account')), findsOneWidget);
        expect(find.byKey(const Key('titleBar.room')), findsOneWidget);
      },
    );

    testWidgets('a tight bar shortens the space first, without overflowing', (
      tester,
    ) async {
      final session = _session(
        spaces: const [
          Space(
            id: '!acme:acme.com',
            name: 'A space with a very very long name indeed, really',
            roomIds: {'!eng:acme.com'},
          ),
        ],
      );
      await _open(
        tester,
        session: session,
        size: const Size(900, 700),
        window: _DrawnWindow(),
        ui: MemoryUiPrefs(selectedSpaces: {_me: _acme.id}),
      );
      await _go(tester, Routes.room('!eng:acme.com'));
      expect(tester.takeException(), isNull);
      final space = tester.getSize(find.byKey(const Key('titleBar.space')));
      final account = tester.getSize(find.byKey(const Key('titleBar.account')));
      final room = tester.getSize(find.byKey(const Key('titleBar.room')));
      // The account and the chat whole, the space cut short.
      expect(account.width, greaterThan(80));
      expect(room.width, greaterThan(60));
      expect(space.width, lessThan(330));
    });

    test('names fit: the space gives way first, then the others share', () {
      final roomy = TitleWidths.fit(
        available: 600,
        account: 150,
        space: 100,
        room: 120,
      );
      expect((roomy.account, roomy.space, roomy.room), (150, 100, 120));
      final tight = TitleWidths.fit(
        available: 330,
        account: 150,
        space: 100,
        room: 120,
      );
      expect((tight.account, tight.space, tight.room), (150, 60, 120));
      final tighter = TitleWidths.fit(
        available: 200,
        account: 150,
        space: 100,
        room: 120,
      );
      expect(tighter.space, TitleWidths.spaceMin);
      expect(tighter.account + tighter.space + tighter.room, 200);
      expect(tighter.account, 76);
      expect(tighter.room, 76);
    });
  });

  testWidgets('2 000 chats, half of them in a space, filter at once', (
    tester,
  ) async {
    final rooms = [
      for (var i = 0; i < 2000; i++)
        Room(id: '!r$i:acme.com', name: 'Room $i', unreadCount: i % 3),
    ];
    final big = Space(
      id: '!big:acme.com',
      name: 'Big',
      roomIds: {for (var i = 0; i < 2000; i += 2) '!r$i:acme.com'},
    );
    await _open(
      tester,
      session: _session(rooms: rooms, spaces: [big]),
    );
    final watch = Stopwatch()..start();
    await tester.tap(find.byKey(const Key('rail.space.!big:acme.com')));
    await tester.pumpAndSettle();
    watch.stop();
    expect(_chat('Room 0'), findsOneWidget);
    expect(_chat('Room 1'), findsNothing);
    // ignore: avoid_print
    print(
      'selecting a space of 1000 among 2000 chats: ${watch.elapsedMilliseconds} ms',
    );
  });
}
