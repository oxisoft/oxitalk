import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../../rust/api/error.dart';
import '../../rust/api/pins.dart' as pins_api;
import '../../rust/api/room_list.dart' as rust;
import '../../rust/api/rooms.dart' as rust;
import '../../rust/api/sections.dart' as rust;
import '../../rust/api/session.dart' as rust;
import '../../rust/api/threads.dart' as thread_api;
import '../../rust/api/timeline.dart' as rust;
import '../../rust/api/verification.dart' as rust;
import '../../rust/api/voice.dart' as voice;
import '../../util/latest.dart';
import '../../util/log.dart';
import '../api/matrix.dart';
import '../api/secret_store.dart';
import 'diffs.dart';
import 'mapping.dart';
import 'sync_supervisor.dart';

/// The Matrix layer on the Rust core. The accounts' session data and store passphrases are
/// kept in [secrets], each account's store under `<dataDir>/accounts/<random id>/`.
///
/// Only the store's path inside [_dataDir] is saved: iOS moves the app's data to a new
/// container folder on every update, so a saved full path stops pointing at the store.
final class RustMatrixClientFactory implements MatrixClientFactory {
  RustMatrixClientFactory({required this._secrets, required this._dataDir});

  static const _accountsKey = 'oxitalk.accounts';
  static const _activeKey = 'oxitalk.activeAccount';

  /// Where v0.1.7 and earlier kept their only session; moved into the list on first start.
  static const _legacyKey = 'oxitalk.session';

  final SecretStore _secrets;
  final Future<Directory> Function() _dataDir;

  /// Serializes the read-modify-write of the account list.
  Future<void> _lock = Future.value();

  @override
  List<String> get unopened => List.unmodifiable(_unopened);
  final _unopened = <String>[];

  @override
  Future<MatrixSession> login({
    required String server,
    required String username,
    required String password,
  }) async {
    final store = 'accounts/${_randomId()}';
    final storeDir = Directory(await _path(store));
    final passphrase = _randomSecret();
    try {
      final session = await guarded(
        () => rust.login(
          server: server,
          username: username,
          password: password,
          storeDir: storeDir.path,
          storePassphrase: passphrase,
        ),
      );
      final saved = _SavedSession(session.sessionData(), store, passphrase);
      final userId = saved.data.userId;
      // An account saved before but not opened at the start is replaced by the new login.
      final replaced = <_SavedSession>[];
      var duplicate = false;
      await _update((accounts) {
        duplicate = accounts.any(
          (a) => a.data.userId == userId && !_unopened.contains(userId),
        );
        if (duplicate) return accounts;
        replaced.addAll(accounts.where((a) => a.data.userId == userId));
        return [
          for (final account in accounts)
            if (account.data.userId != userId) account,
          saved,
        ];
      });
      if (duplicate) {
        // The login made a new device on the server; take it away again.
        await session.logout().catchError((Object _) {});
        session.dispose();
        throw MatrixFailure(FailureKind.alreadyLoggedIn, saved.data.userId);
      }
      _unopened.remove(userId);
      for (final old in replaced) {
        await _deleteDir(await _path(old.store));
      }
      return RustMatrixSession._(session, () => _forget(saved.store));
    } catch (_) {
      await _deleteDir(storeDir.path);
      rethrow;
    }
  }

  @override
  Future<List<MatrixSession>> restoreAll() async {
    await _migrateLegacy();
    await _relocate();
    _unopened.clear();
    final sessions = <MatrixSession>[];
    for (final saved in await _read()) {
      final storeDir = await _path(saved.store);
      try {
        if (!Directory(storeDir).existsSync()) {
          throw FileSystemException('store missing', storeDir);
        }
        final session = await rust.restore(
          data: saved.data,
          storeDir: storeDir,
          storePassphrase: saved.passphrase,
        );
        sessions.add(RustMatrixSession._(session, () => _forget(saved.store)));
      } on Object catch (error) {
        // Kept, never deleted here: the store holds the account's encryption keys, and the
        // cause can pass (a locked keychain, a moved folder). The next start tries again;
        // logging in to the account again replaces it.
        appLog(
          LogLevel.error,
          'accounts',
          'could not open ${saved.data.userId}: $error',
        );
        _unopened.add(saved.data.userId);
      }
    }
    return sessions;
  }

  @override
  Future<String?> readActive() => _secrets.read(_activeKey);

  @override
  Future<void> writeActive(String userId) => _secrets.write(_activeKey, userId);

  Future<void> _forget(String store) async {
    await _update(
      (accounts) => [
        for (final account in accounts)
          if (account.store != store) account,
      ],
    );
    await _deleteDir(await _path(store));
  }

  /// The full path of a [store] saved inside the data folder; a full path (from a version
  /// that saved those, not found where it pointed) as it is.
  Future<String> _path(String store) async =>
      store.startsWith('/') || store.contains(':')
      ? store
      : '${(await _dataDir()).path}/$store';

  /// Versions up to 0.1.27 saved each store's full path. Turns those into paths inside the
  /// data folder: the same folder name under the current data folder's `accounts`, which
  /// finds the store again after iOS moved the app's data on an update.
  Future<void> _relocate() async {
    final accounts = await _read();
    if (!accounts.any((account) => _isFull(account.store))) return;
    final dataDir = (await _dataDir()).path;
    await _update(
      (accounts) => [
        for (final account in accounts)
          _isFull(account.store)
              ? account.withStore(_inside(dataDir, account.store))
              : account,
      ],
    );
  }

  static bool _isFull(String store) =>
      store.startsWith('/') || store.contains(':');

  /// [full] inside [dataDir]; else `accounts/<its folder name>` when that exists, which is
  /// where every version kept the stores; else [full] unchanged.
  static String _inside(String dataDir, String full) {
    final normal = full.replaceAll(r'\', '/');
    final root = '${dataDir.replaceAll(r'\', '/')}/';
    if (normal.startsWith(root)) return normal.substring(root.length);
    final name = normal.split('/').lastWhere((part) => part.isNotEmpty);
    return Directory('$dataDir/accounts/$name').existsSync()
        ? 'accounts/$name'
        : full;
  }

  Future<List<_SavedSession>> _read() async {
    final json = await _secrets.read(_accountsKey);
    if (json == null) return [];
    try {
      return [
        for (final account in jsonDecode(json) as List<Object?>)
          _SavedSession.fromJson(account! as Map<String, Object?>),
      ];
    } on Object {
      await _secrets.delete(_accountsKey);
      return [];
    }
  }

  /// Applies [change] to the saved account list, one change at a time.
  Future<void> _update(
    List<_SavedSession> Function(List<_SavedSession>) change,
  ) {
    final done = _lock.then((_) async {
      final accounts = change(await _read());
      await _secrets.write(
        _accountsKey,
        jsonEncode([for (final account in accounts) account.toJson()]),
      );
    });
    _lock = done.catchError((Object _) {});
    return done;
  }

  Future<void> _migrateLegacy() async {
    final json = await _secrets.read(_legacyKey);
    if (json == null) return;
    try {
      final saved = _SavedSession.fromJson(
        jsonDecode(json) as Map<String, Object?>,
      );
      await _update((accounts) => [...accounts, saved]);
    } on Object {
      // Unreadable; dropped below.
    }
    await _secrets.delete(_legacyKey);
  }

  static Future<void> _deleteDir(String path) async {
    final dir = Directory(path);
    if (dir.existsSync()) await dir.delete(recursive: true);
  }

  static String _randomId() => List.generate(
    16,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();

  static String _randomSecret() =>
      base64Url.encode(List.generate(32, (_) => Random.secure().nextInt(256)));
}

final class _SavedSession {
  _SavedSession(this.data, this.store, this.passphrase);

  factory _SavedSession.fromJson(Map<String, Object?> json) => _SavedSession(
    rust.SessionData(
      homeserverUrl: json['homeserverUrl']! as String,
      userId: json['userId']! as String,
      deviceId: json['deviceId']! as String,
      accessToken: json['accessToken']! as String,
    ),
    // `storeDir`: the full path, as versions up to 0.1.27 saved it.
    (json['store'] ?? json['storeDir'])! as String,
    json['passphrase']! as String,
  );

  final rust.SessionData data;

  /// The store's path inside the data folder (`accounts/<id>`), or a full path kept from an
  /// earlier version when the store wasn't found inside the data folder.
  final String store;
  final String passphrase;

  _SavedSession withStore(String store) =>
      _SavedSession(data, store, passphrase);

  Map<String, Object?> toJson() => {
    'homeserverUrl': data.homeserverUrl,
    'userId': data.userId,
    'deviceId': data.deviceId,
    'accessToken': data.accessToken,
    'store': store,
    'passphrase': passphrase,
  };
}

final class RustMatrixSession implements MatrixSession {
  RustMatrixSession._(this._session, this._forget)
    : userId = _session.userId() {
    _supervisor = SyncSupervisor(
      states: _session.subscribeSyncState(),
      start: _session.startSync,
    );
    _subscriptions
      ..add(
        _session.subscribeRooms().listen((batch) {
          for (final diff in batch) {
            applyRoomListDiff(_summaries, diff);
          }
          _rooms.value = [for (final summary in _summaries) roomOf(summary)];
        }),
      )
      ..add(
        _session.subscribeTyping().listen(
          (update) => _typing.value = {
            for (final entry in _typing.value.entries)
              if (entry.key != update.roomId) entry.key: entry.value,
            if (update.names.isNotEmpty) update.roomId: update.names,
          },
        ),
      )
      ..add(
        _session.subscribeSections().listen(
          (update) =>
              _sections.value = applySectionsUpdate(_sections.value, update),
        ),
      )
      ..add(
        _session.subscribeNotificationSettings().listen(
          (state) =>
              _notificationSettings.value = notificationSettingsOf(state),
        ),
      )
      ..add(
        _session.subscribeNotifications().listen(
          (item) => _notifications.add(messageNotificationOf(item)),
        ),
      )
      ..add(
        _session.subscribeVerificationStatus().listen(
          (status) => _verificationStatus.value = verificationStatusOf(status),
        ),
      )
      ..add(
        _session.subscribeEncryptionStatus().listen(
          (status) => _encryptionStatus.value = encryptionStatusOf(status),
        ),
      )
      ..add(
        _session.subscribeVerificationRequests().listen(
          (request) => _verificationRequests.add(
            VerificationRequest(
              flowId: request.flowId,
              deviceId: request.deviceId,
              deviceName: request.deviceName,
            ),
          ),
        ),
      )
      ..add(
        // Fetched again whenever the connection comes back, since a fetch offline has only
        // what the store remembers.
        _supervisor.status.stream.listen((status) {
          final online = status == SyncStatus.online;
          if (online && !_online) unawaited(_refreshProfile());
          _online = online;
        }),
      )
      ..add(
        _session.subscribeSessionChanges().listen((change) {
          if (change is rust.SessionChange_UnknownToken) {
            unawaited(_onTokenRejected());
          }
        }),
      );
    unawaited(_session.startSync());
    unawaited(_refreshProfile());
  }

  final rust.Session _session;
  final Future<void> Function() _forget;
  late final SyncSupervisor _supervisor;
  final _subscriptions = <StreamSubscription<Object?>>[];
  final _summaries = <rust.RoomSummary>[];
  final _rooms = Latest<List<Room>?>(null);
  final _profile = Latest(const Profile());
  final _sections = Latest(const Sections());
  final _notificationSettings = Latest<NotificationSettings?>(null);
  final _notifications = StreamController<MessageNotification>.broadcast();
  final _typing = Latest(const <String, List<String>>{});
  final _verificationStatus = Latest(VerificationStatus.unknown);
  final _encryptionStatus = Latest(const EncryptionStatus());
  final _verificationRequests =
      StreamController<VerificationRequest>.broadcast();
  final _expired = Completer<void>();
  var _online = false;
  var _closed = false;

  @override
  final String userId;

  @override
  Stream<SyncStatus> get syncStatus => _supervisor.status.stream;

  @override
  Stream<List<Room>?> get rooms => _rooms.stream;

  @override
  Future<void> get expired => _expired.future;

  @override
  Stream<VerificationStatus> get verificationStatus =>
      _verificationStatus.stream;

  @override
  Stream<VerificationRequest> get verificationRequests =>
      _verificationRequests.stream;

  @override
  Future<void> recover(String key) => guarded(() => _session.recover(key: key));

  @override
  Future<DeviceVerification> requestVerification() async =>
      RustDeviceVerification._(
        await guarded(_session.requestSelfVerification),
        weAsked: true,
      );

  @override
  Future<DeviceVerification> openVerification(String flowId) async =>
      RustDeviceVerification._(
        await guarded(() => _session.verification(flowId: flowId)),
        weAsked: false,
      );

  @override
  Stream<EncryptionStatus> get encryptionStatus => _encryptionStatus.stream;

  @override
  Future<String> enableRecovery({
    void Function(RecoveryProgress)? onProgress,
  }) async {
    final progress = _session.subscribeRecoveryProgress().listen((step) {
      if (recoveryProgressOf(step) case final step?) onProgress?.call(step);
    });
    try {
      return await guarded(_session.enableRecovery);
    } finally {
      // Not awaited: see close.
      unawaited(progress.cancel());
    }
  }

  @override
  Future<String> resetRecoveryKey() => guarded(_session.resetRecoveryKey);

  @override
  Future<bool> isLastDevice() => guarded(_session.isLastDevice);

  @override
  Future<List<Device>> devices() async => [
    for (final device in await guarded(_session.devices)) deviceOf(device),
  ];

  @override
  Stream<List<Device>> get deviceChanges => _session.subscribeDevices().map(
    (list) => [for (final device in list) deviceOf(device)],
  );

  @override
  Future<void> renameDevice(String deviceId, String name) =>
      guarded(() => _session.renameDevice(deviceId: deviceId, name: name));

  @override
  Future<void> signOutDevices(List<String> deviceIds, {String? password}) =>
      guarded(
        () => _session.signOutDevices(deviceIds: deviceIds, password: password),
      );

  @override
  Future<DeviceVerification> verifyDevice(String deviceId) async =>
      RustDeviceVerification._(
        await guarded(() => _session.verifyDevice(deviceId: deviceId)),
        weAsked: true,
      );

  @override
  Stream<Profile> get profile => _profile.stream;

  Future<void> _refreshProfile() async {
    try {
      final profile = await guarded(_session.ownProfile);
      if (_closed) return;
      _profile.value = Profile(
        displayName: profile.displayName,
        avatarUrl: profile.avatarUrl,
      );
    } on MatrixFailure {
      // Shown as it was; fetched again when the connection comes back.
    }
  }

  @override
  Future<void> setAvatar(Uint8List data, String mimeType) async {
    await guarded(() => _session.setAvatar(data: data, mimeType: mimeType));
    await _refreshProfile();
  }

  @override
  Future<void> removeAvatar() async {
    await guarded(_session.removeAvatar);
    await _refreshProfile();
  }

  @override
  Future<Uint8List> thumbnail(String mxcUrl, int size) =>
      guarded(() => _session.thumbnail(mxcUri: mxcUrl, size: size));

  @override
  Stream<Sections> get sections => _sections.stream;

  @override
  Stream<Map<String, List<String>>> get typing => _typing.stream;

  @override
  Future<void> setRoomSection(String roomId, String? tag) =>
      guarded(() => _session.setRoomSection(roomId: roomId, tag: tag));

  @override
  Future<void> saveSections(List<CustomSection> custom, List<String> order) =>
      guarded(
        () => _session.saveSectionSettings(
          settings: rust.SectionSettings(
            sections: [
              for (final section in custom)
                rust.CustomSection(tag: section.tag, name: section.name),
            ],
            order: order,
          ),
        ),
      );

  @override
  Stream<MessageNotification> get notifications => _notifications.stream;

  @override
  Stream<NotificationSettings?> get notificationSettings =>
      _notificationSettings.stream;

  @override
  Future<void> setRoomNotificationMode(String roomId, NotificationMode? mode) =>
      guarded(
        () => _session.setRoomNotificationMode(
          roomId: roomId,
          mode: switch (mode) {
            final mode? => rustNotificationMode(mode),
            null => null,
          },
        ),
      );

  @override
  Future<void> setDefaultNotificationMode({
    required bool directChats,
    required NotificationMode mode,
  }) => guarded(
    () => _session.setDefaultNotificationMode(
      oneToOne: directChats,
      mode: rustNotificationMode(mode),
    ),
  );

  @override
  Future<void> fixNotificationDefaults() =>
      guarded(_session.fixInconsistentNotificationDefaults);

  @override
  Future<void> setRoomMentionsEnabled(bool enabled) =>
      guarded(() => _session.setRoomMentionsEnabled(enabled: enabled));

  @override
  Future<void> setInvitesEnabled(bool enabled) =>
      guarded(() => _session.setInvitesEnabled(enabled: enabled));

  @override
  Future<void> addNotificationKeyword(String keyword) =>
      guarded(() => _session.addNotificationKeyword(keyword: keyword));

  @override
  Future<void> removeNotificationKeyword(String keyword) =>
      guarded(() => _session.removeNotificationKeyword(keyword: keyword));

  @override
  Future<void> setMarkedUnread(String roomId, bool unread) =>
      guarded(() => _session.setMarkedUnread(roomId: roomId, unread: unread));

  @override
  Future<void> markRoomRead(String roomId) =>
      guarded(() => _session.markRoomRead(roomId: roomId));

  @override
  Future<Uint8List> mediaContent(String source) =>
      guarded(() => _session.mediaContent(source: source));

  @override
  Future<Uint8List> mediaThumbnail(
    String source,
    String? thumbnail,
    int size,
  ) => guarded(
    () => _session.mediaThumbnail(
      source: source,
      thumbnail: thumbnail,
      size: size,
    ),
  );

  @override
  Future<void> saveMedia(String source, String path) =>
      guarded(() => _session.saveMedia(source: source, path: path));

  @override
  Future<void> setMediaRetention(int? days) =>
      guarded(() => _session.setMediaRetention(days: days));

  @override
  Future<int?> mediaCacheSize() => guarded(_session.mediaCacheSize);

  @override
  Future<void> clearMediaCache() => guarded(_session.clearMediaCache);

  @override
  Future<RoomDetails> roomDetails(String roomId) async =>
      roomDetailsOf(await guarded(() => _session.roomDetails(roomId: roomId)));

  @override
  Stream<RoomSettings> roomSettings(String roomId) => _session
      .subscribeRoomSettings(roomId: roomId)
      .map(roomSettingsOf)
      .handleError(
        (Object error) => throw failure(error as CoreError),
        test: (error) => error is CoreError,
      );

  @override
  Future<void> setRoomName(String roomId, String name) =>
      guarded(() => _session.setRoomName(roomId: roomId, name: name));

  @override
  Future<void> setRoomTopic(String roomId, String topic) =>
      guarded(() => _session.setRoomTopic(roomId: roomId, topic: topic));

  @override
  Future<void> setRoomAvatar(String roomId, Uint8List data, String mimeType) =>
      guarded(
        () => _session.setRoomAvatar(
          roomId: roomId,
          data: data,
          mimeType: mimeType,
        ),
      );

  @override
  Future<void> removeRoomAvatar(String roomId) =>
      guarded(() => _session.removeRoomAvatar(roomId: roomId));

  @override
  Future<void> setRoomJoinRule(String roomId, RoomJoinRule rule) => guarded(
    () => _session.setRoomJoinRule(roomId: roomId, rule: rustJoinRule(rule)),
  );

  @override
  Future<void> setRoomHistory(String roomId, RoomHistory history) => guarded(
    () =>
        _session.setRoomHistory(roomId: roomId, history: rustHistory(history)),
  );

  @override
  Future<void> enableRoomEncryption(String roomId) =>
      guarded(() => _session.enableRoomEncryption(roomId: roomId));

  @override
  Future<bool> setRoomMainAddress(String roomId, String localpart) => guarded(
    () => _session.setRoomMainAddress(roomId: roomId, localpart: localpart),
  );

  @override
  Future<bool> roomPublished(String roomId) =>
      guarded(() => _session.roomPublished(roomId: roomId));

  @override
  Future<void> setRoomPublished(String roomId, bool published) => guarded(
    () => _session.setRoomPublished(roomId: roomId, published: published),
  );

  @override
  Future<List<RoomMember>> roomMembers(String roomId) async => [
    for (final member in await guarded(
      () => _session.roomMembers(roomId: roomId),
    ))
      roomMemberOf(member),
  ];

  @override
  Future<RoomTimeline> openMediaTimeline(String roomId) async =>
      RustRoomTimeline._(
        await guarded(() => _session.mediaTimeline(roomId: roomId)),
      );

  @override
  Future<List<String>> recentEmojis() => guarded(_session.recentEmojis);

  @override
  Future<void> addRecentEmoji(String emoji) =>
      guarded(() => _session.addRecentEmoji(emoji: emoji));

  @override
  Future<String> createDm(String userId) =>
      guarded(() => _session.createDm(userId: userId));

  @override
  Future<String> createRoom({
    required String name,
    String? topic,
    bool public = false,
    String? alias,
    bool encrypted = true,
    Uint8List? avatar,
    String? avatarMimeType,
  }) => guarded(
    () => _session.createRoom(
      room: rust.NewRoom(
        name: name,
        topic: topic,
        public: public,
        alias: alias,
        encrypted: encrypted,
        avatar: avatar == null || avatarMimeType == null
            ? null
            : rust.RoomAvatar(data: avatar, mimeType: avatarMimeType),
      ),
    ),
  );

  @override
  Future<List<Person>> knownPeople() async => [
    for (final person in await guarded(() => _session.knownPeople(limit: 200)))
      Person(
        person.userId,
        displayName: person.displayName,
        avatarUrl: person.avatarUrl,
      ),
  ];

  @override
  Future<List<Person>> searchPeople(String term) async => [
    for (final person in await guarded(
      () => _session.searchPeople(term: term, limit: 30),
    ))
      Person(
        person.userId,
        displayName: person.displayName,
        avatarUrl: person.avatarUrl,
      ),
  ];

  @override
  String? dmWith(String userId) {
    try {
      return _session.dmWith(userId: userId);
    } on Object {
      return null;
    }
  }

  @override
  Future<List<PublicRoom>> publicRooms(String? term) async => [
    for (final room in await guarded(
      () => _session.publicRooms(term: term, limit: 100),
    ))
      PublicRoom(
        roomId: room.roomId,
        name: room.name,
        topic: room.topic,
        alias: room.alias,
        members: room.members,
        avatarUrl: room.avatarUrl,
        joined: room.joined,
      ),
  ];

  @override
  Future<void> setPowerLevel(String roomId, String userId, int level) =>
      guarded(
        () => _session.setPowerLevel(
          roomId: roomId,
          userId: userId,
          level: level,
        ),
      );

  @override
  Future<void> removeMember(String roomId, String userId, {String? reason}) =>
      guarded(
        () => _session.removeMember(
          roomId: roomId,
          userId: userId,
          reason: reason,
        ),
      );

  @override
  Future<void> banMember(String roomId, String userId, {String? reason}) =>
      guarded(
        () =>
            _session.banMember(roomId: roomId, userId: userId, reason: reason),
      );

  @override
  Future<void> unbanMember(String roomId, String userId) =>
      guarded(() => _session.unbanMember(roomId: roomId, userId: userId));

  @override
  Future<String> joinByAddress(String address) =>
      guarded(() => _session.joinByAddress(address: address));

  @override
  Future<void> invite(String roomId, String userId) =>
      guarded(() => _session.invite(roomId: roomId, userId: userId));

  @override
  Future<void> join(String roomId) =>
      guarded(() => _session.join(roomId: roomId));

  @override
  Future<RoomTimeline> openTimeline(String roomId) async => RustRoomTimeline._(
    await guarded(() => _session.timeline(roomId: roomId)),
  );

  @override
  Future<RoomTimeline> openThread(String roomId, String rootEventId) async =>
      RustRoomTimeline._(
        await guarded(
          () =>
              _session.threadTimeline(roomId: roomId, rootEventId: rootEventId),
        ),
      );

  @override
  Future<ThreadList> openThreadList(String roomId) async => RustThreadList._(
    await guarded(() => _session.threadList(roomId: roomId)),
  );

  @override
  Future<RoomTimeline> openTimelineAt(String roomId, String eventId) async =>
      RustRoomTimeline._(
        await guarded(
          () => _session.eventTimeline(roomId: roomId, eventId: eventId),
        ),
      );

  @override
  Future<PinnedEvents> openPins(String roomId) async =>
      RustPinnedEvents._(await guarded(() => _session.pins(roomId: roomId)));

  @override
  Future<RoomTimeline> openPinnedTimeline(String roomId) async =>
      RustRoomTimeline._(
        await guarded(() => _session.pinnedTimeline(roomId: roomId)),
      );

  @override
  Future<SearchResults> searchRoom(
    String roomId,
    String query, {
    int limit = 500,
  }) async => searchResultsOf(
    await guarded(
      () => _session.searchRoom(roomId: roomId, query: query, limit: limit),
    ),
  );

  @override
  Future<bool> searchLoadOlder(String roomId, {int events = 500}) =>
      guarded(() => _session.searchLoadOlder(roomId: roomId, events: events));

  @override
  Future<void> logout() async {
    try {
      await guarded(_session.logout);
    } on MatrixFailure {
      // Logged out locally regardless; the server forgets the device in time.
    }
    await close();
    await _forget();
  }

  Future<void> _onTokenRejected() async {
    await close();
    await _forget();
    if (!_expired.isCompleted) _expired.complete();
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    // A bridge stream's cancel completes only when Rust sends again, which a quiet stream
    // never does; so cancel without waiting.
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    await _supervisor.close();
    await _session.stopSync();
    // Not awaited either: closing a broadcast stream waits for every listener to take the
    // done event, which a paused listener never does.
    unawaited(_rooms.close());
    unawaited(_profile.close());
    unawaited(_sections.close());
    unawaited(_notificationSettings.close());
    unawaited(_notifications.close());
    unawaited(_typing.close());
    unawaited(_verificationStatus.close());
    unawaited(_encryptionStatus.close());
    unawaited(_verificationRequests.close());
    _session.dispose();
  }
}

final class RustThreadList implements ThreadList {
  RustThreadList._(this._list) {
    _subscription = _list.subscribe().listen(
      (list) =>
          _threads.value = [for (final thread in list) roomThreadOf(thread)],
    );
  }

  final thread_api.ThreadList _list;
  late final StreamSubscription<List<thread_api.ThreadSummary>> _subscription;
  final _threads = Latest<List<RoomThread>>(const []);

  @override
  Stream<List<RoomThread>> get threads => _threads.stream;

  @override
  Future<bool> loadMore() => guarded(_list.paginate);

  @override
  void close() {
    // Not awaited: see RustMatrixSession.close.
    unawaited(_subscription.cancel());
    unawaited(_threads.close());
    _list.dispose();
  }
}

final class RustPinnedEvents implements PinnedEvents {
  RustPinnedEvents._(this._pins) {
    _subscription = _pins.subscribe().listen(
      (pins) =>
          _state.value = RoomPins(eventIds: pins.eventIds, canPin: pins.canPin),
    );
  }

  final pins_api.Pins _pins;
  late final StreamSubscription<pins_api.RoomPins> _subscription;
  final _state = Latest(const RoomPins());

  @override
  Stream<RoomPins> get pins => _state.stream;

  @override
  Future<bool> pin(String eventId) =>
      guarded(() => _pins.pin(eventId: eventId));

  @override
  Future<bool> unpin(String eventId) =>
      guarded(() => _pins.unpin(eventId: eventId));

  @override
  void close() {
    // Not awaited: see RustMatrixSession.close.
    unawaited(_subscription.cancel());
    unawaited(_state.close());
    _pins.dispose();
  }
}

final class RustRoomTimeline implements RoomTimeline {
  RustRoomTimeline._(this._timeline) {
    _subscription = _timeline.subscribeItems().listen((batch) {
      for (final diff in batch) {
        applyTimelineDiff(_items, diff);
      }
      _entries.value = entriesOf(_items);
    });
  }

  final rust.Timeline _timeline;
  late final StreamSubscription<List<rust.TimelineDiff>> _subscription;
  final _items = <rust.TimelineItem>[];
  final _entries = Latest<List<TimelineEntry>>(const []);

  @override
  Stream<List<TimelineEntry>> get entries => _entries.stream;

  @override
  Future<bool> loadOlder() => guarded(() => _timeline.paginateBack(count: 20));

  @override
  Future<bool> loadNewer() =>
      guarded(() => _timeline.paginateForward(count: 20));

  @override
  Future<void> send(String text, {bool markdown = false}) =>
      guarded(() => _timeline.sendText(body: text, markdown: markdown));

  @override
  Future<void> markAsRead() => guarded(_timeline.markAsRead);

  @override
  Future<void> setTyping(bool typing) =>
      guarded(() => _timeline.setTyping(typing: typing));

  @override
  Future<void> sendReply(
    String text,
    String eventId, {
    bool markdown = false,
  }) => guarded(
    () => _timeline.sendReply(body: text, replyTo: eventId, markdown: markdown),
  );

  @override
  Future<void> toggleReaction(String ref, String key) =>
      guarded(() => _timeline.toggleReaction(item: ref, key: key));

  @override
  Future<void> edit(
    String ref,
    String text, {
    bool caption = false,
    bool markdown = false,
  }) => guarded(
    () => _timeline.edit(
      item: ref,
      body: text,
      caption: caption,
      markdown: markdown,
    ),
  );

  @override
  Future<void> redact(String ref) => guarded(() => _timeline.redact(item: ref));

  @override
  Future<void> retrySend(String ref) =>
      guarded(() => _timeline.retrySend(item: ref));

  @override
  Future<bool> canRedactOthers() => _timeline.canRedactOthers();

  @override
  Future<void> sendFile(
    Uint8List data, {
    required String filename,
    required String mimeType,
    String? caption,
    bool compress = false,
    bool markdown = false,
  }) => guarded(
    () => _timeline.sendData(
      data: data,
      filename: filename,
      mimeType: mimeType,
      caption: caption,
      compress: compress,
      markdown: markdown,
    ),
  );

  @override
  Future<void> sendVoice(VoiceClip clip, {String? inReplyTo}) => guarded(
    () => _timeline.sendVoice(
      data: clip.data,
      durationMs: clip.duration.inMilliseconds,
      waveform: clip.waveform,
      inReplyTo: inReplyTo,
    ),
  );

  @override
  Future<void> sendVideo(
    Uint8List data, {
    required String filename,
    required String mimeType,
    required Duration duration,
    Uint8List? photo,
    int? width,
    int? height,
    String? inReplyTo,
  }) => guarded(
    () => _timeline.sendVideo(
      data: data,
      filename: filename,
      mimeType: mimeType,
      photo: photo,
      width: width,
      height: height,
      durationMs: duration.inMilliseconds,
      inReplyTo: inReplyTo,
    ),
  );

  @override
  Future<void> forward(String eventId, String roomId) =>
      guarded(() => _timeline.forward(item: eventId, toRoom: roomId));

  @override
  void close() {
    unawaited(_subscription.cancel());
    unawaited(_entries.close());
    _timeline.dispose();
  }
}

/// The app's policy on top of the SDK's verification states: the device that asked starts the
/// emoji once both sides are ready, and the other one accepts them.
final class RustDeviceVerification implements DeviceVerification {
  RustDeviceVerification._(this._verification, {required this._weAsked}) {
    _subscription = _verification.subscribeStates().listen(_onState);
  }

  final rust.Verification _verification;
  final bool _weAsked;
  late final StreamSubscription<rust.VerificationFlowState> _subscription;
  final _steps = Latest<VerificationStep>(const VerificationWaiting());

  void _onState(rust.VerificationFlowState state) {
    appLog(LogLevel.debug, 'verification', '$state');
    switch (state) {
      case rust.VerificationFlowState_Ready() when _weAsked:
        unawaited(_quietly(_verification.startSas));
      case rust.VerificationFlowState_SasStarted():
        unawaited(_quietly(_verification.acceptSas));
      default:
    }
    _steps.value = stepOf(state);
  }

  /// A failed step shows as a cancellation from the other side; nothing to report here.
  Future<void> _quietly(Future<void> Function() call) async {
    try {
      await call();
    } on Object {
      // The state stream reports what happened.
    }
  }

  @override
  Stream<VerificationStep> get steps => _steps.stream;

  @override
  Future<void> accept() => guarded(_verification.accept);

  @override
  Future<void> confirm() => guarded(_verification.confirm);

  @override
  Future<void> mismatch() => guarded(_verification.mismatch);

  @override
  Future<void> cancel() => guarded(_verification.cancel);

  @override
  void close() {
    // Not awaited: see RustMatrixSession.close.
    unawaited(_subscription.cancel());
    unawaited(_steps.close());
    _verification.dispose();
  }
}

/// Voice messages through the core: Opus in pure Rust, the same on every platform.
final class RustAudioCodec implements AudioCodec {
  const RustAudioCodec();

  @override
  Future<VoiceClip> encodeVoice(
    Int16List pcm, {
    required int sampleRate,
    required int channels,
  }) async {
    final clip = await guarded(
      () => voice.encodeVoice(
        pcm: pcm,
        sampleRate: sampleRate,
        channels: channels,
      ),
    );
    return VoiceClip(
      data: clip.data,
      duration: Duration(milliseconds: clip.durationMs),
      waveform: clip.waveform,
    );
  }

  @override
  Future<Uint8List?> playableWav(Uint8List data) =>
      voice.playableWav(data: data);
}
