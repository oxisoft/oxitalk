/// A voice call between two real app sessions over a REAL deployment (homeserver, lk-jwt,
/// LiveKit SFU on the internet), not the test pod. Manual: run it with `scripts/call-prod.sh`,
/// which reads the two accounts from env files, brings up a fake microphone and a silent
/// speaker for the app only, and logs both devices out at the end. Never in CI: skipped
/// unless `OXITALK_PROD_CALL=1`.
///
/// Both sessions are headless sets of the app's providers in one process (Alice calls, Bob's
/// IncomingCalls rings and he answers), each with its own LiveKitCallMedia, so everything of
/// a call is real: Matrix signalling, the LiveKit token, media through the SFU with frame
/// encryption. It checks what a person on a call needs: both connect, both microphones are
/// published and unmuted, every encryptor and decryptor says ok, and sound decodes both ways.
library;

import 'dart:async';
import 'dart:io';

// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:logging/logging.dart';
import 'package:oxitalk/src/app/account_pictures.dart';
import 'package:oxitalk/src/app/collapsed_sections.dart';
import 'package:oxitalk/src/app/diagnostics.dart';
import 'package:oxitalk/src/app/file_actions.dart';
import 'package:oxitalk/src/app/media_prefs.dart';
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

final _env = Platform.environment;
final _on = _env['OXITALK_PROD_CALL'] == '1';

const _timeout = Duration(seconds: 90);

final _log = <String>[];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await RustLib.init();
    final logs = _env['OXITALK_PROD_LOGS'];
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
    if (_env['OXITALK_PROD_VERBOSE'] == '1') {
      hierarchicalLoggingEnabled = true;
      lk.setLoggingLevel(lk.LoggerLevel.kALL);
      Logger.root.onRecord.listen((r) {
        // ignore: avoid_print
        print('LK ${r.time.toIso8601String()} ${r.level.name} ${r.message}');
      });
    }
  });

  testWidgets(
    'a voice call over the real call server: both connect, publish an unmuted, '
    'encrypted microphone, and hear each other',
    (tester) async {
      final server = _env['OXITALK_PROD_SERVER']!;
      final dataDir = Directory(_env['OXITALK_PROD_DATA']!)
        ..createSync(recursive: true);
      await tester.pumpWidget(const SizedBox());

      Future<(ProviderContainer, String)> start(String who, String user) async {
        final app = ProviderContainer(
          overrides: _overrides('${dataDir.path}/$who', server),
        );
        addTearDown(app.dispose);
        app
          ..listen(incomingCallsProvider, (_, _) {})
          ..listen(callControllerProvider, (_, next) {
            _step(
              '$who call ${next?.phase.name} ${next?.media.connection.name} '
              'mic=${next?.media.micOn} enc=${next?.media.encrypted}',
            );
          });
        await _whileWaiting(tester, app.read(accountsProvider.future));
        await _whileWaiting(
          tester,
          app
              .read(accountsProvider.notifier)
              .login(
                server: server,
                username: user,
                password: _env['OXITALK_PROD_${who.toUpperCase()}_PASSWORD']!,
              ),
        );
        final id = app.read(accountsProvider).value!.sessions.single.userId;
        app.listen(roomsProvider(id), (_, _) {});
        _step('$who logged in as $id');
        return (app, id);
      }

      final (aliceApp, aliceId) = await start(
        'alice',
        _env['OXITALK_PROD_ALICE_USER']!,
      );
      final (bobApp, bobId) = await start(
        'bob',
        _env['OXITALK_PROD_BOB_USER']!,
      );
      addTearDown(() async {
        for (final (app, id) in [(aliceApp, aliceId), (bobApp, bobId)]) {
          try {
            await app.read(callControllerProvider.notifier).hangUp();
            await app.read(accountsProvider.notifier).logout(id);
            _step('logged out $id');
          } on Object catch (error) {
            _step('logout $id failed: $error');
          }
        }
      });
      final aliceSession = aliceApp
          .read(accountsProvider)
          .value!
          .byId(aliceId)!;
      final bobSession = bobApp.read(accountsProvider).value!.byId(bobId)!;

      // The room: given, or a new DM between the two.
      var roomId = _env['OXITALK_PROD_ROOM'] ?? '';
      if (roomId.isEmpty) {
        roomId = await _whileWaiting(tester, aliceSession.createDm(bobId));
        _step('created DM $roomId');
        await _until(tester, 'Bob sees the invitation', () {
          return bobApp
                  .read(roomsProvider(bobId))
                  .value
                  ?.any((r) => r.id == roomId) ??
              false;
        });
        await _whileWaiting(tester, bobSession.join(roomId));
      }
      await _until(
        tester,
        'the chat is a DM for both',
        () => _isDm(aliceApp, aliceId, roomId) && _isDm(bobApp, bobId, roomId),
      );
      _step('room $roomId ready');

      // A call ended while its media is still connecting (the callee declined at once, as
      // on 2026-11-26): its LiveKit connection must not stay behind. Left behind, it kept
      // this device's identity in the LiveKit room, and the next call's connection, under
      // the same identity, displaced it (DUPLICATE_IDENTITY) and never sent sound.
      if (_env['OXITALK_PROD_RACE'] == 'decline') {
        // As on 2026-11-26: Alice rings, Bob declines at once (her media still connects),
        // and she rings again right away; Bob answers that one (checked below).
        unawaited(
          aliceApp
              .read(callControllerProvider.notifier)
              .join(
                aliceId,
                roomId,
                intent: CallIntent.audio,
                notify: CallNotify.ring,
              ),
        );
        await _until(
          tester,
          'Bob rings',
          () => bobApp.read(incomingCallsProvider).ringing.isNotEmpty,
        );
        final first = bobApp.read(incomingCallsProvider).ringing.single;
        await _whileWaiting(
          tester,
          bobApp.read(incomingCallsProvider.notifier).decline(first),
        );
        _step(
          'bob declined; alice media '
          '${aliceApp.read(callControllerProvider)?.media.connection.name}',
        );
        await _until(
          tester,
          'Alice’s call ended',
          () =>
              aliceApp.read(callControllerProvider)?.phase != CallPhase.inCall,
        );
        await _until(
          tester,
          'Bob not ringing',
          () => bobApp.read(incomingCallsProvider).ringing.isEmpty,
        );
      }
      if (_env['OXITALK_PROD_RACE'] == '1') {
        unawaited(
          aliceApp
              .read(callControllerProvider.notifier)
              .join(
                aliceId,
                roomId,
                intent: CallIntent.audio,
                notify: CallNotify.none,
              ),
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
        // Long enough for a connection left behind to finish connecting.
        await _pumpFor(tester, const Duration(seconds: 5));
        await _expectNobodyLeftBehind(tester, bobApp, bobId, roomId);
      }

      final since = _log.length;
      unawaited(
        aliceApp
            .read(callControllerProvider.notifier)
            .join(
              aliceId,
              roomId,
              intent: CallIntent.audio,
              notify: CallNotify.ring,
            ),
      );
      await _until(
        tester,
        'Bob rings',
        () => bobApp.read(incomingCallsProvider).ringing.isNotEmpty,
      );
      final ringing = bobApp.read(incomingCallsProvider).ringing.single;
      _step('bob rings');
      unawaited(
        bobApp
            .read(incomingCallsProvider.notifier)
            .accept(ringing, CallIntent.audio),
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
        aliceApp.read(callControllerProvider.notifier).hangUp(),
      );
      await _until(
        tester,
        'Bob’s call ended',
        () => bobApp.read(callControllerProvider) == null,
      );
      _step('both ended');
      await _pumpFor(tester, const Duration(seconds: 1));
    },
    skip: !_on,
    timeout: const Timeout(Duration(minutes: 6)),
  );
}

Future<void> _expectTalking(
  WidgetTester tester,
  ProviderContainer aliceApp,
  ProviderContainer bobApp, {
  required String aliceId,
  required String bobId,
  required int since,
}) async {
  bool connectedTo(ProviderContainer app, String otherUser) {
    final call = app.read(callControllerProvider);
    if (call == null || call.phase != CallPhase.inCall) return false;
    final media = call.media;
    return media.connection == CallConnection.connected &&
        media.micOn &&
        media.tiles.any((t) => t.isLocal && t.micOn) &&
        media.tiles.any((t) => !t.isLocal && t.userId == otherUser && t.micOn);
  }

  await _until(
    tester,
    'both connected, each with its own microphone on and the other’s',
    () => connectedTo(aliceApp, bobId) && connectedTo(bobApp, aliceId),
    detail: () => _describe(aliceApp, bobApp),
  );
  _step('both connected');
  final aliceIdentity = _local(aliceApp).identity;
  final bobIdentity = _local(bobApp).identity;

  await _until(
    tester,
    'encrypted both ways',
    () =>
        aliceApp.read(callControllerProvider)!.media.encrypted &&
        bobApp.read(callControllerProvider)!.media.encrypted,
    detail: () => _describe(aliceApp, bobApp),
  );
  _step('encrypted both ways');
  for (final (who, other) in [
    (aliceIdentity, bobIdentity),
    (bobIdentity, aliceIdentity),
  ]) {
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
  // Each side's own microphone track is published, unmuted, and encrypted.
  for (final app in [aliceApp, bobApp]) {
    final room = _room(app);
    final mic = room.localParticipant!.audioTrackPublications.firstWhere(
      (p) => p.source == lk.TrackSource.microphone,
    );
    expect(mic.muted, isFalse, reason: 'local mic muted');
    expect(mic.encryptionType, isNot(lk.EncryptionType.kNone));
  }

  final aliceHears = await _hearing(tester, aliceApp, bobIdentity);
  final bobHears = await _hearing(tester, bobApp, aliceIdentity);
  _step('alice hears bob: $aliceHears');
  _step('bob hears alice: $bobHears');
  for (final (who, heard) in [('Alice', aliceHears), ('Bob', bobHears)]) {
    expect(heard.samplesGained, greaterThan(24000), reason: '$who: samples');
    expect(heard.packetsGained, greaterThan(50), reason: '$who: packets');
    expect(heard.energyGained, greaterThan(1e-5), reason: '$who: energy');
  }
}

/// Bob joins the room's call alone: LiveKit must have nobody else in it (no connection of
/// Alice's left behind by a call she ended while it connected).
Future<void> _expectNobodyLeftBehind(
  WidgetTester tester,
  ProviderContainer bobApp,
  String bobId,
  String roomId,
) async {
  unawaited(
    bobApp
        .read(callControllerProvider.notifier)
        .join(bobId, roomId, intent: CallIntent.audio),
  );
  await _until(
    tester,
    'Bob alone in LiveKit',
    () =>
        bobApp.read(callControllerProvider)?.media.connection ==
        CallConnection.connected,
  );
  await _pumpFor(tester, const Duration(seconds: 2));
  final others = _room(bobApp).remoteParticipants.values
      .map((p) => p.identity)
      .toList();
  _step('bob alone in LiveKit; others there: $others');
  expect(others, isEmpty, reason: 'a connection left behind');
  await _whileWaiting(
    tester,
    bobApp.read(callControllerProvider.notifier).hangUp(),
  );
}

void _step(String what) {
  final line = '${DateTime.now().toIso8601String()} STEP $what';
  _log.add(line);
  // ignore: avoid_print
  print(line);
}

List<Override> _overrides(String dataDir, String server) => [
  clientFactoryProvider.overrideWithValue(
    RustMatrixClientFactory(
      secrets: MemorySecretStore(),
      dataDir: () async => Directory(dataDir)..createSync(recursive: true),
    ),
  ),
  defaultServerProvider.overrideWithValue(server),
  diagnosticsProvider.overrideWithValue(MemoryDiagnostics()),
  mediaPrefsProvider.overrideWithValue(MemoryMediaPrefs()),
  fileActionsProvider.overrideWithValue(FakeFileActions()),
  uiPrefsProvider.overrideWithValue(MemoryUiPrefs()),
  accountPicturesProvider.overrideWithValue(MemoryAccountPictures()),
  collapsedSectionsStoreProvider.overrideWithValue(MemoryCollapsedSections()),
  ringerProvider.overrideWithValue(FakeRinger()),
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

lk.Room _room(ProviderContainer app) {
  final media = app.read(callControllerProvider.notifier).media;
  return (media! as LiveKitCallMedia).room!;
}

String _describe(ProviderContainer alice, ProviderContainer bob) {
  String one(String who, ProviderContainer app) {
    final call = app.read(callControllerProvider);
    if (call == null) return '$who: no call';
    final m = call.media;
    return '$who: ${call.phase.name} ${m.connection.name} mic=${m.micOn} '
        'encrypted=${m.encrypted} error=${call.error ?? m.error} tiles='
        '${[for (final t in m.tiles) '${t.identity}${t.isLocal ? '(me)' : ''} mic=${t.micOn}']}';
  }

  return '${one('alice', alice)}; ${one('bob', bob)}';
}

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
  final room = _room(app);
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

Future<void> _pumpFor(WidgetTester tester, Duration duration) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 50));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
  }
}

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
