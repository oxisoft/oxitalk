import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
import '../../matrix/api/matrix.dart';
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

/// The accounts down the left edge of a wide window: tap one to bring it to the front.
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
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            for (final (index, id) in ids.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Tooltip(
                  message: '$id  ${_shortcut(index)}'.trim(),
                  child: InkWell(
                    key: Key('account.$id'),
                    customBorder: const CircleBorder(),
                    onTap: () =>
                        ref.read(accountsProvider.notifier).activate(id),
                    child: Row(
                      children: [
                        // Marks the account in front, as Slack and Discord do.
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 4,
                          height: id == active ? 36 : 0,
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
    );
  }
}

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
      child: InitialsAvatar(name: account, seed: account, radius: radius),
    );
  }
}

/// The active account's avatar in the chat list header, where there is no rail; opens the
/// account list. A dot shows unread messages in the other accounts.
class AccountSwitcherButton extends ConsumerWidget {
  const AccountSwitcherButton({required this.account, super.key});

  final String account;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final othersUnread = _accountIds(ref)
        .where((id) => id != account)
        .any((id) => ref.watch(unreadCountProvider(id)) > 0);
    return IconButton(
      key: const Key('account.switcher'),
      tooltip: 'Accounts',
      onPressed: () => unawaited(
        showModalBottomSheet<void>(
          context: context,
          builder: (_) => const _AccountSheet(),
        ),
      ),
      icon: Badge(
        isLabelVisible: othersUnread,
        smallSize: 10,
        backgroundColor: OxiColors.accent,
        child: InitialsAvatar(name: account, seed: account, radius: 16),
      ),
    );
  }
}

class _AccountSheet extends ConsumerWidget {
  const _AccountSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeAccountProvider);
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          for (final (index, id) in _accountIds(ref).indexed)
            ListTile(
              key: Key('accountSheet.$id'),
              leading: AccountAvatar(account: id, radius: 20),
              title: Text(id, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(_shortcut(index)),
              trailing: id == active
                  ? const Icon(Icons.check_rounded, color: OxiColors.accent)
                  : null,
              onTap: () {
                Navigator.of(context).pop();
                ref.read(accountsProvider.notifier).activate(id);
              },
            ),
          ListTile(
            leading: const CircleAvatar(child: Icon(Icons.add_rounded)),
            title: const Text('Add account'),
            onTap: () {
              Navigator.of(context).pop();
              context.go(Routes.addAccount);
            },
          ),
        ],
      ),
    );
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
