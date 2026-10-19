import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart'
    show ProviderListenableSelect;
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../matrix/api/matrix.dart';
import '../matrix/api/secret_store.dart';
import '../matrix/rust/rust_matrix.dart';
import 'secure_secret_store.dart';

part 'providers.g.dart';

/// Tests override this (no keyring in CI).
@Riverpod(keepAlive: true)
SecretStore secretStore(Ref ref) => const SecureSecretStore();

/// Tests override this with fakes.
@Riverpod(keepAlive: true)
MatrixClientFactory clientFactory(Ref ref) => RustMatrixClientFactory(
  secrets: ref.watch(secretStoreProvider),
  dataDir: getApplicationSupportDirectory,
);

/// What the login form suggests.
@Riverpod(keepAlive: true)
String defaultServer(Ref ref) => 'matrix.org';

/// The logged-in accounts, in the order they were added, and which one is in front.
final class AccountsState {
  const AccountsState(this.sessions, this.activeId);

  final List<MatrixSession> sessions;

  /// The user ID of the account in front; `null` only when there are no accounts.
  final String? activeId;

  MatrixSession? get active =>
      sessions.where((session) => session.userId == activeId).firstOrNull;

  MatrixSession? byId(String userId) =>
      sessions.where((session) => session.userId == userId).firstOrNull;
}

/// The accounts. Starts by restoring the saved ones; all of them sync all the time.
@Riverpod(keepAlive: true)
class Accounts extends _$Accounts {
  @override
  Future<AccountsState> build() async {
    final factory = ref.watch(clientFactoryProvider);
    final sessions = await factory.restoreAll();
    sessions.forEach(_watchExpiry);
    final saved = await factory.readActive();
    final active = sessions.any((session) => session.userId == saved)
        ? saved
        : sessions.firstOrNull?.userId;
    return AccountsState(sessions, active);
  }

  AccountsState get _current => state.value ?? const AccountsState([], null);

  /// Logs in to one more account and brings it to the front. Throws [MatrixFailure]; the
  /// login form shows it.
  Future<void> login({
    required String server,
    required String username,
    required String password,
  }) async {
    final session = await ref
        .read(clientFactoryProvider)
        .login(server: server, username: username, password: password);
    _watchExpiry(session);
    // Right after login the status is unknown until the keys are fetched; waiting a moment
    // avoids showing the chats just before the verification screen.
    await session.verificationStatus
        .firstWhere((status) => status != VerificationStatus.unknown)
        .timeout(
          const Duration(seconds: 15),
          onTimeout: () => VerificationStatus.unknown,
        );
    state = AsyncData(
      AccountsState([..._current.sessions, session], session.userId),
    );
    _saveActive(session.userId);
  }

  /// Brings the account with [userId] to the front.
  void activate(String userId) {
    final current = _current;
    if (current.activeId == userId || current.byId(userId) == null) return;
    state = AsyncData(AccountsState(current.sessions, userId));
    _saveActive(userId);
  }

  /// Logs out of the account with [userId]; the next one comes to the front.
  Future<void> logout(String userId) async {
    final session = _current.byId(userId);
    if (session == null) return;
    _remove(session);
    await session.logout();
  }

  void _remove(MatrixSession session) {
    final current = _current;
    final index = current.sessions.indexOf(session);
    if (index < 0) return;
    final sessions = [...current.sessions]..removeAt(index);
    final active = current.activeId != session.userId
        ? current.activeId
        : sessions.isEmpty
        ? null
        : sessions[index.clamp(0, sessions.length - 1)].userId;
    state = AsyncData(AccountsState(sessions, active));
    if (active != null) _saveActive(active);
  }

  void _saveActive(String userId) =>
      unawaited(ref.read(clientFactoryProvider).writeActive(userId));

  void _watchExpiry(MatrixSession session) =>
      unawaited(session.expired.then((_) => _remove(session)));
}

/// The user ID of the account in front, or `null` when there are none.
@Riverpod(keepAlive: true)
String? activeAccount(Ref ref) =>
    ref.watch(accountsProvider.select((accounts) => accounts.value?.activeId));

MatrixSession? _session(Ref ref, String account) => ref.watch(
  accountsProvider.select((accounts) => accounts.value?.byId(account)),
);

@riverpod
Stream<SyncStatus> syncStatus(Ref ref, String account) =>
    _session(ref, account)?.syncStatus ?? Stream.value(SyncStatus.connecting);

/// The account's verification status; [VerificationStatus.unknown] once it is gone.
@riverpod
Stream<VerificationStatus> verificationStatus(Ref ref, String account) =>
    _session(ref, account)?.verificationStatus ??
    Stream.value(VerificationStatus.unknown);

@riverpod
Stream<VerificationRequest> verificationRequests(Ref ref, String account) =>
    _session(ref, account)?.verificationRequests ?? const Stream.empty();

/// `null` until the first room list has arrived.
@riverpod
Stream<List<Room>?> rooms(Ref ref, String account) =>
    _session(ref, account)?.rooms ?? Stream.value(null);

/// What the account switcher shows: unread messages plus invites.
@riverpod
int unreadCount(Ref ref, String account) => [
  for (final room in ref.watch(roomsProvider(account)).value ?? const <Room>[])
    room.membership == Membership.invited ? 1 : room.unreadCount,
].fold(0, (sum, count) => sum + count);

@riverpod
Future<RoomTimeline> roomTimeline(
  Ref ref,
  String account,
  String roomId,
) async {
  final session = _session(ref, account);
  if (session == null) throw const MatrixFailure(FailureKind.sessionExpired);
  RoomTimeline? timeline;
  var disposed = false;
  ref.onDispose(() {
    disposed = true;
    timeline?.close();
  });
  timeline = await session.openTimeline(roomId);
  if (disposed) timeline.close();
  return timeline;
}

/// Follows the timeline's state rather than awaiting its `future`: a logout disposes both
/// while the timeline may still be opening, and an awaited `future` then fails unhandled.
@riverpod
Stream<List<TimelineEntry>> timelineEntries(
  Ref ref,
  String account,
  String roomId,
) => switch (ref.watch(roomTimelineProvider(account, roomId))) {
  AsyncData(:final value) => value.entries,
  AsyncError(:final error, :final stackTrace) => Stream.error(
    error,
    stackTrace,
  ),
  _ => const Stream.empty(),
};
