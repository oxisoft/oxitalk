//! Finding people to chat with and public rooms to join.

use std::collections::HashSet;

use flutter_rust_bridge::frb;
use matrix_sdk::{
    RoomMemberships, RoomState,
    ruma::{
        OwnedUserId, UInt,
        api::client::directory::get_public_rooms_filtered::v3::Request as PublicRoomsRequest,
        directory::Filter,
    },
};

use super::{
    error::{CoreError, parse_id},
    session::Session,
};

/// Someone to chat with.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Person {
    pub user_id: String,
    pub display_name: Option<String>,
    /// An `mxc://` URI.
    pub avatar_url: Option<String>,
}

/// A room in the server's public directory.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PublicRoom {
    pub room_id: String,
    pub name: Option<String>,
    pub topic: Option<String>,
    /// Its main address, like `#team:example.org`.
    pub alias: Option<String>,
    pub members: u32,
    /// An `mxc://` URI.
    pub avatar_url: Option<String>,
    /// Whether the user is in it already.
    pub joined: bool,
}

impl Session {
    /// The people the user shares chats with, those of the most recently active chats first,
    /// each once; the user left out. Read from the store, so it works offline.
    ///
    /// # Errors
    ///
    /// Only if the store can't be read.
    pub async fn known_people(&self, limit: u32) -> Result<Vec<Person>, CoreError> {
        let own = self.client.user_id().map(ToOwned::to_owned);
        let mut rooms = self.client.joined_rooms();
        rooms.sort_by_key(|room| std::cmp::Reverse(room.recency_stamp()));
        let mut seen = HashSet::<OwnedUserId>::new();
        let mut people = Vec::new();
        for room in rooms {
            let members = room
                .members_no_sync(RoomMemberships::JOIN)
                .await
                .map_err(|error| CoreError::internal(&error))?;
            let mut candidates: Vec<Person> = members
                .iter()
                .map(|member| Person {
                    user_id: member.user_id().to_string(),
                    display_name: member.display_name().map(ToOwned::to_owned),
                    avatar_url: member.avatar_url().map(ToString::to_string),
                })
                .collect();
            // A DM names its partner before their membership reaches the store (it comes
            // with a later sync, or never while members load lazily); a one-to-one DM is
            // named after them.
            let targets = room.direct_targets();
            let dm_name = (targets.len() == 1)
                .then(|| room.cached_display_name().map(|name| name.to_string()))
                .flatten();
            candidates.extend(targets.iter().filter_map(|target| {
                target.as_user_id().map(|user| Person {
                    user_id: user.to_string(),
                    display_name: dm_name.clone(),
                    avatar_url: None,
                })
            }));
            for person in candidates {
                let Ok(user) = OwnedUserId::try_from(person.user_id.as_str()) else {
                    continue;
                };
                if Some(&user) == own.as_ref() || !seen.insert(user) {
                    continue;
                }
                people.push(person);
                if people.len() >= limit as usize {
                    return Ok(people);
                }
            }
        }
        Ok(people)
    }

    /// People in the server's user directory whose name or ID matches `term`. Which users
    /// a server lists is up to it (often those sharing a room with the user, or in public
    /// rooms).
    ///
    /// # Errors
    ///
    /// As the server answers.
    pub async fn search_people(&self, term: String, limit: u32) -> Result<Vec<Person>, CoreError> {
        let own = self.client.user_id().map(ToString::to_string);
        let response = self
            .client
            .search_users(term.trim(), u64::from(limit))
            .await?;
        Ok(response
            .results
            .into_iter()
            .map(|user| Person {
                user_id: user.user_id.to_string(),
                display_name: user.display_name,
                avatar_url: user.avatar_url.map(|url| url.to_string()),
            })
            .filter(|person| Some(&person.user_id) != own.as_ref())
            .collect())
    }

    /// The user's direct chat with `user_id`, if they have one.
    ///
    /// # Errors
    ///
    /// [`CoreError::InvalidId`].
    #[allow(
        clippy::needless_pass_by_value,
        reason = "flutter_rust_bridge passes owned strings"
    )]
    #[frb(sync)]
    pub fn dm_with(&self, user_id: String) -> Result<Option<String>, CoreError> {
        let user: OwnedUserId = parse_id(&user_id)?;
        Ok(self
            .client
            .get_dm_room(&user)
            .map(|room| room.room_id().to_string()))
    }

    /// Rooms in the server's public directory matching `term` (all with `None`): the most
    /// joined first, the ones the user is in at the end.
    ///
    /// # Errors
    ///
    /// As the server answers.
    pub async fn public_rooms(
        &self,
        term: Option<String>,
        limit: u32,
    ) -> Result<Vec<PublicRoom>, CoreError> {
        let mut request = PublicRoomsRequest::new();
        request.limit = Some(UInt::from(limit));
        request.filter = Filter::new();
        request.filter.generic_search_term = term.filter(|term| !term.trim().is_empty());
        let response = self.client.public_rooms_filtered(request).await?;
        let mut rooms: Vec<PublicRoom> = response
            .chunk
            .into_iter()
            .map(|room| PublicRoom {
                joined: self
                    .client
                    .get_room(&room.room_id)
                    .is_some_and(|known| known.state() == RoomState::Joined),
                room_id: room.room_id.to_string(),
                name: room.name,
                topic: room.topic,
                alias: room.canonical_alias.map(|alias| alias.to_string()),
                members: u32::try_from(u64::from(room.num_joined_members)).unwrap_or(u32::MAX),
                avatar_url: room.avatar_url.map(|url| url.to_string()),
            })
            .collect();
        rooms.sort_by_key(|room| (room.joined, std::cmp::Reverse(room.members)));
        Ok(rooms)
    }
}
