//! The user's own profile: display name and avatar.

use std::time::Duration;

use flutter_rust_bridge::frb;
use matrix_sdk::{
    Client,
    ruma::{
        api::error::ErrorKind,
        events::{GlobalAccountDataEventType, room::member::SyncRoomMemberEvent},
        serde::Raw,
    },
};
use mime::Mime;
use tokio::sync::mpsc;

use super::{error::CoreError, session::Session};
use crate::frb_generated::StreamSink;

/// How long a change of the user's own member events is let settle before the profile is
/// asked for again: a new picture is one member event in every room.
const PROFILE_SETTLE: Duration = Duration::from_millis(500);

/// Where Element keeps the recently used emojis.
const RECENT_EMOJI_EVENT_TYPE: &str = "io.element.recent_emoji";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Profile {
    pub display_name: Option<String>,
    /// An `mxc://` URI; see [`Session::thumbnail`].
    pub avatar_url: Option<String>,
}

impl Session {
    /// The user's profile as the server has it, or as last seen when the server can't be
    /// reached.
    ///
    /// # Errors
    ///
    /// Only if the store can't be read.
    pub async fn own_profile(&self) -> Result<Profile, CoreError> {
        fetch_profile(&self.client).await
    }

    /// The user's profile each time it changes, also when another app or device changed it
    /// (the server then sends the user's new member event in their rooms). Not the current
    /// profile at the start: that is [`Self::own_profile`].
    #[allow(
        clippy::unused_async,
        reason = "async so flutter_rust_bridge runs it on its tokio runtime, which spawn needs"
    )]
    pub async fn subscribe_own_profile(&self, sink: StreamSink<Profile>) {
        self.own_profile_updates(move |profile| sink.add(profile).is_ok());
    }

    /// Like [`Self::subscribe_own_profile`], for Rust callers. Must run on a tokio runtime.
    /// Stops when `emit` returns `false`.
    #[frb(ignore)]
    pub fn own_profile_updates(&self, emit: impl Fn(Profile) -> bool + Send + Sync + 'static) {
        let Some(user) = self.client.user_id().map(ToOwned::to_owned) else {
            return;
        };
        let (sender, mut receiver) = mpsc::unbounded_channel::<()>();
        let handler = self
            .client
            .add_event_handler(move |event: SyncRoomMemberEvent| {
                let sender = sender.clone();
                let user = user.clone();
                async move {
                    if event.state_key() == &user {
                        let _ = sender.send(());
                    }
                }
            });
        let guard = self.client.event_handler_drop_guard(handler);
        let client = self.client.clone();
        self.spawn(async move {
            let _guard = guard;
            let mut last: Option<Profile> = None;
            while receiver.recv().await.is_some() {
                tokio::time::sleep(PROFILE_SETTLE).await;
                while receiver.try_recv().is_ok() {}
                let Ok(profile) = fetch_profile(&client).await else {
                    continue;
                };
                if last.as_ref() == Some(&profile) {
                    continue;
                }
                if !emit(profile.clone()) {
                    break;
                }
                last = Some(profile);
            }
        });
    }
}

/// The user's profile as the server has it, or as last seen when it can't be reached.
async fn fetch_profile(client: &Client) -> Result<Profile, CoreError> {
    let account = client.account();
    let (display_name, avatar_url) = match (
        account.get_display_name().await,
        account.get_avatar_url().await,
    ) {
        (Ok(display_name), Ok(avatar_url)) => (display_name, avatar_url),
        // Offline: the avatar is cached; the display name isn't.
        _ => (None, account.get_cached_avatar_url().await?),
    };
    Ok(Profile {
        display_name,
        avatar_url: avatar_url.map(|url| url.to_string()),
    })
}

impl Session {
    /// Uploads `data` and makes it the user's avatar. `mime_type` is its type, like
    /// `image/png`.
    ///
    /// # Errors
    ///
    /// [`CoreError::Internal`] for a malformed `mime_type`, otherwise as the server answers
    /// (it may refuse a file that is too large).
    pub async fn set_avatar(&self, data: Vec<u8>, mime_type: String) -> Result<(), CoreError> {
        let mime_type: Mime = mime_type
            .parse()
            .map_err(|error| CoreError::internal(&error))?;
        self.client
            .account()
            .upload_avatar(&mime_type, data)
            .await?;
        Ok(())
    }

    /// Removes the user's avatar.
    ///
    /// # Errors
    ///
    /// As the server answers.
    pub async fn remove_avatar(&self) -> Result<(), CoreError> {
        Ok(self.client.account().set_avatar_url(None).await?)
    }

    /// The emojis the user used lately, the last used first; kept in the account like
    /// Element keeps them, so they are the same everywhere.
    ///
    /// # Errors
    ///
    /// Only if the store can't be read.
    pub async fn recent_emojis(&self) -> Result<Vec<String>, CoreError> {
        let account = self.client.account();
        // The server's, which another device may have just changed; else the last synced
        // (offline, or none yet).
        let recent = match account.get_recent_emojis(true).await {
            Ok(recent) => recent,
            Err(_) => account.get_recent_emojis(false).await?,
        };
        Ok(recent.into_iter().map(|(emoji, _)| emoji).collect())
    }

    /// Counts a use of `emoji` among the recent ones.
    ///
    /// # Errors
    ///
    /// As the server answers.
    pub async fn add_recent_emoji(&self, emoji: String) -> Result<(), CoreError> {
        let account = self.client.account();
        match account.add_recent_emoji(&emoji).await {
            // The SDK reads the list from the server first, which has none until the first
            // emoji: start it here, as Element does.
            Err(error) if error.client_api_error_kind() == Some(&ErrorKind::NotFound) => {
                let content = serde_json::json!({ "recent_emoji": [[emoji, 1]] }).to_string();
                account
                    .set_account_data_raw(
                        GlobalAccountDataEventType::from(RECENT_EMOJI_EVENT_TYPE),
                        Raw::from_json_string(content).map_err(|e| CoreError::internal(&e))?,
                    )
                    .await?;
                Ok(())
            }
            result => Ok(result?),
        }
    }
}
