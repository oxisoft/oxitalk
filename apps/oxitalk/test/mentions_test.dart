import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oxitalk/src/features/chat/mentions/composer_controller.dart';
import 'package:oxitalk/src/features/chat/mentions/mention_suggestions.dart';
import 'package:oxitalk/src/matrix/api/matrix.dart';
import 'package:oxitalk/src/matrix/fakes/fakes.dart';

import 'support/app.dart';

const _wide = Size(1400, 900);
const _me = '@me:acme.com';
const _bob = '@bob:acme.com';
const _bobby = '@bobby:acme.com';
const _alice = '@alice:acme.com';
const _room = '!team:acme.com';

const _members = [
  RoomMember(userId: _me, displayName: 'Me'),
  RoomMember(userId: _alice, displayName: 'Alice Robinson'),
  RoomMember(userId: _bobby, displayName: 'Bobby Tables'),
  RoomMember(userId: _bob, displayName: 'Bob'),
  RoomMember(
    userId: '@banned:acme.com',
    displayName: 'Bo Banned',
    banned: true,
  ),
];

MessageEntry _message(
  String id,
  String body, {
  String sender = _bob,
  List<RichBlock>? formatted,
}) => MessageEntry(
  id: id,
  sender: sender,
  senderName: sender == _bob ? 'Bob' : 'Me',
  time: DateTime(2026, 10, 26, 9),
  body: body,
  formatted: formatted,
  isOwn: sender == _me,
  meta: EventMeta(eventId: '\$$id', isEditable: sender == _me),
);

Future<(FakeSession, FakeTimeline)> _open(
  WidgetTester tester, {
  bool roomMention = false,
  List<TimelineEntry>? entries,
}) async {
  final timeline = FakeTimeline(
    ownUserId: _me,
    entries: entries ?? [_message('hello', 'Hello there')],
  );
  final session =
      FakeSession(
          userId: _me,
          rooms: const [Room(id: _room, name: 'Team')],
        )
        ..members[_room] = _members
        ..roomMentionAllowed = roomMention
        ..mentionRoomList = const [
          MentionRoom(
            roomId: '!garden:acme.com',
            name: 'Garden',
            alias: '#garden:acme.com',
          ),
          MentionRoom(roomId: _room, name: 'Team'),
        ];
  session.timelines[_room] = timeline;
  await pumpApp(tester, FakeMatrixClientFactory(saved: [session]), size: _wide);
  await tester.tap(find.text('Team'));
  await tester.pumpAndSettle();
  return (session, timeline);
}

final _box = find.byKey(const Key('composer.text'));
final _popup = find.byKey(const Key('mentions.popup'));

ComposerController _controller(WidgetTester tester) =>
    tester.widget<TextField>(_box).controller! as ComposerController;

/// Types [text] into the composer, as the keyboard would, the cursor at its end.
Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(_box, text);
  await tester.pumpAndSettle();
}

Future<void> _key(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

/// The suggestions' titles, top to bottom.
List<String> _titles(WidgetTester tester) => [
  for (final tile in tester.widgetList<ListTile>(
    find.descendant(of: _popup, matching: find.byType(ListTile)),
  ))
    ((tile.title! as Text).data!),
];

bool _lit(WidgetTester tester, String seed) =>
    tester.widget<ListTile>(find.byKey(Key('mentions.item.$seed'))).selected;

void main() {
  group('what is typed', () {
    test(
      '@ or # after a space or at the start opens a query up to the cursor',
      () {
        MentionQuery? at(String text, [int? cursor]) => mentionQueryAt(
          TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: cursor ?? text.length),
          ),
        );
        expect(at('hi @bo'), (trigger: '@', text: 'bo', start: 3, end: 6));
        expect(at('@'), (trigger: '@', text: '', start: 0, end: 1));
        expect(at('see #gar'), (trigger: '#', text: 'gar', start: 4, end: 8));
        expect(at('mail me@acme.com'), isNull);
        expect(at('hi @bob there'), isNull);
        expect(at('hi @bob there', 7), (
          trigger: '@',
          text: 'bob',
          start: 3,
          end: 7,
        ));
      },
    );

    test('members are ranked: name start, word start, ID, anywhere; the user, '
        'the banned and more than six are left out', () {
      List<String> names(String query, {bool room = false}) => [
        for (final s in memberSuggestions(
          query,
          _members,
          own: _me,
          canMentionRoom: room,
        ))
          s.title,
      ];
      expect(names('bo'), ['Bob', 'Bobby Tables']);
      expect(names('rob'), ['Alice Robinson']);
      expect(names('alice'), ['Alice Robinson']);
      // By ID too.
      expect(names('bobby'), ['Bobby Tables']);
      expect(names('xyz'), isEmpty);
      expect(names(''), ['Alice Robinson', 'Bob', 'Bobby Tables']);
      expect(names('ro', room: true), ['@room', 'Alice Robinson']);
      expect(names('ro'), ['Alice Robinson']);
      final many = [
        for (var i = 0; i < 10; i++)
          RoomMember(userId: '@u$i:acme.com', displayName: 'User $i'),
      ];
      expect(
        memberSuggestions('user', many, own: _me, canMentionRoom: false),
        hasLength(maxSuggestions),
      );
    });

    test('rooms match by name or address', () {
      const rooms = [
        MentionRoom(roomId: '!a:x', name: 'Garden', alias: '#garden:x'),
        MentionRoom(roomId: '!b:x', name: 'Team', alias: '#crew:x'),
      ];
      expect([for (final s in roomSuggestions('cr', rooms)) s.title], ['Team']);
      expect(
        [for (final s in roomSuggestions('gar', rooms)) s.title],
        ['Garden'],
      );
    });
  });

  group('the composer text', () {
    test('a pill is one character; deleting it drops it, a pasted one is '
        'taken out', () {
      final text = ComposerController()..text = 'hi @bo';
      text.insertPill(3, 6, const UserPill(_bob, 'Bob'));
      expect(text.text, 'hi $pillChar ');
      expect(text.selection.baseOffset, 5);
      text.value = text.value.copyWith(
        text: '${text.text}how are you',
        selection: const TextSelection.collapsed(offset: 16),
      );
      expect(text.parts(), [
        isA<TextPart>().having((p) => p.text, 'text', 'hi '),
        isA<UserPill>().having((p) => p.userId, 'userId', _bob),
        isA<TextPart>().having((p) => p.text, 'text', ' how are you'),
      ]);
      expect(plainText(text.parts()), 'hi Bob how are you');
      // Backspace right after the pill.
      text.value = const TextEditingValue(
        text: 'hi  how are you',
        selection: TextSelection.collapsed(offset: 3),
      );
      expect(text.pills, isEmpty);
      expect(text.parts(), [
        isA<TextPart>().having((p) => p.text, 'text', 'hi  how are you'),
      ]);
      // A pill character from a paste has no pill.
      text.value = const TextEditingValue(
        text: 'x${pillChar}y',
        selection: TextSelection.collapsed(offset: 2),
      );
      expect(text.text, 'xy');
    });

    test('of two pills side by side, the one before the cursor goes', () {
      final text = ComposerController()
        ..setContent('$pillChar$pillChar', const [
          UserPill(_alice, 'Alice'),
          UserPill(_bob, 'Bob'),
        ]);
      // Backspace with the cursor between them.
      text.value = const TextEditingValue(
        text: pillChar,
        selection: TextSelection.collapsed(offset: 0),
      );
      expect(text.pills, [
        isA<UserPill>().having((p) => p.userId, 'userId', _bob),
      ]);
    });

    test('editing a message puts its mentions back as pills', () {
      final (text, pills) = pillsFromMessage('Hi Bob and Bob, see #team:x', [
        const RichBlock(ParagraphBlock(), [
          RichSpan('Hi '),
          RichSpan('Bob', mention: _bob),
          RichSpan(' and Bob, see '),
          RichSpan('#team:x', link: 'https://matrix.to/#/%23team:x'),
        ]),
      ]);
      expect(text, 'Hi $pillChar and Bob, see $pillChar');
      expect(pills, [
        isA<UserPill>().having((p) => p.name, 'name', 'Bob'),
        isA<RoomPill>().having((p) => p.alias, 'alias', '#team:x'),
      ]);
    });
  });

  group('suggestions in the chat', () {
    testWidgets('@ and letters list the matching members above the box; '
        'arrows move, Enter puts a pill, sending names and links them', (
      tester,
    ) async {
      final (_, timeline) = await _open(tester);
      await _type(tester, 'Hi @bo');
      expect(_popup, findsOneWidget);
      expect(_titles(tester), ['Bob', 'Bobby Tables']);
      // Above the composer.
      expect(
        tester.getBottomLeft(_popup).dy,
        lessThanOrEqualTo(tester.getTopLeft(_box).dy),
      );
      expect(_lit(tester, _bob), isTrue);
      await _key(tester, LogicalKeyboardKey.arrowDown);
      expect(_lit(tester, _bobby), isTrue);
      await _key(tester, LogicalKeyboardKey.arrowDown);
      expect(_lit(tester, _bob), isTrue, reason: 'wraps around');
      await _key(tester, LogicalKeyboardKey.arrowUp);
      await _key(tester, LogicalKeyboardKey.enter);
      expect(_popup, findsNothing);
      expect(
        find.byKey(const Key('composer.pill.Bobby Tables')),
        findsOneWidget,
      );
      expect(timeline.messages, isEmpty, reason: 'Enter picked, not sent');

      await tester.enterText(_box, '${_controller(tester).text}hello');
      await tester.pumpAndSettle();
      await _key(tester, LogicalKeyboardKey.enter);
      expect(timeline.messages, hasLength(1));
      final (parts, replyTo) = timeline.messages.single;
      expect(replyTo, isNull);
      expect(parts, [
        isA<TextPart>().having((p) => p.text, 'text', 'Hi '),
        isA<UserPill>()
            .having((p) => p.userId, 'userId', _bobby)
            .having((p) => p.name, 'name', 'Bobby Tables'),
        isA<TextPart>().having((p) => p.text, 'text', ' hello'),
      ]);
      expect(find.text('Hi Bobby Tables hello'), findsOneWidget);
      expect(_controller(tester).text, isEmpty);
    }, variant: desktop);

    testWidgets('Tab picks too; Esc closes the list and Enter then sends', (
      tester,
    ) async {
      final (_, timeline) = await _open(tester);
      await _type(tester, '@ali');
      await _key(tester, LogicalKeyboardKey.tab);
      expect(
        find.byKey(const Key('composer.pill.Alice Robinson')),
        findsOneWidget,
      );

      await tester.enterText(_box, '${_controller(tester).text}@bo');
      await tester.pumpAndSettle();
      expect(_popup, findsOneWidget);
      await _key(tester, LogicalKeyboardKey.escape);
      expect(_popup, findsNothing);
      await _key(tester, LogicalKeyboardKey.enter);
      final (parts, _) = timeline.messages.single;
      expect(plainText(parts), 'Alice Robinson @bo');
    }, variant: desktop);

    testWidgets('a tap picks; backspace deletes the pill whole', (
      tester,
    ) async {
      await _open(tester);
      await _type(tester, '@b');
      await tester.tap(find.byKey(const Key('mentions.item.$_bob')));
      await tester.pumpAndSettle();
      expect(_controller(tester).pills, hasLength(1));
      // The space after it, then the pill.
      await _key(tester, LogicalKeyboardKey.backspace);
      await _key(tester, LogicalKeyboardKey.backspace);
      expect(_controller(tester).pills, isEmpty);
      expect(_controller(tester).text, isEmpty);
      expect(find.byKey(const Key('composer.pill.Bob')), findsNothing);
    });

    testWidgets('@room is offered only to who may notify the room', (
      tester,
    ) async {
      final (_, timeline) = await _open(tester, roomMention: true);
      await _type(tester, 'lunch @ro');
      expect(_titles(tester), ['@room', 'Alice Robinson']);
      await _key(tester, LogicalKeyboardKey.enter);
      await _key(tester, LogicalKeyboardKey.enter);
      expect(timeline.messages.single.$1, [isA<TextPart>(), isA<AtRoomPill>()]);
    }, variant: desktop);

    testWidgets('without the right, no @room', (tester) async {
      await _open(tester);
      await _type(tester, '@ro');
      expect(_titles(tester), ['Alice Robinson']);
    }, variant: desktop);

    testWidgets('# lists the user’s rooms, picked as a room pill', (
      tester,
    ) async {
      final (_, timeline) = await _open(tester);
      await _type(tester, 'see #gar');
      expect(_titles(tester), ['Garden']);
      await _key(tester, LogicalKeyboardKey.enter);
      expect(
        find.byKey(const Key('composer.pill.#garden:acme.com')),
        findsOneWidget,
      );
      await _key(tester, LogicalKeyboardKey.enter);
      expect(timeline.messages.single.$1.last, isA<RoomPill>());
    }, variant: desktop);

    testWidgets('a reply carries its pills and what it answers', (
      tester,
    ) async {
      final (_, timeline) = await _open(tester);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.text('Hello there')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('hover.reply')).hitTestable().first,
      );
      await tester.pumpAndSettle();
      await _type(tester, '@bob');
      await _key(tester, LogicalKeyboardKey.enter);
      await _key(tester, LogicalKeyboardKey.enter);
      final (parts, replyTo) = timeline.messages.single;
      expect(replyTo, r'$hello');
      expect(parts.single, isA<UserPill>());
      expect(timeline.calls, [r'reply $hello Bob']);
    }, variant: desktop);

    testWidgets('editing a message with a mention keeps it as a pill', (
      tester,
    ) async {
      final (_, timeline) = await _open(
        tester,
        entries: [
          _message(
            'mine',
            'Thanks Bob!',
            sender: _me,
            formatted: const [
              RichBlock(ParagraphBlock(), [
                RichSpan('Thanks '),
                RichSpan('Bob', mention: _bob),
                RichSpan('!'),
              ]),
            ],
          ),
        ],
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.text('Thanks Bob!')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('hover.more')).hitTestable().first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('composer.pill.Bob')), findsOneWidget);
      await tester.tap(find.byKey(const Key('composer.send')));
      await tester.pumpAndSettle();
      final (ref, parts) = timeline.messageEdits.single;
      expect(ref, r'$mine');
      expect(parts, [
        isA<TextPart>().having((p) => p.text, 'text', 'Thanks '),
        isA<UserPill>().having((p) => p.userId, 'userId', _bob),
        isA<TextPart>().having((p) => p.text, 'text', '!'),
      ]);
    }, variant: desktop);
  });
}
