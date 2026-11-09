import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart'
    show ProviderListenableSelect;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../app/providers.dart';
import '../../matrix/api/matrix.dart';
import '../chats/badges.dart';

part 'space_state.g.dart';

/// [account]'s top-level joined spaces, in Element's order; `null` until first read.
@riverpod
Stream<List<Space>?> spaces(Ref ref, String account) =>
    ref
        .watch(
          accountsProvider.select((accounts) => accounts.value?.byId(account)),
        )
        ?.spaces ??
    Stream.value(null);

/// The space [account]'s chat list shows (its ID), or `null` for all chats. Kept per
/// account on this device. A space the user leaves, or is removed from, falls back to all
/// chats.
@Riverpod(keepAlive: true)
class SelectedSpace extends _$SelectedSpace {
  /// A chat opened before the spaces were read, to check once they are.
  String? _pendingReveal;

  @override
  String? build(String account) {
    ref.listen(spacesProvider(account), (previous, next) {
      final now = next.value;
      if (now == null) return;
      final id = state;
      // Gone: it was there, or this is the first list read (left while the app was
      // closed). A space just accepted isn't there yet and is kept until it comes.
      if (id != null && !now.any((space) => space.id == id)) {
        final before = previous?.value;
        if (before == null || before.any((space) => space.id == id)) {
          select(null);
        }
      }
      if (_pendingReveal case final roomId?) {
        _pendingReveal = null;
        reveal(roomId);
      }
    });
    final prefs = ref.watch(uiPrefsProvider);
    final saved = prefs.selectedSpace(account);
    // Read before: left while the app was closed.
    final loaded = ref.read(spacesProvider(account)).value;
    if (saved != null &&
        loaded != null &&
        !loaded.any((space) => space.id == saved)) {
      unawaited(prefs.setSelectedSpace(account, null));
      return null;
    }
    return saved;
  }

  void select(String? spaceId) {
    if (state == spaceId) return;
    state = spaceId;
    unawaited(ref.read(uiPrefsProvider).setSelectedSpace(account, spaceId));
  }

  /// Makes sure the chat [roomId], just opened, shows in the list: all chats if it isn't
  /// in the selected space.
  void reveal(String roomId) {
    final id = state;
    if (id == null) return;
    final spaces = ref.read(spacesProvider(account)).value;
    if (spaces == null) {
      _pendingReveal = roomId;
      return;
    }
    final space = spaces.where((space) => space.id == id).firstOrNull;
    // Not there (yet): the list shows all chats anyway.
    if (space == null) return;
    if (!space.roomIds.contains(roomId)) select(null);
  }

  /// The previous ([step] -1) or next (1) of all chats and the spaces, round.
  void cycle(int step) {
    final spaces = ref.read(spacesProvider(account)).value ?? const <Space>[];
    if (spaces.isEmpty) return;
    final order = <String?>[null, for (final space in spaces) space.id];
    final current = order.indexOf(state);
    select(order[((current < 0 ? 0 : current) + step) % order.length]);
  }
}

/// The space [account]'s list shows, once it is among the account's spaces; `null` for all
/// chats.
@riverpod
Space? currentSpace(Ref ref, String account) {
  final id = ref.watch(selectedSpaceProvider(account));
  if (id == null) return null;
  return ref
      .watch(spacesProvider(account))
      .value
      ?.where((space) => space.id == id)
      .firstOrNull;
}

/// The chats [account]'s list shows: those of the current space, or all of them; `null`
/// until the room list is read.
@riverpod
List<Room>? visibleRooms(Ref ref, String account) {
  final rooms = ref.watch(roomsProvider(account)).value;
  final space = ref.watch(currentSpaceProvider(account));
  if (rooms == null || space == null) return rooms;
  return inSpace(rooms, space);
}

List<Room> inSpace(List<Room> rooms, Space space) => [
  for (final room in rooms)
    if (space.roomIds.contains(room.id)) room,
];

/// The badge of a space: as a room's, from its chats together. A mention anywhere in it
/// makes it a mention; muted chats add nothing.
RoomBadge spaceBadgeOf(List<Room> rooms, Space space) {
  var count = 0;
  var mention = false;
  for (final room in rooms) {
    if (!space.roomIds.contains(room.id) || room.isMuted) continue;
    count += room.notifyingCount;
    if (room.unreadMentions > 0) mention = true;
  }
  if (mention) return RoomBadge(BadgeKind.mention, count);
  if (count > 0) return RoomBadge(BadgeKind.notifying, count);
  return const RoomBadge(BadgeKind.none);
}

/// What a space's badge shows: its chats' notifying unread messages.
@riverpod
RoomBadge spaceBadge(Ref ref, String account, String spaceId) {
  final rooms = ref.watch(roomsProvider(account)).value ?? const <Room>[];
  final space = ref
      .watch(spacesProvider(account))
      .value
      ?.where((space) => space.id == spaceId)
      .firstOrNull;
  if (space == null) return const RoomBadge(BadgeKind.none);
  return spaceBadgeOf(rooms, space);
}

/// Whether chats outside the current space have notifying unread messages (or invites):
/// the space selector shows a red dot then.
@riverpod
bool unreadOutsideSpace(Ref ref, String account) {
  final space = ref.watch(currentSpaceProvider(account));
  if (space == null) return false;
  final rooms = ref.watch(roomsProvider(account)).value ?? const <Room>[];
  return rooms.any(
    (room) => !space.roomIds.contains(room.id) && room.notifyingCount > 0,
  );
}
