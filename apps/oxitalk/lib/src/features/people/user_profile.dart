import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
import '../../matrix/api/matrix.dart';
import '../../ui/avatar.dart';
import '../verify/verify_screen.dart';
import 'people_providers.dart';

/// Opens [userId]'s profile: a sheet from the bottom on a phone, a dialog on a wide window.
/// [name] and [avatarUrl] show until the profile has loaded; [roomId] is where they were
/// seen, for their name there.
Future<void> showUserProfile(
  BuildContext context, {
  required String account,
  required String userId,
  String? roomId,
  String? name,
  String? avatarUrl,
}) {
  final view = UserProfileView(
    account: account,
    userId: userId,
    roomId: roomId,
    name: name,
    avatarUrl: avatarUrl,
  );
  if (MediaQuery.sizeOf(context).width >= wideLayoutBreakpoint) {
    return showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(child: view),
        ),
      ),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => SingleChildScrollView(child: view),
  );
}

/// Someone's profile: picture, name, user ID (to copy), whether the user verified them, and
/// what can be done: message them, verify them, ignore (or unignore) and report them.
class UserProfileView extends ConsumerWidget {
  const UserProfileView({
    required this.account,
    required this.userId,
    this.roomId,
    this.name,
    this.avatarUrl,
    super.key,
  });

  final String account;
  final String userId;
  final String? roomId;
  final String? name;
  final String? avatarUrl;

  ProfileKey get _key => (account, userId, roomId);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider(_key)).value;
    final displayName = profile?.displayName ?? name ?? userId;
    final own = userId == account;
    final theme = Theme.of(context);
    final palette = context.oxi;
    final verified = profile?.verified;
    return Padding(
      key: const Key('profile'),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          MatrixAvatar(
            account: account,
            url: profile?.avatarUrl ?? avatarUrl,
            name: displayName,
            seed: userId,
            radius: 40,
          ),
          const SizedBox(height: 12),
          Text(
            displayName,
            key: const Key('profile.name'),
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: SelectableText(
                  userId,
                  key: const Key('profile.userId'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: palette.muted,
                  ),
                ),
              ),
              IconButton(
                key: const Key('profile.copyId'),
                tooltip: 'Copy user ID',
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.copy_rounded),
                onPressed: () => unawaited(_copyId(context)),
              ),
            ],
          ),
          if (!own && profile != null) ...[
            const SizedBox(height: 4),
            _VerifiedLine(verified: verified),
          ],
          if (profile?.ignored ?? false) ...[
            const SizedBox(height: 8),
            Text(
              'You ignore them: their messages and invites are hidden.',
              key: const Key('profile.ignoredNote'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: palette.muted),
            ),
          ],
          if (!own) ...[
            const SizedBox(height: 20),
            _Actions(
              account: account,
              userId: userId,
              name: displayName,
              profile: profile,
              onChanged: () => ref.invalidate(userProfileProvider(_key)),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _copyId(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    await Clipboard.setData(ClipboardData(text: userId));
    messenger?.showSnackBar(const SnackBar(content: Text('User ID copied')));
  }
}

class _VerifiedLine extends StatelessWidget {
  const _VerifiedLine({required this.verified});

  final bool? verified;

  @override
  Widget build(BuildContext context) {
    final muted = context.oxi.muted;
    final (icon, label) = switch (verified) {
      true => (Icons.verified_rounded, 'Verified'),
      false => (Icons.gpp_maybe_outlined, 'Not verified'),
      null => (Icons.shield_outlined, 'Can’t be verified yet'),
    };
    return Row(
      key: Key('profile.verified.$verified'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 16,
          color: verified ?? false
              ? Theme.of(context).colorScheme.onSurface
              : muted,
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: verified ?? false ? null : muted,
          ),
        ),
      ],
    );
  }
}

class _Actions extends ConsumerWidget {
  const _Actions({
    required this.account,
    required this.userId,
    required this.name,
    required this.profile,
    required this.onChanged,
  });

  final String account;
  final String userId;
  final String name;
  final UserProfile? profile;
  final VoidCallback onChanged;

  MatrixSession? _session(WidgetRef ref) =>
      ref.read(accountsProvider).value?.byId(account);

  Future<void> _message(BuildContext context, WidgetRef ref) async {
    final session = _session(ref);
    if (session == null) return;
    final router = GoRouter.of(context);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final room = session.dmWith(userId) ?? await session.createDm(userId);
      navigator.pop();
      router.go(Routes.room(room));
    } on MatrixFailure catch (failure) {
      messenger.showSnackBar(
        SnackBar(content: Text('Can’t open the chat: ${failure.kind.name}')),
      );
    }
  }

  Future<void> _verify(BuildContext context, WidgetRef ref) async {
    final session = _session(ref);
    if (session == null) return;
    await showDialog<void>(
      context: context,
      builder: (_) =>
          VerifyUserDialog(session: session, userId: userId, name: name),
    );
    onChanged();
  }

  Future<void> _ignore(BuildContext context, WidgetRef ref) async {
    final session = _session(ref);
    if (session == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final sure = await confirmIgnore(context, name);
    if (!sure) return;
    try {
      await session.ignoreUser(userId);
      messenger.showSnackBar(SnackBar(content: Text('$name is ignored')));
      afterIgnoreChange(ref);
    } on MatrixFailure catch (failure) {
      messenger.showSnackBar(
        SnackBar(content: Text('Can’t ignore: ${failure.kind.name}')),
      );
    }
    onChanged();
  }

  Future<void> _unignore(BuildContext context, WidgetRef ref) async {
    final session = _session(ref);
    if (session == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await session.unignoreUser(userId);
      messenger.showSnackBar(
        SnackBar(content: Text('$name is no longer ignored')),
      );
      afterIgnoreChange(ref);
    } on MatrixFailure catch (failure) {
      messenger.showSnackBar(
        SnackBar(content: Text('Can’t unignore: ${failure.kind.name}')),
      );
    }
    onChanged();
  }

  Future<void> _report(BuildContext context, WidgetRef ref) async {
    final session = _session(ref);
    if (session == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final report = await showDialog<ReportChoice>(
      context: context,
      builder: (_) => ReportDialog(
        title: 'Report $name?',
        note:
            'The admins of their server get your report, with your user ID and '
            'the reason you give.',
        ignoreLabel: (profile?.ignored ?? false) ? null : 'Also ignore $name',
      ),
    );
    if (report == null) return;
    try {
      await session.reportUser(userId, reason: report.reason);
      if (report.ignore) {
        await session.ignoreUser(userId);
        afterIgnoreChange(ref);
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            report.ignore
                ? 'Reported and ignored $name. Thank you.'
                : 'Reported $name. Thank you.',
          ),
        ),
      );
    } on MatrixFailure catch (failure) {
      messenger.showSnackBar(
        SnackBar(content: Text('Can’t report: ${failure.kind.name}')),
      );
    }
    onChanged();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ignored = profile?.ignored ?? false;
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          key: const Key('profile.message'),
          icon: const Icon(Icons.chat_bubble_outline_rounded),
          onPressed: () => unawaited(_message(context, ref)),
          label: const Text('Send message'),
        ),
        if (profile?.verified == false)
          OutlinedButton.icon(
            key: const Key('profile.verify'),
            icon: const Icon(Icons.verified_user_outlined),
            onPressed: () => unawaited(_verify(context, ref)),
            label: const Text('Verify'),
          ),
        if (ignored)
          OutlinedButton.icon(
            key: const Key('profile.unignore'),
            icon: const Icon(Icons.visibility_outlined),
            onPressed: () => unawaited(_unignore(context, ref)),
            label: const Text('Unignore'),
          )
        else
          OutlinedButton.icon(
            key: const Key('profile.ignore'),
            style: OxiButtons.destructive(context),
            icon: const Icon(Icons.block_rounded),
            onPressed: () => unawaited(_ignore(context, ref)),
            label: const Text('Ignore'),
          ),
        OutlinedButton.icon(
          key: const Key('profile.report'),
          style: OxiButtons.destructive(context),
          icon: const Icon(Icons.flag_outlined),
          onPressed: () => unawaited(_report(context, ref)),
          label: const Text('Report'),
        ),
      ],
    );
  }
}

/// After ignoring or unignoring someone: the SDK has dropped the cached timelines, so the open
/// ones are opened again, without (or with) their messages.
void afterIgnoreChange(WidgetRef ref) => ref.invalidate(roomTimelineProvider);

/// Asks whether to ignore [name], saying what it does; `true` to go ahead.
Future<bool> confirmIgnore(BuildContext context, String name) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Ignore $name?'),
        content: const Text(
          'Their messages and invites are hidden from you, on all your devices. '
          'They aren’t told. You can unignore them here or in Settings › Account.',
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('ignore.confirm'),
            style: OxiButtons.destructiveFilled(context),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Ignore'),
          ),
        ],
      ),
    ) ??
    false;

/// What the user chose in a [ReportDialog].
typedef ReportChoice = ({String? reason, bool ignore});

/// Asks to confirm a report, with an optional reason and, with [ignoreLabel], a box to ignore
/// the sender too. Pops with a [ReportChoice], or nothing when cancelled.
class ReportDialog extends StatefulWidget {
  const ReportDialog({
    required this.title,
    required this.note,
    this.ignoreLabel,
    super.key,
  });

  final String title;
  final String note;

  /// The ignore box's label; no box without one.
  final String? ignoreLabel;

  @override
  State<ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<ReportDialog> {
  final _reason = TextEditingController();
  var _ignore = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _confirm() {
    final reason = _reason.text.trim();
    Navigator.of(context).pop<ReportChoice>((
      reason: reason.isEmpty ? null : reason,
      ignore: _ignore,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final ignoreLabel = widget.ignoreLabel;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.note),
            const SizedBox(height: 8),
            TextField(
              key: const Key('report.reason'),
              controller: _reason,
              autofocus: true,
              maxLines: 3,
              minLines: 1,
              decoration: const InputDecoration(labelText: 'Reason (optional)'),
            ),
            if (ignoreLabel != null)
              CheckboxListTile(
                key: const Key('report.ignore'),
                value: _ignore,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(ignoreLabel),
                subtitle: const Text('Hide their messages and invites'),
                onChanged: (value) => setState(() => _ignore = value ?? false),
              ),
          ],
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('report.confirm'),
          style: OxiButtons.destructiveFilled(context),
          onPressed: _confirm,
          child: const Text('Report'),
        ),
      ],
    );
  }
}

/// Verifies another user by emoji: asks them in the direct chat, then the same steps as
/// verifying a device ([VerificationFlow]).
class VerifyUserDialog extends StatefulWidget {
  const VerifyUserDialog({
    required this.session,
    required this.userId,
    required this.name,
    super.key,
  });

  final MatrixSession session;
  final String userId;
  final String name;

  @override
  State<VerifyUserDialog> createState() => _VerifyUserDialogState();
}

class _VerifyUserDialogState extends State<VerifyUserDialog> {
  late final Future<DeviceVerification> _verification = widget.session
      .verifyUser(widget.userId);

  @override
  void dispose() {
    _verification.then((verification) => verification.close()).ignore();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
    key: const Key('verifyUser'),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: FutureBuilder(
          future: _verification,
          builder: (context, snapshot) => switch (snapshot) {
            AsyncSnapshot(:final DeviceVerification data) => VerificationFlow(
              verification: data,
              otherUser: widget.name,
              waitingText:
                  'Ask ${widget.name} to accept the request in your chat with '
                  'them. Then compare the emoji together, in person or on a call.',
              onFinished: () => Navigator.of(context).pop(),
            ),
            AsyncSnapshot(:final MatrixFailure error) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Can’t verify ${widget.name}: ${error.kind.name}',
                  key: const Key('verifyUser.error'),
                ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            ),
            _ => const Center(child: CircularProgressIndicator()),
          },
        ),
      ),
    ),
  );
}
