import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/media_prefs.dart';
import '../../app/pick_image.dart';
import '../../app/providers.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
import '../../matrix/api/matrix.dart';
import '../../ui/avatar.dart';
import '../../ui/format.dart';
import '../about/about_screen.dart';
import '../accounts/account_switcher.dart';
import 'devices_settings.dart';
import 'encryption_settings.dart';
import 'ignored_users_settings.dart';
import 'notification_settings_screen.dart';
import 'server_settings.dart';
import 'settings_heading.dart';

/// The categories of Settings, in the order of the menu; each has its own route under
/// [Routes.settings], named by its [slug]. Notifications are in Account, by account, with
/// this device's own switches after them ([Routes.oldNotificationSettings] leads there).
enum SettingsSection {
  account('account', 'Account', Icons.person_outline_rounded),
  server('server', 'Server', Icons.dns_outlined),
  appearance('appearance', 'Appearance', Icons.palette_outlined),
  messages('messages', 'Messages', Icons.chat_bubble_outline_rounded),
  media('media', 'Media & storage', Icons.perm_media_outlined),
  diagnostics('diagnostics', 'Diagnostics', Icons.bug_report_outlined);

  const SettingsSection(this.slug, this.title, this.icon);

  /// The last part of its route.
  final String slug;
  final String title;
  final IconData icon;

  /// Account and Server are about an account, so they need one.
  bool get needsAccount => this == account || this == server;

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
  const SettingsScreen({
    this.section,
    this.user,
    this.showNotifications = false,
    super.key,
  });

  /// The section open beside the menu on a wide window; `null` for the first.
  final SettingsSection? section;

  /// The account the Account section is about (`?user=` in its link); the active one if
  /// `null` or not logged in.
  final String? user;

  /// Whether the Account section opens scrolled to its notifications (an old link to
  /// Settings › Notifications).
  final bool showNotifications;

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
                  body: SettingsSectionPane(
                    key: ValueKey(open),
                    section: open,
                    user: user,
                    showNotifications: showNotifications,
                  ),
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
  const SettingsSectionScreen({
    required this.section,
    this.user,
    this.showNotifications = false,
    super.key,
  });

  final SettingsSection section;

  /// As [SettingsScreen.user].
  final String? user;

  /// As [SettingsScreen.showNotifications].
  final bool showNotifications;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: BackButton(
        key: const Key('settings.back'),
        onPressed: () => context.go(Routes.settings),
      ),
      title: Text(section.title),
    ),
    body: SettingsSectionPane(
      section: section,
      user: user,
      showNotifications: showNotifications,
    ),
  );
}

/// The sections of Settings, each with its icon, its name and how it is set now; then
/// About. The [selected] one, if any, is marked as the open chat is in the chat list.
class SettingsMenu extends ConsumerWidget {
  const SettingsMenu({required this.sections, this.selected, super.key});

  final List<SettingsSection> sections;
  final SettingsSection? selected;

  String _summary(WidgetRef ref, SettingsSection section) => switch (section) {
    SettingsSection.account => switch (ref.watch(
      accountsProvider.select((accounts) => accounts.value?.sessions.length),
    )) {
      null || 0 => '',
      1 => ref.watch(activeAccountProvider) ?? '',
      final count => '$count accounts',
    },
    SettingsSection.server => switch (ref.watch(activeAccountProvider)) {
      final user? when user.contains(':') => user.substring(
        user.indexOf(':') + 1,
      ),
      _ => '',
    },
    SettingsSection.appearance => switch (ref.watch(appThemeProvider)) {
      ThemeMode.system => 'Automatic',
      ThemeMode.light => 'Light',
      ThemeMode.dark => 'Dark',
    },
    SettingsSection.messages => [
      if (ref.watch(useMarkdownProvider)) 'Markdown' else 'Plain text',
      if (ref.watch(sendTypingProvider)) 'typing shown' else 'typing hidden',
    ].join(', '),
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
  const SettingsSectionPane({
    required this.section,
    this.user,
    this.showNotifications = false,
    super.key,
  });

  final SettingsSection section;

  /// As [SettingsScreen.user].
  final String? user;

  /// As [SettingsScreen.showNotifications].
  final bool showNotifications;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Widget content = switch (section) {
      SettingsSection.account => switch (editedAccount(
        ref.watch(accountsProvider).value,
        user,
      )) {
        final edited? => _AccountSettings(
          account: edited,
          showNotifications: showNotifications,
        ),
        null => const SizedBox.shrink(),
      },
      SettingsSection.server => switch (editedAccount(
        ref.watch(accountsProvider).value,
        user,
      )) {
        final edited? => _ServerSettings(account: edited),
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

/// The account the Account section is about: [user] while it is logged in, else the
/// active one; `null` without accounts.
String? editedAccount(AccountsState? accounts, String? user) {
  if (accounts == null) return null;
  if (user != null && accounts.byId(user) != null) return user;
  return accounts.activeId;
}

/// Everything about one [account], top to bottom: which account (the picker), its
/// pictures, its notifications (kept on its server), its encryption and devices, ignored
/// users, then this device's notification switches, which are for all accounts, and logging out last.
class _AccountSettings extends ConsumerStatefulWidget {
  const _AccountSettings({
    required this.account,
    required this.showNotifications,
  });

  final String account;

  /// Scrolls to the notifications once they are laid out.
  final bool showNotifications;

  @override
  ConsumerState<_AccountSettings> createState() => _AccountSettingsState();
}

class _AccountSettingsState extends ConsumerState<_AccountSettings> {
  final _notifications = GlobalKey(debugLabel: 'settings.notifications');

  /// Whether the notifications are still to be scrolled to.
  late var _toReveal = widget.showNotifications;

  /// Scrolls to the notifications once they are laid out in full: before the server's
  /// settings come, the page may be too short to bring them to the top.
  void _revealWhenLoaded(bool loaded) {
    if (!_toReveal || !loaded) return;
    _toReveal = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final group = _notifications.currentContext;
      if (!mounted || group == null) return;
      unawaited(Scrollable.ensureVisible(group));
    });
  }

  @override
  Widget build(BuildContext context) {
    final account = widget.account;
    _revealWhenLoaded(
      ref.watch(notificationSettingsProvider(account)).value != null,
    );
    const divider = Divider(height: 33, indent: 16, endIndent: 16);
    // A scroll view, not a list: the notifications are built even when off screen, so a
    // link can scroll to them.
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SettingsHeading('Accounts'),
          SettingsAccountSwitcher(selected: account),
          divider,
          const SettingsHeading('Profile'),
          _AccountPictures(key: ValueKey(account), account: account),
          divider,
          KeyedSubtree(
            key: _notifications,
            child: AccountNotificationSettings(
              key: ValueKey(('notifications', account)),
              account: account,
            ),
          ),
          divider,
          AccountEncryptionSettings(
            key: ValueKey(('encryption', account)),
            account: account,
          ),
          divider,
          AccountDevicesSettings(
            key: ValueKey(('devices', account)),
            account: account,
          ),
          divider,
          IgnoredUsersSettings(
            key: ValueKey(('ignored', account)),
            account: account,
          ),
          divider,
          const DeviceNotificationSettings(),
          divider,
          _LogOut(key: ValueKey(('logout', account)), account: account),
        ],
      ),
    );
  }
}

/// The homeserver of one [account] (the picker first, as in Account): what it runs and
/// supports, then its voice and video calls.
class _ServerSettings extends StatelessWidget {
  const _ServerSettings({required this.account});

  final String account;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SettingsHeading('Accounts'),
        SettingsAccountSwitcher(
          selected: account,
          section: SettingsSection.server,
        ),
        const Divider(height: 33, indent: 16, endIndent: 16),
        AccountServerSettings(
          key: ValueKey(('server', account)),
          account: account,
        ),
      ],
    ),
  );
}

/// Which account the Account section is about, as a dropdown: the [selected] account's
/// picture, name and user ID; opened, every logged-in account (the selected one checked),
/// then adding one. Picking an account shows its settings below; it doesn't bring it to the
/// front. With one account it still opens, for Add account.
class SettingsAccountSwitcher extends ConsumerStatefulWidget {
  const SettingsAccountSwitcher({
    required this.selected,
    this.section = SettingsSection.account,
    super.key,
  });

  final String selected;

  /// The section picking an account opens it in.
  final SettingsSection section;

  /// The closed control's height, a field's.
  static const height = 56.0;

  @override
  ConsumerState<SettingsAccountSwitcher> createState() =>
      _SettingsAccountSwitcherState();
}

class _SettingsAccountSwitcherState
    extends ConsumerState<SettingsAccountSwitcher> {
  final _menu = MenuController();

  void _pick(String account) {
    if (account != widget.selected) {
      context.go(Routes.settingsSectionOf(widget.section, account));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ids = [
      for (final session
          in ref.watch(accountsProvider).value?.sessions ??
              const <MatrixSession>[])
        session.userId,
    ];
    final active = ref.watch(activeAccountProvider);
    final palette = context.oxi;
    bool inUse(String id) => id == active && ids.length > 1;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              return MenuAnchor(
                controller: _menu,
                alignmentOffset: const Offset(0, 4),
                style: MenuStyle(
                  minimumSize: WidgetStatePropertyAll(Size(width, 0)),
                  maximumSize: WidgetStatePropertyAll(
                    Size(width, double.infinity),
                  ),
                  padding: const WidgetStatePropertyAll(
                    EdgeInsets.symmetric(vertical: 6),
                  ),
                  backgroundColor: WidgetStatePropertyAll(palette.panel),
                  // Flat, outlined as the secondary buttons are.
                  elevation: const WidgetStatePropertyAll(0),
                  shape: WidgetStatePropertyAll(
                    OxiShapes.cut(
                      8,
                      side: BorderSide(color: OxiButtons.outline(palette)),
                    ),
                  ),
                ),
                menuChildren: [
                  for (final id in ids)
                    // As wide as the control: a menu is only as wide as its items.
                    SizedBox(
                      width: width,
                      child: _PickerAccount(
                        key: Key('settings.accounts.$id'),
                        account: id,
                        current: id == widget.selected,
                        inUse: inUse(id),
                        onPressed: () => _pick(id),
                      ),
                    ),
                  const Divider(height: 13),
                  MenuItemButton(
                    key: const Key('settings.accounts.add'),
                    style: _PickerAccount.itemStyle,
                    leadingIcon: SizedBox.square(
                      dimension: 36,
                      child: DecoratedBox(
                        decoration: ShapeDecoration(
                          shape: OxiShapes.cut(
                            6,
                            side: BorderSide(color: palette.muted, width: 1.5),
                          ),
                        ),
                        child: Icon(Icons.add_rounded, color: palette.muted),
                      ),
                    ),
                    onPressed: () => context.go(Routes.addAccount),
                    child: const Padding(
                      padding: EdgeInsetsDirectional.only(start: 4),
                      child: Text('Add account'),
                    ),
                  ),
                ],
                builder: (context, menu, _) => Material(
                  key: const Key('settings.accounts.picker'),
                  color: palette.panel2,
                  shape: OxiShapes.cut(
                    6,
                    side: BorderSide(color: palette.line),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => menu.isOpen ? menu.close() : menu.open(),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight: SettingsAccountSwitcher.height,
                      ),
                      child: Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(
                          10,
                          8,
                          8,
                          8,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: _AccountLine(
                                key: Key(
                                  'settings.accounts.picked.${widget.selected}',
                                ),
                                account: widget.selected,
                                inUse: inUse(widget.selected),
                                ring: palette.panel2,
                                inUseKey: Key(
                                  'settings.accounts.active.${widget.selected}',
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              menu.isOpen
                                  ? Icons.expand_less_rounded
                                  : Icons.expand_more_rounded,
                              color: palette.muted,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// An account in the [SettingsAccountSwitcher]'s menu; the [current] one is checked.
class _PickerAccount extends StatelessWidget {
  const _PickerAccount({
    required this.account,
    required this.current,
    required this.inUse,
    required this.onPressed,
    super.key,
  });

  final String account;
  final bool current;
  final bool inUse;
  final VoidCallback onPressed;

  static final itemStyle = ButtonStyle(
    minimumSize: const WidgetStatePropertyAll(
      Size(0, SettingsAccountSwitcher.height),
    ),
    padding: const WidgetStatePropertyAll(
      EdgeInsetsDirectional.fromSTEB(10, 6, 12, 6),
    ),
    shape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
  );

  @override
  Widget build(BuildContext context) {
    final palette = context.oxi;
    return MenuItemButton(
      style: itemStyle.copyWith(
        backgroundColor: WidgetStatePropertyAll(
          current ? palette.selectedRow : null,
        ),
      ),
      trailingIcon: current
          ? Icon(
              Icons.check_rounded,
              key: Key('settings.accounts.current.$account'),
              size: 20,
              color: Theme.of(context).colorScheme.primary,
            )
          : const SizedBox(width: 20),
      onPressed: onPressed,
      child: _AccountLine(
        account: account,
        inUse: inUse,
        ring: current ? palette.selectedRow : palette.panel,
      ),
    );
  }
}

/// An account as the [SettingsAccountSwitcher] shows it: its picture, name and user ID, and
/// whether it is the one in front or not verified yet.
class _AccountLine extends ConsumerWidget {
  const _AccountLine({
    required this.account,
    required this.inUse,
    required this.ring,
    this.inUseKey,
    super.key,
  });

  final String account;

  /// What the line sits on, around the avatar's server icon.
  final Color ring;

  /// In front in the app (only told with several accounts).
  final bool inUse;
  final Key? inUseKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.oxi;
    final theme = Theme.of(context);
    final name = ref.watch(profileProvider(account)).value?.displayName;
    final unverified =
        ref.watch(verificationStatusProvider(account)).value ==
        VerificationStatus.unverified;
    return Row(
      children: [
        AccountAvatar(account: account, radius: 18, ring: ring),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name ?? account,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: palette.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (name != null || unverified)
                Text.rich(
                  TextSpan(
                    children: [
                      if (name != null) TextSpan(text: account),
                      if (unverified) ...[
                        if (name != null) const TextSpan(text: '  ·  '),
                        TextSpan(
                          text: 'Not verified',
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ],
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: palette.muted,
                  ),
                ),
            ],
          ),
        ),
        if (inUse) ...[
          const SizedBox(width: 8),
          Text(
            'In use',
            key: inUseKey,
            style: theme.textTheme.labelMedium?.copyWith(color: palette.muted),
          ),
        ],
      ],
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
      SwitchListTile(
        key: const Key('settings.showMembershipEvents'),
        title: const Text('Show join and leave events'),
        subtitle: const Text(
          'Who joined, left, was invited or changed their name or picture, '
          'as small lines in the chat. Changes to the room itself always show.',
        ),
        value: ref.watch(showMembershipEventsProvider),
        onChanged: (on) =>
            ref.read(showMembershipEventsProvider.notifier).set(on: on),
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
        _ActionRow(
          leading: MatrixAvatar(
            account: _account,
            url: profile?.avatarUrl,
            name: name,
            seed: _account,
            radius: 20,
          ),
          title: 'Profile picture',
          subtitle: 'Everyone you chat with sees it.',
          actions: Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                key: const Key('settings.setAvatar'),
                onPressed: _busy ? null : _setProfilePicture,
                child: const Text('Change'),
              ),
              if (profile?.avatarUrl != null)
                OutlinedButton(
                  key: const Key('settings.removeAvatar'),
                  style: OxiButtons.destructive(context),
                  onPressed: _busy ? null : _removeProfilePicture,
                  child: const Text('Remove'),
                ),
            ],
          ),
        ),
        _ActionRow(
          leading: local == null
              ? const IconAvatar(icon: Icons.devices_rounded)
              : PictureAvatar(
                  bytes: local,
                  radius: 20,
                  fallback: const IconAvatar(icon: null),
                ),
          title: 'Picture on this device',
          subtitle:
              'Marks this account in OxiTalk on this device only, instead of '
              'the profile picture. Nobody else sees it.',
          actions: Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                key: const Key('settings.setLocalPicture'),
                onPressed: _busy ? null : _setLocalPicture,
                child: const Text('Choose'),
              ),
              if (local != null)
                OutlinedButton(
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

/// Logging out of [account], the last row of the Account section; the account itself is
/// named in the picker at its top.
class _LogOut extends ConsumerWidget {
  const _LogOut({required this.account, super.key});

  final String account;

  @override
  Widget build(BuildContext context, WidgetRef ref) => _ActionRow(
    leading: const IconAvatar(icon: Icons.logout_rounded),
    title: 'Log out',
    subtitle: 'OxiTalk on this device forgets this account.',
    actions: OutlinedButton(
      key: const Key('settings.logout'),
      style: OxiButtons.destructive(context),
      // Another account's settings then show the active one's; the active one's, as
      // anywhere, leave for the next account's chats (or the login).
      onPressed: () async {
        // Warns first when that would lose the encrypted history.
        if (!await confirmLogout(context, ref, account)) return;
        final wasActive = ref.read(activeAccountProvider) == account;
        unawaited(ref.read(accountsProvider.notifier).logout(account));
        if (!wasActive && context.mounted) {
          context.go(Routes.settingsSection(SettingsSection.account));
        }
      },
      child: const Text('Log out'),
    ),
  );
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
          trailing: OutlinedButton(
            key: const Key('settings.clearCache'),
            style: OxiButtons.destructive(context),
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

/// A settings row with buttons: beside the text where there is room, under it on a narrow
/// screen, so the text is not squeezed into a thin column.
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.actions,
  });

  final Widget leading;
  final String title;
  final String subtitle;
  final Widget actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.bodyLarge),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 520;
          return Row(
            crossAxisAlignment: narrow
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.center,
            children: [
              leading,
              const SizedBox(width: 16),
              Expanded(
                child: narrow
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [text, const SizedBox(height: 10), actions],
                      )
                    : text,
              ),
              if (!narrow) ...[const SizedBox(width: 16), actions],
            ],
          );
        },
      ),
    );
  }
}
