import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oxitalk/src/app/theme.dart';
import 'package:oxitalk/src/features/chat/mentions/composer_controller.dart';
import 'package:oxitalk/src/matrix/api/matrix.dart';
import 'package:oxitalk/src/matrix/fakes/fakes.dart';

import 'support/app.dart';

const _wide = Size(1400, 900);
const _narrow = Size(400, 800);
const _me = '@me:acme.com';
const _bob = '@bob:acme.com';
const _team = '!team:acme.com';

MessageEntry _message(
  String id,
  String body, {
  String sender = _bob,
  ThreadSummary? thread,
}) => MessageEntry(
  id: id,
  sender: sender,
  senderName: sender == _bob ? 'Bob' : 'Me',
  time: DateTime(2026, 10, 26, 9),
  body: body,
  isOwn: sender == _me,
  meta: EventMeta(eventId: '\$$id', isEditable: sender == _me, thread: thread),
);

FakeSession _session({String userId = _me, String server = 'acme.com'}) {
  final team = '!team:$server';
  final garden = '!garden:$server';
  final session = FakeSession(
    userId: userId,
    rooms: [
      Room(id: team, name: 'Team $server'),
      Room(id: garden, name: 'Garden $server', lastMessage: 'Last in garden'),
    ],
  );
  session.members[team] = const [
    RoomMember(userId: _me, displayName: 'Me'),
    RoomMember(userId: _bob, displayName: 'Bob'),
  ];
  session.timelines[team] = FakeTimeline(
    ownUserId: userId,
    entries: [
      _message('hello', 'Hello there', thread: ThreadSummary(replyCount: 1)),
      _message('mine', 'My own words', sender: userId),
    ],
  );
  session.timelines[garden] = FakeTimeline(
    ownUserId: userId,
    entries: [_message('flowers', 'Flowers')],
  );
  session.threadTimelines[r'$hello'] = FakeTimeline(
    ownUserId: userId,
    entries: [
      _message('hello', 'Hello there'),
      _message('inthread', 'A reply in the thread'),
    ],
  );
  return session;
}

Future<FakeSession> _start(
  WidgetTester tester, {
  FakeSession? session,
  Size size = _wide,
  bool open = true,
}) async {
  final s = session ?? _session();
  await pumpApp(tester, FakeMatrixClientFactory(saved: [s]), size: size);
  if (open) await _openRoom(tester, 'Team acme.com');
  return s;
}

Future<void> _openRoom(WidgetTester tester, String name) async {
  await tester.tap(find.text(name).first);
  await tester.pumpAndSettle();
}

final _boxes = find.byKey(const Key('composer.text'));

ComposerController _controller(WidgetTester tester, [int index = 0]) =>
    tester.widget<TextField>(_boxes.at(index)).controller!
        as ComposerController;

Future<void> _type(WidgetTester tester, String text, [int index = 0]) async {
  await tester.enterText(_boxes.at(index), text);
  await tester.pump();
}

Future<void> _key(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

Future<void> _hoverAndTap(
  WidgetTester tester,
  String text,
  String button,
) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  await mouse.moveTo(tester.getCenter(find.text(text).first));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key(button)).hitTestable().first);
  await tester.pumpAndSettle();
}

/// The chat list's preview line for [roomId] when it shows a draft.
Finder _draftLine(String roomId) => find.byKey(Key('draft.$roomId'));

String _plain(Finder finder, WidgetTester tester) =>
    tester.widget<Text>(finder).textSpan!.toPlainText();

void main() {
  testWidgets('typed text survives opening another chat and coming back, '
      'the cursor at its end; the chat list says Draft:', (tester) async {
    final session = await _start(tester);
    await _type(tester, 'half a thought\nand more');
    expect(
      _draftLine(_team),
      findsNothing,
      reason: 'only once the chat is left',
    );

    await _openRoom(tester, 'Garden acme.com');
    expect(_controller(tester).text, isEmpty, reason: 'the garden has none');
    final line = _draftLine(_team);
    expect(line, findsOneWidget);
    expect(_plain(line, tester), 'Draft: half a thought');
    final draft = tester.widget<Text>(line).textSpan! as TextSpan;
    expect(
      (draft.children!.first as TextSpan).style!.color,
      OxiButtons.danger(Theme.of(tester.element(line)).brightness),
      reason: 'the red of the brand, darker on the light theme for contrast',
    );
    // Stored in the account's store, as a new message.
    final stored = session.drafts[(_team, null)]!;
    expect(stored.type, DraftType.newMessage);
    expect(plainText(stored.parts), 'half a thought\nand more');

    await _openRoom(tester, 'Team acme.com');
    final text = _controller(tester);
    expect(text.text, 'half a thought\nand more');
    expect(text.selection, const TextSelection.collapsed(offset: 23));
  });

  testWidgets('typing saves about half a second after the last key, and an '
      'emptied composer forgets the draft', (tester) async {
    final session = await _start(tester);
    await _type(tester, 'h');
    await tester.pump(const Duration(milliseconds: 300));
    await _type(tester, 'hi');
    await tester.pump(const Duration(milliseconds: 300));
    expect(session.draftSaves, 0);
    await tester.pump(const Duration(milliseconds: 300));
    expect(session.draftSaves, 1);
    expect(plainText(session.drafts[(_team, null)]!.parts), 'hi');

    await _type(tester, '');
    await tester.pump(const Duration(milliseconds: 600));
    expect(session.drafts, isEmpty);
    await _openRoom(tester, 'Garden acme.com');
    expect(_draftLine(_team), findsNothing);
    expect(find.text('Last in garden'), findsOneWidget);
  });

  testWidgets('a mention comes back as a pill, not as text', (tester) async {
    final session = await _start(tester);
    await _type(tester, 'Hi @bo');
    await tester.pumpAndSettle();
    await _key(tester, LogicalKeyboardKey.enter);
    await _type(tester, '${_controller(tester).text}see this');
    await _openRoom(tester, 'Garden acme.com');
    expect(_plain(_draftLine(_team), tester), 'Draft: Hi Bob see this');
    expect(session.drafts[(_team, null)]!.parts[1], isA<UserPill>());

    await _openRoom(tester, 'Team acme.com');
    expect(find.byKey(const Key('composer.pill.Bob')), findsOneWidget);
    expect(_controller(tester).text, 'Hi $pillChar see this');
    await tester.tap(find.byKey(const Key('composer.send')));
    await tester.pumpAndSettle();
    final timeline = session.timelines[_team]!;
    expect(timeline.messages.single.$1, [
      isA<TextPart>().having((p) => p.text, 'text', 'Hi '),
      isA<UserPill>().having((p) => p.userId, 'userId', _bob),
      isA<TextPart>().having((p) => p.text, 'text', ' see this'),
    ]);
  }, variant: desktop);

  testWidgets('a reply comes back with its banner and is sent as a reply; '
      'sending clears the draft', (tester) async {
    final session = await _start(tester);
    await _hoverAndTap(tester, 'Hello there', 'hover.reply');
    await _type(tester, 'sure thing');
    await _openRoom(tester, 'Garden acme.com');
    expect(session.drafts[(_team, null)]!.type, DraftType.reply);
    expect(session.drafts[(_team, null)]!.eventId, r'$hello');

    await _openRoom(tester, 'Team acme.com');
    expect(find.text('Replying to Bob'), findsOneWidget);
    expect(_controller(tester).text, 'sure thing');
    await tester.tap(find.byKey(const Key('composer.send')));
    await tester.pumpAndSettle();
    final timeline = session.timelines[_team]!;
    expect(timeline.messages.single.$2, r'$hello');
    expect(session.drafts, isEmpty);

    await _openRoom(tester, 'Garden acme.com');
    expect(_draftLine(_team), findsNothing);
    await _openRoom(tester, 'Team acme.com');
    expect(_controller(tester).text, isEmpty);
    expect(find.text('Replying to Bob'), findsNothing);
  }, variant: desktop);

  testWidgets('after a restart the stored draft comes back: text, pill, '
      'reply banner; the chat list shows it first', (tester) async {
    final session = _session()
      ..drafts[(_team, null)] = const ComposerDraft(
        [TextPart('from before '), UserPill(_bob, 'Bob'), TextPart(' ok')],
        type: DraftType.reply,
        eventId: r'$hello',
      );
    await _start(tester, session: session, open: false);
    expect(_plain(_draftLine(_team), tester), 'Draft: from before Bob ok');

    await _openRoom(tester, 'Team acme.com');
    expect(_controller(tester).text, 'from before $pillChar ok');
    expect(find.byKey(const Key('composer.pill.Bob')), findsOneWidget);
    expect(find.text('Replying to Bob'), findsOneWidget);
  });

  testWidgets('a reply to a message that can no longer be loaded keeps the '
      'text without the banner', (tester) async {
    final session = _session()
      ..drafts[(_team, null)] = const ComposerDraft(
        [TextPart('still here')],
        type: DraftType.reply,
        eventId: r'$gone',
      );
    await _start(tester, session: session);
    expect(_controller(tester).text, 'still here');
    expect(find.textContaining('Replying to'), findsNothing);
  });

  testWidgets('a reply to an older message not in the timeline comes back '
      'from the store', (tester) async {
    final session = _session()
      ..drafts[(_team, null)] = const ComposerDraft(
        [TextPart('about that')],
        type: DraftType.reply,
        eventId: r'$old',
      );
    session.timelines[_team]!.storedEvents[r'$old'] = _message(
      'old',
      'From last week',
    );
    await _start(tester, session: session);
    expect(find.text('Replying to Bob'), findsOneWidget);
    expect(find.text('From last week'), findsWidgets);
  });

  testWidgets('an edit comes back with the draft’s text, not the message’s', (
    tester,
  ) async {
    final session = _session()
      ..drafts[(_team, null)] = const ComposerDraft(
        [TextPart('My own better words')],
        type: DraftType.edit,
        eventId: r'$mine',
      );
    await _start(tester, session: session);
    expect(find.text('Editing'), findsOneWidget);
    expect(_controller(tester).text, 'My own better words');
    await tester.tap(find.byKey(const Key('composer.send')));
    await tester.pumpAndSettle();
    final timeline = session.timelines[_team]!;
    expect(timeline.messageEdits.single.$1, r'$mine');
    expect(plainText(timeline.messageEdits.single.$2), 'My own better words');
    expect(session.drafts, isEmpty);
  });

  testWidgets('a thread keeps its own draft apart from the chat’s, across '
      'closing and opening the thread', (tester) async {
    final session = await _start(tester);
    await _type(tester, 'for the room');
    await tester.tap(find.byKey(const Key('thread.bar.\$hello')));
    await tester.pumpAndSettle();
    expect(_boxes, findsNWidgets(2));
    expect(_controller(tester, 1).text, isEmpty);
    await _type(tester, 'for the thread', 1);

    await tester.tap(find.byKey(const Key('thread.close')));
    await tester.pumpAndSettle();
    expect(_boxes, findsOneWidget);
    expect(_controller(tester).text, 'for the room');
    expect(
      plainText(session.drafts[(_team, r'$hello')]!.parts),
      'for the thread',
    );

    await tester.tap(find.byKey(const Key('thread.bar.\$hello')));
    await tester.pumpAndSettle();
    expect(_controller(tester).text, 'for the room');
    expect(_controller(tester, 1).text, 'for the thread');

    // Sending in the thread clears only the thread's draft.
    await tester.tap(find.byKey(const Key('composer.send')).last);
    await tester.pumpAndSettle();
    expect(session.drafts.keys, [(_team, null)]);
    await _openRoom(tester, 'Garden acme.com');
    // The chat list shows the room's draft, never a thread's.
    expect(_plain(_draftLine(_team), tester), 'Draft: for the room');
  });

  testWidgets('a thread draft comes back from the store after a restart', (
    tester,
  ) async {
    final session = _session()
      ..drafts[(_team, r'$hello')] = const ComposerDraft([
        TextPart('thread words'),
      ]);
    await _start(tester, session: session);
    expect(_draftLine(_team), findsNothing);
    expect(_controller(tester).text, isEmpty);
    await tester.tap(find.byKey(const Key('thread.bar.\$hello')));
    await tester.pumpAndSettle();
    expect(_controller(tester, 1).text, 'thread words');
  });

  testWidgets('on a phone Back to the list keeps the draft', (tester) async {
    final session = await _start(tester, size: _narrow);
    await _type(tester, 'on the go');
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(_plain(_draftLine(_team), tester), 'Draft: on the go');
    expect(plainText(session.drafts[(_team, null)]!.parts), 'on the go');
    await _openRoom(tester, 'Team acme.com');
    expect(_controller(tester).text, 'on the go');
  });

  testWidgets('going to the background saves at once', (tester) async {
    final session = await _start(tester);
    await _type(tester, 'before the call');
    expect(session.drafts, isEmpty);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    expect(plainText(session.drafts[(_team, null)]!.parts), 'before the call');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
  });

  testWidgets('switching accounts keeps each account’s drafts', (tester) async {
    const other = '@me:globex.org';
    final acme = _session();
    final globex = _session(userId: other, server: 'globex.org');
    final factory = FakeMatrixClientFactory(saved: [acme, globex], active: _me);
    await pumpApp(tester, factory, size: _wide);
    await _openRoom(tester, 'Team acme.com');
    await _type(tester, 'acme words');

    await tester.tap(find.byKey(const Key('account.$other')));
    await tester.pumpAndSettle();
    await _openRoom(tester, 'Team globex.org');
    expect(_controller(tester).text, isEmpty);
    await _type(tester, 'globex words');

    await tester.tap(find.byKey(const Key('account.$_me')));
    await tester.pumpAndSettle();
    expect(_controller(tester).text, 'acme words');
    expect(plainText(acme.drafts[(_team, null)]!.parts), 'acme words');
    expect(
      plainText(globex.drafts[('!team:globex.org', null)]!.parts),
      'globex words',
    );

    await tester.tap(find.byKey(const Key('account.$other')));
    await tester.pumpAndSettle();
    expect(_controller(tester).text, 'globex words');
  });
}
