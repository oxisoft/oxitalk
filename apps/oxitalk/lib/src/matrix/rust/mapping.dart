import '../../rust/api/error.dart';
import '../../rust/api/room_list.dart' as rust;
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
    time: DateTime.fromMillisecondsSinceEpoch(event.timestampMs),
    body: body,
    isOwn: event.isOwn,
    sendState: switch (event.sendState) {
      rust.SendState.sending => SendState.sending,
      rust.SendState.sent => SendState.sent,
      rust.SendState.failed => SendState.failed,
    },
  ),
  rust.TimelineItemContent_UnableToDecrypt(:final event) => UndecryptableEntry(
    id: item.id,
    sender: event.sender,
    senderName: event.senderName,
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
