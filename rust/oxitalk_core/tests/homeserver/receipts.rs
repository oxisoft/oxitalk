//! Read receipts on the test homeserver: who has read up to which message, in a direct chat
//! and in a group.

use std::error::Error;

use matrix_sdk::ruma::{
    OwnedEventId, OwnedRoomId,
    api::client::receipt::create_receipt::v3::ReceiptType,
    events::{
        reaction::ReactionEventContent, receipt::ReceiptThread, relation::Annotation,
        room::message::RoomMessageEventContent,
    },
};
use oxitalk_core::api::{
    error::CoreError,
    rooms::NewRoom,
    session::Session,
    timeline::{ReadReceipt, TimelineItem, TimelineItemContent},
};

use super::{TestResult, TestUser, event_of, joined_dm, poll_until, watch_rooms, watch_timeline};
use crate::pins::{id_of, wait_sent};

/// No readers.
const NO_ONE: [String; 0] = [];

/// Who has read up to the text message `body`, by user ID, newest first.
fn readers(items: &[TimelineItem], body: &str) -> Vec<String> {
    event_of(items, body).map_or_else(Vec::new, |event| {
        event.read_by.iter().map(|r| r.user_id.clone()).collect()
    })
}

/// The receipt of `user` on the text message `body`, if it is there.
fn receipt<'a>(items: &'a [TimelineItem], body: &str, user: &str) -> Option<&'a ReadReceipt> {
    event_of(items, body)?
        .read_by
        .iter()
        .find(|r| r.user_id == user)
}

/// In a direct chat, Alice sees on her messages how far Bob has read: his receipt sits on
/// the newest message he read and moves on when he reads more, or when he answers (an
/// implicit receipt). Her own receipt never shows.
#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a test homeserver (test-infra/)"]
async fn the_other_side_of_a_direct_chat_shows_where_it_read() -> TestResult {
    let (alice, bob, room_id, _stores) = joined_dm().await?;
    let alice_timeline = alice.timeline(room_id.clone()).await?;
    let mut alice_items = watch_timeline(&alice_timeline).await;
    for body in ["one", "two"] {
        alice_timeline.send_text(body.to_owned(), false).await?;
    }
    wait_sent(&mut alice_items, &["one", "two"]).await?;
    assert_eq!(readers(&alice_items.items, "one"), NO_ONE);
    assert_eq!(readers(&alice_items.items, "two"), NO_ONE);

    let bob_id = bob.user_id();
    let bob_timeline = bob.timeline(room_id.clone()).await?;
    let mut bob_items = watch_timeline(&bob_timeline).await;
    bob_items
        .wait_until(|items| event_of(items, "two").is_some())
        .await?;
    bob_timeline.mark_as_read().await?;
    alice_items
        .wait_until(|items| readers(items, "two") == [bob_id.clone()])
        .await?;
    assert_eq!(readers(&alice_items.items, "one"), NO_ONE);
    let read = receipt(&alice_items.items, "two", &bob_id).ok_or("no receipt")?;
    assert!(read.timestamp_ms.is_some_and(|ms| ms > 0), "{read:?}");

    // He reads the next message: the receipt moves there.
    alice_timeline.send_text("three".to_owned(), false).await?;
    bob_items
        .wait_until(|items| event_of(items, "three").is_some())
        .await?;
    bob_timeline.mark_as_read().await?;
    alice_items
        .wait_until(|items| {
            readers(items, "three") == [bob_id.clone()] && readers(items, "two").is_empty()
        })
        .await?;

    // Alice's own receipt is never among the readers on her side; Bob sees it.
    alice_timeline.send_text("four".to_owned(), false).await?;
    bob_timeline.send_text("answer".to_owned(), false).await?;
    // Answering is reading: Bob's receipt is on his own answer, after Alice's "four".
    alice_items
        .wait_until(|items| {
            readers(items, "answer") == [bob_id.clone()]
                && readers(items, "four").is_empty()
                && readers(items, "three").is_empty()
        })
        .await?;
    alice_timeline.mark_as_read().await?;
    let alice_id = alice.user_id();
    bob_items
        .wait_until(|items| {
            items.iter().any(|item| match &item.content {
                TimelineItemContent::Message { event, .. } => {
                    event.read_by.iter().any(|r| r.user_id == alice_id)
                }
                _ => false,
            })
        })
        .await?;
    assert!(
        alice_items
            .items
            .iter()
            .filter_map(|item| match &item.content {
                TimelineItemContent::Message { event, .. } => Some(event),
                _ => None,
            })
            .all(|event| event.read_by.iter().all(|r| r.user_id != alice.user_id())),
        "Alice's own receipt shows on her side"
    );
    Ok(())
}

/// In a thread, receipts are the thread's own: Bob reading the thread shows on its replies in
/// Alice's thread.
#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a test homeserver (test-infra/)"]
async fn a_thread_shows_where_the_other_side_read_in_it() -> TestResult {
    let (alice, bob, room_id, _stores) = joined_dm().await?;
    let alice_timeline = alice.timeline(room_id.clone()).await?;
    let mut alice_items = watch_timeline(&alice_timeline).await;
    alice_timeline.send_text("lunch?".to_owned(), false).await?;
    wait_sent(&mut alice_items, &["lunch?"]).await?;
    let root = id_of(&alice_items.items, "lunch?")?;
    let alice_thread = alice.thread_timeline(room_id.clone(), root.clone()).await?;
    let mut alice_thread_items = watch_timeline(&alice_thread).await;
    for body in ["pizza", "at noon"] {
        alice_thread.send_text(body.to_owned(), false).await?;
    }
    wait_sent(&mut alice_thread_items, &["pizza", "at noon"]).await?;

    // Bob opens the thread from its first message, once he has that (the thread can't be
    // opened before).
    let bob_timeline = bob.timeline(room_id.clone()).await?;
    let mut bob_items = watch_timeline(&bob_timeline).await;
    bob_items
        .wait_paging(&bob_timeline, |items| event_of(items, "lunch?").is_some())
        .await?;
    let bob_thread = bob.thread_timeline(room_id.clone(), root).await?;
    let mut bob_thread_items = watch_timeline(&bob_thread).await;
    bob_thread_items
        .wait_paging(&bob_thread, |items| event_of(items, "at noon").is_some())
        .await?;
    bob_thread.mark_as_read().await?;
    let bob_id = bob.user_id();
    alice_thread_items
        .wait_until(|items| {
            readers(items, "at noon") == [bob_id.clone()] && readers(items, "pizza").is_empty()
        })
        .await?;
    Ok(())
}

/// Logs in a new user with the display name `name`, syncing.
async fn user_named(
    name: &str,
    stores: &mut Vec<tempfile::TempDir>,
) -> Result<Session, Box<dyn Error>> {
    let user = TestUser::register().await?;
    let store = tempfile::tempdir()?;
    let session = user.login(&store.path().to_string_lossy()).await?;
    stores.push(store);
    session.sdk().account().set_display_name(Some(name)).await?;
    session.start_sync().await;
    Ok(session)
}

/// Sends `user`'s public read receipt for `event_id`, as any client would.
async fn read_up_to(user: &Session, room_id: &str, event_id: &str) -> TestResult {
    let id: OwnedRoomId = room_id.try_into()?;
    let room = poll_until("the reader has the room", || async {
        Ok::<_, CoreError>(user.sdk().get_room(&id))
    })
    .await?;
    let event_id: OwnedEventId = event_id.try_into()?;
    room.send_single_receipt(ReceiptType::Read, ReceiptThread::Unthreaded, event_id)
        .await?;
    Ok(())
}

/// In a group of three, each reader shows on the message they read last, with their name;
/// a receipt on a reaction shows on the message reacted to, and the newest reader first.
#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a test homeserver (test-infra/)"]
async fn a_group_shows_who_read_up_to_each_message() -> TestResult {
    let mut stores = Vec::new();
    let alice = user_named("Alice", &mut stores).await?;
    let bob = user_named("Bob", &mut stores).await?;
    let carol = user_named("Carol", &mut stores).await?;
    let room_id = alice
        .create_room(NewRoom {
            name: "Three".to_owned(),
            topic: None,
            public: true,
            alias: None,
            encrypted: false,
            avatar: None,
        })
        .await?;
    bob.join(room_id.clone()).await?;
    carol.join(room_id.clone()).await?;
    let mut alice_rooms = watch_rooms(&alice).await?;
    alice_rooms
        .wait_until(|rooms| {
            rooms
                .iter()
                .any(|r| r.room_id == room_id && r.joined_members == 3)
        })
        .await?;

    // Sent before the timeline opens: a timeline that gets its own message from the send
    // queue and from a sync at once can hold it twice (the SDK's event cache race, see
    // skill oxitalk-homeserver-tests), and a receipt on it then finds no item. The direct
    // chat test covers receipts on messages sent through the timeline.
    let id: OwnedRoomId = room_id.as_str().try_into()?;
    let alice_room = alice.sdk().get_room(&id).ok_or("Alice has no room")?;
    let mut sent = Vec::new();
    for body in ["g1", "g2", "g3"] {
        let response = alice_room
            .send(RoomMessageEventContent::text_plain(body))
            .await?;
        sent.push(response.response.event_id.to_string());
    }
    let (g1, g3) = (sent[0].clone(), sent[2].clone());
    let timeline = alice.timeline(room_id.clone()).await?;
    let mut items = watch_timeline(&timeline).await;
    items
        .wait_paging(&timeline, |items| {
            ["g1", "g2", "g3"]
                .iter()
                .all(|body| event_of(items, body).is_some())
        })
        .await?;
    let (bob_id, carol_id) = (bob.user_id(), carol.user_id());

    read_up_to(&carol, &room_id, &g3).await?;
    read_up_to(&bob, &room_id, &g1).await?;
    items
        .wait_until(|items| {
            readers(items, "g1") == [bob_id.clone()]
                && readers(items, "g2").is_empty()
                && readers(items, "g3") == [carol_id.clone()]
        })
        .await?;
    let bob_read = receipt(&items.items, "g1", &bob_id).ok_or("no receipt")?;
    assert_eq!(bob_read.display_name.as_deref(), Some("Bob"));
    let carol_read = receipt(&items.items, "g3", &carol_id).ok_or("no receipt")?;
    assert_eq!(carol_read.display_name.as_deref(), Some("Carol"));

    // Bob reacts to g3 and reads up to his reaction, which the timeline doesn't show as an
    // item: his receipt shows on g3, newest first.
    let bob_room = bob.sdk().get_room(&id).ok_or("Bob has no room")?;
    let reaction = bob_room
        .send(ReactionEventContent::new(Annotation::new(
            g3.as_str().try_into()?,
            "👍".to_owned(),
        )))
        .await?;
    read_up_to(&bob, &room_id, reaction.response.event_id.as_str()).await?;
    items
        .wait_until(|items| {
            readers(items, "g3") == [bob_id.clone(), carol_id.clone()]
                && readers(items, "g1").is_empty()
        })
        .await?;
    Ok(())
}
