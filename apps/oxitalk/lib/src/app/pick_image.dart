import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

/// An image file the user picked.
final class PickedImage {
  const PickedImage(this.bytes, this.mimeType);

  final Uint8List bytes;

  /// Like `image/png`.
  final String mimeType;
}

/// Asks the user for an image file; `null` if they cancel.
typedef PickImage = Future<PickedImage?> Function();

const _types = {
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'gif': 'image/gif',
  'webp': 'image/webp',
};

/// [PickImage] with the platform's file dialog.
Future<PickedImage?> pickImageFile() async {
  final file = await openFile(
    acceptedTypeGroups: [
      XTypeGroup(
        label: 'Images',
        extensions: _types.keys.toList(),
        mimeTypes: _types.values.toSet().toList(),
        uniformTypeIdentifiers: const ['public.image'],
      ),
    ],
  );
  if (file == null) return null;
  final extension = file.name.split('.').last.toLowerCase();
  return PickedImage(
    await file.readAsBytes(),
    file.mimeType ?? _types[extension] ?? 'application/octet-stream',
  );
}
