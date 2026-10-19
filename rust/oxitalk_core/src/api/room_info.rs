//! What the chat info screen shows: a room's details, its members, and a timeline of only its
//! files and links.

use std::sync::{Arc, Mutex};

use matrix_sdk::{
    RoomMemberships,
    ruma::{
        Int, OwnedRoomId,
        events::{
            AnySyncMessageLikeEvent, AnySyncTimelineEvent, SyncMessageLikeEvent,
            room::{member::MembershipState, message::MessageType, power_levels::UserPowerLevel},
        },
    },
};
use matrix_sdk_ui::timeline::RoomExt;

use super::{
    error::{CoreError, parse_id},
    session::Session,
    timeline::Timeline,
};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RoomDetails {
    pub room_id: String,
    pub name: String,
    /// An `mxc://` URI: the room's avatar or, in a direct chat without one, the other
    /// person's.
    pub avatar_url: Option<String>,
    pub topic: Option<String>,
    /// The room's main address, like `#team:example.org`.
    pub alias: Option<String>,
    pub joined_members: u32,
    pub is_encrypted: bool,
    /// The other person, in a direct chat with one.
    pub dm_user_id: Option<String>,
    /// Whether the user verified the other person of a direct chat; `None` if unknown.
    pub dm_user_verified: Option<bool>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MemberRole {
    Admin,
    Moderator,
    Member,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RoomMember {
    pub user_id: String,
    pub display_name: Option<String>,
    /// An `mxc://` URI.
    pub avatar_url: Option<String>,
    pub role: MemberRole,
    /// Invited, not joined yet.
    pub invited: bool,
}

impl Session {
    /// A room's details for its info screen.
    ///
    /// # Errors
    ///
    /// [`CoreError::InvalidId`] or [`CoreError::RoomNotFound`].
    pub async fn room_details(&self, room_id: String) -> Result<RoomDetails, CoreError> {
        let room = self.room(&room_id)?;
        let is_dm = room.is_direct().await.unwrap_or(false);
        let dm_user = match room.direct_targets().iter().collect::<Vec<_>>().as_slice() {
            [target] if is_dm => target.as_user_id().map(ToOwned::to_owned),
            _ => None,
        };
        let mut avatar_url = room.avatar_url();
        let mut dm_user_verified = None;
        if let Some(user) = &dm_user {
            if avatar_url.is_none()
                && let Ok(Some(member)) = room.get_member_no_sync(user).await
            {
                avatar_url = member.avatar_url().map(ToOwned::to_owned);
            }
            let encryption = self.client.encryption();
            // Not stored until something needed it; then asked of the server.
            let identity = match encryption.get_user_identity(user).await {
                Ok(Some(identity)) => Some(identity),
                _ => encryption.request_user_identity(user).await.ok().flatten(),
            };
            dm_user_verified = identity.map(|identity| identity.is_verified());
        }
        Ok(RoomDetails {
            room_id,
            name: room
                .cached_display_name()
                .map_or_else(|| room.room_id().to_string(), |name| name.to_string()),
            avatar_url: avatar_url.map(|url| url.to_string()),
            topic: room.topic(),
            alias: room.canonical_alias().map(|alias| alias.to_string()),
            joined_members: u32::try_from(room.joined_members_count()).unwrap_or(u32::MAX),
            is_encrypted: room.encryption_state().is_encrypted(),
            dm_user_id: dm_user.map(|user| user.to_string()),
            dm_user_verified,
        })
    }

    /// The room's joined and invited members, admins first, then by name. Fetched from the
    /// server first if the store doesn't have them all; the stored ones when offline.
    ///
    /// # Errors
    ///
    /// [`CoreError::InvalidId`] or [`CoreError::RoomNotFound`].
    pub async fn room_members(&self, room_id: String) -> Result<Vec<RoomMember>, CoreError> {
        let room = self.room(&room_id)?;
        // Offline: what the store has.
        let _ = room.sync_members().await;
        let members = room
            .members_no_sync(RoomMemberships::JOIN | RoomMemberships::INVITE)
            .await
            .map_err(|error| CoreError::internal(&error))?;
        let mut members: Vec<RoomMember> = members
            .iter()
            .map(|member| RoomMember {
                user_id: member.user_id().to_string(),
                display_name: member.display_name().map(ToOwned::to_owned),
                avatar_url: member.avatar_url().map(ToString::to_string),
                role: match member.power_level() {
                    UserPowerLevel::Infinite => MemberRole::Admin,
                    UserPowerLevel::Int(level) if level >= Int::from(100) => MemberRole::Admin,
                    UserPowerLevel::Int(level) if level >= Int::from(50) => MemberRole::Moderator,
                    _ => MemberRole::Member,
                },
                invited: *member.membership() == MembershipState::Invite,
            })
            .collect();
        members.sort_by_cached_key(|member| {
            (
                member.role as u8,
                member.invited,
                member
                    .display_name
                    .clone()
                    .unwrap_or_else(|| member.user_id.clone())
                    .to_lowercase(),
            )
        });
        Ok(members)
    }

    /// A timeline of only the room's files and the text messages with links, for the info
    /// screen; it fills as it pages back. Encrypted events show until they are decrypted.
    ///
    /// # Errors
    ///
    /// [`CoreError::InvalidId`] or [`CoreError::RoomNotFound`].
    pub async fn media_timeline(&self, room_id: String) -> Result<Timeline, CoreError> {
        let room = self.room(&room_id)?;
        let timeline = room
            .timeline_builder()
            .event_filter(|event, _| is_media_or_link(event))
            .build()
            .await?;
        Ok(Timeline::new(Arc::new(timeline), Mutex::default()))
    }

    fn room(&self, room_id: &str) -> Result<matrix_sdk::Room, CoreError> {
        let id: OwnedRoomId = parse_id(room_id)?;
        self.client
            .get_room(&id)
            .ok_or_else(|| CoreError::RoomNotFound {
                room_id: room_id.to_owned(),
            })
    }
}

fn is_media_or_link(event: &AnySyncTimelineEvent) -> bool {
    let AnySyncTimelineEvent::MessageLike(AnySyncMessageLikeEvent::RoomMessage(
        SyncMessageLikeEvent::Original(message),
    )) = event
    else {
        return false;
    };
    match &message.content.msgtype {
        MessageType::Image(_)
        | MessageType::Video(_)
        | MessageType::Audio(_)
        | MessageType::File(_) => true,
        MessageType::Text(text) => has_link(&text.body),
        MessageType::Notice(notice) => has_link(&notice.body),
        _ => false,
    }
}

fn has_link(text: &str) -> bool {
    text.contains("https://") || text.contains("http://")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn links_are_found_in_text() {
        assert!(has_link("see https://oxisoft.io/x"));
        assert!(has_link("http://a.b"));
        assert!(!has_link("no link here, just https:"));
    }
}
