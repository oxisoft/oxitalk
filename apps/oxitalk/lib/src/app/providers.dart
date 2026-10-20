import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart'
    show ProviderListenableSelect;
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../matrix/api/matrix.dart';
import '../matrix/api/secret_store.dart';
import '../matrix/rust/rust_matrix.dart';
import '../util/log.dart';
import 'account_pictures.dart';
import 'collapsed_sections.dart';
import 'diagnostics.dart';
import 'file_actions.dart';
import 'media_prefs.dart';
import 'pick_image.dart';
import 'ui_prefs.dart';
import 'window_controls.dart';
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

/// Set by `main` (and by tests): it is started before the app.
@Riverpod(keepAlive: true)
Diagnostics diagnostics(Ref ref) =>
    throw UnimplementedError('diagnosticsProvider is overridden in main');

/// Set by `main` (and by tests), next to the app's other data.
@Riverpod(keepAlive: true)
AccountPictures accountPictures(Ref ref) =>
    throw UnimplementedError('accountPicturesProvider is overridden in main');

/// Set by `main` (and by tests), next to the app's other data.
@Riverpod(keepAlive: true)
CollapsedSections collapsedSectionsStore(Ref ref) => throw UnimplementedError(
  'collapsedSectionsStoreProvider is overridden in main',
);

/// Tests override this; there is no file dialog in a test.
@Riverpod(keepAlive: true)
PickImage pickImage(Ref ref) => pickImageFile;

/// Set by `main` (and by tests), next to the app's other data.
@Riverpod(keepAlive: true)
UiPrefs uiPrefs(Ref ref) =>
    throw UnimplementedError('uiPrefsProvider is overridden in main');

/// Whether the chat list is narrowed to pictures and short names.
@Riverpod(keepAlive: true)
class NarrowList extends _$NarrowList {
  @override
  bool build() => ref.watch(uiPrefsProvider).narrowList;

  void toggle() {
    state = !state;
    unawaited(ref.read(uiPrefsProvider).setNarrowList(narrow: state));
  }
}

/// Whether the account rail is hidden.
@Riverpod(keepAlive: true)
class RailHidden extends _$RailHidden {
  @override
  bool build() => ref.watch(uiPrefsProvider).railHidden;

  void toggle() {
    state = !state;
    unawaited(ref.read(uiPrefsProvider).setRailHidden(hidden: state));
  }
}

/// Whether messages are sent formatted from their markdown, as Element sends them.
@Riverpod(keepAlive: true)
class UseMarkdown extends _$UseMarkdown {
  @override
  bool build() => ref.watch(uiPrefsProvider).useMarkdown;

  void set({required bool on}) {
    state = on;
    unawaited(ref.read(uiPrefsProvider).setUseMarkdown(on: on));
  }
}

/// `main` sets the real window; tests and phones have none of the app's own.
@Riverpod(keepAlive: true)
WindowControls windowControls(Ref ref) => const PlatformWindowControls();

/// Set by `main` (and by tests), next to the app's other data.
@Riverpod(keepAlive: true)
MediaPrefs mediaPrefs(Ref ref) =>
    throw UnimplementedError('mediaPrefsProvider is overridden in main');

/// Tests override this: no file dialogs or other apps in a test.
@Riverpod(keepAlive: true)
FileActions fileActions(Ref ref) => const SystemFileActions();

/// How long cached media is kept, in days (`null`: forever); applied to every account.
@Riverpod(keepAlive: true)
class MediaRetention extends _$MediaRetention {
  @override
  int? build() => ref.watch(mediaPrefsProvider).retentionDays;

  Future<void> set(int? days) async {
    state = days;
    await ref.read(mediaPrefsProvider).setRetentionDays(days);
    for (final session
        in ref.read(accountsProvider).value?.sessions ??
            const <MatrixSession>[]) {
      _applyRetention(session, days);
    }
  }
}

/// A failure only leaves the cache's previous setting; the next start tries again.
void _applyRetention(MatrixSession session, int? days) => unawaited(
  session.setMediaRetention(days).catchError((Object error) {
    appLog(LogLevel.warn, 'media', 'retention not set: $error');
  }),
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
    final days = ref.read(mediaPrefsProvider).retentionDays;
    for (final session in sessions) {
      _applyRetention(session, days);
    }
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
    _applyRetention(session, ref.read(mediaRetentionProvider));
    // Right after login the status is unknown until the keys are fetched; waiting a moment
    // avoids showing the chats just before the verification screen.
    await session.verificationStatus
        .firstWhere((status) => status != VerificationStatus.unknown)
        .timeout(
          const Duration(seconds: 15),
          onTimeout: () => VerificationStatus.unknown,
        );
    appLog(LogLevel.info, 'accounts', 'logged in ${session.userId}');
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
    appLog(LogLevel.info, 'accounts', 'logging out $userId');
    _remove(session);
    await session.logout();
    await ref.read(accountPicturesProvider).clearLocal(userId);
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

  void _watchExpiry(MatrixSession session) => unawaited(
    session.expired.then((_) {
      appLog(LogLevel.warn, 'accounts', 'session rejected: ${session.userId}');
      _remove(session);
    }),
  );
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

@riverpod
Stream<Profile> profile(Ref ref, String account) =>
    _session(ref, account)?.profile ?? Stream.value(const Profile());

/// The picture at [mxcUrl] (`mxc://`), as a thumbnail about [size] pixels wide. Kept once
/// loaded; a failed load is tried again the next time it is shown.
@riverpod
Future<Uint8List> picture(
  Ref ref,
  String account,
  String mxcUrl,
  int size,
) async {
  final session = _session(ref, account);
  if (session == null) throw const MatrixFailure(FailureKind.sessionExpired);
  final bytes = await session.thumbnail(mxcUrl, size);
  ref.keepAlive();
  return bytes;
}

/// The picture the user picked for [account] on this device, if any.
@riverpod
Future<Uint8List?> localPicture(Ref ref, String account) =>
    ref.watch(accountPicturesProvider).local(account);

/// The website icon of [server], if it has one.
@Riverpod(keepAlive: true)
Future<Uint8List?> serverIcon(Ref ref, String server) =>
    ref.watch(accountPicturesProvider).serverIcon(server);

@riverpod
Stream<Sections> sections(Ref ref, String account) =>
    _session(ref, account)?.sections ?? Stream.value(const Sections());

/// The sections of [account]'s room list that the user folded.
@Riverpod(keepAlive: true)
class CollapsedSectionTags extends _$CollapsedSectionTags {
  @override
  Future<Set<String>> build(String account) =>
      ref.watch(collapsedSectionsStoreProvider).read(account);

  void toggle(String tag) {
    final tags = {...?state.value};
    if (!tags.remove(tag)) tags.add(tag);
    state = AsyncData(tags);
    unawaited(ref.read(collapsedSectionsStoreProvider).write(account, tags));
  }
}

/// A picture of a message's file for showing it in the chat. Kept once loaded.
@riverpod
Future<Uint8List> mediaThumbnail(
  Ref ref,
  String account,
  String source,
  String? thumbnail,
) async {
  final session = _session(ref, account);
  if (session == null) throw const MatrixFailure(FailureKind.sessionExpired);
  final bytes = await session.mediaThumbnail(source, thumbnail, 640);
  ref.keepAlive();
  return bytes;
}

/// A message's whole file, while something shows it.
@riverpod
Future<Uint8List> mediaContent(Ref ref, String account, String source) {
  final session = _session(ref, account);
  if (session == null) throw const MatrixFailure(FailureKind.sessionExpired);
  return session.mediaContent(source);
}

@riverpod
Future<RoomDetails> roomDetails(Ref ref, String account, String roomId) {
  final session = _session(ref, account);
  if (session == null) throw const MatrixFailure(FailureKind.sessionExpired);
  return session.roomDetails(roomId);
}

@riverpod
Future<List<RoomMember>> roomMembers(Ref ref, String account, String roomId) {
  final session = _session(ref, account);
  if (session == null) throw const MatrixFailure(FailureKind.sessionExpired);
  return session.roomMembers(roomId);
}

/// The room's files and links, for its info screen; closed when no longer shown.
@riverpod
Future<RoomTimeline> mediaTimeline(
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
  timeline = await session.openMediaTimeline(roomId);
  if (disposed) timeline.close();
  return timeline;
}

/// As [timelineEntries], for [mediaTimeline].
@riverpod
Stream<List<TimelineEntry>> mediaTimelineEntries(
  Ref ref,
  String account,
  String roomId,
) => switch (ref.watch(mediaTimelineProvider(account, roomId))) {
  AsyncData(:final value) => value.entries,
  AsyncError(:final error, :final stackTrace) => Stream.error(
    error,
    stackTrace,
  ),
  _ => const Stream.empty(),
};

/// The emojis the user used lately, the last first.
@riverpod
Future<List<String>> recentEmojis(Ref ref, String account) async =>
    await _session(ref, account)?.recentEmojis() ?? const [];

/// Whether the user may delete other people's messages in the room.
@riverpod
Future<bool> canRedactOthers(Ref ref, String account, String roomId) async =>
    switch (ref.watch(roomTimelineProvider(account, roomId))) {
      AsyncData(:final value) => value.canRedactOthers(),
      _ => false,
    };

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
