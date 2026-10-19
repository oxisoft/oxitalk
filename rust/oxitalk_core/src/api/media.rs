//! Downloading pictures (avatars) from the server's content repository.

use matrix_sdk::{
    media::{MediaFormat, MediaRequestParameters, MediaThumbnailSettings},
    ruma::{OwnedMxcUri, UInt, events::room::MediaSource},
};

use super::{error::CoreError, session::Session};

impl Session {
    /// A square thumbnail of the picture at `mxc_uri`, about `size` pixels wide, as encoded
    /// image bytes. Kept in the account's store, so it is downloaded once.
    ///
    /// # Errors
    ///
    /// [`CoreError::InvalidId`] for a malformed `mxc://` URI, otherwise as the server answers.
    pub async fn thumbnail(&self, mxc_uri: String, size: u32) -> Result<Vec<u8>, CoreError> {
        let uri = OwnedMxcUri::from(mxc_uri.as_str());
        if !uri.is_valid() {
            return Err(CoreError::InvalidId { id: mxc_uri });
        }
        let size = UInt::from(size);
        let request = MediaRequestParameters {
            source: MediaSource::Plain(uri),
            format: MediaFormat::Thumbnail(MediaThumbnailSettings::new(size, size)),
        };
        Ok(self
            .client
            .media()
            .get_media_content(&request, true)
            .await?)
    }
}
