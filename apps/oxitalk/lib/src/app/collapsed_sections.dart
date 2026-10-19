import 'dart:convert';
import 'dart:io';

/// Which room list sections the user folded, per account; on this device only, as Element
/// does.
abstract interface class CollapsedSections {
  Future<Set<String>> read(String account);

  Future<void> write(String account, Set<String> tags);
}

/// Keeps them in `<dataDir>/collapsed_sections.json`.
final class FileCollapsedSections implements CollapsedSections {
  FileCollapsedSections(Directory dataDir)
    : _file = File('${dataDir.path}/collapsed_sections.json');

  final File _file;

  /// Serializes the read-modify-write of the file.
  Future<void> _lock = Future.value();

  Future<Map<String, Object?>> _readAll() async {
    try {
      return jsonDecode(await _file.readAsString()) as Map<String, Object?>;
    } on Object {
      return {};
    }
  }

  @override
  Future<Set<String>> read(String account) async => {
    for (final tag in (await _readAll())[account] as List<Object?>? ?? const [])
      ?tag as String?,
  };

  @override
  Future<void> write(String account, Set<String> tags) {
    final done = _lock.then((_) async {
      final all = await _readAll();
      if (tags.isEmpty) {
        all.remove(account);
      } else {
        all[account] = tags.toList();
      }
      await _file.writeAsString(jsonEncode(all), flush: true);
    });
    _lock = done.catchError((Object _) {});
    return done;
  }
}

/// For tests.
final class MemoryCollapsedSections implements CollapsedSections {
  final values = <String, Set<String>>{};

  @override
  Future<Set<String>> read(String account) async => {...?values[account]};

  @override
  Future<void> write(String account, Set<String> tags) async =>
      values[account] = {...tags};
}
