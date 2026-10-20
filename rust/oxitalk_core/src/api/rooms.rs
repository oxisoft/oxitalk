//! Creating, joining and inviting to rooms.

use matrix_sdk::ruma::{
    MatrixToUri, MatrixUri, OwnedRoomId, OwnedRoomOrAliasId, OwnedServerName, OwnedUserId,
    api::client::room::{
        Visibility,
        create_room::v3::{Request as CreateRoomRequest, RoomPreset},
    },
    events::{InitialStateEvent, room::encryption::RoomEncryptionEventContent},
    matrix_uri::MatrixId,
};
use mime::Mime;

use super::{
    error::{CoreError, parse_id},
    session::Session,
};

/// A room to create.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NewRoom {
    pub name: String,
    pub topic: Option<String>,
    /// Anyone can join; else invite only.
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
        let created = self.client.create_room(request).await?;
        if let Some(avatar) = room.avatar {
            let mime: Mime = avatar
                .mime_type
                .parse()
                .map_err(|error| CoreError::internal(&error))?;
            created.upload_avatar(&mime, avatar.data, None).await?;
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
