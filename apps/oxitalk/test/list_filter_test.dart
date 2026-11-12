// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oxitalk/src/app/collapsed_sections.dart';
import 'package:oxitalk/src/app/ui_prefs.dart';
import 'package:oxitalk/src/features/chat/chat_pane.dart';
import 'package:oxitalk/src/features/chats/chats_screen.dart';
import 'package:oxitalk/src/features/chats/list_filter.dart';
import 'package:oxitalk/src/features/chats/room_groups.dart';
import 'package:oxitalk/src/matrix/api/matrix.dart';
import 'package:oxitalk/src/matrix/fakes/fakes.dart';

import 'support/app.dart';

const _wide = Size(1200, 800);
const _me = '@me:acme.com';
const _other = '@me:globex.org';
const _acme = '${SectionTags.customPrefix}acme';

const _sections = Sections(
  custom: [CustomSection(_acme, 'Acme')],
  order: [_acme, SectionTags.people, SectionTags.rooms],
  roomTags: {
    '!team:acme.com': [SectionTags.favourites],
    '!news:acme.com': [_acme],
  },
);

FakeSession _session() =>
    FakeSession(
        userId: _me,
        sections: _sections,
        rooms: const [
          Room(id: '!bob:acme.com', name: 'Robert', isDm: true),
          Room(id: '!zoe:acme.com', name: 'Zoë Ågren', isDm: true),
          Room(id: '!team:acme.com', name: 'Team'),
          Room(id: '!news:acme.com', name: 'News'),
          Room(id: '!lobby:acme.com', name: 'Lobby'),
        ],
      )
      ..known = const [Person('@bob:acme.com', displayName: 'Bobby')]
      ..dms['@bob:acme.com'] = '!bob:acme.com';

/// The chats the list shows, top to bottom.
List<String> _shown(WidgetTester tester) => [
  for (final tile in tester.widgetList<RoomTile>(find.byType(RoomTile)))
    tile.room.name,
];

/// The section headers, top to bottom.
List<String> _headers(WidgetTester tester) => [
  for (final header in tester.widgetList<SectionHeader>(
    find.byType(SectionHeader),
  ))
    header.group.tag,
];

Finder get _field => find.byKey(const Key('list.filter'));

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(_field, text);
  await tester.pumpAndSettle();
}

Future<void> _ctrlK(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

bool _focused(WidgetTester tester) =>
    tester.widget<TextField>(_field).focusNode!.hasFocus;

void main() {
  group('matching', () {
    test('ignores case and accents', () {
      expect(foldForSearch('Zoë ÅGREN Łódź straße'), 'zoe agren lodz strasse');
      expect(foldForSearch('Zoe\u0301'), 'zoe');
      expect(foldForSearch('Алёна'), 'алена');
    });

    test('every word must be in the name, the ID or the person', () {
      const room = Room(id: '!x:acme.com', name: 'Zoë Ågren', isDm: true);
      expect(roomMatches(room, ''), isTrue);
      expect(roomMatches(room, '  '), isTrue);
      expect(roomMatches(room, 'ZOE'), isTrue);
      expect(roomMatches(room, 'agr zo'), isTrue);
      expect(roomMatches(room, 'zoe smith'), isFalse);
      expect(roomMatches(room, '!x:acme'), isTrue);
      expect(roomMatches(room, '@zoe:acme'), isFalse);
      const people = ['@zz:acme.com', 'Zed'];
      expect(roomMatches(room, '@zz:acme', people: people), isTrue);
      expect(roomMatches(room, 'zz', people: people), isTrue);
      expect(roomMatches(room, 'zed', people: people), isTrue);
      // The server alone, or the room ID's letters, don't find it.
      expect(roomMatches(room, 'acme', people: people), isFalse);
      expect(roomMatches(room, 'x', people: people), isFalse);
      expect(roomMatches(room, ':acme', people: people), isTrue);
    });

    test('sections keep their order; empty ones go', () {
      const a = Room(id: '!a', name: 'Alpha');
      const b = Room(id: '!b', name: 'Beta');
      const c = Room(id: '!c', name: 'Gamma');
      final groups = filterGroups(const [
        RoomGroup(SectionTags.favourites, 'Favorites', [a]),
        RoomGroup(SectionTags.people, 'People', [b, c]),
        RoomGroup(SectionTags.rooms, 'Rooms', [c]),
      ], (room) => roomMatches(room, 'ma'));
      expect(
        [for (final g in groups) g.tag],
        [SectionTags.people, SectionTags.rooms],
      );
      expect(groups.first.rooms, [c]);
    });
  });

  testWidgets('typing filters the sections; folded ones open while filtering', (
    tester,
  ) async {
    await pumpApp(
      tester,
      FakeMatrixClientFactory(saved: [_session()]),
      size: _wide,
      collapsed: MemoryCollapsedSections()..values[_me] = {SectionTags.people},
    );
    expect(_field, findsOneWidget);
    expect(_shown(tester), ['Team', 'News', 'Lobby']);

    await _type(tester, 'zoe agren');
    expect(_shown(tester), ['Zoë Ågren']);
    expect(_headers(tester), [SectionTags.people]);

    await _type(tester, 'E');
    expect(_shown(tester), ['Team', 'News', 'Robert', 'Zoë Ågren']);
    expect(_headers(tester), [
      SectionTags.favourites,
      _acme,
      SectionTags.people,
    ]);

    // Folded again once the filter is gone.
    await tester.tap(find.byKey(const Key('list.filter.clear')));
    await tester.pumpAndSettle();
    expect(_shown(tester), ['Team', 'News', 'Lobby']);
    expect(find.byKey(const Key('list.filter.clear')), findsNothing);
  });

  testWidgets('a direct chat is found by the person’s user ID and name', (
    tester,
  ) async {
    await pumpApp(
      tester,
      FakeMatrixClientFactory(saved: [_session()]),
      size: _wide,
    );
    await _type(tester, '@bob:acme');
    expect(_shown(tester), ['Robert']);
    await _type(tester, 'bobby');
    expect(_shown(tester), ['Robert']);
    await _type(tester, '!lobby');
    expect(_shown(tester), ['Lobby']);
  });

  testWidgets('nothing found says so', (tester) async {
    await pumpApp(tester, FakeMatrixClientFactory(saved: [_session()]));
    await _type(tester, 'nobody here');
    expect(_shown(tester), isEmpty);
    expect(find.byKey(const Key('list.filter.empty')), findsOneWidget);
    expect(find.text('No chats match'), findsOneWidget);
  });

  testWidgets('Esc clears and leaves the field; Enter opens the first match', (
    tester,
  ) async {
    await pumpApp(
      tester,
      FakeMatrixClientFactory(saved: [_session()]),
      size: _wide,
    );
    await tester.tap(_field);
    await _type(tester, 'lob');
    expect(_focused(tester), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(_field).controller!.text, isEmpty);
    expect(_focused(tester), isFalse);
    expect(_shown(tester).length, 5);

    await tester.tap(_field);
    await _type(tester, 'ne');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    final chat = tester.widget<ChatPane>(find.byType(ChatPane));
    expect(chat.roomId, '!news:acme.com');
  });

  testWidgets('Ctrl+K goes to the filter, widening a narrowed list', (
    tester,
  ) async {
    await pumpApp(
      tester,
      FakeMatrixClientFactory(saved: [_session()]),
      size: _wide,
      ui: MemoryUiPrefs()..narrowList = true,
    );
    // Narrowed: pictures only, no field.
    expect(_field, findsNothing);
    await _ctrlK(tester);
    expect(find.byKey(const Key('list.narrow')), findsOneWidget);
    expect(_field, findsOneWidget);
    expect(_focused(tester), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(_focused(tester), isFalse);
    await _ctrlK(tester);
    expect(_focused(tester), isTrue);
  });

  testWidgets('each account keeps its own filter', (tester) async {
    await pumpApp(
      tester,
      FakeMatrixClientFactory(
        saved: [
          _session(),
          FakeSession(
            userId: _other,
            rooms: const [
              Room(id: '!g1:globex.org', name: 'Globex board'),
              Room(id: '!g2:globex.org', name: 'Globex lunch'),
            ],
          ),
        ],
        active: _me,
      ),
      size: _wide,
    );
    await _type(tester, 'team');
    expect(_shown(tester), ['Team']);

    await tester.tap(find.byKey(const Key('account.$_other')));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(_field).controller!.text, isEmpty);
    expect(_shown(tester), ['Globex board', 'Globex lunch']);
    await _type(tester, 'lunch');
    expect(_shown(tester), ['Globex lunch']);

    await tester.tap(find.byKey(const Key('account.$_me')));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(_field).controller!.text, 'team');
    expect(_shown(tester), ['Team']);
  });
}
