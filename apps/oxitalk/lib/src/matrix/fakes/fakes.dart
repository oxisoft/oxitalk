import 'dart:async';
import 'dart:typed_data';

import '../../util/latest.dart';
import '../api/matrix.dart';
import '../api/secret_store.dart';

/// In-memory stand-ins for the Matrix layer, for widget tests (and the integration test's
/// secret store, since CI has no keyring).
final class MemorySecretStore implements SecretStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

final class FakeMatrixClientFactory implements MatrixClientFactory {
  FakeMatrixClientFactory({
    List<FakeSession> saved = const [],
    this.active,
    this.password = 'secret',
    this.rooms = const [],
    this.loginVerification = VerificationStatus.verified,
  }) : saved = [...saved];

  /// What [restoreAll] returns; [login] adds to it.
  final List<FakeSession> saved;

  /// The account [readActive] returns; [writeActive] sets it.
  String? active;

  /// The only password [login] accepts.
  final String password;

  /// The rooms a session made by [login] starts with.
  final List<Room> rooms;

  /// The verification status of a session made by [login].
  final VerificationStatus loginVerification;

  FakeSession? lastLogin;

  @override
  Future<MatrixSession> login({
    required String server,
    required String username,
    required String password,
  }) async {
    if (password != this.password) {
      throw const MatrixFailure(FailureKind.forbidden, 'Invalid password');
    }
    final userId = '@$username:$server';
    if (saved.any((session) => session.userId == userId)) {
      throw MatrixFailure(FailureKind.alreadyLoggedIn, userId);
    }
    final session = FakeSession(userId: userId, rooms: rooms)
      ..verification.value = loginVerification;
    saved.add(session);
    return lastLogin = session;
  }

  @override
  Future<List<MatrixSession>> restoreAll() async => [...saved];

  @override
  Future<String?> readActive() async => active;

  @override
  Future<void> writeActive(String userId) async => active = userId;
}

final class FakeSession implements MatrixSession {
  FakeSession({
    this.userId = '@me:example.org',
    List<Room>? rooms,
    Profile profile = const Profile(),
    Sections sections = const Sections(),
  }) : _rooms = Latest(rooms),
       ownProfile = Latest(profile),
       sectionState = Latest(sections);

  @override
  final String userId;
  final Latest<List<Room>?> _rooms;
  final status = Latest(SyncStatus.online);
  final timelines = <String, FakeTimeline>{};
  final _expired = Completer<void>();
  var loggedOut = false;

  /// The user's profile; tests change it.
  final Latest<Profile> ownProfile;

  /// The room list sections; tests change them.
  final Latest<Sections> sectionState;

  /// The pictures on the server, by `mxc://` URI; [thumbnail] serves them as they are.
  final pictures = <String, Uint8List>{};

  /// This device's verification status; tests change it.
  final verification = Latest(VerificationStatus.verified);

  /// What [recover] accepts; any other key is wrong.
  String? recoveryKey = 'the recovery key';
  final _requests = StreamController<VerificationRequest>.broadcast();

  /// The verification [requestVerification] or [openVerification] returned last.
  FakeVerification? lastVerification;

  /// Sends a request from another device, as it would arrive.
  void receiveVerificationRequest(VerificationRequest request) =>
      _requests.add(request);

  set roomList(List<Room>? rooms) => _rooms.value = rooms;

  List<Room> get roomList => _rooms.value ?? const [];

  /// Rejects the session, as the server would.
  void expire() => _expired.complete();

  @override
  Stream<SyncStatus> get syncStatus => status.stream;

  @override
  Stream<List<Room>?> get rooms => _rooms.stream;

  @override
  Future<void> get expired => _expired.future;

  @override
  Stream<VerificationStatus> get verificationStatus => verification.stream;

  @override
  Stream<VerificationRequest> get verificationRequests => _requests.stream;

  @override
  Future<void> recover(String key) async {
    if (recoveryKey == null) {
      throw const MatrixFailure(FailureKind.recoveryNotSetUp);
    }
    if (key != recoveryKey) {
      throw const MatrixFailure(FailureKind.wrongRecoveryKey);
    }
    verification.value = VerificationStatus.verified;
  }

  @override
  Future<DeviceVerification> requestVerification() async =>
      lastVerification = FakeVerification(this);

  @override
  Future<DeviceVerification> openVerification(String flowId) async =>
      lastVerification = FakeVerification(
        this,
        step: const VerificationIncoming(),
      );

  @override
  Stream<Profile> get profile => ownProfile.stream;

  @override
  Future<void> setAvatar(Uint8List data, String mimeType) async {
    final url = 'mxc://example.org/avatar${pictures.length}';
    pictures[url] = data;
    ownProfile.value = Profile(
      displayName: ownProfile.value.displayName,
      avatarUrl: url,
    );
  }

  @override
  Future<void> removeAvatar() async =>
      ownProfile.value = Profile(displayName: ownProfile.value.displayName);

  @override
  Future<Uint8List> thumbnail(String mxcUrl, int size) async =>
      pictures[mxcUrl] ?? (throw MatrixFailure(FailureKind.network, mxcUrl));

  /// The cache's retention, as last set; `-1` until set.
  int? retentionDays = -1;

  /// What [mediaCacheSize] returns.
  int? cacheSize = 1234;

  /// What [saveMedia] wrote: path → source.
  final saved = <String, String>{};

  /// Chat details and members by room ID; a room without them gets a plain default.
  final details = <String, RoomDetails>{};
  final members = <String, List<RoomMember>>{};

  /// The timelines [openMediaTimeline] returns, by room ID.
  final mediaTimelines = <String, FakeTimeline>{};

  @override
  Future<Uint8List> mediaContent(String source) async =>
      pictures[source] ?? (throw MatrixFailure(FailureKind.network, source));

  @override
  Future<Uint8List> mediaThumbnail(
    String source,
    String? thumbnail,
    int size,
  ) => mediaContent(thumbnail ?? source);

  @override
  Future<void> saveMedia(String source, String path) async {
    await mediaContent(source);
    saved[path] = source;
  }

  @override
  Future<void> setMediaRetention(int? days) async => retentionDays = days;

  @override
  Future<int?> mediaCacheSize() async => cacheSize;

  @override
  Future<void> clearMediaCache() async => cacheSize = 0;

  @override
  Future<RoomDetails> roomDetails(String roomId) async =>
      details[roomId] ??
      RoomDetails(
        roomId: roomId,
        name:
            roomList.where((room) => room.id == roomId).firstOrNull?.name ??
            roomId,
      );

  @override
  Future<List<RoomMember>> roomMembers(String roomId) async =>
      members[roomId] ?? [RoomMember(userId: userId)];

  @override
  Future<RoomTimeline> openMediaTimeline(String roomId) async =>
      mediaTimelines.putIfAbsent(roomId, () => FakeTimeline(ownUserId: userId));

  /// What [recentEmojis] returns; [addRecentEmoji] puts one first.
  final recent = <String>[];

  @override
  Future<List<String>> recentEmojis() async => [...recent];

  @override
  Future<void> addRecentEmoji(String emoji) async => recent
    ..remove(emoji)
    ..insert(0, emoji);

  /// Who types where; tests change it.
  final typingState = Latest(const <String, List<String>>{});

  @override
  Stream<Map<String, List<String>>> get typing => typingState.stream;

  @override
  Stream<Sections> get sections => sectionState.stream;

  @override
  Future<void> setRoomSection(String roomId, String? tag) async {
    final current = sectionState.value;
    sectionState.value = Sections(
      custom: current.custom,
      order: current.order,
      roomTags: {
        ...current.roomTags,
        roomId: [
          for (final old in current.roomTags[roomId] ?? const <String>[])
            if (!SectionTags.isSection(old)) old,
          ?tag,
        ],
      },
    );
  }

  @override
  Future<void> saveSections(
    List<CustomSection> custom,
    List<String> order,
  ) async => sectionState.value = Sections(
    custom: custom,
    order: order,
    roomTags: sectionState.value.roomTags,
  );

  /// What [notifications] sends; tests add to it.
  final notificationItems = StreamController<MessageNotification>.broadcast();

  @override
  Stream<MessageNotification> get notifications => notificationItems.stream;

  /// The notification settings; tests change them.
  final notificationState = Latest<NotificationSettings?>(
    const NotificationSettings(),
  );

  /// What the notification calls did, like `mode !room:x mute`, `default dm mentions`,
  /// `markRead !room:x`.
  final notificationCalls = <String>[];

  void _changeRoom(String roomId, Room Function(Room room) change) => roomList =
      [for (final room in roomList) room.id == roomId ? change(room) : room];

  NotificationSettings get _settings =>
      notificationState.value ?? const NotificationSettings();

  @override
  Stream<NotificationSettings?> get notificationSettings =>
      notificationState.stream;

  @override
  Future<void> setRoomNotificationMode(
    String roomId,
    NotificationMode? mode,
  ) async {
    notificationCalls.add('mode $roomId ${mode?.name ?? 'default'}');
    _changeRoom(roomId, (room) => room.copyWith(notificationMode: mode));
  }

  @override
  Future<void> setDefaultNotificationMode({
    required bool directChats,
    required NotificationMode mode,
  }) async {
    notificationCalls.add(
      'default ${directChats ? 'dm' : 'group'} ${mode.name}',
    );
    notificationState.value = directChats
        ? _settings.copyWith(dmDefault: mode, inconsistent: false)
        : _settings.copyWith(groupDefault: mode, inconsistent: false);
    roomList = [
      for (final room in roomList)
        room.isOneToOne == directChats
            ? room.copyWith(defaultNotificationMode: mode)
            : room,
    ];
  }

  @override
  Future<void> fixNotificationDefaults() async {
    notificationCalls.add('fix');
    notificationState.value = _settings.copyWith(inconsistent: false);
  }

  @override
  Future<void> setRoomMentionsEnabled(bool enabled) async {
    notificationCalls.add('roomMentions $enabled');
    notificationState.value = _settings.copyWith(roomMentions: enabled);
  }

  @override
  Future<void> setInvitesEnabled(bool enabled) async {
    notificationCalls.add('invites $enabled');
    notificationState.value = _settings.copyWith(invites: enabled);
  }

  @override
  Future<void> addNotificationKeyword(String keyword) async {
    notificationCalls.add('keyword+ $keyword');
    notificationState.value = _settings.copyWith(
      keywords: [..._settings.keywords, keyword],
    );
  }

  @override
  Future<void> removeNotificationKeyword(String keyword) async {
    notificationCalls.add('keyword- $keyword');
    notificationState.value = _settings.copyWith(
      keywords: [
        for (final word in _settings.keywords)
          if (word != keyword) word,
      ],
    );
  }

  @override
  Future<void> setMarkedUnread(String roomId, bool unread) async {
    notificationCalls.add('markedUnread $roomId $unread');
    _changeRoom(roomId, (room) => room.copyWith(markedUnread: unread));
  }

  @override
  Future<void> markRoomRead(String roomId) async {
    notificationCalls.add('markRead $roomId');
    _changeRoom(
      roomId,
      (room) => room.copyWith(
        unreadCount: 0,
        unreadNotifications: 0,
        unreadMentions: 0,
        markedUnread: false,
      ),
    );
  }

  @override
  Future<String> createDm(String userId) async {
    if (!userId.startsWith('@') || !userId.contains(':')) {
      throw MatrixFailure(FailureKind.invalidId, userId);
    }
    final id = '!dm${roomList.length}:example.org';
    roomList = [
      Room(
        id: id,
        name: userId,
        isDm: true,
        isOneToOne: true,
        isEncrypted: true,
      ),
      ...roomList,
    ];
    return id;
  }

  /// Like the server's answer, it arrives after the room list has changed.
  /// What [createRoom] was asked: name → (public, alias, encrypted, has avatar).
  final created = <String, (bool, String?, bool, bool)>{};

  /// Room addresses [joinByAddress] knows: address → room.
  final addresses = <String, Room>{};

  /// What [invite] was asked: `roomId userId`.
  final invited = <String>[];

  @override
  Future<String> createRoom({
    required String name,
    String? topic,
    bool public = false,
    String? alias,
    bool encrypted = true,
    Uint8List? avatar,
    String? avatarMimeType,
  }) async {
    created[name] = (public, alias, encrypted || !public, avatar != null);
    final id = '!room${roomList.length}:example.org';
    roomList = [
      Room(id: id, name: name, isEncrypted: encrypted || !public),
      ...roomList,
    ];
    return id;
  }

  /// What [knownPeople] answers.
  List<Person> known = const [];

  /// The server's user directory, searched by name or ID.
  List<Person> directory = const [];

  /// The server's public rooms; [publicRooms] filters them by name.
  List<PublicRoom> publicDirectory = const [];

  /// Direct chats by the other person's user ID.
  final dms = <String, String>{};

  @override
  Future<List<Person>> knownPeople() async => known;

  @override
  Future<List<Person>> searchPeople(String term) async => [
    for (final person in directory)
      if ('${person.userId} ${person.displayName ?? ''}'.toLowerCase().contains(
        term.toLowerCase(),
      ))
        person,
  ];

  @override
  String? dmWith(String userId) => dms[userId];

  @override
  Future<List<PublicRoom>> publicRooms(String? term) async => [
    for (final room in publicDirectory)
      if (term == null ||
          (room.name ?? '').toLowerCase().contains(term.toLowerCase()))
        room,
  ];

  @override
  Future<String> joinByAddress(String address) async {
    final room = addresses[address.trim()];
    if (room == null) throw MatrixFailure(FailureKind.invalidId, address);
    roomList = [room, ...roomList];
    return room.id;
  }

  /// What the member menu did: `setPowerLevel roomId userId level`, `remove …`, `ban …`,
  /// `unban …`, with the reason after a `:` when there was one.
  final moderated = <String>[];

  void _changeMember(
    String roomId,
    String userId,
    RoomMember? Function(RoomMember member) change,
  ) => members[roomId] = [
    for (final member in members[roomId] ?? const <RoomMember>[])
      if (member.userId != userId) member else ?change(member),
  ];

  @override
  Future<void> setPowerLevel(String roomId, String userId, int level) async {
    moderated.add('setPowerLevel $roomId $userId $level');
    _changeMember(
      roomId,
      userId,
      (member) => member.copyWith(
        powerLevel: level,
        role: level >= 100
            ? MemberRole.admin
            : level >= 50
            ? MemberRole.moderator
            : MemberRole.member,
      ),
    );
  }

  @override
  Future<void> removeMember(
    String roomId,
    String userId, {
    String? reason,
  }) async {
    moderated.add('remove $roomId $userId${reason == null ? '' : ':$reason'}');
    _changeMember(roomId, userId, (_) => null);
  }

  @override
  Future<void> banMember(String roomId, String userId, {String? reason}) async {
    moderated.add('ban $roomId $userId${reason == null ? '' : ':$reason'}');
    _changeMember(
      roomId,
      userId,
      (member) => member.copyWith(
        banned: true,
        canBan: false,
        canRemove: false,
        canUnban: true,
      ),
    );
  }

  @override
  Future<void> unbanMember(String roomId, String userId) async {
    moderated.add('unban $roomId $userId');
    _changeMember(roomId, userId, (_) => null);
  }

  @override
  Future<void> invite(String roomId, String userId) async {
    if (!userId.startsWith('@') || !userId.contains(':')) {
      throw MatrixFailure(FailureKind.invalidId, userId);
    }
    invited.add('$roomId $userId');
  }

  @override
  Future<void> join(String roomId) async {
    roomList = [
      for (final room in roomList)
        room.id == roomId ? room.copyWith(membership: Membership.joined) : room,
    ];
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }

  @override
  Future<RoomTimeline> openTimeline(String roomId) async =>
      timelines.putIfAbsent(roomId, () => FakeTimeline(ownUserId: userId));

  /// The timelines [openThread] returns, by thread root event ID.
  final threadTimelines = <String, FakeTimeline>{};

  @override
  Future<RoomTimeline> openThread(String roomId, String rootEventId) async =>
      threadTimelines.putIfAbsent(
        rootEventId,
        () => FakeTimeline(ownUserId: userId),
      );

  /// The thread lists [openThreadList] returns, by room ID.
  final threadLists = <String, FakeThreadList>{};

  @override
  Future<ThreadList> openThreadList(String roomId) async =>
      threadLists.putIfAbsent(roomId, FakeThreadList.new);

  @override
  Future<void> logout() async => loggedOut = true;

  @override
  Future<void> close() async {}
}

final class FakeThreadList implements ThreadList {
  FakeThreadList([List<RoomThread> threads = const []])
    : _threads = Latest(threads);

  final Latest<List<RoomThread>> _threads;
  var loads = 0;
  var closed = false;

  set threadList(List<RoomThread> threads) => _threads.value = threads;

  @override
  Stream<List<RoomThread>> get threads => _threads.stream;

  @override
  Future<bool> loadMore() async {
    loads++;
    return true;
  }

  @override
  void close() => closed = true;
}

final class FakeTimeline implements RoomTimeline {
  FakeTimeline({
    this.ownUserId = '@me:example.org',
    List<TimelineEntry> entries = const [],
  }) : _entries = Latest(entries);

  final String ownUserId;
  final Latest<List<TimelineEntry>> _entries;
  var olderLoads = 0;

  /// How many times the room was marked read.
  var readMarks = 0;

  /// Everything else asked of it, like `react $ref 👍` or `reply $eventId text`.
  final calls = <String>[];

  /// Files sent: name → (caption, compress).
  final files = <String, (String?, bool)>{};

  /// What [canRedactOthers] answers.
  var moderator = false;
  var closed = false;

  set entryList(List<TimelineEntry> entries) => _entries.value = entries;

  List<TimelineEntry> get entryList => _entries.value;

  @override
  Stream<List<TimelineEntry>> get entries => _entries.stream;

  @override
  Future<bool> loadOlder() async {
    olderLoads++;
    return true;
  }

  /// Whether the last message sent was sent as markdown.
  bool? lastSentAsMarkdown;

  @override
  Future<void> send(String text, {bool markdown = false}) async {
    lastSentAsMarkdown = markdown;
    entryList = [
      ...entryList,
      MessageEntry(
        id: 'local${entryList.length}',
        sender: ownUserId,
        time: DateTime.now(),
        body: text,
        isOwn: true,
      ),
    ];
  }

  @override
  Future<void> markAsRead() async => readMarks++;

  /// What [setTyping] was told, in order.
  final typingSent = <bool>[];

  @override
  Future<void> setTyping(bool typing) async => typingSent.add(typing);

  @override
  Future<void> sendReply(
    String text,
    String eventId, {
    bool markdown = false,
  }) async {
    calls.add('reply $eventId $text');
    await send(text, markdown: markdown);
  }

  /// Gives or takes back the user's reaction on the entry named [ref], as the server would.
  @override
  Future<void> toggleReaction(String ref, String key) async {
    calls.add('react $ref $key');
    entryList = [
      for (final entry in entryList)
        entry is MessageEntry && entry.meta.ref == ref
            ? MessageEntry(
                id: entry.id,
                sender: entry.sender,
                senderName: entry.senderName,
                time: entry.time,
                body: entry.body,
                isOwn: entry.isOwn,
                meta: EventMeta(
                  eventId: entry.meta.eventId,
                  reactions: _toggled(entry.meta.reactions, key),
                  isEditable: entry.meta.isEditable,
                ),
              )
            : entry,
    ];
  }

  List<Reaction> _toggled(List<Reaction> reactions, String key) {
    final mine = reactions.where((r) => r.key == key && r.mine).firstOrNull;
    if (mine != null) {
      return [
        for (final r in reactions)
          if (r != mine)
            r
          else if (r.senders.length > 1)
            Reaction(r.key, [...r.senders]..remove(ownUserId)),
      ];
    }
    final other = reactions.where((r) => r.key == key).firstOrNull;
    return [
      for (final r in reactions)
        r == other ? Reaction(r.key, [...r.senders, ownUserId], mine: true) : r,
      if (other == null) Reaction(key, [ownUserId], mine: true),
    ];
  }

  @override
  Future<void> edit(
    String ref,
    String text, {
    bool caption = false,
    bool markdown = false,
  }) async => calls.add('edit $ref${caption ? ' caption' : ''} $text');

  @override
  Future<void> redact(String ref) async => calls.add('redact $ref');

  @override
  Future<void> retrySend(String ref) async => calls.add('retry $ref');

  @override
  Future<bool> canRedactOthers() async => moderator;

  @override
  Future<void> sendFile(
    Uint8List data, {
    required String filename,
    required String mimeType,
    String? caption,
    bool compress = false,
    bool markdown = false,
  }) async => files[filename] = (caption, compress);

  /// Voice messages sent, with the event each answers.
  final voices = <(VoiceClip, String?)>[];

  @override
  Future<void> sendVoice(VoiceClip clip, {String? inReplyTo}) async =>
      voices.add((clip, inReplyTo));

  /// Videos sent: name → (duration, photo, reply).
  final videos = <String, (Duration, Uint8List?, String?)>{};

  @override
  Future<void> sendVideo(
    Uint8List data, {
    required String filename,
    required String mimeType,
    required Duration duration,
    Uint8List? photo,
    int? width,
    int? height,
    String? inReplyTo,
  }) async => videos[filename] = (duration, photo, inReplyTo);

  @override
  Future<void> forward(String eventId, String roomId) async =>
      calls.add('forward $eventId $roomId');

  @override
  void close() => closed = true;
}

/// Encodes nothing: a clip is the samples' bytes, as long as they play at their rate, with a
/// waveform of their loudness. Everything plays but an mp3 (`ID3…`), as on Linux.
final class FakeAudioCodec implements AudioCodec {
  const FakeAudioCodec();

  @override
  Future<VoiceClip> encodeVoice(
    Int16List pcm, {
    required int sampleRate,
    required int channels,
  }) async => VoiceClip(
    data: pcm.buffer.asUint8List(pcm.offsetInBytes, pcm.lengthInBytes),
    duration: Duration(
      microseconds: pcm.length * 1000000 ~/ (sampleRate * channels),
    ),
    waveform: [
      for (var i = 0; i < 100; i++)
        pcm.isEmpty
            ? 0
            : (pcm[i * pcm.length ~/ 100].abs() *
                  VoiceClip.waveformMax ~/
                  32768),
    ],
  );

  @override
  Future<Uint8List?> playableWav(Uint8List data) async =>
      data.length >= 3 && String.fromCharCodes(data.sublist(0, 3)) == 'ID3'
      ? null
      : data;
}

/// A verification the test drives: it moves the [step] as the other device would.
final class FakeVerification implements DeviceVerification {
  FakeVerification(
    this._session, {
    VerificationStep step = const VerificationWaiting(),
  }) : _steps = Latest(step);

  static const emojis = [
    VerificationEmoji('🐶', 'Dog'),
    VerificationEmoji('🔑', 'Key'),
    VerificationEmoji('🎸', 'Guitar'),
    VerificationEmoji('🚀', 'Rocket'),
    VerificationEmoji('🌵', 'Cactus'),
    VerificationEmoji('🍕', 'Pizza'),
    VerificationEmoji('⚓', 'Anchor'),
  ];

  final FakeSession _session;
  final Latest<VerificationStep> _steps;
  var accepted = false;
  var closed = false;

  set step(VerificationStep step) => _steps.value = step;

  VerificationStep get step => _steps.value;

  /// The other device accepted and both sides exchanged keys.
  void showEmoji() => step = const VerificationCompare(emojis, [1, 2, 3]);

  @override
  Stream<VerificationStep> get steps => _steps.stream;

  @override
  Future<void> accept() async {
    accepted = true;
    step = const VerificationWaiting();
  }

  /// The other device has confirmed already, so confirming finishes it.
  @override
  Future<void> confirm() async {
    step = const VerificationDone();
    _session.verification.value = VerificationStatus.verified;
  }

  @override
  Future<void> mismatch() async =>
      step = const VerificationCancelled('The emoji did not match', byUs: true);

  @override
  Future<void> cancel() async =>
      step = const VerificationCancelled('Cancelled', byUs: true);

  @override
  void close() => closed = true;
}
