//! Who is typing in which room, and telling the room when the user types.

use flutter_rust_bridge::frb;
use futures_util::{Stream, StreamExt};
use matrix_sdk::{Room, ruma::events::typing::SyncTypingEvent};

use super::{error::CoreError, session::Session, timeline::Timeline};
use crate::frb_generated::StreamSink;

/// The people typing in a room right now, the user left out; empty when nobody is.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RoomTyping {
    pub room_id: String,
    /// Their display names, or user IDs where they have none.
    pub names: Vec<String>,
}

impl Session {
    /// Sends who is typing, for every room, whenever it changes.
    #[allow(
        clippy::unused_async,
        reason = "async so flutter_rust_bridge runs it on its tokio runtime, which spawn needs"
    )]
    pub async fn subscribe_typing(&self, sink: StreamSink<RoomTyping>) {
        let mut typing = self.typing_updates();
        self.spawn(async move {
            while let Some(update) = typing.next().await {
                if sink.add(update).is_err() {
                    break;
                }
            }
        });
    }

    /// Like [`Self::subscribe_typing`], for Rust callers.
    #[frb(ignore)]
    pub fn typing_updates(&self) -> impl Stream<Item = RoomTyping> + Send + Unpin + 'static {
        // The subscriber only holds the handler weakly; the stream keeps it.
        let handler = self.client.observe_events::<SyncTypingEvent, Room>();
        let events = handler.subscribe();
        Box::pin(
            events
                .then(move |(event, room)| {
                    let _keep = &handler;
                    async move { room_typing(&room, &event).await }
                })
                .boxed(),
        )
    }
}

async fn room_typing(room: &Room, event: &SyncTypingEvent) -> RoomTyping {
    let mut names = Vec::new();
    for user in &event.content.user_ids {
        if user == room.own_user_id() {
            continue;
        }
        let name = match room.get_member_no_sync(user).await {
            Ok(Some(member)) => member.display_name().map(ToOwned::to_owned),
            _ => None,
        };
        names.push(name.unwrap_or_else(|| user.to_string()));
    }
    RoomTyping {
        room_id: room.room_id().to_string(),
        names,
    }
}

impl Timeline {
    /// Tells the room whether the user is typing. Calls come as often as keys are pressed;
    /// the SDK sends a notice only when it changes or the last one is about to run out.
    ///
    /// # Errors
    ///
    /// As the server answers; [`CoreError::Internal`] if the user isn't in the room.
    pub async fn set_typing(&self, typing: bool) -> Result<(), CoreError> {
        Ok(self.room().typing_notice(typing).await?)
    }
}
