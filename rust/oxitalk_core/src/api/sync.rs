//! Syncing: the SDK's sync service, passed through.
//!
//! The service runs in the SDK's offline mode: after a failed sync, including an expired
//! sliding-sync position (`M_UNKNOWN_POS`), it waits until the server answers again and starts
//! over by itself. Any other policy (restarting after an error, reacting to a rejected token)
//! belongs to the app.

use flutter_rust_bridge::frb;
use futures_util::{Stream, StreamExt, stream};
use matrix_sdk::Client;
use matrix_sdk_ui::{
    encryption_sync_service, room_list_service,
    sync_service::{self, SyncService},
};

use super::{error::CoreError, session::Session};
use crate::frb_generated::StreamSink;

/// [`sync_service::State`], one to one.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SyncState {
    /// Not started, or stopped.
    Idle,
    /// Syncing.
    Running,
    /// A sync ended without an error, without being stopped.
    Terminated,
    /// A sync ended in an error. Syncing has stopped until it is started again.
    Error { error: CoreError },
    /// The server can't be reached; syncing resumes by itself once it can.
    Offline,
}

impl Session {
    /// Starts syncing. Calling it while syncing is harmless; while offline it retries at once.
    pub async fn start_sync(&self) {
        self.sync.start().await;
    }

    /// Stops syncing, e.g. when the app goes to the background.
    pub async fn stop_sync(&self) {
        self.sync.stop().await;
    }

    /// Sends the current [`SyncState`], then every change.
    #[allow(
        clippy::unused_async,
        reason = "async so flutter_rust_bridge runs it on its tokio runtime, which spawn needs"
    )]
    pub async fn subscribe_sync_state(&self, sink: StreamSink<SyncState>) {
        let mut states = self.sync_states();
        self.spawn(async move {
            while let Some(state) = states.next().await {
                if sink.add(state).is_err() {
                    break;
                }
            }
        });
    }

    /// The current [`SyncState`], then every change, for Rust callers.
    #[frb(ignore)]
    pub fn sync_states(&self) -> impl Stream<Item = SyncState> + Send + Unpin + 'static {
        let states = self.sync.state();
        stream::iter([states.get()])
            .chain(states)
            .map(|state| sync_state(&state))
    }
}

pub(crate) async fn new_sync_service(client: Client) -> Result<SyncService, CoreError> {
    SyncService::builder(client)
        .with_offline_mode()
        .build()
        .await
        .map_err(|error| sync_error(&error))
}

fn sync_state(state: &sync_service::State) -> SyncState {
    match state {
        sync_service::State::Idle => SyncState::Idle,
        sync_service::State::Running => SyncState::Running,
        sync_service::State::Terminated => SyncState::Terminated,
        sync_service::State::Error(error) => SyncState::Error {
            error: sync_error(error),
        },
        sync_service::State::Offline => SyncState::Offline,
    }
}

fn sync_error(error: &sync_service::Error) -> CoreError {
    match error {
        sync_service::Error::RoomList(room_list_service::Error::SlidingSync(error))
        | sync_service::Error::EncryptionSync(encryption_sync_service::Error::SlidingSync(error)) => {
            CoreError::from_sdk(error)
        }
        other => CoreError::internal(other),
    }
}
