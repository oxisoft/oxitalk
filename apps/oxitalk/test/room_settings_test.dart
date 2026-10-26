import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oxitalk/src/app/pick_image.dart';
import 'package:oxitalk/src/features/chat_info/chat_info.dart';
import 'package:oxitalk/src/features/chat_info/room_settings.dart';
import 'package:oxitalk/src/matrix/api/matrix.dart';
import 'package:oxitalk/src/matrix/fakes/fakes.dart';

import 'support/app.dart';
import 'support/png.dart';

const _me = '@me:acme.com';
const _room = '!team:acme.com';

/// Opens the info of the room "Team" on a wide window, with [settings] (the user may
/// change everything unless [permissions] says otherwise).
Future<FakeSession> _openInfo(
  WidgetTester tester, {
  RoomPermissions permissions = RoomPermissions.all,
  bool encrypted = true,
  RoomJoinRule joinRule = RoomJoinRule.invite,
  bool knockSupported = true,
  Size size = const Size(1400, 900),
  PickImage? pickImage,
}) async {
  final session =
      FakeSession(
          userId: _me,
          rooms: [Room(id: _room, name: 'Team', isEncrypted: encrypted)],
        )
        ..details[_room] = RoomDetails(
          roomId: _room,
          name: 'Team',
          topic: 'Old topic',
          isEncrypted: encrypted,
          joinedMembers: 3,
        );
  session.settingsOf(_room).value = RoomSettings(
    roomId: _room,
    name: 'Team',
    topic: 'Old topic',
    isEncrypted: encrypted,
    joinRule: joinRule,
    serverName: 'acme.com',
    knockSupported: knockSupported,
    permissions: permissions,
  );
  await pumpApp(
    tester,
    FakeMatrixClientFactory(saved: [session]),
    size: size,
    pickImage: pickImage,
  );
  await tester.tap(find.text('Team'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('chat.title')));
  await tester.pumpAndSettle();
  return session;
}

Finder _inInfo(Finder finder) =>
    find.descendant(of: find.byType(ChatInfoPane), matching: finder);

Future<void> _openSecurity(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('info.security')));
  await tester.pumpAndSettle();
  expect(find.byType(RoomSecurityPane), findsOneWidget);
}

void main() {
  testWidgets('the name and topic are edited and show in the info', (
    tester,
  ) async {
    final session = await _openInfo(tester);
    await tester.tap(find.byKey(const Key('info.edit')));
    await tester.pumpAndSettle();
    expect(find.byType(EditRoomDetailsDialog), findsOneWidget);

    await tester.enterText(find.byKey(const Key('editRoom.name')), 'Crew');
    await tester.enterText(
      find.byKey(const Key('editRoom.topic')),
      'Where the crew talks',
    );
    await tester.tap(find.byKey(const Key('editRoom.save')));
    await tester.pumpAndSettle();

    expect(find.byType(EditRoomDetailsDialog), findsNothing);
    expect(session.settingsCalls, [
      'name $_room Crew',
      'topic $_room Where the crew talks',
    ]);
    expect(_inInfo(find.text('Crew')), findsOneWidget);
    expect(_inInfo(find.text('Where the crew talks')), findsOneWidget);
  });

  testWidgets('a change made elsewhere shows in the open info', (tester) async {
    final session = await _openInfo(tester);
    final latest = session.settingsOf(_room);
    latest.value = latest.value.copyWith(
      name: () => 'Renamed elsewhere',
      topic: () => null,
    );
    await tester.pumpAndSettle();
    expect(_inInfo(find.text('Renamed elsewhere')), findsOneWidget);
    expect(_inInfo(find.text('Old topic')), findsNothing);
  });

  testWidgets('unchanged fields are not sent, a picture is', (tester) async {
    final session = await _openInfo(
      tester,
      pickImage: () async => PickedImage(png, 'image/png'),
    );
    await tester.tap(find.byKey(const Key('info.edit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('editRoom.choosePicture')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('editRoom.removePicture')), findsOneWidget);
    await tester.tap(find.byKey(const Key('editRoom.save')));
    await tester.pumpAndSettle();
    expect(session.settingsCalls, ['avatar $_room image/png']);
    expect(session.settingsOf(_room).value.avatarUrl, isNotNull);

    await tester.tap(find.byKey(const Key('info.edit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('editRoom.removePicture')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('editRoom.save')));
    await tester.pumpAndSettle();
    expect(session.settingsCalls.last, 'removeAvatar $_room');
    expect(session.settingsOf(_room).value.avatarUrl, isNull);
  });

  testWidgets('a refused change keeps the dialog open with why', (
    tester,
  ) async {
    final session = await _openInfo(tester);
    await tester.tap(find.byKey(const Key('info.edit')));
    await tester.pumpAndSettle();
    session.settingsFailure = const MatrixFailure(FailureKind.forbidden);
    await tester.enterText(find.byKey(const Key('editRoom.name')), 'Crew');
    await tester.tap(find.byKey(const Key('editRoom.save')));
    await tester.pumpAndSettle();
    expect(find.byType(EditRoomDetailsDialog), findsOneWidget);
    expect(
      find.text('You aren’t allowed to change the name in this room.'),
      findsOneWidget,
    );
  });

  testWidgets('only what the power level allows can be edited', (tester) async {
    await _openInfo(tester, permissions: const RoomPermissions(topic: true));
    await tester.tap(find.byKey(const Key('info.edit')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byKey(const Key('editRoom.name'))).enabled,
      isFalse,
    );
    expect(
      tester.widget<TextField>(find.byKey(const Key('editRoom.topic'))).enabled,
      isTrue,
    );
    expect(find.byKey(const Key('editRoom.choosePicture')), findsNothing);
  });

  testWidgets('without the power level, nothing is editable', (tester) async {
    final session = await _openInfo(
      tester,
      permissions: const RoomPermissions(),
      encrypted: false,
    );
    expect(find.byKey(const Key('info.edit')), findsNothing);
    await _openSecurity(tester);
    expect(find.byKey(const Key('security.join.readOnly')), findsOneWidget);
    expect(find.byKey(const Key('security.history.readOnly')), findsOneWidget);
    expect(find.byType(RadioListTile<RoomJoinRule>), findsNothing);
    expect(find.text('Invite only'), findsOneWidget);
    expect(find.text('Members, since this option was chosen'), findsOneWidget);
    expect(find.byKey(const Key('security.enableEncryption')), findsNothing);
    expect(
      find.text('You aren’t allowed to turn encryption on.'),
      findsOneWidget,
    );
    expect(session.settingsCalls, isEmpty);
  });

  testWidgets('encryption is enabled only after confirming, for good', (
    tester,
  ) async {
    final session = await _openInfo(tester, encrypted: false);
    expect(_inInfo(find.text('Invite only · Not encrypted')), findsOneWidget);
    await _openSecurity(tester);
    expect(find.text('Not encrypted'), findsOneWidget);

    await tester.tap(find.byKey(const Key('security.enableEncryption')));
    await tester.pumpAndSettle();
    expect(find.text('Enable encryption?'), findsOneWidget);
    expect(find.textContaining('can’t be turned off again'), findsOneWidget);
    // The confirm is a plain primary button: not a destructive one.
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('security.confirmEncryption')),
          )
          .style,
      isNull,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(session.settingsCalls, isEmpty);

    await tester.tap(find.byKey(const Key('security.enableEncryption')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('security.confirmEncryption')));
    await tester.pumpAndSettle();
    expect(session.settingsCalls, ['encryption $_room']);
    expect(find.text('End-to-end encryption is on'), findsOneWidget);
    expect(find.byKey(const Key('security.enableEncryption')), findsNothing);

    await tester.tap(find.byKey(const Key('security.back')));
    await tester.pumpAndSettle();
    expect(_inInfo(find.text('End-to-end encrypted')), findsOneWidget);
  });

  testWidgets(
    'who can join changes; a public room gets address and directory',
    (tester) async {
      final session = await _openInfo(tester);
      await _openSecurity(tester);
      expect(find.byKey(const Key('security.join.knock')), findsOneWidget);
      expect(find.byKey(const Key('security.address')), findsNothing);
      expect(
        find.byKey(const Key('security.history.worldReadable')),
        findsNothing,
      );

      await tester.tap(find.byKey(const Key('security.join.public')));
      await tester.pumpAndSettle();
      expect(session.settingsCalls, ['joinRule $_room public']);
      expect(find.text('No address yet'), findsOneWidget);
      expect(
        find.byKey(const Key('security.history.worldReadable')),
        findsOneWidget,
      );
      final directory = find.byKey(const Key('security.published'));
      expect(tester.widget<SwitchListTile>(directory).value, isFalse);
      await tester.tap(directory);
      await tester.pumpAndSettle();
      expect(session.published, {_room});
      expect(tester.widget<SwitchListTile>(directory).value, isTrue);

      await tester.tap(find.byKey(const Key('security.history.worldReadable')));
      await tester.pumpAndSettle();
      expect(session.settingsCalls.last, 'history $_room worldReadable');

      // Back to invite only: anyone reading becomes the members.
      await tester.tap(find.byKey(const Key('security.join.invite')));
      await tester.pumpAndSettle();
      expect(session.settingsOf(_room).value.history, RoomHistory.shared);
      expect(find.byKey(const Key('security.address')), findsNothing);
    },
  );

  testWidgets('ask to join is offered only where the room version has it', (
    tester,
  ) async {
    await _openInfo(tester, knockSupported: false);
    await _openSecurity(tester);
    expect(find.byKey(const Key('security.join.invite')), findsOneWidget);
    expect(find.byKey(const Key('security.join.knock')), findsNothing);
  });

  testWidgets('a main address is added; a taken or malformed one is refused', (
    tester,
  ) async {
    final session = await _openInfo(tester, joinRule: RoomJoinRule.public)
      ..takenAddresses.add('#taken:acme.com');
    await _openSecurity(tester);
    await tester.tap(find.byKey(const Key('security.changeAddress')));
    await tester.pumpAndSettle();

    final field = find.byKey(const Key('security.addressField'));
    await tester.enterText(field, 'two words');
    await tester.tap(find.byKey(const Key('security.saveAddress')));
    await tester.pumpAndSettle();
    expect(find.text('Use a name without spaces, # or :.'), findsOneWidget);

    await tester.enterText(field, 'taken');
    await tester.tap(find.byKey(const Key('security.saveAddress')));
    await tester.pumpAndSettle();
    expect(find.text('Another room has this address.'), findsOneWidget);

    await tester.enterText(field, 'team');
    await tester.tap(find.byKey(const Key('security.saveAddress')));
    await tester.pumpAndSettle();
    expect(session.settingsCalls, ['address $_room #team:acme.com']);
    expect(find.text('#team:acme.com'), findsOneWidget);
  });

  testWidgets('on a phone, security is a page of its own with back to info', (
    tester,
  ) async {
    await _openInfo(tester, size: const Size(400, 800));
    await _openSecurity(tester);
    await tester.tap(find.byKey(const Key('security.back')));
    await tester.pumpAndSettle();
    expect(find.byType(ChatInfoPane), findsOneWidget);
    expect(find.byType(RoomSecurityPane), findsNothing);
  });
}
