import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../rust/api/logging.dart' as rust;
import '../util/log.dart';

/// Diagnostic logs on this device, which the user turns on in the settings. Off by default in
/// release builds, on in debug builds.
abstract interface class Diagnostics {
  bool get collectLogs;

  /// Where the log files are.
  String get logDir;

  Future<void> setCollectLogs({required bool on});
}

/// Logs through the Rust core: the SDK's lines and the app's, in daily files in [logDir].
final class RustDiagnostics implements Diagnostics {
  RustDiagnostics._(this._settingsFile, this.logDir, this._collectLogs);

  static const _collectLogsKey = 'collectLogs';

  /// Reads the setting from `<dataDir>/settings.json` and starts logging to `<dataDir>/logs/`.
  static Future<RustDiagnostics> start(Directory dataDir) async {
    final settingsFile = File('${dataDir.path}/settings.json');
    final logDir = Directory('${dataDir.path}/logs')
      ..createSync(recursive: true);
    final diagnostics = RustDiagnostics._(
      settingsFile,
      logDir.path,
      (await _readSettings(settingsFile))[_collectLogsKey] as bool? ??
          !kReleaseMode,
    );
    rust.initLogging(dir: logDir.path, enabled: diagnostics._collectLogs);
    logSink = (level, target, message) => rust.writeLog(
      level: switch (level) {
        LogLevel.error => rust.LogLevel.error,
        LogLevel.warn => rust.LogLevel.warn,
        LogLevel.info => rust.LogLevel.info,
        LogLevel.debug => rust.LogLevel.debug,
      },
      target: target,
      message: message,
    );
    return diagnostics;
  }

  final File _settingsFile;
  bool _collectLogs;

  @override
  final String logDir;

  @override
  bool get collectLogs => _collectLogs;

  @override
  Future<void> setCollectLogs({required bool on}) async {
    _collectLogs = on;
    rust.setLogging(enabled: on);
    final settings = await _readSettings(_settingsFile);
    settings[_collectLogsKey] = on;
    await _settingsFile.writeAsString(jsonEncode(settings));
  }

  static Future<Map<String, Object?>> _readSettings(File file) async {
    try {
      return jsonDecode(await file.readAsString()) as Map<String, Object?>;
    } on Object {
      return {};
    }
  }
}

/// For tests: remembers the setting, writes nothing.
final class MemoryDiagnostics implements Diagnostics {
  MemoryDiagnostics({this.collectLogs = false});

  @override
  bool collectLogs;

  @override
  String get logDir => '/tmp/oxitalk-logs';

  @override
  Future<void> setCollectLogs({required bool on}) async => collectLogs = on;
}
