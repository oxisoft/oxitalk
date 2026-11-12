// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oxitalk/src/app/file_actions.dart';
import 'package:oxitalk/src/features/calls/call_ui.dart';
import 'package:oxitalk/src/matrix/api/matrix.dart';
import 'package:oxitalk/src/matrix/fakes/fakes.dart';

import 'support/app.dart';

const _wide = Size(1400, 900);
const _me = '@alexander.bykov:chat.securium.ch';
const _team = '!team:chat.securium.ch';
const _jitsi = 'jitsi.securium.ch';

/// An account on a server like chat.securium.ch: no LiveKit call service, Jitsi in its
/// `.well-known`.
FakeSession _session({
  List<String> services = const [],
  String? jitsi = _jitsi,
}) {
  final session = FakeSession(
    userId: _me,
    rooms: const [Room(id: _team, name: 'Team')],
  )..callServiceUrls = services;
  session
    ..jitsiServer = jitsi
    ..timelines[_team] = FakeTimeline(ownUserId: _me, entries: const []);
  return session;
}

JitsiConference _conference({bool audioOnly = false}) => JitsiConference(
  roomId: _team,
  widgetId: 'w1',
  domain: _jitsi,
  conferenceId: 'JitsiAbcdef',
  audioOnly: audioOnly,
  creatorUserId: '@bob:chat.securium.ch',
  creatorName: 'Bob',
  startedAt: DateTime(2026, 11, 3, 10),
  joinUrl: 'https://$_jitsi/JitsiAbcdef',
);

Future<FakeFileActions> _open(WidgetTester tester, FakeSession session) async {
  final files = FakeFileActions();
  await pumpApp(
    tester,
    FakeMatrixClientFactory(saved: [session]),
    size: _wide,
    files: files,
  );
  await tester.tap(find.text('Team').first);
  await tester.pumpAndSettle();
  return files;
}

void main() {
  test('Jitsi takes the call buttons only where the server has no LiveKit', () {
    expect(
      callRouteOf(services: const [], jitsiDomain: _jitsi),
      CallRoute.jitsi,
    );
    expect(
      callRouteOf(
        services: const ['https://rtc.example/jwt'],
        jitsiDomain: _jitsi,
      ),
      CallRoute.matrixRtc,
    );
    expect(
      callRouteOf(services: const [], jitsiDomain: null),
      CallRoute.matrixRtc,
    );
    expect(
      callRouteOf(services: null, jitsiDomain: _jitsi),
      CallRoute.matrixRtc,
    );
  });

  testWidgets('a Jitsi conference going on shows a bar whose Join opens it', (
    tester,
  ) async {
    final session = _session();
    session.jitsiOf(_team).value = [_conference()];
    final files = await _open(tester, session);

    expect(find.byKey(const Key('jitsi.banner')), findsOneWidget);
    expect(find.text('Group call (Jitsi)'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('jitsi.details'))).data,
      'Started by Bob · $_jitsi',
    );
    await tester.tap(find.byKey(const Key('jitsi.join')));
    await tester.pumpAndSettle();
    expect(files.launched, [Uri.parse('https://$_jitsi/JitsiAbcdef')]);

    // It ends (the widget is removed): the bar goes.
    session.jitsiOf(_team).value = const [];
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('jitsi.banner')), findsNothing);
  });

  testWidgets('a conference on a Jitsi with Matrix sign-in opens signed in', (
    tester,
  ) async {
    final session = _session();
    final signedIn = JitsiConference(
      roomId: _team,
      widgetId: 'w2',
      domain: _jitsi,
      conferenceId: 'EFQWEYZ2PAXHS',
      creatorUserId: _me,
      startedAt: DateTime(2026, 11, 3, 10),
      joinUrl: 'https://$_jitsi/EFQWEYZ2PAXHS',
      needsSignIn: true,
    );
    session.jitsiOf(_team).value = [signedIn];
    final files = await _open(tester, session);
    expect(
      tester.widget<Text>(find.byKey(const Key('jitsi.details'))).data,
      'Started by you · $_jitsi',
    );
    await tester.tap(find.byKey(const Key('jitsi.join')));
    await tester.pumpAndSettle();
    expect(files.launched, [
      Uri.parse('https://$_jitsi/EFQWEYZ2PAXHS?jwt=fake-jwt'),
    ]);
  });

  testWidgets('a voice conference says so', (tester) async {
    final session = _session();
    session.jitsiOf(_team).value = [_conference(audioOnly: true)];
    await _open(tester, session);
    expect(
      tester.widget<Text>(find.byKey(const Key('jitsi.details'))).data,
      'Voice · Started by Bob · $_jitsi',
    );
  });

  testWidgets(
    'without LiveKit the video button starts a Jitsi conference and opens it',
    (tester) async {
      final session = _session();
      final files = await _open(tester, session);
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('chat.videoCall')))
            .tooltip,
        'Video call (Jitsi)',
      );

      await tester.tap(find.byKey(const Key('chat.videoCall')));
      await tester.pumpAndSettle();
      expect(session.startedJitsi, [(_team, false)]);
      expect(session.joinedCalls, isEmpty, reason: 'no MatrixRTC call');
      expect(files.launched, [Uri.parse('https://$_jitsi/JitsiFake1')]);
      expect(
        tester.widget<Text>(find.byKey(const Key('jitsi.details'))).data,
        'Started by you · $_jitsi',
      );

      // Now the buttons join it rather than start another.
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('chat.voiceCall')))
            .tooltip,
        'Join the group call (Jitsi)',
      );
      await tester.tap(find.byKey(const Key('chat.voiceCall')));
      await tester.pumpAndSettle();
      expect(session.startedJitsi, hasLength(1));
      expect(files.launched, hasLength(2));
    },
  );

  testWidgets('the voice button starts a voice-only conference', (
    tester,
  ) async {
    final session = _session();
    final files = await _open(tester, session);
    await tester.tap(find.byKey(const Key('chat.voiceCall')));
    await tester.pumpAndSettle();
    expect(session.startedJitsi, [(_team, true)]);
    expect(files.launched.single.fragment, 'config.startAudioOnly=true');
  });

  testWidgets('a member who may not add widgets is told why', (tester) async {
    final session = _session()..mayStartJitsi = false;
    final files = await _open(tester, session);
    await tester.tap(find.byKey(const Key('chat.videoCall')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('jitsi.cantStart')), findsOneWidget);
    expect(session.startedJitsi, isEmpty);
    expect(files.launched, isEmpty);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('jitsi.cantStart')), findsNothing);
  });

  testWidgets('with LiveKit the call buttons stay OxiTalk calls', (
    tester,
  ) async {
    final session = _session(services: const ['https://rtc.example/jwt']);
    final files = await _open(tester, session);
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('chat.videoCall')))
          .tooltip,
      'Video call',
    );
    await tester.tap(find.byKey(const Key('chat.videoCall')));
    await tester.pumpAndSettle();
    expect(session.joinedCalls.single.$1, _team);
    expect(session.startedJitsi, isEmpty);
    expect(files.launched, isEmpty);
    // Leave the call screen's media behind.
    session.lastJoinedCall?.onLeave?.call();
  });
}
