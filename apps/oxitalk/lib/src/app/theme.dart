import 'package:flutter/material.dart';

/// The brand of the app icon (branding/oxitalk-icon.svg): a yellow bubble with cut
/// corners and a red voice wave, on ink.
abstract final class OxiBrand {
  static const ink = Color(0xFF0B0B12);
  static const yellow = Color(0xFFFCEE0A);
  static const red = Color(0xFFFF1744);
}

/// Colours that are the same in both themes. Colour is for highlights only: red for unread
/// counts, yellow for the @ badge, the send button, the new-chat button and what is active.
abstract final class OxiColors {
  /// The app-drawn title bar: flat ink in both themes.
  static const titleBar = OxiBrand.ink;
  static const titleBarLine = Color(0xFF3A3820);
  static const titleBarText = Color(0xFFF2F2F5);
  static const titleBarMuted = Color(0xFFA8A8B8);

  /// The account rail: always dark.
  static const railDark = Color(0xFF07070B);
  static const railLight = OxiBrand.ink;
  static const railLine = Color(0xFF1E1E2A);
  static const railIcon = Color(0xFF8C8C9C);
  static const railAddOutline = Color(0xFF3A3A4C);

  /// Avatar backgrounds, picked by a hash of the room or user: muted, never cyan.
  static const avatars = [
    Color(0xFF8A3A47),
    Color(0xFF3E4E86),
    Color(0xFF8C5A2E),
    Color(0xFF5E4A8C),
    Color(0xFF356B55),
    Color(0xFF6E6838),
    Color(0xFF7A3F68),
  ];

  /// The avatar of no one in particular.
  static const avatarFallback = Color(0xFF3D3D52);

  /// The avatar colour of [seed] (a room or user ID).
  static Color avatarOf(String seed) =>
      avatars[seed.hashCode.abs() % avatars.length];
}

/// The theme's own colours beyond the [ColorScheme]: panels, chat bubbles and highlights.
@immutable
class OxiPalette extends ThemeExtension<OxiPalette> {
  const OxiPalette({
    required this.page,
    required this.panel,
    required this.panel2,
    required this.line,
    required this.text,
    required this.muted,
    required this.wallpaper,
    required this.bubble,
    required this.ownBubble,
    required this.ownText,
    required this.ownMeta,
    required this.ownStrip,
    required this.selectedRow,
    required this.threadLink,
    required this.quoteBar,
    required this.rail,
  });

  static const light = OxiPalette(
    page: Color(0xFFF4F4EF),
    panel: Color(0xFFFFFFFF),
    panel2: Color(0xFFECECE4),
    line: Color(0xFFDEDED4),
    text: OxiBrand.ink,
    muted: Color(0xFF6B6B78),
    wallpaper: Color(0xFFE9E9E1),
    bubble: Color(0xFFFFFFFF),
    ownBubble: Color(0xFFFFF5B8),
    ownText: OxiBrand.ink,
    ownMeta: Color(0xFF7A7330),
    ownStrip: null,
    selectedRow: Color(0xFFF3F1DC),
    threadLink: Color(0xFF8A7F00),
    quoteBar: OxiBrand.ink,
    rail: OxiColors.railLight,
  );

  static const dark = OxiPalette(
    page: OxiBrand.ink,
    panel: Color(0xFF12121B),
    panel2: Color(0xFF1A1A26),
    line: Color(0xFF262634),
    text: Color(0xFFF2F2F5),
    muted: Color(0xFF8C8C9C),
    wallpaper: OxiBrand.ink,
    bubble: Color(0xFF1C1C29),
    ownBubble: Color(0xFF24231B),
    ownText: Color(0xFFF2F2F5),
    ownMeta: Color(0xFF9C9878),
    ownStrip: OxiBrand.yellow,
    selectedRow: Color(0xFF1A1A20),
    threadLink: Color(0xFFD9CE3A),
    quoteBar: OxiBrand.yellow,
    rail: OxiColors.railDark,
  );

  /// Behind the panels.
  final Color page;

  /// The chat list, the headers and the message box.
  final Color panel;

  /// A quieter surface on a panel: the search and message fields, muted badges.
  final Color panel2;
  final Color line;
  final Color text;
  final Color muted;

  /// Behind the messages.
  final Color wallpaper;

  /// Others' messages.
  final Color bubble;

  /// The user's own messages, their text and their time.
  final Color ownBubble;
  final Color ownText;
  final Color ownMeta;

  /// A thin strip inside the right edge of the user's own messages, if any.
  final Color? ownStrip;

  /// The open chat in the list; a yellow bar marks its left edge.
  final Color selectedRow;

  /// The link to a message's thread.
  final Color threadLink;

  /// The bar beside a quoted message.
  final Color quoteBar;

  /// The account rail.
  final Color rail;

  /// Behind a reaction.
  Color get reaction => const Color(0x247F7F7F);

  /// Behind a quoted message.
  Color get quote => const Color(0x1A7F7F7F);

  @override
  OxiPalette copyWith() => this;

  @override
  OxiPalette lerp(OxiPalette? other, double t) =>
      other == null || t < 0.5 ? this : other;
}

/// Cut (bevelled) corners instead of round ones, the shape of the app icon's bubble.
abstract final class OxiShapes {
  /// The top-left and bottom-right corners cut by [cut], as the brand's tags and avatars.
  static BeveledRectangleBorder cut(
    double cut, {
    BorderSide side = BorderSide.none,
  }) => BeveledRectangleBorder(
    side: side,
    borderRadius: BorderRadius.only(
      topLeft: Radius.circular(cut),
      bottomRight: Radius.circular(cut),
    ),
  );

  /// Every corner cut by [cut].
  static BeveledRectangleBorder all(
    double cut, {
    BorderSide side = BorderSide.none,
  }) => BeveledRectangleBorder(
    side: side,
    borderRadius: BorderRadius.circular(cut),
  );

  /// The usual cut of buttons, fields, chips and badges.
  static final small = cut(6);

  /// Cards, dialogs and menus.
  static final medium = cut(10);
}

/// The app's one button system. Every button has the same geometry: [height] tall, 16 px
/// either side, the [OxiShapes.small] bevel, a 14 px semibold label and an 18 px icon; no
/// elevation, no gradient, no glow. Three kinds:
///
/// * primary, [FilledButton]: yellow under ink in dark, ink under white in light;
/// * secondary, [OutlinedButton]: no fill, a quiet neutral outline, the text colour;
/// * destructive, [OutlinedButton] with [destructive]: the secondary shape in [danger].
///   A dialog that confirms a destructive action uses [FilledButton] with
///   [destructiveFilled].
///
/// [TextButton] stays borderless for the framework's own text actions (snack bar actions,
/// the text selection menu); the app itself uses [OutlinedButton] wherever it shows a
/// button, so nothing that acts as a button reads as plain text.
abstract final class OxiButtons {
  static const height = 40.0;
  static const padding = EdgeInsets.symmetric(horizontal: 16);
  static const iconSize = 18.0;
  static const label = TextStyle(
    // A button's text style replaces the theme's, font included.
    fontFamily: textFont,
    fontFamilyFallback: [emojiFont],
    fontSize: 14,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
  );

  /// Red for destructive labels and outlines: the brand red on dark; on light a darker red,
  /// as the brand red is too light for text on white (3.8:1, this is 5.4:1).
  static Color danger(Brightness brightness) =>
      brightness == Brightness.dark ? OxiBrand.red : dangerOnLight;

  static const dangerOnLight = Color(0xFFD50032);

  /// The secondary button's outline: the muted text colour at 60%.
  static Color outline(OxiPalette p) => p.muted.withValues(alpha: 0.6);

  /// What every kind shares.
  static ButtonStyle base() => ButtonStyle(
    minimumSize: const WidgetStatePropertyAll(Size(64, height)),
    padding: const WidgetStatePropertyAll(padding),
    iconSize: const WidgetStatePropertyAll(iconSize),
    textStyle: const WidgetStatePropertyAll(label),
    elevation: const WidgetStatePropertyAll(0),
    shadowColor: const WidgetStatePropertyAll(Colors.transparent),
    surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
    shape: WidgetStatePropertyAll<OutlinedBorder>(OxiShapes.small),
    // The same height on desktop (compact density) as on phones.
    visualDensity: VisualDensity.standard,
  );

  /// Primary: [ColorScheme.primary] under [ColorScheme.onPrimary].
  static ButtonStyle primary(ColorScheme scheme) => base().copyWith(
    backgroundColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.disabled)
          ? scheme.onSurface.withValues(alpha: 0.12)
          : scheme.primary,
    ),
    foregroundColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.disabled)
          ? scheme.onSurface.withValues(alpha: 0.38)
          : scheme.onPrimary,
    ),
    iconColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.disabled)
          ? scheme.onSurface.withValues(alpha: 0.38)
          : scheme.onPrimary,
    ),
    overlayColor: _overlay(scheme.onPrimary),
  );

  /// Secondary: no fill, [outline], the text colour; [OxiPalette.panel2] under the pointer.
  static ButtonStyle secondary(OxiPalette p) {
    Color fore(Set<WidgetState> states) => states.contains(WidgetState.disabled)
        ? p.text.withValues(alpha: 0.38)
        : p.text;
    return base().copyWith(
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) => _active(states) ? p.panel2 : Colors.transparent,
      ),
      foregroundColor: WidgetStateProperty.resolveWith(fore),
      iconColor: WidgetStateProperty.resolveWith(fore),
      overlayColor: _overlay(p.text),
      side: WidgetStateProperty.resolveWith(
        (states) => BorderSide(
          color: states.contains(WidgetState.disabled) ? p.line : outline(p),
        ),
      ),
    );
  }

  /// Destructive, on an [OutlinedButton]: the secondary shape with a red label and outline.
  static ButtonStyle destructive(BuildContext context) {
    final p = context.oxi;
    final red = danger(Theme.of(context).brightness);
    Color fore(Set<WidgetState> states) => states.contains(WidgetState.disabled)
        ? p.text.withValues(alpha: 0.38)
        : red;
    return base().copyWith(
      // Red reads thinner than white on ink at the same weight: one step heavier.
      textStyle: WidgetStatePropertyAll(
        label.copyWith(fontWeight: FontWeight.w700),
      ),
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) =>
            _active(states) ? red.withValues(alpha: 0.1) : Colors.transparent,
      ),
      foregroundColor: WidgetStateProperty.resolveWith(fore),
      iconColor: WidgetStateProperty.resolveWith(fore),
      overlayColor: _overlay(red),
      side: WidgetStateProperty.resolveWith(
        (states) => BorderSide(
          color: states.contains(WidgetState.disabled) ? p.line : red,
        ),
      ),
    );
  }

  /// Destructive, on a [FilledButton]: the confirm button of a dialog that deletes or
  /// removes something. White on [dangerOnLight] in both themes (white on the brand red
  /// would be 3.8:1).
  static ButtonStyle destructiveFilled(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? scheme.onSurface.withValues(alpha: 0.12)
            : dangerOnLight,
      ),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? scheme.onSurface.withValues(alpha: 0.38)
            : Colors.white,
      ),
      iconColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? scheme.onSurface.withValues(alpha: 0.38)
            : Colors.white,
      ),
      overlayColor: _overlay(Colors.white),
    );
  }

  static bool _active(Set<WidgetState> states) =>
      states.contains(WidgetState.hovered) ||
      states.contains(WidgetState.focused) ||
      states.contains(WidgetState.pressed);

  /// A subtle wash over a button the pointer is on or presses.
  static WidgetStateProperty<Color?> _overlay(Color color) =>
      WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.pressed)
            ? color.withValues(alpha: 0.12)
            : states.contains(WidgetState.hovered) ||
                  states.contains(WidgetState.focused)
            ? color.withValues(alpha: 0.08)
            : null,
      );
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

/// The colours of [brightness]. In light, yellow is only ever a fill under ink, so the
/// primary colour is ink; in dark, yellow reads well and is the primary colour.
ColorScheme oxiColorScheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final p = dark ? OxiPalette.dark : OxiPalette.light;
  return ColorScheme(
    brightness: brightness,
    primary: dark ? OxiBrand.yellow : OxiBrand.ink,
    onPrimary: dark ? OxiBrand.ink : Colors.white,
    primaryContainer: p.ownBubble,
    onPrimaryContainer: p.ownText,
    secondary: p.muted,
    onSecondary: dark ? OxiBrand.ink : Colors.white,
    secondaryContainer: p.panel2,
    onSecondaryContainer: p.text,
    tertiary: p.threadLink,
    onTertiary: dark ? OxiBrand.ink : Colors.white,
    tertiaryContainer: p.selectedRow,
    onTertiaryContainer: p.text,
    error: OxiBrand.red,
    onError: Colors.white,
    errorContainer: dark ? const Color(0xFF3A0F1A) : const Color(0xFFFFE3E8),
    onErrorContainer: dark ? const Color(0xFFFFB3C0) : const Color(0xFF7A0019),
    surface: p.panel,
    onSurface: p.text,
    onSurfaceVariant: p.muted,
    surfaceDim: dark ? const Color(0xFF0E0E16) : const Color(0xFFE4E4DA),
    surfaceBright: dark ? const Color(0xFF22222F) : Colors.white,
    surfaceContainerLowest: dark ? OxiBrand.ink : Colors.white,
    surfaceContainerLow: dark
        ? const Color(0xFF101018)
        : const Color(0xFFF9F9F5),
    surfaceContainer: dark ? const Color(0xFF15151F) : p.page,
    surfaceContainerHigh: dark ? p.panel2 : p.panel2,
    surfaceContainerHighest: dark
        ? const Color(0xFF22222F)
        : const Color(0xFFE4E4DA),
    outline: dark ? const Color(0xFF4A4A5A) : const Color(0xFFA9A99E),
    outlineVariant: p.line,
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: dark ? p.text : OxiBrand.ink,
    onInverseSurface: dark ? OxiBrand.ink : const Color(0xFFF2F2F5),
    inversePrimary: dark ? OxiBrand.ink : OxiBrand.yellow,
    surfaceTint: Colors.transparent,
  );
}

ThemeData oxiTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = oxiColorScheme(brightness);
  final p = dark ? OxiPalette.dark : OxiPalette.light;
  final small = OxiShapes.small;
  final buttonShape = WidgetStatePropertyAll<OutlinedBorder>(small);
  final field = const OxiInputBorder(cut: 6);
  return ThemeData(
    useMaterial3: true,
    fontFamily: textFont,
    fontFamilyFallback: const [emojiFont],
    colorScheme: scheme,
    extensions: [p],
    scaffoldBackgroundColor: p.panel,
    canvasColor: p.panel,
    dividerColor: p.line,
    dividerTheme: DividerThemeData(color: p.line, space: 1, thickness: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: p.panel,
      foregroundColor: p.text,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      shape: Border(bottom: BorderSide(color: p.line)),
      iconTheme: IconThemeData(color: p.muted),
      actionsIconTheme: IconThemeData(color: p.muted),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: OxiBrand.yellow,
      foregroundColor: OxiBrand.ink,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      shape: OxiShapes.cut(10),
      smallSizeConstraints: const BoxConstraints.tightFor(
        width: 40,
        height: 40,
      ),
    ),
    cardTheme: CardThemeData(
      color: p.panel,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: OxiShapes.medium,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.panel,
      surfaceTintColor: Colors.transparent,
      shape: OxiShapes.medium,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: p.panel,
      surfaceTintColor: Colors.transparent,
      shape: OxiShapes.cut(8, side: BorderSide(color: p.line)),
      elevation: 2,
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(p.panel),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(OxiShapes.cut(8)),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.panel,
      surfaceTintColor: Colors.transparent,
      shape: const BeveledRectangleBorder(
        borderRadius: BorderRadius.only(topLeft: Radius.circular(12)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: TextStyle(color: scheme.onInverseSurface),
      actionTextColor: dark ? OxiBrand.ink : OxiBrand.yellow,
      shape: small,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: ShapeDecoration(
        color: dark ? const Color(0xFF2A2A38) : OxiBrand.ink,
        shape: OxiShapes.cut(4),
      ),
      textStyle: const TextStyle(color: Color(0xFFF2F2F5), fontSize: 12),
    ),
    // One button system (OxiButtons): primary = filled (and elevated), secondary =
    // outlined. Text buttons keep only the shape: the framework's own text actions (snack
    // bar actions, the text selection menu) use them; the app uses outlined buttons.
    filledButtonTheme: FilledButtonThemeData(style: OxiButtons.primary(scheme)),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: OxiButtons.primary(scheme),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OxiButtons.secondary(p),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(shape: buttonShape),
    ),
    // The picked segment is filled like a primary button: yellow under ink in dark, ink
    // under white in light; the others stay plain.
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: buttonShape,
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? (dark ? OxiBrand.yellow : OxiBrand.ink)
              : Colors.transparent,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? p.text.withValues(alpha: 0.38)
              : states.contains(WidgetState.selected)
              ? (dark ? OxiBrand.ink : Colors.white)
              : p.text,
        ),
        iconColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? (dark ? OxiBrand.ink : Colors.white)
              : p.text,
        ),
        side: WidgetStatePropertyAll(BorderSide(color: OxiButtons.outline(p))),
        textStyle: const WidgetStatePropertyAll(OxiButtons.label),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(shape: buttonShape),
    ),
    chipTheme: ChipThemeData(
      shape: small,
      backgroundColor: p.panel2,
      side: BorderSide.none,
      selectedColor: dark ? OxiBrand.yellow : OxiBrand.ink,
      secondarySelectedColor: dark ? OxiBrand.yellow : OxiBrand.ink,
    ),
    badgeTheme: const BadgeThemeData(
      backgroundColor: OxiBrand.red,
      textColor: Colors.white,
    ),
    // Filter tabs: ink fill under white text in light; yellow text over a yellow line in
    // dark.
    tabBarTheme: TabBarThemeData(
      labelColor: dark ? OxiBrand.yellow : Colors.white,
      unselectedLabelColor: p.muted,
      labelStyle: const TextStyle(fontWeight: FontWeight.w700),
      unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700),
      dividerColor: p.line,
      indicatorSize: TabBarIndicatorSize.tab,
      indicator: dark
          ? const UnderlineTabIndicator(
              borderSide: BorderSide(color: OxiBrand.yellow, width: 2),
            )
          : ShapeDecoration(color: OxiBrand.ink, shape: small),
    ),
    listTileTheme: ListTileThemeData(
      selectedColor: p.text,
      selectedTileColor: p.selectedRow,
      iconColor: p.muted,
    ),
    navigationRailTheme: NavigationRailThemeData(
      indicatorShape: small,
      indicatorColor: p.panel2,
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: p.panel2,
      hintStyle: TextStyle(color: p.muted),
      border: field,
      enabledBorder: field,
      disabledBorder: field,
      focusedBorder: OxiInputBorder(
        cut: 6,
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
      errorBorder: OxiInputBorder(
        cut: 6,
        borderSide: const BorderSide(color: OxiBrand.red),
      ),
      focusedErrorBorder: OxiInputBorder(
        cut: 6,
        borderSide: const BorderSide(color: OxiBrand.red, width: 1.5),
      ),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: scheme.primary,
      selectionColor: OxiBrand.yellow.withValues(alpha: dark ? 0.35 : 0.6),
      selectionHandleColor: dark ? OxiBrand.yellow : OxiBrand.ink,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
      linearTrackColor: p.panel2,
    ),
  );
}

/// A field's outline with cut corners; no outline at all with [BorderSide.none].
class OxiInputBorder extends InputBorder {
  const OxiInputBorder({required this.cut, super.borderSide = BorderSide.none});

  final double cut;

  BorderSide get side => borderSide;

  BeveledRectangleBorder get _shape => OxiShapes.cut(cut, side: side);

  @override
  bool get isOutline => false;

  @override
  InputBorder copyWith({BorderSide? borderSide}) =>
      OxiInputBorder(cut: cut, borderSide: borderSide ?? side);

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      _shape.getInnerPath(rect, textDirection: textDirection);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      _shape.getOuterPath(rect, textDirection: textDirection);

  @override
  void paint(
    Canvas canvas,
    Rect rect, {
    double? gapStart,
    double gapExtent = 0.0,
    double gapPercentage = 0.0,
    TextDirection? textDirection,
  }) {
    if (side.style == BorderStyle.none) return;
    _shape.paint(canvas, rect, textDirection: textDirection);
  }

  @override
  ShapeBorder scale(double t) =>
      OxiInputBorder(cut: cut * t, borderSide: side.scale(t));

  @override
  bool operator ==(Object other) =>
      other is OxiInputBorder && other.cut == cut && other.side == side;

  @override
  int get hashCode => Object.hash(cut, side);
}

extension OxiThemeContext on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  /// The theme's [OxiPalette].
  OxiPalette get oxi =>
      Theme.of(this).extension<OxiPalette>() ??
      (isDark ? OxiPalette.dark : OxiPalette.light);
}
