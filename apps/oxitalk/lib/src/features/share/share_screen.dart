// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
import '../../matrix/api/matrix.dart';
import '../../ui/avatar.dart';
import '../chats/chats_screen.dart';
import 'share_inbox.dart';

/// "Send to…": what another app shared, and the chats to send it to, filtered as the chat
/// list is. With several accounts, the user picks whose chats show. A pick opens the chat
/// with the files in the send dialog and the text in the message box; ✕ drops the share.
class ShareTargetScreen extends ConsumerStatefulWidget {
  const ShareTargetScreen({super.key});

  @override
  ConsumerState<ShareTargetScreen> createState() => _ShareTargetScreenState();
}

class _ShareTargetScreenState extends ConsumerState<ShareTargetScreen> {
  final _filter = TextEditingController();
  final _filterFocus = FocusNode(debugLabel: 'share.filter');

  /// The account whose chats show; the one in front until the user picks another.
  String? _account;

  @override
  void dispose() {
    _filter.dispose();
    _filterFocus.dispose();
    super.dispose();
  }

  void _cancel() {
    ref.read(pendingShareProvider.notifier).clear();
    // The router leaves this screen once nothing waits.
  }

  void _pick(String account, Room room) {
    final items = ref.read(pendingShareProvider);
    if (items == null) return;
    ref
        .read(shareDeliveryProvider.notifier)
        .deliver(ShareDelivery(account, room.id, items));
    final router = GoRouter.of(context);
    if (ref.read(activeAccountProvider) != account) {
      ref.read(accountsProvider.notifier).activate(account);
      // Lets the switch to the account go where it goes first, so the chat comes after.
      ref.read(activeAccountProvider);
    }
    ref.read(pendingShareProvider.notifier).clear();
    router.go(Routes.room(room.id));
  }

  /// [account]'s chats the filter leaves, in the chat list's order; invites can't take a
  /// message yet.
  List<Room> _rooms(String account, {bool watch = true}) {
    final all =
        (watch
                ? ref.watch(roomsProvider(account))
                : ref.read(roomsProvider(account)))
            .value ??
        const <Room>[];
    return [
      for (final group in filteredRoomGroups(
        ref,
        account,
        [
          for (final room in all)
            if (room.membership != Membership.invited) room,
        ],
        _filter.text,
        watch: watch,
      ))
        ...group.rooms,
    ];
  }

  /// Enter in the filter: the first chat it leaves.
  void _pickFirst(String? account) {
    if (account == null) return;
    final first = _rooms(account, watch: false).firstOrNull;
    if (first != null) _pick(account, first);
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(pendingShareProvider);
    final sessions =
        ref.watch(accountsProvider).value?.sessions ?? const <MatrixSession>[];
    final ids = [for (final session in sessions) session.userId];
    final active = ref.watch(activeAccountProvider);
    final account = ids.contains(_account) ? _account : active;
    final palette = context.oxi;
    final rooms = account == null ? const <Room>[] : _rooms(account);
    final loaded =
        account != null && ref.watch(roomsProvider(account)).value != null;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: Scaffold(
        key: const Key('share'),
        appBar: AppBar(
          leading: IconButton(
            key: const Key('share.cancel'),
            tooltip: 'Cancel',
            onPressed: _cancel,
            icon: const Icon(Icons.close_rounded),
          ),
          title: const Text('Send to…'),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (items != null) _Summary(items: items),
                if (ids.length > 1)
                  SizedBox(
                    height: 48,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      children: [
                        for (final id in ids)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: _AccountChip(
                              account: id,
                              selected: id == account,
                              onSelected: () => setState(() => _account = id),
                            ),
                          ),
                      ],
                    ),
                  ),
                ListFilterField(
                  controller: _filter,
                  focusNode: _filterFocus,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: () => _pickFirst(account),
                  onClear: ({unfocus = false}) {
                    _filter.clear();
                    setState(() {});
                    if (unfocus) _filterFocus.unfocus();
                  },
                ),
                Expanded(
                  child: !loaded
                      ? const Center(child: CircularProgressIndicator())
                      : rooms.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                          child: Text(
                            _filter.text.trim().isEmpty
                                ? 'No chats yet'
                                : 'No chats match',
                            key: const Key('share.empty'),
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: palette.muted),
                          ),
                        )
                      : ListView.builder(
                          itemCount: rooms.length,
                          itemBuilder: (context, index) => _RoomChoice(
                            account: account,
                            room: rooms[index],
                            onTap: () => _pick(account, rooms[index]),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// What is about to be sent: the files' names and the text's start.
class _Summary extends StatelessWidget {
  const _Summary({required this.items});

  final SharedItems items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.oxi;
    final names = items.names;
    final files = switch (names.length) {
      0 => null,
      1 => names.single,
      <= 3 => names.join(', '),
      _ => '${names.take(2).join(', ')} and ${names.length - 2} more',
    };
    return Padding(
      key: const Key('share.summary'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          Icon(
            names.isEmpty ? Icons.notes_rounded : Icons.attach_file_rounded,
            color: palette.muted,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (files != null)
                  Text(
                    files,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                if (items.text.isNotEmpty)
                  Text(
                    items.text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: palette.muted,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountChip extends ConsumerWidget {
  const _AccountChip({
    required this.account,
    required this.selected,
    required this.onSelected,
  });

  final String account;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider(account)).value;
    return Tooltip(
      message: account,
      child: ChoiceChip(
        key: Key('share.account.$account'),
        selected: selected,
        onSelected: (_) => onSelected(),
        avatar: MatrixAvatar(
          account: account,
          url: profile?.avatarUrl,
          name: profile?.displayName ?? account,
          seed: account,
          radius: 10,
        ),
        label: Text(profile?.displayName ?? account),
      ),
    );
  }
}

/// A chat as the chat list shows it, without its unread count and menu.
class _RoomChoice extends StatelessWidget {
  const _RoomChoice({
    required this.account,
    required this.room,
    required this.onTap,
  });

  final String account;
  final Room room;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.oxi;
    return ListTile(
      key: Key('share.room.${room.id}'),
      leading: MatrixAvatar(
        account: account,
        url: room.avatarUrl,
        name: room.name,
        seed: room.id,
      ),
      title: Row(
        children: [
          if (room.isEncrypted) ...[
            Icon(Icons.lock_rounded, size: 13, color: palette.muted),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Text(
              room.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      subtitle: room.lastMessage == null
          ? null
          : Text(
              room.lastMessage!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: palette.muted),
            ),
      onTap: onTap,
    );
  }
}
