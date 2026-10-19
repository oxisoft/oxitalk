//! Pictures and files from the server's content repository, kept in the account's encrypted
//! media cache so each is downloaded once.

use std::time::Duration;

use matrix_sdk::{
    media::{MediaFormat, MediaRequestParameters, MediaRetentionPolicy, MediaThumbnailSettings},
    ruma::{OwnedMxcUri, UInt, events::room::MediaSource},
};

use super::{error::CoreError, session::Session};

/// How often the cache drops what has expired.
const CLEANUP_EVERY: Duration = Duration::from_hours(24);

impl Session {
    /// A square thumbnail of the picture at `mxc_uri`, about `size` pixels wide, as encoded
    /// image bytes.
    ///
    /// # Errors
    ///
    /// [`CoreError::InvalidId`] for a malformed `mxc://` URI, otherwise as the server answers.
    pub async fn thumbnail(&self, mxc_uri: String, size: u32) -> Result<Vec<u8>, CoreError> {
        let uri = OwnedMxcUri::from(mxc_uri.as_str());
        if !uri.is_valid() {
            return Err(CoreError::InvalidId { id: mxc_uri });
        }
        self.fetch(MediaSource::Plain(uri), Some(size)).await
    }

    /// The whole file of a message, decrypted. `source` is a `MediaMessage`'s.
    ///
    /// # Errors
    ///
    /// [`CoreError::InvalidId`] for a malformed source, otherwise as the server answers.
    pub async fn media_content(&self, source: String) -> Result<Vec<u8>, CoreError> {
        self.fetch(parse_source(&source)?, None).await
    }

    /// A picture of a message's file about `size` pixels wide: the thumbnail the sender
    /// attached, else one the server makes of an unencrypted image, else the file itself.
    ///
    /// # Errors
    ///
    /// As [`Self::media_content`].
    pub async fn media_thumbnail(
        &self,
        source: String,
        thumbnail: Option<String>,
        size: u32,
    ) -> Result<Vec<u8>, CoreError> {
        if let Some(thumbnail) = thumbnail {
            return self.fetch(parse_source(&thumbnail)?, None).await;
        }
        match parse_source(&source)? {
            plain @ MediaSource::Plain(_) => self.fetch(plain, Some(size)).await,
            // The server can't see into an encrypted file.
            encrypted @ MediaSource::Encrypted(_) => self.fetch(encrypted, None).await,
        }
    }

    /// Writes a message's whole file to `path`, to open it in another app or keep it.
    ///
    /// # Errors
    ///
    /// As [`Self::media_content`], or [`CoreError::Internal`] if the file can't be written.
    pub async fn save_media(&self, source: String, path: String) -> Result<(), CoreError> {
        let content = self.media_content(source).await?;
        std::fs::write(&path, content).map_err(|error| CoreError::internal(&error))
    }

    /// Keeps cached media until it hasn't been used for `days`, or forever with `None`; no
    /// limit on size.
    ///
    /// # Errors
    ///
    /// Only if the cache can't be written.
    pub async fn set_media_retention(&self, days: Option<u32>) -> Result<(), CoreError> {
        let policy = MediaRetentionPolicy::empty()
            .with_last_access_expiry(days.map(|days| Duration::from_hours(u64::from(days) * 24)))
            .with_cleanup_frequency(Some(CLEANUP_EVERY));
        Ok(self
            .client
            .media()
            .set_media_retention_policy(policy)
            .await?)
    }

    /// The size of the media cache on disk, in bytes, if it can be told.
    ///
    /// # Errors
    ///
    /// Only if the cache can't be read.
    pub async fn media_cache_size(&self) -> Result<Option<i64>, CoreError> {
        let store = self
            .client
            .media_store()
            .lock()
            .await
            .map_err(|error| CoreError::internal(&error))?;
        let size = store
            .get_size()
            .await
            .map_err(|error| CoreError::internal(&error))?;
        Ok(size.map(|size| i64::try_from(size).unwrap_or(i64::MAX)))
    }

    /// Empties the media cache; the retention period stays.
    ///
    /// # Errors
    ///
    /// Only if the cache can't be written.
    pub async fn clear_media_cache(&self) -> Result<(), CoreError> {
        let media = self.client.media();
        let policy = media.media_retention_policy().await?;
        media
            .set_media_retention_policy(policy.with_last_access_expiry(Some(Duration::ZERO)))
            .await?;
        let cleaned = media.clean().await;
        media.set_media_retention_policy(policy).await?;
        cleaned?;
        // Gives the space back to the disk.
        let store = self
            .client
            .media_store()
            .lock()
            .await
            .map_err(|error| CoreError::internal(&error))?;
        store
            .optimize()
            .await
            .map_err(|error| CoreError::internal(&error))
    }

    async fn fetch(&self, source: MediaSource, size: Option<u32>) -> Result<Vec<u8>, CoreError> {
        let format = match size {
            Some(size) => {
                let size = UInt::from(size);
                MediaFormat::Thumbnail(MediaThumbnailSettings::new(size, size))
            }
            None => MediaFormat::File,
        };
        let request = MediaRequestParameters { source, format };
        Ok(self
            .client
            .media()
            .get_media_content(&request, true)
            .await?)
    }
}

fn parse_source(json: &str) -> Result<MediaSource, CoreError> {
    let source: MediaSource = serde_json::from_str(json).map_err(|_| CoreError::InvalidId {
        id: json.to_owned(),
    })?;
    if let MediaSource::Plain(uri) = &source
        && !uri.is_valid()
    {
        return Err(CoreError::InvalidId {
            id: uri.to_string(),
        });
    }
    Ok(source)
}
