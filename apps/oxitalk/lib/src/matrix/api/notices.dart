/// What a timeline notice ([NoticeEntry] in models.dart) says happened: a room event other
/// than a message. The one who did it is the entry's sender.
library;

sealed class RoomNotice {
  const RoomNotice();
}

enum MembershipChange {
  joined,
  left,
  invited,
  inviteAccepted,
  inviteDeclined,
  inviteRevoked,
  kicked,
  banned,
  kickedAndBanned,
  unbanned,
  knocked,
  knockAccepted,
  knockRetracted,
  knockDenied,
}

/// Someone's membership changed; [userId] is whose, which needn't be the sender's (an
/// invite, a kick, a ban).
final class MembershipNotice extends RoomNotice {
  const MembershipNotice({
    required this.userId,
    required this.change,
    this.userName,
    this.userIsOwn = false,
    this.reason,
  });

  final String userId;
  final String? userName;

  /// [userId] is the account's own.
  final bool userIsOwn;
  final MembershipChange change;

  /// Why, as the sender wrote.
  final String? reason;
}

/// A member changed their name or picture.
final class ProfileNotice extends RoomNotice {
  const ProfileNotice({
    required this.userId,
    this.oldName,
    this.newName,
    this.nameChanged = false,
    this.avatarChanged = false,
    this.avatarRemoved = false,
  });

  final String userId;
  final String? oldName;

  /// `null` with [nameChanged] for a removed name.
  final String? newName;
  final bool nameChanged;
  final bool avatarChanged;
  final bool avatarRemoved;
}

final class RoomCreatedNotice extends RoomNotice {
  const RoomCreatedNotice();
}

/// `null` removed the name.
final class RoomNameNotice extends RoomNotice {
  const RoomNameNotice(this.name);

  final String? name;
}

/// `null` removed the topic.
final class RoomTopicNotice extends RoomNotice {
  const RoomTopicNotice(this.topic);

  final String? topic;
}

final class RoomAvatarNotice extends RoomNotice {
  const RoomAvatarNotice({this.removed = false});

  final bool removed;
}

/// The main address changed; `null` removed it.
final class RoomAliasNotice extends RoomNotice {
  const RoomAliasNotice(this.alias);

  final String? alias;
}

final class EncryptionNotice extends RoomNotice {
  const EncryptionNotice();
}

enum HistoryVisibilityKind { invited, joined, shared, worldReadable, other }

final class HistoryVisibilityNotice extends RoomNotice {
  const HistoryVisibilityNotice(this.visibility);

  final HistoryVisibilityKind visibility;
}

enum JoinRuleKind { public, invite, knock, restricted, other }

final class JoinRuleNotice extends RoomNotice {
  const JoinRuleNotice(this.rule);

  final JoinRuleKind rule;
}

/// One user's new power level.
final class PowerLevelChange {
  const PowerLevelChange(this.userId, this.oldLevel, this.newLevel);

  final String userId;
  final int oldLevel;
  final int newLevel;
}

/// Roles changed; [changes] are users', empty when only the room's rules changed.
final class PowerLevelsNotice extends RoomNotice {
  const PowerLevelsNotice([this.changes = const []]);

  final List<PowerLevelChange> changes;
}

/// The pinned messages changed: pins [added], [removed], or both.
final class PinnedNotice extends RoomNotice {
  const PinnedNotice({this.added = false, this.removed = false});

  final bool added;
  final bool removed;
}

final class RoomUpgradedNotice extends RoomNotice {
  const RoomUpgradedNotice();
}

final class PollNotice extends RoomNotice {
  const PollNotice(this.question);

  final String question;
}

final class StickerNotice extends RoomNotice {
  const StickerNotice(this.body);

  final String body;
}

/// A location; [body] is the sender's description.
final class LocationNotice extends RoomNotice {
  const LocationNotice(this.body);

  final String body;
}

final class LiveLocationNotice extends RoomNotice {
  const LiveLocationNotice();
}

/// A call invitation, or a call started in the room.
final class CallNotice extends RoomNotice {
  const CallNotice();
}
