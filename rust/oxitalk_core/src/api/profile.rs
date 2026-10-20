//! The user's own profile: display name and avatar.

use matrix_sdk::ruma::{api::error::ErrorKind, events::GlobalAccountDataEventType, serde::Raw};
use mime::Mime;

use super::{error::CoreError, session::Session};

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
        let account = self.client.account();
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
