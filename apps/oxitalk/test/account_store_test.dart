import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oxitalk/src/matrix/api/matrix.dart';
import 'package:oxitalk/src/matrix/fakes/fakes.dart';
import 'package:oxitalk/src/matrix/rust/rust_matrix.dart';

import 'support/rust_core.dart';

/// A saved session as the factory stores it. Restoring doesn't contact the server, so the
/// data needs no real account.
Map<String, Object?> _saved(String user, String storeDir) => {
  'homeserverUrl': 'http://localhost:1',
  'userId': '@$user:example.org',
  'deviceId': 'DEVICE${user.toUpperCase()}',
  'accessToken': 'token',
  'storeDir': storeDir,
  'passphrase': 'passphrase',
};

void main() {
  setUpAll(initRustCore);

  late Directory dataDir;
  late MemorySecretStore secrets;
  late RustMatrixClientFactory factory;
  final sessions = <MatrixSession>[];

  setUp(() async {
    dataDir = await Directory.systemTemp.createTemp('oxitalk-accounts');
    secrets = MemorySecretStore();
    factory = RustMatrixClientFactory(
      secrets: secrets,
      dataDir: () async => dataDir,
    );
  });

  tearDown(() async {
    for (final session in sessions) {
      await session.close();
    }
    sessions.clear();
    await dataDir.delete(recursive: true);
  });

  test('every saved account comes back, in order', () async {
    secrets.values['oxitalk.accounts'] = jsonEncode([
      _saved('alice', '${dataDir.path}/a'),
      _saved('bob', '${dataDir.path}/b'),
    ]);
    sessions.addAll(await factory.restoreAll());
    expect(sessions.map((session) => session.userId), [
      '@alice:example.org',
      '@bob:example.org',
    ]);

    await factory.writeActive('@bob:example.org');
    expect(await factory.readActive(), '@bob:example.org');
  });

  test('the single session of earlier versions joins the list', () async {
    secrets.values['oxitalk.session'] = jsonEncode(
      _saved('alice', '${dataDir.path}/a'),
    );
    sessions.addAll(await factory.restoreAll());
    expect(sessions.single.userId, '@alice:example.org');
    expect(secrets.values.containsKey('oxitalk.session'), isFalse);
    expect(
      (jsonDecode(secrets.values['oxitalk.accounts']!) as List).single,
      containsPair('userId', '@alice:example.org'),
    );
  });

  test('closing the accounts keeps them saved', () async {
    secrets.values['oxitalk.accounts'] = jsonEncode([
      _saved('alice', '${dataDir.path}/a'),
      _saved('bob', '${dataDir.path}/b'),
    ]);
    for (final session in await factory.restoreAll()) {
      await session.close();
    }
    final again = await factory.restoreAll();
    expect(again.map((session) => session.userId), [
      '@alice:example.org',
      '@bob:example.org',
    ]);
    sessions.addAll(again);
  });
}
