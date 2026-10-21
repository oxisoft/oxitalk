import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'providers.dart';

enum WindowButton { minimize, maximize, close }

/// What a double-click on the title bar does, as the desktop is set up.
enum TitleBarDoubleClick { toggleMaximize, minimize, menu, none }

/// The window, when the app draws its title bar: which buttons the desktop wants and where,
/// and what the title bar's clicks do.
abstract interface class WindowControls {
  /// Whether the app draws the title bar (else the platform does, or there is no window).
  bool get drawsTitleBar;

  /// The buttons at the left and at the right of the title bar, in order.
  List<WindowButton> get leftButtons;
  List<WindowButton> get rightButtons;

  /// Moves the window with the pointer that is down.
  Future<void> startDragging();

  /// What the desktop does on a double-click of a title bar.
  Future<void> doubleClick();

  /// The desktop's window menu (move, resize, always on top, …).
  Future<void> showMenu();

  Future<void> press(WindowButton button);
}

/// No title bar of the app's own: phones, the platforms not done yet, and tests.
final class PlatformWindowControls implements WindowControls {
  const PlatformWindowControls();

  @override
  bool get drawsTitleBar => false;

  @override
  List<WindowButton> get leftButtons => const [];

  @override
  List<WindowButton> get rightButtons => const [];

  @override
  Future<void> startDragging() async {}

  @override
  Future<void> doubleClick() async {}

  @override
  Future<void> showMenu() async {}

  @override
  Future<void> press(WindowButton button) async {}
}

/// The app's title bar on Linux, as GNOME sets it up: GTK's own is hidden, keeping the
/// window's shadow and edges; the buttons and the double-click follow GNOME's settings.
final class DrawnWindowControls implements WindowControls {
  DrawnWindowControls._(this.leftButtons, this.rightButtons, this._doubleClick);

  /// Hides the platform's title bar where the app draws its own; call before `runApp`.
  static Future<WindowControls> start() async {
    if (!Platform.isLinux) return const PlatformWindowControls();
    await windowManager.ensureInitialized();
    await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
    final layout = parseButtonLayout(
      await _gsetting('button-layout') ?? ':minimize,maximize,close',
    );
    return DrawnWindowControls._(
      layout.left,
      layout.right,
      parseDoubleClick(await _gsetting('action-double-click-titlebar')),
    );
  }

  /// A GNOME window manager setting, without its quotes; `null` without GNOME.
  static Future<String?> _gsetting(String key) async {
    try {
      final result = await Process.run('gsettings', [
        'get',
        'org.gnome.desktop.wm.preferences',
        key,
      ]);
      if (result.exitCode != 0) return null;
      return (result.stdout as String).trim().replaceAll("'", '');
    } on ProcessException {
      return null;
    }
  }

  @override
  bool get drawsTitleBar => true;

  @override
  final List<WindowButton> leftButtons;

  @override
  final List<WindowButton> rightButtons;

  final TitleBarDoubleClick _doubleClick;

  @override
  Future<void> startDragging() => windowManager.startDragging();

  @override
  Future<void> doubleClick() => switch (_doubleClick) {
    TitleBarDoubleClick.toggleMaximize => press(WindowButton.maximize),
    TitleBarDoubleClick.minimize => press(WindowButton.minimize),
    TitleBarDoubleClick.menu => showMenu(),
    TitleBarDoubleClick.none => Future.value(),
  };

  @override
  Future<void> showMenu() => windowManager.popUpWindowMenu();

  @override
  Future<void> press(WindowButton button) async {
    switch (button) {
      case WindowButton.minimize:
        await windowManager.minimize();
      case WindowButton.maximize:
        await windowManager.isMaximized()
            ? await windowManager.unmaximize()
            : await windowManager.maximize();
      case WindowButton.close:
        await windowManager.close();
    }
  }
}

/// GNOME's `button-layout`, like `appmenu:minimize,maximize,close`: the buttons left and
/// right of the colon. Entries other than the three buttons are left out.
({List<WindowButton> left, List<WindowButton> right}) parseButtonLayout(
  String layout,
) {
  List<WindowButton> side(String names) => [
    for (final name in names.split(','))
      ?switch (name.trim()) {
        'minimize' => WindowButton.minimize,
        'maximize' => WindowButton.maximize,
        'close' => WindowButton.close,
        _ => null,
      },
  ];
  final parts = layout.split(':');
  return (
    left: side(parts.first),
    right: side(parts.length > 1 ? parts[1] : ''),
  );
}

/// GNOME's `action-double-click-titlebar`; maximizing unless it says otherwise.
TitleBarDoubleClick parseDoubleClick(String? action) => switch (action) {
  'minimize' => TitleBarDoubleClick.minimize,
  'menu' => TitleBarDoubleClick.menu,
  'none' || 'lower' => TitleBarDoubleClick.none,
  _ => TitleBarDoubleClick.toggleMaximize,
};

/// The empty part of the app's title bar: drag to move, double-click as the desktop says,
/// right-click for the window menu. Put it behind the bar's content, so the content keeps
/// its clicks.
class WindowDragArea extends ConsumerWidget {
  const WindowDragArea({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controls = ref.watch(windowControlsProvider);
    if (!controls.drawsTitleBar) return const SizedBox.expand();
    return GestureDetector(
      key: const Key('window.drag'),
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => unawaited(controls.startDragging()),
      onDoubleTap: () => unawaited(controls.doubleClick()),
      onSecondaryTapUp: (_) => unawaited(controls.showMenu()),
      child: const SizedBox.expand(),
    );
  }
}

/// The window buttons for one end of the app's title bar, drawn as GNOME draws them: small
/// round buttons, Close turning red under the pointer. Nothing when the desktop wants none
/// there, or draws its own title bar.
class WindowButtons extends ConsumerWidget {
  const WindowButtons.left({super.key}) : _right = false;

  const WindowButtons.right({super.key}) : _right = true;

  final bool _right;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controls = ref.watch(windowControlsProvider);
    if (!controls.drawsTitleBar) return const SizedBox.shrink();
    final buttons = _right ? controls.rightButtons : controls.leftButtons;
    if (buttons.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(left: _right ? 4 : 12, right: _right ? 12 : 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final button in buttons)
            _RoundButton(
              key: Key('window.${button.name}'),
              tooltip: switch (button) {
                WindowButton.minimize => 'Minimize',
                WindowButton.maximize => 'Maximize',
                WindowButton.close => 'Close OxiTalk',
              },
              danger: button == WindowButton.close,
              icon: switch (button) {
                WindowButton.minimize => Icons.minimize_rounded,
                WindowButton.maximize => Icons.crop_square_rounded,
                WindowButton.close => Icons.close_rounded,
              },
              onPressed: () => unawaited(controls.press(button)),
            ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.danger = false,
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  /// Red under the pointer, as a button that ends something.
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: scheme.onSurface.withValues(alpha: 0.1),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            hoverColor: danger
                ? const Color(0xFFE5484D)
                : scheme.onSurface.withValues(alpha: 0.12),
            onTap: onPressed,
            child: SizedBox.square(
              dimension: 24,
              child: Icon(icon, size: 15, color: scheme.onSurface),
            ),
          ),
        ),
      ),
    );
  }
}
