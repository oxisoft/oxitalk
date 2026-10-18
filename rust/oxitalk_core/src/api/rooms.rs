//! Creating and joining rooms.

use matrix_sdk::ruma::{OwnedRoomId, OwnedUserId};

use super::{
    error::{CoreError, parse_id},
    session::Session,
};

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
}
