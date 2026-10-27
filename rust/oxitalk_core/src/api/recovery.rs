//! Recovery: the account's secrets (its cross-signing keys and the key backup's key) kept on
//! the server, encrypted with the recovery key, so that a new device can verify itself and
//! read the old messages. Its state, setting it up and changing its key. The key is shown to
//! the user once and can't be read back: neither the server nor the app keeps it.

use flutter_rust_bridge::frb;
use futures_util::{Stream, StreamExt, stream};
use matrix_sdk::{
    Client,
    encryption::{
        backups::BackupState,
        recovery::{EnableProgress, RecoveryError, RecoveryState},
    },
};
use tokio::sync::broadcast;

use super::{error::CoreError, session::Session, verification::recovery_error};
use crate::frb_generated::StreamSink;

/// How long [`Session::enable_recovery`] waits for its last progress steps to be passed on.
const PROGRESS_RELAY_DEADLINE: std::time::Duration = std::time::Duration::from_secs(5);

/// [`RecoveryState`], one to one.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RecoveryStatus {
    /// Not known yet, e.g. right after login.
    Unknown,
    /// Set up, and this device has every secret.
    Enabled,
    /// Not set up.
    Disabled,
    /// Set up, but this device lacks some of the secrets: entering the recovery key brings
    /// them.
    Incomplete,
}

/// What the Encryption settings show: recovery and the key backup.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct EncryptionStatus {
    pub recovery: RecoveryStatus,
    /// Whether this device backs its message keys up to the server.
    pub backup_enabled: bool,
}

/// How far [`Session::enable_recovery`] is: [`EnableProgress`] without the key.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RecoveryProgress {
    Starting,
    CreatingBackup,
    CreatingRecoveryKey,
    /// Backing the message keys up; sent again as the count grows.
    BackingUp {
        backed_up: u32,
        total: u32,
    },
    /// Some message keys could not be backed up; the device tries again later.
    BackupFailed,
    Done,
}

impl Session {
    /// Sends the current [`EncryptionStatus`], then every change.
    #[allow(
        clippy::unused_async,
        reason = "async so flutter_rust_bridge runs it on its tokio runtime, which spawn needs"
    )]
    pub async fn subscribe_encryption_status(&self, sink: StreamSink<EncryptionStatus>) {
        let mut statuses = self.encryption_statuses();
        self.spawn(async move {
            while let Some(status) = statuses.next().await {
                if sink.add(status).is_err() {
                    break;
                }
            }
        });
    }

    /// The current [`EncryptionStatus`], then every change, for Rust callers.
    #[frb(ignore)]
    pub fn encryption_statuses(
        &self,
    ) -> impl Stream<Item = EncryptionStatus> + Send + Unpin + 'static {
        let encryption = self.client.encryption();
        let recovery = encryption.recovery().state_stream().map(|_| ());
        let backups = encryption.backups().state_stream().map(|_| ());
        let client = self.client.clone();
        let mut last = None;
        Box::pin(
            stream::once(async {})
                .chain(stream::select(recovery, backups))
                .filter_map(move |()| {
                    let status = encryption_status(&client);
                    let changed = last.replace(status) != Some(status);
                    std::future::ready(changed.then_some(status))
                }),
        )
    }

    /// Sets recovery up: a key backup if there is none, then a new recovery key that the
    /// account's secrets are stored with; waits until the message keys are backed up.
    /// Returns the new key, to show the user once. [`Self::subscribe_recovery_progress`]
    /// tells how far it is.
    ///
    /// # Errors
    ///
    /// [`CoreError::Internal`] if the server has a key backup this device isn't connected to
    /// (verify it first), otherwise as the server answers.
    pub async fn enable_recovery(&self) -> Result<String, CoreError> {
        let recovery = self.client.encryption().recovery();
        let enable = recovery.enable().wait_for_backups_to_upload();
        let mut updates = enable.subscribe_to_progress();
        let sender = self.recovery_progress.clone();
        let forward = tokio::spawn(async move {
            while let Some(update) = updates.next().await {
                // A lagged update only skips a step.
                if let Ok(update) = update {
                    let _ = sender.send(recovery_progress(&update));
                }
            }
        });
        let result = enable.await;
        // Every step is passed on before returning, the last (Done) too: aborting the relay
        // here lost the steps it hadn't passed on yet (seen under load). With the enabling
        // finished its sender is gone, so the relay ends once it has caught up.
        let mut forward = forward;
        if tokio::time::timeout(PROGRESS_RELAY_DEADLINE, &mut forward)
            .await
            .is_err()
        {
            forward.abort();
        }
        result.map_err(|error| enable_error(&error))
    }

    /// Sends how far a running [`Self::enable_recovery`] is, from now on.
    #[allow(
        clippy::unused_async,
        reason = "async so flutter_rust_bridge runs it on its tokio runtime, which spawn needs"
    )]
    pub async fn subscribe_recovery_progress(&self, sink: StreamSink<RecoveryProgress>) {
        let mut progress = self.recovery_progresses();
        self.spawn(async move {
            while let Some(step) = progress.next().await {
                if sink.add(step).is_err() {
                    break;
                }
            }
        });
    }

    /// Like [`Self::subscribe_recovery_progress`], for Rust callers.
    #[frb(ignore)]
    pub fn recovery_progresses(
        &self,
    ) -> impl Stream<Item = RecoveryProgress> + Send + Unpin + 'static {
        Box::pin(stream::unfold(
            self.recovery_progress.subscribe(),
            |mut receiver| async move {
                loop {
                    match receiver.recv().await {
                        Ok(step) => return Some((step, receiver)),
                        Err(broadcast::error::RecvError::Lagged(_)) => {}
                        Err(broadcast::error::RecvError::Closed) => return None,
                    }
                }
            },
        ))
    }

    /// Replaces the recovery key with a new one and returns it, to show the user once; the
    /// old key stops working.
    ///
    /// # Errors
    ///
    /// [`CoreError::RecoveryNotSetUp`] if recovery is off, otherwise as the server answers.
    pub async fn reset_recovery_key(&self) -> Result<String, CoreError> {
        let recovery = self.client.encryption().recovery();
        if recovery.state() == RecoveryState::Disabled {
            return Err(CoreError::RecoveryNotSetUp);
        }
        recovery
            .reset_key()
            .await
            .map_err(|error| recovery_error(&error))
    }

    /// Whether this is the account's only device: logging out of it without recovery loses
    /// the encrypted history.
    ///
    /// # Errors
    ///
    /// As the server answers.
    pub async fn is_last_device(&self) -> Result<bool, CoreError> {
        self.client
            .encryption()
            .recovery()
            .is_last_device()
            .await
            .map_err(|error| recovery_error(&error))
    }
}

fn encryption_status(client: &Client) -> EncryptionStatus {
    let encryption = client.encryption();
    EncryptionStatus {
        recovery: match encryption.recovery().state() {
            RecoveryState::Unknown => RecoveryStatus::Unknown,
            RecoveryState::Enabled => RecoveryStatus::Enabled,
            RecoveryState::Disabled => RecoveryStatus::Disabled,
            RecoveryState::Incomplete => RecoveryStatus::Incomplete,
        },
        backup_enabled: backup_on(encryption.backups().state()),
    }
}

/// Whether the backup is in use: on, or fetching keys from it.
fn backup_on(state: BackupState) -> bool {
    matches!(state, BackupState::Enabled | BackupState::Downloading)
}

fn recovery_progress(progress: &EnableProgress) -> RecoveryProgress {
    let count = |n: usize| u32::try_from(n).unwrap_or(u32::MAX);
    match progress {
        EnableProgress::Starting => RecoveryProgress::Starting,
        EnableProgress::CreatingBackup => RecoveryProgress::CreatingBackup,
        EnableProgress::CreatingRecoveryKey => RecoveryProgress::CreatingRecoveryKey,
        EnableProgress::BackingUp(counts) => RecoveryProgress::BackingUp {
            backed_up: count(counts.backed_up),
            total: count(counts.total),
        },
        EnableProgress::RoomKeyUploadError => RecoveryProgress::BackupFailed,
        // The key it carries is returned by enable_recovery; it stays out of the stream.
        EnableProgress::Done { .. } => RecoveryProgress::Done,
    }
}

fn enable_error(error: &RecoveryError) -> CoreError {
    match error {
        RecoveryError::BackupExistsOnServer => CoreError::internal(
            &"the server has a key backup this device isn't connected to; verify it first",
        ),
        other => recovery_error(other),
    }
}

#[cfg(test)]
mod tests {
    use matrix_sdk::encryption::backups::BackupState;

    use super::*;

    #[test]
    fn the_progress_never_carries_the_key() {
        let done = EnableProgress::Done {
            recovery_key: "EsT0 secret".to_owned(),
        };
        assert_eq!(recovery_progress(&done), RecoveryProgress::Done);
        assert!(!format!("{:?}", recovery_progress(&done)).contains("secret"));
    }

    #[test]
    fn the_backup_is_on_when_enabled_or_downloading() {
        assert!(backup_on(BackupState::Enabled));
        assert!(backup_on(BackupState::Downloading));
        assert!(!backup_on(BackupState::Unknown));
        assert!(!backup_on(BackupState::Disabling));
    }
}
