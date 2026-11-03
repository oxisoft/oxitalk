//! A room's timeline around one event, to jump to an old message (a pinned one, a search
//! hit, or the first message of a day) without loading everything after it.

use matrix_sdk::{
    HttpError,
    deserialized_responses::{RawSyncOrStrippedState, TimelineEvent},
    room::MessagesOptions,
    ruma::{
        MilliSecondsSinceUnixEpoch, OwnedEventId, OwnedRoomId, UInt,
        api::{client::room::get_event_by_timestamp, error::ErrorKind},
        events::room::create::RoomCreateEventContent,
    },
};
use matrix_sdk_ui::timeline::{TimelineEventFocusThreadMode, TimelineFocus};
use serde_json::Value;

use super::{
    error::{CoreError, parse_id},
    session::Session,
    timeline::Timeline,
};

/// How many events around the target an event timeline loads at first.
const CONTEXT_EVENTS: u16 = 30;

/// How many events after the server's answer [`Session::first_message_since`] reads at once,
/// and how many such pages at most, to get past reactions, edits and thread replies.
const SCAN_EVENTS: u16 = 50;
const SCAN_PAGES: usize = 10;

/// The first message of a room at or after a time, as [`Session::first_message_since`] finds
/// it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum MessageSince {
    /// The first message the room's timeline shows at or after the time.
    Found { event_id: String, timestamp_ms: i64 },
    /// No message since then; the newest end of the room is the place.
    NoneAfter,
    /// The server can't look events up by time (no `timestamp_to_event`, MSC3030).
    Unsupported,
}

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

    /// Finds the room's first message at or after `timestamp_ms` (milliseconds since the Unix
    /// epoch), e.g. the first of a day, to jump there with [`Self::event_timeline`]. Asks the
    /// server's `timestamp_to_event` (MSC3030, Matrix 1.6) for the first event since then,
    /// and from there reads on to the first one the chat shows: reactions, edits, thread
    /// replies, redactions and state changes are skipped.
    ///
    /// # Errors
    ///
    /// [`CoreError::InvalidId`], [`CoreError::RoomNotFound`], or as the server answers.
    pub async fn first_message_since(
        &self,
        room_id: String,
        timestamp_ms: i64,
    ) -> Result<MessageSince, CoreError> {
        let id: OwnedRoomId = parse_id(&room_id)?;
        let room = self
            .client
            .get_room(&id)
            .ok_or(CoreError::RoomNotFound { room_id })?;
        let ts =
            MilliSecondsSinceUnixEpoch(UInt::try_from(timestamp_ms.max(0)).unwrap_or(UInt::MAX));
        let request = get_event_by_timestamp::v1::Request::since(id, ts);
        let found = match self.client.send(request).await {
            Ok(found) => found,
            Err(error) => {
                return match since_failure(&error) {
                    Some(answer) => Ok(answer),
                    None => Err(error.into()),
                };
            }
        };
        let context = room
            .event_with_context(&found.event_id, false, UInt::from(SCAN_EVENTS), None)
            .await?;
        if let Some(found) = first_shown(context.event.iter().chain(&context.events_after)) {
            return Ok(found);
        }
        let mut token = context.next_batch_token;
        for _ in 0..SCAN_PAGES {
            let Some(from) = token else { break };
            let mut options = MessagesOptions::forward().from(from.as_str());
            options.limit = UInt::from(SCAN_EVENTS);
            let page = room.messages(options).await?;
            if let Some(found) = first_shown(&page.chunk) {
                return Ok(found);
            }
            if page.chunk.is_empty() {
                break;
            }
            token = page.end;
        }
        Ok(MessageSince::NoneAfter)
    }

    /// When the room was created (its `m.room.create` event), in milliseconds since the Unix
    /// epoch, if this device has that event: the first day there can be messages.
    ///
    /// # Errors
    ///
    /// [`CoreError::InvalidId`], [`CoreError::RoomNotFound`], or if the store can't be read.
    pub async fn room_created_ms(&self, room_id: String) -> Result<Option<i64>, CoreError> {
        let id: OwnedRoomId = parse_id(&room_id)?;
        let room = self
            .client
            .get_room(&id)
            .ok_or(CoreError::RoomNotFound { room_id })?;
        Ok(
            match room
                .get_state_event_static::<RoomCreateEventContent>()
                .await?
            {
                Some(RawSyncOrStrippedState::Sync(raw)) => {
                    raw.get_field::<i64>("origin_server_ts").ok().flatten()
                }
                _ => None,
            },
        )
    }
}

/// What a failed `timestamp_to_event` means, if it is an answer rather than an error:
/// `M_NOT_FOUND` is no event since then; an endpoint the server doesn't know (or the client
/// can't build for its versions) is [`MessageSince::Unsupported`].
fn since_failure(error: &HttpError) -> Option<MessageSince> {
    if matches!(error, HttpError::IntoHttp(_)) {
        return Some(MessageSince::Unsupported);
    }
    match error.client_api_error_kind() {
        Some(ErrorKind::NotFound) => Some(MessageSince::NoneAfter),
        Some(ErrorKind::Unrecognized) => Some(MessageSince::Unsupported),
        Some(_) => None,
        None => error
            .as_client_api_error()
            .filter(|e| matches!(e.status_code.as_u16(), 404 | 405 | 501))
            .map(|_| MessageSince::Unsupported),
    }
}

/// The first of `events` the chat shows as a message.
fn first_shown<'a>(events: impl IntoIterator<Item = &'a TimelineEvent>) -> Option<MessageSince> {
    events.into_iter().find_map(|event| {
        let json: Value = serde_json::from_str(event.raw().json().get()).ok()?;
        if !is_shown_message(&json) {
            return None;
        }
        Some(MessageSince::Found {
            event_id: json.get("event_id")?.as_str()?.to_owned(),
            timestamp_ms: json.get("origin_server_ts")?.as_i64()?,
        })
    })
}

/// Whether the event (as JSON) shows in a chat's timeline as a message of its own: a message,
/// sticker, poll or encrypted event, but not one that edits, reacts to or replies in the
/// thread of another, nor a state event.
fn is_shown_message(event: &Value) -> bool {
    if event.get("state_key").is_some() {
        return false;
    }
    let shown_type = matches!(
        event.get("type").and_then(Value::as_str),
        Some(
            "m.room.message"
                | "m.room.encrypted"
                | "m.sticker"
                | "m.poll.start"
                | "org.matrix.msc3381.poll.start"
        )
    );
    let relation = event
        .pointer("/content/m.relates_to/rel_type")
        .and_then(Value::as_str);
    shown_type && !matches!(relation, Some("m.replace" | "m.annotation" | "m.thread"))
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

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::is_shown_message;

    #[test]
    fn messages_show_but_edits_reactions_thread_replies_and_state_do_not() {
        let text = json!({"type": "m.room.message", "content": {"body": "hi"}});
        let reply = json!({"type": "m.room.message", "content": {
            "body": "re", "m.relates_to": {"m.in_reply_to": {"event_id": "$a"}}}});
        let encrypted = json!({"type": "m.room.encrypted", "content": {}});
        let edit = json!({"type": "m.room.message", "content": {
            "m.relates_to": {"rel_type": "m.replace", "event_id": "$a"}}});
        let reaction = json!({"type": "m.reaction", "content": {
            "m.relates_to": {"rel_type": "m.annotation", "event_id": "$a", "key": "👍"}}});
        let in_thread = json!({"type": "m.room.encrypted", "content": {
            "m.relates_to": {"rel_type": "m.thread", "event_id": "$a"}}});
        let member = json!({"type": "m.room.member", "state_key": "@a:b", "content": {}});
        assert!(is_shown_message(&text));
        assert!(is_shown_message(&reply));
        assert!(is_shown_message(&encrypted));
        assert!(!is_shown_message(&edit));
        assert!(!is_shown_message(&reaction));
        assert!(!is_shown_message(&in_thread));
        assert!(!is_shown_message(&member));
    }
}
