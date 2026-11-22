import 'package:flutter/widgets.dart';

/// Decoded pictures Flutter keeps for showing again, at most: half of Flutter's default
/// 100 MB, and 300 instead of 1000. Pictures on screen don't count, and each is decoded at
/// the size it shows, so this is plenty for scrolling back and forth in a chat.
const imageCacheBytes = 48 << 20;
const imageCacheCount = 300;

AppLifecycleListener? _lifecycle;

/// Limits the pictures Flutter keeps decoded (on the graphics card) and lets them all go
/// when the window is hidden or minimised; they decode again from memory when it shows.
void limitImageMemory() {
  PaintingBinding.instance.imageCache
    ..maximumSizeBytes = imageCacheBytes
    ..maximumSize = imageCacheCount;
  _lifecycle ??= AppLifecycleListener(
    onHide: () => PaintingBinding.instance.imageCache.clear(),
  );
}
