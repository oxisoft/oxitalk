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
import '../../ui/avatar.dart';
import '../about/about_screen.dart';

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
    // Always dark, in both themes: the brand's ink.
    return Material(
      color: context.oxi.rail,
      child: SizedBox(
        width: 72,
        child: IconTheme.merge(
          data: const IconThemeData(color: OxiColors.railIcon),
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  children: [
                    for (final (index, id) in ids.indexed)
                      _RailAccount(id: id, index: index, active: id == active),
                    const Center(child: _AddAccountButton()),
                  ],
                ),
              ),
              _railButton(
                const Key('rail.hide'),
                'Hide accounts',
                Icons.keyboard_double_arrow_left_rounded,
                () => ref.read(railHiddenProvider.notifier).toggle(),
              ),
              _railButton(
                const Key('rail.settings'),
                'Settings',
                Icons.settings_outlined,
                () => context.go(Routes.settings),
              ),
              _railButton(
                const Key('rail.about'),
                'About',
                Icons.info_outline_rounded,
                () => showOxiTalkAbout(context),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _railButton(
    Key key,
    String tooltip,
    IconData icon,
    VoidCallback onPressed,
  ) => IconButton(
    key: key,
    tooltip: tooltip,
    color: OxiColors.railIcon,
    hoverColor: Colors.white.withValues(alpha: 0.08),
    onPressed: onPressed,
    icon: Icon(icon),
  );
}

/// Adds an account: a dashed outline with cut corners around a grey +.
class _AddAccountButton extends StatelessWidget {
  const _AddAccountButton();

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Add account',
    child: Material(
      color: Colors.transparent,
      shape: OxiShapes.cut(6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const Key('account.add'),
        hoverColor: Colors.white.withValues(alpha: 0.08),
        onTap: () => context.go(Routes.addAccount),
        child: const CustomPaint(
          painter: _DashedCutOutline(color: OxiColors.railAddOutline),
          child: SizedBox.square(
            dimension: 44,
            child: Icon(
              Icons.add_rounded,
              color: OxiColors.titleBarMuted,
              semanticLabel: 'Add account',
            ),
          ),
        ),
      ),
    ),
  );
}

/// A dashed outline of a square with its top-left and bottom-right corners cut.
class _DashedCutOutline extends CustomPainter {
  const _DashedCutOutline({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const inset = 0.75;
    final outline = OxiShapes.cut(6)
        .getOuterPath((Offset.zero & size).deflate(inset));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    const dash = 4.0;
    const gap = 3.0;
    for (final metric in outline.computeMetrics()) {
      for (var at = 0.0; at < metric.length; at += dash + gap) {
        canvas.drawPath(metric.extractPath(at, at + dash), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedCutOutline oldDelegate) =>
      oldDelegate.color != color;
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
          customBorder: OxiShapes.cut(6),
          hoverColor: Colors.white.withValues(alpha: 0.06),
          onTap: () => ref.read(accountsProvider.notifier).activate(id),
          child: Row(
            children: [
              // Marks the account in front, as Slack and Discord do: a straight yellow bar.
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 4,
                height: active ? 36 : 0,
                color: OxiBrand.yellow,
              ),
              const SizedBox(width: 10),
              AccountAvatar(account: id, ring: context.oxi.rail),
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

/// An account's avatar with its unread count, and a warning while it is unverified.
class AccountAvatar extends ConsumerWidget {
  const AccountAvatar({
    required this.account,
    this.radius = 22,
    this.ring,
    super.key,
  });

  final String account;
  final double radius;

  /// Around the server's icon: what the avatar sits on.
  final Color? ring;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadCountProvider(account));
    final unverified =
        ref.watch(verificationStatusProvider(account)).value ==
        VerificationStatus.unverified;
    return Badge(
      isLabelVisible: unverified || unread > 0,
      backgroundColor: OxiBrand.red,
      textColor: Colors.white,
      label: Text(
        unverified
            ? '!'
            : unread > 99
            ? '99+'
            : '$unread',
      ),
      child: AccountPicture(account: account, radius: radius, ring: ring),
    );
  }
}

/// How an account shows: the picture picked for it on this device, else the user's Matrix
/// avatar, with the website icon of its server in the corner.
class AccountPicture extends ConsumerWidget {
  const AccountPicture({
    required this.account,
    this.radius = 22,
    this.ring,
    super.key,
  });

  final String account;
  final double radius;

  /// Around the server's icon: what the picture sits on; the surface if `null`.
  final Color? ring;

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
            decoration: ShapeDecoration(
              color: ring ?? Theme.of(context).colorScheme.surface,
              shape: avatarShape(iconRadius + 1.5),
            ),
            child: icon != null
                ? PictureAvatar(
                    bytes: icon,
                    radius: iconRadius,
                    fallback: _ServerLetter(
                      server: server,
                      radius: iconRadius,
                      dark: ring != null,
                    ),
                  )
                : _ServerLetter(
                    server: server,
                    radius: iconRadius,
                    dark: ring != null,
                  ),
          ),
        ),
      ],
    );
  }
}

/// A server without a website icon: its first letter.
class _ServerLetter extends StatelessWidget {
  const _ServerLetter({
    required this.server,
    required this.radius,
    this.dark = false,
  });

  final String server;
  final double radius;

  /// On the always-dark account rail.
  final bool dark;

  @override
  Widget build(BuildContext context) => Container(
    width: radius * 2,
    height: radius * 2,
    alignment: Alignment.center,
    decoration: ShapeDecoration(
      color: dark
          ? OxiColors.railAddOutline
          : Theme.of(context).colorScheme.secondaryContainer,
      shape: avatarShape(radius),
    ),
    child: Text(
      server.isEmpty ? '?' : server[0].toUpperCase(),
      style: TextStyle(
        fontSize: radius * 1.1,
        fontWeight: FontWeight.w700,
        color: dark
            ? OxiColors.titleBarText
            : Theme.of(context).colorScheme.onSecondaryContainer,
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
        customBorder: OxiShapes.small,
        onTap: () => unawaited(_open(context, ref)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Badge(
                isLabelVisible: othersUnread,
                smallSize: 10,
                backgroundColor: OxiBrand.red,
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
                      ? Icon(
                          Icons.check_rounded,
                          color: Theme.of(context).colorScheme.primary,
                        )
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
