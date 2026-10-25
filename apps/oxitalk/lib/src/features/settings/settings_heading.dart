import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// A heading over a group of settings, with a muted line under it when the group needs
/// saying what it is about (one account, or all of them).
class SettingsHeading extends StatelessWidget {
  const SettingsHeading(this.text, {this.subtitle, super.key});

  final String text;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = this.subtitle;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: context.oxi.muted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
