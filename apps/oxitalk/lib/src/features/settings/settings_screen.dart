import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/pick_image.dart';
import '../../app/providers.dart';
import '../../app/router.dart';
import '../../matrix/api/matrix.dart';
import '../../ui/avatar.dart';
import '../accounts/account_switcher.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final diagnostics = ref.watch(diagnosticsProvider);
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.go(Routes.chats)),
        title: const Text('Settings'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            children: [
              if (ref.watch(activeAccountProvider) case final account?)
                _AccountPictures(account: account),
              const _SectionTitle('Diagnostics'),
              SwitchListTile(
                key: const Key('settings.collectLogs'),
                title: const Text('Collect logs'),
                subtitle: const Text(
                  'Saves technical logs on this device to help find problems. '
                  'They hold account and device IDs, never message contents '
                  'or keys, and are kept for a week.',
                ),
                value: diagnostics.collectLogs,
                onChanged: (on) async {
                  await diagnostics.setCollectLogs(on: on);
                  if (mounted) setState(() {});
                },
              ),
              ListTile(
                title: const Text('Logs folder'),
                subtitle: SelectableText(diagnostics.logDir),
                trailing: IconButton(
                  tooltip: 'Copy path',
                  icon: const Icon(Icons.copy_rounded),
                  onPressed: () {
                    unawaited(
                      Clipboard.setData(
                        ClipboardData(text: diagnostics.logDir),
                      ),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Path copied')),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

/// The account's profile picture, which everyone sees, and the picture that marks it on this
/// device only.
class _AccountPictures extends ConsumerStatefulWidget {
  const _AccountPictures({required this.account});

  final String account;

  @override
  ConsumerState<_AccountPictures> createState() => _AccountPicturesState();
}

class _AccountPicturesState extends ConsumerState<_AccountPictures> {
  var _busy = false;

  String get _account => widget.account;

  MatrixSession? get _session =>
      ref.read(accountsProvider).value?.byId(_account);

  /// Runs [change], showing a failure instead of throwing it.
  Future<void> _run(Future<void> Function() change) async {
    setState(() => _busy = true);
    try {
      await change();
    } on MatrixFailure catch (failure) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Can’t change the picture: ${failure.kind.name}'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<PickedImage?> _pick() => ref.read(pickImageProvider)();

  Future<void> _setProfilePicture() async {
    final image = await _pick();
    final session = _session;
    if (image == null || session == null) return;
    await _run(() => session.setAvatar(image.bytes, image.mimeType));
  }

  Future<void> _removeProfilePicture() async {
    final session = _session;
    if (session == null) return;
    await _run(session.removeAvatar);
  }

  Future<void> _setLocalPicture() async {
    final image = await _pick();
    if (image == null) return;
    await _run(() async {
      await ref.read(accountPicturesProvider).setLocal(_account, image.bytes);
      ref.invalidate(localPictureProvider(_account));
    });
  }

  Future<void> _resetLocalPicture() => _run(() async {
    await ref.read(accountPicturesProvider).clearLocal(_account);
    ref.invalidate(localPictureProvider(_account));
  });

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider(_account)).value;
    final local = ref.watch(localPictureProvider(_account)).value;
    final name = profile?.displayName ?? _account;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionTitle('Account'),
        ListTile(
          leading: AccountPicture(account: _account, radius: 28),
          title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(_account),
        ),
        ListTile(
          leading: MatrixAvatar(
            account: _account,
            url: profile?.avatarUrl,
            name: name,
            seed: _account,
            radius: 20,
          ),
          title: const Text('Profile picture'),
          subtitle: const Text('Everyone you chat with sees it.'),
          trailing: Wrap(
            spacing: 4,
            children: [
              TextButton(
                key: const Key('settings.setAvatar'),
                onPressed: _busy ? null : _setProfilePicture,
                child: const Text('Change'),
              ),
              if (profile?.avatarUrl != null)
                TextButton(
                  key: const Key('settings.removeAvatar'),
                  onPressed: _busy ? null : _removeProfilePicture,
                  child: const Text('Remove'),
                ),
            ],
          ),
        ),
        ListTile(
          leading: local == null
              ? const CircleAvatar(
                  radius: 20,
                  child: Icon(Icons.devices_rounded),
                )
              : PictureAvatar(
                  bytes: local,
                  radius: 20,
                  fallback: const CircleAvatar(radius: 20),
                ),
          title: const Text('Picture on this device'),
          subtitle: const Text(
            'Marks this account in OxiTalk on this device only, instead of '
            'the profile picture. Nobody else sees it.',
          ),
          trailing: Wrap(
            spacing: 4,
            children: [
              TextButton(
                key: const Key('settings.setLocalPicture'),
                onPressed: _busy ? null : _setLocalPicture,
                child: const Text('Choose'),
              ),
              if (local != null)
                TextButton(
                  key: const Key('settings.resetLocalPicture'),
                  onPressed: _busy ? null : _resetLocalPicture,
                  child: const Text('Reset'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
