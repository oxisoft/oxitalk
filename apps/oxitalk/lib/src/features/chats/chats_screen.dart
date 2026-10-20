import 'dart:async';
import 'dart:math';

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

/// The active account's chats: on a wide window the account rail (unless hidden), the list
/// (perhaps narrowed) and the open chat or its info side by side; otherwise the list alone.
class ChatsScreen extends ConsumerWidget {
  const ChatsScreen({this.roomId, this.showInfo = false, super.key});

  /// The open chat, if any.
  final String? roomId;

  /// The open chat's info, in the chat's place.
  final bool showInfo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(activeAccountProvider);
    if (account == null) return const SizedBox.shrink();
    final rooms = ref.watch(roomsProvider(account)).value;
    // A remembered chat that is gone (left, or deleted) shows the welcome instead.
    final roomId = switch (this.roomId) {
      final id? when rooms == null || rooms.any((room) => room.id == id) => id,
      _ => null,
    };
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < wideLayoutBreakpoint) {
          return ChatListPane(
            account: account,
            selectedRoomId: roomId,
            phone: true,
          );
        }
        final narrow = ref.watch(narrowListProvider);
        final railHidden = ref.watch(railHiddenProvider);
        return Row(
          children: [
            if (!railHidden) ...[
              const AccountRail(),
              const VerticalDivider(width: 1),
            ],
            SizedBox(
              width: narrow ? 96 : 360,
              child: ChatListPane(account: account, selectedRoomId: roomId),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              // Its own messenger: a snack bar shows in the pane it is about, not in
              // every pane of the window.
              child: ScaffoldMessenger(
                child: switch (roomId) {
                  final id? when showInfo => ChatInfoPane(
                    key: ValueKey((account, id, 'info')),
                    account: account,
                    roomId: id,
                  ),
                  final id? => ChatPane(
                    key: ValueKey((account, id)),
                    account: account,
                    roomId: id,
                    showBack: false,
                  ),
                  null => WelcomePane(account: account),
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

/// What shows where a chat would, before one is picked: a greeting by the time of day, one
/// friendly line, and where to start.
class WelcomePane extends ConsumerStatefulWidget {
  const WelcomePane({required this.account, super.key});

  final String account;

  @override
  ConsumerState<WelcomePane> createState() => _WelcomePaneState();
}

const _smallTalk = [
  'Your messages are end-to-end encrypted: only you and the people you talk to can read them.',
  'Several accounts at once? Ctrl+1, Ctrl+2… switches between them.',
  'Right-click a chat to make it a favorite, or to put it in a section of your own.',
  'Click a chat’s name at the top to see its members, photos, files and links.',
  'Matrix is an open network: you can talk to people on any server, like email.',
  'Sections you make here show up in Element too, and the other way round.',
  'Pictures and files are kept on this device for as long as Settings → Media says.',
];

/// `Good morning`, `Good afternoon`, `Good evening`, or `Good night`, for [hour].
String greeting(int hour) => switch (hour) {
  < 5 => 'Good night',
  < 12 => 'Good morning',
  < 18 => 'Good afternoon',
  < 23 => 'Good evening',
  _ => 'Good night',
};

class _WelcomePaneState extends ConsumerState<WelcomePane> {
  /// Picked once, so it doesn't change while the pane shows.
  final _line = _smallTalk[Random().nextInt(_smallTalk.length)];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profile = ref.watch(profileProvider(widget.account)).value;
    final name =
        profile?.displayName ?? widget.account.substring(1).split(':').first;
    return Scaffold(
      backgroundColor: context.isDark
          ? OxiColors.wallpaperDark
          : OxiColors.wallpaperLight,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        flexibleSpace: const WindowDragArea(),
        actions: const [WindowButtons.right()],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              key: const Key('welcome'),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircleAvatar(
                      radius: 36,
                      backgroundColor: OxiColors.accent,
                      foregroundColor: Colors.white,
                      child: Icon(Icons.forum_rounded, size: 36),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      '${greeting(DateTime.now().hour)}, $name',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _line,
                      key: const Key('welcome.line'),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.west_rounded,
                          size: 18,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Pick a chat on the left to start.',
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The account's chats under a header with the account dropdown; on a wide window it can be
/// narrowed to pictures and short names, and brings back a hidden account rail.
class ChatListPane extends ConsumerWidget {
  const ChatListPane({
    required this.account,
    this.selectedRoomId,
    this.phone = false,
    super.key,
  });

  /// The user ID of the account whose chats these are.
  final String account;
  final String? selectedRoomId;

  /// The whole window: no rail, no narrowing, and the window buttons in this header.
  final bool phone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rooms = ref.watch(roomsProvider(account)).value;
    final narrow = !phone && ref.watch(narrowListProvider);
    final railHidden = phone || ref.watch(railHiddenProvider);
    final narrowButton = IconButton(
      key: Key(narrow ? 'list.widen' : 'list.narrow'),
      tooltip: narrow ? 'Widen the list' : 'Narrow the list',
      visualDensity: VisualDensity.compact,
      onPressed: () => ref.read(narrowListProvider.notifier).toggle(),
      icon: Icon(
        narrow
            ? Icons.keyboard_double_arrow_right_rounded
            : Icons.keyboard_double_arrow_left_rounded,
      ),
    );
    final showRail = IconButton(
      key: const Key('rail.show'),
      tooltip: 'Show accounts',
      visualDensity: VisualDensity.compact,
      onPressed: () => ref.read(railHiddenProvider.notifier).toggle(),
      icon: const Icon(Icons.keyboard_double_arrow_right_rounded),
    );
    return Scaffold(
      appBar: AppBar(
        // On a wide window the open chat is a route above the list; no back arrow there.
        automaticallyImplyLeading: false,
        flexibleSpace: const WindowDragArea(),
        titleSpacing: narrow ? 0 : 8,
        centerTitle: narrow,
        title: narrow
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AccountDropdown(
                    account: account,
                    compact: true,
                    withAppItems: railHidden,
                  ),
                  narrowButton,
                ],
              )
            : Row(
                children: [
                  if (!phone) const WindowButtons.left(),
                  if (railHidden && !phone) showRail,
                  Flexible(
                    child: AccountDropdown(
                      account: account,
                      withAppItems: railHidden,
                    ),
                  ),
                ],
              ),
        actions: [
          if (!phone && !narrow) narrowButton,
          if (phone) const WindowButtons.right(),
        ],
      ),
      body: switch (rooms) {
        null => const Center(child: CircularProgressIndicator()),
        [] => Center(child: Text(narrow ? '—' : 'No chats yet')),
        final rooms => _RoomList(
          account: account,
          rooms: rooms,
          selectedRoomId: selectedRoomId,
          narrow: narrow,
        ),
      },
      floatingActionButton: FloatingActionButton(
        tooltip: 'New chat',
        mini: narrow,
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

/// The rooms in their sections, each under a header that folds it; a plain list while every
/// room is in Rooms, as in Element.
class _RoomList extends ConsumerWidget {
  const _RoomList({
    required this.account,
    required this.rooms,
    required this.selectedRoomId,
    this.narrow = false,
  });

  final String account;
  final List<Room> rooms;
  final String? selectedRoomId;

  /// Pictures and short names only: no section headers, every room in section order.
  final bool narrow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sections =
        ref.watch(sectionsProvider(account)).value ?? const Sections();
    final collapsed =
        ref.watch(collapsedSectionTagsProvider(account)).value ?? const {};
    final groups = groupRooms(rooms, sections);
    final flat =
        narrow ||
        (groups.length == 1 && groups.single.tag == SectionTags.rooms);
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
          narrow: narrow,
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
    this.narrow = false,
    super.key,
  });

  final String account;
  final Room room;
  final bool selected;

  /// The picture with the unread count, and the name's start under it.
  final bool narrow;

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
    if (narrow) return _narrowTile(context, ref, theme, invited);
    final typing = typingLabel(
      ref.watch(typingProvider(account)).value?[room.id],
      direct: room.isDm,
    );
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
              invited
                  ? 'Invitation — tap to join'
                  : typing ?? room.lastMessage ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: invited || typing != null
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

  Widget _narrowTile(
    BuildContext context,
    WidgetRef ref,
    ThemeData theme,
    bool invited,
  ) => Tooltip(
    message: room.name,
    child: Material(
      color: selected ? theme.colorScheme.primaryContainer : Colors.transparent,
      child: InkWell(
        onTap: () => unawaited(_open(context, ref)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Column(
            children: [
              Badge(
                isLabelVisible: invited || room.unreadCount > 0,
                backgroundColor: OxiColors.accent,
                label: Text(
                  invited
                      ? '!'
                      : room.unreadCount > 99
                      ? '99+'
                      : '${room.unreadCount}',
                ),
                child: MatrixAvatar(
                  account: account,
                  url: room.avatarUrl,
                  name: room.name,
                  seed: room.id,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                room.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall,
              ),
            ],
          ),
        ),
      ),
    ),
  );

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
