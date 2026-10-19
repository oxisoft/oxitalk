import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../../rust/api/room_list.dart' as rust;
import '../../rust/api/session.dart' as rust;
import '../../rust/api/timeline.dart' as rust;
import '../../rust/api/verification.dart' as rust;
import '../../util/latest.dart';
import '../api/matrix.dart';
import '../api/secret_store.dart';
import 'diffs.dart';
import 'mapping.dart';
import 'sync_supervisor.dart';

/// The Matrix layer on the Rust core. The accounts' session data and store passphrases are
/// kept in [secrets], each account's store under `<dataDir>/accounts/<random id>/`.
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
      var duplicate = false;
      await _update((accounts) {
        duplicate = accounts.any((a) => a.data.userId == saved.data.userId);
        return duplicate ? accounts : [...accounts, saved];
      });
      if (duplicate) {
        // The login made a new device on the server; take it away again.
        await session.logout().catchError((Object _) {});
        session.dispose();
        throw MatrixFailure(FailureKind.alreadyLoggedIn, saved.data.userId);
      }
      return RustMatrixSession._(session, () => _forget(saved.storeDir));
    } catch (_) {
      await _deleteDir(storeDir.path);
      rethrow;
    }
  }

  @override
  Future<List<MatrixSession>> restoreAll() async {
    await _migrateLegacy();
    final sessions = <MatrixSession>[];
    for (final saved in await _read()) {
      try {
        final session = await rust.restore(
          data: saved.data,
          storeDir: saved.storeDir,
          storePassphrase: saved.passphrase,
        );
        sessions.add(
          RustMatrixSession._(session, () => _forget(saved.storeDir)),
        );
      } on Object {
        // Restoring works offline, so a failure means the store can't be used any more.
        await _forget(saved.storeDir);
      }
    }
    return sessions;
  }

  @override
  Future<String?> readActive() => _secrets.read(_activeKey);

  @override
  Future<void> writeActive(String userId) => _secrets.write(_activeKey, userId);

  Future<void> _forget(String storeDir) async {
    await _update(
      (accounts) => [
        for (final account in accounts)
          if (account.storeDir != storeDir) account,
      ],
    );
    await _deleteDir(storeDir);
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
        _session.subscribeVerificationStatus().listen(
          (status) => _verificationStatus.value = verificationStatusOf(status),
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
  final _verificationStatus = Latest(VerificationStatus.unknown);
  final _verificationRequests =
      StreamController<VerificationRequest>.broadcast();
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
    // Not awaited either: closing a broadcast stream waits for every listener to take the
    // done event, which a paused listener never does.
    unawaited(_rooms.close());
    unawaited(_verificationStatus.close());
    unawaited(_verificationRequests.close());
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
