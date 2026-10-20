import 'package:flutter/material.dart';

/// M0's local theme constants (M1 lifts them into the design system's tokens).
abstract final class OxiColors {
  static const accent = Color(0xFF2AABEE);
  static const ownBubbleLight = Color(0xFFE3F6D0);
  static const ownBubbleDark = Color(0xFF2B5278);
  static const bubbleLight = Colors.white;
  static const bubbleDark = Color(0xFF182533);
  static const wallpaperLight = Color(0xFFDDE6EC);
  static const wallpaperDark = Color(0xFF0E1621);

  /// Avatar backgrounds, picked by a hash of the room or user.
  static const avatars = [
    Color(0xFFE17076),
    Color(0xFFFAA774),
    Color(0xFFA695E7),
    Color(0xFF7BC862),
    Color(0xFF6EC9CB),
    Color(0xFF65AADD),
    Color(0xFFEE7AAE),
  ];
}

/// From this width on, the chat list and the chat sit side by side.
const wideLayoutBreakpoint = 840.0;

/// The bundled text font, on every platform.
const textFont = 'Open Sans';

/// The bundled colour emoji font, for every emoji the text font lacks. It also has a space,
/// digits, `#` and `*` (for keycap emoji), so it must never stand in for a missing text font.
const emojiFont = 'Noto Color Emoji';

/// Code, in the platform's monospaced font: `monospace` names it on Linux and Android,
/// the others by name; the text font if none is there.
const codeStyle = TextStyle(
  fontFamily: 'monospace',
  fontFamilyFallback: [
    'Menlo',
    'Consolas',
    'Cascadia Mono',
    'Courier New',
    textFont,
    emojiFont,
  ],
);

ThemeData oxiTheme(Brightness brightness) => ThemeData(
  useMaterial3: true,
  fontFamily: textFont,
  fontFamilyFallback: const [emojiFont],
  colorScheme: ColorScheme.fromSeed(
    seedColor: OxiColors.accent,
    brightness: brightness,
  ),
);

extension OxiThemeContext on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}
