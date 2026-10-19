import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
import '../../matrix/api/matrix.dart';
import '../../rust/api.dart';
import '../../ui/avatar.dart';
import '../../ui/format.dart';
import '../chat/chat_pane.dart';

/// The chats: on a wide window the list and the open chat side by side, otherwise the list.
class ChatsScreen extends StatelessWidget {
  const ChatsScreen({this.roomId, super.key});

  /// The open chat, if any.
  final String? roomId;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < wideLayoutBreakpoint) {
        return ChatListPane(selectedRoomId: roomId);
      }
      return Row(
        children: [
          SizedBox(width: 360, child: ChatListPane(selectedRoomId: roomId)),
          const VerticalDivider(width: 1),
          Expanded(
            child: switch (roomId) {
              final id? => ChatPane(
                key: ValueKey(id),
                roomId: id,
                showBack: false,
              ),
              null => const _NoChatSelected(),
            },
          ),
        ],
      );
    },
  );
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
  const ChatListPane({this.selectedRoomId, super.key});

  final String? selectedRoomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rooms = ref.watch(roomsProvider).value;
    return Scaffold(
      appBar: AppBar(
        // On a wide window the open chat is a route above the list; no back arrow there.
        automaticallyImplyLeading: false,
        title: SyncTitle(roomsLoaded: rooms != null),
        actions: const [_AccountMenu()],
      ),
      body: switch (rooms) {
        null => const Center(child: CircularProgressIndicator()),
        [] => const Center(child: Text('No chats yet')),
        final rooms => ListView.builder(
          itemCount: rooms.length,
          itemBuilder: (context, index) => RoomTile(
            room: rooms[index],
            selected: rooms[index].id == selectedRoomId,
          ),
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
    final session = ref.read(authProvider).value;
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
  const SyncTitle({required this.roomsLoaded, super.key});

  final bool roomsLoaded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncStatusProvider).value ?? SyncStatus.connecting;
    return Text(switch (status) {
      SyncStatus.offline => 'Waiting for network…',
      SyncStatus.connecting => 'Connecting…',
      SyncStatus.online when !roomsLoaded => 'Updating…',
      SyncStatus.online => 'OxiTalk',
    });
  }
}

class _AccountMenu extends ConsumerWidget {
  const _AccountMenu();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(authProvider).value?.userId ?? '';
    return PopupMenuButton<VoidCallback>(
      tooltip: 'Menu',
      onSelected: (action) => action(),
      itemBuilder: (context) => [
        PopupMenuItem(enabled: false, child: Text(userId)),
        PopupMenuItem(
          value: () => showAboutDialog(
            context: context,
            applicationName: 'OxiTalk',
            applicationLegalese: 'Rust core ${coreVersion()}',
          ),
          child: const Text('About'),
        ),
        PopupMenuItem(
          value: () => unawaited(ref.read(authProvider.notifier).logout()),
          child: const Text('Log out'),
        ),
      ],
    );
  }
}

class RoomTile extends ConsumerWidget {
  const RoomTile({required this.room, this.selected = false, super.key});

  final Room room;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final invited = room.membership == Membership.invited;
    return ListTile(
      selected: selected,
      selectedTileColor: theme.colorScheme.primaryContainer,
      leading: InitialsAvatar(name: room.name, seed: room.id),
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
    if (room.membership == Membership.invited) {
      try {
        await ref.read(authProvider).value?.join(room.id);
      } on MatrixFailure catch (failure) {
        if (context.mounted) showFailure(context, 'Can’t join', failure);
        return;
      }
    }
    if (context.mounted) context.go(Routes.room(room.id));
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

void showFailure(BuildContext context, String what, MatrixFailure failure) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        '$what: ${failure.kind == FailureKind.invalidId ? 'invalid ID “${failure.message}”' : failure.kind.name}',
      ),
    ),
  );
}
