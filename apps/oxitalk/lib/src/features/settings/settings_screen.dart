import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/media_prefs.dart';
import '../../app/notification_service.dart';
import '../../app/pick_image.dart';
import '../../app/providers.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
import '../../matrix/api/matrix.dart';
import '../../ui/avatar.dart';
import '../../ui/format.dart';
import '../about/about_screen.dart';
import '../accounts/account_switcher.dart';
import 'notification_settings_screen.dart';

/// The categories of Settings, in the order of the menu; each has its own route under
/// [Routes.settings], named by its [slug].
enum SettingsSection {
  account('account', 'Account', Icons.person_outline_rounded),
  appearance('appearance', 'Appearance', Icons.palette_outlined),
  messages('messages', 'Messages', Icons.chat_bubble_outline_rounded),
  notifications('notifications', 'Notifications', Icons.notifications_outlined),
  media('media', 'Media & storage', Icons.perm_media_outlined),
  diagnostics('diagnostics', 'Diagnostics', Icons.bug_report_outlined);

  const SettingsSection(this.slug, this.title, this.icon);

  /// The last part of its route.
  final String slug;
  final String title;
  final IconData icon;

  /// Account and Notifications are about the active account, so they need one.
  bool get needsAccount => this == account || this == notifications;

  /// The section named [slug] in a route, if any.
  static SettingsSection? bySlug(String? slug) {
    for (final section in values) {
      if (section.slug == slug) return section;
    }
    return null;
  }
}

/// The sections there are with [account] active (or none).
List<SettingsSection> settingsSections({required bool account}) => [
  for (final section in SettingsSection.values)
    if (account || !section.needsAccount) section,
];

/// Whether logs are collected, as Settings shows it: [Diagnostics] itself doesn't tell
/// when it changes.
final collectLogsProvider = NotifierProvider<CollectLogs, bool>(
  CollectLogs.new,
);

class CollectLogs extends Notifier<bool> {
  @override
  bool build() => ref.watch(diagnosticsProvider).collectLogs;

  Future<void> set({required bool on}) async {
    final diagnostics = ref.read(diagnosticsProvider);
    await diagnostics.setCollectLogs(on: on);
    state = diagnostics.collectLogs;
  }
}

/// Settings: on a wide window the menu of sections and, beside it, the [section] picked
/// (the first one at first); otherwise the menu alone, and each section a page of its own
/// ([SettingsSectionScreen]).
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({this.section, super.key});

  /// The section open beside the menu on a wide window; `null` for the first.
  final SettingsSection? section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sections = settingsSections(
      account: ref.watch(activeAccountProvider) != null,
    );
    void home() => context.go(
      homeLocation(ref.read(uiPrefsProvider), ref.read(activeAccountProvider)),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= wideLayoutBreakpoint;
        final menu = Scaffold(
          appBar: AppBar(
            leading: BackButton(onPressed: home),
            title: const Text('Settings'),
          ),
          body: SettingsMenu(
            sections: sections,
            selected: wide ? _open(sections) : null,
          ),
        );
        if (!wide) return menu;
        final open = _open(sections);
        return Row(
          children: [
            SizedBox(width: settingsMenuWidth, child: menu),
            const VerticalDivider(width: 1),
            Expanded(
              // Its own messenger: a snack bar shows in the pane it is about.
              child: ScaffoldMessenger(
                child: Scaffold(
                  appBar: AppBar(
                    automaticallyImplyLeading: false,
                    title: Text(open.title),
                  ),
                  body: SettingsSectionPane(key: ValueKey(open), section: open),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// The section shown beside the menu: the one asked for, if there is, else the first.
  SettingsSection _open(List<SettingsSection> sections) =>
      sections.contains(section) ? section! : sections.first;
}

/// The width of the settings menu on a wide window.
const settingsMenuWidth = 300.0;

/// One section of Settings as a page of its own, over the menu (narrow windows); Back and
/// the system's back return to the menu.
class SettingsSectionScreen extends StatelessWidget {
  const SettingsSectionScreen({required this.section, super.key});

  final SettingsSection section;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: BackButton(
        key: Key(
          section == SettingsSection.notifications
              ? 'notificationSettings.back'
              : 'settings.back',
        ),
        onPressed: () => context.go(Routes.settings),
      ),
      title: Text(section.title),
    ),
    body: SettingsSectionPane(section: section),
  );
}

/// The sections of Settings, each with its icon, its name and how it is set now; then
/// About. The [selected] one, if any, is marked as the open chat is in the chat list.
class SettingsMenu extends ConsumerWidget {
  const SettingsMenu({required this.sections, this.selected, super.key});

  final List<SettingsSection> sections;
  final SettingsSection? selected;

  String _summary(WidgetRef ref, SettingsSection section) => switch (section) {
    SettingsSection.account => ref.watch(activeAccountProvider) ?? '',
    SettingsSection.appearance => switch (ref.watch(appThemeProvider)) {
      ThemeMode.system => 'Automatic',
      ThemeMode.light => 'Light',
      ThemeMode.dark => 'Dark',
    },
    SettingsSection.messages => [
      if (ref.watch(useMarkdownProvider)) 'Markdown' else 'Plain text',
      if (ref.watch(sendTypingProvider)) 'typing shown' else 'typing hidden',
    ].join(', '),
    SettingsSection.notifications => switch (ref.watch(
      deviceNotificationsProvider,
    )) {
      DeviceNotificationPrefs(enabled: false) => 'Off on this device',
      DeviceNotificationPrefs(sound: true) => 'On, with sound',
      _ => 'On, silent',
    },
    SettingsSection.media => switch (ref.watch(mediaRetentionProvider)) {
      null => 'Media kept forever',
      final days => 'Media kept for ${retentionLabel(days)}',
    },
    SettingsSection.diagnostics =>
      ref.watch(collectLogsProvider) ? 'Logs on' : 'Logs off',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListView(
    padding: const EdgeInsets.symmetric(vertical: 8),
    children: [
      for (final section in sections)
        SettingsMenuTile(
          key: Key('settings.${section.slug}'),
          icon: section.icon,
          title: section.title,
          subtitle: _summary(ref, section),
          selected: section == selected,
          // A page of its own only where the menu is alone.
          chevron: selected == null,
          onTap: () => context.go(Routes.settingsSection(section)),
        ),
      const Divider(height: 17, indent: 16, endIndent: 16),
      SettingsMenuTile(
        key: const Key('settings.about'),
        icon: Icons.info_outline_rounded,
        title: 'About OxiTalk',
        subtitle: 'Version, licence and links',
        chevron: selected == null,
        onTap: () => showOxiTalkAbout(context),
      ),
    ],
  );
}

/// An entry of [SettingsMenu]: a muted icon, the name and a muted line under it; when
/// [selected], the open chat's background and a yellow bar at its left edge.
class SettingsMenuTile extends StatelessWidget {
  const SettingsMenuTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.selected = false,
    this.chevron = false,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool selected;

  /// A chevron at the end, for an entry that opens a page of its own.
  final bool chevron;

  @override
  Widget build(BuildContext context) {
    final palette = context.oxi;
    final tile = ListTile(
      selected: selected,
      selectedTileColor: palette.selectedRow,
      selectedColor: palette.text,
      leading: Icon(icon, color: selected ? palette.text : palette.muted),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: palette.muted),
      ),
      trailing: chevron
          ? Icon(Icons.chevron_right_rounded, color: palette.muted)
          : null,
      onTap: onTap,
    );
    if (!selected) return tile;
    // As the open chat in the chat list: a yellow bar at its left edge.
    return Container(
      foregroundDecoration: const BoxDecoration(
        border: Border(left: BorderSide(color: OxiBrand.yellow, width: 3)),
      ),
      child: tile,
    );
  }
}

/// The settings of [section], wherever they show: beside the menu or as a page.
class SettingsSectionPane extends ConsumerWidget {
  const SettingsSectionPane({required this.section, super.key});

  final SettingsSection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(activeAccountProvider);
    final Widget content = switch (section) {
      SettingsSection.notifications => switch (account) {
        final account? => NotificationSettingsPane(
          key: ValueKey(account),
          account: account,
        ),
        null => const SizedBox.shrink(),
      },
      SettingsSection.account => switch (account) {
        final account? => ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            _AccountPictures(key: ValueKey(account), account: account),
          ],
        ),
        null => const SizedBox.shrink(),
      },
      SettingsSection.appearance => const _AppearanceSettings(),
      SettingsSection.messages => const _MessageSettings(),
      SettingsSection.media => ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: const [_MediaSettings()],
      ),
      SettingsSection.diagnostics => const _DiagnosticsSettings(),
    };
    // Under the pane's title, at its start; lines stay readable on a wide window.
    return Align(
      alignment: AlignmentDirectional.topStart,
      child: ConstrainedBox(
        key: Key('settings.pane.${section.slug}'),
        constraints: const BoxConstraints(maxWidth: 720),
        child: content,
      ),
    );
  }
}

class _AppearanceSettings extends ConsumerWidget {
  const _AppearanceSettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListView(
    padding: const EdgeInsets.symmetric(vertical: 8),
    children: [
      ListTile(
        title: const Text('Theme'),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SegmentedButton<ThemeMode>(
                key: const Key('settings.theme'),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: ThemeMode.system,
                    icon: Icon(Icons.brightness_auto_rounded),
                    label: Text('Automatic'),
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    icon: Icon(Icons.light_mode_rounded),
                    label: Text('Light'),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    icon: Icon(Icons.dark_mode_rounded),
                    label: Text('Dark'),
                  ),
                ],
                selected: {ref.watch(appThemeProvider)},
                onSelectionChanged: (choice) =>
                    ref.read(appThemeProvider.notifier).set(choice.single),
              ),
              const SizedBox(height: 4),
              const Text('Automatic follows your system.'),
            ],
          ),
        ),
      ),
    ],
  );
}

class _MessageSettings extends ConsumerWidget {
  const _MessageSettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListView(
    padding: const EdgeInsets.symmetric(vertical: 8),
    children: [
      SwitchListTile(
        key: const Key('settings.markdown'),
        title: const Text('Use markdown'),
        subtitle: const Text(
          'Send **bold**, *italic*, `code`, lists, quotes and links '
          'formatted, as Element does. Off sends exactly what you '
          'typed.',
        ),
        value: ref.watch(useMarkdownProvider),
        onChanged: (on) => ref.read(useMarkdownProvider.notifier).set(on: on),
      ),
      SwitchListTile(
        key: const Key('settings.sendTyping'),
        title: const Text('Send typing notifications'),
        subtitle: const Text(
          'Others see when you are typing. Off keeps it to yourself; '
          'you still see theirs.',
        ),
        value: ref.watch(sendTypingProvider),
        onChanged: (on) => ref.read(sendTypingProvider.notifier).set(on: on),
      ),
      SwitchListTile(
        key: const Key('settings.replaceEmoticons'),
        title: const Text('Replace emoticons with emoji'),
        subtitle: const Text(
          'Typing :) ;) :D <3 and the like turns them into 🙂 😉 😃 ❤️. '
          'Ctrl+Z brings the text back.',
        ),
        value: ref.watch(replaceEmoticonsProvider),
        onChanged: (on) =>
            ref.read(replaceEmoticonsProvider.notifier).set(on: on),
      ),
    ],
  );
}

class _DiagnosticsSettings extends ConsumerWidget {
  const _DiagnosticsSettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logDir = ref.watch(diagnosticsProvider).logDir;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        SwitchListTile(
          key: const Key('settings.collectLogs'),
          title: const Text('Collect logs'),
          subtitle: const Text(
            'Saves technical logs on this device to help find problems. '
            'They hold account and device IDs, never message contents '
            'or keys, and are kept for a week.',
          ),
          value: ref.watch(collectLogsProvider),
          onChanged: (on) =>
              unawaited(ref.read(collectLogsProvider.notifier).set(on: on)),
        ),
        ListTile(
          title: const Text('Logs folder'),
          subtitle: SelectableText(logDir),
          trailing: IconButton(
            tooltip: 'Copy path',
            icon: const Icon(Icons.copy_rounded),
            onPressed: () {
              unawaited(Clipboard.setData(ClipboardData(text: logDir)));
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('Path copied')));
            },
          ),
        ),
      ],
    );
  }
}

/// The account's profile picture, which everyone sees, and the picture that marks it on this
/// device only.
class _AccountPictures extends ConsumerStatefulWidget {
  const _AccountPictures({required this.account, super.key});

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
              ? const IconAvatar(icon: Icons.devices_rounded)
              : PictureAvatar(
                  bytes: local,
                  radius: 20,
                  fallback: const IconAvatar(icon: null),
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

  @override
  Widget build(BuildContext context) {
    final days = ref.watch(mediaRetentionProvider);
    final size = _size;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
                DropdownMenuItem(
                  value: choice,
                  child: Text(retentionLabel(choice)),
                ),
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

/// How long [days] of keeping media is, as the settings name it.
String retentionLabel(int? days) => switch (days) {
  null => 'Forever',
  7 => '1 week',
  30 => '1 month',
  90 => '3 months',
  365 => '1 year',
  _ => '$days days',
};
