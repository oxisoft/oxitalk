import 'dart:convert';
import 'dart:io';

/// How long cached pictures and files are kept after they were last used, for all accounts.
abstract interface class MediaPrefs {
  /// `null` keeps them forever.
  int? get retentionDays;

  Future<void> setRetentionDays(int? days);
}

/// The choices the settings offer, in days; `null` is forever.
const retentionChoices = <int?>[7, 30, 90, 365, null];

const defaultRetentionDays = 30;

/// Keeps the setting in `<dataDir>/media.json`.
final class FileMediaPrefs implements MediaPrefs {
  FileMediaPrefs._(this._file, this._days);

  static const _key = 'retentionDays';

  static Future<FileMediaPrefs> load(Directory dataDir) async {
    final file = File('${dataDir.path}/media.json');
    var days = defaultRetentionDays as int?;
    try {
      final json =
          jsonDecode(await file.readAsString()) as Map<String, Object?>;
      if (json.containsKey(_key)) days = json[_key] as int?;
    } on Object {
      // Not set yet, or unreadable: the default.
    }
    return FileMediaPrefs._(file, days);
  }

  final File _file;
  int? _days;

  @override
  int? get retentionDays => _days;

  @override
  Future<void> setRetentionDays(int? days) async {
    _days = days;
    await _file.writeAsString(jsonEncode({_key: days}), flush: true);
  }
}

/// For tests.
final class MemoryMediaPrefs implements MediaPrefs {
  MemoryMediaPrefs([this.retentionDays = defaultRetentionDays]);

  @override
  int? retentionDays;

  @override
  Future<void> setRetentionDays(int? days) async => retentionDays = days;
}
