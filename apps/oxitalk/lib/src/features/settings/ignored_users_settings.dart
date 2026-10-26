import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../matrix/api/matrix.dart';
import '../people/people_providers.dart';
import '../people/user_profile.dart';
import 'settings_heading.dart';

/// The users [account] ignores, in Settings › Account, each with Unignore; follows changes
/// made here and on the account's other devices.
class IgnoredUsersSettings extends ConsumerWidget {
  const IgnoredUsersSettings({required this.account, super.key});

  final String account;

  Future<void> _unignore(
    BuildContext context,
    WidgetRef ref,
    String userId,
  ) async {
    final session = ref.read(accountsProvider).value?.byId(account);
    if (session == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await session.unignoreUser(userId);
      messenger.showSnackBar(
        SnackBar(content: Text('$userId is no longer ignored')),
      );
      afterIgnoreChange(ref);
    } on MatrixFailure catch (failure) {
      messenger.showSnackBar(
        SnackBar(content: Text('Can’t unignore: ${failure.kind.name}')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ignored = ref.watch(ignoredUsersProvider(account));
    return Column(
      key: const Key('settings.ignored'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SettingsHeading(
          'Ignored users',
          subtitle:
              'Their messages and invites are hidden on all your devices.',
        ),
        switch (ignored) {
          AsyncValue(value: final users?) when users.isEmpty => const ListTile(
            key: Key('ignored.none'),
            title: Text('You don’t ignore anyone.'),
          ),
          AsyncValue(value: final users?) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final userId in users)
                ListTile(
                  key: Key('ignored.row.$userId'),
                  title: Text(
                    userId,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: OutlinedButton(
                    key: Key('ignored.unignore.$userId'),
                    onPressed: () => unawaited(_unignore(context, ref, userId)),
                    child: const Text('Unignore'),
                  ),
                ),
            ],
          ),
          AsyncValue(hasError: true) => const ListTile(
            title: Text('Can’t load the ignored users.'),
          ),
          _ => const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
        },
      ],
    );
  }
}
