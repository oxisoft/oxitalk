import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
import '../../app/window_controls.dart';
import '../../matrix/api/matrix.dart';
import '../../ui/avatar.dart';
import '../../ui/format.dart';
import '../accounts/account_switcher.dart';
import '../chat/chat_pane.dart';
import '../chat_info/chat_info.dart';
import 'room_groups.dart';
import 'section_actions.dart';

/// The active account's chats: on a wide window the account rail, the list and the open chat
/// side by side, otherwise the list with the account switcher in its header.
class ChatsScreen extends ConsumerWidget {
  const ChatsScreen({this.roomId, this.showInfo = false, super.key});

  /// The open chat, if any.
  final String? roomId;

  /// The open chat's info, beside it.
  final bool showInfo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(activeAccountProvider);
    if (account == null) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < wideLayoutBreakpoint) {
          return ChatListPane(
            account: account,
            selectedRoomId: roomId,
            showSwitcher: true,
          );
        }
        return Row(
          children: [
            const AccountRail(),
            const VerticalDivider(width: 1),
            SizedBox(
              width: 360,
              child: ChatListPane(account: account, selectedRoomId: roomId),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: switch (roomId) {
                final id? => ChatPane(
                  key: ValueKey((account, id)),
                  account: account,
                  roomId: id,
                  showBack: false,
                  leaveWindowButtonsSpace: !showInfo,
                ),
                null => const _NoChatSelected(),
              },
            ),
            if (roomId case final id? when showInfo) ...[
              const VerticalDivider(width: 1),
              SizedBox(
                width: 360,
                child: ChatInfoPane(
                  key: ValueKey((account, id, 'info')),
                  account: account,
                  roomId: id,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _NoChatSelected extends StatelessWidget {
  const _NoChatSelected();

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: context.isDark ? OxiColors.wallpaperDark : OxiColors.wallpaperLight,
    child: Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black26,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Text(
            'Select a chat to start messaging',
            style: TextStyle(color: Colors.white),
          ),
        ),
      ),
    ),
  );
}

class ChatListPane extends ConsumerWidget {
  const ChatListPane({
    required this.account,
    this.selectedRoomId,
    this.showSwitcher = false,
    super.key,
  });

  /// The user ID of the account whose chats these are.
  final String account;
  final String? selectedRoomId;

  /// The account switcher in the header, where there is no rail.
  final bool showSwitcher;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rooms = ref.watch(roomsProvider(account)).value;
    return Scaffold(
      appBar: AppBar(
        // On a wide window the open chat is a route above the list; no back arrow there.
        automaticallyImplyLeading: false,
        leading: showSwitcher ? AccountSwitcherButton(account: account) : null,
        title: SyncTitle(account: account, roomsLoaded: rooms != null),
        actions: [
          _AccountMenu(account: account, withAppItems: showSwitcher),
          if (showSwitcher) const WindowButtonsSpace(),
        ],
      ),
      body: switch (rooms) {
        null => const Center(child: CircularProgressIndicator()),
        [] => const Center(child: Text('No chats yet')),
        final rooms => _RoomList(
          account: account,
          rooms: rooms,
          selectedRoomId: selectedRoomId,
        ),
      },
      floatingActionButton: FloatingActionButton(
        tooltip: 'New chat',
        onPressed: () => unawaited(_newChat(context, ref)),
        child: const Icon(Icons.edit_rounded),
      ),
    );
  }

  Future<void> _newChat(BuildContext context, WidgetRef ref) async {
    final userId = await showDialog<String>(
      context: context,
      builder: (_) => const _NewChatDialog(),
    );
    final session = ref.read(accountsProvider).value?.byId(account);
    if (userId == null || session == null || !context.mounted) return;
    try {
      final roomId = await session.createDm(userId);
      if (context.mounted) context.go(Routes.room(roomId));
    } on MatrixFailure catch (failure) {
      if (context.mounted) {
        showFailure(context, 'Can’t start the chat', failure);
      }
    }
  }
}

/// The app bar title: the app name, or what the connection is doing (as Telegram does).
class SyncTitle extends ConsumerWidget {
  const SyncTitle({
    required this.account,
    required this.roomsLoaded,
    super.key,
  });

  final String account;
  final bool roomsLoaded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status =
        ref.watch(syncStatusProvider(account)).value ?? SyncStatus.connecting;
    return Text(switch (status) {
      SyncStatus.offline => 'Waiting for network…',
      SyncStatus.connecting => 'Connecting…',
      SyncStatus.online when !roomsLoaded => 'Updating…',
      SyncStatus.online => 'OxiTalk',
    });
  }
}

class _AccountMenu extends ConsumerWidget {
  const _AccountMenu({required this.account, required this.withAppItems});

  final String account;

  /// Settings and About, which are at the bottom of the rail where there is one.
  final bool withAppItems;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      PopupMenuButton<VoidCallback>(
        tooltip: 'Menu',
        onSelected: (action) => action(),
        itemBuilder: (context) => [
          PopupMenuItem(enabled: false, child: Text(account)),
          if (withAppItems) ...[
            PopupMenuItem(
              value: () => context.go(Routes.settings),
              child: const Text('Settings'),
            ),
            PopupMenuItem(
              value: () => showOxiTalkAbout(context),
              child: const Text('About'),
            ),
          ],
          PopupMenuItem(
            value: () =>
                unawaited(ref.read(accountsProvider.notifier).logout(account)),
            child: const Text('Log out'),
          ),
        ],
      );
}

/// The rooms in their sections, each under a header that folds it; a plain list while every
/// room is in Rooms, as in Element.
class _RoomList extends ConsumerWidget {
  const _RoomList({
    required this.account,
    required this.rooms,
    required this.selectedRoomId,
  });

  final String account;
  final List<Room> rooms;
  final String? selectedRoomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sections =
        ref.watch(sectionsProvider(account)).value ?? const Sections();
    final collapsed =
        ref.watch(collapsedSectionTagsProvider(account)).value ?? const {};
    final groups = groupRooms(rooms, sections);
    final flat = groups.length == 1 && groups.single.tag == SectionTags.rooms;
    final movable = movableOrder(sections);
    final items = <Object>[
      for (final group in groups) ...[
        if (!flat) group,
        if (flat || !collapsed.contains(group.tag)) ...group.rooms,
      ],
    ];
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, index) => switch (items[index]) {
        final RoomGroup group => SectionHeader(
          account: account,
          group: group,
          collapsed: collapsed.contains(group.tag),
          canMoveUp: movable.indexOf(group.tag) > 0,
          canMoveDown:
              group.isMovable &&
              movable.indexOf(group.tag) < movable.length - 1,
        ),
        final Room room => RoomTile(
          account: account,
          room: room,
          selected: room.id == selectedRoomId,
        ),
        _ => const SizedBox.shrink(),
      },
    );
  }
}

/// A section's title, unread count and menu; tapping it folds or unfolds the section.
class SectionHeader extends ConsumerWidget {
  const SectionHeader({
    required this.account,
    required this.group,
    required this.collapsed,
    required this.canMoveUp,
    required this.canMoveDown,
    super.key,
  });

  final String account;
  final RoomGroup group;
  final bool collapsed;
  final bool canMoveUp;
  final bool canMoveDown;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final actions = SectionActions(context, ref, account);
    final unread = group.unread;
    return InkWell(
      key: Key('section.${group.tag}'),
      onTap: () => ref
          .read(collapsedSectionTagsProvider(account).notifier)
          .toggle(group.tag),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
        child: SizedBox(
          height: 36,
          child: Row(
            children: [
              Icon(
                collapsed
                    ? Icons.chevron_right_rounded
                    : Icons.expand_more_rounded,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  group.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              // Folded, the count says what is hidden.
              if (collapsed && unread > 0) _Badge(count: unread),
              if (group.isMovable)
                PopupMenuButton<VoidCallback>(
                  key: Key('sectionMenu.${group.tag}'),
                  tooltip: 'Section menu',
                  icon: const Icon(Icons.more_horiz_rounded, size: 20),
                  onSelected: (action) => action(),
                  itemBuilder: (_) => [
                    if (group.isCustom)
                      PopupMenuItem(
                        value: () => unawaited(actions.rename(group.tag)),
                        child: const Text('Rename…'),
                      ),
                    PopupMenuItem(
                      enabled: canMoveUp,
                      value: () => unawaited(actions.move(group.tag, -1)),
                      child: const Text('Move up'),
                    ),
                    PopupMenuItem(
                      enabled: canMoveDown,
                      value: () => unawaited(actions.move(group.tag, 1)),
                      child: const Text('Move down'),
                    ),
                    if (group.isCustom)
                      PopupMenuItem(
                        value: () => unawaited(actions.delete(group.tag)),
                        child: const Text('Delete…'),
                      ),
                  ],
                )
              else
                const SizedBox(width: 40),
            ],
          ),
        ),
      ),
    );
  }
}

class RoomTile extends ConsumerWidget {
  const RoomTile({
    required this.account,
    required this.room,
    this.selected = false,
    super.key,
  });

  final String account;
  final Room room;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final invited = room.membership == Membership.invited;
    return GestureDetector(
      // Right-click on desktop, long-press on a phone; an invite has no sections yet.
      onSecondaryTapUp: invited
          ? null
          : (details) => unawaited(_menu(context, ref, details.globalPosition)),
      onLongPressStart: invited
          ? null
          : (details) => unawaited(_menu(context, ref, details.globalPosition)),
      child: _tile(context, ref, theme, invited),
    );
  }

  Future<void> _menu(BuildContext context, WidgetRef ref, Offset at) async {
    final sections =
        ref.read(sectionsProvider(account)).value ?? const Sections();
    final current = sectionOf(room, sections);
    final actions = SectionActions(context, ref, account);
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final action = await showMenu<VoidCallback>(
      context: context,
      position: RelativeRect.fromRect(
        at & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: () => unawaited(
            actions.setSection(
              room,
              current == SectionTags.favourites ? null : SectionTags.favourites,
            ),
          ),
          child: Text(
            current == SectionTags.favourites
                ? 'Remove from favorites'
                : 'Add to favorites',
          ),
        ),
        PopupMenuItem(
          value: () => unawaited(
            actions.setSection(
              room,
              current == SectionTags.lowPriority
                  ? null
                  : SectionTags.lowPriority,
            ),
          ),
          child: Text(
            current == SectionTags.lowPriority
                ? 'Remove from low priority'
                : 'Low priority',
          ),
        ),
        PopupMenuItem(
          value: () => unawaited(actions.chooseFor(room)),
          child: const Text('Move to section…'),
        ),
        PopupMenuItem(
          value: () => unawaited(actions.create(room: room)),
          child: const Text('New section…'),
        ),
      ],
    );
    action?.call();
  }

  Widget _tile(
    BuildContext context,
    WidgetRef ref,
    ThemeData theme,
    bool invited,
  ) {
    return ListTile(
      selected: selected,
      selectedTileColor: theme.colorScheme.primaryContainer,
      leading: MatrixAvatar(
        account: account,
        url: room.avatarUrl,
        name: room.name,
        seed: room.id,
      ),
      title: Row(
        children: [
          if (room.isEncrypted) ...[
            Icon(
              Icons.lock_rounded,
              size: 14,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Text(
              room.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (room.lastActivity case final time?)
            Text(listTime(time), style: theme.textTheme.bodySmall),
        ],
      ),
      subtitle: Row(
        children: [
          Expanded(
            child: Text(
              invited ? 'Invitation — tap to join' : room.lastMessage ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: invited
                  ? TextStyle(color: theme.colorScheme.primary)
                  : null,
            ),
          ),
          if (room.unreadCount > 0) _Badge(count: room.unreadCount),
        ],
      ),
      onTap: () => unawaited(_open(context, ref)),
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    // Joining moves the room from Invites to its section, which replaces this tile; so the
    // router and the messenger are taken before.
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (room.membership == Membership.invited) {
      try {
        await ref.read(accountsProvider).value?.byId(account)?.join(room.id);
      } on MatrixFailure catch (failure) {
        messenger.showSnackBar(failureSnackBar('Can’t join', failure));
        return;
      }
    }
    router.go(Routes.room(room.id));
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(left: 8),
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: OxiColors.accent,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      count > 999 ? '999+' : '$count',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class _NewChatDialog extends StatefulWidget {
  const _NewChatDialog();

  @override
  State<_NewChatDialog> createState() => _NewChatDialogState();
}

class _NewChatDialogState extends State<_NewChatDialog> {
  final _userId = TextEditingController();

  @override
  void dispose() {
    _userId.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_userId.text.trim());

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('New chat'),
    content: TextField(
      key: const Key('newChat.userId'),
      controller: _userId,
      autofocus: true,
      decoration: const InputDecoration(
        labelText: 'User ID',
        hintText: '@name:server.org',
      ),
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Start')),
    ],
  );
}

void showFailure(BuildContext context, String what, MatrixFailure failure) =>
    ScaffoldMessenger.of(context).showSnackBar(failureSnackBar(what, failure));

SnackBar failureSnackBar(String what, MatrixFailure failure) => SnackBar(
  content: Text(
    '$what: ${failure.kind == FailureKind.invalidId ? 'invalid ID “${failure.message}”' : failure.kind.name}',
  ),
);
