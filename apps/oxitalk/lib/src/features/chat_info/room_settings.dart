import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/pick_image.dart';
import '../../app/providers.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
import '../../matrix/api/matrix.dart';
import '../../ui/avatar.dart';
import '../settings/settings_heading.dart';

/// What a join rule is called where it is chosen.
String joinRuleLabel(RoomJoinRule rule) => switch (rule) {
  RoomJoinRule.invite => 'Invite only',
  RoomJoinRule.knock => 'Ask to join',
  RoomJoinRule.public => 'Anyone',
  RoomJoinRule.restricted => 'Members of a space',
  RoomJoinRule.knockRestricted => 'Members of a space, others ask to join',
  RoomJoinRule.other => 'Custom',
};

/// What a history setting is called where it is chosen.
String historyLabel(RoomHistory history) => switch (history) {
  RoomHistory.shared => 'Members, since this option was chosen',
  RoomHistory.invited => 'Members, since they were invited',
  RoomHistory.joined => 'Members, since they joined',
  RoomHistory.worldReadable => 'Anyone',
};

/// The line under "Security & privacy" in the chat info: who can join, and encryption.
String securitySummary(RoomSettings settings) => [
  joinRuleLabel(settings.joinRule),
  if (settings.isEncrypted) 'Encrypted' else 'Not encrypted',
].join(' · ');

/// Shows a failed change: [what] is what didn't change, like `the name`.
void _showFailure(
  ScaffoldMessengerState messenger,
  MatrixFailure failure,
  String what,
) => messenger.showSnackBar(
  SnackBar(
    content: Text(
      failure.kind == FailureKind.forbidden
          ? 'You aren’t allowed to change $what in this room'
          : 'Can’t change $what: ${failure.kind.name}',
    ),
  ),
);

/// Asks for the room's new name, topic and picture and saves what changed. Only what the
/// user's power level allows can be edited; the rest shows as it is.
Future<void> editRoomDetails(
  BuildContext context, {
  required String account,
  required RoomSettings settings,
  required String shownName,
}) => showDialog<void>(
  context: context,
  builder: (_) => EditRoomDetailsDialog(
    account: account,
    settings: settings,
    shownName: shownName,
  ),
);

/// The room's name, topic and picture, edited together and saved with Save.
class EditRoomDetailsDialog extends ConsumerStatefulWidget {
  const EditRoomDetailsDialog({
    required this.account,
    required this.settings,
    required this.shownName,
    super.key,
  });

  final String account;
  final RoomSettings settings;

  /// The name the room shows under, for its picture's initials when it has no name.
  final String shownName;

  @override
  ConsumerState<EditRoomDetailsDialog> createState() =>
      _EditRoomDetailsDialogState();
}

class _EditRoomDetailsDialogState extends ConsumerState<EditRoomDetailsDialog> {
  late final _name = TextEditingController(text: widget.settings.name ?? '');
  late final _topic = TextEditingController(text: widget.settings.topic ?? '');

  /// A newly chosen picture, saved with Save.
  PickedImage? _picture;

  /// The picture is to be removed with Save.
  var _removePicture = false;
  var _saving = false;
  String? _error;

  RoomSettings get _settings => widget.settings;
  RoomPermissions get _may => _settings.permissions;

  @override
  void dispose() {
    _name.dispose();
    _topic.dispose();
    super.dispose();
  }

  Future<void> _choosePicture() async {
    final picture = await ref.read(pickImageProvider)();
    if (picture == null || !mounted) return;
    setState(() {
      _picture = picture;
      _removePicture = false;
    });
  }

  bool get _hasPicture =>
      _picture != null || (_settings.avatarUrl != null && !_removePicture);

  Future<void> _save() async {
    final session = ref.read(accountsProvider).value?.byId(widget.account);
    if (session == null) return;
    final roomId = _settings.roomId;
    final name = _name.text.trim();
    final topic = _topic.text.trim();
    setState(() {
      _saving = true;
      _error = null;
    });
    var what = 'the details';
    try {
      if (_may.name && name != (_settings.name ?? '')) {
        what = 'the name';
        await session.setRoomName(roomId, name);
      }
      if (_may.topic && topic != (_settings.topic ?? '')) {
        what = 'the topic';
        await session.setRoomTopic(roomId, topic);
      }
      if (_may.avatar) {
        what = 'the picture';
        if (_picture case final picture?) {
          await session.setRoomAvatar(roomId, picture.bytes, picture.mimeType);
        } else if (_removePicture && _settings.avatarUrl != null) {
          await session.removeRoomAvatar(roomId);
        }
      }
      if (mounted) Navigator.of(context).pop();
    } on MatrixFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = failure.kind == FailureKind.forbidden
            ? 'You aren’t allowed to change $what in this room.'
            : 'Can’t change $what: ${failure.kind.name}.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = _error;
    final picture = _picture;
    return AlertDialog(
      title: const Text('Edit details'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: picture != null
                    ? PictureAvatar(
                        bytes: picture.bytes,
                        radius: 44,
                        fallback: const IconAvatar(icon: null, radius: 44),
                      )
                    : MatrixAvatar(
                        account: widget.account,
                        url: _removePicture ? null : _settings.avatarUrl,
                        name: widget.shownName,
                        seed: _settings.roomId,
                        radius: 44,
                      ),
              ),
              if (_may.avatar) ...[
                const SizedBox(height: 8),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  children: [
                    OutlinedButton(
                      key: const Key('editRoom.choosePicture'),
                      onPressed: _saving ? null : _choosePicture,
                      child: const Text('Choose picture'),
                    ),
                    if (_hasPicture)
                      OutlinedButton(
                        key: const Key('editRoom.removePicture'),
                        style: OxiButtons.destructive(context),
                        onPressed: _saving
                            ? null
                            : () => setState(() {
                                _picture = null;
                                _removePicture = true;
                              }),
                        child: const Text('Remove'),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                key: const Key('editRoom.name'),
                controller: _name,
                enabled: _may.name && !_saving,
                autofocus: _may.name,
                decoration: InputDecoration(
                  labelText: 'Name',
                  helperText: _may.name
                      ? null
                      : 'You aren’t allowed to change the name.',
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('editRoom.topic'),
                controller: _topic,
                enabled: _may.topic && !_saving,
                minLines: 1,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: 'Topic',
                  helperText: _may.topic
                      ? null
                      : 'You aren’t allowed to change the topic.',
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(
                  error,
                  key: const Key('editRoom.error'),
                  style: TextStyle(color: OxiButtons.danger(theme.brightness)),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('editRoom.save'),
          onPressed: _saving ? null : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// A chat's security and privacy settings of the active account as a page of its own
/// (narrow windows).
class RoomSecurityScreen extends ConsumerWidget {
  const RoomSecurityScreen({required this.roomId, super.key});

  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(activeAccountProvider);
    if (account == null) return const SizedBox.shrink();
    return RoomSecurityPane(
      key: ValueKey((account, roomId)),
      account: account,
      roomId: roomId,
    );
  }
}

/// Element X's "Security & privacy": who can join, the address of a public room and its
/// listing in the room directory, who can read the history, and encryption. A setting the
/// user's power level doesn't allow shows as text. Back returns to the chat's info.
class RoomSecurityPane extends ConsumerStatefulWidget {
  const RoomSecurityPane({
    required this.account,
    required this.roomId,
    super.key,
  });

  final String account;
  final String roomId;

  @override
  ConsumerState<RoomSecurityPane> createState() => _RoomSecurityPaneState();
}

class _RoomSecurityPaneState extends ConsumerState<RoomSecurityPane> {
  /// A choice being saved, shown at once.
  RoomJoinRule? _pendingJoinRule;
  RoomHistory? _pendingHistory;
  bool? _pendingPublished;
  var _saving = false;

  String get _roomId => widget.roomId;

  MatrixSession? get _session =>
      ref.read(accountsProvider).value?.byId(widget.account);

  /// Runs [change]; a failure shows in a snack bar naming [what].
  Future<void> _run(String what, Future<void> Function() change) async {
    if (_saving) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      await change();
    } on MatrixFailure catch (failure) {
      _showFailure(messenger, failure, what);
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _pendingJoinRule = null;
          _pendingHistory = null;
          _pendingPublished = null;
        });
      }
    }
  }

  void _setJoinRule(RoomSettings settings, RoomJoinRule rule) {
    final session = _session;
    if (session == null || rule == settings.joinRule) return;
    setState(() => _pendingJoinRule = rule);
    unawaited(
      _run('who can join', () => session.setRoomJoinRule(_roomId, rule)),
    );
  }

  void _setHistory(RoomSettings settings, RoomHistory history) {
    final session = _session;
    if (session == null || history == settings.history) return;
    setState(() => _pendingHistory = history);
    unawaited(
      _run(
        'who can read the history',
        () => session.setRoomHistory(_roomId, history),
      ),
    );
  }

  void _setPublished(bool published) {
    final session = _session;
    if (session == null) return;
    setState(() => _pendingPublished = published);
    unawaited(
      _run('the directory listing', () async {
        await session.setRoomPublished(_roomId, published);
        ref.invalidate(roomPublishedProvider(widget.account, _roomId));
        await ref.read(roomPublishedProvider(widget.account, _roomId).future);
      }),
    );
  }

  Future<void> _enableEncryption(RoomSettings settings) async {
    final session = _session;
    if (session == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enable encryption?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Encryption can’t be turned off again once it is on. Messages '
              'sent from then on can be read only on the members’ devices: not '
              'by the server, nor by bots and bridges that don’t support '
              'encryption, and search finds them only on each device.',
            ),
            if (settings.joinRule == RoomJoinRule.public) ...[
              const SizedBox(height: 12),
              const Text(
                'Anyone can join this room, so encryption keeps little private '
                'here and makes it slower for many members.',
              ),
            ],
          ],
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('security.confirmEncryption'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Enable encryption'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run('encryption', () => session.enableRoomEncryption(_roomId));
  }

  Future<void> _changeAddress(RoomSettings settings) async {
    final session = _session;
    if (session == null) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _AddressDialog(
        settings: settings,
        save: (localpart) => session.setRoomMainAddress(_roomId, localpart),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(roomSettingsProvider(widget.account, _roomId));
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: BackButton(
          key: const Key('security.back'),
          onPressed: () => context.go(Routes.roomInfo(_roomId)),
        ),
        title: const Text('Security & privacy'),
      ),
      body: switch (settings) {
        AsyncValue(:final value?) => _body(context, value),
        AsyncError() => const Center(
          child: Text('Can’t load this chat’s settings.'),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Widget _body(BuildContext context, RoomSettings settings) {
    final may = settings.permissions;
    final joinRule = _pendingJoinRule ?? settings.joinRule;
    final history = _pendingHistory ?? settings.history;
    final public = joinRule == RoomJoinRule.public;
    final joinChoices = [
      RoomJoinRule.invite,
      if (settings.knockSupported || joinRule == RoomJoinRule.knock)
        RoomJoinRule.knock,
      RoomJoinRule.public,
      // One this app doesn't offer, shown as the current choice.
      if (joinRule
          case RoomJoinRule.restricted ||
              RoomJoinRule.knockRestricted ||
              RoomJoinRule.other)
        joinRule,
    ];
    final historyChoices = [
      // Anyone (members or not) only where anyone can join.
      if (public || history == RoomHistory.worldReadable)
        RoomHistory.worldReadable,
      RoomHistory.shared,
      RoomHistory.invited,
      RoomHistory.joined,
    ];
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        const SettingsHeading('Who can join'),
        if (may.joinRule)
          RadioGroup<RoomJoinRule>(
            groupValue: joinRule,
            onChanged: (choice) {
              if (choice != null && !_saving) _setJoinRule(settings, choice);
            },
            child: Column(
              children: [
                for (final choice in joinChoices)
                  RadioListTile<RoomJoinRule>(
                    key: Key('security.join.${choice.name}'),
                    value: choice,
                    enabled:
                        !_saving &&
                        switch (choice) {
                          RoomJoinRule.invite ||
                          RoomJoinRule.knock ||
                          RoomJoinRule.public => true,
                          _ => false,
                        },
                    title: Text(joinRuleLabel(choice)),
                    subtitle: switch (choice) {
                      RoomJoinRule.invite => const Text(
                        'Only people who are invited can join.',
                      ),
                      RoomJoinRule.knock => const Text(
                        'Anyone can ask to join; a member lets them in.',
                      ),
                      RoomJoinRule.public => const Text(
                        'Anyone who finds the room can join.',
                      ),
                      _ => const Text('Set in another app.'),
                    },
                  ),
              ],
            ),
          )
        else
          _ReadOnly(
            key: const Key('security.join.readOnly'),
            value: joinRuleLabel(joinRule),
          ),
        if (public) ...[
          const Divider(),
          const SettingsHeading(
            'Address',
            subtitle: 'People find and join the room by its address.',
          ),
          ListTile(
            key: const Key('security.address'),
            leading: const Icon(Icons.alternate_email_rounded),
            title: const Text('Main address'),
            subtitle: SelectableText(settings.mainAddress ?? 'No address yet'),
            trailing: may.address
                ? OutlinedButton(
                    key: const Key('security.changeAddress'),
                    onPressed: _saving ? null : () => _changeAddress(settings),
                    child: Text(
                      settings.mainAddress == null ? 'Add' : 'Change',
                    ),
                  )
                : null,
          ),
          _DirectorySwitch(
            account: widget.account,
            roomId: _roomId,
            enabled: may.address && !_saving,
            pending: _pendingPublished,
            onChanged: _setPublished,
          ),
        ],
        const Divider(),
        const SettingsHeading('Who can read the history'),
        if (may.history)
          RadioGroup<RoomHistory>(
            groupValue: history,
            onChanged: (choice) {
              if (choice != null && !_saving) _setHistory(settings, choice);
            },
            child: Column(
              children: [
                for (final choice in historyChoices)
                  RadioListTile<RoomHistory>(
                    key: Key('security.history.${choice.name}'),
                    value: choice,
                    enabled:
                        !_saving &&
                        (choice != RoomHistory.worldReadable || public),
                    title: Text(historyLabel(choice)),
                    subtitle: choice == RoomHistory.worldReadable
                        ? const Text('Members or not.')
                        : null,
                  ),
              ],
            ),
          )
        else
          _ReadOnly(
            key: const Key('security.history.readOnly'),
            value: historyLabel(history),
          ),
        const Divider(),
        const SettingsHeading('Encryption'),
        ListTile(
          key: const Key('security.encryption'),
          leading: Icon(
            settings.isEncrypted ? Icons.lock_rounded : Icons.lock_open_rounded,
          ),
          title: Text(
            settings.isEncrypted
                ? 'End-to-end encryption is on'
                : 'Not encrypted',
          ),
          subtitle: Text(
            settings.isEncrypted
                ? 'Messages can be read only on the members’ devices. '
                      'Encryption can’t be turned off.'
                : may.encryption
                ? 'Once on, encryption can’t be turned off.'
                : 'You aren’t allowed to turn encryption on.',
          ),
        ),
        if (!settings.isEncrypted && may.encryption)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton(
                key: const Key('security.enableEncryption'),
                onPressed: _saving ? null : () => _enableEncryption(settings),
                child: const Text('Enable encryption'),
              ),
            ),
          ),
      ],
    );
  }
}

/// A setting the user may not change: its value, and why it can't be changed.
class _ReadOnly extends StatelessWidget {
  const _ReadOnly({required this.value, super.key});

  final String value;

  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(value),
    subtitle: Text(
      'You aren’t allowed to change this.',
      style: TextStyle(color: context.oxi.muted),
    ),
  );
}

/// The listing in the server's room directory, asked of the server once shown.
class _DirectorySwitch extends ConsumerWidget {
  const _DirectorySwitch({
    required this.account,
    required this.roomId,
    required this.enabled,
    required this.pending,
    required this.onChanged,
  });

  final String account;
  final String roomId;
  final bool enabled;
  final bool? pending;
  final void Function(bool) onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final published = ref.watch(roomPublishedProvider(account, roomId));
    final value = pending ?? published.value;
    return SwitchListTile(
      key: const Key('security.published'),
      title: const Text('Visible in the public room directory'),
      subtitle: Text(switch (published) {
        AsyncError() when value == null => 'Can’t tell if it is listed.',
        _ when !enabled && value != null =>
          'You aren’t allowed to change this.',
        _ => 'Anyone on the server can find it by searching.',
      }),
      value: value ?? false,
      onChanged: enabled && value != null ? onChanged : null,
    );
  }
}

/// Asks for a new main address `#name:server` and saves it, saying when it is taken.
class _AddressDialog extends StatefulWidget {
  const _AddressDialog({required this.settings, required this.save});

  final RoomSettings settings;

  /// Saves the address with this localpart; `false` if it is taken.
  final Future<bool> Function(String localpart) save;

  @override
  State<_AddressDialog> createState() => _AddressDialogState();
}

class _AddressDialogState extends State<_AddressDialog> {
  late final _localpart = TextEditingController(
    text: _localpartOf(widget.settings),
  );
  var _saving = false;
  String? _error;

  /// The current address's name part, if it is on the user's server.
  static String _localpartOf(RoomSettings settings) {
    final address = settings.mainAddress;
    final suffix = ':${settings.serverName}';
    if (address == null || !address.endsWith(suffix)) return '';
    return address.substring(1, address.length - suffix.length);
  }

  @override
  void dispose() {
    _localpart.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final localpart = _localpart.text.trim();
    if (localpart.isEmpty || localpart.contains(RegExp(r'[:#\s]'))) {
      setState(() => _error = 'Use a name without spaces, # or :.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await widget.save(localpart);
      if (!mounted) return;
      if (saved) {
        Navigator.of(context).pop();
      } else {
        setState(() {
          _saving = false;
          _error = 'Another room has this address.';
        });
      }
    } on MatrixFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = switch (failure.kind) {
          FailureKind.invalidId => 'This can’t be an address.',
          FailureKind.forbidden =>
            'You aren’t allowed to change the address in this room.',
          _ => 'Can’t change the address: ${failure.kind.name}.',
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.settings.mainAddress == null ? 'Add an address' : 'Main address',
    ),
    content: SizedBox(
      width: 420,
      child: TextField(
        key: const Key('security.addressField'),
        controller: _localpart,
        autofocus: true,
        enabled: !_saving,
        decoration: InputDecoration(
          prefixText: '#',
          suffixText: ':${widget.settings.serverName}',
          errorText: _error,
          helperText: 'The room keeps its earlier addresses.',
        ),
        onSubmitted: (_) => unawaited(_submit()),
      ),
    ),
    actions: [
      OutlinedButton(
        onPressed: _saving ? null : () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const Key('security.saveAddress'),
        onPressed: _saving ? null : _submit,
        child: const Text('Save'),
      ),
    ],
  );
}
