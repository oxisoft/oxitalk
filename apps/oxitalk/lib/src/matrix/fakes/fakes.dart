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
  });

  /// What [restoreSaved] returns.
  FakeSession? saved;

  /// The only password [login] accepts.
  final String password;

  /// The rooms a session made by [login] starts with.
  final List<Room> rooms;

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
    return lastLogin = FakeSession(userId: '@$username:$server', rooms: rooms);
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
