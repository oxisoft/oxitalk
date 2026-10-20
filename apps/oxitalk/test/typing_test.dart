import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oxitalk/src/app/ui_prefs.dart';
import 'package:oxitalk/src/matrix/api/matrix.dart';
import 'package:oxitalk/src/matrix/fakes/fakes.dart';
import 'package:oxitalk/src/ui/format.dart';

import 'support/app.dart';

const _wide = Size(1400, 900);
const _me = '@me:acme.com';

Future<(FakeSession, FakeTimeline)> _open(
  WidgetTester tester, {
  MemoryUiPrefs? ui,
}) async {
  final timeline = FakeTimeline(ownUserId: _me);
  final session = FakeSession(
    userId: _me,
    rooms: const [
      Room(id: '!bob', name: 'Bob', isDm: true, lastMessage: 'See you'),
      Room(id: '!team', name: 'Team', lastMessage: 'Standup at ten'),
    ],
  );
  session.timelines['!bob'] = timeline;
  await pumpApp(
    tester,
    FakeMatrixClientFactory(saved: [session]),
    size: _wide,
    ui: ui,
  );
  await tester.tap(find.text('Bob'));
  await tester.pumpAndSettle();
  return (session, timeline);
}

void main() {
  testWidgets('who is typing shows under the chat title and in the list', (
    tester,
  ) async {
    final (session, _) = await _open(tester);
    session.typingState.value = {
      '!bob': ['Bob'],
      '!team': ['Carol', 'Dave'],
    };
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const Key('chat.typing'))).data,
      'typing…',
    );
    expect(find.text('Carol and Dave are typing…'), findsOneWidget);
    expect(find.text('Standup at ten'), findsNothing);

    session.typingState.value = const {};
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat.typing')), findsNothing);
    expect(find.text('Standup at ten'), findsOneWidget);
  });

  testWidgets('typing tells the room; sending, clearing or a pause stop it', (
    tester,
  ) async {
    final (_, timeline) = await _open(tester);
    final box = find.byKey(const Key('composer.text'));
    await tester.enterText(box, 'Hel');
    await tester.enterText(box, 'Hello');
    expect(timeline.typingSent, [true, true]);

    await tester.pump(const Duration(seconds: 6));
    expect(timeline.typingSent.last, isFalse);

    await tester.enterText(box, 'Hello again');
    await tester.tap(find.byKey(const Key('composer.send')));
    await tester.pumpAndSettle();
    expect(timeline.typingSent.last, isFalse);
  });

  testWidgets('with the setting off, typing is not sent', (tester) async {
    final (_, timeline) = await _open(
      tester,
      ui: MemoryUiPrefs(sendTyping: false),
    );
    await tester.enterText(find.byKey(const Key('composer.text')), 'Quiet');
    await tester.pumpAndSettle();
    expect(timeline.typingSent, isEmpty);
  });

  test('the label names who types', () {
    expect(typingLabel(null, direct: false), isNull);
    expect(typingLabel(const [], direct: true), isNull);
    expect(typingLabel(const ['Bob'], direct: true), 'typing…');
    expect(typingLabel(const ['Bob'], direct: false), 'Bob is typing…');
    expect(
      typingLabel(const ['Bob', 'Carol', 'Dave'], direct: false),
      '3 people are typing…',
    );
  });
}
