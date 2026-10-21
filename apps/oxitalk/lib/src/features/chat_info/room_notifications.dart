import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../matrix/api/matrix.dart';
import '../chats/notification_actions.dart';

/// A chat's notification settings of the active account as a page of its own (narrow
/// windows).
class RoomNotificationsScreen extends ConsumerWidget {
  const RoomNotificationsScreen({required this.roomId, super.key});

  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(activeAccountProvider);
    if (account == null) return const SizedBox.shrink();
    return RoomNotificationsPane(
      key: ValueKey((account, roomId)),
      account: account,
      roomId: roomId,
    );
  }
}

/// A chat's notifications as Element X has them: a switch to follow the account's default,
/// and without it the three modes. Back returns to the chat's info.
class RoomNotificationsPane extends ConsumerStatefulWidget {
  const RoomNotificationsPane({
    required this.account,
    required this.roomId,
    super.key,
  });

  final String account;
  final String roomId;

  @override
  ConsumerState<RoomNotificationsPane> createState() =>
      _RoomNotificationsPaneState();
}

class _RoomNotificationsPaneState extends ConsumerState<RoomNotificationsPane> {
  /// What is being saved, so the choice shows at once and twice-tapping sends once.
  NotificationMode? _pending;
  var _saving = false;

  Future<void> _set(Room room, NotificationMode? mode) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _pending = mode;
    });
    await RoomNotificationActions(
      context,
      ref,
      widget.account,
    ).setMode(room, mode);
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final room = ref
        .watch(roomsProvider(widget.account))
        .value
        ?.where((room) => room.id == widget.roomId)
        .firstOrNull;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: BackButton(
          key: const Key('roomNotifications.back'),
          onPressed: () => context.go(Routes.roomInfo(widget.roomId)),
        ),
        title: const Text('Notifications'),
      ),
      body: room == null
          ? const Center(child: CircularProgressIndicator())
          : _body(context, room),
    );
  }

  Widget _body(BuildContext context, Room room) {
    final theme = Theme.of(context);
    final mode = _saving ? _pending : room.notificationMode;
    final followsDefault = mode == null;
    final shown = mode ?? room.defaultNotificationMode;
    return ListView(
      children: [
        SwitchListTile(
          key: const Key('roomNotifications.matchDefault'),
          title: const Text('Match default setting'),
          subtitle: Text(
            'Default for ${room.isDm ? 'direct chats' : 'group chats'}: '
            '${notificationModeLabel(room.defaultNotificationMode)}. '
            'Change it in Settings.',
          ),
          value: followsDefault,
          onChanged: _saving
              ? null
              : (on) => unawaited(
                  _set(room, on ? null : room.defaultNotificationMode),
                ),
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            'Notify me for',
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        RadioGroup<NotificationMode>(
          groupValue: shown,
          onChanged: (choice) {
            if (choice != null && !followsDefault && !_saving) {
              unawaited(_set(room, choice));
            }
          },
          child: Column(
            children: [
              for (final choice in NotificationMode.values)
                RadioListTile<NotificationMode>(
                  key: Key('roomNotifications.${choice.name}'),
                  value: choice,
                  enabled: !followsDefault && !_saving,
                  title: Text(notificationModeLabel(choice)),
                  subtitle: switch (choice) {
                    NotificationMode.mentionsAndKeywords => const Text(
                      'Only when someone mentions you, or @room, or writes one '
                      'of your keywords.',
                    ),
                    NotificationMode.mute => const Text(
                      'Nothing, and no count in the chat list.',
                    ),
                    NotificationMode.allMessages => null,
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }
}
