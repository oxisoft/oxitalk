import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/notification_service.dart';
import '../../app/providers.dart';
import '../../matrix/api/matrix.dart';
import 'settings_heading.dart';

/// [account]'s notification settings, kept on its server, as Element X has them in
/// Settings › Notifications: the defaults for direct and group chats, @room, invitations,
/// and (as Element Web) keywords; with a warning and a fix when another client left the
/// defaults inconsistent. A group of the Account section, under its heading; every change
/// goes to [account], whichever account is in front.
class AccountNotificationSettings extends ConsumerStatefulWidget {
  const AccountNotificationSettings({required this.account, super.key});

  final String account;

  @override
  ConsumerState<AccountNotificationSettings> createState() =>
      _AccountNotificationSettingsState();
}

class _AccountNotificationSettingsState
    extends ConsumerState<AccountNotificationSettings> {
  var _busy = false;

  MatrixSession? get _session =>
      ref.read(accountsProvider).value?.byId(widget.account);

  /// Runs [change], showing a failure instead of throwing it.
  Future<void> _run(Future<void> Function(MatrixSession session) change) async {
    final session = _session;
    if (session == null || _busy) return;
    setState(() => _busy = true);
    try {
      await change(session);
    } on MatrixFailure catch (failure) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Can’t change the notifications: ${failure.kind.name}',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Asks for a keyword and adds it.
  Future<void> _addKeyword() async {
    final word = await showDialog<String>(
      context: context,
      builder: (_) => const _KeywordDialog(),
    );
    if (word == null || word.trim().isEmpty) return;
    await _run((session) => session.addNotificationKeyword(word.trim()));
  }

  Widget _default(
    String key,
    String title,
    NotificationMode mode, {
    required bool directChats,
  }) => ListTile(
    title: Text(title),
    subtitle: Padding(
      padding: const EdgeInsets.only(top: 8),
      child: SegmentedButton<NotificationMode>(
        key: Key('settings.notifications.$key'),
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(
            value: NotificationMode.allMessages,
            label: Text('All messages'),
          ),
          ButtonSegment(
            value: NotificationMode.mentionsAndKeywords,
            label: Text('Mentions and keywords'),
          ),
        ],
        selected: {mode},
        onSelectionChanged: _busy
            ? null
            : (choice) => unawaited(
                _run(
                  (session) => session.setDefaultNotificationMode(
                    directChats: directChats,
                    mode: choice.single,
                  ),
                ),
              ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final settings = ref
        .watch(notificationSettingsProvider(widget.account))
        .value;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SettingsHeading('Notifications', subtitle: 'For this account'),
        if (settings == null)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          )
        else ...[
          if (settings.inconsistent)
            Card(
              key: const Key('settings.notifications.inconsistent'),
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              color: theme.colorScheme.errorContainer,
              child: ListTile(
                leading: Icon(
                  Icons.warning_amber_rounded,
                  color: theme.colorScheme.onErrorContainer,
                ),
                title: const Text('Your notification settings don’t match'),
                subtitle: const Text(
                  'Another app set different defaults for encrypted and '
                  'unencrypted chats. Fix makes them the same again.',
                ),
                trailing: OutlinedButton(
                  key: const Key('settings.notifications.fix'),
                  onPressed: _busy
                      ? null
                      : () => unawaited(
                          _run((session) => session.fixNotificationDefaults()),
                        ),
                  child: const Text('Fix'),
                ),
              ),
            ),
          _default('dm', 'Direct chats', settings.dmDefault, directChats: true),
          _default(
            'group',
            'Group chats',
            settings.groupDefault,
            directChats: false,
          ),
          SwitchListTile(
            key: const Key('settings.notifications.roomMentions'),
            title: const Text('@room mentions'),
            subtitle: const Text(
              'Notify when someone mentions the whole room.',
            ),
            value: settings.roomMentions ?? false,
            onChanged: settings.roomMentions == null || _busy
                ? null
                : (on) => unawaited(
                    _run((session) => session.setRoomMentionsEnabled(on)),
                  ),
          ),
          SwitchListTile(
            key: const Key('settings.notifications.invites'),
            title: const Text('Invitations'),
            subtitle: const Text('Notify when you are invited to a chat.'),
            value: settings.invites ?? false,
            onChanged: settings.invites == null || _busy
                ? null
                : (on) => unawaited(
                    _run((session) => session.setInvitesEnabled(on)),
                  ),
          ),
          ListTile(
            title: const Text('Keywords'),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Messages with these words notify you, also in chats set '
                    'to mentions and keywords.',
                  ),
                  if (settings.keywords.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final word in settings.keywords)
                          InputChip(
                            key: Key('keyword.$word'),
                            label: Text(word),
                            onDeleted: _busy
                                ? null
                                : () => unawaited(
                                    _run(
                                      (session) => session
                                          .removeNotificationKeyword(word),
                                    ),
                                  ),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 4),
                  // In a dialog: a text field here would be a second scrollable on the page.
                  OutlinedButton.icon(
                    key: const Key('settings.notifications.newKeyword'),
                    onPressed: _busy ? null : () => unawaited(_addKeyword()),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add a keyword…'),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(
              'Kept on your server, so Element and your other devices use '
              'them too.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ],
    );
  }
}

/// How notifications show on this device, for all its accounts, as Element Desktop has them:
/// on or off, the message text or only "New message", sound.
class DeviceNotificationSettings extends ConsumerWidget {
  const DeviceNotificationSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(deviceNotificationsProvider);
    final notifier = ref.read(deviceNotificationsProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SettingsHeading(
          'Notifications on this device',
          subtitle: 'For all accounts',
        ),
        SwitchListTile(
          key: const Key('settings.device.enabled'),
          title: const Text('Enable notifications on this device'),
          subtitle: const Text(
            'While OxiTalk runs. On a phone, nothing comes once the system '
            'has closed the app.',
          ),
          value: prefs.enabled,
          onChanged: (on) async {
            final enabled = await notifier.setEnabled(on: on);
            if (on && !enabled && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Notifications are not allowed for OxiTalk in the system '
                    'settings.',
                  ),
                ),
              );
            }
          },
        ),
        SwitchListTile(
          key: const Key('settings.device.showText'),
          title: const Text('Show message text'),
          subtitle: const Text(
            'Off shows only “New message”, so nobody reads along on your '
            'screen.',
          ),
          value: prefs.showText,
          onChanged: prefs.enabled
              ? (on) => notifier.setShowText(on: on)
              : null,
        ),
        SwitchListTile(
          key: const Key('settings.device.sound'),
          title: const Text('Sound'),
          value: prefs.sound,
          onChanged: prefs.enabled ? (on) => notifier.setSound(on: on) : null,
        ),
      ],
    );
  }
}

/// Asks for a word that makes a message notify; pops it, or `null` when cancelled.
class _KeywordDialog extends StatefulWidget {
  const _KeywordDialog();

  @override
  State<_KeywordDialog> createState() => _KeywordDialogState();
}

class _KeywordDialogState extends State<_KeywordDialog> {
  final _word = TextEditingController();

  @override
  void dispose() {
    _word.dispose();
    super.dispose();
  }

  void _add() => Navigator.of(context).pop(_word.text);

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add a keyword'),
    content: TextField(
      key: const Key('settings.notifications.keyword'),
      controller: _word,
      autofocus: true,
      decoration: const InputDecoration(hintText: 'A word or name'),
      onSubmitted: (_) => _add(),
    ),
    actions: [
      OutlinedButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const Key('settings.notifications.addKeyword'),
        onPressed: _add,
        child: const Text('Add'),
      ),
    ],
  );
}
