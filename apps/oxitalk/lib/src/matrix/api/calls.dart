import 'dart:typed_data';

/// Audio only, or video too.
enum CallIntent { audio, video }

/// Whom to tell when the user starts a call.
enum CallNotify {
  /// Nobody: the user joins a call that is already going on.
  none,

  /// Ring the other member (a direct chat).
  ring,

  /// Notify the room without ringing (a group).
  notify,
}

/// One device in a room's call.
final class CallParticipant {
  const CallParticipant({
    required this.userId,
    required this.deviceId,
    required this.identity,
    this.displayName,
    this.avatarUrl,
    this.intent,
    this.isOwnUser = false,
    this.isThisDevice = false,
  });

  final String userId;
  final String deviceId;

  /// Its name in LiveKit, `@user:server:DEVICE`.
  final String identity;
  final String? displayName;
  final String? avatarUrl;
  final CallIntent? intent;
  final bool isOwnUser;
  final bool isThisDevice;

  String get name => displayName ?? userId;
}

/// A room's call as its state says; no participants, no call.
final class RoomCall {
  const RoomCall({
    required this.roomId,
    this.participants = const [],
    this.intent,
  });

  final String roomId;

  /// Oldest first.
  final List<CallParticipant> participants;

  /// What the participants agree on, if they all say the same.
  final CallIntent? intent;

  bool get isActive => participants.isNotEmpty;

  /// Whether the user is in it with any device.
  bool get hasOwnUser => participants.any((p) => p.isOwnUser);
}

/// A key for LiveKit's frame encryption: [key] at [index] of the participant [identity].
final class CallMediaKey {
  const CallMediaKey({
    required this.identity,
    required this.index,
    required this.key,
    required this.isOwn,
  });

  final String identity;
  final int index;
  final Uint8List key;

  /// This device's own key, the one it encrypts with.
  final bool isOwn;
}

/// A ring addressed to the user.
final class IncomingCall {
  const IncomingCall({
    required this.roomId,
    required this.notificationEventId,
    required this.senderId,
    required this.expiresAt,
    this.senderName,
    this.senderAvatarUrl,
    this.intent,
    this.ring = true,
  });

  final String roomId;
  final String notificationEventId;
  final String senderId;
  final String? senderName;
  final String? senderAvatarUrl;
  final CallIntent? intent;

  /// A ring (direct chat); `false` for a group's notification.
  final bool ring;
  final DateTime expiresAt;

  String get callerName => senderName ?? senderId;
}

/// Why a ring stopped.
enum IncomingCallEnd { expired, callEnded, answered, declined }

sealed class IncomingCallUpdate {
  const IncomingCallUpdate();
}

final class CallRinging extends IncomingCallUpdate {
  const CallRinging(this.call);

  final IncomingCall call;
}

final class CallRingEnded extends IncomingCallUpdate {
  const CallRingEnded({
    required this.roomId,
    required this.notificationEventId,
    required this.reason,
  });

  final String roomId;
  final String notificationEventId;
  final IncomingCallEnd reason;
}

/// This device in a room's call, on the Matrix side: its LiveKit address and token, and the
/// media keys. [leave] ends it.
abstract interface class JoinedCall {
  String get roomId;
  String get livekitUrl;
  String get livekitToken;

  /// This device's LiveKit identity.
  String get identity;
  CallIntent get intent;

  /// Every key so far, then each new one.
  Stream<CallMediaKey> get mediaKeys;

  /// A new LiveKit address and token, for a media connect that failed. The call service also
  /// makes the LiveKit room again if LiveKit closed it after the first token.
  Future<({String url, String token})> renewAccess();

  Future<void> leave();
}

/// A Jitsi group call going on in a room, as Element Web and Desktop start them (a room
/// widget). OxiTalk joins it outside the app: [joinUrl] opens in the browser, or in the Jitsi
/// Meet app where it takes such links.
final class JitsiConference {
  const JitsiConference({
    required this.roomId,
    required this.widgetId,
    required this.domain,
    required this.conferenceId,
    required this.creatorUserId,
    required this.startedAt,
    required this.joinUrl,
    this.audioOnly = false,
    this.creatorName,
    this.needsSignIn = false,
  });

  final String roomId;
  final String widgetId;

  /// The Jitsi server, e.g. `meet.example.org`.
  final String domain;
  final String conferenceId;

  /// Started as a voice call.
  final bool audioOnly;
  final String creatorUserId;
  final String? creatorName;
  final DateTime startedAt;

  /// `https://<domain>/<conference>`, without a sign-in.
  final String joinUrl;

  /// The Jitsi server wants a Matrix sign-in: join with `MatrixSession.jitsiJoinUrl`.
  final bool needsSignIn;

  String get creator => creatorName ?? creatorUserId;
}
