//! The user's own membership: what an invitation shows before it is accepted, declining it,
//! and leaving a room (with what leaving would cost).

use matrix_sdk::{
    RoomMemberships, RoomState,
    deserialized_responses::SyncOrStrippedState,
    ruma::{
        Int,
        events::{SyncStateEvent, room::join_rules::JoinRule, room::power_levels::UserPowerLevel},
    },
};

use super::{error::CoreError, session::Session};

/// What an invitation shows before the user accepts or declines it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct InviteDetails {
    pub room_id: String,
    /// The room's name as the invitation tells it (in a direct chat, often the inviter's).
    pub name: String,
    /// An `mxc://` URI: the room's avatar or, in a direct chat without one, the inviter's.
    pub avatar_url: Option<String>,
    pub topic: Option<String>,
    /// The room's main address, like `#team:example.org`.
    pub alias: Option<String>,
    /// An invitation to a direct chat rather than a room.
    pub is_dm: bool,
    /// As far as the invitation tells; often 0.
    pub joined_members: u32,
    /// Who invited the user; `None` if the invitation doesn't tell.
    pub inviter_id: Option<String>,
    pub inviter_name: Option<String>,
    /// An `mxc://` URI.
    pub inviter_avatar_url: Option<String>,
}

/// What leaving a room would cost, for the confirmation to warn about.
#[derive(Debug, Clone, PartialEq, Eq)]
#[allow(
    clippy::struct_excessive_bools,
    reason = "independent warnings, each shown on its own"
)]
pub struct LeaveInfo {
    /// A direct chat rather than a room.
    pub is_dm: bool,
    /// The room isn't public: without a new invite the user can't come back.
    pub needs_invite_to_rejoin: bool,
    /// The user is the room's only admin while others stay: nobody could manage it after.
    pub last_admin: bool,
    /// Nobody else is in the room.
    pub only_member: bool,
}

impl Session {
    /// What the invitation to `room_id` shows: the room and who invited the user.
    ///
    /// # Errors
    ///
    /// [`CoreError::InvalidId`], [`CoreError::RoomNotFound`], or [`CoreError::Internal`] if
    /// the user isn't invited to it.
    pub async fn invite_details(&self, room_id: String) -> Result<InviteDetails, CoreError> {
        let room = self.room(&room_id)?;
        if room.state() != RoomState::Invited {
            return Err(CoreError::internal(&"not an invitation"));
        }
        // Right after the invitation shows, its member event may not be stored yet; the
        // details come without the inviter then, and with them when asked again.
        let invite = room.invite_details().await.ok();
        let flagged_direct =
            invite
                .as_ref()
                .is_some_and(|invite| match invite.invitee.event().as_ref() {
                    SyncOrStrippedState::Sync(SyncStateEvent::Original(event)) => {
                        event.content.is_direct.unwrap_or(false)
                    }
                    SyncOrStrippedState::Stripped(event) => {
                        event.content.is_direct.unwrap_or(false)
                    }
                    SyncOrStrippedState::Sync(SyncStateEvent::Redacted(_)) => false,
                });
        let is_dm = flagged_direct || room.is_direct().await.unwrap_or(false);
        let inviter = invite.as_ref().and_then(|invite| invite.inviter.as_ref());
        let inviter_avatar = inviter.and_then(|member| member.avatar_url().map(ToOwned::to_owned));
        let avatar_url = room
            .avatar_url()
            .or_else(|| is_dm.then(|| inviter_avatar.clone()).flatten());
        let inviter_name = inviter.and_then(|member| member.display_name().map(ToOwned::to_owned));
        // The SDK works the display name out a moment after the room shows; until then a
        // direct chat goes by its inviter, another room by its name, else its ID.
        let name = room
            .cached_display_name()
            .map(|name| name.to_string())
            .or_else(|| is_dm.then(|| inviter_name.clone()).flatten())
            .or_else(|| room.name())
            .unwrap_or_else(|| room.room_id().to_string());
        Ok(InviteDetails {
            room_id,
            name,
            avatar_url: avatar_url.map(|url| url.to_string()),
            topic: room.topic().filter(|topic| !topic.trim().is_empty()),
            alias: room.canonical_alias().map(|alias| alias.to_string()),
            is_dm,
            joined_members: u32::try_from(room.joined_members_count()).unwrap_or(u32::MAX),
            // The invite's sender; the user themself only for a malformed one.
            inviter_id: invite
                .as_ref()
                .map(|invite| invite.inviter_id.to_string())
                .filter(|id| id.as_str() != room.own_user_id().as_str()),
            inviter_name,
            inviter_avatar_url: inviter_avatar.map(|url| url.to_string()),
        })
    }

    /// What leaving the room would cost: whether the user could come back, and whether
    /// they are its last admin.
    ///
    /// # Errors
    ///
    /// [`CoreError::InvalidId`] or [`CoreError::RoomNotFound`].
    pub async fn leave_info(&self, room_id: String) -> Result<LeaveInfo, CoreError> {
        let room = self.room(&room_id)?;
        let own = room.own_user_id().to_owned();
        // Offline: what the store has.
        let _ = room.sync_members().await;
        let members = room
            .members_no_sync(RoomMemberships::JOIN)
            .await
            .map_err(|error| CoreError::internal(&error))?;
        let others: Vec<_> = members.iter().filter(|m| m.user_id() != own).collect();
        let is_admin = |level: UserPowerLevel| match level {
            UserPowerLevel::Int(level) => level >= Int::from(100),
            // A room version 12 creator, above every number.
            _ => true,
        };
        let own_level = match room.power_levels().await {
            Ok(levels) => levels.for_user(&own),
            Err(_) => UserPowerLevel::Int(Int::from(0)),
        };
        Ok(LeaveInfo {
            is_dm: room.is_direct().await.unwrap_or(false),
            needs_invite_to_rejoin: !matches!(room.join_rule(), Some(JoinRule::Public)),
            last_admin: is_admin(own_level)
                && !others.is_empty()
                && !others.iter().any(|member| is_admin(member.power_level())),
            only_member: others.is_empty(),
        })
    }

    /// Leaves the room, or declines the invitation to it (which forgets it too). It drops
    /// out of the room list.
    ///
    /// # Errors
    ///
    /// [`CoreError::InvalidId`], [`CoreError::RoomNotFound`], otherwise as the server
    /// answers.
    pub async fn leave(&self, room_id: String) -> Result<(), CoreError> {
        let room = self.room(&room_id)?;
        if matches!(room.state(), RoomState::Left | RoomState::Banned) {
            return Ok(());
        }
        room.leave().await?;
        Ok(())
    }
}
