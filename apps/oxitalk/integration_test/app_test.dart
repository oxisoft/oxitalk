import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:oxitalk/src/app/app.dart';
import 'package:oxitalk/src/app/providers.dart';
import 'package:oxitalk/src/matrix/api/matrix.dart';
import 'package:oxitalk/src/matrix/fakes/fakes.dart';
import 'package:oxitalk/src/matrix/rust/rust_matrix.dart';
import 'package:oxitalk/src/rust/frb_generated.dart';

/// The Synapse test homeserver from `test-infra/`, which `scripts/ci.sh` starts.
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
        ],
        child: const OxiTalkApp(),
      ),
    );
    await _pumpUntil(tester, find.text('Sign in'));
    await tester.enterText(find.byKey(const Key('login.username')), alice.name);
    await tester.enterText(
      find.byKey(const Key('login.password')),
      alice.password,
    );
    await tester.tap(find.byKey(const Key('login.submit')));
    await _pumpUntil(tester, find.text('No chats yet'));

    // Bob, on the same Matrix layer, without UI.
    final bobSession = await RustMatrixClientFactory(
      secrets: MemorySecretStore(),
      dataDir: () async => Directory('${dataDir.path}/bob')..createSync(),
    ).login(server: _homeserver, username: bob.name, password: bob.password);
    addTearDown(() => _bounded(bobSession.close));
    final roomId = await bobSession.createDm('@${alice.name}:localhost');
    final bobTimeline = await bobSession.openTimeline(roomId);
    addTearDown(() => _bounded(bobTimeline.close));

    // Alice sees the invite, joins, and reads Bob's encrypted message.
    await _pumpUntil(tester, find.text('Invitation — tap to join'));
    await tester.tap(find.text('Invitation — tap to join'));
    await _pumpUntil(tester, find.byKey(const Key('composer.text')));
    await bobTimeline.send('Hello from Bob');
    await _pumpUntil(tester, find.text('Hello from Bob'));

    // Alice answers through the composer; Bob gets it decrypted.
    await tester.enterText(find.byKey(const Key('composer.text')), 'Hi Bob!');
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

    // Logging out stops the session and returns to the login.
    await tester.tap(find.byTooltip('Menu'));
    await _pumpUntil(tester, find.text('Log out'));
    await _pumpFor(
      tester,
      const Duration(milliseconds: 500),
    ); // the menu opening
    await tester.tap(find.text('Log out'));
    await _pumpUntil(tester, find.text('Sign in'));
  });
}

/// Runs a teardown [body], failing instead of hanging if it never completes.
Future<void> _bounded(FutureOr<void> Function() body) =>
    Future.sync(body).timeout(_timeout);

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

/// Pumps frames, letting real time pass, until [finder] finds something.
Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  final deadline = DateTime.now().add(_timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
  }
  throw TestFailure('Timed out waiting for $finder');
}
