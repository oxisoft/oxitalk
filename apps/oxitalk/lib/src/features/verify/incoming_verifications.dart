import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../matrix/api/matrix.dart';
import 'verify_screen.dart';

/// Shows a request from another device of any of the accounts as a dialog, wherever the user
/// is.
class IncomingVerifications extends ConsumerWidget {
  const IncomingVerifications({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions =
        ref.watch(accountsProvider).value?.sessions ?? const <MatrixSession>[];
    for (final session in sessions) {
      ref.listen(verificationRequestsProvider(session.userId), (_, next) {
        final request = next.value;
        final context = rootNavigatorKey.currentContext;
        if (request == null || context == null) return;
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => _IncomingDialog(session: session, request: request),
        ).ignore();
      });
    }
    return child;
  }
}

class _IncomingDialog extends StatefulWidget {
  const _IncomingDialog({required this.session, required this.request});

  final MatrixSession session;
  final VerificationRequest request;

  @override
  State<_IncomingDialog> createState() => _IncomingDialogState();
}

class _IncomingDialogState extends State<_IncomingDialog> {
  late final Future<DeviceVerification> _verification = widget.session
      .openVerification(widget.request.flowId);

  @override
  void dispose() {
    _verification.then((verification) => verification.close()).ignore();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: FutureBuilder(
          future: _verification,
          builder: (context, snapshot) => switch (snapshot) {
            AsyncSnapshot(:final DeviceVerification data) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.session.userId,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                Text(
                  widget.request.deviceName ?? widget.request.deviceId,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                VerificationFlow(
                  verification: data,
                  onFinished: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            AsyncSnapshot(hasError: true) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('This verification request is no longer valid.'),
                const SizedBox(height: 16),
                FilledButton(
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
