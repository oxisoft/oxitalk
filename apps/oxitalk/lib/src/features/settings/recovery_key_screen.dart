import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../matrix/api/matrix.dart';

/// Whether [RecoveryKeyScreen] sets recovery up or changes its key.
enum RecoveryKeyAction { setUp, change }

/// Opens [RecoveryKeyScreen] for [account] over everything; completes `true` once the user
/// has saved the new key and finished.
Future<bool> showRecoveryKeyScreen(
  BuildContext context,
  String account,
  RecoveryKeyAction action,
) async =>
    await Navigator.of(context, rootNavigator: true).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => RecoveryKeyScreen(account: account, action: action),
      ),
    ) ??
    false;

enum _Step { working, failed, reveal, confirm }

/// Makes a new recovery key for [account] (setting recovery up, or changing the key), shows it
/// once, and asks the user to type its last group back before Done, as Element X does. The
/// key lives only in this screen's state, which forgets it when the screen closes; it is
/// never logged, and written only where the user saves it.
class RecoveryKeyScreen extends ConsumerStatefulWidget {
  const RecoveryKeyScreen({
    required this.account,
    required this.action,
    super.key,
  });

  final String account;
  final RecoveryKeyAction action;

  @override
  ConsumerState<RecoveryKeyScreen> createState() => _RecoveryKeyScreenState();
}

class _RecoveryKeyScreenState extends ConsumerState<RecoveryKeyScreen> {
  var _step = _Step.working;
  String? _key;
  RecoveryProgress _progress = const RecoveryPreparing();
  String? _error;
  final _check = TextEditingController();

  @override
  void initState() {
    super.initState();
    unawaited(_make());
  }

  @override
  void dispose() {
    _key = null;
    _check.dispose();
    super.dispose();
  }

  /// The key's last group of characters, which the user types back.
  String get _lastGroup => _key?.trim().split(RegExp(r'\s+')).last ?? '';

  Future<void> _make() async {
    final session = ref.read(accountsProvider).value?.byId(widget.account);
    setState(() {
      _step = _Step.working;
      _error = null;
    });
    if (session == null) {
      setState(() {
        _step = _Step.failed;
        _error = 'This account is no longer logged in.';
      });
      return;
    }
    try {
      final key = switch (widget.action) {
        RecoveryKeyAction.setUp => await session.enableRecovery(
          onProgress: (progress) {
            if (mounted) setState(() => _progress = progress);
          },
        ),
        RecoveryKeyAction.change => await session.resetRecoveryKey(),
      };
      if (!mounted) return;
      setState(() {
        _key = key;
        _step = _Step.reveal;
      });
    } on MatrixFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _step = _Step.failed;
        _error = switch (failure.kind) {
          FailureKind.network =>
            'Can’t reach the server. Check your connection.',
          FailureKind.recoveryNotSetUp => 'Recovery is not set up.',
          _ => failure.message.isEmpty ? failure.kind.name : failure.message,
        };
      });
    }
  }

  Future<void> _copy() async {
    final key = _key;
    if (key == null) return;
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: key));
    messenger.showSnackBar(
      const SnackBar(content: Text('Recovery key copied')),
    );
  }

  Future<void> _save() async {
    final key = _key;
    if (key == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final files = ref.read(fileActionsProvider);
    final path = await files.askSavePath('OxiTalk recovery key.txt');
    if (path == null) return;
    try {
      await files.writeText(
        path,
        'OxiTalk recovery key for ${widget.account}\n\n$key\n',
      );
      messenger.showSnackBar(SnackBar(content: Text('Saved to $path')));
    } on Exception {
      messenger.showSnackBar(
        const SnackBar(content: Text('Can’t save the file there')),
      );
    }
  }

  /// Leaving before Done: the new key is already the account's, so it is lost unless saved.
  Future<void> _leave() async {
    if (_step != _Step.reveal && _step != _Step.confirm) {
      Navigator.of(context).pop(false);
      return;
    }
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave without the key?'),
        content: const Text(
          'Your new recovery key won’t be shown again. Without it, you can only '
          'make a new one.',
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Stay'),
          ),
          FilledButton(
            key: const Key('recovery.leave'),
            style: OxiButtons.destructiveFilled(context),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (leave == true && mounted) Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _step == _Step.failed,
    onPopInvokedWithResult: (popped, _) {
      if (!popped) unawaited(_leave());
    },
    child: Scaffold(
      appBar: AppBar(
        leading: IconButton(
          key: const Key('recovery.close'),
          tooltip: 'Close',
          icon: const Icon(Icons.close_rounded),
          onPressed: _step == _Step.working ? null : _leave,
        ),
        title: Text(switch (widget.action) {
          RecoveryKeyAction.setUp => 'Set up recovery',
          RecoveryKeyAction.change => 'Change recovery key',
        }),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: switch (_step) {
              _Step.working => _working(context),
              _Step.failed => _failed(context),
              _Step.reveal => _reveal(context),
              _Step.confirm => _confirm(context),
            },
          ),
        ),
      ),
    ),
  );

  Widget _working(BuildContext context) => Column(
    key: const Key('recovery.working'),
    mainAxisSize: MainAxisSize.min,
    children: [
      const CircularProgressIndicator(),
      const SizedBox(height: 24),
      Text(
        switch ((widget.action, _progress)) {
          (RecoveryKeyAction.change, _) => 'Making a new recovery key…',
          (_, RecoveryBackingUp(:final backedUp, :final total)) =>
            'Backing up your message keys: $backedUp of $total',
          _ => 'Setting up recovery…',
        },
        key: const Key('recovery.progress'),
        textAlign: TextAlign.center,
      ),
    ],
  );

  Widget _failed(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'That didn’t work',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 8),
      Text(
        _error ?? '',
        key: const Key('recovery.error'),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 24),
      FilledButton(
        key: const Key('recovery.retry'),
        onPressed: _make,
        child: const Text('Try again'),
      ),
      const SizedBox(height: 12),
      OutlinedButton(
        onPressed: () => Navigator.of(context).pop(false),
        child: const Text('Close'),
      ),
    ],
  );

  Widget _reveal(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.oxi;
    final canSave = ref.read(fileActionsProvider).canAskSavePath;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.key_rounded, size: 56, color: theme.colorScheme.primary),
        const SizedBox(height: 16),
        Text(
          'Save your recovery key',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          'Keep it somewhere safe, like a password manager. With it, a new '
          'device can verify itself and read your encrypted messages. It '
          'can’t be shown again: neither the server nor OxiTalk keeps it.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        if (widget.action == RecoveryKeyAction.change) ...[
          const SizedBox(height: 8),
          Text(
            'Your old recovery key no longer works.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: OxiButtons.danger(theme.brightness),
            ),
          ),
        ],
        const SizedBox(height: 24),
        DecoratedBox(
          decoration: ShapeDecoration(
            color: palette.panel2,
            shape: OxiShapes.cut(6, side: BorderSide(color: palette.line)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SelectableText(
              _key ?? '',
              key: const Key('recovery.key'),
              textAlign: TextAlign.center,
              style: codeStyle.copyWith(
                fontSize: 18,
                height: 1.6,
                letterSpacing: 1,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              key: const Key('recovery.copy'),
              onPressed: _copy,
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Copy'),
            ),
            if (canSave)
              OutlinedButton.icon(
                key: const Key('recovery.save'),
                onPressed: _save,
                icon: const Icon(Icons.save_alt_rounded),
                label: const Text('Save to file'),
              ),
          ],
        ),
        const SizedBox(height: 24),
        FilledButton(
          key: const Key('recovery.continue'),
          onPressed: () => setState(() => _step = _Step.confirm),
          child: const Text('I’ve saved it'),
        ),
      ],
    );
  }

  Widget _confirm(BuildContext context) {
    final theme = Theme.of(context);
    final matches =
        _check.text.trim().toLowerCase() == _lastGroup.toLowerCase() &&
        _lastGroup.isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Check your recovery key',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          'Type the last group of ${_lastGroup.length} characters of the key '
          'you saved.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        TextField(
          key: const Key('recovery.check'),
          controller: _check,
          autofocus: true,
          autocorrect: false,
          enableSuggestions: false,
          textAlign: TextAlign.center,
          style: codeStyle.copyWith(fontSize: 18),
          decoration: const InputDecoration(
            labelText: 'Last group',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) {
            if (matches) Navigator.of(context).pop(true);
          },
        ),
        const SizedBox(height: 24),
        FilledButton(
          key: const Key('recovery.done'),
          onPressed: matches ? () => Navigator.of(context).pop(true) : null,
          child: const Text('Done'),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          key: const Key('recovery.showAgain'),
          onPressed: () => setState(() {
            _check.clear();
            _step = _Step.reveal;
          }),
          child: const Text('Show the key again'),
        ),
      ],
    );
  }
}
