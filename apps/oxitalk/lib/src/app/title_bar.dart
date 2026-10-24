import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/chats/badges.dart';
import 'providers.dart';
import 'router.dart';
import 'theme.dart';
import 'window_controls.dart';

/// The window's title bar, where the app draws its own: the app's name and the open chat's,
/// and the window's buttons. It is a bar of its own above every pane, so its Close reads as
/// closing the app, not the chat or the thread under it. Nothing where the platform draws
/// the title bar.
class AppTitleBar extends ConsumerWidget {
  const AppTitleBar({super.key});

  static const height = 38.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(windowControlsProvider).drawsTitleBar) {
      return const SizedBox.shrink();
    }
    final router = ref.watch(routerProvider);
    // Flat ink in both themes, as the app icon's background.
    return Material(
      key: const Key('titleBar'),
      color: OxiColors.titleBar,
      child: Container(
        height: height,
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: OxiColors.titleBarLine)),
        ),
        child: Stack(
          children: [
            const Positioned.fill(child: WindowDragArea()),
            // Fills the bar, so the row centres its content in the bar's height.
            Positioned.fill(
              child: Row(
                children: [
                  const WindowButtons.left(),
                  const SizedBox(width: 8),
                  Expanded(
                    // The title follows the open chat as the route changes.
                    child: IgnorePointer(
                      child: ListenableBuilder(
                        listenable: router.routerDelegate,
                        // Not `router.state`: that throws before the first route is set.
                        builder: (context, _) => _Title(
                          roomId: router
                              .routerDelegate
                              .currentConfiguration
                              .pathParameters['roomId'],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const WindowButtons.right(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The app's picture and name, the account in front (its user ID), then the open chat's name.
class _Title extends ConsumerWidget {
  const _Title({required this.roomId});

  final String? roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final account = ref.watch(activeAccountProvider);
    final room = switch ((account, roomId)) {
      (final account?, final id?) =>
        ref
            .watch(roomsProvider(account))
            .value
            ?.where((room) => room.id == id)
            .firstOrNull,
      _ => null,
    };
    const muted = OxiColors.titleBarMuted;
    // The whole account, user and server (@bkv:chat.oxisoft.net), not just a name.
    final accountName = account;
    Widget chevron() => const Padding(
      padding: EdgeInsets.symmetric(horizontal: 10),
      child: Text(
        '›',
        style: TextStyle(
          color: OxiBrand.yellow,
          fontWeight: FontWeight.w800,
          fontSize: 16,
          height: 1,
        ),
      ),
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: Image.asset(
            'assets/branding/oxitalk-icon-96.png',
            width: 20,
            height: 20,
            filterQuality: FilterQuality.medium,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'OxiTalk',
          key: const Key('titleBar.app'),
          style: theme.textTheme.titleSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.3,
          ),
        ),
        if (accountName != null) ...[
          chevron(),
          Flexible(
            child: Text(
              accountName,
              key: const Key('titleBar.account'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(color: muted),
            ),
          ),
        ],
        if (room != null) ...[
          chevron(),
          if (room.isEncrypted) ...[
            const Icon(Icons.lock_rounded, size: 13, color: muted),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              room.name,
              key: const Key('titleBar.room'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: OxiColors.titleBarText,
              ),
            ),
          ),
          if (room.isMuted) ...[
            const SizedBox(width: 6),
            MutedIcon(key: const Key('titleBar.muted'), size: 14, color: muted),
          ],
        ],
      ],
    );
  }
}

/// [child] under the app's title bar, where it draws one.
///
/// The bar sits above the navigator, so it brings an overlay of its own for its tooltips,
/// painted over [child] so a tooltip is not cut off at the bar's edge.
class WithTitleBar extends ConsumerStatefulWidget {
  const WithTitleBar({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<WithTitleBar> createState() => _WithTitleBarState();
}

class _WithTitleBarState extends ConsumerState<WithTitleBar> {
  /// Made when the bar is first drawn, and in its overlay from then on.
  OverlayEntry? _bar;

  @override
  void dispose() {
    _bar
      ?..remove()
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final drawn = ref.watch(windowControlsProvider).drawsTitleBar;
    return Stack(
      children: [
        Positioned.fill(
          top: drawn ? AppTitleBar.height : 0,
          child: widget.child,
        ),
        if (drawn)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: AppTitleBar.height,
            child: Overlay(
              clipBehavior: Clip.none,
              initialEntries: [
                _bar ??= OverlayEntry(builder: (_) => const AppTitleBar()),
              ],
            ),
          ),
      ],
    );
  }
}
