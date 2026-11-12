import 'dart:async';

// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/file_actions.dart';
import '../../app/providers.dart';
import '../../matrix/api/matrix.dart';
import '../../ui/format.dart';

/// Shows [files] with a caption field and, for photos, a Compress switch; on Send, sends
/// them to the chat, or with [thread] into that thread. The caption goes with the first file
/// and starts as [caption]. Returns whether the user pressed Send.
Future<bool> confirmAndSendFiles(
  BuildContext context,
  WidgetRef ref, {
  required String account,
  required String roomId,
  required List<PendingFile> files,
  String? thread,
  String caption = '',
}) async {
  if (files.isEmpty) return false;
  final messenger = ScaffoldMessenger.of(context);
  final choice = await showDialog<({String caption, bool compress})>(
    context: context,
    builder: (_) => _SendFilesDialog(files: files, caption: caption),
  );
  final timeline = ref
      .read(roomTimelineProvider(account, roomId, thread: thread))
      .value;
  final markdown = ref.read(useMarkdownProvider);
  if (choice == null || timeline == null) return false;
  for (final (index, file) in files.indexed) {
    try {
      await timeline.sendFile(
        file.bytes,
        filename: file.name,
        mimeType: file.mimeType,
        caption: index == 0 && choice.caption.isNotEmpty
            ? choice.caption
            : null,
        compress: choice.compress,
        markdown: markdown,
      );
    } on MatrixFailure catch (failure) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Can’t send ${file.name}: ${failure.kind.name}'),
        ),
      );
    }
  }
  return true;
}

class _SendFilesDialog extends StatefulWidget {
  const _SendFilesDialog({required this.files, this.caption = ''});

  final List<PendingFile> files;

  /// What the caption field starts with: the message box's draft when an image is pasted.
  final String caption;

  @override
  State<_SendFilesDialog> createState() => _SendFilesDialogState();
}

class _SendFilesDialogState extends State<_SendFilesDialog> {
  late final _caption = TextEditingController(text: widget.caption);
  var _compress = true;

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  void _send() =>
      Navigator.of(context)
          .pop((caption: _caption.text.trim(), compress: _compress));

  @override
  Widget build(BuildContext context) {
    final files = widget.files;
    final images = files.where((file) => file.isImage).length;
    return AlertDialog(
      key: const Key('sendFiles'),
      title: Text(
        files.length == 1
            ? (files.single.isImage ? 'Send photo' : 'Send file')
            : 'Send ${files.length} files',
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final file in files) _Preview(file: file),
              const SizedBox(height: 8),
              // Enter sends, as in the message box; Shift+Enter makes a new line.
              CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.enter): _send,
                  const SingleActivator(LogicalKeyboardKey.numpadEnter): _send,
                },
                child: TextField(
                  key: const Key('send.caption'),
                  controller: _caption,
                  autofocus: true,
                  minLines: 1,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Caption'),
                ),
              ),
            ],
          ),
        ),
      ),
      // One row: Compress at the start, level with Cancel and Send at the end.
      actions: [
        Row(
          children: [
            // Made smaller rather than pushing the buttons out on a phone.
            Expanded(
              child: images > 0
                  ? Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: _CompressToggle(
                          value: _compress,
                          onChanged: (on) => setState(() => _compress = on),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              key: const Key('send.confirm'),
              onPressed: _send,
              child: const Text('Send'),
            ),
          ],
        ),
      ],
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.file});

  final PendingFile file;

  @override
  Widget build(BuildContext context) {
    final details = Text(
      '${file.name} · ${fileSize(file.bytes.length)}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodySmall,
    );
    if (file.isImage) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: Image.memory(
                  file.bytes,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) =>
                      const Icon(Icons.broken_image_outlined, size: 48),
                ),
              ),
            ),
            details,
          ],
        ),
      );
    }
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.insert_drive_file_outlined),
      title: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(fileSize(file.bytes.length)),
    );
  }
}

/// Compress as a small switch with a short label at the dialog's bottom left; the tooltip
/// says what it does.
class _CompressToggle extends StatelessWidget {
  const _CompressToggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Tooltip(
    message:
        'Big photos are made smaller (2048 px, JPEG). Off sends the original '
        'file.',
    child: InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Transform.scale(
              scale: 0.7,
              child: Switch(
                key: const Key('send.compress'),
                value: value,
                onChanged: onChanged,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            Text('Compress', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    ),
  );
}
