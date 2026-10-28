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
  final List<String> unopened = [];

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
    unopened.remove(userId);
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

  /// Recovery and the key backup; tests change them, and so does setting recovery up.
  final encryption = Latest(
    const EncryptionStatus(
      recovery: RecoveryState.disabled,
      backupEnabled: true,
    ),
  );

  /// The keys [enableRecovery] and [resetRecoveryKey] return, one after another.
  final newRecoveryKeys = <String>[
    'EsTj 3yST y93F SLpB jJsz eAXc 2XzA ygD3 w69H fGaN TKBj jXEd',
    'EsUA nz8p Zg5k pT3c 9iHv Ab2Q rDxW m4Lq Ve7Y sKa1 Nf6B uP2G',
  ];

  /// Completes [enableRecovery]; a test may hold it to see the progress.
  Completer<void>? recoveryGate;

  /// What [isLastDevice] answers.
  var lastDevice = false;

  /// The account's devices; tests change them, and so do the actions on them.
  final deviceList = Latest<List<Device>>(const [
    Device(
      id: 'THISDEVICE',
      name: 'OxiTalk',
      isThisDevice: true,
      verified: true,
    ),
  ]);

  /// What [serverInfo] answers; `null` gives one about [userId]'s server with only the
  /// basics known.
  ServerInfo? server;

  /// What [serverInfo] throws instead, while set.
  MatrixFailure? serverInfoFailure;

  /// Holds [serverInfo] until completed, so a test sees it loading.
  Completer<void>? serverInfoGate;

  /// How often [serverInfo] was asked.
  var serverInfoCalls = 0;

  /// The password [signOutDevices] wants; with `null` the server asks for none.
  String? accountPassword = 'the password';

  /// The passwords [signOutDevices] was called with, `null` for none.
  final signOutPasswords = <String?>[];

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
    if (encryption.value.recovery == RecoveryState.incomplete) {
      encryption.value = EncryptionStatus(
        recovery: RecoveryState.enabled,
        backupEnabled: encryption.value.backupEnabled,
      );
    }
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
  Stream<EncryptionStatus> get encryptionStatus => encryption.stream;

  @override
  Future<String> enableRecovery({
    void Function(RecoveryProgress)? onProgress,
  }) async {
    onProgress?.call(const RecoveryPreparing());
    onProgress?.call(const RecoveryBackingUp(3, 10));
    await recoveryGate?.future;
    return _newRecoveryKey();
  }

  @override
  Future<String> resetRecoveryKey() async {
    if (encryption.value.recovery == RecoveryState.disabled) {
      throw const MatrixFailure(FailureKind.recoveryNotSetUp);
    }
    return _newRecoveryKey();
  }

  String _newRecoveryKey() {
    final key = newRecoveryKeys.removeAt(0);
    recoveryKey = key;
    encryption.value = const EncryptionStatus(
      recovery: RecoveryState.enabled,
      backupEnabled: true,
    );
    return key;
  }

  @override
  Future<bool> isLastDevice() async => lastDevice;

  @override
  Future<ServerInfo> serverInfo() async {
    serverInfoCalls++;
    await serverInfoGate?.future;
    if (serverInfoFailure case final failure?) throw failure;
    final serverName = userId.split(':').last;
    return server ??
        ServerInfo(
          userId: userId,
          homeserverUrl: 'https://$serverName/',
          serverName: serverName,
        );
  }

  @override
  Future<List<Device>> devices() async => deviceList.value;

  @override
  Stream<List<Device>> get deviceChanges => deviceList.stream;

  @override
  Future<void> renameDevice(String deviceId, String name) async =>
      _changeDevice(
        deviceId,
        (device) => Device(
          id: device.id,
          name: name,
          lastSeen: device.lastSeen,
          lastSeenIp: device.lastSeenIp,
          isThisDevice: device.isThisDevice,
          verified: device.verified,
        ),
      );

  @override
  Future<void> signOutDevices(
    List<String> deviceIds, {
    String? password,
  }) async {
    signOutPasswords.add(password);
    if (accountPassword case final wanted?) {
      if (password == null) {
        throw const MatrixFailure(FailureKind.passwordNeeded);
      }
      if (password != wanted) {
        throw const MatrixFailure(FailureKind.wrongPassword);
      }
    }
    deviceList.value = [
      for (final device in deviceList.value)
        if (!deviceIds.contains(device.id)) device,
    ];
  }

  @override
  Future<DeviceVerification> verifyDevice(String deviceId) async =>
      lastVerification = FakeVerification(
        this,
        onDone: () => _changeDevice(
          deviceId,
          (device) => Device(
            id: device.id,
            name: device.name,
            lastSeen: device.lastSeen,
            lastSeenIp: device.lastSeenIp,
            verified: true,
          ),
        ),
      );

  void _changeDevice(String deviceId, Device Function(Device) change) =>
      deviceList.value = [
        for (final device in deviceList.value)
          device.id == deviceId ? change(device) : device,
      ];

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
  Future<RoomDetails> roomDetails(String roomId) async {
    final base =
        details[roomId] ??
        RoomDetails(
          roomId: roomId,
          name:
              roomList.where((room) => room.id == roomId).firstOrNull?.name ??
              roomId,
        );
    // Changed settings show in the details, as the room's state does.
    final changed = settings[roomId]?.value;
    if (changed == null) return base;
    return RoomDetails(
      roomId: roomId,
      name: changed.name ?? base.name,
      avatarUrl: changed.avatarUrl,
      topic: changed.topic,
      alias: changed.mainAddress,
      joinedMembers: base.joinedMembers,
      isEncrypted: changed.isEncrypted,
      dmUserId: base.dmUserId,
      dmUserVerified: base.dmUserVerified,
      ownPowerLevel: base.ownPowerLevel,
    );
  }

  @override
  Future<List<RoomMember>> roomMembers(String roomId) async =>
      members[roomId] ?? [RoomMember(userId: userId)];

  /// Each room's settings; a room without them gets defaults the user may change.
  final settings = <String, Latest<RoomSettings>>{};

  /// The settings of [roomId], for tests to read and change as another client would.
  Latest<RoomSettings> settingsOf(String roomId) => settings.putIfAbsent(
    roomId,
    () => Latest(
      RoomSettings(
        roomId: roomId,
        name:
            details[roomId]?.name ??
            roomList.where((room) => room.id == roomId).firstOrNull?.name,
        topic: details[roomId]?.topic,
        avatarUrl: details[roomId]?.avatarUrl,
        isEncrypted:
            details[roomId]?.isEncrypted ??
            roomList
                .where((room) => room.id == roomId)
                .firstOrNull
                ?.isEncrypted ??
            false,
        mainAddress: details[roomId]?.alias,
        serverName: userId.split(':').last,
        permissions: RoomPermissions.all,
      ),
    ),
  );

  /// What the room settings setters were asked, like `name !a:b Team`, in order.
  final settingsCalls = <String>[];

  /// Room addresses another room has; [setRoomMainAddress] refuses them.
  final takenAddresses = <String>{};

  /// Rooms listed in the room directory.
  final published = <String>{};

  /// The failure the next settings change throws, if any.
  MatrixFailure? settingsFailure;

  void _changeSettings(
    String roomId,
    String call,
    RoomSettings Function(RoomSettings) change,
  ) {
    if (settingsFailure case final failure?) {
      settingsFailure = null;
      throw failure;
    }
    settingsCalls.add(call);
    final latest = settingsOf(roomId);
    latest.value = change(latest.value);
  }

  @override
  Stream<RoomSettings> roomSettings(String roomId) => settingsOf(roomId).stream;

  @override
  Future<void> setRoomName(String roomId, String name) async => _changeSettings(
    roomId,
    'name $roomId $name',
    (s) => s.copyWith(name: () => name.trim().isEmpty ? null : name.trim()),
  );

  @override
  Future<void> setRoomTopic(String roomId, String topic) async =>
      _changeSettings(
        roomId,
        'topic $roomId $topic',
        (s) =>
            s.copyWith(topic: () => topic.trim().isEmpty ? null : topic.trim()),
      );

  @override
  Future<void> setRoomAvatar(
    String roomId,
    Uint8List data,
    String mimeType,
  ) async => _changeSettings(
    roomId,
    'avatar $roomId $mimeType',
    (s) => s.copyWith(avatarUrl: () => 'mxc://example.org/room$roomId'),
  );

  @override
  Future<void> removeRoomAvatar(String roomId) async => _changeSettings(
    roomId,
    'removeAvatar $roomId',
    (s) => s.copyWith(avatarUrl: () => null),
  );

  @override
  Future<void> setRoomJoinRule(String roomId, RoomJoinRule rule) async =>
      _changeSettings(
        roomId,
        'joinRule $roomId ${rule.name}',
        (s) => s.copyWith(
          joinRule: rule,
          history:
              rule != RoomJoinRule.public &&
                  s.history == RoomHistory.worldReadable
              ? RoomHistory.shared
              : null,
        ),
      );

  @override
  Future<void> setRoomHistory(String roomId, RoomHistory history) async =>
      _changeSettings(
        roomId,
        'history $roomId ${history.name}',
        (s) => s.copyWith(history: history),
      );

  @override
  Future<void> enableRoomEncryption(String roomId) async => _changeSettings(
    roomId,
    'encryption $roomId',
    (s) => s.copyWith(isEncrypted: true),
  );

  @override
  Future<bool> setRoomMainAddress(String roomId, String localpart) async {
    final part = localpart.trim();
    if (part.isEmpty || part.contains(RegExp(r'[:#\s]'))) {
      throw MatrixFailure(FailureKind.invalidId, localpart);
    }
    final address = '#$part:${settingsOf(roomId).value.serverName}';
    if (takenAddresses.contains(address)) return false;
    _changeSettings(
      roomId,
      'address $roomId $address',
      (s) => s.copyWith(mainAddress: () => address),
    );
    return true;
  }

  @override
  Future<bool> roomPublished(String roomId) async => published.contains(roomId);

  @override
  Future<void> setRoomPublished(String roomId, bool published) async {
    _changeSettings(roomId, 'published $roomId $published', (s) => s);
    published ? this.published.add(roomId) : this.published.remove(roomId);
  }

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

  /// The rooms [leave] was called for, in order.
  final left = <String>[];

  /// What [inviteDetails] answers, by room ID; else the room's name only.
  final inviteDetailsById = <String, InviteDetails>{};

  /// What [leaveInfo] answers, by room ID; else no warnings.
  final leaveInfos = <String, LeaveInfo>{};

  /// What [leave] throws, if anything.
  MatrixFailure? leaveFailure;

  @override
  Future<void> leave(String roomId) async {
    if (leaveFailure case final failure?) throw failure;
    left.add(roomId);
    roomList = [
      for (final room in roomList)
        if (room.id != roomId) room,
    ];
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }

  @override
  Future<InviteDetails> inviteDetails(String roomId) async =>
      inviteDetailsById[roomId] ??
      InviteDetails(
        roomId: roomId,
        name:
            roomList.where((room) => room.id == roomId).firstOrNull?.name ??
            roomId,
      );

  @override
  Future<LeaveInfo> leaveInfo(String roomId) async =>
      leaveInfos[roomId] ?? const LeaveInfo();

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

  /// The timelines [openTimelineAt] returns, by event ID.
  final timelinesAt = <String, FakeTimeline>{};

  @override
  Future<RoomTimeline> openTimelineAt(String roomId, String eventId) async =>
      timelinesAt.putIfAbsent(eventId, () => FakeTimeline(ownUserId: userId));

  /// The pins [openPins] returns, by room ID.
  final pins = <String, FakePinnedEvents>{};

  @override
  Future<PinnedEvents> openPins(String roomId) async =>
      pins.putIfAbsent(roomId, FakePinnedEvents.new);

  /// The timelines [openPinnedTimeline] returns, by room ID.
  final pinnedTimelines = <String, FakeTimeline>{};

  @override
  Future<RoomTimeline> openPinnedTimeline(String roomId) async =>
      pinnedTimelines.putIfAbsent(
        roomId,
        () => FakeTimeline(ownUserId: userId),
      );

  /// The messages of each room this device has, which [searchRoom] searches.
  final searchable = <String, List<SearchHit>>{};

  /// What [searchLoadOlder] adds to [searchable], by room ID; then the start is reached.
  final olderHistory = <String, List<SearchHit>>{};

  /// The queries [searchRoom] was asked, in order.
  final searches = <String>[];
  var historyLoads = 0;

  @override
  Future<SearchResults> searchRoom(
    String roomId,
    String query, {
    int limit = 500,
  }) async {
    searches.add(query);
    final needle = query.trim().toLowerCase();
    final messages = searchable[roomId] ?? const <SearchHit>[];
    final hits = [
      for (final hit in messages)
        if (needle.isNotEmpty &&
            (hit.text.toLowerCase().contains(needle) ||
                (hit.filename?.toLowerCase().contains(needle) ?? false)))
          hit,
    ]..sort((a, b) => b.time.compareTo(a.time));
    return SearchResults(
      hits: hits.take(limit).toList(),
      total: hits.length,
      searched: messages.length,
      oldest: messages.isEmpty
          ? null
          : messages.map((m) => m.time).reduce((a, b) => a.isBefore(b) ? a : b),
    );
  }

  @override
  Future<bool> searchLoadOlder(String roomId, {int events = 500}) async {
    historyLoads++;
    final older = olderHistory.remove(roomId) ?? const <SearchHit>[];
    searchable[roomId] = [...older, ...?searchable[roomId]];
    return true;
  }

  /// Whether [canMentionRoom] answers yes.
  var roomMentionAllowed = false;

  /// What [mentionRooms] lists.
  var mentionRoomList = <MentionRoom>[];

  /// The profiles [userProfile] tells, by user ID; others have only their ID. [ignored] and
  /// [dms] are added as they are.
  final profiles = <String, UserProfile>{};

  /// The users ignored; tests change it, and so do [ignoreUser] and [unignoreUser].
  final ignored = Latest<List<String>>(const []);

  /// Reports sent, like `user @bob:example.org spam` or `event !room $event null`.
  final reports = <String>[];

  /// The users [verifyUser] was asked for.
  final verifiedUsers = <String>[];

  @override
  Future<bool> canMentionRoom(String roomId) async => roomMentionAllowed;

  @override
  List<MentionRoom> mentionRooms() => mentionRoomList;

  @override
  Future<UserProfile> userProfile(String userId, {String? roomId}) async {
    final known = profiles[userId];
    return UserProfile(
      userId: userId,
      displayName: known?.displayName,
      avatarUrl: known?.avatarUrl,
      verified: known?.verified,
      ignored: ignored.value.contains(userId),
      dmRoomId: dms[userId],
    );
  }

  @override
  Future<DeviceVerification> verifyUser(String userId) async {
    verifiedUsers.add(userId);
    return lastVerification = FakeVerification(this, onDone: () {});
  }

  @override
  Future<void> ignoreUser(String userId) async =>
      ignored.value = ({...ignored.value, userId}.toList()..sort());

  @override
  Future<void> unignoreUser(String userId) async => ignored.value = [
    for (final user in ignored.value)
      if (user != userId) user,
  ];

  @override
  Stream<List<String>> get ignoredUsers => ignored.stream;

  @override
  Future<void> reportUser(String userId, {String? reason}) async =>
      reports.add('user $userId $reason');

  @override
  Future<void> reportEvent(
    String roomId,
    String eventId, {
    String? reason,
  }) async => reports.add('event $roomId $eventId $reason');

  /// The drafts kept, by room and thread (`null` for the room's own), as the store would.
  final drafts = <(String, String?), ComposerDraft>{};

  /// How many times a draft was saved.
  var draftSaves = 0;

  @override
  Future<void> saveDraft(
    String roomId,
    ComposerDraft draft, {
    String? thread,
  }) async {
    draftSaves++;
    draft.hasText
        ? drafts[(roomId, thread)] = draft
        : drafts.remove((roomId, thread));
  }

  @override
  Future<ComposerDraft?> loadDraft(String roomId, {String? thread}) async =>
      drafts[(roomId, thread)];

  @override
  Future<void> clearDraft(String roomId, {String? thread}) async =>
      drafts.remove((roomId, thread));

  @override
  Future<Map<String, String>> draftPreviews() async => {
    for (final MapEntry(key: (roomId, thread), value: draft) in drafts.entries)
      if (thread == null && draft.hasText) roomId: draft.firstLine,
  };

  /// Each room's call, for tests to change as the server would.
  final calls = <String, Latest<RoomCall>>{};

  Latest<RoomCall> callOf(String roomId) =>
      calls.putIfAbsent(roomId, () => Latest(RoomCall(roomId: roomId)));

  /// The calls joined, in order: (room, intent, notify).
  final joinedCalls = <(String, CallIntent, CallNotify)>[];

  /// The call [joinCall] made last.
  FakeJoinedCall? lastJoinedCall;

  /// When set, [joinCall] fails with it.
  MatrixFailure? joinCallFailure;

  /// The rings declined: (room, notification event).
  final declinedCalls = <(String, String)>[];

  /// What [incomingCalls] sends; tests add rings and their ends.
  final incomingCallUpdates = StreamController<IncomingCallUpdate>.broadcast();

  @override
  Stream<RoomCall> roomCall(String roomId) => callOf(roomId).stream;

  @override
  Future<JoinedCall> joinCall(
    String roomId, {
    required CallIntent intent,
    CallNotify notify = CallNotify.none,
  }) async {
    if (joinCallFailure case final failure?) throw failure;
    joinedCalls.add((roomId, intent, notify));
    final call = lastJoinedCall = FakeJoinedCall(roomId, intent, userId);
    final latest = callOf(roomId);
    latest.value = RoomCall(
      roomId: roomId,
      intent: intent,
      participants: [
        ...latest.value.participants,
        CallParticipant(
          userId: userId,
          deviceId: 'FAKEDEVICE',
          identity: call.identity,
          isOwnUser: true,
          isThisDevice: true,
        ),
      ],
    );
    call.onLeave = () => latest.value = RoomCall(
      roomId: roomId,
      intent: latest.value.intent,
      participants: [
        for (final p in latest.value.participants)
          if (!p.isThisDevice) p,
      ],
    );
    return call;
  }

  @override
  Future<void> declineCall(String roomId, String notificationEventId) async =>
      declinedCalls.add((roomId, notificationEventId));

  @override
  Stream<IncomingCallUpdate> get incomingCalls => incomingCallUpdates.stream;

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

final class FakePinnedEvents implements PinnedEvents {
  FakePinnedEvents([RoomPins pins = const RoomPins()]) : _pins = Latest(pins);

  final Latest<RoomPins> _pins;
  var closed = false;

  RoomPins get state => _pins.value;

  set state(RoomPins pins) => _pins.value = pins;

  @override
  Stream<RoomPins> get pins => _pins.stream;

  @override
  Future<bool> pin(String eventId) async {
    if (!state.canPin) throw const MatrixFailure(FailureKind.forbidden);
    if (state.eventIds.contains(eventId)) return false;
    state = RoomPins(eventIds: [...state.eventIds, eventId], canPin: true);
    return true;
  }

  @override
  Future<bool> unpin(String eventId) async {
    if (!state.canPin) throw const MatrixFailure(FailureKind.forbidden);
    if (!state.eventIds.contains(eventId)) return false;
    state = RoomPins(
      eventIds: [...state.eventIds]..remove(eventId),
      canPin: true,
    );
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

  var newerLoads = 0;

  @override
  Future<bool> loadNewer() async {
    newerLoads++;
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

  /// Messages [draftTarget] finds besides [entryList], as if loaded from the store.
  final storedEvents = <String, TimelineEntry>{};

  @override
  Future<TimelineEntry?> draftTarget(
    String eventId, {
    required bool reply,
  }) async {
    for (final entry in entryList) {
      final id = switch (entry) {
        MessageEntry(:final meta) || MediaEntry(:final meta) => meta.eventId,
        _ => null,
      };
      if (id == eventId) return entry;
    }
    return reply ? storedEvents[eventId] : null;
  }

  @override
  Future<void> sendReply(
    String text,
    String eventId, {
    bool markdown = false,
  }) async {
    calls.add('reply $eventId $text');
    await send(text, markdown: markdown);
  }

  /// What [sendMessage] was given: the parts and the event replied to.
  final messages = <(List<MessagePart>, String?)>[];

  /// What [editMessage] was given: the message and the parts.
  final messageEdits = <(String, List<MessagePart>)>[];

  /// Records the parts, then sends their plain text as [send] or [sendReply] do.
  @override
  Future<void> sendMessage(
    List<MessagePart> parts, {
    String? replyTo,
    bool markdown = false,
  }) async {
    messages.add((parts, replyTo));
    final text = plainText(parts);
    replyTo == null
        ? await send(text, markdown: markdown)
        : await sendReply(text, replyTo, markdown: markdown);
  }

  /// Records the parts, then edits with their plain text as [edit] does.
  @override
  Future<void> editMessage(
    String ref,
    List<MessagePart> parts, {
    bool caption = false,
    bool markdown = false,
  }) async {
    messageEdits.add((ref, parts));
    await edit(ref, plainText(parts), caption: caption, markdown: markdown);
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
    this.onDone,
  }) : _steps = Latest(step);

  /// What finishing it does; by default this device becomes verified.
  final void Function()? onDone;

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
    if (onDone case final done?) {
      done();
    } else {
      _session.verification.value = VerificationStatus.verified;
    }
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

/// A call joined through [FakeSession.joinCall].
final class FakeJoinedCall implements JoinedCall {
  FakeJoinedCall(this.roomId, this.intent, String userId)
    : identity = '$userId:FAKEDEVICE';

  @override
  final String roomId;

  @override
  final CallIntent intent;

  @override
  final String identity;

  @override
  String get livekitUrl => 'wss://sfu.test';

  @override
  String get livekitToken => 'fake-token';

  /// What [mediaKeys] sends; tests add keys.
  final keys = StreamController<CallMediaKey>.broadcast();

  bool left = false;
  void Function()? onLeave;

  @override
  Stream<CallMediaKey> get mediaKeys => keys.stream;

  /// How often [renewAccess] was called; the n-th renewal gives `fake-token-<n+1>`.
  int renewals = 0;

  @override
  Future<({String url, String token})> renewAccess() async {
    renewals++;
    return (url: livekitUrl, token: 'fake-token-${renewals + 1}');
  }

  @override
  Future<void> leave() async {
    if (left) return;
    left = true;
    onLeave?.call();
  }
}
