import 'package:flutter_test/flutter_test.dart';
import 'package:oxitalk/src/app/ui_prefs.dart';
import 'package:oxitalk/src/features/settings/server_settings.dart';
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
  test('Server names sliding sync', () {
    expect(slidingSyncLabel(_info), 'Supported');
    expect(
      slidingSyncLabel(
        const ServerInfo(
          userId: '@a:b',
          homeserverUrl: 'https://b/',
          serverName: 'b',
          versionsKnown: true,
        ),
      ),
      'Not advertised (OxiTalk needs it)',
    );
  });

  test('Calls names the call service and the media server seen in a call', () {
    final lines = _byKey(
      callLines(
        info: _info,
        services: const ['https://rtc.oxisoft.net/livekit/jwt'],
        servicesFailed: false,
        seen: CallServerSeen(
          url: 'wss://rtc.oxisoft.net/livekit/sfu',
          seenAt: DateTime(2026, 10, 29, 14, 5),
          version: '1.13.11',
        ),
        now: DateTime(2026, 10, 29, 15),
      ),
    );
    expect(lines['supported'], 'Supported, end-to-end encrypted');
    expect(
      lines['service'],
      'https://rtc.oxisoft.net/livekit/jwt (lk-jwt-service)',
    );
    expect(
      lines['mediaServer'],
      'LiveKit 1.13.11\nwss://rtc.oxisoft.net/livekit/sfu\n'
      'Seen in a call today at 14:05',
    );
    expect(lines['cleanup'], 'By the app only (no delayed events)');
  });

  test('a server without a call service says so and nothing more', () {
    final lines = callLines(
      info: _info,
      services: const [],
      servicesFailed: false,
      seen: null,
    );
    expect(lines, hasLength(1));
    expect(_byKey(lines)['supported'], 'Not offered by this server');
  });

  test('before the call services answer, and when they fail', () {
    expect(
      _byKey(
        callLines(
          info: null,
          services: null,
          servicesFailed: false,
          seen: null,
        ),
      ),
      {'supported': 'Checking…', 'mediaServer': 'Shown after the first call'},
    );
    expect(
      _byKey(
        callLines(info: null, services: null, servicesFailed: true, seen: null),
      )['supported'],
      'Can’t check',
    );
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
