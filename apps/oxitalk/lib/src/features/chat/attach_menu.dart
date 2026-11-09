import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';

/// Where the files to attach come from.
enum AttachSource { gallery, photo, video, file }

/// On a touch screen, what the paperclip opens, as other phone messengers do: a sheet from
/// the bottom that asks what to attach first. `null` if the user closes it.
Future<AttachSource?> showAttachMenu(BuildContext context) {
  unawaited(HapticFeedback.selectionClick());
  return showModalBottomSheet<AttachSource>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => const AttachMenu(),
  );
}

/// The sheet [showAttachMenu] shows. It pops with the chosen [AttachSource].
class AttachMenu extends StatelessWidget {
  const AttachMenu({super.key});

  static const _items = [
    (AttachSource.gallery, Icons.photo_library_outlined, 'Gallery'),
    (AttachSource.photo, Icons.photo_camera_outlined, 'Camera'),
    (AttachSource.video, Icons.videocam_outlined, 'Video'),
    (AttachSource.file, Icons.insert_drive_file_outlined, 'File'),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = context.oxi;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (final (source, icon, label) in _items)
              Expanded(
                child: InkWell(
                  key: Key('attach.${source.name}'),
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => Navigator.of(context).pop(source),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: palette.panel2,
                          foregroundColor: palette.text,
                          child: Icon(icon, size: 26),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          label,
                          style: TextStyle(color: palette.text, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
