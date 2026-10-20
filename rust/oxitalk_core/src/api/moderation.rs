//! Managing a room's members: their roles (power levels), removing, banning and unbanning.

use matrix_sdk::ruma::{Int, OwnedUserId};

use super::{
    error::{CoreError, parse_id},
    session::Session,
};

impl Session {
    /// Gives `user_id` the power level `level` in the room: 100 is Admin, 50 Moderator,
    /// 0 a plain member.
    ///
    /// # Errors
    ///
    /// [`CoreError::InvalidId`] or [`CoreError::RoomNotFound`]; [`CoreError::Internal`] for a
    /// level out of range; otherwise as the server answers (e.g. [`CoreError::Forbidden`]
    /// without the right).
    pub async fn set_power_level(
        &self,
        room_id: String,
        user_id: String,
        level: i64,
    ) -> Result<(), CoreError> {
        let user: OwnedUserId = parse_id(user_id.trim())?;
        let level =
            Int::new(level).ok_or_else(|| CoreError::internal(&"power level out of range"))?;
        self.room(&room_id)?
            .update_power_levels(vec![(&user, level)])
            .await?;
        Ok(())
    }

    /// Removes `user_id` from the room, or withdraws their invite.
    ///
    /// # Errors
    ///
    /// As [`Session::set_power_level`].
    pub async fn remove_member(
        &self,
        room_id: String,
        user_id: String,
        reason: Option<String>,
    ) -> Result<(), CoreError> {
        let user: OwnedUserId = parse_id(user_id.trim())?;
        Ok(self
            .room(&room_id)?
            .kick_user(&user, non_empty(reason.as_deref()))
            .await?)
    }

    /// Bans `user_id` from the room.
    ///
    /// # Errors
    ///
    /// As [`Session::set_power_level`].
    pub async fn ban_member(
        &self,
        room_id: String,
        user_id: String,
        reason: Option<String>,
    ) -> Result<(), CoreError> {
        let user: OwnedUserId = parse_id(user_id.trim())?;
        Ok(self
            .room(&room_id)?
            .ban_user(&user, non_empty(reason.as_deref()))
            .await?)
    }

    /// Lifts `user_id`'s ban; they can join again when invited or the room is public.
    ///
    /// # Errors
    ///
    /// As [`Session::set_power_level`].
    pub async fn unban_member(&self, room_id: String, user_id: String) -> Result<(), CoreError> {
        let user: OwnedUserId = parse_id(user_id.trim())?;
        Ok(self.room(&room_id)?.unban_user(&user, None).await?)
    }
}

fn non_empty(reason: Option<&str>) -> Option<&str> {
    reason.map(str::trim).filter(|reason| !reason.is_empty())
}
