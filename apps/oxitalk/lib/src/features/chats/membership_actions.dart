import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
import '../../matrix/api/matrix.dart';

/// Leaving rooms and answering invitations, for one account: each asks first where Element
/// does, and failures show as a snack bar. A room left or declined drops out of the list;
/// if it was open, the window goes back to the list.
final class MembershipActions {
  MembershipActions(this._context, this._ref, this._account);

  final BuildContext _context;
  final WidgetRef _ref;
  final String _account;

  MatrixSession? get _session =>
      _ref.read(accountsProvider).value?.byId(_account);

  /// Asks, telling what leaving costs, then leaves [roomId] ([isDm] for a direct chat).
  /// Returns whether it left.
  Future<bool> leave(
    String roomId, {
    required String name,
    bool isDm = false,
  }) async {
    final session = _session;
    if (session == null) return false;
    final router = GoRouter.of(_context);
    final messenger = ScaffoldMessenger.of(_context);
    LeaveInfo info;
    try {
      info = await session.leaveInfo(roomId);
    } on MatrixFailure {
      // Asked without the warnings then.
      info = const LeaveInfo();
    }
    if (!_context.mounted) return false;
    final sure = await showDialog<bool>(
      context: _context,
      builder: (context) =>
          LeaveDialog(name: name, info: info, isDm: isDm || info.isDm),
    );
    if (sure != true) return false;
    try {
      await session.leave(roomId);
    } on MatrixFailure catch (failure) {
      messenger.showSnackBar(
        SnackBar(content: Text('Can’t leave: ${failure.kind.name}')),
      );
      return false;
    }
    _closeIfOpen(router, roomId);
    return true;
  }

  /// Joins the room [roomId] the user was invited to; it opens as a chat.
  Future<void> accept(String roomId) async {
    final session = _session;
    if (session == null) return;
    final router = GoRouter.of(_context);
    final messenger = ScaffoldMessenger.of(_context);
    try {
      await session.join(roomId);
    } on MatrixFailure catch (failure) {
      messenger.showSnackBar(
        SnackBar(content: Text('Can’t join: ${failure.kind.name}')),
      );
      return;
    }
    router.go(Routes.room(roomId));
  }

  /// Asks, then declines the invitation to [roomId]. Returns whether it declined.
  Future<bool> decline(String roomId, {required String name}) async {
    final session = _session;
    if (session == null) return false;
    final router = GoRouter.of(_context);
    final messenger = ScaffoldMessenger.of(_context);
    final sure = await showDialog<bool>(
      context: _context,
      builder: (context) => AlertDialog(
        title: const Text('Decline the invitation?'),
        content: Text(
          'You won’t join “$name”. Whoever invited you can invite you again.',
        ),
        actions: [
          OutlinedButton(
            key: const Key('decline.cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('decline.confirm'),
            style: OxiButtons.destructiveFilled(context),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Decline'),
          ),
        ],
      ),
    );
    if (sure != true) return false;
    try {
      await session.leave(roomId);
    } on MatrixFailure catch (failure) {
      messenger.showSnackBar(
        SnackBar(content: Text('Can’t decline: ${failure.kind.name}')),
      );
      return false;
    }
    _closeIfOpen(router, roomId);
    return true;
  }

  /// Back to the chat list if [roomId] (or its info, or a thread of it) is open.
  void _closeIfOpen(GoRouter router, String roomId) {
    final path = router.routerDelegate.currentConfiguration.uri.path;
    final room = Routes.room(roomId);
    if (path == room || path.startsWith('$room/')) router.go(Routes.chats);
  }
}

/// Asks before leaving a room, with Element's warnings: no way back without an invite, the
/// last admin, the last one in it.
class LeaveDialog extends StatelessWidget {
  const LeaveDialog({
    required this.name,
    required this.info,
    this.isDm = false,
    super.key,
  });

  final String name;
  final LeaveInfo info;
  final bool isDm;

  @override
  Widget build(BuildContext context) {
    final warnings = [
      if (info.onlyMember)
        'You’re the only one here. If you leave, nobody will be able to join '
            'it again, you included.'
      else ...[
        if (info.lastAdmin)
          'You’re its only admin. If you leave, nobody can change its settings '
              'or make someone else an admin.',
        if (info.needsInviteToRejoin && !isDm)
          'This room isn’t public: you can’t come back without a new invite.',
      ],
    ];
    return AlertDialog(
      title: Text(isDm ? 'Leave this chat?' : 'Leave “$name”?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          if (warnings.isEmpty)
            Text(
              isDm
                  ? 'You won’t get its messages any more.'
                  : 'You can join it again later.',
            ),
          for (final (i, warning) in warnings.indexed)
            Text(warning, key: Key('leave.warning.$i')),
        ],
      ),
      actions: [
        OutlinedButton(
          key: const Key('leave.cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('leave.confirm'),
          style: OxiButtons.destructiveFilled(context),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Leave'),
        ),
      ],
    );
  }
}

/// The Leave row of a chat's info.
class LeaveRoomRow extends ConsumerWidget {
  const LeaveRoomRow({required this.account, required this.roomId, super.key});

  final String account;
  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final room = ref
        .watch(roomsProvider(account))
        .value
        ?.where((room) => room.id == roomId)
        .firstOrNull;
    if (room == null || room.membership != Membership.joined) {
      return const SizedBox.shrink();
    }
    final red = OxiButtons.danger(Theme.of(context).brightness);
    return ListTile(
      key: const Key('info.leave'),
      leading: Icon(Icons.logout_rounded, color: red),
      title: Text(
        room.isDm ? 'Leave chat' : 'Leave room',
        style: TextStyle(color: red, fontWeight: FontWeight.w700),
      ),
      onTap: () => unawaited(
        MembershipActions(
          context,
          ref,
          account,
        ).leave(roomId, name: room.name, isDm: room.isDm),
      ),
    );
  }
}
