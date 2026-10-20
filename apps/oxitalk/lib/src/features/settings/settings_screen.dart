import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/media_prefs.dart';
import '../../app/pick_image.dart';
import '../../app/providers.dart';
import '../../app/router.dart';
import '../../app/window_controls.dart';
import '../../matrix/api/matrix.dart';
import '../../ui/avatar.dart';
import '../../ui/format.dart';
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
        leading: BackButton(
          onPressed: () => context.go(
            homeLocation(
              ref.read(uiPrefsProvider),
              ref.read(activeAccountProvider),
            ),
          ),
        ),
        title: const Text('Settings'),
        flexibleSpace: const WindowDragArea(),
        actions: const [WindowButtons.right()],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            children: [
              if (ref.watch(activeAccountProvider) case final account?)
                _AccountPictures(account: account),
              const _SectionTitle('Messages'),
              SwitchListTile(
                key: const Key('settings.markdown'),
                title: const Text('Use markdown'),
                subtitle: const Text(
                  'Send **bold**, *italic*, `code`, lists, quotes and links '
                  'formatted, as Element does. Off sends exactly what you '
                  'typed.',
                ),
                value: ref.watch(useMarkdownProvider),
                onChanged: (on) =>
                    ref.read(useMarkdownProvider.notifier).set(on: on),
              ),
              SwitchListTile(
                key: const Key('settings.sendTyping'),
                title: const Text('Send typing notifications'),
                subtitle: const Text(
                  'Others see when you are typing. Off keeps it to yourself; '
                  'you still see theirs.',
                ),
                value: ref.watch(sendTypingProvider),
                onChanged: (on) =>
                    ref.read(sendTypingProvider.notifier).set(on: on),
              ),
              const _MediaSettings(),
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
          trailing: OutlinedButton.icon(
            key: const Key('settings.logout'),
            onPressed: () =>
                unawaited(ref.read(accountsProvider.notifier).logout(_account)),
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Log out'),
          ),
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

/// How long pictures and files are kept, and the cache's size, for all accounts.
class _MediaSettings extends ConsumerStatefulWidget {
  const _MediaSettings();

  @override
  ConsumerState<_MediaSettings> createState() => _MediaSettingsState();
}

class _MediaSettingsState extends ConsumerState<_MediaSettings> {
  /// The cache's size over all accounts; `null` while it is measured.
  int? _size;
  var _clearing = false;

  List<MatrixSession> get _sessions =>
      ref.read(accountsProvider).value?.sessions ?? const [];

  @override
  void initState() {
    super.initState();
    unawaited(_measure());
  }

  Future<void> _measure() async {
    var total = 0;
    for (final session in _sessions) {
      try {
        total += await session.mediaCacheSize() ?? 0;
      } on MatrixFailure {
        // That account's cache counts as empty.
      }
    }
    if (mounted) setState(() => _size = total);
  }

  Future<void> _clear() async {
    setState(() => _clearing = true);
    for (final session in _sessions) {
      try {
        await session.clearMediaCache();
      } on MatrixFailure {
        // What could be cleared is.
      }
    }
    if (!mounted) return;
    setState(() {
      _clearing = false;
      _size = null;
    });
    await _measure();
  }

  static String _label(int? days) => switch (days) {
    null => 'Forever',
    7 => '1 week',
    30 => '1 month',
    90 => '3 months',
    365 => '1 year',
    _ => '$days days',
  };

  @override
  Widget build(BuildContext context) {
    final days = ref.watch(mediaRetentionProvider);
    final size = _size;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionTitle('Media'),
        ListTile(
          title: const Text('Keep media for'),
          subtitle: const Text(
            'Pictures and files not opened for this long are removed from '
            'this device; they download again when needed.',
          ),
          trailing: DropdownButton<int?>(
            key: const Key('settings.retention'),
            value: days,
            onChanged: (days) =>
                unawaited(ref.read(mediaRetentionProvider.notifier).set(days)),
            items: [
              for (final choice in retentionChoices)
                DropdownMenuItem(value: choice, child: Text(_label(choice))),
            ],
          ),
        ),
        ListTile(
          title: const Text('Media on this device'),
          subtitle: Text(
            size == null ? 'Measuring…' : fileSize(size),
            key: const Key('settings.cacheSize'),
          ),
          trailing: TextButton(
            key: const Key('settings.clearCache'),
            onPressed: _clearing || size == 0 ? null : _clear,
            child: const Text('Clear'),
          ),
        ),
      ],
    );
  }
}
