/// The user's own membership: an invitation before it is answered, and what leaving costs.
library;

/// What an invitation shows before the user accepts or declines it.
final class InviteDetails {
  const InviteDetails({
    required this.roomId,
    required this.name,
    this.avatarUrl,
    this.topic,
    this.alias,
    this.isDm = false,
    this.joinedMembers = 0,
    this.inviterId,
    this.inviterName,
    this.inviterAvatarUrl,
  });

  final String roomId;

  /// As the invitation tells it; in a direct chat often the inviter's name.
  final String name;

  /// An `mxc://` URI.
  final String? avatarUrl;
  final String? topic;

  /// The room's main address, like `#team:example.org`.
  final String? alias;

  /// An invitation to a direct chat rather than a room.
  final bool isDm;

  /// As far as the invitation tells; often 0.
  final int joinedMembers;

  /// Who invited the user; `null` until the invitation's details arrive.
  final String? inviterId;
  final String? inviterName;

  /// An `mxc://` URI.
  final String? inviterAvatarUrl;
}

/// What leaving a room would cost, for the confirmation to warn about.
final class LeaveInfo {
  const LeaveInfo({
    this.isDm = false,
    this.needsInviteToRejoin = false,
    this.lastAdmin = false,
    this.onlyMember = false,
  });

  final bool isDm;

  /// The room isn't public: without a new invitation the user can't come back.
  final bool needsInviteToRejoin;

  /// The user is the only admin while others stay.
  final bool lastAdmin;

  /// Nobody else is in the room.
  final bool onlyMember;
}
