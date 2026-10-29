import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oxitalk/src/app/router.dart';
import 'package:oxitalk/src/features/settings/server_settings.dart';
import 'package:oxitalk/src/matrix/api/matrix.dart';
import 'package:oxitalk/src/matrix/fakes/fakes.dart';

import 'support/app.dart';

const _wide = Size(1400, 900);

const _me = '@alex:chat.oxisoft.net';
const _work = '@alex:work.example';

/// chat.oxisoft.net as it answered on 2026-10-26.
const _oxisoft = ServerInfo(
  userId: _me,
  homeserverUrl: 'https://chat.oxisoft.net/',
  serverName: 'chat.oxisoft.net',
  wellKnownClient: Probe.found,
  wellKnownBaseUrl: 'https://chat.oxisoft.net/',
  wellKnownServer: Probe.found,
  serverDelegation: 'chat.oxisoft.net:443',
  software: ServerSoftware(
    name: 'Tuwunel',
    version: '1.9.4',
    source: '/_tuwunel/server_version',
  ),
  federation: Federation.disabled,
  versionsKnown: true,
  specVersions: ['r0.0.1', 'v1.1', 'v1.18', 'v1.19'],
  newestSpecVersion: 'v1.19',
  unstableFeatures: [
    UnstableFeature(
      id: 'org.matrix.simplified_msc3575',
      label: 'Simplified sliding sync (MSC4186)',
      usedByApp: true,
    ),
    UnstableFeature(id: 'org.example.other', enabled: false),
  ],
  login: LoginInfo(
    flows: ['m.login.application_service', 'm.login.token', 'm.login.password'],
    getLoginToken: true,
  ),
  oauth: Availability.no,
  capabilities: ServerCapabilities(
    defaultRoomVersion: '11',
    roomVersions: [
      RoomVersion('10'),
      RoomVersion('11'),
      RoomVersion('org.matrix.hydra.11', stable: false),
    ],
  ),
  uploadLimitBytes: 50 * 1024 * 1024,
  wellKnownSupport: Probe.notFound,
  connection: ConnectionInfo(
    host: 'chat.oxisoft.net',
    port: 443,
    addresses: ['203.0.113.7'],
    roundTrip: Duration(milliseconds: 42),
    tls: true,
    httpVersion: 'HTTP/2.0',
  ),
);

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));

/// Settings › Server of [user], without waiting for everything to settle (a loading
/// indicator never does).
Future<void> _open(
  WidgetTester tester,
  List<FakeSession> sessions, {
  String? user,
  Size size = _wide,
}) async {
  await pumpApp(
    tester,
    FakeMatrixClientFactory(saved: sessions, active: sessions.first.userId),
    size: size,
  );
  _container(tester)
      .read(routerProvider)
      .go(Routes.settingsServer(user ?? sessions.first.userId));
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// The value shown in the line with [key].
Finder _line(String key, String value) => find.descendant(
  of: find.byKey(Key('server.$key')),
  matching: find.text(value),
);

void main() {
  testWidgets(
    'the server loads when the section opens, then shows its key lines',
    (tester) async {
      final gate = Completer<void>();
      final session = FakeSession(userId: _me, rooms: const [])
        ..server = _oxisoft
        ..serverInfoGate = gate;
      await _open(tester, [session]);
      await _scrollTo(tester, find.byKey(const Key('server.group')));

      expect(find.text('Server'), findsWidgets);
      expect(find.byKey(const Key('server.loading')), findsOneWidget);
      expect(session.serverInfoCalls, 1);

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('server.loading')), findsNothing);
      expect(_line('address', 'https://chat.oxisoft.net'), findsOneWidget);
      expect(_line('software', 'Tuwunel 1.9.4'), findsOneWidget);
      expect(_line('matrixVersion', 'v1.19'), findsOneWidget);
      expect(_line('federation', 'Off'), findsOneWidget);
      // The application-service login is for bridges, not people.
      expect(_line('signIn', 'Login token, Password'), findsOneWidget);
      expect(_line('uploadLimit', '50 MB'), findsOneWidget);
      // More details stays closed until asked.
      expect(find.text('Simplified sliding sync (MSC4186)'), findsNothing);
    },
  );

  testWidgets(
    'More details shows room versions, capabilities, features and more',
    (tester) async {
      final session = FakeSession(userId: _me, rooms: const [])
        ..server = _oxisoft;
      await _open(tester, [session]);
      await _scrollTo(tester, find.byKey(const Key('server.more')));
      await tester.tap(find.text('More details'));
      await tester.pumpAndSettle();

      expect(find.text('Simplified sliding sync (MSC4186)'), findsOneWidget);
      expect(find.text('On · used by OxiTalk'), findsOneWidget);
      expect(find.text('10, 11'), findsOneWidget);
      expect(find.text('org.matrix.hydra.11'), findsOneWidget);
      expect(find.text('chat.oxisoft.net:443'), findsOneWidget);
      expect(find.text('203.0.113.7'), findsOneWidget);
      expect(find.text('42 ms'), findsOneWidget);
      expect(find.text('Yes · HTTP/2.0'), findsOneWidget);
      expect(find.text('Not offered'), findsOneWidget);
      expect(find.text('Not published'), findsOneWidget);
      expect(find.text('r0.0.1, v1.1, v1.18, v1.19'), findsOneWidget);

      // The raw list is a level deeper.
      expect(find.text('All unstable features (2)'), findsOneWidget);
      expect(find.textContaining('org.example.other: off'), findsNothing);
      await _scrollTo(tester, find.byKey(const Key('server.rawFeatures')));
      await tester.tap(find.text('All unstable features (2)'));
      await tester.pumpAndSettle();
      expect(find.textContaining('org.example.other: off'), findsOneWidget);
    },
  );

  testWidgets('a server that can’t be asked shows an error with Try again', (
    tester,
  ) async {
    final session = FakeSession(userId: _me, rooms: const [])
      ..server = _oxisoft
      ..serverInfoFailure = const MatrixFailure(FailureKind.network);
    await _open(tester, [session]);
    await _scrollTo(tester, find.byKey(const Key('server.group')));
    await tester.pumpAndSettle();

    expect(find.text('Can’t load the server details.'), findsOneWidget);
    expect(find.byKey(const Key('server.copy')), findsNothing);

    session.serverInfoFailure = null;
    await tester.tap(find.byKey(const Key('server.retry')));
    await tester.pumpAndSettle();
    expect(session.serverInfoCalls, 2);
    expect(find.byKey(const Key('server.error')), findsNothing);
    expect(_line('software', 'Tuwunel 1.9.4'), findsOneWidget);
  });

  testWidgets('Refresh asks the server again and shows its new answer', (
    tester,
  ) async {
    final session = FakeSession(userId: _me, rooms: const [])
      ..server = _oxisoft;
    await _open(tester, [session]);
    await _scrollTo(tester, find.byKey(const Key('server.refresh')));
    await tester.pumpAndSettle();

    session.server = const ServerInfo(
      userId: _me,
      homeserverUrl: 'https://chat.oxisoft.net/',
      serverName: 'chat.oxisoft.net',
      software: ServerSoftware(name: 'Tuwunel', version: '1.10.0'),
    );
    await tester.tap(find.byKey(const Key('server.refresh')));
    await tester.pumpAndSettle();
    expect(session.serverInfoCalls, 2);
    expect(_line('software', 'Tuwunel 1.10.0'), findsOneWidget);
    expect(_line('uploadLimit', 'Unknown'), findsOneWidget);
    expect(_line('federation', 'Unknown'), findsOneWidget);

    // A failed refresh keeps what was shown, with Try again.
    session.serverInfoFailure = const MatrixFailure(FailureKind.network);
    await tester.tap(find.byKey(const Key('server.refresh')));
    await tester.pumpAndSettle();
    expect(_line('software', 'Tuwunel 1.10.0'), findsOneWidget);
    expect(find.text('Can’t refresh the server details.'), findsOneWidget);
  });

  testWidgets(
    'Copy server details puts a plain-text summary on the clipboard',
    (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final session = FakeSession(userId: _me, rooms: const [])
        ..server = _oxisoft;
      await _open(tester, [session]);
      await _scrollTo(tester, find.byKey(const Key('server.copy')));
      await tester.tap(find.byKey(const Key('server.copy')));
      await tester.pumpAndSettle();

      expect(find.text('Server details copied'), findsOneWidget);
      // The server, then its calls (this fake server offers none).
      expect(
        copied,
        '${serverDetailsText(_oxisoft)}\nCalls\n'
        'Voice and video calls: Not offered by this server',
      );
      expect(copied, contains('Address: https://chat.oxisoft.net\n'));
      expect(
        copied,
        contains('Software: Tuwunel 1.9.4 (from /_tuwunel/server_version)'),
      );
      expect(copied, contains('Federation: Off'));
      expect(copied, contains('Matrix version: v1.19'));
      expect(copied, contains('Upload limit: 50 MB'));
      expect(copied, contains('Support Contacts: Not published'));
      // For support: the server, not who the user is.
      expect(copied, isNot(contains(_me)));
    },
  );

  testWidgets(
    'the server shown is the picked account’s, not the active one’s',
    (tester) async {
      final active = FakeSession(userId: _me, rooms: const [])
        ..server = _oxisoft;
      final picked = FakeSession(userId: _work, rooms: const []);
      await _open(tester, [active, picked], user: _work);
      await _scrollTo(tester, find.byKey(const Key('server.group')));
      await tester.pumpAndSettle();

      expect(_line('address', 'https://work.example'), findsOneWidget);
      expect(_line('software', 'Unknown'), findsOneWidget);
      expect(picked.serverInfoCalls, 1);
      expect(active.serverInfoCalls, 0);

      // Picking the other account shows its server.
      _container(tester).read(routerProvider).go(Routes.settingsServer(_me));
      await tester.pumpAndSettle();
      await _scrollTo(tester, find.byKey(const Key('server.group')));
      await tester.pumpAndSettle();
      expect(_line('address', 'https://chat.oxisoft.net'), findsOneWidget);
      expect(_line('software', 'Tuwunel 1.9.4'), findsOneWidget);
      expect(active.serverInfoCalls, 1);
    },
  );

  testWidgets('on a phone each label stands above its value', (tester) async {
    final session = FakeSession(userId: _me, rooms: const [])
      ..server = _oxisoft;
    await _open(tester, [session], size: const Size(360, 800));
    await _scrollTo(tester, find.byKey(const Key('server.software')));
    await tester.pumpAndSettle();

    final label = tester.getTopLeft(
      find.descendant(
        of: find.byKey(const Key('server.software')),
        matching: find.text('Software'),
      ),
    );
    final value = tester.getTopLeft(_line('software', 'Tuwunel 1.9.4'));
    expect(value.dy, greaterThan(label.dy));
    expect(value.dx, label.dx);
    expect(tester.takeException(), isNull);
  });

  group('server updates', () {
    const outdated = ReleaseCheck(
      project: 'Tuwunel',
      latest: '1.10.0',
      url: 'https://github.com/matrix-construct/tuwunel/releases/tag/v1.10.0',
      status: ReleaseStatus.outdated,
    );
    const latest = ReleaseCheck(
      project: 'Tuwunel',
      latest: '1.9.4',
      status: ReleaseStatus.upToDate,
    );

    testWidgets('an admin sees a newer release in green after the red '
        'version, and a red banner above the accounts', (tester) async {
      final session = FakeSession(userId: _me, rooms: const [])
        ..server = _oxisoft
        ..serverAdmin = true
        ..releases = {'tuwunel': outdated};
      await _open(tester, [session]);
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const Key('server.software')),
          matching: find.byKey(const Key('release.newer')),
        ),
        findsOneWidget,
      );
      expect(find.text('→ 1.10.0'), findsOneWidget);
      expect(find.byKey(const Key('settings.serverUpdate')), findsOneWidget);
      expect(
        find.text('Tuwunel 1.10.0 is out; this server runs 1.9.4.'),
        findsOneWidget,
      );
      expect(session.releaseCalls, contains('Tuwunel'));
    });

    testWidgets('the latest release gets a green check and no banner', (
      tester,
    ) async {
      final session = FakeSession(userId: _me, rooms: const [])
        ..server = _oxisoft
        ..serverAdmin = true
        ..releases = {'tuwunel': latest};
      await _open(tester, [session]);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('release.latest')), findsOneWidget);
      expect(find.byKey(const Key('settings.serverUpdate')), findsNothing);
    });

    testWidgets('a user who isn’t a server admin never makes the release '
        'pages be asked', (tester) async {
      final session = FakeSession(userId: _me, rooms: const [])
        ..server = _oxisoft
        ..releases = {'tuwunel': outdated};
      await _open(tester, [session]);
      await tester.pumpAndSettle();

      expect(session.releaseCalls, isEmpty);
      expect(find.byKey(const Key('release.newer')), findsNothing);
      expect(find.byKey(const Key('settings.serverUpdate')), findsNothing);
    });

    testWidgets('an admin can turn the check off in Account; then nothing '
        'is asked', (tester) async {
      final session = FakeSession(userId: _me, rooms: const [])
        ..server = _oxisoft
        ..serverAdmin = true
        ..releases = {'tuwunel': outdated};
      await pumpApp(
        tester,
        FakeMatrixClientFactory(saved: [session], active: _me),
        size: _wide,
      );
      _container(tester).read(routerProvider).go(Routes.settingsAccount(_me));
      await tester.pumpAndSettle();
      // The banner shows in Account too, above the accounts.
      expect(find.byKey(const Key('settings.serverUpdate')), findsOneWidget);

      final toggle = find.byKey(const Key('settings.serverUpdates'));
      await _scrollTo(tester, toggle);
      expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);

      session.releaseCalls.clear();
      _container(tester).read(routerProvider).go(Routes.settingsServer(_me));
      await tester.pumpAndSettle();
      expect(session.releaseCalls, isEmpty);
      expect(find.byKey(const Key('release.newer')), findsNothing);
    });
  });
}
