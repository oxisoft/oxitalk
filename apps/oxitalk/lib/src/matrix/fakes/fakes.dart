import 'dart:async';

import '../../util/latest.dart';
import '../api/matrix.dart';
import '../api/secret_store.dart';

/// In-memory stand-ins for the Matrix layer, for widget tests (and the integration test's
/// secret store, since CI has no keyring).
final class MemorySecretStore implements SecretStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

final class FakeMatrixClientFactory implements MatrixClientFactory {
  FakeMatrixClientFactory({
    this.saved,
    this.password = 'secret',
    this.rooms = const [],
    this.loginVerification = VerificationStatus.verified,
  });

  /// What [restoreSaved] returns.
  FakeSession? saved;

  /// The only password [login] accepts.
  final String password;

  /// The rooms a session made by [login] starts with.
  final List<Room> rooms;

  /// The verification status of a session made by [login].
  final VerificationStatus loginVerification;

  FakeSession? lastLogin;

  @override
  Future<MatrixSession> login({
    required String server,
    required String username,
    required String password,
  }) async {
    if (password != this.password) {
      throw const MatrixFailure(FailureKind.forbidden, 'Invalid password');
    }
    return lastLogin = FakeSession(userId: '@$username:$server', rooms: rooms)
      ..verification.value = loginVerification;
  }

  @override
  Future<MatrixSession?> restoreSaved() async => saved;
}

final class FakeSession implements MatrixSession {
  FakeSession({this.userId = '@me:example.org', List<Room>? rooms})
    : _rooms = Latest(rooms);

  @override
  final String userId;
  final Latest<List<Room>?> _rooms;
  final status = Latest(SyncStatus.online);
  final timelines = <String, FakeTimeline>{};
  final _expired = Completer<void>();
  var loggedOut = false;

  /// This device's verification status; tests change it.
  final verification = Latest(VerificationStatus.verified);

  /// What [recover] accepts; any other key is wrong.
  String? recoveryKey = 'the recovery key';
  final _requests = StreamController<VerificationRequest>.broadcast();

  /// The verification [requestVerification] or [openVerification] returned last.
  FakeVerification? lastVerification;

  /// Sends a request from another device, as it would arrive.
  void receiveVerificationRequest(VerificationRequest request) =>
      _requests.add(request);

  set roomList(List<Room>? rooms) => _rooms.value = rooms;

  List<Room> get roomList => _rooms.value ?? const [];

  /// Rejects the session, as the server would.
  void expire() => _expired.complete();

  @override
  Stream<SyncStatus> get syncStatus => status.stream;

  @override
  Stream<List<Room>?> get rooms => _rooms.stream;

  @override
  Future<void> get expired => _expired.future;

  @override
  Stream<VerificationStatus> get verificationStatus => verification.stream;

  @override
  Stream<VerificationRequest> get verificationRequests => _requests.stream;

  @override
  Future<void> recover(String key) async {
    if (recoveryKey == null) {
      throw const MatrixFailure(FailureKind.recoveryNotSetUp);
    }
    if (key != recoveryKey) {
      throw const MatrixFailure(FailureKind.wrongRecoveryKey);
    }
    verification.value = VerificationStatus.verified;
  }

  @override
  Future<DeviceVerification> requestVerification() async =>
      lastVerification = FakeVerification(this);

  @override
  Future<DeviceVerification> openVerification(String flowId) async =>
      lastVerification = FakeVerification(
        this,
        step: const VerificationIncoming(),
      );

  @override
  Future<String> createDm(String userId) async {
    if (!userId.startsWith('@') || !userId.contains(':')) {
      throw MatrixFailure(FailureKind.invalidId, userId);
    }
    final id = '!dm${roomList.length}:example.org';
    roomList = [
      Room(id: id, name: userId, isDm: true, isEncrypted: true),
      ...roomList,
    ];
    return id;
  }

  @override
  Future<void> join(String roomId) async {
    roomList = [
      for (final room in roomList)
        room.id == roomId ? room.copyWith(membership: Membership.joined) : room,
    ];
  }

  @override
  Future<RoomTimeline> openTimeline(String roomId) async =>
      timelines.putIfAbsent(roomId, () => FakeTimeline(ownUserId: userId));

  @override
  Future<void> logout() async => loggedOut = true;

  @override
  Future<void> close() async {}
}

final class FakeTimeline implements RoomTimeline {
  FakeTimeline({
    this.ownUserId = '@me:example.org',
    List<TimelineEntry> entries = const [],
  }) : _entries = Latest(entries);

  final String ownUserId;
  final Latest<List<TimelineEntry>> _entries;
  var olderLoads = 0;
  var closed = false;

  set entryList(List<TimelineEntry> entries) => _entries.value = entries;

  List<TimelineEntry> get entryList => _entries.value;

  @override
  Stream<List<TimelineEntry>> get entries => _entries.stream;

  @override
  Future<bool> loadOlder() async {
    olderLoads++;
    return true;
  }

  @override
  Future<void> send(String text) async {
    entryList = [
      ...entryList,
      MessageEntry(
        id: 'local${entryList.length}',
        sender: ownUserId,
        time: DateTime.now(),
        body: text,
        isOwn: true,
      ),
    ];
  }

  @override
  void close() => closed = true;
}

/// A verification the test drives: it moves the [step] as the other device would.
final class FakeVerification implements DeviceVerification {
  FakeVerification(
    this._session, {
    VerificationStep step = const VerificationWaiting(),
  }) : _steps = Latest(step);

  static const emojis = [
    VerificationEmoji('🐶', 'Dog'),
    VerificationEmoji('🔑', 'Key'),
    VerificationEmoji('🎸', 'Guitar'),
    VerificationEmoji('🚀', 'Rocket'),
    VerificationEmoji('🌵', 'Cactus'),
    VerificationEmoji('🍕', 'Pizza'),
    VerificationEmoji('⚓', 'Anchor'),
  ];

  final FakeSession _session;
  final Latest<VerificationStep> _steps;
  var accepted = false;
  var closed = false;

  set step(VerificationStep step) => _steps.value = step;

  VerificationStep get step => _steps.value;

  /// The other device accepted and both sides exchanged keys.
  void showEmoji() => step = const VerificationCompare(emojis, [1, 2, 3]);

  @override
  Stream<VerificationStep> get steps => _steps.stream;

  @override
  Future<void> accept() async {
    accepted = true;
    step = const VerificationWaiting();
  }

  /// The other device has confirmed already, so confirming finishes it.
  @override
  Future<void> confirm() async {
    step = const VerificationDone();
    _session.verification.value = VerificationStatus.verified;
  }

  @override
  Future<void> mismatch() async =>
      step = const VerificationCancelled('The emoji did not match', byUs: true);

  @override
  Future<void> cancel() async =>
      step = const VerificationCancelled('Cancelled', byUs: true);

  @override
  void close() => closed = true;
}
