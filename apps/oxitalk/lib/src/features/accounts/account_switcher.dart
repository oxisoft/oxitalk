import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/account_pictures.dart';
import '../../app/providers.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
import '../../matrix/api/matrix.dart';
import '../../rust/api.dart';
import '../../ui/avatar.dart';

/// Ctrl on Linux and Windows, Cmd on Apple platforms.
bool get _isApple =>
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.iOS;

String _shortcut(int index) =>
    index < 9 ? '${_isApple ? '⌘' : 'Ctrl+'}${index + 1}' : '';

List<String> _accountIds(WidgetRef ref) => [
  for (final session
      in ref.watch(accountsProvider).value?.sessions ?? const <MatrixSession>[])
    session.userId,
];

/// The accounts down the left edge of a wide window: tap one to bring it to the front,
/// right-click it to log out. At the bottom: hiding the rail, Settings and About.
class AccountRail extends ConsumerWidget {
  const AccountRail({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ids = _accountIds(ref);
    final active = ref.watch(activeAccountProvider);
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: SizedBox(
        width: 72,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 12),
                children: [
                  for (final (index, id) in ids.indexed)
                    _RailAccount(id: id, index: index, active: id == active),
                  Center(
                    child: IconButton.filledTonal(
                      key: const Key('account.add'),
                      tooltip: 'Add account',
                      onPressed: () => context.go(Routes.addAccount),
                      icon: const Icon(Icons.add_rounded),
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              key: const Key('rail.hide'),
              tooltip: 'Hide accounts',
              onPressed: () => ref.read(railHiddenProvider.notifier).toggle(),
              icon: const Icon(Icons.keyboard_double_arrow_left_rounded),
            ),
            IconButton(
              key: const Key('rail.settings'),
              tooltip: 'Settings',
              onPressed: () => context.go(Routes.settings),
              icon: const Icon(Icons.settings_outlined),
            ),
            IconButton(
              key: const Key('rail.about'),
              tooltip: 'About',
              onPressed: () => showOxiTalkAbout(context),
              icon: const Icon(Icons.info_outline_rounded),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _RailAccount extends ConsumerWidget {
  const _RailAccount({
    required this.id,
    required this.index,
    required this.active,
  });

  final String id;
  final int index;
  final bool active;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Tooltip(
      message: '$id  ${_shortcut(index)}'.trim(),
      child: GestureDetector(
        onSecondaryTapUp: (details) =>
            unawaited(_menu(context, ref, details.globalPosition)),
        child: InkWell(
          key: Key('account.$id'),
          customBorder: const CircleBorder(),
          onTap: () => ref.read(accountsProvider.notifier).activate(id),
          child: Row(
            children: [
              // Marks the account in front, as Slack and Discord do.
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 4,
                height: active ? 36 : 0,
                decoration: const BoxDecoration(
                  color: OxiColors.accent,
                  borderRadius: BorderRadius.horizontal(
                    right: Radius.circular(4),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              AccountAvatar(account: id),
            ],
          ),
        ),
      ),
    ),
  );

  Future<void> _menu(BuildContext context, WidgetRef ref, Offset at) async {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final logOut = await showMenu<bool>(
      context: context,
      position: RelativeRect.fromRect(
        at & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(enabled: false, child: Text(id)),
        const PopupMenuItem(
          key: Key('railMenu.logout'),
          value: true,
          child: Text('Log out'),
        ),
      ],
    );
    if (logOut ?? false) {
      unawaited(ref.read(accountsProvider.notifier).logout(id));
    }
  }
}

void showOxiTalkAbout(BuildContext context) => showAboutDialog(
  context: context,
  applicationName: 'OxiTalk',
  applicationLegalese: 'Rust core ${coreVersion()}',
);

/// An account's avatar with its unread count, and a warning while it is unverified.
class AccountAvatar extends ConsumerWidget {
  const AccountAvatar({required this.account, this.radius = 22, super.key});

  final String account;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadCountProvider(account));
    final unverified =
        ref.watch(verificationStatusProvider(account)).value ==
        VerificationStatus.unverified;
    return Badge(
      isLabelVisible: unverified || unread > 0,
      backgroundColor: unverified
          ? Theme.of(context).colorScheme.error
          : OxiColors.accent,
      label: Text(
        unverified
            ? '!'
            : unread > 99
            ? '99+'
            : '$unread',
      ),
      child: AccountPicture(account: account, radius: radius),
    );
  }
}

/// How an account shows: the picture picked for it on this device, else the user's Matrix
/// avatar, with the website icon of its server in the corner.
class AccountPicture extends ConsumerWidget {
  const AccountPicture({required this.account, this.radius = 22, super.key});

  final String account;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider(account)).value;
    final local = ref.watch(localPictureProvider(account)).value;
    final fallback = InitialsAvatar(
      name: profile?.displayName ?? account,
      seed: account,
      radius: radius,
    );
    final server = serverOf(account);
    final icon = ref.watch(serverIconProvider(server)).value;
    final iconRadius = radius * 0.42;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (local != null)
          PictureAvatar(
            key: Key('localPicture.$account'),
            bytes: local,
            radius: radius,
            fallback: fallback,
          )
        else
          MatrixAvatar(
            account: account,
            url: profile?.avatarUrl,
            name: profile?.displayName ?? account,
            seed: account,
            radius: radius,
          ),
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            key: Key('serverIcon.$server'),
            padding: const EdgeInsets.all(1.5),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              shape: BoxShape.circle,
            ),
            child: icon != null
                ? PictureAvatar(
                    bytes: icon,
                    radius: iconRadius,
                    fallback: _ServerLetter(server: server, radius: iconRadius),
                  )
                : _ServerLetter(server: server, radius: iconRadius),
          ),
        ),
      ],
    );
  }
}

/// A server without a website icon: its first letter.
class _ServerLetter extends StatelessWidget {
  const _ServerLetter({required this.server, required this.radius});

  final String server;
  final double radius;

  @override
  Widget build(BuildContext context) => CircleAvatar(
    radius: radius,
    backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
    child: Text(
      server.isEmpty ? '?' : server[0].toUpperCase(),
      style: TextStyle(
        fontSize: radius * 1.1,
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.onSecondaryContainer,
      ),
    ),
  );
}

/// The account in front, in the chat list's header: its picture and name (and, while not
/// online, what the connection is doing). A click lists every account to switch to, adding
/// one, and logging out of this one; with [withAppItems] also Settings and About.
class AccountDropdown extends ConsumerWidget {
  const AccountDropdown({
    required this.account,
    this.compact = false,
    this.withAppItems = false,
    super.key,
  });

  final String account;

  /// Only the picture, for the narrow list.
  final bool compact;

  /// Settings and About, which are at the bottom of the rail while it shows.
  final bool withAppItems;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final name =
        ref.watch(profileProvider(account)).value?.displayName ?? account;
    final status =
        ref.watch(syncStatusProvider(account)).value ?? SyncStatus.connecting;
    final roomsLoaded = ref.watch(roomsProvider(account)).value != null;
    final state = switch (status) {
      SyncStatus.offline => 'Waiting for network…',
      SyncStatus.connecting => 'Connecting…',
      SyncStatus.online when !roomsLoaded => 'Updating…',
      SyncStatus.online => null,
    };
    final othersUnread = _accountIds(ref)
        .where((id) => id != account)
        .any((id) => ref.watch(unreadCountProvider(id)) > 0);
    return Tooltip(
      message: 'Accounts',
      child: InkWell(
        key: const Key('account.dropdown'),
        borderRadius: BorderRadius.circular(8),
        onTap: () => unawaited(_open(context, ref)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Badge(
                isLabelVisible: othersUnread,
                smallSize: 10,
                backgroundColor: OxiColors.accent,
                child: AccountPicture(account: account, radius: 16),
              ),
              if (!compact) ...[
                const SizedBox(width: 10),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                      if (state != null)
                        Text(
                          state,
                          key: const Key('account.status'),
                          style: theme.textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
              ],
              // The narrow list has no room for it; the picture alone opens the menu.
              if (!compact) const Icon(Icons.arrow_drop_down_rounded),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final box = context.findRenderObject()! as RenderBox;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final ids = _accountIds(ref);
    final notifier = ref.read(accountsProvider.notifier);
    final action = await showMenu<VoidCallback>(
      context: context,
      position: RelativeRect.fromRect(
        box.localToGlobal(Offset(0, box.size.height), ancestor: overlay) &
            const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        for (final (index, id) in ids.indexed)
          PopupMenuItem(
            key: Key('accountMenu.$id'),
            value: () => notifier.activate(id),
            child: Row(
              children: [
                AccountAvatar(account: id, radius: 16),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(id, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 12),
                Text(
                  _shortcut(index),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                SizedBox(
                  width: 28,
                  child: id == account
                      ? const Icon(Icons.check_rounded, color: OxiColors.accent)
                      : null,
                ),
              ],
            ),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(
          key: const Key('accountMenu.add'),
          value: () => context.go(Routes.addAccount),
          child: const ListTile(
            leading: Icon(Icons.add_rounded),
            title: Text('Add account'),
          ),
        ),
        if (withAppItems) ...[
          PopupMenuItem(
            key: const Key('accountMenu.settings'),
            value: () => context.go(Routes.settings),
            child: const ListTile(
              leading: Icon(Icons.settings_outlined),
              title: Text('Settings'),
            ),
          ),
          PopupMenuItem(
            key: const Key('accountMenu.about'),
            value: () => showOxiTalkAbout(context),
            child: const ListTile(
              leading: Icon(Icons.info_outline_rounded),
              title: Text('About'),
            ),
          ),
        ],
        const PopupMenuDivider(),
        PopupMenuItem(
          key: const Key('accountMenu.logout'),
          value: () => unawaited(notifier.logout(account)),
          child: const ListTile(
            leading: Icon(Icons.logout_rounded),
            title: Text('Log out of this account'),
          ),
        ),
      ],
    );
    action?.call();
  }
}

/// Ctrl+1…9 (Cmd on Apple platforms) brings account 1–9 to the front, Ctrl+Shift+↑/↓ the
/// previous or next one. Handled before the focused widget, so it works while typing too.
class AccountHotkeys extends ConsumerStatefulWidget {
  const AccountHotkeys({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<AccountHotkeys> createState() => _AccountHotkeysState();
}

class _AccountHotkeysState extends ConsumerState<AccountHotkeys> {
  static const _digits = [
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6,
    LogicalKeyboardKey.digit7,
    LogicalKeyboardKey.digit8,
    LogicalKeyboardKey.digit9,
  ];

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final keyboard = HardwareKeyboard.instance;
    final modifier = _isApple
        ? keyboard.isMetaPressed
        : keyboard.isControlPressed;
    if (!modifier || keyboard.isAltPressed) return false;
    final accounts = ref.read(accountsProvider).value;
    if (accounts == null || accounts.sessions.isEmpty) return false;
    final ids = [for (final session in accounts.sessions) session.userId];
    final notifier = ref.read(accountsProvider.notifier);

    final digit = _digits.indexOf(event.logicalKey);
    if (digit >= 0 && !keyboard.isShiftPressed) {
      if (digit < ids.length) notifier.activate(ids[digit]);
      return true;
    }
    final step = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowUp => -1,
      LogicalKeyboardKey.arrowDown => 1,
      _ => 0,
    };
    if (step != 0 && keyboard.isShiftPressed) {
      final current = ids.indexOf(accounts.activeId ?? '');
      notifier.activate(ids[(current + step) % ids.length]);
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
