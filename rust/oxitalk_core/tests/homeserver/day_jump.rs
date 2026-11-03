//! Jumping to a day: the room's first message at or after a time, from the server.

use std::time::Duration;

use matrix_sdk::{
    Room,
    ruma::{OwnedEventId, OwnedRoomId, events::room::message::RoomMessageEventContent},
};
use oxitalk_core::api::{error::CoreError, jump::MessageSince};
use serde_json::json;

use super::{TestResult, event_of, poll_until, watch_timeline};
use crate::pins::public_room_with;

/// When the server got the event.
async fn sent_at(room: &Room, event_id: &OwnedEventId) -> Result<i64, Box<dyn std::error::Error>> {
    let event = room.event(event_id, None).await?;
    Ok(event.timestamp().ok_or("no timestamp")?.get().into())
}

/// Sends a message-like event as JSON; returns its ID and when the server got it. Waits a
/// little first, so no two events share a millisecond.
async fn send(
    room: &Room,
    event_type: &str,
    content: serde_json::Value,
) -> Result<(OwnedEventId, i64), Box<dyn std::error::Error>> {
    tokio::time::sleep(Duration::from_millis(20)).await;
    let id = room.send_raw(event_type, content).await?.response.event_id;
    let at = sent_at(room, &id).await?;
    Ok((id, at))
}

/// The first message since a time is the first one the chat shows: reactions, thread
/// replies, edits and the room's state events are passed over; after the newest event there
/// is none; and the room opens around what was found.
#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a test homeserver (test-infra/)"]
async fn the_first_message_of_a_day_skips_what_the_chat_does_not_show() -> TestResult {
    let (alice, bob, room_id, ids, _stores) = public_room_with(&["morning".to_owned()]).await?;
    let id: OwnedRoomId = room_id.as_str().try_into()?;
    let room = poll_until("Alice has the room", || async {
        Ok::<_, CoreError>(alice.sdk().get_room(&id))
    })
    .await?;
    let morning: OwnedEventId = ids[0].as_str().try_into()?;
    let morning_at = sent_at(&room, &morning).await?;

    let (_, reaction_at) = send(
        &room,
        "m.reaction",
        json!({"m.relates_to": {"rel_type": "m.annotation", "event_id": morning, "key": "👍"}}),
    )
    .await?;
    send(
        &room,
        "m.room.message",
        json!({"msgtype": "m.text", "body": "in a thread",
            "m.relates_to": {"rel_type": "m.thread", "event_id": morning}}),
    )
    .await?;
    send(
        &room,
        "m.room.message",
        json!({"msgtype": "m.text", "body": "* morning!",
            "m.new_content": {"msgtype": "m.text", "body": "morning!"},
            "m.relates_to": {"rel_type": "m.replace", "event_id": morning}}),
    )
    .await?;
    tokio::time::sleep(Duration::from_millis(20)).await;
    let noon = room
        .send(RoomMessageEventContent::text_plain("noon"))
        .await?
        .response
        .event_id;
    let noon_at = sent_at(&room, &noon).await?;

    // The calendar starts on the day the room was made, before its first message.
    let created = poll_until("Bob knows when the room was made", || async {
        bob.room_created_ms(room_id.clone()).await
    })
    .await?;
    assert!(
        created > 0 && created <= morning_at,
        "{created} vs {morning_at}"
    );

    // Bob asks, as the app does for a day picked in the calendar.
    assert_eq!(
        bob.first_message_since(room_id.clone(), morning_at).await?,
        MessageSince::Found {
            event_id: morning.to_string(),
            timestamp_ms: morning_at,
        },
    );
    assert_eq!(
        bob.first_message_since(room_id.clone(), reaction_at)
            .await?,
        MessageSince::Found {
            event_id: noon.to_string(),
            timestamp_ms: noon_at,
        },
        "the reaction, the thread reply and the edit are not messages of the chat",
    );
    // From the start of time: the room's creation and other state come first.
    assert_eq!(
        bob.first_message_since(room_id.clone(), 0).await?,
        MessageSince::Found {
            event_id: morning.to_string(),
            timestamp_ms: morning_at,
        },
    );
    assert_eq!(
        bob.first_message_since(room_id.clone(), noon_at + 60_000)
            .await?,
        MessageSince::NoneAfter,
    );
    assert!(matches!(
        bob.first_message_since("!nowhere:example.org".to_owned(), 0)
            .await,
        Err(CoreError::RoomNotFound { .. })
    ));

    // The app then opens the room around it.
    let around = bob.event_timeline(room_id, noon.to_string()).await?;
    let mut items = watch_timeline(&around).await;
    items
        .wait_until(|items| event_of(items, "noon").is_some())
        .await?;
    Ok(())
}
