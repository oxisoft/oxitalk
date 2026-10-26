//! A room's settings as its info screen edits them: name, topic and picture, who can join
//! and read the history, encryption, the main address and the listing in the server's room
//! directory. Each comes with whether the user's power level lets them change it.

use flutter_rust_bridge::frb;
use matrix_sdk::{
    Room,
    ruma::{
        OwnedRoomAliasId, UserId,
        api::{client::room::Visibility, error::ErrorKind},
        events::{
            StateEventType,
            room::{
                history_visibility::HistoryVisibility, join_rules::JoinRule,
                power_levels::RoomPowerLevels,
            },
        },
    },
};
use mime::Mime;

use super::{error::CoreError, session::Session};
use crate::frb_generated::StreamSink;

/// Who may join a room.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RoomJoinRule {
    /// Only people who are invited.
    Invite,
    /// Anyone may ask; a member lets them in.
    Knock,
    /// Anyone who finds the room.
    Public,
    /// Members of some other rooms (spaces), which this app doesn't edit.
    Restricted,
    /// Members of some other rooms join, others may ask.
    KnockRestricted,
    /// Anything else, shown as it is.
    Other,
}

/// Who may read the room's messages.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RoomHistory {
    /// Members, all of the history (from when this option was chosen).
    Shared,
    /// Members, from when they were invited.
    Invited,
    /// Members, from when they joined.
    Joined,
    /// Anyone, members or not; for public rooms.
    WorldReadable,
}

/// What the user's power level lets them change in a room.
#[allow(
    clippy::struct_excessive_bools,
    reason = "independent flags, one per state event the settings send"
)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct RoomPermissions {
    pub name: bool,
    pub topic: bool,
    pub avatar: bool,
    pub join_rule: bool,
    pub history: bool,
    pub encryption: bool,
    /// The main address, and the listing in the room directory.
    pub address: bool,
}

/// A room's settings, as the room's state has them.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RoomSettings {
    pub room_id: String,
    /// The name the room was given; `None` when it has none (it then shows its members).
    pub name: Option<String>,
    pub topic: Option<String>,
    /// The room's own picture, an `mxc://` URI.
    pub avatar_url: Option<String>,
    pub join_rule: RoomJoinRule,
    pub history: RoomHistory,
    pub is_encrypted: bool,
    /// The main address, like `#team:example.org`.
    pub main_address: Option<String>,
    /// The user's server, for a new address `#name:server`.
    pub server_name: String,
    /// Whether the room's version allows "ask to join".
    pub knock_supported: bool,
    pub permissions: RoomPermissions,
}

impl Session {
    /// The room's settings now.
    ///
    /// # Errors
    ///
    /// [`CoreError::InvalidId`] or [`CoreError::RoomNotFound`].
    pub async fn room_settings(&self, room_id: String) -> Result<RoomSettings, CoreError> {
        let room = self.room(&room_id)?;
        Ok(settings_of(&room, self.client.user_id()).await)
    }

    /// Sends the room's [`Self::room_settings`] now, then after every change, made here or
    /// elsewhere (they arrive with the sync), power levels included.
    ///
    /// # Errors
    ///
    /// [`CoreError::InvalidId`] or [`CoreError::RoomNotFound`].
    #[allow(
        clippy::unused_async,
        clippy::unused_async_trait_impl,
        reason = "async so flutter_rust_bridge runs it on its tokio runtime, which spawn needs"
    )]
    pub async fn subscribe_room_settings(
        &self,
        room_id: String,
        sink: StreamSink<RoomSettings>,
    ) -> Result<(), CoreError> {
        self.room_settings_updates(room_id, move |settings| sink.add(settings).is_ok())
    }

    /// Like [`Self::subscribe_room_settings`], for Rust callers: `emit` gets each state and
    /// returns `false` to stop. Must run on a tokio runtime.
    ///
    /// # Errors
    ///
    /// As [`Self::subscribe_room_settings`].
    #[frb(ignore)]
    pub fn room_settings_updates(
        &self,
        room_id: String,
        emit: impl Fn(RoomSettings) -> bool + Send + 'static,
    ) -> Result<(), CoreError> {
        let room = self.room(&room_id)?;
        let own = self.client.user_id().map(ToOwned::to_owned);
        // Listening before the first read, so no change falls between the two.
        let mut infos = room.subscribe_info();
        self.spawn(async move {
            let mut last = settings_of(&room, own.as_deref()).await;
            if !emit(last.clone()) {
                return;
            }
            // Every change to the room's info: the sync saves it with each state event.
            while infos.next().await.is_some() {
                let settings = settings_of(&room, own.as_deref()).await;
                if settings != last {
                    last = settings.clone();
                    if !emit(settings) {
                        break;
                    }
                }
            }
        });
        Ok(())
    }

    /// Gives the room the name `name`; an empty one takes the name away.
    ///
    /// # Errors
    ///
    /// [`CoreError::InvalidId`], [`CoreError::RoomNotFound`], or as the server answers
    /// ([`CoreError::Forbidden`] without the power level).
    pub async fn set_room_name(&self, room_id: String, name: String) -> Result<(), CoreError> {
        let room = self.room(&room_id)?;
        room.set_name(name.trim().to_owned()).await?;
        Ok(())
    }

    /// Gives the room the topic `topic`; an empty one takes the topic away.
    ///
    /// # Errors
    ///
    /// As [`Self::set_room_name`].
    pub async fn set_room_topic(&self, room_id: String, topic: String) -> Result<(), CoreError> {
        let room = self.room(&room_id)?;
        room.set_room_topic(topic.trim()).await?;
        Ok(())
    }

    /// Uploads `data` and makes it the room's picture; `mime_type` is its type, like
    /// `image/png`.
    ///
    /// # Errors
    ///
    /// [`CoreError::Internal`] for a malformed `mime_type`, otherwise as
    /// [`Self::set_room_name`].
    pub async fn set_room_avatar(
        &self,
        room_id: String,
        data: Vec<u8>,
        mime_type: String,
    ) -> Result<(), CoreError> {
        let room = self.room(&room_id)?;
        let mime: Mime = mime_type
            .parse()
            .map_err(|error| CoreError::internal(&error))?;
        room.upload_avatar(&mime, data, None).await?;
        Ok(())
    }

    /// Takes the room's picture away.
    ///
    /// # Errors
    ///
    /// As [`Self::set_room_name`].
    pub async fn remove_room_avatar(&self, room_id: String) -> Result<(), CoreError> {
        let room = self.room(&room_id)?;
        room.remove_avatar().await?;
        Ok(())
    }

    /// Sets who may join. Leaving "anyone", a history anyone could read becomes the
    /// members' (all of it), as Element X does: only a public room is readable by anyone.
    ///
    /// # Errors
    ///
    /// [`CoreError::Internal`] for [`RoomJoinRule::Restricted`],
    /// [`RoomJoinRule::KnockRestricted`] and [`RoomJoinRule::Other`], which need more than a
    /// choice; otherwise as [`Self::set_room_name`].
    pub async fn set_room_join_rule(
        &self,
        room_id: String,
        rule: RoomJoinRule,
    ) -> Result<(), CoreError> {
        let room = self.room(&room_id)?;
        let new_rule = match rule {
            RoomJoinRule::Invite => JoinRule::Invite,
            RoomJoinRule::Knock => JoinRule::Knock,
            RoomJoinRule::Public => JoinRule::Public,
            RoomJoinRule::Restricted | RoomJoinRule::KnockRestricted | RoomJoinRule::Other => {
                return Err(CoreError::internal(&"this join rule can't be chosen here"));
            }
        };
        let privacy = room.privacy_settings();
        privacy.update_join_rule(new_rule).await?;
        if rule != RoomJoinRule::Public
            && room.history_visibility_or_default() == HistoryVisibility::WorldReadable
        {
            privacy
                .update_room_history_visibility(HistoryVisibility::Shared)
                .await?;
        }
        Ok(())
    }

    /// Sets who may read the room's messages.
    ///
    /// # Errors
    ///
    /// As [`Self::set_room_name`].
    pub async fn set_room_history(
        &self,
        room_id: String,
        history: RoomHistory,
    ) -> Result<(), CoreError> {
        let room = self.room(&room_id)?;
        let visibility = match history {
            RoomHistory::Shared => HistoryVisibility::Shared,
            RoomHistory::Invited => HistoryVisibility::Invited,
            RoomHistory::Joined => HistoryVisibility::Joined,
            RoomHistory::WorldReadable => HistoryVisibility::WorldReadable,
        };
        room.privacy_settings()
            .update_room_history_visibility(visibility)
            .await?;
        Ok(())
    }

    /// Turns end-to-end encryption on. It can't be turned off again. Waits until the sync
    /// brings it back.
    ///
    /// # Errors
    ///
    /// As [`Self::set_room_name`].
    pub async fn enable_room_encryption(&self, room_id: String) -> Result<(), CoreError> {
        let room = self.room(&room_id)?;
        room.enable_encryption().await?;
        Ok(())
    }

    /// Makes `#localpart:server` (the user's server) the room's main address, creating it
    /// in the server's directory first. Returns `false`, changing nothing, if another room
    /// has that address. The earlier main address keeps pointing to the room.
    ///
    /// # Errors
    ///
    /// [`CoreError::InvalidId`] for a localpart that can't be an address, otherwise as
    /// [`Self::set_room_name`].
    pub async fn set_room_main_address(
        &self,
        room_id: String,
        localpart: String,
    ) -> Result<bool, CoreError> {
        let room = self.room(&room_id)?;
        let server = self.client.user_id().ok_or(CoreError::SessionExpired)?;
        let alias = address_of(&localpart, server)?;
        match self.client.resolve_room_alias(&alias).await {
            Ok(found) if found.room_id == room.room_id() => {}
            Ok(_) => return Ok(false),
            Err(error) if error.client_api_error_kind() == Some(&ErrorKind::NotFound) => {
                self.client
                    .create_room_alias(&alias, room.room_id())
                    .await?;
            }
            Err(error) => return Err(error.into()),
        }
        let mut others = room.alt_aliases();
        others.retain(|other| *other != alias);
        room.privacy_settings()
            .update_canonical_alias(Some(alias), others)
            .await?;
        Ok(true)
    }

    /// Whether the room is listed in the server's room directory. Asks the server.
    ///
    /// # Errors
    ///
    /// As [`Self::set_room_name`].
    pub async fn room_published(&self, room_id: String) -> Result<bool, CoreError> {
        let room = self.room(&room_id)?;
        Ok(room.privacy_settings().get_room_visibility().await? == Visibility::Public)
    }

    /// Lists the room in the server's room directory, or takes it out.
    ///
    /// # Errors
    ///
    /// As [`Self::set_room_name`]; a server that lets only its admins publish refuses.
    pub async fn set_room_published(
        &self,
        room_id: String,
        published: bool,
    ) -> Result<(), CoreError> {
        let room = self.room(&room_id)?;
        room.privacy_settings()
            .update_room_visibility(if published {
                Visibility::Public
            } else {
                Visibility::Private
            })
            .await?;
        Ok(())
    }
}

async fn settings_of(room: &Room, own: Option<&UserId>) -> RoomSettings {
    let levels = room.power_levels().await.ok();
    let may = |state: StateEventType| {
        levels
            .as_ref()
            .zip(own)
            .is_some_and(|(levels, own): (&RoomPowerLevels, _)| {
                levels.user_can_send_state(own, state)
            })
    };
    let info = room.clone_info();
    RoomSettings {
        room_id: room.room_id().to_string(),
        name: room.name().filter(|name| !name.is_empty()),
        topic: room.topic().filter(|topic| !topic.is_empty()),
        avatar_url: room.avatar_url().map(|url| url.to_string()),
        join_rule: match room.join_rule() {
            Some(JoinRule::Public) => RoomJoinRule::Public,
            Some(JoinRule::Knock) => RoomJoinRule::Knock,
            Some(JoinRule::Restricted(_)) => RoomJoinRule::Restricted,
            Some(JoinRule::KnockRestricted(_)) => RoomJoinRule::KnockRestricted,
            // No event: invite only is what the spec assumes.
            Some(JoinRule::Invite) | None => RoomJoinRule::Invite,
            Some(_) => RoomJoinRule::Other,
        },
        history: history_of(&room.history_visibility_or_default()),
        is_encrypted: room.encryption_state().is_encrypted(),
        main_address: room.canonical_alias().map(|alias| alias.to_string()),
        server_name: own.map_or_else(String::new, |own| own.server_name().to_string()),
        knock_supported: info.room_version_rules_or_default().authorization.knocking,
        permissions: RoomPermissions {
            name: may(StateEventType::RoomName),
            topic: may(StateEventType::RoomTopic),
            avatar: may(StateEventType::RoomAvatar),
            join_rule: may(StateEventType::RoomJoinRules),
            history: may(StateEventType::RoomHistoryVisibility),
            encryption: may(StateEventType::RoomEncryption),
            address: may(StateEventType::RoomCanonicalAlias),
        },
    }
}

fn history_of(visibility: &HistoryVisibility) -> RoomHistory {
    match visibility {
        HistoryVisibility::Invited => RoomHistory::Invited,
        HistoryVisibility::Joined => RoomHistory::Joined,
        HistoryVisibility::WorldReadable => RoomHistory::WorldReadable,
        // Shared is the spec's default for anything unknown.
        _ => RoomHistory::Shared,
    }
}

/// The address `#localpart:server` of the user's server.
fn address_of(localpart: &str, own: &UserId) -> Result<OwnedRoomAliasId, CoreError> {
    let localpart = localpart.trim().trim_start_matches('#');
    let invalid = || CoreError::InvalidId {
        id: localpart.to_owned(),
    };
    if localpart.is_empty()
        || localpart
            .chars()
            .any(|c| c == ':' || c == '#' || c.is_whitespace() || c.is_control())
    {
        return Err(invalid());
    }
    OwnedRoomAliasId::try_from(format!("#{localpart}:{}", own.server_name())).map_err(|_| invalid())
}

#[cfg(test)]
mod tests {
    use matrix_sdk::ruma::user_id;

    use super::*;

    #[test]
    fn addresses_are_made_on_the_users_server() {
        let own = user_id!("@alice:example.org");
        let address = |localpart| address_of(localpart, own).map(|alias| alias.to_string());
        assert_eq!(address("team"), Ok("#team:example.org".to_owned()));
        assert_eq!(address(" #team "), Ok("#team:example.org".to_owned()));
        assert_eq!(
            address("my-team_2"),
            Ok("#my-team_2:example.org".to_owned())
        );
        for bad in ["", "  ", "a:b", "two words", "a#b"] {
            assert!(
                matches!(address(bad), Err(CoreError::InvalidId { .. })),
                "{bad:?} is no address"
            );
        }
    }

    #[test]
    fn unknown_history_counts_as_shared() {
        assert_eq!(history_of(&HistoryVisibility::Shared), RoomHistory::Shared);
        assert_eq!(history_of(&HistoryVisibility::Joined), RoomHistory::Joined);
        assert_eq!(
            history_of(&HistoryVisibility::Invited),
            RoomHistory::Invited
        );
        assert_eq!(
            history_of(&HistoryVisibility::WorldReadable),
            RoomHistory::WorldReadable
        );
        assert_eq!(
            history_of(&HistoryVisibility::from("org.example.custom")),
            RoomHistory::Shared
        );
    }
}
