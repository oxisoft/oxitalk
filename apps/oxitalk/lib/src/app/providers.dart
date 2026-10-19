import 'dart:async';

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

/// The logged-in session, or `null` when logged out. Starts by restoring a saved session.
@Riverpod(keepAlive: true)
class Auth extends _$Auth {
  @override
  Future<MatrixSession?> build() async {
    final session = await ref.watch(clientFactoryProvider).restoreSaved();
    _watchExpiry(session);
    return session;
  }

  /// Throws [MatrixFailure]; the login form shows it.
  Future<void> login({
    required String server,
    required String username,
    required String password,
  }) async {
    final session = await ref
        .read(clientFactoryProvider)
        .login(server: server, username: username, password: password);
    _watchExpiry(session);
    state = AsyncData(session);
  }

  Future<void> logout() async {
    final session = state.value;
    state = const AsyncData(null);
    await session?.logout();
  }

  void _watchExpiry(MatrixSession? session) {
    unawaited(
      session?.expired.then((_) {
        if (state.value == session) state = const AsyncData(null);
      }),
    );
  }
}

MatrixSession? _session(Ref ref) => ref.watch(authProvider).value;

@riverpod
Stream<SyncStatus> syncStatus(Ref ref) =>
    _session(ref)?.syncStatus ?? Stream.value(SyncStatus.connecting);

/// `null` until the first room list has arrived.
@riverpod
Stream<List<Room>?> rooms(Ref ref) =>
    _session(ref)?.rooms ?? Stream.value(null);

@riverpod
Future<RoomTimeline> roomTimeline(Ref ref, String roomId) async {
  final session = _session(ref);
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
Stream<List<TimelineEntry>> timelineEntries(Ref ref, String roomId) =>
    switch (ref.watch(roomTimelineProvider(roomId))) {
      AsyncData(:final value) => value.entries,
      AsyncError(:final error, :final stackTrace) => Stream.error(
        error,
        stackTrace,
      ),
      _ => const Stream.empty(),
    };
