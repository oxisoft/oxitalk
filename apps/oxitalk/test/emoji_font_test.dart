import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oxitalk/src/app/theme.dart';

void main() {
  test('text falls back to the bundled emoji font', () {
    final theme = oxiTheme(Brightness.light);
    for (final style in [
      theme.textTheme.bodyMedium,
      theme.textTheme.titleMedium,
      theme.textTheme.labelSmall,
    ]) {
      expect(style?.fontFamilyFallback, contains(emojiFont));
    }
  });

  // Tests draw text in a font with every character, so nothing falls back here; the
  // emoji font is asked for by name.
  testWidgets('the bundled emoji font draws in colour', (tester) async {
    await tester.runAsync(() async {
      final font = File('assets/fonts/NotoColorEmoji.ttf').readAsBytesSync();
      await (FontLoader(
        emojiFont,
      )..addFont(Future.value(ByteData.sublistView(font)))).load();
    });
    final boundary = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: oxiTheme(Brightness.light),
        home: Center(
          child: RepaintBoundary(
            key: boundary,
            child: ColoredBox(
              color: Colors.white,
              child: Text(
                '😀',
                style: TextStyle(fontSize: 48, fontFamily: emojiFont),
              ),
            ),
          ),
        ),
      ),
    );
    final pixels = await tester.runAsync(() async {
      final image =
          await (boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage();
      return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    });
    // The grinning face is yellow: plenty of pixels far from grey.
    var colourful = 0;
    for (var i = 0; i < pixels!.lengthInBytes; i += 4) {
      final r = pixels.getUint8(i);
      final g = pixels.getUint8(i + 1);
      final b = pixels.getUint8(i + 2);
      if (r > 150 && g > 120 && b < 100) colourful++;
    }
    expect(colourful, greaterThan(200));
  });
}
