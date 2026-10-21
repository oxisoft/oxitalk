import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../matrix/api/matrix.dart';

/// Settings › Notifications for the active account.
class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(activeAccountProvider);
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          key: const Key('notificationSettings.back'),
          onPressed: () => context.go(Routes.settings),
        ),
        title: const Text('Notifications'),
      ),
      body: account == null
          ? const SizedBox.shrink()
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: NotificationSettingsPane(
                  key: ValueKey(account),
                  account: account,
                ),
              ),
            ),
    );
  }
}

/// The account's notification settings as Element X has them in Settings › Notifications:
/// the defaults for direct and group chats, @room, invitations, and (as Element Web)
/// keywords; with a warning and a fix when another client left the defaults inconsistent.
class NotificationSettingsPane extends ConsumerStatefulWidget {
  const NotificationSettingsPane({required this.account, super.key});

  final String account;

  @override
  ConsumerState<NotificationSettingsPane> createState() =>
      _NotificationSettingsPaneState();
}

class _NotificationSettingsPaneState
    extends ConsumerState<NotificationSettingsPane> {
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
    return ListView(
      children: [
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
                trailing: TextButton(
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
                  TextButton.icon(
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
      TextButton(
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
