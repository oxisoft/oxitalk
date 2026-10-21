import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../matrix/api/matrix.dart';

/// What a room's badge shows, as Element X decides it.
enum BadgeKind {
  none,

  /// An invitation: an accent "!".
  invite,

  /// Unread mentions (or keywords): an accent "@" with the notifying count.
  mention,

  /// Unread messages that notify: an accent count.
  notifying,

  /// Unread but nothing that notifies, or marked unread: a small grey dot.
  dot,
}

/// A room's badge and the count it shows.
final class RoomBadge {
  const RoomBadge(this.kind, [this.count = 0]);

  final BadgeKind kind;
  final int count;
}

/// The badge of [room]. A muted room has none; it shows a crossed-out bell instead.
RoomBadge badgeOf(Room room) {
  if (room.membership == Membership.invited) {
    return const RoomBadge(BadgeKind.invite);
  }
  if (room.isMuted) return const RoomBadge(BadgeKind.none);
  final notifying = room.notifyingCount;
  if (room.unreadMentions > 0) return RoomBadge(BadgeKind.mention, notifying);
  if (notifying > 0) return RoomBadge(BadgeKind.notifying, notifying);
  if (room.hasUnread) return const RoomBadge(BadgeKind.dot);
  return const RoomBadge(BadgeKind.none);
}

/// [count] as a badge shows it: at most [max], then `max+`.
String badgeCount(int count, {int max = 999}) =>
    count > max ? '$max+' : '$count';

/// A room's badge beside its last message.
class RoomBadgeView extends StatelessWidget {
  const RoomBadgeView({required this.room, super.key});

  final Room room;

  @override
  Widget build(BuildContext context) {
    final badge = badgeOf(room);
    return switch (badge.kind) {
      BadgeKind.none => const SizedBox.shrink(),
      BadgeKind.dot => Container(
        key: Key('badge.dot.${room.id}'),
        margin: const EdgeInsets.only(left: 8),
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.outline,
          shape: BoxShape.circle,
        ),
      ),
      BadgeKind.invite => _Pill(key: Key('badge.invite.${room.id}'), text: '!'),
      BadgeKind.mention => _Pill(
        key: Key('badge.mention.${room.id}'),
        text: badge.count > 0 ? '@ ${badgeCount(badge.count)}' : '@',
      ),
      BadgeKind.notifying => _Pill(
        key: Key('badge.notifying.${room.id}'),
        text: badgeCount(badge.count),
      ),
    };
  }
}

/// A count in an accent pill, as a section header shows its total.
class CountBadge extends StatelessWidget {
  const CountBadge({required this.count, super.key});

  final int count;

  @override
  Widget build(BuildContext context) => _Pill(text: badgeCount(count));
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(left: 8),
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: OxiColors.accent,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

/// The crossed-out bell of a muted room.
class MutedIcon extends StatelessWidget {
  const MutedIcon({this.size = 16, this.color, super.key});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => Icon(
    Icons.notifications_off_outlined,
    size: size,
    semanticLabel: 'Muted',
    color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
  );
}

/// The narrow list's badge over a room's picture: the same as [RoomBadgeView], smaller; a
/// muted room shows its bell.
Widget narrowBadge(BuildContext context, Room room, Widget child) {
  final badge = badgeOf(room);
  final grey = Theme.of(context).colorScheme.outline;
  if (room.isMuted && room.membership != Membership.invited) {
    return Badge(
      key: Key('badge.muted.${room.id}'),
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      label: Icon(Icons.notifications_off_outlined, size: 10, color: grey),
      child: child,
    );
  }
  return switch (badge.kind) {
    BadgeKind.none => child,
    BadgeKind.dot => Badge(
      key: Key('badge.dot.${room.id}'),
      smallSize: 10,
      backgroundColor: grey,
      child: child,
    ),
    BadgeKind.invite || BadgeKind.mention || BadgeKind.notifying => Badge(
      key: Key('badge.${badge.kind.name}.${room.id}'),
      backgroundColor: OxiColors.accent,
      label: Text(switch (badge.kind) {
        BadgeKind.invite => '!',
        BadgeKind.mention => '@',
        _ => badgeCount(badge.count, max: 99),
      }),
      child: child,
    ),
  };
}
