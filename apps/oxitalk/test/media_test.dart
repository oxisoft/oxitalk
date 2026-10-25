import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oxitalk/src/app/file_actions.dart';
import 'package:oxitalk/src/app/media_prefs.dart';
import 'package:oxitalk/src/features/chat_info/chat_info.dart';
import 'package:oxitalk/src/matrix/api/matrix.dart';
import 'package:oxitalk/src/matrix/fakes/fakes.dart';

import 'support/app.dart';
import 'support/png.dart';

const _wide = Size(1400, 900);
const _me = '@me:acme.com';
const _bob = '@bob:acme.com';
const _room = '!team:acme.com';

const _photo = MediaInfo(
  kind: MediaKind.image,
  source: 'photo',
  filename: 'office.png',
  caption: 'The new office',
  width: 64,
  height: 64,
);
const _video = MediaInfo(
  kind: MediaKind.video,
  source: 'video',
  thumbnail: 'video-thumb',
  filename: 'demo.mp4',
  duration: Duration(minutes: 1, seconds: 5),
);
const _doc = MediaInfo(
  kind: MediaKind.file,
  source: 'doc',
  filename: 'contract.pdf',
  size: 2 * 1024 * 1024,
);
const _voice = MediaInfo(
  kind: MediaKind.audio,
  source: 'voice',
  filename: 'voice.ogg',
  duration: Duration(seconds: 7),
);

MediaEntry _media(String id, MediaInfo media, int minute) => MediaEntry(
  id: id,
  sender: _bob,
  senderName: 'Bob',
  time: DateTime(2026, 10, 19, 12, minute),
  media: media,
);

FakeSession _session() {
  final entries = [
    _media('photo', _photo, 1),
    _media('video', _video, 2),
    _media('doc', _doc, 3),
    _media('voice', _voice, 4),
    MessageEntry(
      id: 'link',
      sender: _bob,
      senderName: 'Bob',
      time: DateTime(2026, 10, 19, 12, 5),
      body: 'Docs at https://oxisoft.io/docs. And (https://example.org/a)!',
    ),
  ];
  final session = FakeSession(
    userId: _me,
    rooms: const [Room(id: _room, name: 'Team', isEncrypted: true)],
  );
  session.pictures.addAll({
    'photo': png,
    'video-thumb': png,
    'video': png,
    'doc': png,
    'voice': png,
  });
  session.timelines[_room] = FakeTimeline(ownUserId: _me, entries: entries);
  session.mediaTimelines[_room] = FakeTimeline(
    ownUserId: _me,
    entries: entries,
  );
  session.details[_room] = const RoomDetails(
    roomId: _room,
    name: 'Team',
    topic: 'Where the team talks',
    alias: '#team:acme.com',
    joinedMembers: 2,
    isEncrypted: true,
  );
  session.members[_room] = const [
    RoomMember(userId: _bob, displayName: 'Bob', role: MemberRole.admin),
    RoomMember(userId: _me, displayName: 'Me'),
  ];
  return session;
}

Future<(FakeSession, FakeFileActions)> _openChat(
  WidgetTester tester, {
  Size size = _wide,
}) async {
  final session = _session();
  final files = FakeFileActions();
  await pumpApp(
    tester,
    FakeMatrixClientFactory(saved: [session]),
    size: size,
    files: files,
  );
  await tester.tap(find.text('Team'));
  await tester.pumpAndSettle();
  return (session, files);
}

Finder _mediaOf(MediaInfo media) =>
    find.byKey(Key('media.${media.source.hashCode}'));

void main() {
  testWidgets('an image shows in the chat with its caption, and opens big', (
    tester,
  ) async {
    final (session, files) = await _openChat(tester);
    expect(
      find.descendant(of: _mediaOf(_photo), matching: find.byType(Image)),
      findsOneWidget,
    );
    expect(find.text('The new office'), findsOneWidget);

    await tester.tap(_mediaOf(_photo).first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('viewer')), findsOneWidget);

    final viewer = find.byKey(const Key('viewer'));
    await tester.tap(
      find.descendant(of: viewer, matching: find.byTooltip('Save as…')),
    );
    await tester.pumpAndSettle();
    expect(session.saved, {'/saved/file': 'photo'});

    await tester.tap(
      find.descendant(
        of: viewer,
        matching: find.byTooltip('Open in default app'),
      ),
    );
    await tester.pumpAndSettle();
    expect(files.launched, [Uri.file('/tmp/open/office.png')]);
  });

  testWidgets('a video shows its picture and length, and opens in an app', (
    tester,
  ) async {
    final (session, files) = await _openChat(tester);
    expect(find.text('1:05'), findsOneWidget);
    await tester.tap(_mediaOf(_video));
    await tester.pumpAndSettle();
    expect(session.saved, {'/tmp/open/demo.mp4': 'video'});
    expect(files.launched, [Uri.file('/tmp/open/demo.mp4')]);
  });

  testWidgets('a file shows its name and size; it opens, or saves', (
    tester,
  ) async {
    final (session, files) = await _openChat(tester);
    expect(find.text('contract.pdf'), findsOneWidget);
    expect(find.text('2.0 MB'), findsOneWidget);
    expect(find.text('0:07'), findsOneWidget);

    await tester.tap(find.text('contract.pdf'));
    await tester.pumpAndSettle();
    expect(files.launched.single.path, endsWith('contract.pdf'));

    files.savePath = null;
    await tester.tap(
      find.descendant(of: _mediaOf(_doc), matching: find.byTooltip('Save as…')),
    );
    await tester.pumpAndSettle();
    expect(session.saved.keys, isNot(contains('/saved/file')));
  });

  testWidgets('a picture that can’t be loaded says so', (tester) async {
    final session = _session()..pictures.remove('photo');
    await pumpApp(
      tester,
      FakeMatrixClientFactory(saved: [session]),
      size: _wide,
    );
    await tester.tap(find.text('Team'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: _mediaOf(_photo),
        matching: find.byIcon(Icons.broken_image_outlined),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the right-click menu of a file saves it', (tester) async {
    final (session, _) = await _openChat(tester);
    await tester.tap(find.text('The new office'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save as…'));
    await tester.pumpAndSettle();
    expect(session.saved, {'/saved/file': 'photo'});
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('the chat title opens its info in the chat’s place', (
    tester,
  ) async {
    await _openChat(tester);
    await tester.tap(find.byKey(const Key('chat.title')));
    await tester.pumpAndSettle();
    final info = find.byType(ChatInfoPane);
    expect(info, findsOneWidget);
    expect(find.byKey(const Key('composer.text')), findsNothing);
    Finder inInfo(Finder finder) => find.descendant(of: info, matching: finder);
    expect(inInfo(find.text('#team:acme.com')), findsOneWidget);
    expect(inInfo(find.text('Where the team talks')), findsOneWidget);
    expect(inInfo(find.text('2 members')), findsOneWidget);
    expect(inInfo(find.text('End-to-end encrypted')), findsOneWidget);
    expect(inInfo(find.byKey(const Key('member.$_bob'))), findsOneWidget);
    expect(inInfo(find.text('Admin')), findsOneWidget);

    await tester.tap(inInfo(find.text('Photos & videos')));
    await tester.pumpAndSettle();
    expect(inInfo(_mediaOf(_photo)), findsOneWidget);
    expect(inInfo(_mediaOf(_video)), findsOneWidget);
    expect(inInfo(_mediaOf(_doc)), findsNothing);

    await tester.tap(inInfo(find.text('Audio')));
    await tester.pumpAndSettle();
    expect(inInfo(find.text('voice.ogg')), findsOneWidget);

    await tester.tap(inInfo(find.text('Documents')));
    await tester.pumpAndSettle();
    expect(inInfo(find.text('contract.pdf')), findsOneWidget);

    await tester.tap(inInfo(find.text('Links')));
    await tester.pumpAndSettle();
    expect(inInfo(find.text('https://oxisoft.io/docs')), findsOneWidget);
    expect(inInfo(find.text('https://example.org/a')), findsOneWidget);

    await tester.tap(find.byKey(const Key('info.back')));
    await tester.pumpAndSettle();
    expect(info, findsNothing);
    expect(find.byKey(const Key('composer.text')), findsOneWidget);

    // Esc goes back too.
    await tester.tap(find.byKey(const Key('chat.title')));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(info, findsNothing);
    expect(find.byKey(const Key('composer.text')), findsOneWidget);
  });

  testWidgets('a direct chat’s info shows the person and whether verified', (
    tester,
  ) async {
    final session = _session();
    session.details[_room] = const RoomDetails(
      roomId: _room,
      name: 'Bob',
      dmUserId: _bob,
      dmUserVerified: false,
      isEncrypted: true,
    );
    await pumpApp(
      tester,
      FakeMatrixClientFactory(saved: [session]),
      size: const Size(400, 800),
    );
    await tester.tap(find.text('Team'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat.title')));
    await tester.pumpAndSettle();
    expect(find.text(_bob), findsWidgets);
    expect(find.text('Not verified'), findsOneWidget);
    expect(find.textContaining('members'), findsNothing);
  });

  testWidgets('Settings set how long media is kept, and clear it', (
    tester,
  ) async {
    final session = _session();
    final prefs = MemoryMediaPrefs();
    await pumpApp(
      tester,
      FakeMatrixClientFactory(saved: [session]),
      size: _wide,
      mediaPrefs: prefs,
    );
    // Applied at start.
    expect(session.retentionDays, 30);

    await tester.tap(find.byKey(const Key('rail.settings')));
    await tester.pumpAndSettle();
    await openSettingsSection(tester, 'media');
    expect(find.text('1 month'), findsOneWidget);
    expect(find.text('1.2 KB'), findsOneWidget);

    await tester.tap(find.byKey(const Key('settings.retention')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Forever').last);
    await tester.pumpAndSettle();
    expect(prefs.retentionDays, isNull);
    expect(session.retentionDays, isNull);

    await tester.tap(find.byKey(const Key('settings.clearCache')));
    await tester.pumpAndSettle();
    expect(session.cacheSize, 0);
    expect(find.text('0 B'), findsOneWidget);
  });

  test('links lose the punctuation around them', () {
    expect(linksIn('see https://a.io/x, and (http://b.io/y)! https://c.io.'), [
      'https://a.io/x',
      'http://b.io/y',
      'https://c.io',
    ]);
  });

  test('a file name can’t leave its folder', () {
    expect(safeFilename('../../etc/passwd'), '.._.._etc_passwd');
    expect(safeFilename('..'), 'file');
    expect(safeFilename('report 2026.pdf'), 'report 2026.pdf');
  });
}
