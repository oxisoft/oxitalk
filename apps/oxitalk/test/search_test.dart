import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oxitalk/src/features/chat/chat_search.dart';
import 'package:oxitalk/src/matrix/api/matrix.dart';
import 'package:oxitalk/src/matrix/fakes/fakes.dart';
import 'package:oxitalk/src/matrix/rust/mapping.dart';
import 'package:oxitalk/src/rust/api/search.dart' as core;
import 'package:oxitalk/src/rust/api/timeline.dart' as core;

import 'support/app.dart';

const _wide = Size(1400, 900);
const _me = '@me:acme.com';
const _bob = '@bob:acme.com';
const _room = '!team:acme.com';

DateTime _at(int i) => DateTime(2026, 10, 20, 12).add(Duration(minutes: i));

MessageEntry _message(int i, {String? body}) => MessageEntry(
  id: 'm$i',
  sender: _bob,
  senderName: 'Bob',
  time: _at(i),
  body: body ?? 'message $i',
  meta: EventMeta(eventId: '\$m$i'),
);

SearchHit _hit(int i, String text, {String? filename, String? threadRoot}) =>
    SearchHit(
      eventId: '\$m$i',
      sender: _bob,
      senderName: 'Bob',
      time: _at(i),
      text: text,
      filename: filename,
      mediaKind: filename == null ? null : MediaKind.file,
      threadRoot: threadRoot,
    );

/// The chat with 60 messages, opened; three of them have "needle".
Future<FakeSession> _open(WidgetTester tester) async {
  final session = FakeSession(
    userId: _me,
    rooms: const [Room(id: _room, name: 'Team')],
  );
  session.timelines[_room] = FakeTimeline(
    ownUserId: _me,
    entries: [
      for (var i = 0; i < 60; i++)
        _message(
          i,
          body: switch (i) {
            50 => 'find the needle',
            5 => 'another Needle here',
            _ => null,
          },
        ),
    ],
  );
  session.searchable[_room] = [
    for (var i = 0; i < 60; i++)
      switch (i) {
        50 => _hit(50, 'find the needle'),
        30 => _hit(30, '', filename: 'needle.pdf'),
        5 => _hit(5, 'another Needle here'),
        _ => _hit(i, 'message $i'),
      },
  ];
  await pumpApp(tester, FakeMatrixClientFactory(saved: [session]), size: _wide);
  await tester.tap(find.text('Team'));
  await tester.pumpAndSettle();
  return session;
}

Finder get _highlighted => find.byKey(const Key('message.highlight'));

Finder _highlightedText(String text) =>
    find.descendant(of: _highlighted, matching: find.text(text));

String _count(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('search.count'))).data!;

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const Key('search.field')), text);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('typing finds the hits, newest first; each is scrolled to and '
      'highlighted; Enter goes older, Shift+Enter newer, Esc closes', (
    tester,
  ) async {
    final session = await _open(tester);
    expect(find.byKey(const Key('search.bar')), findsNothing);
    await tester.tap(find.byKey(const Key('chat.search')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('search.bar')), findsOneWidget);

    await _type(tester, 'needle');
    expect(session.searches, ['needle']);
    expect(_count(tester), '1 of 3');
    expect(_highlightedText('find the needle'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('search.scope'))).data,
      startsWith('Searched 60 messages on this device, back to'),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(_count(tester), '2 of 3');
    expect(_highlightedText('message 30'), findsOneWidget);

    await tester.tap(find.byKey(const Key('search.older')));
    await tester.pumpAndSettle();
    expect(_count(tester), '3 of 3');
    // Far up the chat: it was scrolled there.
    expect(_highlightedText('another Needle here'), findsOneWidget);
    expect(_highlightedText('find the needle'), findsNothing);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await tester.pumpAndSettle();
    expect(_count(tester), '2 of 3');

    // The list of hits, the matches marked; a tap shows that one.
    await tester.tap(find.byKey(const Key('search.list')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const Key('search.results')),
        matching: find.byType(ListTile),
      ),
      findsNWidgets(3),
    );
    await tester.tap(find.byKey(const Key(r'search.hit.$m50')));
    await tester.pumpAndSettle();
    expect(_count(tester), '1 of 3');
    expect(_highlightedText('find the needle'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('search.bar')), findsNothing);
    expect(_highlighted, findsNothing);
  });

  testWidgets('Ctrl+F opens the search; with nothing found it loads older '
      'history once and shows a hit from there around it', (tester) async {
    final session = await _open(tester);
    session.olderHistory[_room] = [_hit(-900, 'ancient words')];
    session.timelinesAt[r'$m-900'] = FakeTimeline(
      ownUserId: _me,
      entries: [
        _message(-901),
        _message(-900, body: 'ancient words'),
      ],
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('search.field')), findsOneWidget);

    await _type(tester, 'ANCIENT');
    expect(session.historyLoads, 1);
    expect(_count(tester), '1 of 1');
    expect(_highlightedText('ancient words'), findsOneWidget);
    expect(find.byKey(const Key('chat.toLatest')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('search.scope'))).data,
      'Searched the whole chat on this device',
    );
    expect(find.byKey(const Key('search.loadOlder')), findsNothing);

    // Nothing anywhere: no more loading once the start is reached.
    await _type(tester, 'nowhere');
    expect(_count(tester), 'No results');
    expect(session.historyLoads, 1);
    await tester.tap(find.byKey(const Key('search.close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('search.bar')), findsNothing);
  });

  testWidgets('more history is searched on request, and a reply in a thread '
      'opens its thread', (tester) async {
    final session = await _open(tester);
    session.searchable[_room] = [
      ...session.searchable[_room]!,
      _hit(70, 'pizza in a thread', threadRoot: r'$m10'),
    ];
    session.olderHistory[_room] = [_hit(-5, 'old pizza')];
    session.threadTimelines[r'$m10'] = FakeTimeline(
      ownUserId: _me,
      entries: [
        _message(10),
        _message(70, body: 'pizza in a thread'),
      ],
    );
    await tester.tap(find.byKey(const Key('chat.search')));
    await tester.pumpAndSettle();
    await _type(tester, 'pizza');
    expect(session.historyLoads, 0);
    expect(_count(tester), '1 of 1');
    // The hit is in a thread: the thread opens beside the chat.
    expect(find.byKey(const Key('thread.close')), findsOneWidget);

    await tester.tap(find.byKey(const Key('search.loadOlder')));
    await tester.pumpAndSettle();
    expect(session.historyLoads, 1);
    // The hit shown stays shown.
    expect(_count(tester), '1 of 2');
  });

  test('matches are marked case-insensitively, a long text from shortly before '
      'the first', () {
    const style = TextStyle(fontWeight: FontWeight.bold);
    final spans = highlightMatches('Needle and needle', 'NEEDLE', style);
    expect(
      [for (final span in spans) (span.text, span.style == style)],
      [('Needle', true), (' and ', false), ('needle', true)],
    );
    final long = highlightMatches('${'x' * 100} needle', 'needle', style);
    expect(long.first.text, '…');
    expect(long.map((s) => s.text).join().length, lessThan(50));
  });

  test('the core\'s results map to the app\'s', () {
    final results = searchResultsOf(
      const core.SearchResults(
        hits: [
          core.SearchHit(
            eventId: r'$f',
            threadRoot: r'$root',
            sender: _bob,
            senderName: 'Bob',
            timestampMs: 1760000000000,
            text: 'plan',
            filename: 'plan.pdf',
            mediaKind: core.MediaKind.file,
          ),
          core.SearchHit(
            eventId: r'$t',
            sender: _bob,
            timestampMs: 1750000000000,
            text: 'a plan',
          ),
        ],
        total: 7,
        searched: 120,
        oldestMs: 1740000000000,
      ),
    );
    expect(results.total, 7);
    expect(results.searched, 120);
    expect(results.oldest, DateTime.fromMillisecondsSinceEpoch(1740000000000));
    final file = results.hits.first;
    expect(
      (file.eventId, file.threadRoot, file.filename, file.mediaKind, file.text),
      (r'$f', r'$root', 'plan.pdf', MediaKind.file, 'plan'),
    );
    expect(file.time, DateTime.fromMillisecondsSinceEpoch(1760000000000));
    expect(results.hits.last.mediaKind, isNull);
  });
}
