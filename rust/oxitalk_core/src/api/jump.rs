//! A room's timeline around one event, to jump to an old message (a pinned one, or a search
//! hit) without loading everything after it.

use matrix_sdk::ruma::OwnedEventId;
use matrix_sdk_ui::timeline::{TimelineEventFocusThreadMode, TimelineFocus};

use super::{
    error::{CoreError, parse_id},
    session::Session,
    timeline::Timeline,
};

/// How many events around the target an event timeline loads at first.
const CONTEXT_EVENTS: u16 = 30;

impl Session {
    /// Opens the room's timeline around the event `event_id`: the event with some before and
    /// after it, from the server. It pages back with [`Timeline::paginate_back`] and forward,
    /// towards the newest message, with [`Timeline::paginate_forward`]. As in the live
    /// timeline, thread replies stay in their threads.
    ///
    /// # Errors
    ///
    /// [`CoreError::InvalidId`], [`CoreError::RoomNotFound`], or if the event can't be loaded.
    pub async fn event_timeline(
        &self,
        room_id: String,
        event_id: String,
    ) -> Result<Timeline, CoreError> {
        let target: OwnedEventId = parse_id(&event_id)?;
        self.focused_timeline(
            room_id,
            TimelineFocus::Event {
                target,
                num_context_events: CONTEXT_EVENTS,
                thread_mode: TimelineEventFocusThreadMode::Automatic {
                    hide_threaded_events: true,
                },
            },
        )
        .await
    }
}

impl Timeline {
    /// Loads up to `count` newer events into a timeline around an event. Returns `true` once
    /// the newest event is reached; always `true` for a live timeline.
    ///
    /// # Errors
    ///
    /// As the server answers.
    pub async fn paginate_forward(&self, count: u16) -> Result<bool, CoreError> {
        Ok(self.inner().paginate_forwards(count).await?)
    }
}
