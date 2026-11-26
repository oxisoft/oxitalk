/// A voice call between two real app sessions through a real LiveKit SFU.
///
/// Needs the RTC test pod (`test-infra/rtc/up.sh`) and a microphone that gives sound; run it
/// with `scripts/call-e2e.sh`, which brings up the pod and a fake microphone (a 440 Hz tone on
/// a null sink) and tears both down. Skipped unless `OXITALK_TEST_RTC=1`, so the plain
/// `flutter test integration_test` of ci.sh (no LiveKit there) passes over it.
///
/// Alice is the real app (UI, Riverpod, CallController, LiveKitCallMedia). Bob is a second
/// set of the same providers in the same process, without a UI: his IncomingCalls takes
/// the ring and his CallController answers it, with his own LiveKitCallMedia. Nothing of
/// the call is faked: Matrix signalling on the homeserver, the LiveKit token from
/// lk-jwt-service, media through LiveKit with frame encryption (keys over Olm to-device).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:oxitalk/src/app/account_pictures.dart';
import 'package:oxitalk/src/app/app.dart';
import 'package:oxitalk/src/app/collapsed_sections.dart';
import 'package:oxitalk/src/app/diagnostics.dart';
import 'package:oxitalk/src/app/file_actions.dart';
import 'package:oxitalk/src/app/media_prefs.dart';
import 'package:oxitalk/src/app/pick_image.dart';
import 'package:oxitalk/src/app/providers.dart';
import 'package:oxitalk/src/app/ui_prefs.dart';
import 'package:oxitalk/src/features/calls/call_controller.dart';
import 'package:oxitalk/src/features/calls/call_media.dart';
import 'package:oxitalk/src/matrix/api/matrix.dart';
import 'package:oxitalk/src/matrix/fakes/fakes.dart';
import 'package:oxitalk/src/matrix/rust/rust_matrix.dart';
import 'package:oxitalk/src/rust/frb_generated.dart';
import 'package:oxitalk/src/util/log.dart';

import '../test/support/call_fakes.dart';
import '../test/support/png.dart';

final _homeserver =
    Platform.environment['OXITALK_TEST_HOMESERVER'] ?? 'http://localhost:8008';
final _rtc = Platform.environment['OXITALK_TEST_RTC'] == '1';

/// Joining LiveKit takes 10-16 s on the test pod (ICE over rootless podman).
const _timeout = Duration(seconds: 90);

/// The app's log lines (calls, accounts), both sessions; printed as they come.
final _log = <String>[];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await RustLib.init();
    // The core's log too (SDK, calls), when asked: OXITALK_CALL_E2E_LOGS=<dir>.
    final logs = Platform.environment['OXITALK_CALL_E2E_LOGS'];
    if (logs != null) {
      await RustDiagnostics.start(Directory(logs)..createSync(recursive: true));
    }
    final core = logSink;
    logSink = (level, target, message) {
      core(level, target, message);
      final line =
          '${DateTime.now().toIso8601String()} ${level.name} '
          '$target $message';
      _log.add(line);
      // ignore: avoid_print
      print('APPLOG $line');
    };
  });

  testWidgets(
    'a voice call is answered, both media connect through LiveKit, encrypted '
    'both ways with sound, and hanging up ends it on both sides; then the other '
    'calls back at once and it works again; then a declined call ends for the '
    'caller',
    (tester) async {
      final alice = await _registerUser('alice');
      final bob = await _registerUser('bob');
      final aliceId = '@${alice.name}:localhost';
      final bobId = '@${bob.name}:localhost';
      final dataDir = await Directory.systemTemp.createTemp('oxitalk-call');
      addTearDown(() => dataDir.delete(recursive: true));

      // Bob: the app's providers without its UI.
      final bobRinger = FakeRinger();
      final bobApp = ProviderContainer(
        overrides: _overrides('${dataDir.path}/bob', ringer: bobRinger),
      );
      addTearDown(bobApp.dispose);
      // What the app's UI keeps alive for him: the rings (the shell shows them) and the
      // chat list (CallController reads it to end a call of two when the other leaves).
      bobApp
        ..listen(incomingCallsProvider, (_, _) {})
        ..listen(callControllerProvider, (_, _) {});
      await bobApp.read(accountsProvider.future);
      await bobApp
          .read(accountsProvider.notifier)
          .login(
            server: _homeserver,
            username: bob.name,
            password: bob.password,
          );
      bobApp.listen(roomsProvider(bobId), (_, _) {});
      final bobSession = bobApp.read(accountsProvider).value!.byId(bobId)!;

      // Alice: the real app.
      final aliceRinger = FakeRinger();
      final aliceApp = ProviderContainer(
        overrides: _overrides('${dataDir.path}/alice', ringer: aliceRinger),
      );
      addTearDown(aliceApp.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: aliceApp,
          child: const OxiTalkApp(),
        ),
      );
      await _pumpUntil(tester, find.text('Sign in'));
      await _whileWaiting(
        tester,
        aliceApp
            .read(accountsProvider.notifier)
            .login(
              server: _homeserver,
              username: alice.name,
              password: alice.password,
            ),
      );
      await _pumpUntil(tester, find.text('No chats yet'));

      // Bob opens a DM; Alice accepts it in the app.
      final roomId = await bobSession.createDm(aliceId);
      await _pumpUntil(tester, find.text('Invitation — tap to see it'));
      await tester.tap(find.text('Invitation — tap to see it'));
      await _pumpUntil(tester, find.byKey(const Key('invite.accept')));
      await tester.tap(find.byKey(const Key('invite.accept')));
      await _pumpUntil(tester, find.byKey(const Key('composer.text')));
      // Both see it as a DM (a DM rings, and a DM's call ends when the other leaves).
      await _until(
        tester,
        'the chat is a DM for both',
        () => _isDm(aliceApp, aliceId, roomId) && _isDm(bobApp, bobId, roomId),
      );

      // Alice calls from the chat's header.
      await _pumpUntil(tester, find.byKey(const Key('chat.voiceCall')));
      var since = _log.length;
      await tester.tap(find.byKey(const Key('chat.voiceCall')));
      await _pumpUntil(tester, find.byKey(const Key('call.screen')));
      _step('alice called');

      // Bob's app rings; he answers with voice, as his card's Voice button does.
      await _until(
        tester,
        'Bob rings',
        () => bobApp.read(incomingCallsProvider).ringing.isNotEmpty,
      );
      final ringing = bobApp.read(incomingCallsProvider).ringing.single;
      expect(ringing.call.roomId, roomId);
      expect(ringing.call.senderId, aliceId);
      expect(ringing.call.ring, isTrue);
      expect(ringing.call.intent, CallIntent.audio);
      expect(bobRinger.ringing, isTrue);
      _step('bob rings');
      unawaited(
        bobApp
            .read(incomingCallsProvider.notifier)
            .accept(ringing, CallIntent.audio),
      );
      await _until(tester, 'Bob stops ringing', () => !bobRinger.ringing);

      await _expectTalking(
        tester,
        aliceApp,
        bobApp,
        aliceId: aliceId,
        bobId: bobId,
        since: since,
      );

      // Alice hangs up: her call ends, Bob's ends by itself (a DM's call ends when the other
      // leaves), and the room's call state has nobody left.
      await tester.tap(find.byKey(const Key('call.hangUp')));
      await _pumpUntil(
        tester,
        find.byKey(const Key('call.screen')),
        gone: true,
      );
      expect(aliceApp.read(callControllerProvider), isNull);
      await _until(
        tester,
        'Bob’s call ended',
        () => bobApp.read(callControllerProvider) == null,
      );
      _step('both ended');
      final calls = StreamIterator(bobSession.roomCall(roomId));
      addTearDown(calls.cancel);
      while (true) {
        expect(await _whileWaiting(tester, calls.moveNext()), isTrue);
        if (!calls.current.isActive) break;
      }
      expect(bobRinger.ringing, isFalse);
      expect(aliceRinger.starts, 0);
      _step('room call empty');

      // Bob calls back at once (within LiveKit's departure timeout of the last call's room,
      // which lk-jwt-service may hand out again), and Alice answers on her incoming-call card.
      since = _log.length;
      unawaited(
        bobApp
            .read(callControllerProvider.notifier)
            .join(
              bobId,
              roomId,
              intent: CallIntent.audio,
              notify: CallNotify.ring,
            ),
      );
      await _pumpUntil(tester, find.byKey(const Key('call.incoming')));
      expect(find.text('is calling you'), findsOneWidget);
      expect(aliceRinger.ringing, isTrue);
      _step('alice rings');
      await tester.tap(find.byKey(const Key('call.acceptVoice')));
      await _pumpUntil(tester, find.byKey(const Key('call.screen')));
      expect(find.byKey(const Key('call.incoming')), findsNothing);
      await _until(tester, 'Alice stops ringing', () => !aliceRinger.ringing);
      await _expectTalking(
        tester,
        aliceApp,
        bobApp,
        aliceId: aliceId,
        bobId: bobId,
        since: since,
      );

      // This time Bob hangs up; Alice's call ends by itself and her call screen goes.
      await _whileWaiting(
        tester,
        bobApp.read(callControllerProvider.notifier).hangUp(),
      );
      await _pumpUntil(
        tester,
        find.byKey(const Key('call.screen')),
        gone: true,
      );
      expect(aliceApp.read(callControllerProvider), isNull);
      // The room's call state: it had both in it again, and then nobody.
      do {
        expect(await _whileWaiting(tester, calls.moveNext()), isTrue);
      } while (!calls.current.isActive);
      do {
        expect(await _whileWaiting(tester, calls.moveNext()), isTrue);
      } while (calls.current.isActive);
      _step('second call ended, room call empty');

      // Alice calls once more and Bob declines on his card: Alice's call ends by itself
      // ("Declined" on her screen, then it closes), out of LiveKit and the room's call.
      await tester.tap(find.byKey(const Key('chat.voiceCall')));
      await _pumpUntil(tester, find.byKey(const Key('call.screen')));
      // Alone in LiveKit while her own ring is live.
      await _pumpUntil(tester, find.text('Ringing…'));
      _step('alice rings again');
      await _until(
        tester,
        'Bob rings again',
        () => bobApp.read(incomingCallsProvider).ringing.isNotEmpty,
      );
      final third = bobApp.read(incomingCallsProvider).ringing.single;
      await _whileWaiting(
        tester,
        bobApp.read(incomingCallsProvider.notifier).decline(third),
      );
      _step('bob declined');
      await _pumpUntil(tester, find.text('Declined'));
      expect(aliceApp.read(callControllerProvider)?.phase, CallPhase.ended);
      expect(aliceApp.read(callControllerProvider.notifier).media, isNull);
      await _pumpUntil(
        tester,
        find.byKey(const Key('call.screen')),
        gone: true,
      );
      expect(aliceApp.read(callControllerProvider), isNull);
      expect(bobApp.read(callControllerProvider), isNull);
      // The room's call had Alice in it, then nobody.
      do {
        expect(await _whileWaiting(tester, calls.moveNext()), isTrue);
      } while (!calls.current.isActive);
      do {
        expect(await _whileWaiting(tester, calls.moveNext()), isTrue);
      } while (calls.current.isActive);
      _step('declined call ended, room call empty');

      // Alice calls and hangs up while her media still connects (as when the callee
      // declines at once): no connection of hers stays behind in LiveKit. One that did kept
      // her device's identity there, and her next call's connection displaced it
      // (DUPLICATE_IDENTITY) and never got its microphone out (rtc.oxisoft.net, 2026-11-26).
      unawaited(
        aliceApp
            .read(callControllerProvider.notifier)
            .join(aliceId, roomId, intent: CallIntent.audio),
      );
      await _until(
        tester,
        'Alice’s media connecting',
        () =>
            aliceApp.read(callControllerProvider)?.media.connection ==
            CallConnection.connecting,
      );
      await _whileWaiting(
        tester,
        aliceApp.read(callControllerProvider.notifier).hangUp(),
      );
      _step('alice hung up while connecting');
      // Long enough for a connection left behind to finish connecting (10-16 s on the pod).
      await _pumpFor(tester, const Duration(seconds: 20));
      // From here on: Bob's encryptor starts before Alice comes.
      since = _log.length;
      unawaited(
        bobApp
            .read(callControllerProvider.notifier)
            .join(bobId, roomId, intent: CallIntent.audio),
      );
      await _until(
        tester,
        'Bob in LiveKit',
        () =>
            bobApp.read(callControllerProvider)?.media.connection ==
            CallConnection.connected,
      );
      await _pumpFor(tester, const Duration(seconds: 2));
      final media = bobApp.read(callControllerProvider.notifier).media;
      final left = (media! as LiveKitCallMedia).room!.remoteParticipants.values
          .map((p) => p.identity)
          .toList();
      expect(left, isEmpty, reason: 'a LiveKit connection left behind');
      _step('nothing left behind');
      // And Bob, there already, is called by Alice: they talk.
      unawaited(
        aliceApp
            .read(callControllerProvider.notifier)
            .join(aliceId, roomId, intent: CallIntent.audio),
      );
      await _expectTalking(
        tester,
        aliceApp,
        bobApp,
        aliceId: aliceId,
        bobId: bobId,
        since: since,
      );
      await _whileWaiting(
        tester,
        bobApp.read(callControllerProvider.notifier).hangUp(),
      );
      await _pumpUntil(
        tester,
        find.byKey(const Key('call.screen')),
        gone: true,
      );
      _step('fourth call ended');

      // Let both log out of LiveKit and the homeserver before the containers go.
      await _pumpFor(tester, const Duration(seconds: 1));
      await tester.pumpWidget(const SizedBox());
    },
    skip: !_rtc,
    timeout: const Timeout(Duration(minutes: 8)),
  );
}

/// Waits until Alice and Bob are both connected to LiveKit with the other as a remote
/// participant whose microphone is on, both say the other's frames decrypt, and sound comes
/// through both ways. [since]: the first log line of this call.
Future<void> _expectTalking(
  WidgetTester tester,
  ProviderContainer aliceApp,
  ProviderContainer bobApp, {
  required String aliceId,
  required String bobId,
  required int since,
}) async {
  // Both connect to LiveKit and see each other with a microphone on, and both say the
  // other's frames decrypt (every decryptor kOk, no local encryptor failure).
  bool connectedTo(ProviderContainer app, String otherUser) {
    final call = app.read(callControllerProvider);
    if (call == null || call.phase != CallPhase.inCall) return false;
    final media = call.media;
    return media.connection == CallConnection.connected &&
        media.tiles.any((t) => t.isLocal) &&
        media.tiles.any((t) => !t.isLocal && t.userId == otherUser && t.micOn);
  }

  await _until(
    tester,
    'both connected with the other in the call',
    () => connectedTo(aliceApp, bobId) && connectedTo(bobApp, aliceId),
    detail: () => _describe(aliceApp, bobApp),
  );
  _step('both connected');
  final aliceIdentity = _local(aliceApp).identity;
  final bobIdentity = _local(bobApp).identity;
  expect(_remote(aliceApp).identity, bobIdentity);
  expect(_remote(bobApp).identity, aliceIdentity);

  await _until(
    tester,
    'encrypted both ways',
    () =>
        aliceApp.read(callControllerProvider)!.media.encrypted &&
        bobApp.read(callControllerProvider)!.media.encrypted,
    detail: () => _describe(aliceApp, bobApp),
  );
  _step('encrypted both ways');
  // The app shows it: the lock on Alice's call screen.
  expect(find.byKey(const Key('call.encrypted')), findsOneWidget);
  for (final (who, other) in [
    (aliceIdentity, bobIdentity),
    (bobIdentity, aliceIdentity),
  ]) {
    // Each side's own encryptor and its decryptor of the other said ok.
    expect(
      _log.skip(since).any((l) => l.contains('E2EE encryptor $who: kOk')),
      isTrue,
      reason: 'encryptor of $who',
    );
    expect(
      _log.skip(since).any((l) => l.contains('E2EE decryptor $other: kOk')),
      isTrue,
      reason: 'decryptor of $other',
    );
  }
  expect(
    _log
        .skip(since)
        .where(
          (l) =>
              l.contains('kDecryptionFailed') ||
              l.contains('kEncryptionFailed') ||
              l.contains('kMissingKey') ||
              l.contains('kInternalError'),
        ),
    isEmpty,
  );

  // Sound arrives both ways: the remote audio track's inbound RTP keeps decoding samples,
  // with energy (the fake microphone's tone) and without concealing them.
  final aliceHears = await _hearing(tester, aliceApp, bobIdentity);
  final bobHears = await _hearing(tester, bobApp, aliceIdentity);
  _step('alice hears bob: $aliceHears');
  _step('bob hears alice: $bobHears');
  // Calibrated on the test pod (2 s): the 440 Hz tone gives ~100 packets and energy ~1e-3; a
  // silent microphone ~12 packets (Opus DTX) and energy ~2e-9. (audioLevel is a snapshot that
  // dips now and then, ~0.001 once with the tone on: printed, not checked.)
  for (final (who, heard) in [('Alice', aliceHears), ('Bob', bobHears)]) {
    expect(heard.samplesGained, greaterThan(24000), reason: '$who: samples');
    expect(heard.packetsGained, greaterThan(50), reason: '$who: packets');
    expect(heard.energyGained, greaterThan(1e-5), reason: '$who: energy');
  }
}

void _step(String what) {
  final line = '${DateTime.now().toIso8601String()} STEP $what';
  _log.add(line);
  // ignore: avoid_print
  print(line);
}

List<Override> _overrides(String dataDir, {required Ringer ringer}) => [
  clientFactoryProvider.overrideWithValue(
    RustMatrixClientFactory(
      secrets: MemorySecretStore(),
      dataDir: () async => Directory(dataDir)..createSync(recursive: true),
    ),
  ),
  defaultServerProvider.overrideWithValue(_homeserver),
  diagnosticsProvider.overrideWithValue(MemoryDiagnostics()),
  mediaPrefsProvider.overrideWithValue(MemoryMediaPrefs()),
  fileActionsProvider.overrideWithValue(FakeFileActions()),
  uiPrefsProvider.overrideWithValue(MemoryUiPrefs()),
  accountPicturesProvider.overrideWithValue(MemoryAccountPictures()),
  collapsedSectionsStoreProvider.overrideWithValue(MemoryCollapsedSections()),
  pickImageProvider.overrideWithValue(
    () async => PickedImage(png, 'image/png'),
  ),
  ringerProvider.overrideWithValue(ringer),
];

bool _isDm(ProviderContainer app, String account, String roomId) =>
    app
        .read(roomsProvider(account))
        .value
        ?.where((room) => room.id == roomId)
        .firstOrNull
        ?.isDm ??
    false;

CallTile _local(ProviderContainer app) =>
    app.read(callControllerProvider)!.media.tiles.firstWhere((t) => t.isLocal);

CallTile _remote(ProviderContainer app) =>
    app.read(callControllerProvider)!.media.tiles.firstWhere((t) => !t.isLocal);

String _describe(ProviderContainer alice, ProviderContainer bob) {
  String one(String who, ProviderContainer app) {
    final call = app.read(callControllerProvider);
    if (call == null) return '$who: no call';
    final m = call.media;
    return '$who: ${call.phase.name} ${m.connection.name} '
        'encrypted=${m.encrypted} error=${call.error ?? m.error} tiles='
        '${[for (final t in m.tiles) '${t.identity}${t.isLocal ? '(me)' : ''} mic=${t.micOn}']} '
        'members=${call.roomCall?.participants.map((p) => p.identity).toList()}';
  }

  return '${one('alice', alice)}; ${one('bob', bob)}';
}

/// What came in from [identity]'s microphone over two seconds.
typedef _Heard = ({
  num packetsGained,
  num samplesGained,
  num concealedGained,
  num energyGained,
  num? audioLevel,
});

Future<_Heard> _hearing(
  WidgetTester tester,
  ProviderContainer app,
  String identity,
) async {
  final media = app.read(callControllerProvider.notifier).media;
  expect(media, isA<LiveKitCallMedia>());
  final room = (media! as LiveKitCallMedia).room!;
  final participant = room.remoteParticipants.values.firstWhere(
    (p) => p.identity == identity,
  );
  final publication = participant.audioTrackPublications.firstWhere(
    (p) => p.source == lk.TrackSource.microphone,
  );
  expect(publication.subscribed, isTrue);
  expect(publication.encryptionType, isNot(lk.EncryptionType.kNone));
  final receiver = publication.track!.receiver!;

  Future<Map<String, Object?>> inbound() async {
    final reports = await _whileWaiting(tester, receiver.getStats());
    final rtp = reports.where(
      (r) => r.type == 'inbound-rtp' && r.values['kind'] == 'audio',
    );
    expect(rtp, isNotEmpty, reason: 'inbound-rtp of $identity');
    return Map.of(rtp.first.values.cast<String, Object?>());
  }

  num n(Map<String, Object?> stats, String key) => (stats[key] as num?) ?? 0;

  final before = await inbound();
  await _pumpFor(tester, const Duration(seconds: 2));
  final after = await inbound();
  return (
    packetsGained: n(after, 'packetsReceived') - n(before, 'packetsReceived'),
    samplesGained:
        n(after, 'totalSamplesReceived') - n(before, 'totalSamplesReceived'),
    concealedGained:
        n(after, 'concealedSamples') - n(before, 'concealedSamples'),
    energyGained: n(after, 'totalAudioEnergy') - n(before, 'totalAudioEnergy'),
    audioLevel: after['audioLevel'] as num?,
  );
}

/// Registers a fresh user (open registration on the test server only).
Future<({String name, String password})> _registerUser(String who) async {
  final name = '$who${DateTime.now().microsecondsSinceEpoch}';
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

/// Pumps frames, letting real time pass, until [condition] holds.
Future<void> _until(
  WidgetTester tester,
  String what,
  bool Function() condition, {
  String Function()? detail,
}) async {
  final deadline = DateTime.now().add(_timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (condition()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
  }
  throw TestFailure(
    'Timed out waiting for: $what${detail == null ? '' : '\n${detail()}'}',
  );
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
