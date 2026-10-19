import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oxitalk/src/app/diagnostics.dart';
import 'package:oxitalk/src/util/log.dart';

import 'support/rust_core.dart';

String _logged(Directory dir) => [
  for (final file in dir.listSync().whereType<File>()) file.readAsStringSync(),
].join();

Future<bool> _waitFor(Directory dir, String text) async {
  for (var i = 0; i < 50; i++) {
    if (_logged(dir).contains(text)) return true;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  return false;
}

void main() {
  setUpAll(initRustCore);

  test('app lines reach the log file; the setting is saved', () async {
    final dataDir = await Directory.systemTemp.createTemp('oxitalk-diag');
    addTearDown(() => dataDir.delete(recursive: true));

    // Debug builds (and tests) log unless the user turned it off.
    final diagnostics = await RustDiagnostics.start(dataDir);
    expect(diagnostics.collectLogs, isTrue);
    final logDir = Directory(diagnostics.logDir);
    appLog(LogLevel.info, 'test', 'hello from Dart');
    expect(await _waitFor(logDir, 'hello from Dart'), isTrue);

    await diagnostics.setCollectLogs(on: false);
    expect(
      jsonDecode(File('${dataDir.path}/settings.json').readAsStringSync()),
      {'collectLogs': false},
    );
    appLog(LogLevel.error, 'test', 'not logged');

    // Started again, the saved setting wins.
    final again = await RustDiagnostics.start(dataDir);
    expect(again.collectLogs, isFalse);
    await again.setCollectLogs(on: true);
    appLog(LogLevel.info, 'test', 'marker');
    expect(await _waitFor(logDir, 'marker'), isTrue);
    expect(_logged(logDir), isNot(contains('not logged')));
  });
}
