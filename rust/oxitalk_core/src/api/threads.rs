//! A room's threads, most recent first, for the thread list: each with its first message, its
//! latest reply and how many replies it has. Kept up to date as replies arrive.

use std::sync::{Arc, Mutex, PoisonError};

use flutter_rust_bridge::frb;
use futures_util::StreamExt;
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
