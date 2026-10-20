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
    await tester.enterText(find.byKey(const Key('joinRoom.address')), 'hall');
    await tester.tap(find.byKey(const Key('joinRoom.join')));
    await tester.pumpAndSettle();
    expect(find.text('That isn’t a room address or link'), findsOneWidget);

    await _menu(tester, 'join');
    await tester.enterText(
      find.byKey(const Key('joinRoom.address')),
      '#hall:acme.com',
    );
    await tester.tap(find.byKey(const Key('joinRoom.join')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('composer.text')), findsOneWidget);
    expect(find.text('Hall'), findsWidgets);
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
