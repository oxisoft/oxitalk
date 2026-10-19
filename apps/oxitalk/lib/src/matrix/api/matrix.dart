import 'dart:typed_data';

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
  wrongRecoveryKey,

  /// Logging in to an account that is already in the app.
  alreadyLoggedIn,
  recoveryNotSetUp,
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

/// The user's accounts: logs in to more of them, and brings back the saved ones.
abstract interface class MatrixClientFactory {
  /// Logs in and saves the session as one more account. [server] is a server name
  /// (`matrix.org`) or a homeserver URL. Throws [MatrixFailure] with
  /// [FailureKind.alreadyLoggedIn] if the user is already one of the accounts.
  Future<MatrixSession> login({
    required String server,
    required String username,
    required String password,
  });

  /// Every saved account, in the order they were added. One that can't be opened any more is
  /// dropped.
  Future<List<MatrixSession>> restoreAll();

  /// The user ID of the account that was in front last time, if any.
  Future<String?> readActive();

  Future<void> writeActive(String userId);
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

  /// The current verification status of this device, then every change.
  Stream<VerificationStatus> get verificationStatus;

  /// Requests from the user's other devices to verify (or be verified by) this one.
  Stream<VerificationRequest> get verificationRequests;

  /// Verifies this device with the recovery key or security phrase. Throws [MatrixFailure]
  /// with [FailureKind.wrongRecoveryKey] or [FailureKind.recoveryNotSetUp].
  Future<void> recover(String key);

  /// Asks the user's other devices to verify this one.
  Future<DeviceVerification> requestVerification();

  /// Opens a request from [verificationRequests].
  Future<DeviceVerification> openVerification(String flowId);

  /// The user's profile (empty until it is fetched), then every change made here.
  Stream<Profile> get profile;

  /// Makes [data], an image of type [mimeType] (`image/png`), the user's avatar.
  Future<void> setAvatar(Uint8List data, String mimeType);

  Future<void> removeAvatar();

  /// A square thumbnail of the picture at [mxcUrl], about [size] pixels wide, as encoded
  /// image bytes.
  Future<Uint8List> thumbnail(String mxcUrl, int size);

  /// The room list sections (empty until they are read), then every change.
  Stream<Sections> get sections;

  /// Puts the room in the section with [tag] ([SectionTags.favourites],
  /// [SectionTags.lowPriority] or a custom one), or with `null` in its default one. A room is
  /// in one section at a time.
  Future<void> setRoomSection(String roomId, String? tag);

  /// Saves the user's sections and the order of the movable ones.
  Future<void> saveSections(List<CustomSection> custom, List<String> order);

  /// Creates an encrypted direct chat and invites [userId]. Returns the room ID.
  Future<String> createDm(String userId);

  Future<void> join(String roomId);

  Future<RoomTimeline> openTimeline(String roomId);

  /// Logs out on the server and deletes everything stored for this account; the other
  /// accounts stay.
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

/// One verification with another device of the user, by comparing emoji.
abstract interface class DeviceVerification {
  /// The current step, then every change, until done or cancelled.
  Stream<VerificationStep> get steps;

  /// Accepts a request from the other device.
  Future<void> accept();

  /// The emoji match.
  Future<void> confirm();

  /// The emoji don't match; cancels.
  Future<void> mismatch();

  Future<void> cancel();

  /// Stops following the verification; it isn't cancelled.
  void close();
}
