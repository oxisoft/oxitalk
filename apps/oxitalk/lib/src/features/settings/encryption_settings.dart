import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../matrix/api/matrix.dart';
import '../../ui/avatar.dart';
import '../verify/verify_screen.dart';
import 'recovery_key_screen.dart';
import 'settings_heading.dart';

/// Recovery and the key backup of [account], in Settings › Account: whether they are on,
/// and setting recovery up, changing its key, or entering it on this device.
class AccountEncryptionSettings extends ConsumerWidget {
  const AccountEncryptionSettings({required this.account, super.key});

  final String account;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status =
        ref.watch(encryptionStatusProvider(account)).value ??
        const EncryptionStatus();
    final (title, text) = switch (status.recovery) {
      RecoveryState.enabled => (
        'Recovery is on',
        'A new device can verify itself and read your encrypted messages '
            'with your recovery key.',
      ),
      RecoveryState.incomplete => (
        'Recovery is incomplete on this device',
        'Your account has recovery, but this device lacks its keys. Enter '
            'your recovery key to get them.',
      ),
      RecoveryState.disabled => (
        'Recovery is off',
        'Set it up so a new device can read your encrypted messages, even '
            'when you have no other device with you.',
      ),
      RecoveryState.unknown => ('Checking recovery…', ''),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SettingsHeading('Encryption'),
        _StatusRow(
          key: const Key('encryption.recovery'),
          icon: status.recovery == RecoveryState.enabled
              ? Icons.verified_user_rounded
              : Icons.key_rounded,
          title: title,
          text: text,
          actions: switch (status.recovery) {
            RecoveryState.disabled => [
              FilledButton(
                key: const Key('encryption.setUp'),
                onPressed: () => unawaited(
                  showRecoveryKeyScreen(
                    context,
                    account,
                    RecoveryKeyAction.setUp,
                  ),
                ),
                child: const Text('Set up recovery'),
              ),
            ],
            RecoveryState.enabled => [
              OutlinedButton(
                key: const Key('encryption.change'),
                onPressed: () => unawaited(_change(context)),
                child: const Text('Change recovery key'),
              ),
            ],
            RecoveryState.incomplete => [
              FilledButton(
                key: const Key('encryption.enterKey'),
                onPressed: () => unawaited(_enterKey(context, ref)),
                child: const Text('Enter recovery key'),
              ),
            ],
            RecoveryState.unknown => const [],
          },
        ),
        _StatusRow(
          key: const Key('encryption.backup'),
          icon: Icons.cloud_done_outlined,
          title: status.backupEnabled
              ? 'Key backup is on'
              : 'Key backup is off',
          text: status.backupEnabled
              ? 'This device backs the keys of your messages up to the '
                    'server, encrypted.'
              : 'This device doesn’t back the keys of your messages up.',
          actions: const [],
        ),
      ],
    );
  }

  Future<void> _change(BuildContext context) async {
    final change = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change the recovery key?'),
        content: const Text(
          'You get a new recovery key, and the old one stops working. Your '
          'devices stay as they are.',
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('encryption.confirmChange'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Change key'),
          ),
        ],
      ),
    );
    if (change != true || !context.mounted) return;
    await showRecoveryKeyScreen(context, account, RecoveryKeyAction.change);
  }

  Future<void> _enterKey(BuildContext context, WidgetRef ref) async {
    final session = ref.read(accountsProvider).value?.byId(account);
    if (session == null) return;
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: RecoveryKeyForm(
              session: session,
              onBack: () => Navigator.of(context).pop(),
              onRecovered: () => Navigator.of(context).pop(),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.icon,
    required this.title,
    required this.text,
    required this.actions,
    super.key,
  });

  final IconData icon;
  final String title;
  final String text;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconAvatar(icon: icon),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.bodyLarge),
                if (text.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    text,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: context.oxi.muted,
                    ),
                  ),
                ],
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8, children: actions),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Before logging [account] out: on its last device with recovery off, warns that the
/// encrypted history will be lost and offers to set recovery up first. `true` to go on.
Future<bool> confirmLogout(
  BuildContext context,
  WidgetRef ref,
  String account,
) async {
  final session = ref.read(accountsProvider).value?.byId(account);
  if (session == null) return true;
  // As the Encryption settings above show it.
  final status = ref.read(encryptionStatusProvider(account)).value;
  if (status?.recovery != RecoveryState.disabled) return true;
  bool last;
  try {
    last = await session.isLastDevice();
  } on MatrixFailure {
    // Unknown, e.g. offline: the warning is for the case we know of.
    last = false;
  }
  if (!last || !context.mounted) return true;
  final choice = await showDialog<_LogoutChoice>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('You’ll lose your encrypted messages'),
      content: Text(
        'This is the only device where $account is signed in, and recovery '
        'is off. After you log out, no device can read your encrypted '
        'history. Set up recovery first to keep it.',
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(_LogoutChoice.cancel),
          child: const Text('Cancel'),
        ),
        OutlinedButton(
          key: const Key('logout.anyway'),
          style: OxiButtons.destructive(context),
          onPressed: () => Navigator.of(context).pop(_LogoutChoice.logOut),
          child: const Text('Log out anyway'),
        ),
        FilledButton(
          key: const Key('logout.setUpRecovery'),
          onPressed: () => Navigator.of(context).pop(_LogoutChoice.setUp),
          child: const Text('Set up recovery'),
        ),
      ],
    ),
  );
  switch (choice) {
    case _LogoutChoice.logOut:
      return true;
    case _LogoutChoice.setUp:
      if (context.mounted) {
        await showRecoveryKeyScreen(context, account, RecoveryKeyAction.setUp);
      }
      return false;
    case _LogoutChoice.cancel || null:
      return false;
  }
}

enum _LogoutChoice { cancel, logOut, setUp }
