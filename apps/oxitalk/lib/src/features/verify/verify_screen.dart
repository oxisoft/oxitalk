import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../matrix/api/matrix.dart';

/// "Confirm it's you": an unverified device sees only this until it is verified, with another
/// device or the recovery key, or logged out.
class VerifyScreen extends ConsumerStatefulWidget {
  const VerifyScreen({super.key});

  @override
  ConsumerState<VerifyScreen> createState() => _VerifyScreenState();
}

enum _Mode { choose, recoveryKey, otherDevice }

class _VerifyScreenState extends ConsumerState<VerifyScreen> {
  var _mode = _Mode.choose;
  DeviceVerification? _verification;
  final _key = TextEditingController();
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _verification?.close();
    _key.dispose();
    super.dispose();
  }

  MatrixSession? get _session => ref.read(accountsProvider).value?.active;

  Future<void> _useOtherDevice() async {
    final session = _session;
    if (session == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final verification = await session.requestVerification();
      if (!mounted) return verification.close();
      setState(() {
        _verification = verification;
        _mode = _Mode.otherDevice;
      });
    } on MatrixFailure catch (failure) {
      if (mounted) setState(() => _error = verifyError(failure));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _recover() async {
    final session = _session;
    final key = _key.text.trim();
    if (session == null || key.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Verified now: the router leaves this screen.
      await session.recover(key);
    } on MatrixFailure catch (failure) {
      if (mounted) setState(() => _error = verifyError(failure));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _back() {
    _verification?.close();
    setState(() {
      _verification = null;
      _mode = _Mode.choose;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: switch (_mode) {
            _Mode.choose => _choose(context),
            _Mode.recoveryKey => _recoveryKey(context),
            _Mode.otherDevice => VerificationFlow(
              verification: _verification!,
              onFinished: _back,
            ),
          },
        ),
      ),
    ),
  );

  Widget _choose(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Icon(
        Icons.verified_user_rounded,
        size: 72,
        color: OxiColors.accent,
      ),
      const SizedBox(height: 16),
      Text(
        'Confirm it’s you',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 8),
      if (ref.watch(activeAccountProvider) case final account?) ...[
        Text(
          account,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
      ],
      Text(
        'Verify this device to read your encrypted messages and to show '
        'others it’s really you.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      if (_error case final error?) ...[
        const SizedBox(height: 12),
        _ErrorText(error),
      ],
      const SizedBox(height: 32),
      FilledButton.icon(
        key: const Key('verify.otherDevice'),
        onPressed: _busy ? null : _useOtherDevice,
        icon: const Icon(Icons.devices_rounded),
        label: const Text('Use another device'),
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        key: const Key('verify.recoveryKey'),
        onPressed: _busy
            ? null
            : () => setState(() {
                _mode = _Mode.recoveryKey;
                _error = null;
              }),
        icon: const Icon(Icons.key_rounded),
        label: const Text('Enter recovery key'),
      ),
      const SizedBox(height: 24),
      TextButton(
        onPressed: () {
          if (_session case final session?) {
            unawaited(
              ref.read(accountsProvider.notifier).logout(session.userId),
            );
          }
        },
        child: const Text('Log out'),
      ),
    ],
  );

  Widget _recoveryKey(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Enter recovery key',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 8),
      Text(
        'Your recovery key, or your security phrase if you set one.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      const SizedBox(height: 24),
      TextField(
        key: const Key('verify.key'),
        controller: _key,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Recovery key or security phrase',
          border: OutlineInputBorder(),
        ),
        autocorrect: false,
        enableSuggestions: false,
        onSubmitted: (_) => _recover(),
      ),
      if (_error case final error?) ...[
        const SizedBox(height: 12),
        _ErrorText(error),
      ],
      const SizedBox(height: 24),
      FilledButton(
        key: const Key('verify.keySubmit'),
        onPressed: _busy ? null : _recover,
        child: _busy
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Continue'),
      ),
      const SizedBox(height: 12),
      TextButton(onPressed: _busy ? null : _back, child: const Text('Back')),
    ],
  );
}

String verifyError(MatrixFailure failure) => switch (failure.kind) {
  FailureKind.wrongRecoveryKey => 'That recovery key isn’t right.',
  FailureKind.recoveryNotSetUp =>
    'Your account has no recovery key. Use another device instead.',
  FailureKind.network => 'Can’t reach the server. Check your connection.',
  _ =>
    'Verification failed: ${failure.message.isEmpty ? failure.kind.name : failure.message}',
};

/// One verification with another device, step by step. [onFinished] runs when the user leaves
/// it: after it is done or cancelled.
class VerificationFlow extends StatelessWidget {
  const VerificationFlow({
    required this.verification,
    required this.onFinished,
    super.key,
  });

  final DeviceVerification verification;
  final VoidCallback onFinished;

  @override
  Widget build(BuildContext context) => StreamBuilder(
    stream: verification.steps,
    builder: (context, snapshot) => switch (snapshot.data) {
      null || VerificationWaiting() => _Waiting(
        title: 'Waiting for your other device',
        text:
            'Open OxiTalk or Element where you’re already signed in and '
            'accept the request.',
        onCancel: () => _cancel(verification),
      ),
      VerificationIncoming() => _Message(
        icon: Icons.devices_rounded,
        title: 'Verification request',
        text: 'Another of your devices wants to verify with this one.',
        actions: [
          TextButton(
            onPressed: () => _cancel(verification),
            child: const Text('Decline'),
          ),
          FilledButton(
            onPressed: () => unawaited(verification.accept()),
            child: const Text('Accept'),
          ),
        ],
      ),
      VerificationCompare(:final emojis, :final decimals) => _Compare(
        emojis: emojis,
        decimals: decimals,
        onMatch: () => unawaited(verification.confirm()),
        onMismatch: () => unawaited(verification.mismatch()),
      ),
      VerificationConfirmed() => _Waiting(
        title: 'Almost there',
        text: 'Waiting for the other device to confirm.',
        onCancel: () => _cancel(verification),
      ),
      VerificationDone() => _Message(
        icon: Icons.verified_rounded,
        title: 'Device verified',
        text: 'Your encrypted messages will now arrive on both devices.',
        actions: [
          FilledButton(
            key: const Key('verify.done'),
            onPressed: onFinished,
            child: const Text('Done'),
          ),
        ],
      ),
      VerificationCancelled(:final reason, :final byUs) => _Message(
        icon: Icons.cancel_rounded,
        title: 'Verification cancelled',
        text: byUs ? reason : 'The other device cancelled: $reason',
        actions: [
          FilledButton(onPressed: onFinished, child: const Text('Back')),
        ],
      ),
    },
  );

  static void _cancel(DeviceVerification verification) =>
      unawaited(verification.cancel().catchError((Object _) {}));
}

class _Waiting extends StatelessWidget {
  const _Waiting({
    required this.title,
    required this.text,
    required this.onCancel,
  });

  final String title;
  final String text;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const CircularProgressIndicator(),
      const SizedBox(height: 24),
      Text(
        title,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 8),
      Text(text, textAlign: TextAlign.center),
      const SizedBox(height: 24),
      TextButton(onPressed: onCancel, child: const Text('Cancel')),
    ],
  );
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.text,
    required this.actions,
  });

  final IconData icon;
  final String title;
  final String text;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 64, color: OxiColors.accent),
      const SizedBox(height: 16),
      Text(
        title,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 8),
      Text(text, textAlign: TextAlign.center),
      const SizedBox(height: 24),
      Wrap(spacing: 12, alignment: WrapAlignment.center, children: actions),
    ],
  );
}

class _Compare extends StatelessWidget {
  const _Compare({
    required this.emojis,
    required this.decimals,
    required this.onMatch,
    required this.onMismatch,
  });

  final List<VerificationEmoji> emojis;
  final List<int> decimals;
  final VoidCallback onMatch;
  final VoidCallback onMismatch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          emojis.isEmpty ? 'Compare numbers' : 'Compare emoji',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          emojis.isEmpty
              ? 'Check that the other device shows the same numbers.'
              : 'Check that the other device shows the same emoji, in the '
                    'same order.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        if (emojis.isEmpty)
          Text(decimals.join('  '), style: theme.textTheme.headlineMedium)
        else
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 12,
            children: [
              for (final emoji in emojis)
                SizedBox(
                  width: 76,
                  child: Column(
                    children: [
                      Text(emoji.symbol, style: const TextStyle(fontSize: 36)),
                      const SizedBox(height: 4),
                      Text(
                        emoji.description,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        const SizedBox(height: 32),
        Wrap(
          spacing: 12,
          alignment: WrapAlignment.center,
          children: [
            OutlinedButton(
              key: const Key('verify.mismatch'),
              onPressed: onMismatch,
              child: const Text('They don’t match'),
            ),
            FilledButton(
              key: const Key('verify.match'),
              onPressed: onMatch,
              child: const Text('They match'),
            ),
          ],
        ),
      ],
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    textAlign: TextAlign.center,
    style: TextStyle(color: Theme.of(context).colorScheme.error),
  );
}
