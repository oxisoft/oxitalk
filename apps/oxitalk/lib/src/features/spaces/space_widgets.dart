import 'dart:async';

// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
import '../../matrix/api/matrix.dart';
import '../../ui/avatar.dart';
import '../../ui/touch.dart';
import '../chats/badges.dart';
import 'space_state.dart';

/// "All chats" where a space's picture would be: a stack, in the avatar shape.
class AllChatsAvatar extends StatelessWidget {
  const AllChatsAvatar({this.radius = 20, this.dark = false, super.key});

  final double radius;

  /// On the always-dark account rail.
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: radius * 2,
      height: radius * 2,
      alignment: Alignment.center,
      decoration: ShapeDecoration(
        color: dark ? OxiColors.railAddOutline : scheme.secondaryContainer,
        shape: avatarShape(radius),
      ),
      child: Icon(
        Icons.layers_rounded,
        size: radius * 1.1,
        color: dark ? OxiColors.titleBarText : scheme.onSecondaryContainer,
      ),
    );
  }
}

/// A space's picture: its avatar, else its initials, corners cut as every avatar.
class SpaceAvatar extends StatelessWidget {
  const SpaceAvatar({
    required this.account,
    required this.space,
    this.radius = 20,
    super.key,
  });

  final String account;
  final Space space;
  final double radius;

  @override
  Widget build(BuildContext context) => MatrixAvatar(
    account: account,
    url: space.avatarUrl,
    name: space.name,
    seed: space.id,
    radius: radius,
  );
}

/// [child] (a space's picture) with the space's badge, as the narrow list badges a chat: a
/// red count, or a yellow @ for a mention.
class SpaceBadge extends ConsumerWidget {
  const SpaceBadge({
    required this.account,
    required this.spaceId,
    required this.child,
    super.key,
  });

  final String account;
  final String spaceId;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final badge = ref.watch(spaceBadgeProvider(account, spaceId));
    return switch (badge.kind) {
      BadgeKind.mention || BadgeKind.notifying => Badge(
        key: Key('spaceBadge.${badge.kind.name}.$spaceId'),
        backgroundColor: badge.kind == BadgeKind.mention
            ? OxiBrand.yellow
            : OxiBrand.red,
        textColor: badge.kind == BadgeKind.mention
            ? OxiBrand.ink
            : Colors.white,
        label: Text(
          badge.kind == BadgeKind.mention
              ? '@'
              : badgeCount(badge.count, max: 99),
        ),
        child: child,
      ),
      _ => child,
    };
  }
}

/// What a screen reader says for a space: `Space Acme, 3 unread`.
String spaceSemantics(Space space, RoomBadge badge) =>
    'Space ${space.name}, ${badge.count} unread';

/// The spaces part of the account rail, under Add account: a line, All chats, then the
/// active account's top-level spaces, the selected one marked as the active account is.
/// Nothing for an account without spaces.
class RailSpaces extends ConsumerWidget {
  const RailSpaces({required this.account, super.key});

  final String account;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spaces = ref.watch(spacesProvider(account)).value ?? const <Space>[];
    if (spaces.isEmpty) return const SizedBox.shrink();
    final current = ref.watch(currentSpaceProvider(account))?.id;
    return Column(
      key: const Key('rail.spaces'),
      children: [
        Container(
          key: const Key('rail.spaces.separator'),
          margin: const EdgeInsets.symmetric(vertical: 12),
          width: 44,
          height: 2,
          color: OxiColors.railAddOutline,
        ),
        _RailSpace(account: account, space: null, selected: current == null),
        for (final space in spaces)
          _RailSpace(
            account: account,
            space: space,
            selected: current == space.id,
          ),
      ],
    );
  }
}

class _RailSpace extends ConsumerWidget {
  const _RailSpace({
    required this.account,
    required this.space,
    required this.selected,
  });

  final String account;

  /// `null` for All chats.
  final Space? space;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final space = this.space;
    final badge = space == null
        ? const RoomBadge(BadgeKind.none)
        : ref.watch(spaceBadgeProvider(account, space.id));
    final picture = space == null
        ? const AllChatsAvatar(dark: true)
        : SpaceBadge(
            account: account,
            spaceId: space.id,
            child: SpaceAvatar(account: account, space: space),
          );
    void menu(Offset at) {
      if (space != null) {
        unawaited(showSpaceMenu(context, ref, account, space, at));
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Tooltip(
        message: space?.name ?? 'All chats',
        child: Semantics(
          label: space == null ? 'All chats' : spaceSemantics(space, badge),
          selected: selected,
          button: true,
          excludeSemantics: true,
          child: GestureDetector(
            onSecondaryTapUp: (details) => menu(details.globalPosition),
            onLongPressStart: (details) => menu(details.globalPosition),
            child: InkWell(
              key: Key('rail.space.${space?.id ?? 'all'}'),
              customBorder: OxiShapes.cut(6),
              hoverColor: Colors.white.withValues(alpha: 0.06),
              onTap: () => ref
                  .read(selectedSpaceProvider(account).notifier)
                  .select(space?.id),
              child: Row(
                children: [
                  // The same straight yellow bar as the account in front.
                  AnimatedContainer(
                    key: selected
                        ? Key('rail.space.selected.${space?.id ?? 'all'}')
                        : null,
                    duration: const Duration(milliseconds: 150),
                    width: 4,
                    height: selected ? 32 : 0,
                    color: OxiBrand.yellow,
                  ),
                  const SizedBox(width: 12),
                  picture,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Above the chat filter where the rail is hidden: which space the list shows (All chats or
/// a space), a tap to pick another. A red dot when chats outside it have unread messages.
/// Nothing for an account without spaces.
class SpaceSelectorRow extends ConsumerWidget {
  const SpaceSelectorRow({required this.account, super.key});

  final String account;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spaces = ref.watch(spacesProvider(account)).value ?? const <Space>[];
    if (spaces.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final current = ref.watch(currentSpaceProvider(account));
    final outside = ref.watch(unreadOutsideSpaceProvider(account));
    void menu(Offset at) {
      if (current != null) {
        unawaited(showSpaceMenu(context, ref, account, current, at));
      }
    }

    return Semantics(
      label:
          'Showing ${current?.name ?? 'all chats'}'
          '${outside ? ', unread chats elsewhere' : ''}. Pick a space',
      button: true,
      excludeSemantics: true,
      child: GestureDetector(
        onSecondaryTapUp: (details) => menu(details.globalPosition),
        onLongPressStart: (details) => menu(details.globalPosition),
        child: InkWell(
          key: const Key('spaces.selector'),
          onTap: () => unawaited(showSpacePicker(context, ref, account)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 6, 6),
            child: Row(
              children: [
                if (current == null)
                  const AllChatsAvatar(radius: 12)
                else
                  SpaceAvatar(account: account, space: current, radius: 12),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    current?.name ?? 'All chats',
                    key: const Key('spaces.selector.name'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (outside)
                  Container(
                    key: const Key('spaces.selector.dot'),
                    margin: const EdgeInsets.only(left: 8),
                    width: 9,
                    height: 9,
                    decoration: ShapeDecoration(
                      color: OxiBrand.red,
                      shape: OxiShapes.cut(3),
                    ),
                  ),
                Icon(
                  Icons.arrow_drop_down_rounded,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Lets the user pick All chats or a space: a menu under the selector on desktop, the
/// app's bottom sheet on a touch screen. A long-press on a space in the sheet opens its
/// menu.
Future<void> showSpacePicker(
  BuildContext context,
  WidgetRef ref,
  String account,
) async {
  final spaces = ref.read(spacesProvider(account)).value ?? const <Space>[];
  final current = ref.read(currentSpaceProvider(account))?.id;
  final selected = ref.read(selectedSpaceProvider(account).notifier);
  if (isTouchPlatform(context)) {
    final chosen = await showModalBottomSheet<VoidCallback>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheet) => _SpaceSheet(
        account: account,
        spaces: spaces,
        current: current,
        onSelect: (id) => Navigator.of(sheet).pop(() => selected.select(id)),
        onMenu: (space, at) => Navigator.of(
          sheet,
        ).pop(() => unawaited(showSpaceMenu(context, ref, account, space, at))),
      ),
    );
    chosen?.call();
    return;
  }
  final box = context.findRenderObject()! as RenderBox;
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final chosen = await showMenu<String>(
    context: context,
    position: RelativeRect.fromRect(
      box.localToGlobal(Offset(0, box.size.height), ancestor: overlay) &
          Size(box.size.width, 1),
      Offset.zero & overlay.size,
    ),
    constraints: BoxConstraints(minWidth: box.size.width, maxWidth: 360),
    items: [
      PopupMenuItem(
        key: const Key('spaceMenu.all'),
        value: '',
        child: _SpaceChoice(
          account: account,
          space: null,
          selected: current == null,
        ),
      ),
      const PopupMenuDivider(),
      for (final space in spaces)
        PopupMenuItem(
          key: Key('spaceMenu.${space.id}'),
          value: space.id,
          child: _SpaceChoice(
            account: account,
            space: space,
            selected: current == space.id,
          ),
        ),
    ],
  );
  if (chosen != null) selected.select(chosen.isEmpty ? null : chosen);
}

/// One choice of the space picker: picture, name, badge, and a check on the selected one.
class _SpaceChoice extends ConsumerWidget {
  const _SpaceChoice({
    required this.account,
    required this.space,
    required this.selected,
  });

  final String account;
  final Space? space;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final space = this.space;
    final badge = space == null
        ? const RoomBadge(BadgeKind.none)
        : ref.watch(spaceBadgeProvider(account, space.id));
    return Semantics(
      label: space == null ? 'All chats' : spaceSemantics(space, badge),
      selected: selected,
      excludeSemantics: true,
      child: Row(
        children: [
          if (space == null)
            const AllChatsAvatar(radius: 14)
          else
            SpaceAvatar(account: account, space: space, radius: 14),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              space?.name ?? 'All chats',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          BadgeTag(badge: badge),
          SizedBox(
            width: 32,
            child: selected
                ? Icon(
                    Icons.check_rounded,
                    key: Key('spaceChoice.check.${space?.id ?? 'all'}'),
                    color: Theme.of(context).colorScheme.primary,
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

class _SpaceSheet extends StatelessWidget {
  const _SpaceSheet({
    required this.account,
    required this.spaces,
    required this.current,
    required this.onSelect,
    required this.onMenu,
  });

  final String account;
  final List<Space> spaces;
  final String? current;
  final void Function(String? id) onSelect;
  final void Function(Space space, Offset at) onMenu;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: SingleChildScrollView(
      key: const Key('spaceSheet'),
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            key: const Key('spaceSheet.all'),
            shape: OxiShapes.small,
            title: _SpaceChoice(
              account: account,
              space: null,
              selected: current == null,
            ),
            onTap: () => onSelect(null),
          ),
          Divider(height: 9, color: context.oxi.line),
          for (final space in spaces)
            GestureDetector(
              onLongPressStart: (details) =>
                  onMenu(space, details.globalPosition),
              child: ListTile(
                key: Key('spaceSheet.${space.id}'),
                shape: OxiShapes.small,
                title: _SpaceChoice(
                  account: account,
                  space: space,
                  selected: current == space.id,
                ),
                onTap: () => onSelect(space.id),
              ),
            ),
        ],
      ),
    ),
  );
}

/// What can be done with a space: browse its rooms, copy its link, leave it. A menu where
/// the pointer is on desktop, the bottom sheet on a touch screen.
Future<void> showSpaceMenu(
  BuildContext context,
  WidgetRef ref,
  String account,
  Space space,
  Offset at,
) async {
  final danger = OxiButtons.danger(Theme.of(context).brightness);
  final actions = SpaceActions(context, ref, account);
  final entries = <(String, IconData, String, VoidCallback, bool)>[
    (
      'browse',
      Icons.travel_explore_rounded,
      'Browse rooms',
      () => unawaited(actions.browse(space)),
      false,
    ),
    (
      'copy',
      Icons.link_rounded,
      'Copy link',
      () => unawaited(actions.copyLink(space)),
      false,
    ),
    (
      'leave',
      Icons.logout_rounded,
      'Leave space…',
      () => unawaited(actions.leave(space)),
      true,
    ),
  ];
  if (isTouchPlatform(context)) {
    final chosen = await showModalBottomSheet<VoidCallback>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        top: false,
        child: Column(
          key: const Key('spaceContextSheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  SpaceAvatar(account: account, space: space, radius: 14),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      space.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
            for (final (id, icon, label, run, destructive) in entries)
              ListTile(
                key: Key('spaceContext.$id'),
                shape: OxiShapes.small,
                leading: Icon(icon, color: destructive ? danger : null),
                title: Text(
                  label,
                  style: TextStyle(
                    color: destructive ? danger : null,
                    fontWeight: destructive ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
                onTap: () => Navigator.of(sheet).pop(run),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    chosen?.call();
    return;
  }
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final chosen = await showMenu<VoidCallback>(
    context: context,
    position: RelativeRect.fromRect(
      at & const Size(1, 1),
      Offset.zero & overlay.size,
    ),
    items: [
      PopupMenuItem(enabled: false, child: Text(space.name)),
      for (final (id, _, label, run, destructive) in entries) ...[
        if (destructive) const PopupMenuDivider(),
        PopupMenuItem(
          key: Key('spaceContext.$id'),
          value: run,
          child: Text(
            label,
            style: destructive ? TextStyle(color: danger) : null,
          ),
        ),
      ],
    ],
  );
  chosen?.call();
}

/// Browsing, linking and leaving a space, for one account; failures show as a snack bar.
final class SpaceActions {
  SpaceActions(this._context, this._ref, this._account);

  final BuildContext _context;
  final WidgetRef _ref;
  final String _account;

  MatrixSession? get _session =>
      _ref.read(accountsProvider).value?.byId(_account);

  /// The space's rooms in a dialog, to join the ones the user isn't in.
  Future<void> browse(Space space) async {
    final session = _session;
    if (session == null || !_context.mounted) return;
    final open = await showDialog<String>(
      context: _context,
      builder: (_) =>
          BrowseSpaceDialog(account: _account, space: space, session: session),
    );
    if (open != null && _context.mounted) _context.go(Routes.room(open));
  }

  Future<void> copyLink(Space space) async {
    final messenger = ScaffoldMessenger.maybeOf(_context);
    await Clipboard.setData(ClipboardData(text: space.link));
    messenger?.showSnackBar(const SnackBar(content: Text('Link copied')));
  }

  /// Asks which of the space's rooms to leave with it, then leaves. Returns whether it
  /// left.
  Future<bool> leave(Space space) async {
    final session = _session;
    if (session == null) return false;
    final messenger = ScaffoldMessenger.maybeOf(_context);
    List<SpaceLeaveRoom> rooms;
    try {
      rooms = await session.leaveSpacePreview(space.id);
    } on MatrixFailure {
      rooms = const [];
    }
    if (!_context.mounted) return false;
    final alsoLeave = await showDialog<List<String>>(
      context: _context,
      builder: (_) => LeaveSpaceDialog(name: space.name, rooms: rooms),
    );
    if (alsoLeave == null) return false;
    try {
      await session.leaveSpace(space.id, alsoLeave: alsoLeave);
    } on MatrixFailure catch (failure) {
      messenger?.showSnackBar(
        SnackBar(content: Text('Can’t leave: ${failure.kind.name}')),
      );
      return false;
    }
    final selected = _ref.read(selectedSpaceProvider(_account).notifier);
    if (_ref.read(selectedSpaceProvider(_account)) == space.id) {
      selected.select(null);
    }
    return true;
  }
}

/// Asks before leaving a space, with its rooms to leave too (none picked at first).
/// Pops with the rooms picked, or `null` when cancelled.
class LeaveSpaceDialog extends StatefulWidget {
  const LeaveSpaceDialog({required this.name, required this.rooms, super.key});

  final String name;
  final List<SpaceLeaveRoom> rooms;

  @override
  State<LeaveSpaceDialog> createState() => _LeaveSpaceDialogState();
}

class _LeaveSpaceDialogState extends State<LeaveSpaceDialog> {
  final _chosen = <String>{};

  @override
  Widget build(BuildContext context) {
    final rooms = widget.rooms;
    final muted = context.oxi.muted;
    return AlertDialog(
      key: const Key('leaveSpace.dialog'),
      title: Text('Leave “${widget.name}”?'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              rooms.isEmpty
                  ? 'It goes from your spaces. Your chats stay.'
                  : 'It goes from your spaces. Its rooms stay in your chats '
                        'unless you tick them here.',
            ),
            if (rooms.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Also leave',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  OutlinedButton(
                    key: const Key('leaveSpace.all'),
                    onPressed: () => setState(() {
                      if (_chosen.length == rooms.length) {
                        _chosen.clear();
                      } else {
                        _chosen.addAll(rooms.map((room) => room.id));
                      }
                    }),
                    child: Text(
                      _chosen.length == rooms.length ? 'None' : 'All',
                    ),
                  ),
                ],
              ),
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 320),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final room in rooms)
                        CheckboxListTile(
                          key: Key('leaveSpace.room.${room.id}'),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          value: _chosen.contains(room.id),
                          onChanged: (on) => setState(
                            () => on ?? false
                                ? _chosen.add(room.id)
                                : _chosen.remove(room.id),
                          ),
                          title: Text(
                            room.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: room.lastAdmin || room.isSpace
                              ? Text(
                                  [
                                    if (room.isSpace) 'Space',
                                    if (room.lastAdmin) 'You’re its only admin',
                                  ].join(' · '),
                                  key: room.lastAdmin
                                      ? Key('leaveSpace.lastAdmin.${room.id}')
                                      : null,
                                  style: TextStyle(color: muted),
                                )
                              : null,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        OutlinedButton(
          key: const Key('leaveSpace.cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('leaveSpace.confirm'),
          style: OxiButtons.destructiveFilled(context),
          onPressed: () => Navigator.of(context).pop([
            for (final room in rooms)
              if (_chosen.contains(room.id)) room.id,
          ]),
          child: Text(
            _chosen.isEmpty ? 'Leave space' : 'Leave ${_chosen.length + 1}',
          ),
        ),
      ],
    );
  }
}

/// The rooms of a space, from the server: the joined ones marked (a tap opens one), Join on
/// the rest. Pops with a room to open, if one was tapped.
class BrowseSpaceDialog extends StatefulWidget {
  const BrowseSpaceDialog({
    required this.account,
    required this.space,
    required this.session,
    super.key,
  });

  final String account;
  final Space space;
  final MatrixSession session;

  @override
  State<BrowseSpaceDialog> createState() => _BrowseSpaceDialogState();
}

class _BrowseSpaceDialogState extends State<BrowseSpaceDialog> {
  List<SpaceChild>? _children;
  MatrixFailure? _failure;
  final _joined = <String>{};
  final _joining = <String>{};

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final children = await widget.session.spaceChildren(widget.space.id);
      if (mounted) setState(() => _children = children);
    } on MatrixFailure catch (failure) {
      if (mounted) setState(() => _failure = failure);
    }
  }

  Future<void> _join(SpaceChild child) async {
    setState(() => _joining.add(child.id));
    try {
      await widget.session.joinByAddress(child.joinAddress);
      if (mounted) setState(() => _joined.add(child.id));
    } on MatrixFailure catch (failure) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text('Can’t join: ${failure.kind.name}')),
        );
      }
    } finally {
      if (mounted) setState(() => _joining.remove(child.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = context.oxi.muted;
    final children = _children;
    final Widget body;
    if (_failure case final failure?) {
      body = Text('Can’t load the rooms: ${failure.kind.name}');
    } else if (children == null) {
      body = const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
      );
    } else if (children.isEmpty) {
      body = Text(
        'No rooms in this space yet.',
        key: const Key('browse.empty'),
        style: TextStyle(color: muted),
      );
    } else {
      body = ListView(
        shrinkWrap: true,
        children: [
          for (final child in children)
            _childTile(context, theme, child, muted),
        ],
      );
    }
    return AlertDialog(
      key: const Key('browse.dialog'),
      title: Text('Rooms in ${widget.space.name}'),
      content: SizedBox(
        width: 460,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 440),
          child: body,
        ),
      ),
      actions: [
        OutlinedButton(
          key: const Key('browse.close'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _childTile(
    BuildContext context,
    ThemeData theme,
    SpaceChild child,
    Color muted,
  ) {
    final joined = child.joined || _joined.contains(child.id);
    final details = [
      if (child.isSpace) 'Space',
      if (child.joinedMembers > 0)
        '${child.joinedMembers} member${child.joinedMembers == 1 ? '' : 's'}',
      ?child.topic,
    ].join(' · ');
    return ListTile(
      key: Key('browse.child.${child.id}'),
      contentPadding: EdgeInsets.zero,
      leading: MatrixAvatar(
        account: widget.account,
        url: child.avatarUrl,
        name: child.name,
        seed: child.id,
        radius: 18,
      ),
      title: Text(child.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: details.isEmpty
          ? null
          : Text(
              details,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: muted),
            ),
      trailing: joined
          ? Row(
              key: Key('browse.joined.${child.id}'),
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_rounded, size: 18, color: muted),
                const SizedBox(width: 4),
                Text('Joined', style: TextStyle(color: muted)),
              ],
            )
          : _joining.contains(child.id)
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : OutlinedButton(
              key: Key('browse.join.${child.id}'),
              onPressed: () => unawaited(_join(child)),
              child: const Text('Join'),
            ),
      // A joined room opens; a space has no chat to open.
      onTap: joined && !child.isSpace
          ? () => Navigator.of(context).pop(child.id)
          : null,
    );
  }
}

/// At the end of a space's chat list: its rooms to browse, so a space just joined doesn't
/// look empty. On the narrow list, an icon.
class BrowseSpaceRow extends ConsumerWidget {
  const BrowseSpaceRow({
    required this.account,
    required this.space,
    this.narrow = false,
    super.key,
  });

  final String account;
  final Space space;
  final bool narrow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final muted = context.oxi.muted;
    void browse() =>
        unawaited(SpaceActions(context, ref, account).browse(space));
    if (narrow) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: IconButton(
          key: const Key('spaces.browse'),
          tooltip: 'Browse rooms in ${space.name}',
          color: muted,
          onPressed: browse,
          icon: const Icon(Icons.travel_explore_rounded),
        ),
      );
    }
    return ListTile(
      key: const Key('spaces.browse'),
      leading: SizedBox(
        width: 48,
        child: Icon(Icons.travel_explore_rounded, color: muted),
      ),
      title: Text(
        'Browse rooms in ${space.name}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: muted, fontWeight: FontWeight.w600),
      ),
      onTap: browse,
    );
  }
}
