/// What the app shows, independent of the bridge: features and fakes use only these.
library;

import 'dart:typed_data';

import 'notices.dart';

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
    this.isOneToOne = false,
    this.joinedMembers = 0,
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

  /// Whether [defaultNotificationMode] is the default for direct chats: the room has exactly
  /// two members, the rule of the SDK and Element X, which [isDm] needn't match.
  final bool isOneToOne;

  /// How many members have joined.
  final int joinedMembers;
  final bool isDm;
  final bool isEncrypted;

  /// How the user's messages show who read them: ticks with exactly one other member,
  /// the readers' pictures with more.
  ReadReceiptStyle get readReceiptStyle => switch (joinedMembers) {
    2 => ReadReceiptStyle.ticks,
    > 2 => ReadReceiptStyle.avatars,
    _ => ReadReceiptStyle.none,
  };

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
    isOneToOne: isOneToOne,
    joinedMembers: joinedMembers,
    isDm: isDm,
    isEncrypted: isEncrypted,
  );
}

/// How a chat shows that its messages were read.
enum ReadReceiptStyle {
  /// Nothing: no one else is in the chat (yet).
  none,

  /// With one other member, Telegram's ticks on the user's own messages: one when the
  /// server has it, two once the other has read up to it or further.
  ticks,

  /// In a group, the pictures of the members who read up to each message, under it, as
  /// Element shows them.
  avatars,
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

/// A message (or invitation) to show as an OS notification: it notifies by the push rules and
/// isn't the user's own.
final class MessageNotification {
  const MessageNotification({
    required this.roomId,
    required this.roomName,
    required this.senderId,
    required this.senderName,
    required this.time,
    this.eventId,
    this.threadRoot,
    this.senderAvatarUrl,
    this.text,
    this.isDm = false,
    this.isHighlight = false,
    this.sound = false,
    this.isInvite = false,
  });

  final String roomId;
  final String? eventId;

  /// The thread the message is a reply in.
  final String? threadRoot;
  final String roomName;
  final String senderId;
  final String senderName;

  /// An `mxc://` URI.
  final String? senderAvatarUrl;

  /// The message as one line; `null` when there is none to show (it stayed encrypted, an
  /// invitation, a poll).
  final String? text;
  final bool isDm;

  /// It mentions the user, @room or a keyword.
  final bool isHighlight;

  /// The push rules ask for a sound.
  final bool sound;
  final bool isInvite;
  final DateTime time;
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

/// Someone who has read a chat up to a message, from their read receipt.
final class ReadReceipt {
  const ReadReceipt({
    required this.userId,
    this.displayName,
    this.avatarUrl,
    this.time,
  });

  final String userId;
  final String? displayName;

  /// An `mxc://` URI.
  final String? avatarUrl;

  /// When they read it, if the server said.
  final DateTime? time;

  String get name => displayName ?? userId;
}

/// What every message has besides its content: how to name it for actions, its reactions,
/// what it answers, its thread, whether it was edited, and who has read up to it.
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
    this.readBy = const [],
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

  /// The other members whose latest read receipt is on this message (or on an event after
  /// it that the chat doesn't show), newest first; never the user.
  final List<ReadReceipt> readBy;

  /// What names the message in the timeline's actions.
  String? get ref => eventId ?? transactionId;

  EventMeta copyWith({List<ReadReceipt>? readBy}) => EventMeta(
    eventId: eventId,
    transactionId: transactionId,
    reactions: reactions,
    inReplyTo: inReplyTo,
    thread: thread,
    isEdited: isEdited,
    isEditable: isEditable,
    uploadPercent: uploadPercent,
    readBy: readBy ?? this.readBy,
  );
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
    this.isVoice = false,
    this.waveform,
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

  /// A voice message recorded in a chat app, rather than a sound file.
  final bool isVoice;

  /// An audio message's loudness over time, each point from 0 to [VoiceClip.waveformMax].
  final List<int>? waveform;
}

/// A recorded voice message, ready to send: an Ogg Opus file, its length and its waveform.
final class VoiceClip {
  const VoiceClip({
    required this.data,
    required this.duration,
    required this.waveform,
  });

  /// The loudest point of a [waveform].
  static const waveformMax = 1024;

  final Uint8List data;
  final Duration duration;

  /// From 0 to [waveformMax], the loudest at the top.
  final List<int> waveform;
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

/// A room event shown as a small line: who joined or left, a new name or topic, a poll.
/// [sender] is who did it.
final class NoticeEntry extends TimelineEntry {
  const NoticeEntry({
    required String id,
    required this.sender,
    required this.time,
    required this.notice,
    this.senderName,
    this.isOwn = false,
    this.eventId,
  }) : super(id);

  final String sender;
  final String? senderName;
  final DateTime time;
  final bool isOwn;
  final String? eventId;
  final RoomNotice notice;
}

/// The meta of a message entry of any kind; `null` for notices and day dividers.
EventMeta? entryMeta(TimelineEntry entry) => switch (entry) {
  MessageEntry(:final meta) ||
  MediaEntry(:final meta) ||
  UndecryptableEntry(:final meta) ||
  RedactedEntry(:final meta) => meta,
  NoticeEntry() || DayDivider() => null,
};

/// [entry], a message of any kind, with [meta] instead of its own; others as they are.
TimelineEntry withMeta(TimelineEntry entry, EventMeta meta) => switch (entry) {
  MessageEntry() => MessageEntry(
    id: entry.id,
    sender: entry.sender,
    time: entry.time,
    body: entry.body,
    formatted: entry.formatted,
    senderName: entry.senderName,
    senderAvatarUrl: entry.senderAvatarUrl,
    isOwn: entry.isOwn,
    sendState: entry.sendState,
    meta: meta,
  ),
  MediaEntry() => MediaEntry(
    id: entry.id,
    sender: entry.sender,
    time: entry.time,
    media: entry.media,
    senderName: entry.senderName,
    senderAvatarUrl: entry.senderAvatarUrl,
    isOwn: entry.isOwn,
    sendState: entry.sendState,
    meta: meta,
  ),
  UndecryptableEntry() => UndecryptableEntry(
    id: entry.id,
    sender: entry.sender,
    time: entry.time,
    senderName: entry.senderName,
    senderAvatarUrl: entry.senderAvatarUrl,
    isOwn: entry.isOwn,
    meta: meta,
  ),
  RedactedEntry() => RedactedEntry(
    id: entry.id,
    sender: entry.sender,
    time: entry.time,
    senderName: entry.senderName,
    senderAvatarUrl: entry.senderAvatarUrl,
    isOwn: entry.isOwn,
    meta: meta,
  ),
  NoticeEntry() || DayDivider() => entry,
};

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

/// Who may join a room.
enum RoomJoinRule {
  /// Only people who are invited.
  invite,

  /// Anyone may ask; a member lets them in.
  knock,

  /// Anyone who finds the room.
  public,

  /// Members of some other rooms (spaces); not chosen in this app.
  restricted,

  /// Members of some other rooms join, others may ask; not chosen in this app.
  knockRestricted,

  /// Anything else.
  other,
}

/// Who may read a room's messages.
enum RoomHistory {
  /// Members, all of the history from when this option was chosen.
  shared,

  /// Members, from when they were invited.
  invited,

  /// Members, from when they joined.
  joined,

  /// Anyone, members or not; only offered for public rooms.
  worldReadable,
}

/// What the user's power level lets them change in a room.
final class RoomPermissions {
  const RoomPermissions({
    this.name = false,
    this.topic = false,
    this.avatar = false,
    this.joinRule = false,
    this.history = false,
    this.encryption = false,
    this.address = false,
  });

  /// Everything, as for the room's creator.
  static const all = RoomPermissions(
    name: true,
    topic: true,
    avatar: true,
    joinRule: true,
    history: true,
    encryption: true,
    address: true,
  );

  final bool name;
  final bool topic;
  final bool avatar;
  final bool joinRule;
  final bool history;
  final bool encryption;

  /// The main address, and the listing in the room directory.
  final bool address;

  /// Whether any of the room's details (name, topic, picture) may be changed.
  bool get details => name || topic || avatar;

  @override
  bool operator ==(Object other) =>
      other is RoomPermissions &&
      other.name == name &&
      other.topic == topic &&
      other.avatar == avatar &&
      other.joinRule == joinRule &&
      other.history == history &&
      other.encryption == encryption &&
      other.address == address;

  @override
  int get hashCode =>
      Object.hash(name, topic, avatar, joinRule, history, encryption, address);
}

/// A room's settings as its state has them, with what the user may change.
final class RoomSettings {
  const RoomSettings({
    required this.roomId,
    this.name,
    this.topic,
    this.avatarUrl,
    this.joinRule = RoomJoinRule.invite,
    this.history = RoomHistory.shared,
    this.isEncrypted = false,
    this.mainAddress,
    this.serverName = '',
    this.knockSupported = true,
    this.permissions = const RoomPermissions(),
  });

  final String roomId;

  /// The name the room was given; `null` when it has none.
  final String? name;
  final String? topic;

  /// The room's own picture, an `mxc://` URI.
  final String? avatarUrl;
  final RoomJoinRule joinRule;
  final RoomHistory history;
  final bool isEncrypted;

  /// The main address, like `#team:example.org`.
  final String? mainAddress;

  /// The user's server, where a new address is made.
  final String serverName;

  /// Whether the room's version allows "ask to join".
  final bool knockSupported;
  final RoomPermissions permissions;

  RoomSettings copyWith({
    String? Function()? name,
    String? Function()? topic,
    String? Function()? avatarUrl,
    RoomJoinRule? joinRule,
    RoomHistory? history,
    bool? isEncrypted,
    String? Function()? mainAddress,
    RoomPermissions? permissions,
  }) => RoomSettings(
    roomId: roomId,
    name: name == null ? this.name : name(),
    topic: topic == null ? this.topic : topic(),
    avatarUrl: avatarUrl == null ? this.avatarUrl : avatarUrl(),
    joinRule: joinRule ?? this.joinRule,
    history: history ?? this.history,
    isEncrypted: isEncrypted ?? this.isEncrypted,
    mainAddress: mainAddress == null ? this.mainAddress : mainAddress(),
    serverName: serverName,
    knockSupported: knockSupported,
    permissions: permissions ?? this.permissions,
  );

  @override
  bool operator ==(Object other) =>
      other is RoomSettings &&
      other.roomId == roomId &&
      other.name == name &&
      other.topic == topic &&
      other.avatarUrl == avatarUrl &&
      other.joinRule == joinRule &&
      other.history == history &&
      other.isEncrypted == isEncrypted &&
      other.mainAddress == mainAddress &&
      other.serverName == serverName &&
      other.knockSupported == knockSupported &&
      other.permissions == permissions;

  @override
  int get hashCode => Object.hash(
    roomId,
    name,
    topic,
    avatarUrl,
    joinRule,
    history,
    isEncrypted,
    mainAddress,
    serverName,
    knockSupported,
    permissions,
  );
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

/// A device the account is signed in on (a session).
final class Device {
  const Device({
    required this.id,
    this.name,
    this.lastSeen,
    this.lastSeenIp,
    this.isThisDevice = false,
    this.verified = false,
  });

  final String id;

  /// The name the user (or the app at login) gave it, if any.
  final String? name;

  /// When the server last saw it, in local time, if it tells.
  final DateTime? lastSeen;

  /// The IP address it was last seen from, if the server tells.
  final String? lastSeenIp;

  /// The device the app runs on.
  final bool isThisDevice;

  /// Signed by the account's identity, so the user's other devices and contacts trust it.
  final bool verified;

  /// Its name, or its ID without one.
  String get label => name ?? id;
}

/// Whether the account's secrets are kept on the server with a recovery key, so a new
/// device can verify itself and read the old messages with it.
enum RecoveryState {
  /// Not known yet, e.g. right after login.
  unknown,

  /// Set up, and this device has every secret.
  enabled,

  /// Set up, but this device lacks some of the secrets; entering the key brings them.
  incomplete,

  /// Not set up.
  disabled,
}

/// What Settings › Account › Encryption shows: recovery and the key backup.
final class EncryptionStatus {
  const EncryptionStatus({
    this.recovery = RecoveryState.unknown,
    this.backupEnabled = false,
  });

  final RecoveryState recovery;

  /// Whether this device backs its message keys up to the server.
  final bool backupEnabled;
}

/// How far setting recovery up is.
sealed class RecoveryProgress {
  const RecoveryProgress();
}

/// Making the key backup, or the recovery key.
final class RecoveryPreparing extends RecoveryProgress {
  const RecoveryPreparing();
}

/// Backing the message keys up: [backedUp] of [total] so far.
final class RecoveryBackingUp extends RecoveryProgress {
  const RecoveryBackingUp(this.backedUp, this.total);

  final int backedUp;
  final int total;
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

/// A piece of a message the composer built: text as typed, or a pill.
sealed class MessagePart {
  const MessagePart();

  /// How it reads in the message's plain text.
  String get plain;
}

final class TextPart extends MessagePart {
  const TextPart(this.text);

  final String text;

  @override
  String get plain => text;
}

/// A user mentioned: shown and sent by their display name, linked to their ID.
final class UserPill extends MessagePart {
  const UserPill(this.userId, this.name);

  final String userId;
  final String name;

  @override
  String get plain => name.trim().isEmpty ? userId : name;
}

/// A room linked to: shown by its address when it has one, else by its name.
final class RoomPill extends MessagePart {
  const RoomPill({required this.roomId, required this.name, this.alias});

  final String roomId;
  final String name;

  /// Its main address, like `#team:example.org`.
  final String? alias;

  @override
  String get plain => alias ?? name;
}

/// `@room`: notifies everyone in the room.
final class AtRoomPill extends MessagePart {
  const AtRoomPill();

  @override
  String get plain => '@room';
}

/// The plain text of a message made of [parts].
String plainText(List<MessagePart> parts) =>
    parts.map((part) => part.plain).join();

/// A room the user is in, to link to with `#`.
final class MentionRoom {
  const MentionRoom({
    required this.roomId,
    required this.name,
    this.alias,
    this.avatarUrl,
  });

  final String roomId;
  final String name;

  /// Its main address, like `#team:example.org`.
  final String? alias;

  /// An `mxc://` URI.
  final String? avatarUrl;
}

/// Someone as their profile shows them.
final class UserProfile {
  const UserProfile({
    required this.userId,
    this.displayName,
    this.avatarUrl,
    this.verified,
    this.ignored = false,
    this.dmRoomId,
  });

  final String userId;
  final String? displayName;

  /// An `mxc://` URI.
  final String? avatarUrl;

  /// Whether the user verified them; `null` when they have no cross-signing identity, so
  /// they can't be verified.
  final bool? verified;
  final bool ignored;

  /// The user's direct chat with them, if any.
  final String? dmRoomId;

  String get name => displayName ?? userId;
}

/// Whether a composer draft is a new message, or answers or edits one.
enum DraftType { newMessage, reply, edit }

/// What a composer held when the user left it: its text and pills as typed, and the message it
/// answered or edited. Kept on the device in the account's encrypted store, never sent.
final class ComposerDraft {
  const ComposerDraft(
    this.parts, {
    this.type = DraftType.newMessage,
    this.eventId,
  });

  final List<MessagePart> parts;
  final DraftType type;

  /// The message answered or edited; `null` for a new message.
  final String? eventId;

  /// Whether there is any text in it (white space doesn't count).
  bool get hasText =>
      parts.any((part) => part is! TextPart || part.text.trim().isNotEmpty);

  /// Its first line with text, for the chat list.
  String get firstLine =>
      plainText(parts)
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .firstOrNull ??
      '';
}
