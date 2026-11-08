import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oxitalk/src/app/file_actions.dart';
import 'package:oxitalk/src/features/share/share_inbox.dart';
import 'package:oxitalk/src/matrix/api/matrix.dart';
import 'package:oxitalk/src/matrix/fakes/fakes.dart';

import 'support/app.dart';
import 'support/png.dart';

const _me = '@me:acme.com';
const _work = '@me:globex.org';
const _team = '!team:acme.com';
const _bob = '!bob:acme.com';
const _ops = '!ops:globex.org';

FakeSession _session({String userId = _me, List<Room>? rooms}) {
  final list =
      rooms ??
      const [
        Room(id: _team, name: 'Team'),
        Room(id: _bob, name: 'Robert', isDm: true),
        Room(
          id: '!invite:acme.com',
          name: 'Invite',
          membership: Membership.invited,
        ),
      ];
  final session = FakeSession(userId: userId, rooms: list);
  for (final room in list) {
    session.timelines[room.id] = FakeTimeline(ownUserId: userId);
  }
  return session;
}

FakeFileActions _files() => FakeFileActions()
  ..files['/cache/share/1/report.zip'] = PendingFile(
    'report.zip',
    'application/zip',
    png,
  )
  ..files['/cache/share/1/beach.png'] = PendingFile(
    'beach.png',
    'image/png',
    png,
  );

Finder get _composerText => find.byKey(const Key('composer.text'));

String _composerValue(WidgetTester tester) =>
    tester.widget<TextField>(_composerText).controller!.text;

void main() {
  group('shared items', () {
    test('come from the platform as paths and text', () {
      final items = SharedItems.fromMap({
        'paths': ['/a/x.zip', '', 7],
        'text': '  https://oxitalk.com \n',
      });
      expect(items.paths, ['/a/x.zip']);
      expect(items.text, 'https://oxitalk.com');
      expect(items.names, ['x.zip']);
      expect(const SharedItems().isEmpty, isTrue);
    });

    test('a second share adds to the first', () {
      const first = SharedItems(paths: ['/a/1.png'], text: 'Look');
      const second = SharedItems(paths: ['/a/1.png', '/a/2.png'], text: 'Here');
      expect(
        first.merge(second),
        const SharedItems(paths: ['/a/1.png', '/a/2.png'], text: 'Look\nHere'),
      );
    });

    test('the command line gives existing files and web links', () {
      final items = sharedFromArgs([
        '--verbose',
        '/home/me/report.pdf',
        'file:///home/me/My%20Photo.jpg',
        '/home/me/missing.txt',
        'https://oxitalk.com/x',
      ], isFile: (path) => !path.contains('missing'));
      // A file: URI becomes a path in the platform's own form (backslashes
      // on Windows), as Open with gives it there.
      expect(items.paths, [
        '/home/me/report.pdf',
        Uri.parse('file:///home/me/My%20Photo.jpg').toFilePath(),
      ]);
      expect(items.text, 'https://oxitalk.com/x');
      expect(sharedFromArgs(const []).isEmpty, isTrue);
    });
  });

  group('Send to…', () {
    testWidgets(
      'a shared file opens the picker; the picked chat gets it in the send dialog',
      (tester) async {
        final session = _session();
        final share = FakeShareSource()
          ..sharedBeforeStart(
            const SharedItems(paths: ['/cache/share/1/report.zip']),
          );
        await pumpApp(
          tester,
          FakeMatrixClientFactory(saved: [session]),
          files: _files(),
          share: share,
        );
        expect(find.text('Send to…'), findsOneWidget);
        expect(find.text('report.zip'), findsOneWidget);
        // Joined chats only; an invite can't take a message.
        expect(find.byKey(const Key('share.room.$_team')), findsOneWidget);
        expect(find.byKey(const Key('share.room.$_bob')), findsOneWidget);
        expect(
          find.byKey(const Key('share.room.!invite:acme.com')),
          findsNothing,
        );
        await tester.tap(find.byKey(const Key('share.room.$_team')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('sendFiles')), findsOneWidget);
        expect(find.text('Send file'), findsOneWidget);
        await tester.enterText(find.byKey(const Key('send.caption')), 'Q3');
        await tester.tap(find.byKey(const Key('send.confirm')));
        await tester.pumpAndSettle();
        expect(session.timelines[_team]!.files, {'report.zip': ('Q3', true)});
        expect(find.text('Send to…'), findsNothing);
        expect(find.text('Team'), findsWidgets);
      },
    );

    testWidgets('the filter narrows the chats; Enter picks the first', (
      tester,
    ) async {
      final session = _session();
      final share = FakeShareSource()
        ..sharedBeforeStart(const SharedItems(text: 'https://oxitalk.com'));
      await pumpApp(
        tester,
        FakeMatrixClientFactory(saved: [session]),
        share: share,
      );
      await tester.enterText(find.byKey(const Key('list.filter')), 'rob');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('share.room.$_team')), findsNothing);
      expect(find.byKey(const Key('share.room.$_bob')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('list.filter')), 'nobody');
      await tester.pumpAndSettle();
      expect(find.text('No chats match'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('list.filter')), 'rob');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      // Text goes into the message box, nothing is sent yet.
      expect(find.text('Send to…'), findsNothing);
      expect(_composerValue(tester), 'https://oxitalk.com');
      expect(find.byKey(const Key('sendFiles')), findsNothing);
      expect(session.timelines[_bob]!.files, isEmpty);
    });

    testWidgets('text and files: the text is the caption in the send dialog', (
      tester,
    ) async {
      final session = _session();
      final share = FakeShareSource()
        ..sharedBeforeStart(
          const SharedItems(
            paths: ['/cache/share/1/beach.png', '/cache/share/1/report.zip'],
            text: 'From the trip',
          ),
        );
      await pumpApp(
        tester,
        FakeMatrixClientFactory(saved: [session]),
        files: _files(),
        share: share,
      );
      expect(find.text('beach.png, report.zip'), findsOneWidget);
      expect(find.text('From the trip'), findsOneWidget);
      await tester.tap(find.byKey(const Key('share.room.$_bob')));
      await tester.pumpAndSettle();
      expect(find.text('Send 2 files'), findsOneWidget);
      await tester.tap(find.byKey(const Key('send.confirm')));
      await tester.pumpAndSettle();
      expect(session.timelines[_bob]!.files, {
        'beach.png': ('From the trip', true),
        'report.zip': (null, true),
      });
      // Sent with the files, so gone from the box.
      expect(_composerValue(tester), isEmpty);
    });

    testWidgets('Cancel drops the share and goes back to the chats', (
      tester,
    ) async {
      final session = _session();
      final share = FakeShareSource();
      await pumpApp(
        tester,
        FakeMatrixClientFactory(saved: [session]),
        files: _files(),
        share: share,
      );
      expect(find.text('Send to…'), findsNothing);
      // Shared while the app runs.
      share.share(const SharedItems(paths: ['/cache/share/1/report.zip']));
      await tester.pumpAndSettle();
      expect(find.text('Send to…'), findsOneWidget);
      await tester.tap(find.byKey(const Key('share.cancel')));
      await tester.pumpAndSettle();
      expect(find.text('Send to…'), findsNothing);
      expect(find.text('Team'), findsOneWidget);
      expect(session.timelines[_team]!.files, isEmpty);
    });

    testWidgets(
      'with two accounts, the other account\'s chat is picked and comes to the front',
      (tester) async {
        final home = _session();
        final work = _session(
          userId: _work,
          rooms: const [Room(id: _ops, name: 'Ops')],
        );
        final share = FakeShareSource()
          ..sharedBeforeStart(
            const SharedItems(paths: ['/cache/share/1/report.zip']),
          );
        await pumpApp(
          tester,
          FakeMatrixClientFactory(saved: [home, work]),
          size: const Size(1200, 800),
          files: _files(),
          share: share,
        );
        expect(find.text('Send to…'), findsOneWidget);
        expect(find.byKey(const Key('share.room.$_ops')), findsNothing);
        await tester.tap(find.byKey(const Key('share.account.$_work')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('share.room.$_team')), findsNothing);
        await tester.tap(find.byKey(const Key('share.room.$_ops')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('sendFiles')), findsOneWidget);
        await tester.tap(find.byKey(const Key('send.confirm')));
        await tester.pumpAndSettle();
        expect(work.timelines[_ops]!.files.keys, ['report.zip']);
        expect(home.timelines[_team]!.files, isEmpty);
        // The work account is in front, its chat open.
        expect(find.text('Ops'), findsWidgets);
      },
    );
  });
}
