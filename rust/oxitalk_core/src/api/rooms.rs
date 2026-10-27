//! Creating, joining and inviting to rooms.

use std::time::Duration;

use matrix_sdk::{
    EncryptionState, Room,
    ruma::{
        MatrixToUri, MatrixUri, OwnedRoomId, OwnedRoomOrAliasId, OwnedServerName, OwnedUserId,
        api::client::room::{
            Visibility,
            create_room::{
                RoomPowerLevelsContentOverride,
                v3::{Request as CreateRoomRequest, RoomPreset},
            },
        },
        events::{InitialStateEvent, room::encryption::RoomEncryptionEventContent},
        matrix_uri::MatrixId,
        serde::Raw,
    },
};
use mime::Mime;

use super::{
    calls::CALL_MEMBER_TYPE,
    error::{CoreError, parse_id},
    session::Session,
};

/// How long a new encrypted room may take to show as encrypted in the sync.
const ENCRYPTION_SYNC_DEADLINE: Duration = Duration::from_secs(10);

/// Waits until the sync shows a room just made encrypted as encrypted, at most
/// [`ENCRYPTION_SYNC_DEADLINE`].
///
/// The server creates a room event by event. A sync that comes in between brings the room
/// without its encryption event, and the SDK then takes it as unencrypted until a later sync
/// brings the event: a message or file sent until then goes unencrypted (seen on Synapse
/// under load). Such a sync can still arrive after the room is created, so this waits for the
/// encryption to show rather than only while the room shows unencrypted. Without a running
/// sync the state stays unknown until the deadline, which is safe: the SDK then asks the
/// server before sending.
async fn encryption_synced(room: &Room) {
    let mut infos = room.subscribe_info();
    let encrypted = async {
        while !room.encryption_state().is_encrypted() {
            if infos.next().await.is_none() {
                break;
            }
        }
    };
    if tokio::time::timeout(ENCRYPTION_SYNC_DEADLINE, encrypted)
        .await
        .is_err()
        && matches!(room.encryption_state(), EncryptionState::NotEncrypted)
    {
        tracing::warn!(room_id = %room.room_id(), "a new encrypted room still shows unencrypted");
    }
}

/// A room to create.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NewRoom {
    pub name: String,
    pub topic: Option<String>,
    /// Listed in the server's room directory (when the server allows) and anyone can join;
    /// else invite only.
    pub public: bool,
    /// For a public room: the part of its address before the colon (`team` in
    /// `#team:server`).
    pub alias: Option<String>,
    /// Ignored for a private room, which is always encrypted.
    pub encrypted: bool,
    pub avatar: Option<RoomAvatar>,
}

/// A room's picture: image bytes and their type, like `image/png`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RoomAvatar {
    pub data: Vec<u8>,
    pub mime_type: String,
}

impl Session {
    /// Creates an encrypted direct chat with `user_id` and invites them. Returns the room ID.
    ///
    /// # Errors
    ///
    /// [`CoreError::InvalidId`] for a malformed user ID, otherwise as the server answers.
    pub async fn create_dm(&self, user_id: String) -> Result<String, CoreError> {
        let user_id: OwnedUserId = parse_id(&user_id)?;
        let room = self.client.create_dm(&user_id).await?;
        encryption_synced(&room).await;
        Ok(room.room_id().to_string())
    }

    /// Joins a room, typically one the user was invited to.
    ///
    /// # Errors
    ///
    /// [`CoreError::InvalidId`] for a malformed room ID, otherwise as the server answers.
    pub async fn join(&self, room_id: String) -> Result<(), CoreError> {
        let room_id: OwnedRoomId = parse_id(&room_id)?;
        self.client.join_room_by_id(&room_id).await?;
        Ok(())
    }

    /// Creates a room as [`NewRoom`] describes and returns its ID.
    ///
    /// # Errors
    ///
    /// As the server answers: [`CoreError::Internal`] if the address is taken or malformed.
    pub async fn create_room(&self, room: NewRoom) -> Result<String, CoreError> {
        let mut request = CreateRoomRequest::new();
        request.name = Some(room.name);
        request.topic = room.topic.filter(|topic| !topic.trim().is_empty());
        request.visibility = Visibility::Private;
        request.preset = Some(if room.public {
            RoomPreset::PublicChat
        } else {
            RoomPreset::PrivateChat
        });
        if room.public {
            request.room_alias_name = room.alias.filter(|alias| !alias.is_empty());
        }
        if room.encrypted || !room.public {
            request.initial_state = vec![
                InitialStateEvent::with_empty_state_key(
                    RoomEncryptionEventContent::with_recommended_defaults(),
                )
                .to_raw_any(),
            ];
        }
        // Members may join calls, as in the rooms Element creates: the call membership event
        // at level 0 (by default only moderators could send it).
        request.power_level_content_override = Some(call_power_levels()?);
        let encrypted = !request.initial_state.is_empty();
        let created = self.client.create_room(request).await?;
        if encrypted {
            encryption_synced(&created).await;
        }
        if let Some(avatar) = room.avatar {
            let mime: Mime = avatar
                .mime_type
                .parse()
                .map_err(|error| CoreError::internal(&error))?;
            created.upload_avatar(&mime, avatar.data, None).await?;
        }
        // Listed in the server's room directory, as Element does. Asked for apart from the
        // creation: a server that lets only admins publish would refuse the whole room.
        if room.public
            && let Err(error) = created
                .privacy_settings()
                .update_room_visibility(Visibility::Public)
                .await
        {
            tracing::warn!(%error, "the server didn't list the new room in its directory");
        }
        Ok(created.room_id().to_string())
    }

    /// Joins a room by its address (`#room:server`), ID (`!id:server`), or a `matrix.to` or
    /// `matrix:` link to either, and returns its ID.
    ///
    /// # Errors
    ///
    /// [`CoreError::InvalidId`] for anything else, otherwise as the server answers.
    pub async fn join_by_address(&self, address: String) -> Result<String, CoreError> {
        let (target, via) = room_target(address.trim()).ok_or_else(|| CoreError::InvalidId {
            id: address.clone(),
        })?;
        let room = self.client.join_room_by_id_or_alias(&target, &via).await?;
        Ok(room.room_id().to_string())
    }

    /// Invites `user_id` to the room.
    ///
    /// # Errors
    ///
    /// [`CoreError::InvalidId`] or [`CoreError::RoomNotFound`], otherwise as the server
    /// answers (e.g. [`CoreError::Forbidden`] without the right to invite).
    pub async fn invite(&self, room_id: String, user_id: String) -> Result<(), CoreError> {
        let user: OwnedUserId = parse_id(user_id.trim())?;
        let id: OwnedRoomId = parse_id(&room_id)?;
        let room = self
            .client
            .get_room(&id)
            .ok_or(CoreError::RoomNotFound { room_id })?;
        Ok(room.invite_user_by_id(&user).await?)
    }
}

/// The room an address names, and the servers to join through.
fn room_target(address: &str) -> Option<(OwnedRoomOrAliasId, Vec<OwnedServerName>)> {
    let (id, via) = if let Ok(uri) = MatrixToUri::parse(address) {
        (uri.id().clone(), uri.via().to_vec())
    } else if let Ok(uri) = MatrixUri::parse(address) {
        (uri.id().clone(), uri.via().to_vec())
    } else {
        return OwnedRoomOrAliasId::try_from(address)
            .ok()
            .map(|id| (id, Vec::new()));
    };
    match id {
        MatrixId::Room(room) => Some((room.into(), via)),
        MatrixId::RoomAlias(alias) => Some((alias.into(), via)),
        _ => None,
    }
}

/// The events' power levels of a new room: the servers' defaults (Synapse
/// `handlers/room.py`, also Element Web's `DEFAULT_EVENT_POWER_LEVELS`) and the call
/// membership at 0. The whole map, since servers replace `events` rather than merge it.
fn call_power_levels() -> Result<Raw<RoomPowerLevelsContentOverride>, CoreError> {
    let content = serde_json::json!({
        "events": {
            "m.room.name": 50,
            "m.room.power_levels": 100,
            "m.room.history_visibility": 100,
            "m.room.canonical_alias": 50,
            "m.room.avatar": 50,
            "m.room.tombstone": 100,
            "m.room.server_acl": 100,
            "m.room.encryption": 100,
            CALL_MEMBER_TYPE: 0,
        }
    });
    Raw::from_json_string(content.to_string()).map_err(|error| CoreError::internal(&error))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn addresses_ids_and_links_name_rooms() {
        let target = |address| room_target(address).map(|(id, via)| (id.to_string(), via.len()));
        assert_eq!(
            target("#team:acme.com"),
            Some(("#team:acme.com".to_owned(), 0))
        );
        assert_eq!(
            target("!abc:acme.com"),
            Some(("!abc:acme.com".to_owned(), 0))
        );
        assert_eq!(
            target("https://matrix.to/#/%23team:acme.com"),
            Some(("#team:acme.com".to_owned(), 0))
        );
        assert_eq!(
            target("https://matrix.to/#/!abc:acme.com?via=acme.com"),
            Some(("!abc:acme.com".to_owned(), 1))
        );
        assert_eq!(
            target("matrix:r/team:acme.com"),
            Some(("#team:acme.com".to_owned(), 0))
        );
        assert_eq!(target("@bob:acme.com"), None);
        assert_eq!(target("team"), None);
    }
}
