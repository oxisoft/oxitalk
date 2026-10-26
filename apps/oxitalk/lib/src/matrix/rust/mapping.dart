import '../../rust/api/devices.dart' as rust;
import '../../rust/api/error.dart';
import '../../rust/api/recovery.dart' as rust;
import '../../rust/api/notifications.dart' as rust;
import '../../rust/api/notify.dart' as rust;
import '../../rust/api/rich_text.dart' as rust;
import '../../rust/api/room_info.dart' as rust;
import '../../rust/api/room_list.dart' as rust;
import '../../rust/api/search.dart' as search_api;
import '../../rust/api/sections.dart' as rust;
import '../../rust/api/threads.dart' as thread_api;
import '../../rust/api/timeline.dart' as rust;
import '../../rust/api/verification.dart' as rust;
import '../../util/log.dart';
import '../api/matrix.dart';

MatrixFailure failure(CoreError error) => switch (error) {
  CoreError_InvalidHomeserver(:final message) => MatrixFailure(
    FailureKind.invalidServer,
    message,
  ),
  CoreError_Network(:final message) => MatrixFailure(
    FailureKind.network,
    message,
  ),
  CoreError_Forbidden(:final message) => MatrixFailure(
    FailureKind.forbidden,
    message,
  ),
  CoreError_SessionExpired() => const MatrixFailure(FailureKind.sessionExpired),
  CoreError_WrongStorePassphrase() => const MatrixFailure(
    FailureKind.wrongStorePassphrase,
  ),
  CoreError_InvalidId(:final id) => MatrixFailure(FailureKind.invalidId, id),
  CoreError_RoomNotFound(:final roomId) => MatrixFailure(
    FailureKind.roomNotFound,
    roomId,
  ),
  CoreError_WrongRecoveryKey() => const MatrixFailure(
    FailureKind.wrongRecoveryKey,
  ),
  CoreError_RecoveryNotSetUp() => const MatrixFailure(
    FailureKind.recoveryNotSetUp,
  ),
  CoreError_PasswordNeeded() => const MatrixFailure(FailureKind.passwordNeeded),
  CoreError_WrongPassword() => const MatrixFailure(FailureKind.wrongPassword),
  CoreError_Internal(:final message) => MatrixFailure(
    FailureKind.internal,
    message,
  ),
};

/// Runs [call], reporting a [CoreError] as a [MatrixFailure].
Future<T> guarded<T>(Future<T> Function() call) async {
  try {
    return await call();
  } on CoreError catch (error) {
    appLog(LogLevel.warn, 'core', '$error');
    throw failure(error);
  }
}

Device deviceOf(rust.DeviceInfo device) => Device(
  id: device.deviceId,
  name: device.displayName,
  lastSeen: switch (device.lastSeenTs) {
    final ms? => DateTime.fromMillisecondsSinceEpoch(ms),
    null => null,
  },
  lastSeenIp: device.lastSeenIp,
  isThisDevice: device.isThisDevice,
  verified: device.verified,
);

EncryptionStatus encryptionStatusOf(rust.EncryptionStatus status) =>
    EncryptionStatus(
      recovery: switch (status.recovery) {
        rust.RecoveryStatus.unknown => RecoveryState.unknown,
        rust.RecoveryStatus.enabled => RecoveryState.enabled,
        rust.RecoveryStatus.incomplete => RecoveryState.incomplete,
        rust.RecoveryStatus.disabled => RecoveryState.disabled,
      },
      backupEnabled: status.backupEnabled,
    );

/// What the app shows of a step; `null` for the end, which the returned key tells.
RecoveryProgress? recoveryProgressOf(rust.RecoveryProgress progress) =>
    switch (progress) {
      rust.RecoveryProgress_Starting() ||
      rust.RecoveryProgress_CreatingBackup() ||
      rust.RecoveryProgress_CreatingRecoveryKey() => const RecoveryPreparing(),
      rust.RecoveryProgress_BackingUp(:final backedUp, :final total) =>
        RecoveryBackingUp(backedUp, total),
      // The device backs the rest up later.
      rust.RecoveryProgress_BackupFailed() ||
      rust.RecoveryProgress_Done() => null,
    };

Room roomOf(rust.RoomSummary summary) => Room(
  id: summary.roomId,
  name: summary.name,
  avatarUrl: summary.avatarUrl,
  membership: switch (summary.membership) {
    rust.Membership.joined => Membership.joined,
    rust.Membership.invited => Membership.invited,
    rust.Membership.knocked => Membership.knocked,
    rust.Membership.left => Membership.left,
    rust.Membership.banned => Membership.banned,
  },
  lastMessage: summary.lastMessage,
  lastActivity: switch (summary.lastActivityMs) {
    final ms? => DateTime.fromMillisecondsSinceEpoch(ms),
    null => null,
  },
  unreadCount: summary.unreadCount,
  unreadNotifications: summary.unreadNotifications,
  unreadMentions: summary.unreadMentions,
  markedUnread: summary.markedUnread,
  notificationMode: switch (summary.notificationMode) {
    final mode? => notificationModeOf(mode),
    null => null,
  },
  defaultNotificationMode: notificationModeOf(summary.defaultNotificationMode),
  isOneToOne: summary.isOneToOne,
  isDm: summary.isDm,
  isEncrypted: summary.isEncrypted,
);

NotificationMode notificationModeOf(rust.RoomNotificationMode mode) =>
    switch (mode) {
      rust.RoomNotificationMode.allMessages => NotificationMode.allMessages,
      rust.RoomNotificationMode.mentionsAndKeywordsOnly =>
        NotificationMode.mentionsAndKeywords,
      rust.RoomNotificationMode.mute => NotificationMode.mute,
    };

rust.RoomNotificationMode rustNotificationMode(NotificationMode mode) =>
    switch (mode) {
      NotificationMode.allMessages => rust.RoomNotificationMode.allMessages,
      NotificationMode.mentionsAndKeywords =>
        rust.RoomNotificationMode.mentionsAndKeywordsOnly,
      NotificationMode.mute => rust.RoomNotificationMode.mute,
    };

NotificationSettings notificationSettingsOf(
  rust.NotificationSettingsState state,
) => NotificationSettings(
  dmDefault: notificationModeOf(state.dmDefault),
  groupDefault: notificationModeOf(state.groupDefault),
  roomMentions: state.roomMentions,
  invites: state.invites,
  keywords: state.keywords,
  inconsistent: state.inconsistent.isNotEmpty,
);

/// The visible entries of a timeline; events M0 doesn't show are left out.
List<TimelineEntry> entriesOf(Iterable<rust.TimelineItem> items) => [
  for (final item in items) ?entryOf(item),
];

TimelineEntry? entryOf(rust.TimelineItem item) => switch (item.content) {
  rust.TimelineItemContent_Message(
    :final event,
    :final body,
    :final formatted,
  ) =>
    MessageEntry(
      formatted: formatted == null ? null : richOf(formatted),
      id: item.id,
      sender: event.sender,
      senderName: event.senderName,
      senderAvatarUrl: event.senderAvatarUrl,
      time: DateTime.fromMillisecondsSinceEpoch(event.timestampMs),
      body: body,
      isOwn: event.isOwn,
      sendState: sendStateOf(event.sendState),
      meta: metaOf(event),
    ),
  rust.TimelineItemContent_Media(:final event, :final media) => MediaEntry(
    id: item.id,
    sender: event.sender,
    senderName: event.senderName,
    senderAvatarUrl: event.senderAvatarUrl,
    time: DateTime.fromMillisecondsSinceEpoch(event.timestampMs),
    isOwn: event.isOwn,
    sendState: sendStateOf(event.sendState),
    meta: metaOf(event),
    media: MediaInfo(
      kind: switch (media.kind) {
        rust.MediaKind.image => MediaKind.image,
        rust.MediaKind.video => MediaKind.video,
        rust.MediaKind.audio => MediaKind.audio,
        rust.MediaKind.file => MediaKind.file,
      },
      source: media.source,
      thumbnail: media.thumbnail,
      filename: media.filename,
      caption: media.caption,
      formattedCaption: switch (media.formattedCaption) {
        final blocks? => richOf(blocks),
        null => null,
      },
      mimeType: media.mimeType,
      size: media.size,
      width: media.width,
      height: media.height,
      duration: switch (media.durationMs) {
        final ms? => Duration(milliseconds: ms),
        null => null,
      },
      isVoice: media.isVoice,
      waveform: media.waveform,
    ),
  ),
  rust.TimelineItemContent_UnableToDecrypt(:final event) => UndecryptableEntry(
    id: item.id,
    sender: event.sender,
    senderName: event.senderName,
    senderAvatarUrl: event.senderAvatarUrl,
    time: DateTime.fromMillisecondsSinceEpoch(event.timestampMs),
    isOwn: event.isOwn,
    meta: metaOf(event),
  ),
  rust.TimelineItemContent_Redacted(:final event) => RedactedEntry(
    id: item.id,
    sender: event.sender,
    senderName: event.senderName,
    senderAvatarUrl: event.senderAvatarUrl,
    time: DateTime.fromMillisecondsSinceEpoch(event.timestampMs),
    isOwn: event.isOwn,
    meta: metaOf(event),
  ),
  rust.TimelineItemContent_DateDivider(:final timestampMs) => DayDivider(
    id: item.id,
    day: DateTime.fromMillisecondsSinceEpoch(timestampMs),
  ),
  rust.TimelineItemContent_OtherEvent() ||
  rust.TimelineItemContent_ReadMarker() ||
  rust.TimelineItemContent_TimelineStart() => null,
};

VerificationStatus verificationStatusOf(rust.VerificationStatus status) =>
    switch (status) {
      rust.VerificationStatus.unknown => VerificationStatus.unknown,
      rust.VerificationStatus.verified => VerificationStatus.verified,
      rust.VerificationStatus.unverified => VerificationStatus.unverified,
    };

VerificationStep stepOf(rust.VerificationFlowState state) => switch (state) {
  rust.VerificationFlowState_Requested() => const VerificationIncoming(),
  rust.VerificationFlowState_Created() ||
  rust.VerificationFlowState_Ready() ||
  rust.VerificationFlowState_SasCreated() ||
  rust.VerificationFlowState_SasStarted() ||
  rust.VerificationFlowState_SasAccepted() => const VerificationWaiting(),
  rust.VerificationFlowState_KeysExchanged(:final emojis, :final decimals) =>
    VerificationCompare([
      for (final emoji in emojis ?? const <rust.VerificationEmoji>[])
        VerificationEmoji(emoji.symbol, emoji.description),
    ], decimals),
  rust.VerificationFlowState_Confirmed() => const VerificationConfirmed(),
  rust.VerificationFlowState_Done() => const VerificationDone(),
  rust.VerificationFlowState_Cancelled(:final reason, :final byUs) =>
    VerificationCancelled(reason, byUs: byUs),
};

Sections applySectionsUpdate(Sections sections, rust.SectionsUpdate update) =>
    switch (update) {
      rust.SectionsUpdate_Settings(:final settings) => Sections(
        custom: [
          for (final section in settings.sections)
            CustomSection(section.tag, section.name),
        ],
        order: settings.order,
        roomTags: sections.roomTags,
      ),
      rust.SectionsUpdate_Rooms(:final rooms) => Sections(
        custom: sections.custom,
        order: sections.order,
        roomTags: {
          ...sections.roomTags,
          for (final room in rooms) room.roomId: room.tags,
        },
      ),
    };

RoomDetails roomDetailsOf(rust.RoomDetails details) => RoomDetails(
  roomId: details.roomId,
  name: details.name,
  avatarUrl: details.avatarUrl,
  topic: details.topic,
  alias: details.alias,
  joinedMembers: details.joinedMembers,
  isEncrypted: details.isEncrypted,
  dmUserId: details.dmUserId,
  dmUserVerified: details.dmUserVerified,
  ownPowerLevel: details.ownPowerLevel,
);

RoomMember roomMemberOf(rust.RoomMember member) => RoomMember(
  userId: member.userId,
  displayName: member.displayName,
  avatarUrl: member.avatarUrl,
  role: switch (member.role) {
    rust.MemberRole.admin => MemberRole.admin,
    rust.MemberRole.moderator => MemberRole.moderator,
    rust.MemberRole.member => MemberRole.member,
  },
  powerLevel: member.powerLevel,
  invited: member.invited,
  banned: member.banned,
  canChangeRole: member.canChangeRole,
  canRemove: member.canRemove,
  canBan: member.canBan,
  canUnban: member.canUnban,
);

SendState sendStateOf(rust.SendState state) => switch (state) {
  rust.SendState.sending => SendState.sending,
  rust.SendState.sent => SendState.sent,
  rust.SendState.failed => SendState.failed,
};

EventMeta metaOf(rust.EventInfo event) => EventMeta(
  eventId: event.eventId,
  transactionId: event.transactionId,
  reactions: [
    for (final reaction in event.reactions)
      Reaction(reaction.key, reaction.senders, mine: reaction.mine),
  ],
  inReplyTo: switch (event.inReplyTo) {
    final quote? => ReplyQuote(
      eventId: quote.eventId,
      sender: quote.sender,
      senderName: quote.senderName,
      text: quote.text,
    ),
    null => null,
  },
  thread: switch (event.thread) {
    final thread? => ThreadSummary(
      replyCount: thread.replyCount,
      latest: switch (thread.latest) {
        final latest? => threadEventOf(latest),
        null => null,
      },
    ),
    null => null,
  },
  isEdited: event.isEdited,
  isEditable: event.isEditable,
  uploadPercent: event.uploadPercent,
);

ThreadEvent threadEventOf(rust.ThreadEvent event) => ThreadEvent(
  sender: event.sender,
  senderName: event.senderName,
  senderAvatarUrl: event.senderAvatarUrl,
  text: event.text,
  time: DateTime.fromMillisecondsSinceEpoch(event.timestampMs.toInt()),
);

RoomThread roomThreadOf(thread_api.ThreadSummary thread) => RoomThread(
  rootEventId: thread.rootEventId,
  root: threadEventOf(thread.root),
  latest: switch (thread.latest) {
    final latest? => threadEventOf(latest),
    null => null,
  },
  replyCount: thread.replyCount,
);

List<RichBlock> richOf(List<rust.RichBlock> blocks) => [
  for (final block in blocks)
    RichBlock(
      switch (block.kind) {
        rust.BlockKind_Paragraph() => const ParagraphBlock(),
        rust.BlockKind_Heading(:final level) => HeadingBlock(level),
        rust.BlockKind_ListItem(:final number, :final depth) => ListItemBlock(
          number: number,
          depth: depth,
        ),
        rust.BlockKind_Code(:final language) => CodeBlock(language),
        rust.BlockKind_Rule() => const RuleBlock(),
      },
      [
        for (final span in block.spans)
          RichSpan(
            span.text,
            bold: span.bold,
            italic: span.italic,
            strike: span.strike,
            underline: span.underline,
            code: span.code,
            spoiler: span.spoiler,
            link: span.link,
            mention: span.mention,
            color: span.color,
          ),
      ],
      quoteDepth: block.quoteDepth,
    ),
];

MessageNotification messageNotificationOf(rust.NotificationItem item) =>
    MessageNotification(
      roomId: item.roomId,
      eventId: item.eventId,
      threadRoot: item.threadRoot,
      roomName: item.roomName,
      senderId: item.senderId,
      senderName: item.senderName,
      senderAvatarUrl: item.senderAvatar,
      text: item.bodyPreview,
      isDm: item.isDm,
      isHighlight: item.isHighlight,
      sound: item.sound,
      isInvite: item.isInvite,
      time: DateTime.fromMillisecondsSinceEpoch(item.timestampMs),
    );

/// [results] from the core as the app's.
SearchResults searchResultsOf(search_api.SearchResults results) =>
    SearchResults(
      hits: [
        for (final hit in results.hits)
          SearchHit(
            eventId: hit.eventId,
            threadRoot: hit.threadRoot,
            sender: hit.sender,
            senderName: hit.senderName,
            senderAvatarUrl: hit.senderAvatarUrl,
            time: DateTime.fromMillisecondsSinceEpoch(hit.timestampMs),
            text: hit.text,
            filename: hit.filename,
            mediaKind: switch (hit.mediaKind) {
              null => null,
              rust.MediaKind.image => MediaKind.image,
              rust.MediaKind.video => MediaKind.video,
              rust.MediaKind.audio => MediaKind.audio,
              rust.MediaKind.file => MediaKind.file,
            },
          ),
      ],
      total: results.total,
      searched: results.searched,
      oldest: switch (results.oldestMs) {
        final ms? => DateTime.fromMillisecondsSinceEpoch(ms),
        null => null,
      },
    );
