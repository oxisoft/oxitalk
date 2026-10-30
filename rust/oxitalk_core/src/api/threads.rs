//! A room's threads, most recent first, for the thread list: each with its first message, its
//! latest reply and how many replies it has. Kept up to date as replies arrive.

use std::sync::{Arc, Mutex, PoisonError};

use flutter_rust_bridge::frb;
use futures_util::StreamExt;
use matrix_sdk::{
    Client, Room,
    cross_process_lock::MappedCrossProcessLockState,
    linked_chunk::{ChunkIdentifier, LinkedChunkId, Update},
    ruma::{EventId, RoomId, events::room::encrypted::OriginalSyncRoomEncryptedEvent},
};
use matrix_sdk_ui::timeline::{
    RoomExt,
    thread_list_service::{ThreadListItem, ThreadListItemEvent, ThreadListPaginationState},
};
use tokio::task::AbortHandle;

use super::{
    error::CoreError,
    session::Session,
    timeline::{ThreadEvent, thread_event},
};
use crate::frb_generated::StreamSink;

/// The threads of a room. Dropping it stops its stream.
#[frb(opaque)]
pub struct ThreadList {
    inner: Arc<matrix_sdk_ui::timeline::ThreadListService>,
    tasks: Mutex<Vec<AbortHandle>>,
}

impl std::fmt::Debug for ThreadList {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("ThreadList").finish_non_exhaustive()
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ThreadSummary {
    /// The event ID of the thread's first message, which opens it.
    pub root_event_id: String,
    pub root: ThreadEvent,
    pub latest: Option<ThreadEvent>,
    pub reply_count: u32,
}

impl Session {
    /// The threads of a room the user is in. Nothing is loaded until
    /// [`ThreadList::paginate`].
    ///
    /// # Errors
    ///
    /// [`CoreError::InvalidId`] or [`CoreError::RoomNotFound`].
    #[allow(
        clippy::unused_async,
        clippy::unused_async_trait_impl,
        reason = "async so flutter_rust_bridge runs it on its tokio runtime, which the service needs"
    )]
    pub async fn thread_list(&self, room_id: String) -> Result<ThreadList, CoreError> {
        let room = self.room(&room_id)?;
        Ok(ThreadList {
            inner: Arc::new(room.thread_list_service()),
            tasks: Mutex::default(),
        })
    }
}

impl ThreadList {
    /// Sends the whole list now and after every change.
    pub async fn subscribe(&self, sink: StreamSink<Vec<ThreadSummary>>) {
        self.updates(move |threads| sink.add(threads).is_ok()).await;
    }

    /// Like [`Self::subscribe`], for Rust callers: `emit` gets each list and returns `false` to
    /// stop.
    #[frb(ignore)]
    #[allow(
        clippy::unused_async,
        reason = "async so flutter_rust_bridge runs it on its tokio runtime, which spawn needs"
    )]
    pub async fn updates(&self, emit: impl Fn(Vec<ThreadSummary>) -> bool + Send + 'static) {
        let (_, mut stream) = self.inner.subscribe_to_items_updates();
        let inner = self.inner.clone();
        let handle = tokio::spawn(async move {
            if !emit(summaries(&inner.items())) {
                return;
            }
            // The diffs only say that something changed; the whole list is small.
            while stream.next().await.is_some() {
                if !emit(summaries(&inner.items())) {
                    break;
                }
            }
        })
        .abort_handle();
        let mut tasks = self.tasks.lock().unwrap_or_else(PoisonError::into_inner);
        tasks.retain(|task| !task.is_finished());
        tasks.push(handle);
    }

    /// Loads the next, older page of threads. Returns `true` once there are no more.
    ///
    /// # Errors
    ///
    /// As the server answers.
    pub async fn paginate(&self) -> Result<bool, CoreError> {
        self.inner
            .paginate()
            .await
            .map_err(|error| CoreError::internal(&error))?;
        Ok(matches!(
            self.inner.pagination_state(),
            ThreadListPaginationState::Idle { end_reached: true }
        ))
    }
}

impl Drop for ThreadList {
    fn drop(&mut self) {
        let tasks = self.tasks.get_mut().unwrap_or_else(PoisonError::into_inner);
        for task in tasks.drain(..) {
            task.abort();
        }
    }
}

/// Writes the first, empty chunk of a thread's cached events to the store if the store has
/// none, before the thread's cache is built from it.
///
/// Works around matrix-rust-sdk (a39665d): a thread cache built from an empty store creates its
/// first chunk only in memory, to be written with its first events. Until then, the
/// redecryptor resolving any late-decrypted event of the room drops the pending write
/// (`ThreadEventCache::replace_in_memory_utds`, event_cache/caches/thread/mod.rs:368-377, drains
/// the store updates whether or not it replaced anything). Its events then go to a chunk the
/// store doesn't have: the thread's back-pagination fails (`FOREIGN KEY constraint failed`) and
/// the thread stayed empty, and a new reply in it failed the sync. In an encrypted room this is
/// the usual case after a restart, as the automatic back-pagination loads older events before
/// their keys arrive. A cache built from a stored chunk has nothing pending, so nothing is lost.
/// Test: homeserver `a_thread_answered_while_the_app_was_closed_shows_its_replies`.
pub(crate) async fn persist_thread_head(
    client: &Client,
    room_id: &RoomId,
    thread_id: &EventId,
) -> Result<(), CoreError> {
    let store = match client
        .event_cache_store()
        .lock()
        .await
        .map_err(|error| CoreError::internal(&error))?
    {
        MappedCrossProcessLockState::Clean(store) | MappedCrossProcessLockState::Dirty(store) => {
            store
        }
    };
    let chunks = LinkedChunkId::Thread(room_id, thread_id);
    let (last, _) = store
        .load_last_chunk(chunks)
        .await
        .map_err(|error| CoreError::internal(&error))?;
    if last.is_none() {
        store
            .handle_linked_chunk_updates(
                chunks,
                vec![Update::NewItemsChunk {
                    previous: None,
                    new: ChunkIdentifier::new(0),
                    next: None,
                }],
            )
            .await
            .map_err(|error| CoreError::internal(&error))?;
    }
    Ok(())
}

/// Puts the decrypted copy of a thread's latest reply back in the store, if the SDK has just
/// saved an "unable to decrypt" copy over it.
///
/// Works around matrix-rust-sdk (a39665d): when the thread's back-pagination reaches its first
/// message, the thread cache saves that message's bundled latest reply to the store
/// (`post_process_upserted_events`, event_cache/caches/thread/state.rs:483-489), over the
/// decrypted copy it has just stored. It takes the first message from the room's cache, as the
/// room's (automatic) back-pagination loaded it: if the reply's key came after that, its bundled
/// copy says "unable to decrypt, missing key", which the SDK doesn't try again
/// (`redecryptor::try_decrypt_in_place` only tries copies it never tried), and the redecryptor
/// doesn't either, as the room's cache has the reply decrypted. The open thread keeps its
/// decrypted copy in memory; once it is closed the SDK reloads the thread from the store, so
/// the thread opened again showed its latest reply as "unable to decrypt". Called after each
/// back-pagination of a thread.
/// Test: homeserver `a_thread_opened_again_still_shows_its_replies`.
pub(crate) async fn restore_latest_reply(
    room: &Room,
    thread_id: &EventId,
) -> Result<(), CoreError> {
    let client = room.client();
    let Some(event_cache) = client.event_cache() else {
        return Ok(());
    };
    let (room_cache, _handles) = event_cache
        .room(room.room_id())
        .await
        .map_err(|error| CoreError::internal(&error))?;
    let Some(latest) = room_cache
        .find_event(thread_id)
        .await
        .map_err(|error| CoreError::internal(&error))?
        .and_then(|root| root.bundled_latest_thread_event())
        .filter(|latest| latest.kind.is_utd())
    else {
        return Ok(());
    };
    let decrypted = room
        .decrypt_event(
            latest
                .raw()
                .cast_ref_unchecked::<OriginalSyncRoomEncryptedEvent>(),
            None,
        )
        .await
        .map_err(|error| CoreError::internal(&error))?;
    // Without the key the reply itself is undecryptable too; the SDK decrypts both when it comes.
    if decrypted.kind.is_utd() {
        return Ok(());
    }
    let store = match client
        .event_cache_store()
        .lock()
        .await
        .map_err(|error| CoreError::internal(&error))?
    {
        MappedCrossProcessLockState::Clean(store) | MappedCrossProcessLockState::Dirty(store) => {
            store
        }
    };
    store
        .save_event(room.room_id(), decrypted)
        .await
        .map_err(|error| CoreError::internal(&error))
}

fn summaries(items: &[ThreadListItem]) -> Vec<ThreadSummary> {
    items
        .iter()
        .map(|item| ThreadSummary {
            root_event_id: item.root_event.event_id.to_string(),
            root: list_event(&item.root_event),
            latest: item.latest_event.as_ref().map(list_event),
            reply_count: item.num_replies,
        })
        .collect()
}

fn list_event(event: &ThreadListItemEvent) -> ThreadEvent {
    thread_event(
        &event.sender,
        &event.sender_profile,
        event.content.as_ref(),
        event.timestamp.0.into(),
    )
}
