/// What the app shows, independent of the bridge: features and fakes use only these.
library;

enum Membership { joined, invited, knocked, left, banned }

final class Room {
  const Room({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.membership = Membership.joined,
    this.lastMessage,
    this.lastActivity,
    this.unreadCount = 0,
    this.isDm = false,
    this.isEncrypted = false,
  });

  final String id;
  final String name;

  /// An `mxc://` URI: the room's avatar or, in a direct chat without one, the other person's.
  final String? avatarUrl;
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
    avatarUrl: avatarUrl,
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
    this.senderAvatarUrl,
    this.isOwn = false,
    this.sendState = SendState.sent,
  }) : super(id);

  final String sender;
  final String? senderName;

  /// An `mxc://` URI.
  final String? senderAvatarUrl;
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
    this.senderAvatarUrl,
    this.isOwn = false,
  }) : super(id);

  final String sender;
  final String? senderName;

  /// An `mxc://` URI.
  final String? senderAvatarUrl;
  final DateTime time;
  final bool isOwn;
}

final class DayDivider extends TimelineEntry {
  const DayDivider({required String id, required this.day}) : super(id);

  final DateTime day;
}

/// The room list sections, as Element keeps them: a room is in a section by a room tag, and
/// the sections the user made and the order of the movable ones are account settings.
final class Sections {
  const Sections({
    this.custom = const [],
    this.order = const [],
    this.roomTags = const {},
  });

  /// The sections the user made.
  final List<CustomSection> custom;

  /// The order of the movable sections as stored: custom section tags, [SectionTags.people]
  /// and [SectionTags.rooms]. May name sections that are gone, or miss some.
  final List<String> order;

  /// Each room's tags, by room ID.
  final Map<String, List<String>> roomTags;
}

final class CustomSection {
  const CustomSection(this.tag, this.name);

  /// `element.io.section.<id>`.
  final String tag;
  final String name;
}

/// Element's names for the sections.
abstract final class SectionTags {
  static const invites = 'im.vector.fake.invite';
  static const favourites = 'm.favourite';
  static const people = 'im.vector.fake.direct';
  static const rooms = 'chats';
  static const lowPriority = 'm.lowpriority';
  static const customPrefix = 'element.io.section.';

  static bool isCustom(String tag) => tag.startsWith(customPrefix);

  /// A tag that puts a room in a section.
  static bool isSection(String tag) =>
      tag == favourites || tag == lowPriority || isCustom(tag);
}

/// The user's own profile.
final class Profile {
  const Profile({this.displayName, this.avatarUrl});

  final String? displayName;

  /// An `mxc://` URI.
  final String? avatarUrl;
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

/// Whether this device is verified: signed by the account's identity, so other people's
/// devices trust it and it can get keys from the user's other devices and the backup.
enum VerificationStatus {
  /// Not known yet, e.g. right after login before the keys are fetched.
  unknown,
  verified,
  unverified,
}

/// Another device of the user asking to be verified, or to verify this one.
final class VerificationRequest {
  const VerificationRequest({
    required this.flowId,
    required this.deviceId,
    this.deviceName,
  });

  final String flowId;
  final String deviceId;
  final String? deviceName;
}

final class VerificationEmoji {
  const VerificationEmoji(this.symbol, this.description);

  final String symbol;
  final String description;
}

/// Where a verification with another device stands, as the user sees it.
sealed class VerificationStep {
  const VerificationStep();
}

/// Waiting for the other device: to accept the request, or to agree on the emoji.
final class VerificationWaiting extends VerificationStep {
  const VerificationWaiting();
}

/// The other device asked; accept or cancel.
final class VerificationIncoming extends VerificationStep {
  const VerificationIncoming();
}

/// Compare these with the other device, then confirm or report a mismatch. [emojis] is empty
/// when the other device can't show emoji; compare [decimals] then.
final class VerificationCompare extends VerificationStep {
  const VerificationCompare(this.emojis, this.decimals);

  final List<VerificationEmoji> emojis;
  final List<int> decimals;
}

/// This side confirmed; waiting for the other.
final class VerificationConfirmed extends VerificationStep {
  const VerificationConfirmed();
}

final class VerificationDone extends VerificationStep {
  const VerificationDone();
}

final class VerificationCancelled extends VerificationStep {
  const VerificationCancelled(this.reason, {this.byUs = false});

  final String reason;
  final bool byUs;
}
