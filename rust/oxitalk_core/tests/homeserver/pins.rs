//! Pinned messages, and opening a chat at an old message, on the test homeserver.

use std::error::Error;

use matrix_sdk::ruma::{OwnedRoomId, events::room::message::RoomMessageEventContent};
use oxitalk_core::api::{
    error::CoreError,
    pins::{Pins, RoomPins},
    rooms::NewRoom,
    session::Session,
    timeline::{TimelineDiff, TimelineItem},
};
use tokio::sync::mpsc;

use super::{
    TIMEOUT, TestResult, TestUser, event_of, joined_dm, messages, poll_until, watch_rooms,
    watch_timeline,
};
use crate::support::Watched;

async fn watch_pins(pins: &Pins) -> mpsc::UnboundedReceiver<RoomPins> {
    let (sender, states) = mpsc::unbounded_channel();
    pins.updates(move |state| sender.send(state).is_ok()).await;
    states
}

async fn wait_for_pins(
    states: &mut mpsc::UnboundedReceiver<RoomPins>,
    what: &str,
    done: impl Fn(&RoomPins) -> bool,
) -> Result<RoomPins, Box<dyn Error>> {
    tokio::time::timeout(TIMEOUT, async {
        while let Some(state) = states.recv().await {
            if done(&state) {
                return Ok(state);
            }
        }
        Err("the pins stream ended".into())
    })
    .await
    .map_err(|_| format!("timed out waiting until {what}"))?
}

/// The event ID of the text message `body`, once the server has it.
pub(super) fn id_of(items: &[TimelineItem], body: &str) -> Result<String, Box<dyn Error>> {
    Ok(event_of(items, body)
        .and_then(|event| event.event_id.clone())
        .ok_or_else(|| format!("no event ID for {body}"))?)
}

pub(super) async fn wait_sent(
    items: &mut Watched<TimelineItem, TimelineDiff>,
    bodies: &[&str],
) -> TestResult {
    items
        .wait_until(|items| {
            bodies
                .iter()
                .all(|body| event_of(items, body).is_some_and(|e| e.event_id.is_some()))
        })
        .await
}

/// In an encrypted chat, a pin shows on the other side with the decrypted message in the
/// pinned timeline; unpinning takes it away there.
#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a test homeserver (test-infra/)"]
async fn pinned_messages_follow_pins_in_an_encrypted_chat() -> TestResult {
    let (alice, bob, room_id, _stores) = joined_dm().await?;
    let timeline = alice.timeline(room_id.clone()).await?;
    let mut items = watch_timeline(&timeline).await;
    for body in ["first pin", "second pin", "not pinned"] {
        timeline.send_text(body.to_owned(), false).await?;
    }
    wait_sent(&mut items, &["first pin", "second pin", "not pinned"]).await?;
    let first = id_of(&items.items, "first pin")?;
    let second = id_of(&items.items, "second pin")?;

    let bob_pins = bob.pins(room_id.clone()).await?;
    let mut bob_states = watch_pins(&bob_pins).await;
    // A DM makes both admins, who may pin.
    wait_for_pins(&mut bob_states, "Bob may pin", |p| {
        p.can_pin && p.event_ids.is_empty()
    })
    .await?;

    let alice_pins = alice.pins(room_id.clone()).await?;
    let mut alice_states = watch_pins(&alice_pins).await;
    assert!(alice_pins.pin(first.clone()).await?);
    // Pinning sends the whole list again, from what the store has: wait for the echo.
    wait_for_pins(&mut alice_states, "Alice has the first pin", |p| {
        p.event_ids == [first.clone()]
    })
    .await?;
    assert!(alice_pins.pin(second.clone()).await?);
    wait_for_pins(&mut alice_states, "Alice has both pins", |p| {
        p.event_ids == [first.clone(), second.clone()]
    })
    .await?;
    assert!(!alice_pins.pin(second.clone()).await?, "pinned twice");
    wait_for_pins(&mut bob_states, "Bob sees both pins in order", |p| {
        p.event_ids == [first.clone(), second.clone()]
    })
    .await?;

    let pinned = bob.pinned_timeline(room_id.clone()).await?;
    let mut pinned_items = watch_timeline(&pinned).await;
    pinned_items
        .wait_until(|items| {
            let texts: Vec<_> = messages(items).into_iter().map(|(body, _)| body).collect();
            texts == ["first pin", "second pin"]
        })
        .await?;

    assert!(alice_pins.unpin(first.clone()).await?);
    wait_for_pins(&mut bob_states, "Bob sees the first unpinned", |p| {
        p.event_ids == [second.clone()]
    })
    .await?;
    pinned_items
        .wait_until(|items| {
            let texts: Vec<_> = messages(items).into_iter().map(|(body, _)| body).collect();
            texts == ["second pin"]
        })
        .await?;
    wait_for_pins(&mut alice_states, "Alice has one pin left", |p| {
        p.event_ids == [second.clone()]
    })
    .await?;
    assert!(!alice_pins.unpin(first).await?, "unpinned twice");
    Ok(())
}

/// Alice, Bob, the room ID, the event IDs of the messages and the stores.
pub(super) type PublicRoom = (
    Session,
    Session,
    String,
    Vec<String>,
    Vec<tempfile::TempDir>,
);

/// A public room where Alice is admin and Bob a member, with the messages Alice sent.
pub(super) async fn public_room_with(bodies: &[String]) -> Result<PublicRoom, Box<dyn Error>> {
    let (alice_user, bob_user) = (TestUser::register().await?, TestUser::register().await?);
    let stores = vec![tempfile::tempdir()?, tempfile::tempdir()?];
    let alice = alice_user
        .login(&stores[0].path().to_string_lossy())
        .await?;
    let bob = bob_user.login(&stores[1].path().to_string_lossy()).await?;
    alice.start_sync().await;
    bob.start_sync().await;
    let room_id = alice
        .create_room(NewRoom {
            name: "Open".to_owned(),
            topic: None,
            public: true,
            alias: None,
            encrypted: false,
            avatar: None,
        })
        .await?;
    let id: OwnedRoomId = room_id.as_str().try_into()?;
    let room = poll_until("Alice has the room", || async {
        Ok::<_, CoreError>(alice.sdk().get_room(&id))
    })
    .await?;
    let mut ids = Vec::new();
    for body in bodies {
        let sent = room.send(RoomMessageEventContent::text_plain(body)).await?;
        ids.push(sent.response.event_id.to_string());
    }
    bob.join(room_id.clone()).await?;
    let mut bob_rooms = watch_rooms(&bob).await?;
    bob_rooms
        .wait_until(|rooms| rooms.iter().any(|r| r.room_id == room_id))
        .await?;
    Ok((alice, bob, room_id, ids, stores))
}

/// When the sync starts over because the server forgot its position, as Synapse does after a
/// request cancelled to subscribe to a room, the pins still follow the room.
#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a test homeserver (test-infra/)"]
async fn pins_follow_the_room_after_the_sync_session_expired() -> TestResult {
    let (alice, bob, room_id, ids, _stores) = public_room_with(&["pin me".to_owned()]).await?;
    let pinned = ids[0].clone();

    let bob_pins = bob.pins(room_id.clone()).await?;
    let mut states = watch_pins(&bob_pins).await;
    wait_for_pins(&mut states, "Bob sees no pins", |p| {
        !p.can_pin && p.event_ids.is_empty()
    })
    .await?;

    bob.expire_sync_sessions().await;
    bob.start_sync().await;
    let alice_pins = alice.pins(room_id).await?;
    assert!(alice_pins.pin(pinned.clone()).await?);
    wait_for_pins(
        &mut states,
        "Bob sees the pin after his sync restarted",
        |p| p.event_ids == [pinned.clone()],
    )
    .await?;
    Ok(())
}

/// Only members with the power level for pins may pin; the event timeline jumps to an old
/// message and pages forward to the newest.
#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a test homeserver (test-infra/)"]
async fn pins_need_the_power_level_and_old_messages_open_around_them() -> TestResult {
    let mut bodies = vec!["anchor".to_owned()];
    bodies.extend((0..45).map(|i| format!("after {i}")));
    let (alice, bob, room_id, ids, _stores) = public_room_with(&bodies).await?;
    let anchor = ids[0].clone();

    let bob_pins = bob.pins(room_id.clone()).await?;
    let mut states = watch_pins(&bob_pins).await;

    wait_for_pins(&mut states, "Bob may not pin", |p| !p.can_pin).await?;
    let refused = bob_pins.pin(anchor.clone()).await;
    assert!(
        matches!(refused, Err(CoreError::Forbidden { .. })),
        "{refused:?}"
    );
    alice
        .set_power_level(room_id.clone(), bob.user_id(), 50)
        .await?;
    wait_for_pins(&mut states, "Bob may pin as a moderator", |p| p.can_pin).await?;
    assert!(bob_pins.pin(anchor.clone()).await?);
    wait_for_pins(&mut states, "Bob sees his pin", |p| {
        p.event_ids == [anchor.clone()]
    })
    .await?;

    // Bob opens the room at the anchor, which his sync never brought.
    let around = bob.event_timeline(room_id.clone(), anchor.clone()).await?;
    let mut around_items = watch_timeline(&around).await;
    around_items
        .wait_until(|items| event_of(items, "anchor").is_some())
        .await?;
    assert!(event_of(&around_items.items, "after 44").is_none());
    let mut end = false;
    for _ in 0..10 {
        end = around.paginate_forward(20).await?;
        if end {
            break;
        }
    }
    assert!(end, "never reached the newest message");
    around_items
        .wait_until(|items| event_of(items, "after 44").is_some())
        .await?;
    // A live timeline is at its end already.
    assert!(bob.timeline(room_id).await?.paginate_forward(20).await?);
    Ok(())
}
