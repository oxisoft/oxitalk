import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oxitalk/src/matrix/api/matrix.dart';
import 'package:oxitalk/src/matrix/fakes/fakes.dart';

import 'support/app.dart';

const _wide = Size(1200, 800);
const _me = '@me:acme.com';

MessageEntry _message(int i) => MessageEntry(
  id: 'm$i',
  sender: '@bob:acme.com',
  time: DateTime(2026, 10, 19, 12, i),
  body: 'message $i',
);

/// A chat with [count] messages, opened.
Future<FakeTimeline> _openChat(WidgetTester tester, {int count = 3}) async {
  final timeline = FakeTimeline(
    ownUserId: _me,
    entries: [for (var i = 0; i < count; i++) _message(i)],
  );
  final session = FakeSession(
    userId: _me,
    rooms: const [
      Room(
        id: '!bob',
        name: 'Bob',
        isDm: true,
        unreadCount: 3,
        unreadNotifications: 3,
      ),
    ],
  );
  session.timelines['!bob'] = timeline;
  await pumpApp(tester, FakeMatrixClientFactory(saved: [session]), size: _wide);
  await tester.tap(find.text('Bob'));
  await tester.pumpAndSettle();
  return timeline;
}

void _receive(FakeTimeline timeline) => timeline.entryList = [
  ...timeline.entryList,
  _message(timeline.entryList.length),
];

void main() {
  testWidgets('an open chat is read, and stays read as messages come', (
    tester,
  ) async {
    final timeline = await _openChat(tester);
    expect(timeline.readMarks, 1);

    _receive(timeline);
    await tester.pumpAndSettle();
    expect(timeline.readMarks, 2);

    // Nothing new: nothing to mark.
    await tester.pumpAndSettle();
    expect(timeline.readMarks, 2);
  });

  testWidgets('a message that comes while the window is in the background '
      'waits until it is in front again', (tester) async {
    final timeline = await _openChat(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    _receive(timeline);
    await tester.pumpAndSettle();
    expect(timeline.readMarks, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(timeline.readMarks, 2);
  });

  testWidgets('a message that comes while scrolled up waits until the bottom', (
    tester,
  ) async {
    final timeline = await _openChat(tester, count: 60);
    expect(timeline.readMarks, 1);

    await tester.drag(find.text('message 59'), const Offset(0, 600));
    await tester.pumpAndSettle();
    _receive(timeline);
    await tester.pumpAndSettle();
    expect(timeline.readMarks, 1);

    await tester.drag(find.byType(ListView).last, const Offset(0, -5000));
    await tester.pumpAndSettle();
    expect(timeline.readMarks, 2);
  });
}
