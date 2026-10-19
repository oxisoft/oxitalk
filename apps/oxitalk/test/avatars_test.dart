import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oxitalk/src/app/account_pictures.dart';
import 'package:oxitalk/src/app/pick_image.dart';
import 'package:oxitalk/src/matrix/api/matrix.dart';
import 'package:oxitalk/src/matrix/fakes/fakes.dart';
import 'package:oxitalk/src/ui/avatar.dart';

import 'support/app.dart';
import 'support/png.dart';

const _wide = Size(1200, 800);
const _me = '@me:acme.com';
const _avatar = 'mxc://acme.com/me';
const _bobAvatar = 'mxc://acme.com/bob';

Finder _picture(Finder of) =>
    find.descendant(of: of, matching: find.byType(PictureAvatar));

FakeSession _session({Profile profile = const Profile()}) {
  final session = FakeSession(
    userId: _me,
    profile: profile,
    rooms: const [
      Room(id: '!dm:acme.com', name: 'Bob', avatarUrl: _bobAvatar, isDm: true),
      Room(id: '!team:acme.com', name: 'Team'),
    ],
  );
  session.pictures[_bobAvatar] = png;
  session.pictures[_avatar] = png;
  return session;
}

void main() {
  testWidgets('rooms show their picture, or initials without one', (
    tester,
  ) async {
    await pumpApp(tester, FakeMatrixClientFactory(saved: [_session()]));
    expect(_picture(find.widgetWithText(ListTile, 'Bob')), findsOneWidget);
    expect(_picture(find.widgetWithText(ListTile, 'Team')), findsNothing);
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Team'),
        matching: find.text('T'),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'in a group, the sender’s picture is beside their last message in a row',
    (tester) async {
      final session = _session();
      session.timelines['!team:acme.com'] = FakeTimeline(
        ownUserId: _me,
        entries: [
          for (final (i, body) in ['one', 'two'].indexed)
            MessageEntry(
              id: 'bob$i',
              sender: '@bob:acme.com',
              senderName: 'Bob',
              senderAvatarUrl: _bobAvatar,
              time: DateTime(2026, 10, 19, 12, i),
              body: body,
            ),
          MessageEntry(
            id: 'mine',
            sender: _me,
            time: DateTime(2026, 10, 19, 12, 5),
            body: 'three',
            isOwn: true,
          ),
        ],
      );
      await pumpApp(
        tester,
        FakeMatrixClientFactory(saved: [session]),
        size: _wide,
      );
      await tester.tap(find.text('Team'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('senderAvatar.bob0')), findsNothing);
      expect(
        _picture(find.byKey(const Key('senderAvatar.bob1'))),
        findsOneWidget,
      );
      expect(find.byKey(const Key('senderAvatar.mine')), findsNothing);
    },
  );

  testWidgets('a direct chat shows no sender pictures', (tester) async {
    final session = _session();
    session.timelines['!dm:acme.com'] = FakeTimeline(
      ownUserId: _me,
      entries: [
        MessageEntry(
          id: 'bob0',
          sender: '@bob:acme.com',
          senderAvatarUrl: _bobAvatar,
          time: DateTime(2026, 10, 19, 12),
          body: 'hi',
        ),
      ],
    );
    await pumpApp(
      tester,
      FakeMatrixClientFactory(saved: [session]),
      size: _wide,
    );
    await tester.tap(find.text('Bob'));
    await tester.pumpAndSettle();
    expect(find.text('hi'), findsOneWidget);
    expect(find.byKey(const Key('senderAvatar.bob0')), findsNothing);
  });

  testWidgets('the rail shows the profile picture and the server’s icon', (
    tester,
  ) async {
    await pumpApp(
      tester,
      FakeMatrixClientFactory(
        saved: [_session(profile: const Profile(avatarUrl: _avatar))],
      ),
      size: _wide,
      pictures: MemoryAccountPictures()..serverIcons['acme.com'] = png,
    );
    expect(_picture(find.byKey(const Key('account.$_me'))), findsNWidgets(2));
    expect(
      _picture(find.byKey(const Key('serverIcon.acme.com')).first),
      findsOneWidget,
    );
    expect(find.byKey(const Key('localPicture.$_me')), findsNothing);
  });

  testWidgets('a picture on this device replaces the profile picture', (
    tester,
  ) async {
    final pictures = MemoryAccountPictures()..locals[_me] = png;
    await pumpApp(
      tester,
      FakeMatrixClientFactory(
        saved: [_session(profile: const Profile(avatarUrl: _avatar))],
      ),
      size: _wide,
      pictures: pictures,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('account.$_me')),
        matching: find.byKey(const Key('localPicture.$_me')),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('rail.settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings.resetLocalPicture')));
    await tester.pumpAndSettle();
    expect(pictures.locals, isEmpty);
    expect(find.byKey(const Key('localPicture.$_me')), findsNothing);
  });

  testWidgets('without a website icon the server shows its first letter', (
    tester,
  ) async {
    await pumpApp(
      tester,
      FakeMatrixClientFactory(saved: [_session()]),
      size: _wide,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('serverIcon.acme.com')).first,
        matching: find.text('A'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('Settings change and remove the profile picture and the one '
      'on this device', (tester) async {
    final session = _session();
    final pictures = MemoryAccountPictures();
    await pumpApp(
      tester,
      FakeMatrixClientFactory(saved: [session]),
      size: _wide,
      pictures: pictures,
      pickImage: () async => PickedImage(png, 'image/png'),
    );
    await tester.tap(find.byKey(const Key('rail.settings')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings.removeAvatar')), findsNothing);
    expect(find.byKey(const Key('settings.resetLocalPicture')), findsNothing);

    await tester.tap(find.byKey(const Key('settings.setAvatar')));
    await tester.pumpAndSettle();
    final url = session.ownProfile.value.avatarUrl;
    expect(url, isNotNull);
    expect(session.pictures[url], png);

    await tester.tap(find.byKey(const Key('settings.removeAvatar')));
    await tester.pumpAndSettle();
    expect(session.ownProfile.value.avatarUrl, isNull);

    await tester.tap(find.byKey(const Key('settings.setLocalPicture')));
    await tester.pumpAndSettle();
    expect(pictures.locals[_me], png);
    expect(find.byKey(const Key('localPicture.$_me')), findsWidgets);
  });

  testWidgets('logging out forgets the picture on this device', (tester) async {
    final pictures = MemoryAccountPictures()..locals[_me] = png;
    await pumpApp(
      tester,
      FakeMatrixClientFactory(saved: [_session()]),
      pictures: pictures,
    );
    await pickFromAccountMenu(tester, 'accountMenu.logout');
    expect(pictures.locals, isEmpty);
  });
}
