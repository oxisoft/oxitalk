import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../matrix/api/matrix.dart';

/// How Element names a notification mode.
String notificationModeLabel(NotificationMode mode) => switch (mode) {
  NotificationMode.allMessages => 'All messages',
  NotificationMode.mentionsAndKeywords => 'Mentions and keywords',
  NotificationMode.mute => 'Mute',
};

/// What the room list's menu and a chat's info do about a room's notifications and unread
/// state, showing a failure in a snack bar instead of throwing it.
final class RoomNotificationActions {
  RoomNotificationActions(this.context, this.ref, this.account);

  final BuildContext context;
  final WidgetRef ref;
  final String account;

  MatrixSession? get _session =>
      ref.read(accountsProvider).value?.byId(account);

  /// Gives [room] its own [mode], or with `null` its default again.
  Future<void> setMode(Room room, NotificationMode? mode) => _run(
    'Can’t change the notifications',
    (session) => session.setRoomNotificationMode(room.id, mode),
  );

  /// Element's "Mark as read" with anything unread, else "Mark as unread".
  Future<void> toggleRead(Room room) => room.hasUnread
      ? _run('Can’t mark it read', (session) => session.markRoomRead(room.id))
      : _run(
          'Can’t mark it unread',
          (session) => session.setMarkedUnread(room.id, true),
        );

  Future<void> _run(
    String what,
    Future<void> Function(MatrixSession session) change,
  ) async {
    final session = _session;
    if (session == null) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await change(session);
    } on MatrixFailure catch (failure) {
      messenger?.showSnackBar(
        SnackBar(content: Text('$what: ${failure.kind.name}')),
      );
    }
  }

  /// The Notifications submenu of the room list's menu, at [at]: the default (named with
  /// what it is), then the three modes, the current one checked.
  Future<void> showMenuFor(Room room, Offset at) async {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final current = room.notificationMode;
    PopupMenuItem<VoidCallback> item(
      String key,
      String label,
      NotificationMode? mode,
    ) => CheckedPopupMenuItem(
      key: Key('notify.$key'),
      checked: current == mode,
      value: () => unawaited(setMode(room, mode)),
      child: Text(label),
    );
    final action = await showMenu<VoidCallback>(
      context: context,
      position: RelativeRect.fromRect(
        at & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        item(
          'default',
          'Default (${notificationModeLabel(room.defaultNotificationMode)})',
          null,
        ),
        item(
          'all',
          notificationModeLabel(NotificationMode.allMessages),
          NotificationMode.allMessages,
        ),
        item(
          'mentions',
          notificationModeLabel(NotificationMode.mentionsAndKeywords),
          NotificationMode.mentionsAndKeywords,
        ),
        item(
          'mute',
          notificationModeLabel(NotificationMode.mute),
          NotificationMode.mute,
        ),
      ],
    );
    action?.call();
  }
}
