//! Logging in, restoring a session, and the handle the app holds while it is logged in.

use std::{
    collections::{HashMap, HashSet},
    fmt,
    sync::{Arc, Mutex, PoisonError},
    time::Duration,
};

use flutter_rust_bridge::frb;
use futures_util::{Stream, StreamExt};
use matrix_sdk::{
    Client, ClientBuilder, SessionMeta, SessionTokens, SqliteStoreConfig, ThreadingSupport,
    authentication::matrix::MatrixSession,
    cross_process_lock::CrossProcessLockConfig,
    encryption::{BackupDownloadStrategy, EncryptionSettings},
    notification_settings::NotificationSettings,
    ruma::{OwnedRoomId, OwnedUserId},
    store::RoomLoadSettings,
};
use matrix_sdk_ui::sync_service::SyncService;
use tokio::{runtime::Handle, sync::broadcast, task::AbortHandle};

use super::{
    error::{CoreError, parse_id},
    notify::{self, Candidate},
    pins,
    recovery::RecoveryProgress,
    sync::new_sync_service,
};
use crate::frb_generated::StreamSink;

/// Device name shown in the user's session list.
const DEVICE_DISPLAY_NAME: &str = "OxiTalk";

/// Connections per database. The SDK's default is four per physical core, kept open once
/// opened: 64 per database on a 16-core desktop, each with its own page cache.
const STORE_POOL_SIZE: usize = 4;

/// What the app keeps in secure storage to restore a session without logging in again.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SessionData {
    pub homeserver_url: String,
    pub user_id: String,
    pub device_id: String,
    pub access_token: String,
}

/// [`matrix_sdk::SessionChange`], one to one.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SessionChange {
    /// The server rejected the access token. With `soft_logout` the user may log in again on
    /// the same device and keep its keys.
    UnknownToken { soft_logout: bool },
    /// The tokens were refreshed; the app should store [`Session::session_data`] again.
    TokensRefreshed,
}

/// A logged-in account. Dropping it stops everything it runs.
#[frb(opaque)]
pub struct Session {
    pub(crate) client: Client,
    pub(crate) sync: SyncService,
    /// The one copy of the push rules the session keeps: the SDK makes a new one, with its own
    /// event handler, on every `Client::notification_settings` call.
    pub(crate) notification_settings: NotificationSettings,
    /// What the sync hands over for OS notifications; each subscription listens to it.
    pub(crate) notification_candidates: broadcast::Sender<Candidate>,
    /// The rooms the sync follows closely (all their state, more of their timeline), as
    /// Element X does for an open room, with how many open chats want each.
    pub(crate) room_subscriptions: Arc<Mutex<HashMap<OwnedRoomId, usize>>>,
    /// How far setting up recovery is, for whoever follows it.
    pub(crate) recovery_progress: broadcast::Sender<RecoveryProgress>,
    /// The rooms whose call this device is in through an `ActiveCall` of this session.
    pub(crate) active_calls: Arc<Mutex<HashSet<OwnedRoomId>>>,
    /// Tasks that feed the app's streams; aborted when the session is dropped.
    tasks: Mutex<Vec<AbortHandle>>,
    /// The runtime the session was made on, where its stores close when it is dropped.
    runtime: Handle,
}

/// Logs in with a user name and password. `server` is a server name (`matrix.org`, found
/// through `.well-known`) or a homeserver URL. `store_dir` must be a directory of its own for
/// this account; the store in it is encrypted with `store_passphrase`.
///
/// # Errors
///
/// [`CoreError::Forbidden`] for a wrong user name or password, [`CoreError::InvalidHomeserver`],
/// [`CoreError::Network`], or [`CoreError::WrongStorePassphrase`] for an existing store.
pub async fn login(
    server: String,
    username: String,
    password: String,
    store_dir: String,
    store_passphrase: String,
) -> Result<Session, CoreError> {
    // A server name ("matrix.org") is looked up; a URL is checked to be a homeserver.
    let homeserver = Client::builder().server_name_or_homeserver_url(&server);
    let client = build_client(homeserver, &store_dir, &store_passphrase).await?;
    client
        .matrix_auth()
        .login_username(&username, &password)
        .initial_device_display_name(DEVICE_DISPLAY_NAME)
        .await?;
    Session::new(client).await
}

/// Restores a session from what [`Session::session_data`] returned, on the same store. It
/// doesn't contact the server; an expired token shows once syncing starts.
///
/// # Errors
///
/// [`CoreError::WrongStorePassphrase`], or [`CoreError::InvalidId`] for a malformed user ID.
pub async fn restore(
    data: SessionData,
    store_dir: String,
    store_passphrase: String,
) -> Result<Session, CoreError> {
    let user_id: OwnedUserId = parse_id(&data.user_id)?;
    // The saved URL as is, with no request: a restore has to work offline.
    let homeserver = Client::builder().homeserver_url(&data.homeserver_url);
    let client = build_client(homeserver, &store_dir, &store_passphrase).await?;
    let session = MatrixSession {
        meta: SessionMeta {
            user_id,
            device_id: data.device_id.into(),
        },
        tokens: SessionTokens {
            access_token: data.access_token,
            refresh_token: None,
        },
    };
    client
        .matrix_auth()
        .restore_session(session, RoomLoadSettings::default())
        .await?;
    Session::new(client).await
}

async fn build_client(
    homeserver: ClientBuilder,
    store_dir: &str,
    store_passphrase: &str,
) -> Result<Client, CoreError> {
    Ok(homeserver
        .with_encryption_settings(EncryptionSettings {
            // A new account gets its identity at the first login, which verifies that device.
            auto_enable_cross_signing: true,
            // Keys go to the server backup; a verified device fetches the ones it lacks.
            auto_enable_backups: true,
            backup_download_strategy: BackupDownloadStrategy::AfterDecryptionFailure,
        })
        // Threads as Element X has them. Without it the SDK's caches treat thread replies as
        // the room's own messages: a reply read in its thread still counted the room unread
        // (the chat's receipt is on its main timeline), and a thread's cache could go out of
        // step with the server. Subscriptions (MSC4306) are off: servers don't have them yet.
        .with_threading_support(ThreadingSupport::Enabled {
            with_subscriptions: false,
        })
        .sqlite_store_with_config_and_cache_path(
            SqliteStoreConfig::new(store_dir)
                .passphrase(Some(store_passphrase))
                .pool_max_size(STORE_POOL_SIZE),
            None::<&str>,
        )
        // No other process opens the account's stores (no notification extension or service).
        // The SDK's default cross-process lock renews its lease with a synced write to the
        // crypto store every 50 ms while the sync runs: ~4 MB/s of disk writes when idle
        // with three accounts on btrfs.
        .cross_process_store_config(CrossProcessLockConfig::SingleProcess)
        // The room list syncs one event per room, so a device back after a gap gets only each
        // room's newest event behind a gap. The SDK counts unread events and looks for the
        // latest event only in what it has loaded: a gap ending in a reaction or an edit left
        // a stale preview and place in the list and wrong unread counts, unlike the account's
        // other devices. The SDK's background back-pagination (off by default) fills the gap
        // until the read receipt and a suitable latest event are found. Element X iOS turns it
        // on too. Test: homeserver multi_device.
        .with_enable_automatic_back_pagination(true)
        .build()
        .await?)
}

impl Session {
    async fn new(client: Client) -> Result<Self, CoreError> {
        let sync = new_sync_service(client.clone()).await?;
        let notification_settings = client.notification_settings().await;
        let notification_candidates = notify::register(&client).await;
        let session = Self {
            client,
            sync,
            notification_settings,
            notification_candidates,
            room_subscriptions: Arc::default(),
            recovery_progress: broadcast::channel(16).0,
            active_calls: Arc::default(),
            tasks: Mutex::default(),
            runtime: Handle::current(),
        };
        session.spawn(pins::keep_room_subscriptions(
            session.sync.room_list_service(),
            session.room_subscriptions.clone(),
        ));
        Ok(session)
    }

    /// What the app stores to [`restore`] this session later.
    ///
    /// # Errors
    ///
    /// [`CoreError::SessionExpired`] if the session has been logged out.
    #[frb(sync)]
    pub fn session_data(&self) -> Result<SessionData, CoreError> {
        let session = self
            .client
            .matrix_auth()
            .session()
            .ok_or(CoreError::SessionExpired)?;
        Ok(SessionData {
            homeserver_url: self.client.homeserver().to_string(),
            user_id: session.meta.user_id.to_string(),
            device_id: session.meta.device_id.to_string(),
            access_token: session.tokens.access_token,
        })
    }

    /// Stops syncing and logs this device out on the server. The store stays; the app deletes
    /// it.
    ///
    /// # Errors
    ///
    /// As the server answers.
    pub async fn logout(&self) -> Result<(), CoreError> {
        self.sync.stop().await;
        Ok(self.client.logout().await?)
    }

    /// The logged-in user's Matrix ID.
    #[frb(sync)]
    #[must_use]
    pub fn user_id(&self) -> String {
        self.client
            .user_id()
            .map(ToString::to_string)
            .unwrap_or_default()
    }

    /// Sends every [`SessionChange`].
    #[allow(
        clippy::unused_async,
        reason = "async so flutter_rust_bridge runs it on its tokio runtime, which spawn needs"
    )]
    pub async fn subscribe_session_changes(&self, sink: StreamSink<SessionChange>) {
        let mut changes = self.session_changes();
        self.spawn(async move {
            while let Some(change) = changes.next().await {
                if sink.add(change).is_err() {
                    break;
                }
            }
        });
    }

    /// Every [`SessionChange`], for Rust callers.
    #[frb(ignore)]
    pub fn session_changes(&self) -> impl Stream<Item = SessionChange> + Send + Unpin + 'static {
        let receiver = self.client.subscribe_to_session_changes();
        // A lagging receiver only skips changes; it never ends the stream.
        Box::pin(futures_util::stream::unfold(
            receiver,
            |mut receiver| async move {
                loop {
                    match receiver.recv().await {
                        Ok(change) => return Some((session_change(&change), receiver)),
                        Err(broadcast::error::RecvError::Lagged(_)) => {}
                        Err(broadcast::error::RecvError::Closed) => return None,
                    }
                }
            },
        ))
    }

    /// The SDK client, for Rust callers (the tests set up what the app doesn't do yet).
    #[frb(ignore)]
    #[must_use]
    pub fn sdk(&self) -> &Client {
        &self.client
    }

    /// Runs `future` until the session is dropped.
    pub(crate) fn spawn(&self, future: impl Future<Output = ()> + Send + 'static) {
        let handle = tokio::spawn(future).abort_handle();
        let mut tasks = self.tasks.lock().unwrap_or_else(PoisonError::into_inner);
        tasks.retain(|task| !task.is_finished());
        tasks.push(handle);
    }
}

impl fmt::Debug for Session {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("Session")
            .field("user_id", &self.client.user_id())
            .finish_non_exhaustive()
    }
}

/// How long the dropped session's client is kept, so that it outlives the session's fields.
const CLOSE_DELAY: Duration = Duration::from_secs(1);

impl Drop for Session {
    fn drop(&mut self) {
        let tasks = self.tasks.get_mut().unwrap_or_else(PoisonError::into_inner);
        for task in tasks.drain(..) {
            task.abort();
        }
        // The app drops sessions from a thread without a Tokio runtime, but the SDK's stores
        // need one to close (their connection pool spawns blocking tasks). A copy of the
        // client, held a moment on the session's runtime, is the last to go, so the stores
        // close there.
        let client = self.client.clone();
        self.runtime.spawn(async move {
            tokio::time::sleep(CLOSE_DELAY).await;
            drop(client);
        });
    }
}

fn session_change(change: &matrix_sdk::SessionChange) -> SessionChange {
    match change {
        matrix_sdk::SessionChange::UnknownToken(data) => SessionChange::UnknownToken {
            soft_logout: data.soft_logout,
        },
        matrix_sdk::SessionChange::TokensRefreshed => SessionChange::TokensRefreshed,
    }
}
