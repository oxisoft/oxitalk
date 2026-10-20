import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oxitalk/src/app/theme.dart';

/// Registers a bundled font under its family name, as the app's asset manifest does.
Future<void> _load(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final file in files) {
    loader.addFont(
      Future.value(ByteData.sublistView(File(file).readAsBytesSync())),
    );
  }
  await loader.load();
}

double _width(String text, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
  )..layout();
  return painter.width;
}

void main() {
  final body = oxiTheme(Brightness.light).textTheme.bodyMedium!;

  setUpAll(() async {
    await _load(textFont, [
      'assets/fonts/OpenSans.ttf',
      'assets/fonts/OpenSans-Italic.ttf',
    ]);
    await _load(emojiFont, ['assets/fonts/NotoColorEmoji.ttf']);
  });

  test('spaces and digits come from the text font, not the emoji font', () {
    const text = 'at 14:26 we 1 2 #3 *';
    final alone = body.copyWith(fontFamilyFallback: const []);
    expect(body.fontFamily, textFont);
    expect(_width(text, body), _width(text, alone));
    // Code: a platform without any of the monospaced fonts gets the text font, never the
    // emoji font. (Tests can't draw that: their stand-in font has every character.)
    final code = codeStyle.fontFamilyFallback!;
    expect(code.indexOf(textFont), lessThan(code.indexOf(emojiFont)));
  });

  // Only Linux's headless test renderer applies the font fallback to an emoji; on the Windows
  // and macOS runners it draws nothing (0 coloured pixels), while the app shows them.
  testWidgets('emoji fall back to the bundled font, in colour', (tester) async {
    final boundary = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: oxiTheme(Brightness.light),
        home: Material(
          child: Center(
            child: RepaintBoundary(
              key: boundary,
              child: const ColoredBox(
                color: Colors.white,
                child: Text('😀', style: TextStyle(fontSize: 48)),
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
  }, skip: !Platform.isLinux);
}
