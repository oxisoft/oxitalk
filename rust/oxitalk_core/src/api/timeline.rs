//! A room's timeline: its events oldest first, delivered as batches of diffs, plus paging back
//! and sending.

use std::sync::{Arc, Mutex, PoisonError};

use flutter_rust_bridge::frb;
use futures_util::StreamExt;
use matrix_sdk::ruma::{OwnedRoomId, events::room::message::RoomMessageEventContent};
use matrix_sdk_ui::{
    eyeball_im::VectorDiff,
    timeline::{
        self, EventSendState, EventTimelineItem, RoomExt, TimelineDetails, TimelineItemKind,
        VirtualTimelineItem,
    },
};
use tokio::task::AbortHandle;

use super::{
    error::{CoreError, parse_id},
    session::Session,
};
use crate::frb_generated::StreamSink;

/// An open room timeline. Dropping it stops its stream.
#[frb(opaque)]
#[derive(Debug)]
pub struct Timeline {
    inner: Arc<timeline::Timeline>,
    tasks: Mutex<Vec<AbortHandle>>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TimelineItem {
    /// Stable for the item's life in this timeline, also across a local echo turning into the
    /// sent event.
    pub id: String,
    pub content: TimelineItemContent,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TimelineItemContent {
    /// A text message (for other message types, their fallback body).
    Message { event: EventInfo, body: String },
    /// An encrypted event whose key hasn't arrived (yet).
    UnableToDecrypt { event: EventInfo },
    /// Any other event; M0 doesn't show them.
    OtherEvent { event: EventInfo },
    /// The start of a day, in milliseconds since the Unix epoch.
    DateDivider { timestamp_ms: i64 },
    /// Where the user stopped reading.
    ReadMarker,
    /// Nothing older exists.
    TimelineStart,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EventInfo {
    /// `None` until the server has accepted a local echo.
    pub event_id: Option<String>,
    pub sender: String,
    pub sender_name: Option<String>,
    pub timestamp_ms: i64,
    pub is_own: bool,
    pub send_state: SendState,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SendState {
    Sending,
    Sent,
    Failed,
}

/// One change to the timeline. Indexes refer to the list as it is when the diff is applied;
/// the diffs in a batch are applied in order.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TimelineDiff {
    Append { values: Vec<TimelineItem> },
    Clear,
    PushFront { value: TimelineItem },
    PushBack { value: TimelineItem },
    PopFront,
    PopBack,
    Insert { index: u32, value: TimelineItem },
    Set { index: u32, value: TimelineItem },
    Remove { index: u32 },
    Truncate { length: u32 },
    Reset { values: Vec<TimelineItem> },
}

impl Session {
    /// Opens the timeline of a room the user is in.
    ///
    /// # Errors
    ///
    /// [`CoreError::InvalidId`], or [`CoreError::RoomNotFound`] for a room the session doesn't
    /// know.
    pub async fn timeline(&self, room_id: String) -> Result<Timeline, CoreError> {
        let id: OwnedRoomId = parse_id(&room_id)?;
        let room = self
            .client
            .get_room(&id)
            .ok_or(CoreError::RoomNotFound { room_id })?;
        Ok(Timeline {
            inner: Arc::new(room.timeline().await?),
            tasks: Mutex::default(),
        })
    }
}

impl Timeline {
    /// Sends the items as batches of diffs. The first batch is a `Reset` with every item
    /// loaded so far.
    pub async fn subscribe_items(&self, sink: StreamSink<Vec<TimelineDiff>>) {
        self.item_updates(move |batch| sink.add(batch).is_ok())
            .await;
    }

    /// Like [`Self::subscribe_items`], for Rust callers: `emit` gets each batch and returns
    /// `false` to stop.
    #[frb(ignore)]
    pub async fn item_updates(&self, emit: impl Fn(Vec<TimelineDiff>) -> bool + Send + 'static) {
        let (items, stream) = self.inner.subscribe().await;
        let first = vec![TimelineDiff::Reset {
            values: items.iter().map(|i| item(i)).collect(),
        }];
        let handle = tokio::spawn(async move {
            if !emit(first) {
                return;
            }
            let mut stream = Box::pin(stream);
            while let Some(diffs) = stream.next().await {
                if !emit(diffs.into_iter().map(timeline_diff).collect()) {
                    break;
                }
            }
        })
        .abort_handle();
        let mut tasks = self.tasks.lock().unwrap_or_else(PoisonError::into_inner);
        tasks.retain(|task| !task.is_finished());
        tasks.push(handle);
    }

    /// Loads up to `count` older events. Returns `true` once the start of the room is reached.
    ///
    /// # Errors
    ///
    /// As the server answers.
    pub async fn paginate_back(&self, count: u16) -> Result<bool, CoreError> {
        Ok(self.inner.paginate_backwards(count).await?)
    }

    /// Queues a plain-text message. It shows at once as a local echo in [`SendState::Sending`];
    /// the room is encrypted transparently if it is an encrypted room.
    ///
    /// # Errors
    ///
    /// Only if the message can't be queued; a failed send shows as [`SendState::Failed`].
    pub async fn send_text(&self, body: String) -> Result<(), CoreError> {
        self.inner
            .send(RoomMessageEventContent::text_plain(body).into())
            .await?;
        Ok(())
    }
}

impl Drop for Timeline {
    fn drop(&mut self) {
        let tasks = self.tasks.get_mut().unwrap_or_else(PoisonError::into_inner);
        for task in tasks.drain(..) {
            task.abort();
        }
    }
}

fn timeline_diff(diff: VectorDiff<Arc<timeline::TimelineItem>>) -> TimelineDiff {
    let items = |values: matrix_sdk_ui::eyeball_im::Vector<Arc<timeline::TimelineItem>>| {
        values.iter().map(|i| item(i)).collect()
    };
    match diff {
        VectorDiff::Append { values } => TimelineDiff::Append {
            values: items(values),
        },
        VectorDiff::Clear => TimelineDiff::Clear,
        VectorDiff::PushFront { value } => TimelineDiff::PushFront {
            value: item(&value),
        },
        VectorDiff::PushBack { value } => TimelineDiff::PushBack {
            value: item(&value),
        },
        VectorDiff::PopFront => TimelineDiff::PopFront,
        VectorDiff::PopBack => TimelineDiff::PopBack,
        VectorDiff::Insert { index, value } => TimelineDiff::Insert {
            index: dart_int(index),
            value: item(&value),
        },
        VectorDiff::Set { index, value } => TimelineDiff::Set {
            index: dart_int(index),
            value: item(&value),
        },
        VectorDiff::Remove { index } => TimelineDiff::Remove {
            index: dart_int(index),
        },
        VectorDiff::Truncate { length } => TimelineDiff::Truncate {
            length: dart_int(length),
        },
        VectorDiff::Reset { values } => TimelineDiff::Reset {
            values: items(values),
        },
    }
}

/// A list index or length as a `u32`, which Dart gets as an `int` (a `usize` would be a
/// `BigInt`). No list comes near `u32::MAX`.
pub(crate) fn dart_int(value: usize) -> u32 {
    u32::try_from(value).unwrap_or(u32::MAX)
}

fn item(item: &timeline::TimelineItem) -> TimelineItem {
    let content = match item.kind() {
        TimelineItemKind::Event(event) => event_content(event),
        TimelineItemKind::Virtual(VirtualTimelineItem::DateDivider(timestamp)) => {
            TimelineItemContent::DateDivider {
                timestamp_ms: timestamp.0.into(),
            }
        }
        TimelineItemKind::Virtual(VirtualTimelineItem::ReadMarker) => {
            TimelineItemContent::ReadMarker
        }
        TimelineItemKind::Virtual(VirtualTimelineItem::TimelineStart) => {
            TimelineItemContent::TimelineStart
        }
    };
    TimelineItem {
        id: item.unique_id().0.clone(),
        content,
    }
}

fn event_content(event: &EventTimelineItem) -> TimelineItemContent {
    let info = EventInfo {
        event_id: event.event_id().map(ToString::to_string),
        sender: event.sender().to_string(),
        sender_name: match event.sender_profile() {
            TimelineDetails::Ready(profile) => profile.display_name.clone(),
            _ => None,
        },
        timestamp_ms: event.timestamp().0.into(),
        is_own: event.is_own(),
        send_state: match event.send_state() {
            Some(EventSendState::NotSentYet { .. }) => SendState::Sending,
            Some(EventSendState::SendingFailed { .. }) => SendState::Failed,
            Some(EventSendState::Sent { .. }) | None => SendState::Sent,
        },
    };
    let content = event.content();
    if let Some(message) = content.as_message() {
        TimelineItemContent::Message {
            event: info,
            body: message.body().to_owned(),
        }
    } else if content.is_unable_to_decrypt() {
        TimelineItemContent::UnableToDecrypt { event: info }
    } else {
        TimelineItemContent::OtherEvent { event: info }
    }
}
