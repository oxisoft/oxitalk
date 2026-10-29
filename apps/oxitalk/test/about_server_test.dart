import 'package:flutter_test/flutter_test.dart';
import 'package:oxitalk/src/app/ui_prefs.dart';
import 'package:oxitalk/src/features/about/about_screen.dart';
import 'package:oxitalk/src/matrix/api/matrix.dart';

const _info = ServerInfo(
  userId: '@alex:chat.oxisoft.net',
  homeserverUrl: 'https://chat.oxisoft.net/',
  serverName: 'chat.oxisoft.net',
  software: ServerSoftware(
    name: 'Tuwunel',
    version: '1.9.4',
    source: '/_tuwunel/server_version',
  ),
  federation: Federation.disabled,
  versionsKnown: true,
  newestSpecVersion: 'v1.15',
  unstableFeatures: [
    UnstableFeature(id: 'org.matrix.simplified_msc3575'),
    UnstableFeature(id: 'org.matrix.msc4140', enabled: false),
  ],
  uploadLimitBytes: 50 * 1024 * 1024,
);

Map<String, String> _byKey(List<(String, String, String)> lines) => {
  for (final (_, value, key) in lines) key: value,
};

void main() {
  test('the server card names the homeserver and the call servers', () {
    final now = DateTime(2026, 10, 29, 15);
    final lines = _byKey(
      aboutServerLines(
        info: _info,
        serverFailed: false,
        services: const ['https://rtc.oxisoft.net/livekit/jwt'],
        servicesFailed: false,
        seen: CallServerSeen(
          url: 'wss://rtc.oxisoft.net/livekit/sfu',
          seenAt: DateTime(2026, 10, 29, 14, 5),
          version: '1.13.11',
        ),
        now: now,
      ),
    );
    expect(lines['address'], 'https://chat.oxisoft.net');
    expect(lines['software'], 'Tuwunel 1.9.4');
    expect(lines['matrixVersion'], 'v1.15');
    expect(lines['slidingSync'], 'Supported');
    expect(lines['uploadLimit'], '50 MB');
    expect(lines['calls'], 'Supported, end-to-end encrypted');
    expect(
      lines['callService'],
      'https://rtc.oxisoft.net/livekit/jwt (lk-jwt-service)',
    );
    expect(
      lines['mediaServer'],
      'LiveKit 1.13.11\nwss://rtc.oxisoft.net/livekit/sfu\n'
      'Seen in a call today at 14:05',
    );
    expect(lines['callCleanup'], 'By the app only (no delayed events)');
  });

  test('a server without a call service says so and shows no call lines', () {
    final lines = _byKey(
      aboutServerLines(
        info: _info,
        serverFailed: false,
        services: const [],
        servicesFailed: false,
        seen: null,
      ),
    );
    expect(lines['calls'], 'Not offered by this server');
    expect(lines.containsKey('callService'), isFalse);
    expect(lines.containsKey('mediaServer'), isFalse);
  });

  test('before the answers come, and when they fail', () {
    final loading = _byKey(
      aboutServerLines(
        info: null,
        serverFailed: false,
        services: null,
        servicesFailed: false,
        seen: null,
      ),
    );
    expect(loading['address'], 'Checking…');
    expect(loading['calls'], 'Checking…');
    expect(loading['mediaServer'], 'Shown after the first call');

    final failed = _byKey(
      aboutServerLines(
        info: null,
        serverFailed: true,
        services: null,
        servicesFailed: true,
        seen: null,
      ),
    );
    expect(failed['address'], 'Can’t load');
    expect(failed['calls'], 'Can’t check');
  });

  test('the media server seen in a call is kept as JSON', () {
    final seen = CallServerSeen(
      url: 'wss://rtc.oxisoft.net/livekit/sfu',
      seenAt: DateTime.utc(2026, 10, 29, 13),
      version: '1.13.11',
      region: 'fsn1',
    );
    final back = CallServerSeen.fromJson(seen.toJson())!;
    expect(back.url, seen.url);
    expect(back.seenAt, seen.seenAt);
    expect(back.version, '1.13.11');
    expect(back.region, 'fsn1');
    expect(CallServerSeen.fromJson(null), isNull);
    expect(CallServerSeen.fromJson({'url': 'x'}), isNull);
  });
}
