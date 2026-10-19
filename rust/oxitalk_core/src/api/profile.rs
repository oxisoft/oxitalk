//! The user's own profile: display name and avatar.

use mime::Mime;

use super::{error::CoreError, session::Session};

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
}
