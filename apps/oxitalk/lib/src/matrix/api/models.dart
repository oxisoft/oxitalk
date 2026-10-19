/// What the app shows, independent of the bridge: features and fakes use only these.
library;

enum Membership { joined, invited, knocked, left, banned }

final class Room {
  const Room({
    required this.id,
    required this.name,
    this.membership = Membership.joined,
    this.lastMessage,
    this.lastActivity,
    this.unreadCount = 0,
    this.isDm = false,
    this.isEncrypted = false,
  });

  final String id;
  final String name;
  final Membership membership;

  /// The latest text message, if the latest event is one.
  final String? lastMessage;
  final DateTime? lastActivity;
  final int unreadCount;
  final bool isDm;
  final bool isEncrypted;

  Room copyWith({
    Membership? membership,
    String? lastMessage,
    int? unreadCount,
  }) => Room(
    id: id,
    name: name,
    membership: membership ?? this.membership,
    lastMessage: lastMessage ?? this.lastMessage,
    lastActivity: lastActivity,
    unreadCount: unreadCount ?? this.unreadCount,
    isDm: isDm,
    isEncrypted: isEncrypted,
  );
}

enum SendState { sending, sent, failed }

/// One visible line of a timeline, oldest first.
sealed class TimelineEntry {
  const TimelineEntry(this.id);

  /// Stable for the entry's life, also across a local echo turning into the sent event.
  final String id;
}

final class MessageEntry extends TimelineEntry {
  const MessageEntry({
    required String id,
    required this.sender,
    required this.time,
    required this.body,
    this.senderName,
    this.isOwn = false,
    this.sendState = SendState.sent,
  }) : super(id);

  final String sender;
  final String? senderName;
  final DateTime time;
  final String body;
  final bool isOwn;
  final SendState sendState;
}

/// An encrypted message whose key hasn't arrived (yet).
final class UndecryptableEntry extends TimelineEntry {
  const UndecryptableEntry({
    required String id,
    required this.sender,
    required this.time,
    this.senderName,
    this.isOwn = false,
  }) : super(id);

  final String sender;
  final String? senderName;
  final DateTime time;
  final bool isOwn;
}

final class DayDivider extends TimelineEntry {
  const DayDivider({required String id, required this.day}) : super(id);

  final DateTime day;
}

/// The connection as the user sees it.
enum SyncStatus {
  /// Starting, or restarting after an error.
  connecting,

  /// Syncing.
  online,

  /// The server can't be reached; syncing resumes by itself.
  offline,
}
