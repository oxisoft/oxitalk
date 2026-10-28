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

  Future<void> leave();
}
