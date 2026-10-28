import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oxitalk/src/features/calls/call_controller.dart';
import 'package:oxitalk/src/features/calls/call_media.dart';
import 'package:oxitalk/src/features/chat/notice_line.dart';
import 'package:oxitalk/src/matrix/api/matrix.dart';
import 'package:oxitalk/src/matrix/fakes/fakes.dart';

import 'support/app.dart';
import 'support/call_fakes.dart';

const _wide = Size(1400, 900);
const _me = '@me:acme.com';
const _bob = '@bob:acme.com';
const _dm = '!dm:acme.com';
const _team = '!team:acme.com';

FakeSession _session() {
  final session = FakeSession(
    userId: _me,
    rooms: const [
      Room(id: _dm, name: 'Bob', isDm: true),
      Room(id: _team, name: 'Team'),
    ],
  );
  session.timelines[_dm] = FakeTimeline(ownUserId: _me, entries: const []);
  session.timelines[_team] = FakeTimeline(ownUserId: _me, entries: const []);
  return session;
}

Future<FakeSession> _open(
  WidgetTester tester,
  String name, {
  FakeSession? session,
  FakeRinger? ringer,
}) async {
  FakeCallMedia.made.clear();
  final fake = session ?? _session();
  await pumpApp(
    tester,
    FakeMatrixClientFactory(saved: [fake]),
    size: _wide,
    ringer: ringer,
  );
  await tester.tap(find.text(name).first);
  await tester.pumpAndSettle();
  return fake;
}

const _bobInCall = CallParticipant(
  userId: _bob,
  deviceId: 'BOBDEVICE',
  identity: '$_bob:BOBDEVICE',
  displayName: 'Bob',
  intent: CallIntent.video,
);

IncomingCall _ring({bool ring = true, CallIntent intent = CallIntent.video}) =>
    IncomingCall(
      roomId: _dm,
      notificationEventId: r'$ring',
      senderId: _bob,
      senderName: 'Bob',
      intent: intent,
      ring: ring,
      expiresAt: DateTime.now().add(const Duration(minutes: 1)),
    );

void main() {
  testWidgets('a video call in a direct chat rings, connects, and hangs up', (
    tester,
  ) async {
    final session = await _open(tester, 'Bob');
    expect(find.byKey(const Key('chat.voiceCall')), findsOneWidget);
    await tester.tap(find.byKey(const Key('chat.videoCall')));
    await tester.pumpAndSettle();

    expect(session.joinedCalls, [(_dm, CallIntent.video, CallNotify.ring)]);
    expect(find.byKey(const Key('call.screen')), findsOneWidget);
    final media = FakeCallMedia.made.single;
    expect((media.url, media.token), ('wss://sfu.test', 'fake-token'));
    expect(media.state.cameraOn, isTrue);
    // Alone so far, in a direct chat: it rings.
    expect(find.text('Ringing…'), findsOneWidget);

    // Bob's media arrives, encrypted.
    media.addRemote('$_bob:BOBDEVICE');
    await tester.pumpAndSettle();
    expect(find.text('Ringing…'), findsNothing);
    expect(find.byKey(const Key('call.tile.$_bob:BOBDEVICE')), findsOneWidget);
    expect(find.byKey(const Key('call.encrypted')), findsOneWidget);

    await tester.tap(find.byKey(const Key('call.hangUp')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('call.screen')), findsNothing);
    expect(media.closed, isTrue);
    expect(session.callOf(_dm).value.isActive, isFalse);
  });

  testWidgets('a group is notified, not rung, and a voice call has no camera', (
    tester,
  ) async {
    final session = await _open(tester, 'Team');
    await tester.tap(find.byKey(const Key('chat.voiceCall')));
    await tester.pumpAndSettle();
    expect(session.joinedCalls, [(_team, CallIntent.audio, CallNotify.notify)]);
    expect(FakeCallMedia.made.single.state.cameraOn, isFalse);
    expect(find.text('Waiting for others…'), findsOneWidget);
  });

  testWidgets('the media keys go to the media', (tester) async {
    final session = await _open(tester, 'Bob');
    await tester.tap(find.byKey(const Key('chat.voiceCall')));
    await tester.pumpAndSettle();
    final key = CallMediaKey(
      identity: '$_bob:BOBDEVICE',
      index: 3,
      key: Uint8List.fromList(List.filled(16, 7)),
      isOwn: false,
    );
    session.lastJoinedCall!.keys.add(key);
    await tester.pumpAndSettle();
    expect(FakeCallMedia.made.single.keys, [key]);
    // Hanging up leaves the call on the Matrix side too.
    await tester.tap(find.byKey(const Key('call.hangUp')));
    await tester.pumpAndSettle();
    expect(session.lastJoinedCall!.left, isTrue);
  });

  testWidgets('mute, camera, sound output and the ongoing call bar', (
    tester,
  ) async {
    await _open(tester, 'Bob');
    await tester.tap(find.byKey(const Key('chat.videoCall')));
    await tester.pumpAndSettle();
    final media = FakeCallMedia.made.single;

    await tester.tap(find.byKey(const Key('call.mic')));
    await tester.pumpAndSettle();
    expect(media.state.micOn, isFalse);
    expect(find.text('Unmute'), findsOneWidget);
    await tester.tap(find.byKey(const Key('call.camera')));
    await tester.pumpAndSettle();
    expect(media.state.cameraOn, isFalse);

    await tester.tap(find.byKey(const Key('call.output')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('call.outputs')), findsOneWidget);
    await tester.tap(find.text('Headset'));
    await tester.pumpAndSettle();
    expect(media.route, const AudioRoute('usb', 'Headset'));

    // Back to the chats: the call goes on in a bar over them.
    await tester.tap(find.byKey(const Key('call.minimize')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('call.screen')), findsNothing);
    expect(find.byKey(const Key('call.bar')), findsOneWidget);
    await tester.tap(find.text('Team'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('call.bar')), findsOneWidget);
    await tester.tap(find.byKey(const Key('call.bar.open')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('call.screen')), findsOneWidget);
    await tester.tap(find.byKey(const Key('call.minimize')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('call.bar.hangUp')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('call.bar')), findsNothing);
    expect(media.closed, isTrue);
  });

  testWidgets('a call going on shows a banner, and Join joins it as it is', (
    tester,
  ) async {
    final session = _session();
    session.callOf(_team).value = const RoomCall(
      roomId: _team,
      intent: CallIntent.video,
      participants: [_bobInCall],
    );
    await _open(tester, 'Team', session: session);
    expect(find.text('Call in progress'), findsOneWidget);
    await tester.tap(find.byKey(const Key('call.join')));
    await tester.pumpAndSettle();
    expect(session.joinedCalls, [(_team, CallIntent.video, CallNotify.none)]);
    // In the call now: no banner.
    await tester.tap(find.byKey(const Key('call.minimize')));
    await tester.pumpAndSettle();
    expect(find.text('Call in progress'), findsNothing);
  });

  testWidgets('a refused join says so and closes', (tester) async {
    final session = _session()
      ..joinCallFailure = const MatrixFailure(FailureKind.forbidden);
    await _open(tester, 'Team', session: session);
    await tester.tap(find.byKey(const Key('chat.voiceCall')));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'You can’t join calls in this chat, or the call service refused.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('call.close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('call.screen')), findsNothing);
  });

  testWidgets('an incoming call rings until it is declined', (tester) async {
    final ringer = FakeRinger();
    final session = await _open(tester, 'Team', ringer: ringer);
    session.incomingCallUpdates.add(CallRinging(_ring()));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('call.incoming')), findsOneWidget);
    expect(find.text('is video calling you'), findsOneWidget);
    expect(ringer.ringing, isTrue);

    await tester.tap(find.byKey(const Key('call.decline')));
    await tester.pumpAndSettle();
    expect(session.declinedCalls, [(_dm, r'$ring')]);
    expect(find.byKey(const Key('call.incoming')), findsNothing);
    expect(ringer.ringing, isFalse);
  });

  testWidgets('accepting with voice joins without the camera', (tester) async {
    final ringer = FakeRinger();
    final session = await _open(tester, 'Team', ringer: ringer);
    session.incomingCallUpdates.add(CallRinging(_ring()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('call.acceptVoice')));
    await tester.pumpAndSettle();
    expect(session.joinedCalls, [(_dm, CallIntent.audio, CallNotify.none)]);
    expect(FakeCallMedia.made.single.state.cameraOn, isFalse);
    expect(find.byKey(const Key('call.screen')), findsOneWidget);
    expect(ringer.ringing, isFalse);
  });

  testWidgets('a group notification shows without ringing', (tester) async {
    final ringer = FakeRinger();
    final session = await _open(tester, 'Team', ringer: ringer);
    session.incomingCallUpdates.add(CallRinging(_ring(ring: false)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('call.incoming')), findsOneWidget);
    expect(ringer.starts, 0);
  });

  testWidgets('a ring nobody answered is a missed call in the timeline', (
    tester,
  ) async {
    final ringer = FakeRinger();
    final session = _session();
    session.timelines[_dm] = FakeTimeline(
      ownUserId: _me,
      entries: [
        NoticeEntry(
          id: 'n1',
          sender: _bob,
          senderName: 'Bob',
          time: DateTime(2026, 10, 28, 12),
          eventId: r'$ring',
          notice: const CallNotice(video: true),
        ),
      ],
    );
    await _open(tester, 'Bob', session: session, ringer: ringer);
    expect(find.text('Bob started a video call'), findsOneWidget);
    session.incomingCallUpdates.add(CallRinging(_ring()));
    await tester.pumpAndSettle();
    session.incomingCallUpdates.add(
      const CallRingEnded(
        roomId: _dm,
        notificationEventId: r'$ring',
        reason: IncomingCallEnd.expired,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('call.incoming')), findsNothing);
    expect(ringer.ringing, isFalse);
    expect(find.text('Missed video call from Bob'), findsOneWidget);
  });

  test('call notices say what happened', () {
    NoticeEntry notice(CallNotice call, {bool own = false}) => NoticeEntry(
      id: 'n',
      sender: own ? _me : _bob,
      senderName: own ? 'Me' : 'Bob',
      isOwn: own,
      time: DateTime(2026),
      eventId: r'$n',
      notice: call,
    );
    String text(CallNotice call, {bool own = false, Set<String>? missed}) =>
        noticeText(
          notice(call, own: own),
          ownUserId: _me,
          missedCalls: missed ?? const {},
        );
    expect(text(const CallNotice()), 'Bob started a call');
    expect(
      text(const CallNotice(video: false, ongoing: true)),
      'Bob started a voice call · in progress',
    );
    expect(
      text(const CallNotice(video: true), own: true),
      'You started a video call',
    );
    expect(
      text(const CallNotice(video: true, declinedBy: [_me])),
      'Bob started a video call · declined by you',
    );
    expect(
      text(const CallNotice(video: false), missed: {r'$n'}),
      'Missed voice call from Bob',
    );
    // Declined here is not missed.
    expect(
      text(const CallNotice(declinedBy: [_me]), missed: {r'$n'}),
      'Bob started a call · declined by you',
    );
  });

  test('frame keys apply in order; an own key moves the encryptors', () async {
    final log = <String>[];
    final slow = Completer<void>();
    final ring = FrameKeyRing(
      store: (key) async {
        // The first key is slow to store: the later ones wait for it.
        if (key.index == 0 && !key.isOwn) await slow.future;
        log.add('store ${key.isOwn ? 'own' : key.identity} ${key.index}');
      },
      encryptWith: (index) async => log.add('encrypt $index'),
    );
    CallMediaKey key(int index, {bool own = false}) => CallMediaKey(
      identity: own ? '$_me:MINE' : '$_bob:BOBDEVICE',
      index: index,
      key: Uint8List.fromList(List.filled(16, index)),
      isOwn: own,
    );
    unawaited(ring.add(key(0)));
    unawaited(ring.add(key(0, own: true)));
    unawaited(ring.add(key(1, own: true)));
    await Future<void>.delayed(Duration.zero);
    expect(log, isEmpty);
    slow.complete();
    await ring.applied;
    expect(log, [
      'store $_bob:BOBDEVICE 0',
      'store own 0',
      'encrypt 0',
      'store own 1',
      'encrypt 1',
    ]);
    expect(ring.ownIndex, 1);
  });

  test(
    'a frame key that fails or has no slot does not stop the next',
    () async {
      final stored = <int>[];
      final ring = FrameKeyRing(
        store: (key) async {
          if (key.index == 2) throw StateError('native');
          stored.add(key.index);
        },
        encryptWith: (_) async {},
      );
      for (final index in [256, 2, 255]) {
        unawaited(
          ring.add(
            CallMediaKey(
              identity: '$_bob:BOBDEVICE',
              index: index,
              key: Uint8List(16),
              isOwn: false,
            ),
          ),
        );
      }
      await ring.applied;
      // 256 would land on slot 0 of the native key ring, over another key.
      expect(stored, [255]);
    },
  );

  test('the ring tone is a valid WAV', () {
    final wav = ringTone();
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
    // 3 s at 16 kHz, 16-bit mono.
    expect(wav.length, 44 + 3 * 16000 * 2);
  });
}
