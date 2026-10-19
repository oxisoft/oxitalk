import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final diagnostics = ref.watch(diagnosticsProvider);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.go(Routes.chats)),
        title: const Text('Settings'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                child: Text(
                  'Diagnostics',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              SwitchListTile(
                key: const Key('settings.collectLogs'),
                title: const Text('Collect logs'),
                subtitle: const Text(
                  'Saves technical logs on this device to help find problems. '
                  'They hold account and device IDs, never message contents '
                  'or keys, and are kept for a week.',
                ),
                value: diagnostics.collectLogs,
                onChanged: (on) async {
                  await diagnostics.setCollectLogs(on: on);
                  if (mounted) setState(() {});
                },
              ),
              ListTile(
                title: const Text('Logs folder'),
                subtitle: SelectableText(diagnostics.logDir),
                trailing: IconButton(
                  tooltip: 'Copy path',
                  icon: const Icon(Icons.copy_rounded),
                  onPressed: () {
                    unawaited(
                      Clipboard.setData(
                        ClipboardData(text: diagnostics.logDir),
                      ),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Path copied')),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
