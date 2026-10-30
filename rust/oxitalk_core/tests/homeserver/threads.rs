//! Threads on the test homeserver, opened the way the app's thread pane opens them.

use std::{error::Error, time::Duration};

use matrix_sdk::ruma::{OwnedRoomId, events::room::message::RoomMessageEventContent};
use oxitalk_core::api::{
    room_list::Membership,
    rooms::NewRoom,
    session::restore,
    timeline::{Timeline, TimelineDiff, TimelineItem},
};

use super::{PASSPHRASE, TestResult, TestUser, event_of, watch_rooms, watch_timeline};
use crate::support::{TIMEOUT, Watched};

/// The replies Bob posts in the thread.
const REPLIES: [&str; 6] = ["r1", "r2", "r3", "r4", "r5", "r6"];

/// Waits until `items` has `done`, loading older items as the app's chat pane does: while it
/// shows fewer than 20 entries and the start isn't reached, it asks for 20 more after each
/// change.
async fn wait_as_the_pane(
    items: &mut Watched<TimelineItem, TimelineDiff>,
    timeline: &Timeline,
    done: impl Fn(&[TimelineItem]) -> bool,
) -> TestResult {
    let mut reached_start = false;
    tokio::time::timeout(TIMEOUT, async {
        loop {
            if items.holds_within(Duration::from_secs(1), &done).await? {
                return Ok::<_, Box<dyn Error>>(());
            }
            if items.items.len() < 20 && !reached_start {
                reached_start = timeline.paginate_back(20).await?;
            }
        }
    })
    .await
    .map_err(|_| {
        format!(
            "the thread never showed it; reached start: {reached_start}, items: {:?}",
            items.items
        )
    })?
}

/// An encrypted group in which Bob started a thread under Alice's message and answered in it
/// while Alice's app was closed. When she opens the app again, the chat shows the thread under
/// the message, and the thread shows the message and every reply. It once showed nothing (its
/// back-pagination failed), and Bob's replies stalled his own sync: both lost the thread's first
/// chunk in the store (see `persist_thread_head`).
#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a test homeserver (test-infra/)"]
async fn a_thread_answered_while_the_app_was_closed_shows_its_replies() -> TestResult {
    let (alice_user, bob_user) = (TestUser::register().await?, TestUser::register().await?);
    let (alice_store, bob_store) = (tempfile::tempdir()?, tempfile::tempdir()?);
    let alice_store_dir = alice_store.path().to_string_lossy().into_owned();
    let alice = alice_user.login(&alice_store_dir).await?;
    let bob = bob_user.login(&bob_store.path().to_string_lossy()).await?;
    alice.start_sync().await;
    bob.start_sync().await;
    let room_id = alice
        .create_room(NewRoom {
            name: "Team".to_owned(),
            topic: None,
            public: false,
            alias: None,
            encrypted: true,
            avatar: None,
        })
        .await?;
    alice.invite(room_id.clone(), bob.user_id()).await?;
    let mut bob_rooms = watch_rooms(&bob).await?;
    bob_rooms
        .wait_until(|rooms| rooms.iter().any(|r| r.room_id == room_id))
        .await?;
    bob.join(room_id.clone()).await?;
    bob_rooms
        .wait_until(|rooms| {
            rooms
                .iter()
                .any(|r| r.room_id == room_id && r.membership == Membership::Joined)
        })
        .await?;

    // Alice writes; Bob sees it.
    let alice_timeline = alice.timeline(room_id.clone()).await?;
    alice_timeline
        .send_text("who's in for lunch?".to_owned(), false)
        .await?;
    let bob_timeline = bob.timeline(room_id.clone()).await?;
    let mut bob_items = watch_timeline(&bob_timeline).await;
    bob_items
        .wait_paging(&bob_timeline, |items| {
            event_of(items, "who's in for lunch?").is_some_and(|e| e.event_id.is_some())
        })
        .await?;
    let root = event_of(&bob_items.items, "who's in for lunch?")
        .and_then(|e| e.event_id.clone())
        .ok_or("no event ID")?;

    // Alice closes the app.
    let alice_data = alice.session_data()?;
    alice.stop_sync().await;
    drop((alice_timeline, alice));

    // Bob starts a thread under her message and answers in it, more than once.
    let bob_thread = bob.thread_timeline(room_id.clone(), root.clone()).await?;
    for reply in REPLIES {
        bob_thread.send_text(reply.to_owned(), false).await?;
    }
    // Until the server has them all: his main timeline shows them under the message. (Not his
    // thread's items: its local echoes can miss their event IDs, an SDK race.)
    bob_items
        .wait_paging(&bob_timeline, |items| {
            event_of(items, "who's in for lunch?").is_some_and(|e| {
                e.thread
                    .as_ref()
                    .is_some_and(|t| usize::try_from(t.reply_count) == Ok(REPLIES.len()))
            })
        })
        .await?;
    // A message after the thread, in the main timeline.
    let id: OwnedRoomId = room_id.as_str().try_into()?;
    let bob_room = bob.sdk().get_room(&id).ok_or("Bob has no room")?;
    bob_room
        .send(RoomMessageEventContent::text_plain("anyone?"))
        .await?;

    // Alice opens the app again: the chat shows the thread under her message.
    let alice = restore(alice_data, alice_store_dir, PASSPHRASE.to_owned()).await?;
    alice.start_sync().await;
    let alice_timeline = alice.timeline(room_id.clone()).await?;
    let mut alice_items = watch_timeline(&alice_timeline).await;
    alice_items
        .wait_paging(&alice_timeline, |items| {
            event_of(items, "who's in for lunch?").is_some_and(|e| {
                e.thread
                    .as_ref()
                    .is_some_and(|t| usize::try_from(t.reply_count) == Ok(REPLIES.len()))
            })
        })
        .await
        .map_err(|e| format!("the chat after the restart: {e}"))?;

    // She opens the thread: the message, then every reply.
    let thread = alice.thread_timeline(room_id, root).await?;
    let mut thread_items = watch_timeline(&thread).await;
    wait_as_the_pane(&mut thread_items, &thread, |items| {
        event_of(items, "who's in for lunch?").is_some()
            && REPLIES.iter().all(|r| event_of(items, r).is_some())
    })
    .await
}
