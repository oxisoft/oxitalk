import 'dart:math';

import '../../matrix/api/matrix.dart';

/// One section of the room list as shown: its rooms, newest activity first.
final class RoomGroup {
  const RoomGroup(this.tag, this.title, this.rooms);

  /// The section's tag, see [SectionTags].
  final String tag;
  final String title;
  final List<Room> rooms;

  bool get isCustom => SectionTags.isCustom(tag);

  /// Whether the user can move it among the others.
  bool get isMovable =>
      isCustom || tag == SectionTags.people || tag == SectionTags.rooms;

  /// Notifying unread messages plus invites; muted rooms count nothing.
  int get unread => rooms.fold(0, (sum, room) => sum + room.notifyingCount);
}

/// The movable sections in order, as Element orders them: as stored, without the ones that
/// are gone; People first and Rooms last unless stored elsewhere; a custom section missing
/// from the order goes just above Rooms.
List<String> movableOrder(Sections sections) {
  final custom = {for (final section in sections.custom) section.tag};
  bool known(String tag) =>
      tag == SectionTags.people ||
      tag == SectionTags.rooms ||
      custom.contains(tag);
  final order = [
    for (final tag in sections.order)
      if (known(tag)) tag,
  ];
  // Stored twice by some mishap: the first counts.
  final seen = <String>{};
  order.retainWhere(seen.add);
  if (!order.contains(SectionTags.people)) order.insert(0, SectionTags.people);
  if (!order.contains(SectionTags.rooms)) order.add(SectionTags.rooms);
  for (final tag in custom.where((tag) => !order.contains(tag))) {
    order.insert(order.indexOf(SectionTags.rooms), tag);
  }
  return order;
}

/// The section [room] is in: invites by membership, else its section tag (if the section
/// still exists), else People for a direct chat and Rooms for the rest.
String sectionOf(Room room, Sections sections) {
  if (room.membership == Membership.invited) return SectionTags.invites;
  final custom = {for (final section in sections.custom) section.tag};
  for (final tag in sections.roomTags[room.id] ?? const <String>[]) {
    if (tag == SectionTags.favourites ||
        tag == SectionTags.lowPriority ||
        custom.contains(tag)) {
      return tag;
    }
  }
  return room.isDm ? SectionTags.people : SectionTags.rooms;
}

/// The room list in sections, in display order, leaving out the empty ones.
List<RoomGroup> groupRooms(List<Room> rooms, Sections sections) {
  final names = {
    for (final section in sections.custom) section.tag: section.name,
  };
  final byTag = <String, List<Room>>{};
  for (final room in rooms) {
    byTag.putIfAbsent(sectionOf(room, sections), () => []).add(room);
  }
  return [
    for (final tag in [
      SectionTags.invites,
      SectionTags.favourites,
      ...movableOrder(sections),
      SectionTags.lowPriority,
    ])
      if (byTag[tag] case final rooms?)
        RoomGroup(tag, names[tag] ?? sectionTitle(tag), rooms),
  ];
}

String sectionTitle(String tag) => switch (tag) {
  SectionTags.invites => 'Invites',
  SectionTags.favourites => 'Favorites',
  SectionTags.people => 'People',
  SectionTags.rooms => 'Rooms',
  SectionTags.lowPriority => 'Low priority',
  _ => tag,
};

/// [order] with [tag] moved one place up ([by] = -1) or down (1).
List<String> moved(List<String> order, String tag, int by) {
  final from = order.indexOf(tag);
  final to = from + by;
  if (from < 0 || to < 0 || to >= order.length) return order;
  return [...order]
    ..removeAt(from)
    ..insert(to, tag);
}

/// A new custom section tag, in Element's form (a random UUID).
String newSectionTag([Random? random]) {
  final r = random ?? Random.secure();
  final bytes = List.generate(16, (_) => r.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')]
      .join();
  return '${SectionTags.customPrefix}'
      '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-${hex.substring(20)}';
}
