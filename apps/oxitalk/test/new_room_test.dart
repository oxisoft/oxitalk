import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oxitalk/src/app/pick_image.dart';
import 'package:oxitalk/src/features/chat_info/chat_info.dart';
import 'package:oxitalk/src/features/chats/new_room.dart';
import 'package:oxitalk/src/matrix/api/matrix.dart';
import 'package:oxitalk/src/matrix/fakes/fakes.dart';

import 'support/app.dart';
import 'support/png.dart';

const _wide = Size(1400, 900);
const _me = '@me:acme.com';

Future<FakeSession> _open(WidgetTester tester) async {
  final session = FakeSession(
    userId: _me,
    rooms: const [Room(id: '!team:acme.com', name: 'Team')],
  );
  await pumpApp(
    tester,
    FakeMatrixClientFactory(saved: [session]),
    size: _wide,
    pickImage: () async => PickedImage(png, 'image/png'),
  );
  return session;
}

/// Lets the dialogs' search wait pass and their answers arrive.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

Future<void> _menu(WidgetTester tester, String item) async {
  await tester.tap(find.byKey(const Key('newMenu')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('newMenu.$item')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a private room is made with its picture, and opens', (
    tester,
  ) async {
    final session = await _open(tester);
    await _menu(tester, 'room');
    expect(find.byKey(const Key('newRoom.alias')), findsNothing);
    // Nothing to make without a name.
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('newRoom.create')))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const Key('newRoom.picture')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('newRoom.name')), 'Clients');
    await tester.enterText(
      find.byKey(const Key('newRoom.topic')),
      'Where clients talk',
    );
    await tester.tap(find.byKey(const Key('newRoom.create')));
    await tester.pumpAndSettle();
    expect(session.created, {'Clients': (false, null, true, true)});
    expect(find.byKey(const Key('composer.text')), findsOneWidget);
  });

  testWidgets('a public room gets an address from its name, and can go '
      'unencrypted', (tester) async {
    final session = await _open(tester);
    await _menu(tester, 'room');
    await tester.enterText(find.byKey(const Key('newRoom.name')), 'Open Hall!');
    await tester.tap(find.text('Public'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('newRoom.alias')))
          .controller!
          .text,
      'open-hall',
    );
    expect(find.text(':acme.com'), findsOneWidget);
    await tester.tap(find.byKey(const Key('newRoom.encrypted')));
    await tester.tap(find.byKey(const Key('newRoom.create')));
    await tester.pumpAndSettle();
    expect(session.created, {'Open Hall!': (true, 'open-hall', false, false)});
  });

  testWidgets('Join a room takes an address and opens the room', (
    tester,
  ) async {
    final session = await _open(tester);
    session.addresses['#hall:acme.com'] = const Room(
      id: '!hall:acme.com',
      name: 'Hall',
    );
    await _menu(tester, 'join');
    expect(find.byKey(const Key('joinRoom.none')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('joinRoom.address')), 'hall');
    await _settle(tester);
    expect(find.byKey(const Key('joinRoom.typed')), findsNothing);

    await tester.enterText(
      find.byKey(const Key('joinRoom.address')),
      '#hall:acme.com',
    );
    await _settle(tester);
    await tester.tap(find.byKey(const Key('joinRoom.typed')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('composer.text')), findsOneWidget);
    expect(find.text('Hall'), findsWidgets);
  });

  testWidgets('Join a room lists the directory, joined rooms greyed last, '
      'and filters as you type', (tester) async {
    final session = await _open(tester);
    session
      ..publicDirectory = const [
        PublicRoom(
          roomId: '!big:acme.com',
          name: 'Lobby',
          alias: '#lobby:acme.com',
          members: 120,
        ),
        PublicRoom(roomId: '!small:acme.com', name: 'Chess', members: 4),
        PublicRoom(
          roomId: '!team:acme.com',
          name: 'Team',
          members: 9,
          joined: true,
        ),
      ]
      ..addresses['#lobby:acme.com'] = const Room(
        id: '!big:acme.com',
        name: 'Lobby',
      );
    await _menu(tester, 'join');
    final tiles = find.descendant(
      of: find.byKey(const Key('joinRoom')),
      matching: find.byType(ListTile),
    );
    expect(
      [
        for (final tile in tester.widgetList<ListTile>(tiles))
          (tile.key! as ValueKey<String>).value,
      ],
      [
        'joinRoom.room.!big:acme.com',
        'joinRoom.room.!small:acme.com',
        'joinRoom.room.!team:acme.com',
      ],
    );
    expect(find.text('120'), findsOneWidget);
    expect(
      find.ancestor(of: find.text('Joined'), matching: find.byType(Opacity)),
      findsOneWidget,
    );

    await tester.enterText(find.byKey(const Key('joinRoom.address')), 'che');
    await tester.pump();
    expect(tiles, findsOneWidget);
    await _settle(tester);
    expect(find.text('Chess'), findsOneWidget);

    // A room the user is in opens without joining again.
    await tester.enterText(find.byKey(const Key('joinRoom.address')), '');
    await _settle(tester);
    await tester.tap(find.byKey(const Key('joinRoom.room.!team:acme.com')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('composer.text')), findsOneWidget);

    // Any other joins by its address.
    await _menu(tester, 'join');
    await tester.tap(find.byKey(const Key('joinRoom.room.!big:acme.com')));
    await tester.pumpAndSettle();
    expect(session.roomList.first.id, '!big:acme.com');
  });

  testWidgets('New chat offers people you know, then the server’s, and '
      'opens an existing chat', (tester) async {
    final session = await _open(tester);
    session
      ..known = const [
        Person('@alice:acme.com', displayName: 'Alice'),
        Person('@bob:acme.com', displayName: 'Bob'),
      ]
      ..directory = const [
        Person('@alice:acme.com', displayName: 'Alice'),
        Person('@alina:acme.com', displayName: 'Alina'),
      ]
      ..dms['@alice:acme.com'] = '!team:acme.com';
    await _menu(tester, 'chat');
    expect(find.text('People you know'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('newChat.search')), 'ali');
    await tester.pump();
    // Known people filter at once; the server answers after a pause.
    expect(find.text('Bob'), findsNothing);
    expect(find.text('Alina'), findsNothing);
    await _settle(tester);
    expect(find.text('On the server'), findsOneWidget);
    expect(find.text('Alina'), findsOneWidget);
    // Alice is listed once, under the people known.
    expect(find.text('Alice'), findsOneWidget);

    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('composer.text')), findsOneWidget);
    expect(session.roomList.length, 1);

    await _menu(tester, 'chat');
    await tester.enterText(find.byKey(const Key('newChat.search')), 'ali');
    await _settle(tester);
    await tester.tap(find.text('Alina'));
    await tester.pumpAndSettle();
    expect(session.roomList.first.name, '@alina:acme.com');
  });

  testWidgets('people are invited from the room’s members', (tester) async {
    final session = await _open(tester);
    await tester.tap(find.text('Team'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat.title')));
    await tester.pumpAndSettle();
    final info = find.byType(ChatInfoPane);
    await tester.tap(
      find.descendant(of: info, matching: find.byKey(const Key('info.invite'))),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('invite.userId')),
      '@carol:acme.com',
    );
    await tester.tap(find.byKey(const Key('invite.send')));
    await tester.pumpAndSettle();
    expect(session.invited, ['!team:acme.com @carol:acme.com']);
    expect(find.text('Invited @carol:acme.com'), findsOneWidget);
  });

  test('addresses are made from names', () {
    expect(aliasFrom('Team Alpha!'), 'team-alpha');
    expect(aliasFrom('  Über  Café '), 'ber-caf');
    expect(aliasFrom('dev.ops_2'), 'dev.ops_2');
  });
}
