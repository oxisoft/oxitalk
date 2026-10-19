import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'providers.dart';

/// The window, when the app draws its own title bar: moving it and its buttons.
abstract interface class WindowControls {
  /// Whether the app draws the title bar (else the platform does, or there is no window).
  bool get drawsTitleBar;

  /// Moves the window with the pointer that is down.
  Future<void> startDragging();

  Future<void> minimize();

  /// Maximizes the window, or restores it when maximized.
  Future<void> toggleMaximize();

  Future<void> close();
}

/// No title bar of the app's own: phones, the platforms not done yet, and tests.
final class PlatformWindowControls implements WindowControls {
  const PlatformWindowControls();

  @override
  bool get drawsTitleBar => false;

  @override
  Future<void> startDragging() async {}

  @override
  Future<void> minimize() async {}

  @override
  Future<void> toggleMaximize() async {}

  @override
  Future<void> close() async {}
}

/// The app's own title bar on Linux: GTK's is hidden, keeping the window's shadow and edges.
final class DrawnWindowControls implements WindowControls {
  DrawnWindowControls._();

  /// Hides the platform's title bar where the app draws its own; call before `runApp`.
  static Future<WindowControls> start() async {
    if (!Platform.isLinux) return const PlatformWindowControls();
    await windowManager.ensureInitialized();
    await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
    return DrawnWindowControls._();
  }

  @override
  bool get drawsTitleBar => true;

  @override
  Future<void> startDragging() => windowManager.startDragging();

  @override
  Future<void> minimize() => windowManager.minimize();

  @override
  Future<void> toggleMaximize() async => await windowManager.isMaximized()
      ? windowManager.unmaximize()
      : windowManager.maximize();

  @override
  Future<void> close() => windowManager.close();
}

/// The height of the title bar strip: the Material 3 app bar's.
const _captionHeight = 64.0;
const _buttonWidth = 40.0;

/// Over the whole app when it draws its own title bar: the top strip moves the window and its
/// right end holds the window buttons. The headers below stay usable; a top-right header keeps
/// [WindowButtonsSpace] free for the buttons.
class WindowCaption extends ConsumerWidget {
  const WindowCaption({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controls = ref.watch(windowControlsProvider);
    if (!controls.drawsTitleBar) return child;
    // An overlay of its own for the buttons' tooltips: this is above the app's navigator.
    return Overlay(
      initialEntries: [OverlayEntry(builder: (_) => _withButtons(controls))],
    );
  }

  Widget _withButtons(WindowControls controls) {
    return Stack(
      children: [
        child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: _captionHeight,
          child: Row(
            children: [
              Expanded(
                // Translucent: the headers under it still get their taps.
                child: GestureDetector(
                  key: const Key('window.drag'),
                  behavior: HitTestBehavior.translucent,
                  onPanStart: (_) => unawaited(controls.startDragging()),
                ),
              ),
              _WindowButton(
                key: const Key('window.minimize'),
                tooltip: 'Minimize',
                icon: Icons.minimize_rounded,
                onPressed: controls.minimize,
              ),
              _WindowButton(
                key: const Key('window.maximize'),
                tooltip: 'Maximize',
                icon: Icons.crop_square_rounded,
                onPressed: controls.toggleMaximize,
              ),
              _WindowButton(
                key: const Key('window.close'),
                tooltip: 'Close',
                icon: Icons.close_rounded,
                onPressed: controls.close,
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ],
    );
  }
}

class _WindowButton extends StatelessWidget {
  const _WindowButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: _buttonWidth,
    child: IconButton(
      tooltip: tooltip,
      iconSize: 18,
      icon: Icon(icon),
      onPressed: () => unawaited(onPressed()),
    ),
  );
}

/// The room a top-right header leaves for the window buttons; nothing when the platform
/// draws the title bar.
class WindowButtonsSpace extends ConsumerWidget {
  const WindowButtonsSpace({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => SizedBox(
    width: ref.watch(windowControlsProvider).drawsTitleBar
        ? 3 * _buttonWidth + 8
        : 0,
  );
}
