import 'models.dart';

export 'models.dart';

enum FailureKind {
  invalidServer,
  network,
  forbidden,
  sessionExpired,
  wrongStorePassphrase,
  invalidId,
  roomNotFound,
  internal,
}

/// Every failure the Matrix layer reports. The UI matches on [kind]; [message] is for logs.
final class MatrixFailure implements Exception {
  const MatrixFailure(this.kind, [this.message = '']);

  final FailureKind kind;
  final String message;

  @override
  String toString() =>
      'MatrixFailure(${kind.name}${message.isEmpty ? '' : ': $message'})';
}

/// Logs in, or brings back the session saved by an earlier login.
abstract interface class MatrixClientFactory {
  /// [server] is a server name (`matrix.org`) or a homeserver URL. The session is saved, so
  /// [restoreSaved] brings it back on the next start.
  Future<MatrixSession> login({
    required String server,
    required String username,
    required String password,
  });

  /// The saved session, or `null` if there is none (or it can't be opened any more).
  Future<MatrixSession?> restoreSaved();
}

/// A logged-in account. It syncs from creation until [logout] or [close].
abstract interface class MatrixSession {
  String get userId;

  /// The current status, then every change.
  Stream<SyncStatus> get syncStatus;

  /// The current room list (`null` until the first one arrives), then every change.
  Stream<List<Room>?> get rooms;

  /// Completes when the server has rejected the session. The saved session is gone by then;
  /// the user has to log in again.
  Future<void> get expired;

  /// Creates an encrypted direct chat and invites [userId]. Returns the room ID.
  Future<String> createDm(String userId);

  Future<void> join(String roomId);

  Future<RoomTimeline> openTimeline(String roomId);

  /// Logs out on the server and deletes everything stored for this account.
  Future<void> logout();

  /// Stops syncing and frees the session, keeping it saved.
  Future<void> close();
}

abstract interface class RoomTimeline {
  /// The current entries, then every change.
  Stream<List<TimelineEntry>> get entries;

  /// Loads older messages. Returns `true` once the start of the room is reached.
  Future<bool> loadOlder();

  Future<void> send(String text);

  void close();
}
