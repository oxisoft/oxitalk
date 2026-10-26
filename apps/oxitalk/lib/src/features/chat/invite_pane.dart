import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
import '../../matrix/api/matrix.dart';
import '../../ui/avatar.dart';
import '../chats/membership_actions.dart';

/// What the invitation to a room of an account shows: (account, room ID). Asked again
/// while the inviter isn't known yet: the invitation's details arrive a moment after it.
final inviteDetailsProvider = FutureProvider.autoDispose
    .family<InviteDetails, (String, String)>((ref, key) async {
      final (account, roomId) = key;
      final session = ref.watch(accountsProvider).value?.byId(account);
      if (session == null) {
        throw const MatrixFailure(FailureKind.sessionExpired);
      }
      final details = await session.inviteDetails(roomId);
      if (details.inviterId == null) {
        final retry = Timer(const Duration(seconds: 2), ref.invalidateSelf);
        ref.onDispose(retry.cancel);
      }
      return details;
    });

/// An invitation in the chat's place: the room (or person) it is to, who sent it, and
/// Accept or Decline. Nothing is joined until the user accepts.
class InvitePane extends ConsumerWidget {
  const InvitePane({
    required this.account,
    required this.room,
    required this.showBack,
    super.key,
  });

  final String account;
  final Room room;
  final bool showBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final details = ref.watch(inviteDetailsProvider((account, room.id))).value;
    final theme = Theme.of(context);
    final palette = context.oxi;
    final isDm = details?.isDm ?? room.isDm;
    final name = details?.name ?? room.name;
    final topic = details?.topic;
    final inviterId = details?.inviterId;
    final inviterName = details?.inviterName ?? inviterId;
    final actions = MembershipActions(context, ref, account);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: showBack
            ? BackButton(onPressed: () => context.go(Routes.chats))
            : null,
        title: Text(isDm ? 'Chat invitation' : 'Room invitation'),
      ),
      body: ColoredBox(
        color: context.oxi.wallpaper,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                key: const Key('invite.preview'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  MatrixAvatar(
                    account: account,
                    url: details?.avatarUrl ?? room.avatarUrl,
                    name: name,
                    seed: room.id,
                    radius: 44,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    name,
                    key: const Key('invite.name'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (details?.alias case final alias?)
                    Text(
                      alias,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: palette.muted,
                      ),
                    ),
                  if (topic != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      topic,
                      key: const Key('invite.topic'),
                      textAlign: TextAlign.center,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if ((details?.joinedMembers ?? 0) > 1 && !isDm) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${details!.joinedMembers} members',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: palette.muted,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  if (inviterId != null)
                    Row(
                      key: const Key('invite.inviter'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        MatrixAvatar(
                          account: account,
                          url: details?.inviterAvatarUrl,
                          name: inviterName ?? inviterId,
                          seed: inviterId,
                          radius: 14,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: inviterName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                TextSpan(
                                  text: isDm
                                      ? ' wants to chat with you'
                                      : ' invited you to join',
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  else
                    Text(
                      isDm
                          ? 'You’re invited to a direct chat'
                          : 'You’re invited to join',
                      style: TextStyle(color: palette.muted),
                    ),
                  if (inviterName != null && inviterName != inviterId)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        inviterId!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: palette.muted,
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      OutlinedButton(
                        key: const Key('invite.decline'),
                        style: OxiButtons.destructive(context),
                        onPressed: () =>
                            unawaited(actions.decline(room.id, name: name)),
                        child: const Text('Decline'),
                      ),
                      FilledButton(
                        key: const Key('invite.accept'),
                        onPressed: () => unawaited(actions.accept(room.id)),
                        child: const Text('Accept'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
