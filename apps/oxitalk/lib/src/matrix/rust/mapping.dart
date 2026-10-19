import '../../rust/api/error.dart';
import '../../rust/api/room_info.dart' as rust;
import '../../rust/api/room_list.dart' as rust;
import '../../rust/api/sections.dart' as rust;
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
  isDm: summary.isDm,
  isEncrypted: summary.isEncrypted,
);

/// The visible entries of a timeline; events M0 doesn't show are left out.
List<TimelineEntry> entriesOf(Iterable<rust.TimelineItem> items) => [
  for (final item in items) ?entryOf(item),
];

TimelineEntry? entryOf(rust.TimelineItem item) => switch (item.content) {
  rust.TimelineItemContent_Message(:final event, :final body) => MessageEntry(
    id: item.id,
    sender: event.sender,
    senderName: event.senderName,
    senderAvatarUrl: event.senderAvatarUrl,
    time: DateTime.fromMillisecondsSinceEpoch(event.timestampMs),
    body: body,
    isOwn: event.isOwn,
    sendState: switch (event.sendState) {
      rust.SendState.sending => SendState.sending,
      rust.SendState.sent => SendState.sent,
      rust.SendState.failed => SendState.failed,
    },
  ),
  rust.TimelineItemContent_Media(:final event, :final media) => MediaEntry(
    id: item.id,
    sender: event.sender,
    senderName: event.senderName,
    senderAvatarUrl: event.senderAvatarUrl,
    time: DateTime.fromMillisecondsSinceEpoch(event.timestampMs),
    isOwn: event.isOwn,
    sendState: switch (event.sendState) {
      rust.SendState.sending => SendState.sending,
      rust.SendState.sent => SendState.sent,
      rust.SendState.failed => SendState.failed,
    },
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
      mimeType: media.mimeType,
      size: media.size,
      width: media.width,
      height: media.height,
      duration: switch (media.durationMs) {
        final ms? => Duration(milliseconds: ms),
        null => null,
      },
    ),
  ),
  rust.TimelineItemContent_UnableToDecrypt(:final event) => UndecryptableEntry(
    id: item.id,
    sender: event.sender,
    senderName: event.senderName,
    senderAvatarUrl: event.senderAvatarUrl,
    time: DateTime.fromMillisecondsSinceEpoch(event.timestampMs),
    isOwn: event.isOwn,
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
  invited: member.invited,
);
