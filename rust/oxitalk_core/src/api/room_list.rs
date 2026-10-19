//! The room list: every room the user is in or invited to, newest activity first, delivered as
//! batches of diffs against the list the app holds.

use flutter_rust_bridge::frb;
use futures_util::{StreamExt, future::join_all};
use matrix_sdk::RoomState;
use matrix_sdk_ui::{
    eyeball_im::VectorDiff,
    room_list_service::{RoomListItem, filters::new_filter_non_left},
    timeline::{LatestEventValue, RoomExt},
};

use super::{error::CoreError, session::Session, timeline::dart_int};
use crate::frb_generated::StreamSink;

/// How many rooms the list holds. M0 has no paging; this is far above any real account.
const ROOM_LIST_LIMIT: usize = 10_000;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RoomSummary {
    pub room_id: String,
    /// The display name, computed by the SDK from the room's name, alias or members.
    pub name: String,
    pub membership: Membership,
    /// The body of the latest message, if the latest event is a text message.
    pub last_message: Option<String>,
    /// When the latest event happened, in milliseconds since the Unix epoch.
    pub last_activity_ms: Option<i64>,
    pub unread_count: u32,
    pub is_dm: bool,
    pub is_encrypted: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Membership {
    Joined,
    Invited,
    Knocked,
    Left,
    Banned,
}

/// One change to the room list. Indexes refer to the list as it is when the diff is applied;
/// the diffs in a batch are applied in order.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RoomListDiff {
    Append { values: Vec<RoomSummary> },
    Clear,
    PushFront { value: RoomSummary },
    PushBack { value: RoomSummary },
    PopFront,
    PopBack,
    Insert { index: u32, value: RoomSummary },
    Set { index: u32, value: RoomSummary },
    Remove { index: u32 },
    Truncate { length: u32 },
    Reset { values: Vec<RoomSummary> },
}

impl Session {
    /// Sends the room list as batches of diffs. The first batch is a `Reset` with the whole
    /// list.
    ///
    /// # Errors
    ///
    /// If the SDK's room list can't be set up.
    pub async fn subscribe_rooms(
        &self,
        sink: StreamSink<Vec<RoomListDiff>>,
    ) -> Result<(), CoreError> {
        self.room_list_updates(move |batch| sink.add(batch).is_ok())
            .await
    }

    /// Like [`Self::subscribe_rooms`], for Rust callers: `emit` gets each batch and returns
    /// `false` to stop.
    ///
    /// # Errors
    ///
    /// As [`Self::subscribe_rooms`].
    #[frb(ignore)]
    pub async fn room_list_updates(
        &self,
        emit: impl Fn(Vec<RoomListDiff>) -> bool + Send + 'static,
    ) -> Result<(), CoreError> {
        let room_list = self
            .sync
            .room_list_service()
            .all_rooms()
            .await
            .map_err(|error| CoreError::internal(&error))?;
        self.spawn(async move {
            let (stream, controller) = room_list.entries_with_dynamic_adapters(ROOM_LIST_LIMIT);
            controller.set_filter(Box::new(new_filter_non_left()));
            let mut stream = Box::pin(stream);
            while let Some(diffs) = stream.next().await {
                let batch = join_all(diffs.into_iter().map(room_list_diff)).await;
                if !emit(batch) {
                    break;
                }
            }
        });
        Ok(())
    }
}

async fn room_list_diff(diff: VectorDiff<RoomListItem>) -> RoomListDiff {
    match diff {
        VectorDiff::Append { values } => RoomListDiff::Append {
            values: summaries(values).await,
        },
        VectorDiff::Clear => RoomListDiff::Clear,
        VectorDiff::PushFront { value } => RoomListDiff::PushFront {
            value: summary(value).await,
        },
        VectorDiff::PushBack { value } => RoomListDiff::PushBack {
            value: summary(value).await,
        },
        VectorDiff::PopFront => RoomListDiff::PopFront,
        VectorDiff::PopBack => RoomListDiff::PopBack,
        VectorDiff::Insert { index, value } => RoomListDiff::Insert {
            index: dart_int(index),
            value: summary(value).await,
        },
        VectorDiff::Set { index, value } => RoomListDiff::Set {
            index: dart_int(index),
            value: summary(value).await,
        },
        VectorDiff::Remove { index } => RoomListDiff::Remove {
            index: dart_int(index),
        },
        VectorDiff::Truncate { length } => RoomListDiff::Truncate {
            length: dart_int(length),
        },
        VectorDiff::Reset { values } => RoomListDiff::Reset {
            values: summaries(values).await,
        },
    }
}

async fn summaries(rooms: impl IntoIterator<Item = RoomListItem>) -> Vec<RoomSummary> {
    join_all(rooms.into_iter().map(summary)).await
}

async fn summary(room: RoomListItem) -> RoomSummary {
    let room = room.into_inner();
    let (last_message, last_activity_ms) = match RoomExt::latest_event(&room).await {
        LatestEventValue::Remote {
            timestamp, content, ..
        }
        | LatestEventValue::Local {
            timestamp, content, ..
        } => (
            content
                .as_message()
                .map(|message| message.body().to_owned()),
            Some(timestamp.0.into()),
        ),
        LatestEventValue::RemoteInvite { timestamp, .. } => (None, Some(timestamp.0.into())),
        LatestEventValue::None => (None, None),
    };
    RoomSummary {
        room_id: room.room_id().to_string(),
        name: room
            .cached_display_name()
            .map_or_else(|| room.room_id().to_string(), |name| name.to_string()),
        membership: match room.state() {
            RoomState::Joined => Membership::Joined,
            RoomState::Invited => Membership::Invited,
            RoomState::Knocked => Membership::Knocked,
            RoomState::Left => Membership::Left,
            RoomState::Banned => Membership::Banned,
        },
        last_message,
        last_activity_ms,
        unread_count: u32::try_from(room.num_unread_messages()).unwrap_or(u32::MAX),
        // A store read error only loses the DM marker; the room still shows.
        is_dm: room.is_direct().await.unwrap_or(false),
        is_encrypted: room.encryption_state().is_encrypted(),
    }
}
