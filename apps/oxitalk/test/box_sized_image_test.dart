import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oxitalk/src/ui/box_sized_image.dart';

(int?, int?) _size(ui.TargetImageSize size) => (size.width, size.height);

void main() {
  test(
    'a big photo is decoded just big enough to fill its box, its shape kept',
    () {
      // 4000 × 3000 into a 200 × 200 box: the short side fills it.
      expect(
        _size(
          boxTargetSize(4000, 3000, boxWidth: 200, boxHeight: 200, cover: true),
        ),
        (267, 200),
      );
      // A tall photo in a wide box: the width fills it.
      expect(
        _size(
          boxTargetSize(1000, 4000, boxWidth: 400, boxHeight: 100, cover: true),
        ),
        (400, 1600),
      );
    },
  );

  test('to fit in its box, the long side decides', () {
    expect(
      _size(
        boxTargetSize(4000, 3000, boxWidth: 800, boxHeight: 800, cover: false),
      ),
      (800, 600),
    );
  });

  test(
    'a picture no bigger than its box, or of no size, keeps its own size',
    () {
      expect(
        _size(
          boxTargetSize(96, 96, boxWidth: 200, boxHeight: 200, cover: true),
        ),
        (null, null),
      );
      expect(
        _size(boxTargetSize(0, 0, boxWidth: 200, boxHeight: 200, cover: true)),
        (null, null),
      );
    },
  );

  test('the same picture in the same box is the same image, for the cache', () {
    final bytes = Uint8List.fromList([1, 2, 3]);
    final image = MemoryImage(bytes);
    expect(
      BoxSizedImage(image, width: 10, height: 10),
      BoxSizedImage(MemoryImage(bytes), width: 10, height: 10),
    );
    expect(
      BoxSizedImage(image, width: 10, height: 10),
      isNot(BoxSizedImage(image, width: 20, height: 10)),
    );
  });
}
