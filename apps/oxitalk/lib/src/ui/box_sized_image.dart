import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// [image] decoded with only the pixels a box of [width] × [height] device pixels needs: with
/// [cover], enough to fill the box as [BoxFit.cover] does, else to fit in it as
/// [BoxFit.contain] does; never more than the image has. A 12-megapixel photo shown as a
/// small preview then takes a few hundred kilobytes of graphics memory instead of 48 MB.
///
/// Unlike [ResizeImage], it keeps the image's shape and still fills a box of another shape.
@immutable
class BoxSizedImage extends ImageProvider<BoxSizedImageKey> {
  const BoxSizedImage(
    this.image, {
    required this.width,
    required this.height,
    this.cover = true,
  });

  final ImageProvider<Object> image;
  final int width;
  final int height;
  final bool cover;

  @override
  bool operator ==(Object other) =>
      other is BoxSizedImage &&
      other.image == image &&
      other.width == width &&
      other.height == height &&
      other.cover == cover;

  @override
  int get hashCode => Object.hash(image, width, height, cover);

  @override
  Future<BoxSizedImageKey> obtainKey(ImageConfiguration configuration) {
    // Synchronous when the wrapped image's key is (as MemoryImage's is), so a cached image
    // shows in the first frame.
    Completer<BoxSizedImageKey>? completer;
    SynchronousFuture<BoxSizedImageKey>? result;
    unawaited(
      image
          .obtainKey(configuration)
          .then(
            (key) {
              final sized = BoxSizedImageKey._(key, width, height, cover);
              if (completer case final waiting?) {
                waiting.complete(sized);
              } else {
                result = SynchronousFuture(sized);
              }
            },
            onError: (Object error, StackTrace stack) {
              (completer ??= Completer()).completeError(error, stack);
            },
          ),
    );
    if (result case final result?) return result;
    return (completer ??= Completer()).future;
  }

  @override
  ImageStreamCompleter loadImage(
    BoxSizedImageKey key,
    ImageDecoderCallback decode,
  ) => image.loadImage(
    key._image,
    (buffer, {getTargetSize}) => decode(
      buffer,
      getTargetSize: (imageWidth, imageHeight) => boxTargetSize(
        imageWidth,
        imageHeight,
        boxWidth: width,
        boxHeight: height,
        cover: cover,
      ),
    ),
  );
}

/// What [BoxSizedImage] caches an image under: the wrapped image's key and the box.
@immutable
class BoxSizedImageKey {
  const BoxSizedImageKey._(this._image, this._width, this._height, this._cover);

  final Object _image;
  final int _width;
  final int _height;
  final bool _cover;

  @override
  bool operator ==(Object other) =>
      other is BoxSizedImageKey &&
      other._image == _image &&
      other._width == _width &&
      other._height == _height &&
      other._cover == _cover;

  @override
  int get hashCode => Object.hash(_image, _width, _height, _cover);
}

/// The size to decode an image of [imageWidth] × [imageHeight] at for a box of [boxWidth] ×
/// [boxHeight] (see [BoxSizedImage]); the image's own size when it is no bigger.
ui.TargetImageSize boxTargetSize(
  int imageWidth,
  int imageHeight, {
  required int boxWidth,
  required int boxHeight,
  required bool cover,
}) {
  if (imageWidth <= 0 || imageHeight <= 0) return const ui.TargetImageSize();
  final byWidth = boxWidth / imageWidth;
  final byHeight = boxHeight / imageHeight;
  final scale = cover
      ? math.max(byWidth, byHeight)
      : math.min(byWidth, byHeight);
  if (scale >= 1) return const ui.TargetImageSize();
  return ui.TargetImageSize(
    width: math.max(1, (imageWidth * scale).ceil()),
    height: math.max(1, (imageHeight * scale).ceil()),
  );
}

/// Encoded image [bytes] shown in a box of [width] × [height] logical pixels, decoded at that
/// size on this screen (see [BoxSizedImage]).
class BoxSizedMemoryImage extends StatelessWidget {
  const BoxSizedMemoryImage(
    this.bytes, {
    required this.width,
    required this.height,
    this.fit = BoxFit.cover,
    this.gaplessPlayback = false,
    this.errorBuilder,
    super.key,
  });

  final Uint8List bytes;
  final double width;
  final double height;
  final BoxFit fit;
  final bool gaplessPlayback;
  final ImageErrorWidgetBuilder? errorBuilder;

  @override
  Widget build(BuildContext context) {
    final ratio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    return Image(
      image: BoxSizedImage(
        MemoryImage(bytes),
        width: math.max(1, (width * ratio).ceil()),
        height: math.max(1, (height * ratio).ceil()),
        cover: fit == BoxFit.cover,
      ),
      width: width,
      height: height,
      fit: fit,
      gaplessPlayback: gaplessPlayback,
      errorBuilder: errorBuilder,
    );
  }
}
