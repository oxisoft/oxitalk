import 'dart:convert';
import 'dart:io';

/// How the window was left, on this device: the chat list narrowed, the account rail hidden,
/// and each account's open chat.
abstract interface class UiPrefs {
  bool get narrowList;
  bool get railHidden;

  /// The chat [account] had open, if any.
  String? lastRoom(String account);

  Future<void> setNarrowList({required bool narrow});
  Future<void> setRailHidden({required bool hidden});
  Future<void> setLastRoom(String account, String? roomId);
}

/// Keeps them in `<dataDir>/ui.json`.
final class FileUiPrefs implements UiPrefs {
  FileUiPrefs._(this._file, this._json);

  static Future<FileUiPrefs> load(Directory dataDir) async {
    final file = File('${dataDir.path}/ui.json');
    var json = <String, Object?>{};
    try {
      json = jsonDecode(await file.readAsString()) as Map<String, Object?>;
    } on Object {
      // Not saved yet, or unreadable: the defaults.
    }
    return FileUiPrefs._(file, json);
  }

  final File _file;
  final Map<String, Object?> _json;

  /// Serializes the writes of the file.
  Future<void> _lock = Future.value();

  Map<String, Object?> get _rooms => switch (_json['lastRooms']) {
    final Map<String, Object?> rooms => rooms,
    _ => _json['lastRooms'] = <String, Object?>{},
  };

  @override
  bool get narrowList => _json['narrowList'] == true;

  @override
  bool get railHidden => _json['railHidden'] == true;

  @override
  String? lastRoom(String account) => _rooms[account] as String?;

  @override
  Future<void> setNarrowList({required bool narrow}) =>
      _save(() => _json['narrowList'] = narrow);

  @override
  Future<void> setRailHidden({required bool hidden}) =>
      _save(() => _json['railHidden'] = hidden);

  @override
  Future<void> setLastRoom(String account, String? roomId) => _save(() {
    if (roomId == null) {
      _rooms.remove(account);
    } else {
      _rooms[account] = roomId;
    }
  });

  Future<void> _save(void Function() change) {
    change();
    final text = jsonEncode(_json);
    final done = _lock.then((_) => _file.writeAsString(text, flush: true));
    _lock = done.catchError((Object _) => _file);
    return done;
  }
}

/// For tests.
final class MemoryUiPrefs implements UiPrefs {
  MemoryUiPrefs({
    this.narrowList = false,
    this.railHidden = false,
    Map<String, String>? lastRooms,
  }) : lastRooms = {...?lastRooms};

  @override
  bool narrowList;

  @override
  bool railHidden;

  final Map<String, String> lastRooms;

  @override
  String? lastRoom(String account) => lastRooms[account];

  @override
  Future<void> setNarrowList({required bool narrow}) async =>
      narrowList = narrow;

  @override
  Future<void> setRailHidden({required bool hidden}) async =>
      railHidden = hidden;

  @override
  Future<void> setLastRoom(String account, String? roomId) async {
    if (roomId == null) {
      lastRooms.remove(account);
    } else {
      lastRooms[account] = roomId;
    }
  }
}
