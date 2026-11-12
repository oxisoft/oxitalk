// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/chats/badges.dart';
import '../features/spaces/space_state.dart';
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

/// The app's picture and name, the account in front (its user ID), the space its list
/// shows (none for all chats), then the open chat's name. Where the bar is too narrow, the
/// space's name is shortened first, then the account's and the chat's.
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
    final space = account == null
        ? null
        : ref.watch(currentSpaceProvider(account));
    const muted = OxiColors.titleBarMuted;
    final mutedStyle = theme.textTheme.bodyMedium?.copyWith(color: muted);
    final roomStyle = theme.textTheme.bodyMedium?.copyWith(
      color: OxiColors.titleBarText,
    );
    // The whole account, user and server (@bkv:chat.oxisoft.net), not just a name.
    final accountName = account;
    const chevronStyle = TextStyle(
      color: OxiBrand.yellow,
      fontWeight: FontWeight.w800,
      fontSize: 16,
      height: 1,
    );
    Widget chevron() => const Padding(
      padding: EdgeInsets.symmetric(horizontal: 10),
      child: Text('›', style: chevronStyle),
    );
    final appStyle = theme.textTheme.titleSmall?.copyWith(
      color: Colors.white,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.3,
    );
    final lead = [
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
      Text('OxiTalk', key: const Key('titleBar.app'), style: appStyle),
    ];
    if (accountName == null) {
      return Row(mainAxisAlignment: MainAxisAlignment.center, children: lead);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context);
        double widthOf(String text, TextStyle? style) {
          final painter = TextPainter(
            text: TextSpan(text: text, style: style),
            textDirection: Directionality.of(context),
            textScaler: scale,
            maxLines: 1,
          )..layout();
          final width = painter.width;
          painter.dispose();
          return width.ceilToDouble() + 1;
        }

        // What isn't a name: the picture, OxiTalk, the chevrons and the room's icons.
        final chevrons = 1 + (space != null ? 1 : 0) + (room != null ? 1 : 0);
        final fixed =
            28 +
            widthOf('OxiTalk', appStyle) +
            chevrons * (20 + widthOf('›', chevronStyle)) +
            (room?.isEncrypted ?? false ? 17 : 0) +
            (room?.isMuted ?? false ? 20 : 0);
        final names = TitleWidths.fit(
          // A little room to spare for rounding.
          available: constraints.maxWidth - fixed - 4,
          account: widthOf(accountName, mutedStyle),
          space: space == null ? 0 : widthOf(space.name, mutedStyle),
          room: room == null ? 0 : widthOf(room.name, roomStyle),
        );
        Widget name(String text, Key key, TextStyle? style, double width) =>
            SizedBox(
              width: width,
              child: Text(
                text,
                key: key,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            );
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ...lead,
            chevron(),
            name(
              accountName,
              const Key('titleBar.account'),
              mutedStyle,
              names.account,
            ),
            if (space != null) ...[
              chevron(),
              name(
                space.name,
                const Key('titleBar.space'),
                mutedStyle,
                names.space,
              ),
            ],
            if (room != null) ...[
              chevron(),
              if (room.isEncrypted) ...[
                const Icon(Icons.lock_rounded, size: 13, color: muted),
                const SizedBox(width: 4),
              ],
              name(
                room.name,
                const Key('titleBar.room'),
                roomStyle,
                names.room,
              ),
              if (room.isMuted) ...[
                const SizedBox(width: 6),
                MutedIcon(
                  key: const Key('titleBar.muted'),
                  size: 14,
                  color: muted,
                ),
              ],
            ],
          ],
        );
      },
    );
  }
}

/// How wide the title bar's names are drawn: each as wide as it is while they fit; else
/// the space's is shortened first (down to [spaceMin]), then the account's and the chat's
/// share what is left, each at least its half of it.
final class TitleWidths {
  const TitleWidths(this.account, this.space, this.room);

  final double account;
  final double space;
  final double room;

  /// The narrowest a shortened space's name gets before the others give way.
  static const spaceMin = 48.0;

  static TitleWidths fit({
    required double available,
    required double account,
    required double space,
    required double room,
  }) {
    final room0 = room;
    var left = available < 0 ? 0.0 : available;
    if (account + space + room <= left) {
      return TitleWidths(account, space, room);
    }
    // The space first.
    final spaceFloor = space < spaceMin ? space : spaceMin;
    final spaceWidth = (left - account - room).clamp(spaceFloor, space);
    left = (left - spaceWidth).clamp(0, double.infinity).toDouble();
    if (account + room <= left) {
      return TitleWidths(account, spaceWidth.toDouble(), room);
    }
    // Then the account and the chat: each keeps what it needs up to half, the other takes
    // the rest.
    final half = left / 2;
    final accountWidth = account <= half
        ? account
        : room0 <= half
        ? left - room0
        : half;
    final roomWidth = (left - accountWidth).clamp(0, room0).toDouble();
    return TitleWidths(accountWidth, spaceWidth.toDouble(), roomWidth);
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
