import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';

import '../ui/box_sized_image.dart';

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

/// Files up to this size are kept as they are by [shrinkPicture].
const _smallPicture = 256 * 1024;

/// [image] scaled down to fill a square of [side] pixels (its shape kept), as PNG, for a
/// picture that is only ever shown small and is kept on this device. As it is when the file
/// is small already, a GIF (it may move), or can't be decoded.
Future<Uint8List> shrinkPicture(PickedImage image, {int side = 256}) async {
  if (image.bytes.length <= _smallPicture || image.mimeType == 'image/gif') {
    return image.bytes;
  }
  try {
    final buffer = await ui.ImmutableBuffer.fromUint8List(image.bytes);
    final codec = await ui.instantiateImageCodecWithSize(
      buffer,
      getTargetSize: (width, height) => boxTargetSize(
        width,
        height,
        boxWidth: side,
        boxHeight: side,
        cover: true,
      ),
    );
    final frame = await codec.getNextFrame();
    final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    frame.image.dispose();
    codec.dispose();
    if (png == null || png.lengthInBytes >= image.bytes.length) {
      return image.bytes;
    }
    return png.buffer.asUint8List();
  } on Object {
    return image.bytes;
  }
}
