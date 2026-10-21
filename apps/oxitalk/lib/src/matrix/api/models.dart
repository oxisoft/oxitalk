/// What the app shows, independent of the bridge: features and fakes use only these.
library;

enum Membership { joined, invited, knocked, left, banned }

/// What a room notifies for, as Element names the choices. The account's defaults are never
/// [mute].
enum NotificationMode {
  allMessages,

  /// Only messages that mention the user (or @room) or contain one of their keywords.
  mentionsAndKeywords,

  /// Nothing, and no count badge.
  mute,
}

/// Keeps a field as it is in a `copyWith` whose `null` means something.
const _keep = Object();

final class Room {
  const Room({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.membership = Membership.joined,
    this.lastMessage,
    this.lastActivity,
    this.unreadCount = 0,
    this.unreadNotifications = 0,
    this.unreadMentions = 0,
    this.markedUnread = false,
    this.notificationMode,
    this.defaultNotificationMode = NotificationMode.allMessages,
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

  /// Unread messages, notifying or not.
  final int unreadCount;

  /// Unread messages that notify by the room's mode: all, only mentions and keywords, or none
  /// when muted.
  final int unreadNotifications;

  /// Unread messages that mention the user (or @room) or contain a keyword.
  final int unreadMentions;

  /// Marked unread by the user, here or in another client.
  final bool markedUnread;

  /// The room's own mode; `null` while it follows [defaultNotificationMode].
  final NotificationMode? notificationMode;

  /// The account's default for this kind of room.
  final NotificationMode defaultNotificationMode;
  final bool isDm;
  final bool isEncrypted;

  /// The mode the room notifies by.
  NotificationMode get effectiveNotificationMode =>
      notificationMode ?? defaultNotificationMode;

  bool get isMuted => effectiveNotificationMode == NotificationMode.mute;

  /// What the room adds to its section's and its account's count, as Element X counts: one for
  /// an invitation, nothing when muted, else its notifying unread messages (a mention
  /// notifies even where the count missed it).
  int get notifyingCount {
    if (membership == Membership.invited) return 1;
    if (isMuted) return 0;
    return unreadNotifications > unreadMentions
        ? unreadNotifications
        : unreadMentions;
  }

  /// Anything unread, notifying or not, or marked unread.
  bool get hasUnread =>
      unreadCount > 0 ||
      unreadNotifications > 0 ||
      unreadMentions > 0 ||
      markedUnread;

  /// With [notificationMode] `null` the room follows its default again.
  Room copyWith({
    Membership? membership,
    String? lastMessage,
    int? unreadCount,
    int? unreadNotifications,
    int? unreadMentions,
    bool? markedUnread,
    Object? notificationMode = _keep,
    NotificationMode? defaultNotificationMode,
  }) => Room(
    id: id,
    name: name,
    avatarUrl: avatarUrl,
    membership: membership ?? this.membership,
    lastMessage: lastMessage ?? this.lastMessage,
    lastActivity: lastActivity,
    unreadCount: unreadCount ?? this.unreadCount,
    unreadNotifications: unreadNotifications ?? this.unreadNotifications,
    unreadMentions: unreadMentions ?? this.unreadMentions,
    markedUnread: markedUnread ?? this.markedUnread,
    notificationMode: identical(notificationMode, _keep)
        ? this.notificationMode
        : notificationMode as NotificationMode?,
    defaultNotificationMode:
        defaultNotificationMode ?? this.defaultNotificationMode,
    isDm: isDm,
    isEncrypted: isEncrypted,
  );
}

/// The account's notification settings, kept on the server and shared with Element.
final class NotificationSettings {
  const NotificationSettings({
    this.dmDefault = NotificationMode.allMessages,
    this.groupDefault = NotificationMode.allMessages,
    this.roomMentions,
    this.invites,
    this.keywords = const [],
    this.inconsistent = false,
  });

  /// The default for direct chats (rooms of exactly two people).
  final NotificationMode dmDefault;

  /// The default for every other room.
  final NotificationMode groupDefault;

  /// Whether @room notifies; `null` if the server has no such rule.
  final bool? roomMentions;

  /// Whether an invitation notifies; `null` if the server has no such rule.
  final bool? invites;

  /// Words that make a message notify wherever it is sent.
  final List<String> keywords;

  /// Another client left the defaults for encrypted and unencrypted rooms different; the
  /// defaults show as "All messages" until fixed.
  final bool inconsistent;

  NotificationSettings copyWith({
    NotificationMode? dmDefault,
    NotificationMode? groupDefault,
    bool? roomMentions,
    bool? invites,
    List<String>? keywords,
    bool? inconsistent,
  }) => NotificationSettings(
    dmDefault: dmDefault ?? this.dmDefault,
    groupDefault: groupDefault ?? this.groupDefault,
    roomMentions: roomMentions ?? this.roomMentions,
    invites: invites ?? this.invites,
    keywords: keywords ?? this.keywords,
    inconsistent: inconsistent ?? this.inconsistent,
  );
}

enum SendState { sending, sent, failed }

/// What kind of block of formatted text.
sealed class BlockKind {
  const BlockKind();
}

final class ParagraphBlock extends BlockKind {
  const ParagraphBlock();
}

final class HeadingBlock extends BlockKind {
  const HeadingBlock(this.level);

  /// 1–6.
  final int level;
}

/// A list item: [number] is `null` for a bullet; [depth] is 1 for a top-level list.
final class ListItemBlock extends BlockKind {
  const ListItemBlock({this.number, this.depth = 1});

  final int? number;
  final int depth;
}

final class CodeBlock extends BlockKind {
  const CodeBlock([this.language]);

  final String? language;
}

final class RuleBlock extends BlockKind {
  const RuleBlock();
}

/// A block of formatted text, perhaps in quotes.
final class RichBlock {
  const RichBlock(this.kind, this.spans, {this.quoteDepth = 0});

  final BlockKind kind;
  final List<RichSpan> spans;
  final int quoteDepth;
}

/// A run of text in one style.
final class RichSpan {
  const RichSpan(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.strike = false,
    this.underline = false,
    this.code = false,
    this.spoiler = false,
    this.link,
    this.mention,
    this.color,
  });

  final String text;
  final bool bold;
  final bool italic;
  final bool strike;
  final bool underline;
  final bool code;

  /// Hidden until clicked.
  final bool spoiler;
  final String? link;

  /// The user ID of a user mentioned.
  final String? mention;

  /// A CSS colour like `#ff0000`.
  final String? color;
}

/// One emoji (or other key) given to a message, and by whom.
final class Reaction {
  const Reaction(this.key, this.senders, {this.mine = false});

  final String key;

  /// User IDs, first given first.
  final List<String> senders;

  /// Whether the user is among them.
  final bool mine;
}

/// What a reply shows of the message it answers.
final class ReplyQuote {
  const ReplyQuote({
    required this.eventId,
    this.sender,
    this.senderName,
    this.text,
  });

  final String eventId;

  /// `null` until the original is loaded.
  final String? sender;
  final String? senderName;
  final String? text;
}

/// A message in a thread as the thread's summary or the thread list shows it.
final class ThreadEvent {
  const ThreadEvent({
    required this.sender,
    required this.time,
    this.senderName,
    this.senderAvatarUrl,
    this.text,
  });

  final String sender;
  final String? senderName;

  /// An `mxc://` URI.
  final String? senderAvatarUrl;

  /// Its text, or a file's caption or name; `null` for other events.
  final String? text;
  final DateTime time;
}

/// A thread under its first message: how many replies, and the latest.
final class ThreadSummary {
  const ThreadSummary({required this.replyCount, this.latest});

  final int replyCount;

  /// `null` until the latest reply is loaded.
  final ThreadEvent? latest;
}

/// One thread of a room, for the room's thread list.
final class RoomThread {
  const RoomThread({
    required this.rootEventId,
    required this.root,
    required this.replyCount,
    this.latest,
  });

  /// The event ID of the thread's first message, which opens it.
  final String rootEventId;
  final ThreadEvent root;
  final ThreadEvent? latest;
  final int replyCount;
}

/// What every message has besides its content: how to name it for actions, its reactions,
/// what it answers, its thread, and whether it was edited.
final class EventMeta {
  const EventMeta({
    this.eventId,
    this.transactionId,
    this.reactions = const [],
    this.inReplyTo,
    this.thread,
    this.isEdited = false,
    this.isEditable = false,
    this.uploadPercent,
  });

  /// `null` until the server has accepted a local echo.
  final String? eventId;

  /// A local echo's ID until then.
  final String? transactionId;
  final List<Reaction> reactions;
  final ReplyQuote? inReplyTo;

  /// The thread that starts at this message, if it has replies.
  final ThreadSummary? thread;
  final bool isEdited;

  /// The user's own text message or caption.
  final bool isEditable;

  /// While an attachment uploads, 0–100.
  final int? uploadPercent;

  /// What names the message in the timeline's actions.
  String? get ref => eventId ?? transactionId;
}

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
    this.formatted,
    this.senderName,
    this.senderAvatarUrl,
    this.isOwn = false,
    this.sendState = SendState.sent,
    this.meta = const EventMeta(),
  }) : super(id);

  final EventMeta meta;

  /// The formatted version of [body], if the sender formatted it.
  final List<RichBlock>? formatted;

  final String sender;
  final String? senderName;

  /// An `mxc://` URI.
  final String? senderAvatarUrl;
  final DateTime time;
  final String body;
  final bool isOwn;
  final SendState sendState;
}

enum MediaKind { image, video, audio, file }

/// A file in a message.
final class MediaInfo {
  const MediaInfo({
    required this.kind,
    required this.source,
    required this.filename,
    this.thumbnail,
    this.caption,
    this.formattedCaption,
    this.mimeType,
    this.size,
    this.width,
    this.height,
    this.duration,
  });

  final MediaKind kind;

  /// Where the file is, opaque; the session fetches it.
  final String source;

  /// The same for a thumbnail the sender attached.
  final String? thumbnail;
  final String filename;

  /// Text the sender wrote with the file.
  final String? caption;

  /// The caption's formatting, if any.
  final List<RichBlock>? formattedCaption;
  final String? mimeType;

  /// In bytes.
  final int? size;
  final int? width;
  final int? height;
  final Duration? duration;
}

/// A message with an image, video, audio or other file.
final class MediaEntry extends TimelineEntry {
  const MediaEntry({
    required String id,
    required this.sender,
    required this.time,
    required this.media,
    this.senderName,
    this.senderAvatarUrl,
    this.isOwn = false,
    this.sendState = SendState.sent,
    this.meta = const EventMeta(),
  }) : super(id);

  final EventMeta meta;

  final String sender;
  final String? senderName;

  /// An `mxc://` URI.
  final String? senderAvatarUrl;
  final DateTime time;
  final MediaInfo media;
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
    this.meta = const EventMeta(),
  }) : super(id);

  final String sender;
  final String? senderName;

  /// An `mxc://` URI.
  final String? senderAvatarUrl;
  final DateTime time;
  final bool isOwn;
  final EventMeta meta;
}

/// A message that was deleted.
final class RedactedEntry extends TimelineEntry {
  const RedactedEntry({
    required String id,
    required this.sender,
    required this.time,
    this.senderName,
    this.senderAvatarUrl,
    this.isOwn = false,
    this.meta = const EventMeta(),
  }) : super(id);

  final String sender;
  final String? senderName;

  /// An `mxc://` URI.
  final String? senderAvatarUrl;
  final DateTime time;
  final bool isOwn;
  final EventMeta meta;
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

/// What a chat's info screen shows about it.
final class RoomDetails {
  const RoomDetails({
    required this.roomId,
    required this.name,
    this.avatarUrl,
    this.topic,
    this.alias,
    this.joinedMembers = 0,
    this.isEncrypted = false,
    this.dmUserId,
    this.dmUserVerified,
    this.ownPowerLevel = 0,
  });

  final String roomId;
  final String name;

  /// An `mxc://` URI.
  final String? avatarUrl;
  final String? topic;

  /// The room's main address, like `#team:example.org`.
  final String? alias;
  final int joinedMembers;
  final bool isEncrypted;

  /// The other person of a direct chat.
  final String? dmUserId;

  /// Whether the user verified [dmUserId]; `null` if unknown.
  final bool? dmUserVerified;

  /// The user's own power level; `null` for a room creator who is above every number.
  final int? ownPowerLevel;
}

enum MemberRole { admin, moderator, member }

final class RoomMember {
  const RoomMember({
    required this.userId,
    this.displayName,
    this.avatarUrl,
    this.role = MemberRole.member,
    this.powerLevel = 0,
    this.invited = false,
    this.banned = false,
    this.canChangeRole = false,
    this.canRemove = false,
    this.canBan = false,
    this.canUnban = false,
  });

  final String userId;
  final String? displayName;

  /// An `mxc://` URI.
  final String? avatarUrl;
  final MemberRole role;

  /// 100 is Admin, 50 Moderator, 0 a plain member; `null` for a room creator who is above
  /// every number.
  final int? powerLevel;

  /// Invited, not joined yet.
  final bool invited;

  /// Banned: listed so they can be unbanned.
  final bool banned;

  /// What the user may do to them.
  final bool canChangeRole;
  final bool canRemove;
  final bool canBan;
  final bool canUnban;

  RoomMember copyWith({
    MemberRole? role,
    int? powerLevel,
    bool? invited,
    bool? banned,
    bool? canChangeRole,
    bool? canRemove,
    bool? canBan,
    bool? canUnban,
  }) => RoomMember(
    userId: userId,
    displayName: displayName,
    avatarUrl: avatarUrl,
    role: role ?? this.role,
    powerLevel: powerLevel ?? this.powerLevel,
    invited: invited ?? this.invited,
    banned: banned ?? this.banned,
    canChangeRole: canChangeRole ?? this.canChangeRole,
    canRemove: canRemove ?? this.canRemove,
    canBan: canBan ?? this.canBan,
    canUnban: canUnban ?? this.canUnban,
  );
}

/// Someone to chat with.
final class Person {
  const Person(this.userId, {this.displayName, this.avatarUrl});

  final String userId;
  final String? displayName;

  /// An `mxc://` URI.
  final String? avatarUrl;
}

/// A room in the server's public directory.
final class PublicRoom {
  const PublicRoom({
    required this.roomId,
    this.name,
    this.topic,
    this.alias,
    this.members = 0,
    this.avatarUrl,
    this.joined = false,
  });

  final String roomId;
  final String? name;
  final String? topic;

  /// Its main address, like `#team:example.org`.
  final String? alias;
  final int members;

  /// An `mxc://` URI.
  final String? avatarUrl;

  /// The user is in it already.
  final bool joined;
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
