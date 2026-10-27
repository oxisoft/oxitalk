import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
import '../../matrix/api/matrix.dart';
import '../../ui/avatar.dart';
import '../../ui/format.dart';
import '../../ui/pane_divider.dart';
import '../accounts/account_switcher.dart';
import '../chat/chat_pane.dart';
import '../chat/drafts.dart';
import '../chat/threads.dart';
import '../chat_info/chat_info.dart';
import '../chat_info/room_notifications.dart';
import '../chat_info/room_settings.dart';
import 'badges.dart';
import 'finders.dart';
import 'membership_actions.dart';
import 'new_room.dart';
import 'notification_actions.dart';
import 'pane_layout.dart';
import 'room_groups.dart';
import 'section_actions.dart';

/// The active account's chats: on a wide window the account rail (unless hidden), the list
/// (perhaps narrowed) and the open chat or its info side by side, with a thread or the thread
/// list beside the chat, the lines between them dragged to resize the list and the thread;
/// otherwise the list alone.
class ChatsScreen extends ConsumerWidget {
  const ChatsScreen({
    this.roomId,
    this.showInfo = false,
    this.showNotifications = false,
    this.showSecurity = false,
    this.thread,
    this.showThreads = false,
    super.key,
  });

  /// The open chat, if any.
  final String? roomId;

  /// The open chat's info, in the chat's place.
  final bool showInfo;

  /// The open chat's notification settings, in the chat's place.
  final bool showNotifications;

  /// The open chat's security and privacy settings, in the chat's place.
  final bool showSecurity;

  /// The thread open beside the chat: the event ID of its first message.
  final String? thread;

  /// The chat's thread list, beside it.
  final bool showThreads;

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
        final window = constraints.maxWidth;
        final rail = railHidden ? 0.0 : AccountRail.width + 1;
        final hasSide =
            roomId != null &&
            !showInfo &&
            !showNotifications &&
            !showSecurity &&
            (thread != null || showThreads);
        final panes = PaneLayout.fit(
          window: window,
          rail: rail,
          list: ref.watch(listWidthProvider),
          narrow: narrow,
          thread: ref.watch(threadWidthProvider),
          hasThread: hasSide,
        );
        final listWidth = ref.read(listWidthProvider.notifier);
        final threadWidth = ref.read(threadWidthProvider.notifier);
        // The grips lie over the lines, half a grip either side.
        const grip = PaneDivider.gripWidth;
        return Stack(
          fit: StackFit.expand,
          children: [
            Row(
              children: [
                if (!railHidden) ...[
                  const AccountRail(),
                  const VerticalDivider(width: 1),
                ],
                SizedBox(
                  width: panes.list,
                  child: ChatListPane(account: account, selectedRoomId: roomId),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  // Its own messenger: a snack bar shows in the pane it is about, not in
                  // every pane of the window.
                  child: ScaffoldMessenger(
                    child: switch (roomId) {
                      final id? when showNotifications => RoomNotificationsPane(
                        key: ValueKey((account, id, 'notifications')),
                        account: account,
                        roomId: id,
                      ),
                      final id? when showSecurity => RoomSecurityPane(
                        key: ValueKey((account, id, 'security')),
                        account: account,
                        roomId: id,
                      ),
                      final id? when showInfo => ChatInfoPane(
                        key: ValueKey((account, id, 'info')),
                        account: account,
                        roomId: id,
                      ),
                      final id? => _withSide(account, id, panes.thread),
                      null => WelcomePane(account: account),
                    },
                  ),
                ),
              ],
            ),
            // The narrowed list keeps its width: no grip.
            if (!narrow)
              Positioned(
                left: rail + panes.list + 0.5 - grip / 2,
                top: 0,
                bottom: 0,
                width: grip,
                child: PaneDivider(
                  key: const Key('divider.list'),
                  label: 'Resize chat list',
                  width: panes.list,
                  growsRight: true,
                  onResize: (width) => listWidth.drag(panes.clampList(width)),
                  onResizeEnd: listWidth.save,
                  onReset: listWidth.reset,
                ),
              ),
            if (panes.thread case final width?)
              Positioned(
                right: width + 0.5 - grip / 2,
                top: 0,
                bottom: 0,
                width: grip,
                child: PaneDivider(
                  key: const Key('divider.thread'),
                  label: 'Resize thread',
                  width: width,
                  growsRight: false,
                  onResize: (width) =>
                      threadWidth.drag(panes.clampThread(width)),
                  onResizeEnd: threadWidth.save,
                  onReset: threadWidth.reset,
                ),
              ),
          ],
        );
      },
    );
  }
}

extension on ChatsScreen {
  /// The chat, and beside it the open thread or the thread list, [sideWidth] wide.
  Widget _withSide(String account, String roomId, double? sideWidth) {
    final side = switch ((thread, showThreads)) {
      (final root?, _) => ThreadPane(
        key: ValueKey((account, roomId, root)),
        account: account,
        roomId: roomId,
        rootEventId: root,
        showBack: false,
      ),
      (null, true) => ThreadListPane(
        key: ValueKey((account, roomId, 'threads')),
        account: account,
        roomId: roomId,
        showBack: false,
      ),
      _ => null,
    };
    final chat = ChatPane(
      key: ValueKey((account, roomId)),
      account: account,
      roomId: roomId,
      showBack: false,
    );
    if (side == null) return chat;
    return Row(
      children: [
        Expanded(child: chat),
        const VerticalDivider(width: 1),
        SizedBox(
          width: sideWidth ?? PaneLayout.threadDefault,
          child: ScaffoldMessenger(child: side),
        ),
      ],
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
  'Pictures and files are kept on this device for as long as Settings → Media & storage says.',
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
      backgroundColor: context.oxi.wallpaper,
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
                    Container(
                      width: 72,
                      height: 72,
                      decoration: ShapeDecoration(
                        color: OxiBrand.ink,
                        shape: OxiShapes.cut(14),
                      ),
                      child: const Icon(
                        Icons.forum_rounded,
                        size: 36,
                        color: OxiBrand.yellow,
                      ),
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

  /// The whole window: no rail, no narrowing.
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
                  if (railHidden && !phone) showRail,
                  Flexible(
                    child: AccountDropdown(
                      account: account,
                      withAppItems: railHidden,
                    ),
                  ),
                ],
              ),
        actions: [if (!phone && !narrow) narrowButton],
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
      floatingActionButton: Builder(
        builder: (context) => FloatingActionButton(
          key: const Key('newMenu'),
          tooltip: 'New chat or room',
          mini: narrow,
          onPressed: () => unawaited(_newMenu(context, ref)),
          child: const Icon(Icons.edit_rounded),
        ),
      ),
    );
  }

  /// What ✏️ offers: a chat with a person, a new room, or joining one.
  Future<void> _newMenu(BuildContext context, WidgetRef ref) async {
    final button = context.findRenderObject()! as RenderBox;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        button.localToGlobal(Offset.zero, ancestor: overlay) & button.size,
        Offset.zero & overlay.size,
      ),
      items: const [
        PopupMenuItem(
          key: Key('newMenu.chat'),
          value: 'chat',
          child: ListTile(
            leading: Icon(Icons.person_add_alt_rounded),
            title: Text('New chat'),
          ),
        ),
        PopupMenuItem(
          key: Key('newMenu.room'),
          value: 'room',
          child: ListTile(
            leading: Icon(Icons.group_add_rounded),
            title: Text('New room'),
          ),
        ),
        PopupMenuItem(
          key: Key('newMenu.join'),
          value: 'join',
          child: ListTile(
            leading: Icon(Icons.login_rounded),
            title: Text('Join a room'),
          ),
        ),
      ],
    );
    if (!context.mounted) return;
    switch (choice) {
      case 'chat':
        await _newChat(context, ref);
      case 'room':
        await createRoom(context, ref, account);
      case 'join':
        await joinRoom(context, ref, account);
    }
  }

  /// Lets the user pick someone and opens their direct chat, starting one if there is none.
  Future<void> _newChat(BuildContext context, WidgetRef ref) async {
    final session = ref.read(accountsProvider).value?.byId(account);
    if (session == null) return;
    final userId = await showDialog<String>(
      context: context,
      builder: (_) => newChatDialog(account: account, session: session),
    );
    if (userId == null || !context.mounted) return;
    final existing = session.dmWith(userId);
    if (existing != null) {
      context.go(Routes.room(existing));
      return;
    }
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
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              // Folded, the count says what is hidden.
              if (collapsed && unread > 0) CountBadge(count: unread),
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
      // Right-click on desktop, long-press on a phone; an invite has no sections yet, only
      // Accept and Decline.
      onSecondaryTapUp: (details) => unawaited(
        invited
            ? _inviteMenu(context, ref, details.globalPosition)
            : _menu(context, ref, details.globalPosition),
      ),
      onLongPressStart: (details) => unawaited(
        invited
            ? _inviteMenu(context, ref, details.globalPosition)
            : _menu(context, ref, details.globalPosition),
      ),
      child: _tile(context, ref, theme, invited),
    );
  }

  Future<void> _inviteMenu(
    BuildContext context,
    WidgetRef ref,
    Offset at,
  ) async {
    final membership = MembershipActions(context, ref, account);
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
          key: const Key('roomMenu.accept'),
          value: () => unawaited(membership.accept(room.id)),
          child: const Text('Accept'),
        ),
        PopupMenuItem(
          key: const Key('roomMenu.decline'),
          value: () => unawaited(membership.decline(room.id, name: room.name)),
          child: Text(
            'Decline',
            style: TextStyle(
              color: OxiButtons.danger(Theme.of(context).brightness),
            ),
          ),
        ),
      ],
    );
    action?.call();
  }

  Future<void> _menu(BuildContext context, WidgetRef ref, Offset at) async {
    final sections =
        ref.read(sectionsProvider(account)).value ?? const Sections();
    final current = sectionOf(room, sections);
    final actions = SectionActions(context, ref, account);
    final notifications = RoomNotificationActions(context, ref, account);
    final membership = MembershipActions(context, ref, account);
    final danger = OxiButtons.danger(Theme.of(context).brightness);
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
          key: Key(
            room.hasUnread ? 'roomMenu.markRead' : 'roomMenu.markUnread',
          ),
          value: () => unawaited(notifications.toggleRead(room)),
          child: Text(room.hasUnread ? 'Mark as read' : 'Mark as unread'),
        ),
        PopupMenuItem(
          key: const Key('roomMenu.notifications'),
          // A submenu: it opens where this menu was.
          value: () => unawaited(notifications.showMenuFor(room, at)),
          child: const Row(
            children: [
              Expanded(child: Text('Notifications')),
              Icon(Icons.arrow_right_rounded),
            ],
          ),
        ),
        const PopupMenuDivider(),
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
        const PopupMenuDivider(),
        PopupMenuItem(
          key: const Key('roomMenu.leave'),
          value: () => unawaited(
            membership.leave(room.id, name: room.name, isDm: room.isDm),
          ),
          child: Text(
            room.isDm ? 'Leave chat' : 'Leave room',
            style: TextStyle(color: danger),
          ),
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
    final draft = invited
        ? null
        : ref.watch(
            draftsProvider(account).select((drafts) => drafts[room.id]),
          );
    final palette = context.oxi;
    final tile = ListTile(
      selected: selected,
      selectedTileColor: palette.selectedRow,
      selectedColor: palette.text,
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
          if (room.lastActivity case final time?)
            Text(
              listTime(time),
              style: theme.textTheme.bodySmall?.copyWith(color: palette.muted),
            ),
        ],
      ),
      subtitle: Row(
        children: [
          Expanded(
            child: Text.rich(
              typing == null && draft != null
                  ? TextSpan(
                      children: [
                        TextSpan(
                          text: 'Draft: ',
                          style: TextStyle(
                            color: OxiButtons.danger(theme.brightness),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        TextSpan(text: draft),
                      ],
                    )
                  : TextSpan(
                      text: invited
                          ? 'Invitation — tap to see it'
                          : typing ?? room.lastMessage ?? '',
                    ),
              key: draft != null ? Key('draft.${room.id}') : null,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.muted,
                fontStyle: typing != null ? FontStyle.italic : null,
                fontWeight: invited ? FontWeight.w600 : null,
              ),
            ),
          ),
          if (room.isMuted && !invited)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: MutedIcon(key: Key('muted.${room.id}')),
            ),
          RoomBadgeView(room: room),
        ],
      ),
      onTap: () => unawaited(_open(context, ref)),
    );
    if (!selected) return tile;
    // The open chat: a yellow bar at its left edge.
    return Container(
      foregroundDecoration: const BoxDecoration(
        border: Border(left: BorderSide(color: OxiBrand.yellow, width: 3)),
      ),
      child: tile,
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
      color: selected ? context.oxi.selectedRow : Colors.transparent,
      shape: selected
          ? const Border(left: BorderSide(color: OxiBrand.yellow, width: 3))
          : null,
      child: InkWell(
        onTap: () => unawaited(_open(context, ref)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Column(
            children: [
              narrowBadge(
                context,
                room,
                MatrixAvatar(
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

  /// Opens the chat; an invitation opens its preview, which accepts or declines it.
  Future<void> _open(BuildContext context, WidgetRef ref) async =>
      GoRouter.of(context).go(Routes.room(room.id));
}

void showFailure(BuildContext context, String what, MatrixFailure failure) =>
    ScaffoldMessenger.of(context).showSnackBar(failureSnackBar(what, failure));

SnackBar failureSnackBar(String what, MatrixFailure failure) => SnackBar(
  content: Text(
    '$what: ${failure.kind == FailureKind.invalidId ? 'invalid ID “${failure.message}”' : failure.kind.name}',
  ),
);
