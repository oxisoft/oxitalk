import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../../rust/api/room_list.dart' as rust;
import '../../rust/api/session.dart' as rust;
import '../../rust/api/timeline.dart' as rust;
import '../../util/latest.dart';
import '../api/matrix.dart';
import '../api/secret_store.dart';
import 'diffs.dart';
import 'mapping.dart';
import 'sync_supervisor.dart';

/// The Matrix layer on the Rust core. One account: its session data and store passphrase are
/// kept in [secrets], its store under `<dataDir>/accounts/<random id>/`.
final class RustMatrixClientFactory implements MatrixClientFactory {
  RustMatrixClientFactory({required this._secrets, required this._dataDir});

  static const _savedSessionKey = 'oxitalk.session';

  final SecretStore _secrets;
  final Future<Directory> Function() _dataDir;

  @override
  Future<MatrixSession> login({
    required String server,
    required String username,
    required String password,
  }) async {
    final storeDir = Directory(
      '${(await _dataDir()).path}/accounts/${_randomId()}',
    );
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
      final saved = _SavedSession(
        session.sessionData(),
        storeDir.path,
        passphrase,
      );
      await _secrets.write(_savedSessionKey, jsonEncode(saved.toJson()));
      return RustMatrixSession._(session, () => _forget(saved.storeDir));
    } catch (_) {
      await _deleteDir(storeDir.path);
      rethrow;
    }
  }

  @override
  Future<MatrixSession?> restoreSaved() async {
    final json = await _secrets.read(_savedSessionKey);
    if (json == null) return null;
    final _SavedSession saved;
    try {
      saved = _SavedSession.fromJson(jsonDecode(json) as Map<String, Object?>);
    } on Object {
      await _secrets.delete(_savedSessionKey);
      return null;
    }
    try {
      final session = await rust.restore(
        data: saved.data,
        storeDir: saved.storeDir,
        storePassphrase: saved.passphrase,
      );
      return RustMatrixSession._(session, () => _forget(saved.storeDir));
    } on Object {
      // Restoring works offline, so a failure means the store can't be used any more.
      await _forget(saved.storeDir);
      return null;
    }
  }

  Future<void> _forget(String storeDir) async {
    await _secrets.delete(_savedSessionKey);
    await _deleteDir(storeDir);
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
  _SavedSession(this.data, this.storeDir, this.passphrase);

  factory _SavedSession.fromJson(Map<String, Object?> json) => _SavedSession(
    rust.SessionData(
      homeserverUrl: json['homeserverUrl']! as String,
      userId: json['userId']! as String,
      deviceId: json['deviceId']! as String,
      accessToken: json['accessToken']! as String,
    ),
    json['storeDir']! as String,
    json['passphrase']! as String,
  );

  final rust.SessionData data;
  final String storeDir;
  final String passphrase;

  Map<String, Object?> toJson() => {
    'homeserverUrl': data.homeserverUrl,
    'userId': data.userId,
    'deviceId': data.deviceId,
    'accessToken': data.accessToken,
    'storeDir': storeDir,
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
        _session.subscribeSessionChanges().listen((change) {
          if (change is rust.SessionChange_UnknownToken) {
            unawaited(_onTokenRejected());
          }
        }),
      );
    unawaited(_session.startSync());
  }

  final rust.Session _session;
  final Future<void> Function() _forget;
  late final SyncSupervisor _supervisor;
  final _subscriptions = <StreamSubscription<Object?>>[];
  final _summaries = <rust.RoomSummary>[];
  final _rooms = Latest<List<Room>?>(null);
  final _expired = Completer<void>();
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
  Future<String> createDm(String userId) =>
      guarded(() => _session.createDm(userId: userId));

  @override
  Future<void> join(String roomId) =>
      guarded(() => _session.join(roomId: roomId));

  @override
  Future<RoomTimeline> openTimeline(String roomId) async => RustRoomTimeline._(
    await guarded(() => _session.timeline(roomId: roomId)),
  );

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
    await _rooms.close();
    _session.dispose();
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
  Future<void> send(String text) =>
      guarded(() => _timeline.sendText(body: text));

  @override
  void close() {
    unawaited(_subscription.cancel());
    unawaited(_entries.close());
    _timeline.dispose();
  }
}
