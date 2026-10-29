import 'dart:convert';
import 'dart:io';

/// How the window was left, on this device: the chat list narrowed or resized, the thread
/// pane resized, the account rail hidden, and each account's open chat.
abstract interface class UiPrefs {
  bool get narrowList;
  bool get railHidden;

  /// The width the chat list was dragged to on a wide window; null for the default.
  double? get listWidth;

  /// The width the thread pane was dragged to; null for the default.
  double? get threadWidth;

  /// Whether messages are sent formatted from their markdown; on unless turned off.
  bool get useMarkdown;

  /// Whether the user's typing is shown to the others; on unless turned off.
  bool get sendTyping;

  /// Whether typed emoticons like `:)` become emoji; on unless turned off.
  bool get replaceEmoticons;

  /// Whether the timeline shows who joined, left or changed their profile; on unless
  /// turned off.
  bool get showMembershipEvents;

  /// `light` or `dark`; anything else follows the system.
  String get theme;

  /// Whether this device shows OS notifications; on unless turned off.
  bool get notificationsEnabled;

  /// Whether a notification shows the message's text, else only "New message"; on unless
  /// turned off.
  bool get notificationText;

  /// Whether a notification plays a sound where the push rules ask for one; on unless turned
  /// off.
  bool get notificationSound;

  /// The chat [account] had open, if any.
  String? lastRoom(String account);

  /// The call media server [account] last connected to, if it ever did.
  CallServerSeen? callServer(String account);

  /// Whether a server admin's [account] compares its server's versions with the latest
  /// releases; on unless turned off.
  bool serverUpdateCheck(String account);

  Future<void> setNarrowList({required bool narrow});
  Future<void> setRailHidden({required bool hidden});

  /// Null goes back to the default width.
  Future<void> setListWidth(double? width);

  /// Null goes back to the default width.
  Future<void> setThreadWidth(double? width);
  Future<void> setUseMarkdown({required bool on});
  Future<void> setSendTyping({required bool on});
  Future<void> setReplaceEmoticons({required bool on});
  Future<void> setTheme(String theme);
  Future<void> setShowMembershipEvents({required bool on});
  Future<void> setNotificationsEnabled({required bool on});
  Future<void> setNotificationText({required bool on});
  Future<void> setNotificationSound({required bool on});
  Future<void> setLastRoom(String account, String? roomId);
  Future<void> setCallServer(String account, CallServerSeen server);
  Future<void> setServerUpdateCheck(String account, {required bool on});
}

/// The LiveKit server a call connected to: its address, and the version and region it
/// told when it let this device in. Only a call learns them (the server answers nothing
/// before a join), so About shows the last one seen.
final class CallServerSeen {
  const CallServerSeen({
    required this.url,
    required this.seenAt,
    this.version,
    this.region,
  });

  static CallServerSeen? fromJson(Object? json) => switch (json) {
    {'url': final String url, 'seenAt': final String seenAt} =>
      switch (DateTime.tryParse(seenAt)) {
        final at? => CallServerSeen(
          url: url,
          seenAt: at,
          version: json['version'] as String?,
          region: json['region'] as String?,
        ),
        null => null,
      },
    _ => null,
  };

  final String url;
  final DateTime seenAt;
  final String? version;
  final String? region;

  Map<String, Object?> toJson() => {
    'url': url,
    'seenAt': seenAt.toUtc().toIso8601String(),
    if (version != null) 'version': version,
    if (region != null) 'region': region,
  };
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
  double? get listWidth => (_json['listWidth'] as num?)?.toDouble();

  @override
  double? get threadWidth => (_json['threadWidth'] as num?)?.toDouble();

  @override
  bool get useMarkdown => _json['useMarkdown'] != false;

  @override
  bool get sendTyping => _json['sendTyping'] != false;

  @override
  bool get replaceEmoticons => _json['replaceEmoticons'] != false;

  @override
  String get theme => _json['theme'] as String? ?? 'system';

  @override
  bool get showMembershipEvents => _json['showMembershipEvents'] != false;

  @override
  bool get notificationsEnabled => _json['notificationsEnabled'] != false;

  @override
  bool get notificationText => _json['notificationText'] != false;

  @override
  bool get notificationSound => _json['notificationSound'] != false;

  @override
  String? lastRoom(String account) => _rooms[account] as String?;

  @override
  CallServerSeen? callServer(String account) => switch (_json['callServers']) {
    final Map<String, Object?> servers => CallServerSeen.fromJson(
      servers[account],
    ),
    _ => null,
  };

  @override
  Future<void> setNarrowList({required bool narrow}) =>
      _save(() => _json['narrowList'] = narrow);

  @override
  Future<void> setRailHidden({required bool hidden}) =>
      _save(() => _json['railHidden'] = hidden);

  @override
  Future<void> setListWidth(double? width) => _save(
    () =>
        width == null ? _json.remove('listWidth') : _json['listWidth'] = width,
  );

  @override
  Future<void> setThreadWidth(double? width) => _save(
    () => width == null
        ? _json.remove('threadWidth')
        : _json['threadWidth'] = width,
  );

  @override
  Future<void> setUseMarkdown({required bool on}) =>
      _save(() => _json['useMarkdown'] = on);

  @override
  Future<void> setSendTyping({required bool on}) =>
      _save(() => _json['sendTyping'] = on);

  @override
  Future<void> setReplaceEmoticons({required bool on}) =>
      _save(() => _json['replaceEmoticons'] = on);

  @override
  Future<void> setTheme(String theme) => _save(() => _json['theme'] = theme);

  @override
  Future<void> setShowMembershipEvents({required bool on}) =>
      _save(() => _json['showMembershipEvents'] = on);

  @override
  Future<void> setNotificationsEnabled({required bool on}) =>
      _save(() => _json['notificationsEnabled'] = on);

  @override
  Future<void> setNotificationText({required bool on}) =>
      _save(() => _json['notificationText'] = on);

  @override
  Future<void> setNotificationSound({required bool on}) =>
      _save(() => _json['notificationSound'] = on);

  @override
  Future<void> setLastRoom(String account, String? roomId) => _save(() {
    if (roomId == null) {
      _rooms.remove(account);
    } else {
      _rooms[account] = roomId;
    }
  });

  @override
  bool serverUpdateCheck(String account) => switch (_json['serverUpdatesOff']) {
    final List<Object?> off => !off.contains(account),
    _ => true,
  };

  @override
  Future<void> setServerUpdateCheck(String account, {required bool on}) =>
      _save(() {
        final off = <Object?>[...?(_json['serverUpdatesOff'] as List<Object?>?)]
          ..remove(account);
        if (!on) off.add(account);
        _json['serverUpdatesOff'] = off;
      });

  @override
  Future<void> setCallServer(String account, CallServerSeen server) =>
      _save(() {
        final servers = switch (_json['callServers']) {
          final Map<String, Object?> servers => servers,
          _ => _json['callServers'] = <String, Object?>{},
        };
        servers[account] = server.toJson();
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
    this.listWidth,
    this.threadWidth,
    this.useMarkdown = true,
    this.sendTyping = true,
    this.replaceEmoticons = true,
    this.theme = 'system',
    this.showMembershipEvents = true,
    this.notificationsEnabled = true,
    this.notificationText = true,
    this.notificationSound = true,
    Map<String, String>? lastRooms,
    Map<String, CallServerSeen>? callServers,
  }) : lastRooms = {...?lastRooms},
       callServers = {...?callServers};

  @override
  bool narrowList;

  @override
  bool railHidden;

  @override
  double? listWidth;

  @override
  double? threadWidth;

  @override
  bool useMarkdown;

  @override
  bool sendTyping;

  @override
  bool replaceEmoticons;

  @override
  String theme;

  @override
  bool showMembershipEvents;

  @override
  bool notificationsEnabled;

  @override
  bool notificationText;

  @override
  bool notificationSound;

  final Map<String, String> lastRooms;

  final Map<String, CallServerSeen> callServers;

  @override
  String? lastRoom(String account) => lastRooms[account];

  @override
  CallServerSeen? callServer(String account) => callServers[account];

  /// The accounts whose server update check is off.
  final Set<String> serverUpdatesOff = {};

  @override
  bool serverUpdateCheck(String account) => !serverUpdatesOff.contains(account);

  @override
  Future<void> setServerUpdateCheck(String account, {required bool on}) async {
    if (on) {
      serverUpdatesOff.remove(account);
    } else {
      serverUpdatesOff.add(account);
    }
  }

  @override
  Future<void> setCallServer(String account, CallServerSeen server) async =>
      callServers[account] = server;

  @override
  Future<void> setNarrowList({required bool narrow}) async =>
      narrowList = narrow;

  @override
  Future<void> setRailHidden({required bool hidden}) async =>
      railHidden = hidden;

  @override
  Future<void> setListWidth(double? width) async => listWidth = width;

  @override
  Future<void> setThreadWidth(double? width) async => threadWidth = width;

  @override
  Future<void> setUseMarkdown({required bool on}) async => useMarkdown = on;

  @override
  Future<void> setSendTyping({required bool on}) async => sendTyping = on;

  @override
  Future<void> setReplaceEmoticons({required bool on}) async =>
      replaceEmoticons = on;

  @override
  Future<void> setTheme(String theme) async => this.theme = theme;

  @override
  Future<void> setShowMembershipEvents({required bool on}) async =>
      showMembershipEvents = on;

  @override
  Future<void> setNotificationsEnabled({required bool on}) async =>
      notificationsEnabled = on;

  @override
  Future<void> setNotificationText({required bool on}) async =>
      notificationText = on;

  @override
  Future<void> setNotificationSound({required bool on}) async =>
      notificationSound = on;

  @override
  Future<void> setLastRoom(String account, String? roomId) async {
    if (roomId == null) {
      lastRooms.remove(account);
    } else {
      lastRooms[account] = roomId;
    }
  }
}
