import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../matrix/api/matrix.dart';
import '../../ui/avatar.dart';
import '../../ui/format.dart';
import '../verify/verify_screen.dart';
import 'settings_heading.dart';

/// The devices [account] is signed in on, in Settings › Account: this one first, then the
/// others, the last seen first; each with its name, ID, when and where it was last seen and
/// whether it is verified, and renaming, verifying and signing it out. Follows the changes
/// made here and on the other devices.
class AccountDevicesSettings extends ConsumerWidget {
  const AccountDevicesSettings({required this.account, super.key});

  final String account;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(accountDevicesProvider(account));
    final list = devices.value;
    final others = [
      for (final device in list ?? const <Device>[])
        if (!device.isThisDevice) device,
    ];
    final thisVerified =
        list?.any((device) => device.isThisDevice && device.verified) ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SettingsHeading(
          'Devices',
          subtitle: 'Where this account is signed in.',
        ),
        switch (devices) {
          AsyncValue(value: final list?) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final device in list)
                DeviceRow(
                  key: Key('devices.row.${device.id}'),
                  account: account,
                  device: device,
                  canVerify: thisVerified && !device.isThisDevice,
                ),
            ],
          ),
          AsyncValue(hasError: true) => ListTile(
            key: const Key('devices.error'),
            title: const Text('Can’t load the devices.'),
            trailing: OutlinedButton(
              key: const Key('devices.retry'),
              onPressed: () => ref.invalidate(accountDevicesProvider(account)),
              child: const Text('Retry'),
            ),
          ),
          _ => const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
        },
        if (others.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton.icon(
                key: const Key('devices.signOutOthers'),
                style: OxiButtons.destructive(context),
                icon: const Icon(Icons.logout_rounded),
                onPressed: () => unawaited(
                  signOutDevices(context, ref, account, others, all: true),
                ),
                label: const Text('Sign out of all other devices'),
              ),
            ),
          ),
      ],
    );
  }
}

enum _DeviceAction { rename, verify, signOut }

/// One device of the account: its name (or ID), ID, last seen, a verified badge, and a
/// menu of what can be done with it.
class DeviceRow extends ConsumerWidget {
  const DeviceRow({
    required this.account,
    required this.device,
    required this.canVerify,
    super.key,
  });

  final String account;
  final Device device;

  /// Whether to offer verifying it: another device, verified here only once this one is.
  final bool canVerify;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final palette = context.oxi;
    final muted = theme.textTheme.bodyMedium?.copyWith(color: palette.muted);
    final seen = [
      if (device.lastSeen case final time?)
        'Last seen ${lastSeenLabel(time, now: clock.now())}',
      ?device.lastSeenIp,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconAvatar(
            icon: device.isThisDevice
                ? Icons.important_devices_rounded
                : Icons.devices_rounded,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: device.label,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (device.isThisDevice)
                        TextSpan(
                          text: '  ·  This device',
                          style: TextStyle(color: palette.muted),
                        ),
                    ],
                  ),
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: 2),
                Text(device.id, style: muted),
                if (seen.isNotEmpty) Text(seen, style: muted),
                const SizedBox(height: 4),
                _VerifiedBadge(
                  key: Key('devices.badge.${device.id}'),
                  verified: device.verified,
                ),
              ],
            ),
          ),
          PopupMenuButton<_DeviceAction>(
            key: Key('devices.menu.${device.id}'),
            tooltip: 'Device actions',
            onSelected: (action) => unawaited(switch (action) {
              _DeviceAction.rename => _rename(context, ref),
              _DeviceAction.verify => _verify(context, ref),
              _DeviceAction.signOut => signOutDevices(context, ref, account, [
                device,
              ]),
            }),
            itemBuilder: (_) => [
              const PopupMenuItem(
                key: Key('devices.rename'),
                value: _DeviceAction.rename,
                child: Text('Rename'),
              ),
              if (canVerify && !device.verified)
                const PopupMenuItem(
                  key: Key('devices.verify'),
                  value: _DeviceAction.verify,
                  child: Text('Verify'),
                ),
              if (!device.isThisDevice)
                const PopupMenuItem(
                  key: Key('devices.signOut'),
                  value: _DeviceAction.signOut,
                  child: Text('Sign out'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _RenameDialog(current: device.name ?? ''),
    );
    final session = ref.read(accountsProvider).value?.byId(account);
    if (name == null ||
        name.isEmpty ||
        name == device.name ||
        session == null) {
      return;
    }
    try {
      await session.renameDevice(device.id, name);
      await ref.read(accountDevicesProvider(account).notifier).refresh();
    } on MatrixFailure catch (failure) {
      messenger.showSnackBar(
        SnackBar(content: Text('Can’t rename it: ${deviceError(failure)}')),
      );
    }
  }

  Future<void> _verify(BuildContext context, WidgetRef ref) async {
    final session = ref.read(accountsProvider).value?.byId(account);
    if (session == null) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => VerifyDeviceDialog(session: session, device: device),
    );
    await ref.read(accountDevicesProvider(account).notifier).refresh();
  }
}

class _VerifiedBadge extends StatelessWidget {
  const _VerifiedBadge({required this.verified, super.key});

  final bool verified;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = verified
        ? theme.colorScheme.primary
        : OxiButtons.danger(theme.brightness);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          verified ? Icons.verified_rounded : Icons.gpp_maybe_rounded,
          size: 16,
          color: color,
        ),
        const SizedBox(width: 4),
        Text(
          verified ? 'Verified' : 'Not verified',
          style: theme.textTheme.labelMedium?.copyWith(color: color),
        ),
      ],
    );
  }
}

/// What went wrong with a device, for the user.
String deviceError(MatrixFailure failure) => switch (failure.kind) {
  FailureKind.wrongPassword => 'That password isn’t right.',
  FailureKind.network => 'Can’t reach the server. Check your connection.',
  FailureKind.forbidden => 'The server refused it.',
  _ => failure.message.isEmpty ? failure.kind.name : failure.message,
};

/// Signs [devices] of [account] out after the user confirms, asking for the account's
/// password when the server wants it. [all] when they are all the other devices.
Future<void> signOutDevices(
  BuildContext context,
  WidgetRef ref,
  String account,
  List<Device> devices, {
  bool all = false,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final what = all
      ? (devices.length == 1
            ? 'your other device'
            : 'your ${devices.length} other devices')
      : devices.single.label;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(
        all ? 'Sign out of all other devices?' : 'Sign out of $what?',
      ),
      content: Text(
        'OxiTalk signs $what out of this account. To read your messages there '
        'again, you log in and verify again.',
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('devices.confirmSignOut'),
          style: OxiButtons.destructiveFilled(context),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Sign out'),
        ),
      ],
    ),
  );
  final session = ref.read(accountsProvider).value?.byId(account);
  if (confirmed != true || session == null) return;
  final ids = [for (final device in devices) device.id];
  try {
    await session.signOutDevices(ids);
  } on MatrixFailure catch (failure) {
    if (failure.kind != FailureKind.passwordNeeded) {
      messenger.showSnackBar(
        SnackBar(content: Text('Can’t sign out: ${deviceError(failure)}')),
      );
      return;
    }
    if (!context.mounted) return;
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => PasswordDialog(
        account: account,
        onPassword: (password) =>
            session.signOutDevices(ids, password: password),
      ),
    );
    if (done != true) return;
  }
  messenger.showSnackBar(SnackBar(content: Text('Signed out of $what')));
  await ref.read(accountDevicesProvider(account).notifier).refresh();
}

/// Asks the account's password to confirm an action, and runs [onPassword] with it; stays
/// open with a message when the password is wrong. Pops `true` once it succeeded.
class PasswordDialog extends StatefulWidget {
  const PasswordDialog({
    required this.account,
    required this.onPassword,
    super.key,
  });

  final String account;
  final Future<void> Function(String password) onPassword;

  @override
  State<PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<PasswordDialog> {
  final _password = TextEditingController();
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final password = _password.text;
    if (password.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onPassword(password);
      if (mounted) Navigator.of(context).pop(true);
    } on MatrixFailure catch (failure) {
      if (mounted) setState(() => _error = deviceError(failure));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    return AlertDialog(
      title: const Text('Confirm it’s you'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Enter the password of ${widget.account}.'),
          const SizedBox(height: 12),
          TextField(
            key: const Key('devices.password'),
            controller: _password,
            autofocus: true,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: 'Password',
              errorText: error,
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        OutlinedButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('devices.passwordSubmit'),
          onPressed: _busy ? null : _submit,
          child: const Text('Continue'),
        ),
      ],
    );
  }
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.current});

  final String current;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _name = TextEditingController(text: widget.current);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() => Navigator.of(context).pop(_name.text.trim());

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Rename device'),
    content: TextField(
      key: const Key('devices.name'),
      controller: _name,
      autofocus: true,
      decoration: const InputDecoration(
        labelText: 'Name',
        helperText: 'Other people in encrypted chats may see it.',
      ),
      onSubmitted: (_) => _save(),
    ),
    actions: [
      OutlinedButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const Key('devices.save'),
        onPressed: _save,
        child: const Text('Save'),
      ),
    ],
  );
}

/// Verifies another of the account's devices by emoji: asks it, then the same steps as
/// verifying this device ([VerificationFlow]).
class VerifyDeviceDialog extends StatefulWidget {
  const VerifyDeviceDialog({
    required this.session,
    required this.device,
    super.key,
  });

  final MatrixSession session;
  final Device device;

  @override
  State<VerifyDeviceDialog> createState() => _VerifyDeviceDialogState();
}

class _VerifyDeviceDialogState extends State<VerifyDeviceDialog> {
  late final Future<DeviceVerification> _verification = widget.session
      .verifyDevice(widget.device.id);

  @override
  void dispose() {
    _verification.then((verification) => verification.close()).ignore();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: FutureBuilder(
          future: _verification,
          builder: (context, snapshot) => switch (snapshot) {
            AsyncSnapshot(:final DeviceVerification data) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Verify ${widget.device.label}',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                Text(
                  widget.device.id,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                VerificationFlow(
                  verification: data,
                  waitingText:
                      'Open OxiTalk or Element on ${widget.device.label} and '
                      'accept the request.',
                  onFinished: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            AsyncSnapshot(:final MatrixFailure error) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Can’t verify this device: ${deviceError(error)}',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            ),
            AsyncSnapshot(hasError: true) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Can’t verify this device.'),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            ),
            _ => const Center(child: CircularProgressIndicator()),
          },
        ),
      ),
    ),
  );
}
