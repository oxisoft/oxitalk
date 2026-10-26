import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../matrix/api/matrix.dart';

MatrixSession? _session(Ref ref, String account) => ref.watch(
  accountsProvider.select((accounts) => accounts.value?.byId(account)),
);

/// Account, user, and the room they were seen in (for their name there), if any.
typedef ProfileKey = (String, String, String?);

/// Someone's profile as [MatrixSession.userProfile] tells it.
final userProfileProvider = FutureProvider.autoDispose
    .family<UserProfile, ProfileKey>((ref, key) {
      final (account, userId, roomId) = key;
      final session = _session(ref, account);
      if (session == null) {
        throw const MatrixFailure(FailureKind.sessionExpired);
      }
      return session.userProfile(userId, roomId: roomId);
    });

/// The users the account ignores, as the list changes.
final ignoredUsersProvider = StreamProvider.autoDispose
    .family<List<String>, String>(
      (ref, account) =>
          _session(ref, account)?.ignoredUsers ?? Stream.value(const []),
    );

/// Account and room.
typedef RoomKey = (String, String);

/// Whether the user may mention the whole room with `@room`.
final canMentionRoomProvider = FutureProvider.autoDispose.family<bool, RoomKey>(
  (ref, key) async {
    final (account, roomId) = key;
    return await _session(ref, account)?.canMentionRoom(roomId) ?? false;
  },
);
