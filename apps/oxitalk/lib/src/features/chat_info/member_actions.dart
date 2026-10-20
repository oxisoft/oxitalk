import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../matrix/api/matrix.dart';

/// The power levels the role choices stand for.
const adminLevel = 100;
const moderatorLevel = 50;
const memberLevel = 0;

/// A member's ⋮ menu in a room's member list: message them, copy their ID, and what the
/// user's power level lets them do — change their role, remove, ban or unban them.
class MemberMenu extends ConsumerWidget {
  const MemberMenu({
    required this.account,
    required this.roomId,
    required this.member,
    super.key,
  });

  final String account;
  final String roomId;
  final RoomMember member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final own = member.userId == account;
    return PopupMenuButton<_Action>(
      key: Key('member.menu.${member.userId}'),
      tooltip: 'Member actions',
      icon: const Icon(Icons.more_vert_rounded),
      onSelected: (action) => unawaited(_run(context, ref, action)),
      itemBuilder: (_) => [
        if (!own)
          const PopupMenuItem(
            key: Key('member.message'),
            value: _Action.message,
            child: ListTile(
              leading: Icon(Icons.chat_bubble_outline_rounded),
              title: Text('Message'),
            ),
          ),
        const PopupMenuItem(
          key: Key('member.copyId'),
          value: _Action.copyId,
          child: ListTile(
            leading: Icon(Icons.copy_rounded),
            title: Text('Copy user ID'),
          ),
        ),
        if (member.canChangeRole && !member.banned)
          const PopupMenuItem(
            key: Key('member.role'),
            value: _Action.role,
            child: ListTile(
              leading: Icon(Icons.shield_outlined),
              title: Text('Change role…'),
            ),
          ),
        if (member.canRemove)
          PopupMenuItem(
            key: const Key('member.remove'),
            value: _Action.remove,
            child: ListTile(
              leading: const Icon(Icons.person_remove_outlined),
              title: Text(
                member.invited ? 'Withdraw invite…' : 'Remove from room…',
              ),
            ),
          ),
        if (member.canBan)
          const PopupMenuItem(
            key: Key('member.ban'),
            value: _Action.ban,
            child: ListTile(
              leading: Icon(Icons.block_rounded),
              title: Text('Ban…'),
            ),
          ),
        if (member.canUnban)
          const PopupMenuItem(
            key: Key('member.unban'),
            value: _Action.unban,
            child: ListTile(
              leading: Icon(Icons.lock_open_rounded),
              title: Text('Unban'),
            ),
          ),
      ],
    );
  }

  Future<void> _run(BuildContext context, WidgetRef ref, _Action action) async {
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final session = ref.read(accountsProvider).value?.byId(account);
    if (session == null) return;
    final name = member.displayName ?? member.userId;
    try {
      switch (action) {
        case _Action.message:
          router.go(
            Routes.room(
              session.dmWith(member.userId) ??
                  await session.createDm(member.userId),
            ),
          );
          return;
        case _Action.copyId:
          await Clipboard.setData(ClipboardData(text: member.userId));
          messenger.showSnackBar(
            const SnackBar(content: Text('User ID copied')),
          );
          return;
        case _Action.role:
          final details = await ref.read(
            roomDetailsProvider(account, roomId).future,
          );
          if (!context.mounted) return;
          final level = await showDialog<int>(
            context: context,
            builder: (_) => RoleDialog(
              name: name,
              current: member.powerLevel,
              // `null`: a room creator, above every level.
              ownLevel: details.ownPowerLevel,
              self: member.userId == account,
            ),
          );
          if (level == null || level == member.powerLevel) return;
          await session.setPowerLevel(roomId, member.userId, level);
          messenger.showSnackBar(
            SnackBar(content: Text('$name is now ${roleName(level)}')),
          );
        case _Action.remove:
          if (!context.mounted) return;
          final reason = await _askReason(
            context,
            title: member.invited
                ? 'Withdraw the invite to $name?'
                : 'Remove $name from the room?',
            action: member.invited ? 'Withdraw' : 'Remove',
            note: member.invited
                ? null
                : 'They can come back if invited again, or by the room’s address '
                      'if it is public.',
          );
          if (reason == null) return;
          await session.removeMember(
            roomId,
            member.userId,
            reason: reason.isEmpty ? null : reason,
          );
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                member.invited ? 'Invite withdrawn' : 'Removed $name',
              ),
            ),
          );
        case _Action.ban:
          if (!context.mounted) return;
          final reason = await _askReason(
            context,
            title: 'Ban $name?',
            action: 'Ban',
            note: 'They are removed and can’t come back until unbanned.',
          );
          if (reason == null) return;
          await session.banMember(
            roomId,
            member.userId,
            reason: reason.isEmpty ? null : reason,
          );
          messenger.showSnackBar(SnackBar(content: Text('Banned $name')));
        case _Action.unban:
          await session.unbanMember(roomId, member.userId);
          messenger.showSnackBar(SnackBar(content: Text('Unbanned $name')));
      }
    } on MatrixFailure catch (failure) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            failure.kind == FailureKind.forbidden
                ? 'You aren’t allowed to do that in this room'
                : 'Didn’t work: ${failure.kind.name}',
          ),
        ),
      );
      return;
    }
    ref
      ..invalidate(roomMembersProvider(account, roomId))
      ..invalidate(roomDetailsProvider(account, roomId));
  }
}

enum _Action { message, copyId, role, remove, ban, unban }

/// `Admin`, `Moderator`, `Member`, or `Custom (level)`.
String roleName(int? level) => switch (level) {
  null => 'Creator',
  adminLevel => 'Admin',
  moderatorLevel => 'Moderator',
  memberLevel => 'Member',
  _ => 'Custom ($level)',
};

/// Asks to confirm removing or banning, with an optional reason; gives back the reason
/// (empty for none), or `null` when cancelled.
Future<String?> _askReason(
  BuildContext context, {
  required String title,
  required String action,
  String? note,
}) => showDialog<String>(
  context: context,
  builder: (context) => _ReasonDialog(title: title, action: action, note: note),
);

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({required this.title, required this.action, this.note});

  final String title;
  final String action;
  final String? note;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _confirm() => Navigator.of(context).pop(_reason.text.trim());

  @override
  Widget build(BuildContext context) {
    final note = widget.note;
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (note != null) Text(note),
          TextField(
            key: const Key('member.reason'),
            controller: _reason,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Reason (optional)'),
            onSubmitted: (_) => _confirm(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('member.confirm'),
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: _confirm,
          child: Text(widget.action),
        ),
      ],
    );
  }
}

/// Picks a member's role: Admin, Moderator, Member, or a custom level. Levels above the
/// user's own [ownLevel] (`null`: unlimited) can't be given. Lowering one's own role asks
/// once more, as it can't be undone without someone above.
class RoleDialog extends StatefulWidget {
  const RoleDialog({
    required this.name,
    required this.current,
    required this.ownLevel,
    required this.self,
    super.key,
  });

  final String name;
  final int? current;
  final int? ownLevel;
  final bool self;

  @override
  State<RoleDialog> createState() => _RoleDialogState();
}

class _RoleDialogState extends State<RoleDialog> {
  late int? _level = widget.current;
  late var _custom = !{
    adminLevel,
    moderatorLevel,
    memberLevel,
    null,
  }.contains(widget.current);
  late final _number = TextEditingController(
    text: _custom ? '${widget.current}' : '',
  );
  var _confirmingSelf = false;

  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  bool _allowed(int level) {
    final own = widget.ownLevel;
    return own == null || level <= own;
  }

  int? get _chosen => _custom ? int.tryParse(_number.text.trim()) : _level;

  void _save() {
    final level = _chosen;
    if (level == null || !_allowed(level)) return;
    final current = widget.current;
    final lowering = current == null || level < current;
    if (widget.self && lowering && !_confirmingSelf) {
      setState(() => _confirmingSelf = true);
      return;
    }
    Navigator.of(context).pop(level);
  }

  Widget _choice(String title, int level, String subtitle) =>
      RadioListTile<int>(
        key: Key('role.$level'),
        value: level,
        title: Text(title),
        subtitle: Text(subtitle),
        enabled: _allowed(level),
        contentPadding: EdgeInsets.zero,
      );

  @override
  Widget build(BuildContext context) {
    final chosen = _chosen;
    final valid = chosen != null && _allowed(chosen);
    return AlertDialog(
      title: Text('Role of ${widget.name}'),
      content: SizedBox(
        width: 380,
        child: _confirmingSelf
            ? Text(
                'You are lowering your own role to ${roleName(chosen)}. '
                'You can’t undo this yourself; only someone with a higher role '
                'can give it back.',
                key: const Key('role.selfWarning'),
              )
            : RadioGroup<int>(
                groupValue: _custom ? -1 : _level,
                onChanged: (level) => setState(() {
                  _custom = level == -1;
                  if (level != -1) _level = level;
                }),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _choice('Admin', adminLevel, 'Everything, including roles'),
                    _choice(
                      'Moderator',
                      moderatorLevel,
                      'Removes and bans members, deletes messages',
                    ),
                    _choice('Member', memberLevel, 'Talks in the room'),
                    RadioListTile<int>(
                      key: const Key('role.custom'),
                      value: -1,
                      title: const Text('Custom level'),
                      contentPadding: EdgeInsets.zero,
                    ),
                    if (_custom)
                      TextField(
                        key: const Key('role.number'),
                        controller: _number,
                        autofocus: true,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp('-?[0-9]*')),
                        ],
                        decoration: InputDecoration(
                          labelText: 'Power level',
                          helperText: widget.ownLevel == null
                              ? null
                              : 'Up to ${widget.ownLevel}, your own',
                          errorText: chosen != null && !_allowed(chosen)
                              ? 'Higher than your own level'
                              : null,
                        ),
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (_) => _save(),
                      ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('role.save'),
          onPressed: valid ? _save : null,
          child: Text(_confirmingSelf ? 'Lower my role' : 'Save'),
        ),
      ],
    );
  }
}
