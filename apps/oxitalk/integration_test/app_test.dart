import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:oxitalk/src/app/account_pictures.dart';
import 'package:oxitalk/src/app/app.dart';
import 'package:oxitalk/src/app/collapsed_sections.dart';
import 'package:oxitalk/src/app/diagnostics.dart';
import 'package:oxitalk/src/app/file_actions.dart';
import 'package:oxitalk/src/app/media_prefs.dart';
import 'package:oxitalk/src/app/pick_image.dart';
import 'package:oxitalk/src/app/providers.dart';
import 'package:oxitalk/src/app/ui_prefs.dart';
import 'package:oxitalk/src/features/chat/media_views.dart';
import 'package:oxitalk/src/matrix/api/matrix.dart';
import 'package:oxitalk/src/matrix/fakes/fakes.dart';
import 'package:oxitalk/src/matrix/rust/rust_matrix.dart';
import 'package:oxitalk/src/rust/frb_generated.dart';
import 'package:oxitalk/src/ui/avatar.dart';

import '../test/support/png.dart';

/// A test homeserver from `test-infra/` (Synapse by default; ci.sh also runs it on Tuwunel).
final _homeserver =
    Platform.environment['OXITALK_TEST_HOMESERVER'] ?? 'http://localhost:8008';

const _timeout = Duration(seconds: 90);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(RustLib.init);

  testWidgets('chats with another user over an encrypted DM', (tester) async {
    final alice = await _registerUser();
    final bob = await _registerUser();
    final dataDir = await Directory.systemTemp.createTemp('oxitalk-test');
    addTearDown(() => dataDir.delete(recursive: true));

    // Alice's first device, without UI: its login creates her identity and is verified.
    final aliceFirst =
        await RustMatrixClientFactory(
          secrets: MemorySecretStore(),
          dataDir: () async =>
              Directory('${dataDir.path}/alice-first')..createSync(),
        ).login(
          server: _homeserver,
          username: alice.name,
          password: alice.password,
        );
    addTearDown(() => _bounded(aliceFirst.close));
    await aliceFirst.verificationStatus
        .firstWhere((status) => status == VerificationStatus.verified)
        .timeout(_timeout);
    final requests = StreamIterator(aliceFirst.verificationRequests);
    addTearDown(requests.cancel);

    final files = FakeFileActions();

    // The real app, on the real core; only the keyring is replaced (CI has none).
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clientFactoryProvider.overrideWithValue(
            RustMatrixClientFactory(
              secrets: MemorySecretStore(),
              dataDir: () async =>
                  Directory('${dataDir.path}/alice')..createSync(),
            ),
          ),
          defaultServerProvider.overrideWithValue(_homeserver),
          diagnosticsProvider.overrideWithValue(MemoryDiagnostics()),
          mediaPrefsProvider.overrideWithValue(MemoryMediaPrefs()),
          fileActionsProvider.overrideWithValue(files),
          uiPrefsProvider.overrideWithValue(MemoryUiPrefs()),
          accountPicturesProvider.overrideWithValue(MemoryAccountPictures()),
          collapsedSectionsStoreProvider.overrideWithValue(
            MemoryCollapsedSections(),
          ),
          pickImageProvider.overrideWithValue(
            () async => PickedImage(png, 'image/png'),
          ),
        ],
        child: const OxiTalkApp(),
      ),
    );
    await _pumpUntil(tester, find.text('Sign in'));
    await _type(tester, find.byKey(const Key('login.username')), alice.name);
    await _type(
      tester,
      find.byKey(const Key('login.password')),
      alice.password,
    );
    await tester.tap(find.byKey(const Key('login.submit')));

    // The app is her second device: it has to be verified, here with emoji from the first.
    await _pumpUntil(tester, find.text('Confirm it’s you'));
    await tester.tap(find.byKey(const Key('verify.otherDevice')));
    expect(await _next(tester, requests), isTrue);
    final verification = await aliceFirst.openVerification(
      requests.current.flowId,
    );
    addTearDown(verification.close);
    await verification.accept();
    final compare = await _whileWaiting(
      tester,
      verification.steps.firstWhere((step) => step is VerificationCompare),
    );
    await _pumpUntil(tester, find.text('Compare emoji'));
    for (final emoji in (compare as VerificationCompare).emojis) {
      // The same emoji may come up twice.
      expect(find.text(emoji.symbol), findsWidgets);
    }
    await verification.confirm();
    await tester.tap(find.byKey(const Key('verify.match')));
    await _pumpUntil(tester, find.text('No chats yet'));

    // Bob, on the same Matrix layer, without UI.
    final bobSession = await RustMatrixClientFactory(
      secrets: MemorySecretStore(),
      dataDir: () async => Directory('${dataDir.path}/bob')..createSync(),
    ).login(server: _homeserver, username: bob.name, password: bob.password);
    addTearDown(() => _bounded(bobSession.close));
    await bobSession.setAvatar(png, 'image/png');
    final roomId = await bobSession.createDm('@${alice.name}:localhost');
    final bobTimeline = await bobSession.openTimeline(roomId);
    addTearDown(() => _bounded(bobTimeline.close));

    // Alice sees the invite, joins, and reads Bob's encrypted message.
    await _pumpUntil(tester, find.text('Invitation — tap to join'));
    await tester.tap(find.text('Invitation — tap to join'));
    await _pumpUntil(tester, find.byKey(const Key('composer.text')));
    // Bob's profile picture, downloaded through the core, marks the chat.
    await _pumpUntil(tester, find.byType(PictureAvatar));
    await bobTimeline.send('Hello from Bob');
    await _pumpUntil(tester, find.text('Hello from Bob'));
    // Read while she looks at it: no unread badge on the open chat.
    await _pumpUntil(
      tester,
      find.descendant(
        of: find.widgetWithText(ListTile, bob.name),
        matching: find.text('1'),
      ),
      gone: true,
    );

    // Alice answers through the composer; Bob gets it decrypted.
    await _type(tester, find.byKey(const Key('composer.text')), 'Hi Bob!');
    await tester.tap(find.byKey(const Key('composer.send')));
    await _pumpUntil(tester, find.text('Hi Bob!'));
    await bobTimeline.entries
        .firstWhere(
          (entries) => entries.any(
            (entry) =>
                entry is MessageEntry &&
                entry.body == 'Hi Bob!' &&
                !entry.isOwn,
          ),
        )
        .timeout(_timeout);

    // Markdown goes formatted, as Element sends it: bold here, and at Bob's.
    await _type(
      tester,
      find.byKey(const Key('composer.text')),
      '**Meeting** at *ten*',
    );
    await tester.tap(find.byKey(const Key('composer.send')));
    await bobTimeline.entries
        .firstWhere(
          (entries) => entries.any(
            (e) =>
                e is MessageEntry &&
                e.body == '**Meeting** at *ten*' &&
                (e.formatted?.first.spans.first.bold ?? false),
          ),
        )
        .timeout(_timeout);
    await _pumpUntil(tester, find.text('Meeting at ten'));

    // Alice sends a photo with a caption through 📎; Bob gets it, and reacts to her text.
    files.picked = [PendingFile('office.png', 'image/png', png)];
    await tester.tap(find.byKey(const Key('composer.attach')));
    await _pumpUntil(tester, find.byKey(const Key('send.caption')));
    await _type(tester, find.byKey(const Key('send.caption')), 'Our office');
    await tester.tap(find.byKey(const Key('send.confirm')));
    final bobEntries = await bobTimeline.entries
        .firstWhere(
          (entries) =>
              entries.any(
                (e) => e is MediaEntry && e.media.caption == 'Our office',
              ) &&
              entries.any(
                (e) =>
                    e is MessageEntry &&
                    e.body == 'Hi Bob!' &&
                    e.meta.eventId != null,
              ),
        )
        .timeout(_timeout);
    final hiBob = bobEntries.whereType<MessageEntry>().firstWhere(
      (e) => e.body == 'Hi Bob!',
    );
    await bobTimeline.toggleReaction(hiBob.meta.ref!, '👍');
    await _pumpUntil(tester, find.text('👍 1'));

    // Bob's chat goes to Favorites, then to a new section; the tags round-trip the server.
    final bobTile = find.widgetWithText(ListTile, bob.name);
    await tester.tap(bobTile, buttons: kSecondaryMouseButton);
    await _pumpUntil(tester, find.text('Add to favorites'));
    await _pumpFor(
      tester,
      const Duration(milliseconds: 500),
    ); // the menu opening
    await tester.tap(find.text('Add to favorites'));
    await _pumpUntil(tester, find.byKey(const Key('section.m.favourite')));
    await tester.tap(bobTile, buttons: kSecondaryMouseButton);
    await _pumpUntil(tester, find.text('New section…'));
    await _pumpFor(tester, const Duration(milliseconds: 500));
    await tester.tap(find.text('New section…'));
    await _pumpUntil(tester, find.byKey(const Key('section.name')));
    await _type(tester, find.byKey(const Key('section.name')), 'Customers');
    await tester.tap(find.byKey(const Key('section.save')));
    await _pumpUntil(tester, find.text('Customers'));
    // A room is in one section at a time: Favorites is empty now, so it's gone.
    await _pumpUntil(
      tester,
      find.byKey(const Key('section.m.favourite')),
      gone: true,
    );

    // Bob posts a picture in a new room (over plain HTTP: the app can't send files yet);
    // Alice joins, and the picture shows through the core.
    await _postPicture(bob, invite: '@${alice.name}:localhost');
    await _pumpUntil(tester, find.text('Pictures'));
    await tester.tap(find.text('Pictures'));
    await _pumpUntil(tester, find.text('office.png caption'));
    await _pumpUntil(
      tester,
      find.descendant(
        of: find.byType(MediaPreview),
        matching: find.byType(Image),
      ),
    );

    // New chat finds Bob among the people Alice knows, and opens their chat, not a new one.
    await tester.tap(find.byKey(const Key('newMenu')));
    await _pumpUntil(tester, find.byKey(const Key('newMenu.chat')));
    await _pumpFor(
      tester,
      const Duration(milliseconds: 500),
    ); // the menu opening
    await tester.tap(find.byKey(const Key('newMenu.chat')));
    await _pumpUntil(tester, find.byKey(const Key('newChat.search')));
    await _type(tester, find.byKey(const Key('newChat.search')), bob.name);
    final bobId = '@${bob.name}:localhost';
    await _pumpUntil(tester, find.byKey(Key('newChat.person.$bobId')));
    await tester.tap(find.byKey(Key('newChat.person.$bobId')));
    await _pumpUntil(tester, find.byKey(const Key('newChat')), gone: true);
    await _pumpUntil(tester, find.text('Hi Bob!'));
    expect(find.widgetWithText(ListTile, bob.name), findsOneWidget);

    // Bob opens a public room; Alice finds it in her server's directory and joins.
    final lobby = 'Lobby ${bob.name}';
    final lobbyId = await bobSession.createRoom(
      name: lobby,
      public: true,
      alias: 'lobby-${bob.name}',
      encrypted: false,
    );
    await tester.tap(find.byKey(const Key('newMenu')));
    await _pumpUntil(tester, find.byKey(const Key('newMenu.join')));
    await _pumpFor(tester, const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const Key('newMenu.join')));
    await _pumpUntil(tester, find.byKey(const Key('joinRoom.address')));
    final lobbyTile = find.byKey(Key('joinRoom.room.$lobbyId'));
    // The server lists a new room a moment later; each change of the search asks again.
    for (var attempt = 0; lobbyTile.evaluate().isEmpty; attempt++) {
      if (attempt == 30) throw TestFailure('$lobby never got listed');
      await _type(
        tester,
        find.byKey(const Key('joinRoom.address')),
        attempt.isEven ? 'lobby' : 'Lobby',
      );
      await _pumpFor(tester, const Duration(seconds: 1));
    }
    await tester.tap(lobbyTile);
    await _pumpUntil(tester, find.byKey(const Key('composer.text')));
    await _pumpUntil(tester, find.widgetWithText(ListTile, lobby));

    // Listed again, it is marked Joined.
    await tester.tap(find.byKey(const Key('newMenu')));
    await _pumpUntil(tester, find.byKey(const Key('newMenu.join')));
    await _pumpFor(tester, const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const Key('newMenu.join')));
    await _pumpUntil(
      tester,
      find.descendant(of: lobbyTile, matching: find.text('Joined')),
    );
    await tester.tap(find.text('Cancel'));
    await _pumpUntil(tester, find.byKey(const Key('joinRoom')), gone: true);

    // A second account, for another customer: added from the rail, both stay online.
    final carol = await _registerUser();
    await tester.tap(find.byKey(const Key('account.add')));
    await _pumpUntil(tester, find.text('Add another Matrix account'));
    await _type(tester, find.byKey(const Key('login.username')), carol.name);
    await _type(
      tester,
      find.byKey(const Key('login.password')),
      carol.password,
    );
    await tester.tap(find.byKey(const Key('login.submit')));
    await _pumpUntil(tester, find.text('No chats yet'));
    final carolId = '@${carol.name}:localhost';
    expect(find.byKey(Key('account.$carolId')), findsOneWidget);

    // Ctrl+1 is Alice again, with her chat still open; a message that came meanwhile is there.
    await bobTimeline.send('While you were away');
    await _hotkey(tester, LogicalKeyboardKey.digit1);
    await _pumpUntil(tester, find.text('While you were away'));
    await _hotkey(tester, LogicalKeyboardKey.digit2);
    await _pumpUntil(tester, find.text('No chats yet'));

    // Logging out of Carol leaves Alice; logging out of Alice returns to the login.
    await _logOut(tester);
    await _pumpUntil(tester, find.text('While you were away'));
    expect(find.byKey(Key('account.$carolId')), findsNothing);

    // Alice sets her profile picture; the rail shows it.
    final aliceId = '@${alice.name}:localhost';
    await tester.tap(find.byKey(const Key('rail.settings')));
    await _pumpUntil(tester, find.byKey(const Key('settings.setAvatar')));
    await tester.tap(find.byKey(const Key('settings.setAvatar')));
    await _pumpUntil(tester, find.byKey(const Key('settings.removeAvatar')));
    await tester.tap(find.byType(BackButton));
    await _pumpUntil(
      tester,
      find.descendant(
        of: find.byKey(Key('account.$aliceId')),
        matching: find.byType(PictureAvatar),
      ),
    );

    await _logOut(tester);
    await _pumpUntil(tester, find.text('Sign in'));
  });
}

Future<void> _logOut(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('account.dropdown')));
  await _pumpUntil(tester, find.byKey(const Key('accountMenu.logout')));
  await _pumpFor(tester, const Duration(milliseconds: 500)); // the menu opening
  await tester.tap(find.byKey(const Key('accountMenu.logout')));
}

/// Ctrl+[key], as the user presses it.
Future<void> _hotkey(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
}

/// Types [text] into the text field [field], checking that it took. A desktop app gives up
/// keyboard focus while its window isn't the active one, which a compositor may refuse while
/// the user works in another window; the test then says the app is in front.
Future<void> _type(WidgetTester tester, Finder field, String text) async {
  final editable = find.descendant(
    of: field,
    matching: find.byType(EditableText),
  );
  for (var attempt = 0; attempt < 5; attempt++) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.enterText(field, text);
    await _pumpFor(tester, const Duration(milliseconds: 200));
    if (tester.widget<EditableText>(editable).controller.text == text) return;
  }
  throw TestFailure('Could not type “$text” into $field');
}

/// Runs a teardown [body], failing instead of hanging if it never completes.
Future<void> _bounded(FutureOr<void> Function() body) =>
    Future.sync(body).timeout(_timeout);

/// Logs [user] in over HTTP and makes a room named Pictures with [invite] in it, holding a
/// picture with a caption.
Future<void> _postPicture(
  ({String name, String password}) user, {
  required String invite,
}) async {
  final login = await _http('POST', '/_matrix/client/v3/login', {
    'type': 'm.login.password',
    'identifier': {'type': 'm.id.user', 'user': user.name},
    'password': user.password,
  });
  final token = login['access_token']! as String;
  final room = await _http('POST', '/_matrix/client/v3/createRoom', {
    'name': 'Pictures',
    'invite': [invite],
  }, token: token);
  final upload = await _http(
    'POST',
    '/_matrix/media/v3/upload?filename=office.png',
    png,
    token: token,
    contentType: ContentType('image', 'png'),
  );
  await _http(
    'PUT',
    '/_matrix/client/v3/rooms/${Uri.encodeComponent(room['room_id']! as String)}'
        '/send/m.room.message/picture1',
    {
      'msgtype': 'm.image',
      'body': 'office.png caption',
      'filename': 'office.png',
      'url': upload['content_uri'],
      'info': {'mimetype': 'image/png', 'w': 64, 'h': 64, 'size': png.length},
    },
    token: token,
  );
}

/// One request to the test server; [body] is JSON, or raw bytes with [contentType].
Future<Map<String, Object?>> _http(
  String method,
  String path,
  Object body, {
  String? token,
  ContentType? contentType,
}) async {
  final client = HttpClient();
  try {
    final request = await client.openUrl(
      method,
      Uri.parse('$_homeserver$path'),
    );
    if (token != null) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    request.headers.contentType = contentType ?? ContentType.json;
    final bytes = body is List<int> ? body : utf8.encode(jsonEncode(body));
    request
      ..contentLength = bytes.length
      ..add(bytes);
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    if (response.statusCode != HttpStatus.ok) {
      throw StateError('$method $path: ${response.statusCode} $text');
    }
    return jsonDecode(text) as Map<String, Object?>;
  } finally {
    client.close();
  }
}

/// Registers a fresh user (open registration on the test server only).
Future<({String name, String password})> _registerUser() async {
  final name = 'user${DateTime.now().microsecondsSinceEpoch}';
  final password = '$name-password';
  final client = HttpClient();
  try {
    final request = await client.postUrl(
      Uri.parse('$_homeserver/_matrix/client/v3/register'),
    );
    request.headers.contentType = ContentType.json;
    request.write(
      jsonEncode({
        'username': name,
        'password': password,
        'auth': {'type': 'm.login.dummy'},
      }),
    );
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode != HttpStatus.ok) {
      throw StateError(
        'registering $name failed: ${response.statusCode} $body',
      );
    }
  } finally {
    client.close();
  }
  return (name: name, password: password);
}

/// Waits for [future] while pumping frames, so the app keeps running meanwhile.
Future<T> _whileWaiting<T>(WidgetTester tester, Future<T> future) async {
  var done = false;
  final settled = future.whenComplete(() => done = true);
  final deadline = DateTime.now().add(_timeout);
  while (!done) {
    if (DateTime.now().isAfter(deadline)) {
      settled.ignore();
      throw TestFailure('Timed out waiting for the core');
    }
    await _pumpFor(tester, const Duration(milliseconds: 100));
  }
  return settled;
}

/// The next item of [items], while the app keeps running.
Future<bool> _next<T>(WidgetTester tester, StreamIterator<T> items) =>
    _whileWaiting(tester, items.moveNext());

/// Pumps frames while [duration] of real time passes.
Future<void> _pumpFor(WidgetTester tester, Duration duration) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 50));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
  }
}

/// Pumps frames, letting real time pass, until [finder] finds something (or, with [gone],
/// nothing).
Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  bool gone = false,
}) async {
  final deadline = DateTime.now().add(_timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty != gone) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
  }
  throw TestFailure('Timed out waiting for $finder');
}
