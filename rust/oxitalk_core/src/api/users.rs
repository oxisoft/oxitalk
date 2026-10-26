//! Other people: their profile as the app shows it (name, picture, whether the user verified
//! them, whether they are ignored, the direct chat with them), verifying them by emoji,
//! ignoring them, and reporting them or one of their messages to the server's admins.

use flutter_rust_bridge::frb;
use futures_util::{
    Stream, StreamExt,
    stream::{self, BoxStream},
};
use matrix_sdk::{
    encryption::identities::RequestVerificationError,
    ruma::{
        OwnedEventId, OwnedUserId,
        api::{client::reporting::report_user, error::ErrorKind},
        events::{
            ignored_user_list::IgnoredUserListEventContent, key::verification::VerificationMethod,
        },
    },
};

use super::{
    error::{CoreError, parse_id},
    session::Session,
    verification::Verification,
};
use crate::frb_generated::StreamSink;

/// Someone as their profile sheet shows them.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct UserProfile {
    pub user_id: String,
    pub display_name: Option<String>,
    /// An `mxc://` URI.
    pub avatar_url: Option<String>,
    /// Whether the user verified them; `None` when they have no cross-signing identity (yet),
    /// so they can't be verified.
    pub verified: Option<bool>,
    pub ignored: bool,
    /// The user's direct chat with them, if any.
    pub dm_room_id: Option<String>,
}

impl Session {
    /// `user_id`'s profile: their name and picture in the room `room_id` if given and they are
    /// a member, else as their server tells.
    ///
    /// # Errors
    ///
    /// [`CoreError::InvalidId`]. A profile the server won't tell (e.g. nobody shares a room
    /// with them) comes without name and picture, not as an error.
    pub async fn user_profile(
        &self,
        user_id: String,
        room_id: Option<String>,
    ) -> Result<UserProfile, CoreError> {
        let user: OwnedUserId = parse_id(user_id.trim())?;
        let member = match room_id.as_deref().map(|id| self.room(id)) {
            Some(Ok(room)) => room.get_member_no_sync(&user).await.ok().flatten(),
            _ => None,
        };
        let (display_name, avatar_url) = match member {
            Some(member) => (
                member.display_name().map(ToOwned::to_owned),
                member.avatar_url().map(ToString::to_string),
            ),
            None => match self.client.account().fetch_user_profile_of(&user).await {
                Ok(profile) => (
                    profile
                        .get("displayname")
                        .and_then(|value| value.as_str().map(ToOwned::to_owned)),
                    profile
                        .get("avatar_url")
                        .and_then(|value| value.as_str().map(ToOwned::to_owned)),
                ),
                Err(_) => (None, None),
            },
        };
        let encryption = self.client.encryption();
        let identity = match encryption.get_user_identity(&user).await {
            Ok(Some(identity)) => Some(identity),
            // Not known here yet: ask the server.
            _ => encryption.request_user_identity(&user).await.ok().flatten(),
        };
        Ok(UserProfile {
            user_id: user.to_string(),
            display_name: display_name.filter(|name| !name.trim().is_empty()),
            avatar_url,
            verified: identity.map(|identity| identity.is_verified()),
            ignored: self.client.is_user_ignored(&user).await,
            dm_room_id: self
                .client
                .get_dm_room(&user)
                .map(|room| room.room_id().to_string()),
        })
    }

    /// Asks `user_id` to verify with the user by emoji, in their direct chat (made if there is
    /// none); this side starts the emoji once they accept, as with the user's own devices.
    ///
    /// # Errors
    ///
    /// [`CoreError::InvalidId`]; [`CoreError::Internal`] if they have no cross-signing identity
    /// or the chat can't be made; otherwise as the server answers.
    pub async fn verify_user(&self, user_id: String) -> Result<Verification, CoreError> {
        let user: OwnedUserId = parse_id(user_id.trim())?;
        let identity = self
            .client
            .encryption()
            .request_user_identity(&user)
            .await
            .map_err(|error| CoreError::from_sdk(&error))?
            .ok_or_else(|| CoreError::internal(&"the user has no cross-signing identity"))?;
        let request = identity
            .request_verification_with_methods(vec![VerificationMethod::SasV1])
            .await
            .map_err(|error| match error {
                RequestVerificationError::Sdk(error) => CoreError::from_sdk(&error),
                other @ RequestVerificationError::RoomCreation(_) => CoreError::internal(&other),
            })?;
        Ok(Verification::new(request))
    }

    /// Ignores `user_id`: their messages and invites are no longer shown, on every device of
    /// the account. The SDK then drops the cached timelines, which load again without them.
    ///
    /// # Errors
    ///
    /// [`CoreError::InvalidId`]; [`CoreError::Internal`] for the user's own ID; otherwise as the
    /// server answers.
    pub async fn ignore_user(&self, user_id: String) -> Result<(), CoreError> {
        let user: OwnedUserId = parse_id(user_id.trim())?;
        Ok(self.client.account().ignore_user(&user).await?)
    }

    /// Stops ignoring `user_id`; their messages show again.
    ///
    /// # Errors
    ///
    /// As [`Session::ignore_user`].
    pub async fn unignore_user(&self, user_id: String) -> Result<(), CoreError> {
        let user: OwnedUserId = parse_id(user_id.trim())?;
        Ok(self.client.account().unignore_user(&user).await?)
    }

    /// The users the account ignores, sorted.
    ///
    /// # Errors
    ///
    /// Only if the store can't be read.
    pub async fn ignored_users(&self) -> Result<Vec<String>, CoreError> {
        ignored_list(&self.client).await
    }

    /// Sends [`Session::ignored_users`] now, then again whenever the list changes, here or on
    /// another device.
    #[allow(
        clippy::unused_async,
        reason = "async so flutter_rust_bridge runs it on its tokio runtime, which spawn needs"
    )]
    pub async fn subscribe_ignored_users(&self, sink: StreamSink<Vec<String>>) {
        let mut lists = self.ignored_user_lists();
        self.spawn(async move {
            while let Some(list) = lists.next().await {
                if sink.add(list).is_err() {
                    break;
                }
            }
        });
    }

    /// [`Session::ignored_users`] now, then after every change, for Rust callers.
    #[frb(ignore)]
    pub fn ignored_user_lists(&self) -> impl Stream<Item = Vec<String>> + Send + Unpin + 'static {
        struct State {
            client: matrix_sdk::Client,
            changes: BoxStream<'static, Vec<OwnedUserId>>,
            last: Option<Vec<String>>,
            first: bool,
        }
        let state = State {
            changes: self.client.subscribe_to_ignore_user_list_changes().boxed(),
            client: self.client.clone(),
            last: None,
            first: true,
        };
        Box::pin(stream::unfold(state, |mut state| async move {
            loop {
                if state.first {
                    state.first = false;
                } else {
                    // The store has the change by the time it is announced.
                    state.changes.next().await?;
                }
                if let Ok(list) = ignored_list(&state.client).await
                    && state.last.as_ref() != Some(&list)
                {
                    state.last = Some(list.clone());
                    return Some((list, state));
                }
            }
        }))
    }

    /// Reports `user_id` to their server's admins, with an optional reason.
    ///
    /// # Errors
    ///
    /// [`CoreError::InvalidId`], or as the server answers (an older server may not know the
    /// request).
    pub async fn report_user(
        &self,
        user_id: String,
        reason: Option<String>,
    ) -> Result<(), CoreError> {
        let user: OwnedUserId = parse_id(user_id.trim())?;
        let reason = trimmed(reason).unwrap_or_default();
        let request = report_user::v3::Request::new(user.clone(), reason.clone());
        match self.client.send(request).await {
            // A server that has the endpoint but doesn't claim Matrix 1.14 (Synapse 1.162
            // claims 1.12) gets the MSC4260 path, which it doesn't know: try the stable one.
            Err(error) if error.client_api_error_kind() == Some(&ErrorKind::Unrecognized) => {
                self.report_user_stable(&user, &reason).await
            }
            result => result.map(|_| ()).map_err(Into::into),
        }
    }

    /// `POST /_matrix/client/v3/users/{userId}/report`, whatever versions the server claims.
    async fn report_user_stable(&self, user: &OwnedUserId, reason: &str) -> Result<(), CoreError> {
        let token = self
            .client
            .access_token()
            .ok_or(CoreError::SessionExpired)?;
        let mut url = self.client.homeserver();
        url.path_segments_mut()
            .map_err(|()| CoreError::internal(&"the homeserver URL can't have a path"))?
            .pop_if_empty()
            .extend(["_matrix", "client", "v3", "users", user.as_str(), "report"]);
        let body = serde_json::json!({ "reason": reason }).to_string();
        let response = self
            .client
            .http_client()
            .post(url)
            .bearer_auth(token)
            .header("Content-Type", "application/json")
            .body(body)
            .send()
            .await
            .map_err(|error| CoreError::Network {
                message: error.to_string(),
            })?;
        match response.status().as_u16() {
            200..=299 => Ok(()),
            403 => Err(CoreError::Forbidden {
                message: "report refused".to_owned(),
            }),
            status => Err(CoreError::internal(&format!(
                "report answered with HTTP {status}"
            ))),
        }
    }

    /// Reports the message `event_id` of the room `room_id` to the server's admins, with an
    /// optional reason.
    ///
    /// # Errors
    ///
    /// [`CoreError::InvalidId`] or [`CoreError::RoomNotFound`]; otherwise as the server answers.
    pub async fn report_event(
        &self,
        room_id: String,
        event_id: String,
        reason: Option<String>,
    ) -> Result<(), CoreError> {
        let event: OwnedEventId = parse_id(event_id.trim())?;
        self.room(&room_id)?
            .report_content(event, trimmed(reason))
            .await?;
        Ok(())
    }
}

/// The ignored users as the account data in the store has them: the SDK's own list is empty
/// after a restore until the server sends a change.
#[frb(ignore)]
async fn ignored_list(client: &matrix_sdk::Client) -> Result<Vec<String>, CoreError> {
    let content = client
        .account()
        .account_data::<IgnoredUserListEventContent>()
        .await?
        .map(|raw| raw.deserialize())
        .transpose()
        .map_err(|error| CoreError::internal(&error))?;
    let mut users: Vec<String> = content
        .map(|content| {
            content
                .ignored_users
                .into_keys()
                .map(|user| user.to_string())
                .collect()
        })
        .unwrap_or_default();
    users.sort();
    Ok(users)
}

fn trimmed(reason: Option<String>) -> Option<String> {
    reason
        .map(|reason| reason.trim().to_owned())
        .filter(|reason| !reason.is_empty())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_blank_reason_is_none() {
        assert_eq!(trimmed(None), None);
        assert_eq!(trimmed(Some("  ".to_owned())), None);
        assert_eq!(trimmed(Some(" spam ".to_owned())), Some("spam".to_owned()));
    }
}
