import 'dart:typed_data';

import 'models.dart';
import 'pins.dart';
import 'search.dart';

export 'models.dart';
export 'pins.dart';
export 'search.dart';

enum FailureKind {
  invalidServer,
  network,
  forbidden,
  sessionExpired,
  wrongStorePassphrase,
  invalidId,
  roomNotFound,
  wrongRecoveryKey,

  /// Logging in to an account that is already in the app.
  alreadyLoggedIn,
  recoveryNotSetUp,
  internal,
}

/// Every failure the Matrix layer reports. The UI matches on [kind]; [message] is for logs.
final class MatrixFailure implements Exception {
  const MatrixFailure(this.kind, [this.message = '']);

  final FailureKind kind;
  final String message;

  @override
  String toString() =>
      'MatrixFailure(${kind.name}${message.isEmpty ? '' : ': $message'})';
}

/// The user's accounts: logs in to more of them, and brings back the saved ones.
abstract interface class MatrixClientFactory {
  /// Logs in and saves the session as one more account. [server] is a server name
  /// (`matrix.org`) or a homeserver URL. Throws [MatrixFailure] with
  /// [FailureKind.alreadyLoggedIn] if the user is already one of the accounts.
  Future<MatrixSession> login({
    required String server,
    required String username,
    required String password,
  });

  /// Every saved account, in the order they were added. One that can't be opened any more is
  /// dropped.
  Future<List<MatrixSession>> restoreAll();

  /// The user ID of the account that was in front last time, if any.
  Future<String?> readActive();

  Future<void> writeActive(String userId);
}

/// A logged-in account. It syncs from creation until [logout] or [close].
abstract interface class MatrixSession {
  String get userId;

  /// The current status, then every change.
  Stream<SyncStatus> get syncStatus;

  /// The current room list (`null` until the first one arrives), then every change.
  Stream<List<Room>?> get rooms;

  /// Completes when the server has rejected the session. The saved session is gone by then;
  /// the user has to log in again.
  Future<void> get expired;

  /// The current verification status of this device, then every change.
  Stream<VerificationStatus> get verificationStatus;

  /// Requests from the user's other devices to verify (or be verified by) this one.
  Stream<VerificationRequest> get verificationRequests;

  /// Verifies this device with the recovery key or security phrase. Throws [MatrixFailure]
  /// with [FailureKind.wrongRecoveryKey] or [FailureKind.recoveryNotSetUp].
  Future<void> recover(String key);

  /// Asks the user's other devices to verify this one.
  Future<DeviceVerification> requestVerification();

  /// Opens a request from [verificationRequests].
  Future<DeviceVerification> openVerification(String flowId);

  /// The user's profile (empty until it is fetched), then every change made here.
  Stream<Profile> get profile;

  /// Makes [data], an image of type [mimeType] (`image/png`), the user's avatar.
  Future<void> setAvatar(Uint8List data, String mimeType);

  Future<void> removeAvatar();

  /// A square thumbnail of the picture at [mxcUrl], about [size] pixels wide, as encoded
  /// image bytes.
  Future<Uint8List> thumbnail(String mxcUrl, int size);

  /// Who is typing in which room: room ID → their names, the user left out; rooms where
  /// nobody types are absent. The current state, then every change.
  Stream<Map<String, List<String>>> get typing;

  /// The room list sections (empty until they are read), then every change.
  Stream<Sections> get sections;

  /// Puts the room in the section with [tag] ([SectionTags.favourites],
  /// [SectionTags.lowPriority] or a custom one), or with `null` in its default one. A room is
  /// in one section at a time.
  Future<void> setRoomSection(String roomId, String? tag);

  /// Saves the user's sections and the order of the movable ones.
  Future<void> saveSections(List<CustomSection> custom, List<String> order);

  /// The account's notification settings (`null` until they are read), then every change,
  /// made here or in another client.
  Stream<NotificationSettings?> get notificationSettings;

  /// Every message from now on that should show as an OS notification: it notifies by the
  /// push rules (encrypted ones are decrypted first), and it isn't the user's own.
  Stream<MessageNotification> get notifications;

  /// Gives the room its own [mode], or with `null` lets it follow the default again.
  Future<void> setRoomNotificationMode(String roomId, NotificationMode? mode);

  /// Sets the default for direct chats or for group chats; [mode] is never
  /// [NotificationMode.mute].
  Future<void> setDefaultNotificationMode({
    required bool directChats,
    required NotificationMode mode,
  });

  /// Makes defaults that another client left inconsistent consistent, as Element X does.
  Future<void> fixNotificationDefaults();

  /// Whether @room notifies.
  Future<void> setRoomMentionsEnabled(bool enabled);

  /// Whether an invitation notifies.
  Future<void> setInvitesEnabled(bool enabled);

  Future<void> addNotificationKeyword(String keyword);

  Future<void> removeNotificationKeyword(String keyword);

  /// Marks the room unread for the user's devices, or takes the mark away.
  Future<void> setMarkedUnread(String roomId, bool unread);

  /// Marks the room read up to its latest message and takes away its unread mark.
  Future<void> markRoomRead(String roomId);

  /// The whole file of a message ([MediaInfo.source]), from the cache or the server.
  Future<Uint8List> mediaContent(String source);

  /// A picture of a message's file about [size] pixels wide, for showing it small.
  Future<Uint8List> mediaThumbnail(String source, String? thumbnail, int size);

  /// Writes a message's whole file to [path].
  Future<void> saveMedia(String source, String path);

  /// Keeps cached media until unused for [days], or forever with `null`.
  Future<void> setMediaRetention(int? days);

  /// The size of the media cache in bytes, if known.
  Future<int?> mediaCacheSize();

  Future<void> clearMediaCache();

  Future<RoomDetails> roomDetails(String roomId);

  /// Joined and invited members, admins first.
  Future<List<RoomMember>> roomMembers(String roomId);

  /// A timeline of only the room's files and messages with links.
  Future<RoomTimeline> openMediaTimeline(String roomId);

  /// The thread that starts at the message [rootEventId]: that message, then the replies.
  /// What is sent through it goes into the thread.
  Future<RoomTimeline> openThread(String roomId, String rootEventId);

  /// The room's threads, most recent first.
  Future<ThreadList> openThreadList(String roomId);

  /// The emojis the user used lately, the last used first; the same on every device.
  Future<List<String>> recentEmojis();

  Future<void> addRecentEmoji(String emoji);

  /// Creates an encrypted direct chat and invites [userId]. Returns the room ID.
  Future<String> createDm(String userId);

  Future<void> join(String roomId);

  /// People the user shares chats with, the most recently active chats' first.
  Future<List<Person>> knownPeople();

  /// People in the server's user directory matching [term].
  Future<List<Person>> searchPeople(String term);

  /// The user's direct chat with [userId], if any.
  String? dmWith(String userId);

  /// Rooms in the server's public directory matching [term] (all with `null`): the most
  /// joined first, those the user is in last.
  Future<List<PublicRoom>> publicRooms(String? term);

  /// Creates a room and returns its ID. Private rooms are invite-only and always encrypted;
  /// a public one anyone can join, at `#alias:server` if [alias] is given, encrypted unless
  /// [encrypted] is off. [avatar] is an image of type [avatarMimeType].
  Future<String> createRoom({
    required String name,
    String? topic,
    bool public = false,
    String? alias,
    bool encrypted = true,
    Uint8List? avatar,
    String? avatarMimeType,
  });

  /// Joins a room by its address, ID, or a link to it; returns its ID. Throws
  /// [MatrixFailure] with [FailureKind.invalidId] for anything else.
  Future<String> joinByAddress(String address);

  /// Invites [userId] to the room [roomId].
  Future<void> invite(String roomId, String userId);

  /// Gives [userId] the power level [level] in the room: 100 Admin, 50 Moderator, 0 member.
  Future<void> setPowerLevel(String roomId, String userId, int level);

  /// Removes [userId] from the room, or withdraws their invite.
  Future<void> removeMember(String roomId, String userId, {String? reason});

  Future<void> banMember(String roomId, String userId, {String? reason});

  Future<void> unbanMember(String roomId, String userId);

  Future<RoomTimeline> openTimeline(String roomId);

  /// The room's timeline around the message [eventId], loaded from the server: to show an
  /// old message without loading everything after it. [RoomTimeline.loadNewer] pages it
  /// forward to the newest message.
  Future<RoomTimeline> openTimelineAt(String roomId, String eventId);

  /// The room's pins, and pinning.
  Future<PinnedEvents> openPins(String roomId);

  /// A timeline of only the room's pinned messages, oldest first, decrypted.
  Future<RoomTimeline> openPinnedTimeline(String roomId);

  /// Searches the room's messages on this device for [query] (case-insensitive, in texts,
  /// captions and file names); nothing goes to the server, so it works in encrypted rooms.
  Future<SearchResults> searchRoom(
    String roomId,
    String query, {
    int limit = 500,
  });

  /// Loads about [events] more of the room's history from the server, for [searchRoom] to
  /// reach further back. Returns `true` once the room's first message is there.
  Future<bool> searchLoadOlder(String roomId, {int events = 500});

  /// Logs out on the server and deletes everything stored for this account; the other
  /// accounts stay.
  Future<void> logout();

  /// Stops syncing and frees the session, keeping it saved.
  Future<void> close();
}

/// A room's threads; nothing is loaded until [loadMore].
abstract interface class ThreadList {
  /// The threads loaded so far, then the list after every change.
  Stream<List<RoomThread>> get threads;

  /// Loads the next, older page. Returns `true` once there are no more.
  Future<bool> loadMore();

  void close();
}

abstract interface class RoomTimeline {
  /// The current entries, then every change.
  Stream<List<TimelineEntry>> get entries;

  /// Loads older messages. Returns `true` once the start of the room is reached.
  Future<bool> loadOlder();

  /// Loads newer messages into a timeline opened at an event. Returns `true` once the
  /// newest is there; always `true` for a live timeline.
  Future<bool> loadNewer();

  /// Sends [text]; with [markdown], formatted from its markdown as Element sends it.
  Future<void> send(String text, {bool markdown = false});

  /// Sends [text] as a reply to the event [eventId].
  Future<void> sendReply(String text, String eventId, {bool markdown = false});

  /// Gives the message [ref] ([EventMeta.ref]) the user's reaction [key], or takes it back.
  Future<void> toggleReaction(String ref, String key);

  /// Replaces the text of the user's message, or with [caption] the caption of their file.
  Future<void> edit(
    String ref,
    String text, {
    bool caption = false,
    bool markdown = false,
  });

  /// Deletes the message for everyone; a local echo is just not sent.
  Future<void> redact(String ref);

  /// Sends a message whose sending failed once more.
  Future<void> retrySend(String ref);

  /// Whether the user may delete other people's messages here.
  Future<bool> canRedactOthers();

  /// Sends [data] as the file [filename] of type [mimeType], with [caption]; with
  /// [compress], a big photo goes scaled down as JPEG.
  Future<void> sendFile(
    Uint8List data, {
    required String filename,
    required String mimeType,
    String? caption,
    bool compress = false,
    bool markdown = false,
  });

  /// Sends the message [eventId] again in the account's room [roomId].
  Future<void> forward(String eventId, String roomId);

  /// Tells the room whether the user is typing; call it as often as the text changes.
  Future<void> setTyping(bool typing);

  /// Marks the room read up to its latest message, for the other members and the user's
  /// other devices.
  Future<void> markAsRead();

  void close();
}

/// One verification with another device of the user, by comparing emoji.
abstract interface class DeviceVerification {
  /// The current step, then every change, until done or cancelled.
  Stream<VerificationStep> get steps;

  /// Accepts a request from the other device.
  Future<void> accept();

  /// The emoji match.
  Future<void> confirm();

  /// The emoji don't match; cancels.
  Future<void> mismatch();

  Future<void> cancel();

  /// Stops following the verification; it isn't cancelled.
  void close();
}
