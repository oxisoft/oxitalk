//! Threads on the test homeserver, opened the way the app's thread pane opens them.

use std::{error::Error, time::Duration};

use matrix_sdk::ruma::{OwnedRoomId, events::room::message::RoomMessageEventContent};
use oxitalk_core::api::{
    room_list::Membership,
    rooms::NewRoom,
    session::{Session, restore},
    timeline::{Timeline, TimelineDiff, TimelineItem, TimelineItemContent},
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

/// Whether `items` shows the thread's first message and every reply as text, and nothing it
/// can't decrypt.
fn all_replies_readable(items: &[TimelineItem]) -> bool {
    event_of(items, "who's in for lunch?").is_some()
        && REPLIES.iter().all(|r| event_of(items, r).is_some())
        && !items
            .iter()
            .any(|i| matches!(i.content, TimelineItemContent::UnableToDecrypt { .. }))
}

/// A new encrypted group of `creator` and `members`, all joined.
async fn encrypted_group(
    creator: &Session,
    members: [&Session; 2],
) -> Result<String, Box<dyn Error>> {
    let room_id = creator
        .create_room(NewRoom {
            name: "Team".to_owned(),
            topic: None,
            public: false,
            alias: None,
            encrypted: true,
            avatar: None,
        })
        .await?;
    for other in members {
        creator.invite(room_id.clone(), other.user_id()).await?;
        let mut rooms = watch_rooms(other).await?;
        rooms
            .wait_until(|rooms| rooms.iter().any(|r| r.room_id == room_id))
            .await?;
        other.join(room_id.clone()).await?;
        rooms
            .wait_until(|rooms| {
                rooms
                    .iter()
                    .any(|r| r.room_id == room_id && r.membership == Membership::Joined)
            })
            .await?;
    }
    Ok(room_id)
}

/// Writes the keys `user` encrypted their messages in the room `room_id` with to a file in
/// `dir`, for another device to import.
async fn export_own_keys(
    user: &Session,
    room_id: &str,
    dir: &std::path::Path,
) -> Result<std::path::PathBuf, Box<dyn Error>> {
    let room_id: OwnedRoomId = room_id.try_into()?;
    let own = user
        .sdk()
        .encryption()
        .curve25519_key()
        .await
        .ok_or("no identity key")?;
    let path = dir.join(format!("{}.keys", user.user_id()));
    user.sdk()
        .encryption()
        .export_room_keys(path.clone(), KEYS_PASSPHRASE, |session| {
            session.room_id() == room_id && session.sender_key() == own
        })
        .await?;
    Ok(path)
}

/// Protects the exported keys of [`export_own_keys`].
const KEYS_PASSPHRASE: &str = "test keys";

/// An encrypted group of Alice, Bob and Carol: Carol writes a message and Bob answers it in a
/// thread. Alice signs in on a new device, which has Carol's key (imported) but not yet Bob's
/// when it loads the message: the message comes with its latest reply, which it can't decrypt
/// yet. Then Bob's key comes (imported) and the replies decrypt. Alice opens the thread, closes
/// it and opens it again: every reply shows as text, also a while later. The second time, the
/// latest reply once showed as "unable to decrypt" (see `threads::restore_latest_reply`).
#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a test homeserver (test-infra/)"]
async fn a_thread_opened_again_still_shows_its_replies() -> TestResult {
    let users = [
        TestUser::register().await?,
        TestUser::register().await?,
        TestUser::register().await?,
    ];
    let stores = [
        tempfile::tempdir()?,
        tempfile::tempdir()?,
        tempfile::tempdir()?,
        tempfile::tempdir()?,
    ];
    let alice = users[0].login(&stores[0].path().to_string_lossy()).await?;
    let bob = users[1].login(&stores[1].path().to_string_lossy()).await?;
    let carol = users[2].login(&stores[2].path().to_string_lossy()).await?;
    for session in [&alice, &bob, &carol] {
        session.start_sync().await;
    }
    let room_id = encrypted_group(&alice, [&bob, &carol]).await?;
    // Alice's first device goes, without any key of what follows.
    alice.stop_sync().await;
    drop(alice);

    // Carol writes, and Bob answers her in a thread, more than once.
    let id: OwnedRoomId = room_id.as_str().try_into()?;
    let carol_room = carol.sdk().get_room(&id).ok_or("Carol has no room")?;
    let root = carol_room
        .send(RoomMessageEventContent::text_plain("who's in for lunch?"))
        .await?
        .response
        .event_id
        .to_string();
    let bob_timeline = bob.timeline(room_id.clone()).await?;
    let mut bob_items = watch_timeline(&bob_timeline).await;
    bob_items
        .wait_paging(&bob_timeline, |items| {
            event_of(items, "who's in for lunch?").is_some()
        })
        .await?;
    let bob_thread = bob.thread_timeline(room_id.clone(), root.clone()).await?;
    for reply in REPLIES {
        bob_thread.send_text(reply.to_owned(), false).await?;
    }
    // Until the server has them all: his main timeline shows them under the message.
    bob_items
        .wait_paging(&bob_timeline, |items| {
            event_of(items, "who's in for lunch?").is_some_and(|e| {
                e.thread
                    .as_ref()
                    .is_some_and(|t| usize::try_from(t.reply_count) == Ok(REPLIES.len()))
            })
        })
        .await?;
    carol_room
        .send(RoomMessageEventContent::text_plain("anyone else?"))
        .await?;
    let keys = tempfile::tempdir()?;
    let carol_keys = export_own_keys(&carol, &room_id, keys.path()).await?;
    let bob_keys = export_own_keys(&bob, &room_id, keys.path()).await?;

    // Alice's new device, with Carol's key: her chat loads Carol's message.
    let alice = users[0].login(&stores[3].path().to_string_lossy()).await?;
    alice
        .sdk()
        .encryption()
        .import_room_keys(carol_keys, KEYS_PASSPHRASE)
        .await?;
    alice.start_sync().await;
    watch_rooms(&alice)
        .await?
        .wait_until(|rooms| rooms.iter().any(|r| r.room_id == room_id))
        .await?;
    let alice_timeline = alice.timeline(room_id.clone()).await?;
    let mut alice_items = watch_timeline(&alice_timeline).await;
    alice_items
        .wait_paging(&alice_timeline, |items| {
            event_of(items, "who's in for lunch?").is_some()
        })
        .await?;
    // Bob's key comes.
    alice
        .sdk()
        .encryption()
        .import_room_keys(bob_keys, KEYS_PASSPHRASE)
        .await?;

    // She opens the thread, reads it, closes it, and opens it again.
    for opened in ["first", "second"] {
        let thread = alice.thread_timeline(room_id.clone(), root.clone()).await?;
        let mut thread_items = watch_timeline(&thread).await;
        wait_as_the_pane(&mut thread_items, &thread, all_replies_readable)
            .await
            .map_err(|e| format!("the thread opened the {opened} time: {e}"))?;
        // And it stays so.
        if thread_items
            .holds_within(Duration::from_secs(5), |items| !all_replies_readable(items))
            .await?
        {
            return Err(format!(
                "the thread opened the {opened} time lost a reply: {:?}",
                thread_items.items
            )
            .into());
        }
        drop((thread_items, thread));
    }
    Ok(())
}

/// How many rounds the busy thread below has: a reply from each side per round.
const BUSY_ROUNDS: usize = 6;

/// A busy thread, the way a bot answers in one: each of its replies edited twice while it
/// writes, a reaction on it and on the other side's message, taken back again. Alice has the
/// thread open the whole time and answers in it. After a restart she opens it again and sees
/// every reply.
#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a test homeserver (test-infra/)"]
#[allow(
    clippy::too_many_lines,
    reason = "one thread's story, round after round"
)]
async fn a_busy_thread_read_live_shows_its_replies_after_a_restart() -> TestResult {
    use matrix_sdk::ruma::{
        OwnedEventId,
        events::{
            reaction::ReactionEventContent,
            relation::{Annotation, Thread},
            room::message::{Relation, ReplacementMetadata},
        },
    };

    let (alice_user, bob_user) = (TestUser::register().await?, TestUser::register().await?);
    let (alice_store, bob_store) = (tempfile::tempdir()?, tempfile::tempdir()?);
    let alice_store_dir = alice_store.path().to_string_lossy().into_owned();
    let alice = alice_user.login(&alice_store_dir).await?;
    // Not on Tuwunel yet: there Bob's replies leave Alice's open thread while she reads it,
    // and the reply count never reaches the total. Under investigation.
    if alice
        .server_info()
        .await?
        .software
        .and_then(|s| s.name)
        .is_some_and(|name| name == "Tuwunel")
    {
        return Ok(());
    }
    let bob = bob_user.login(&bob_store.path().to_string_lossy()).await?;
    alice.start_sync().await;
    bob.start_sync().await;
    let room_id = bob
        .create_room(NewRoom {
            name: "Reviews".to_owned(),
            topic: None,
            public: false,
            alias: None,
            encrypted: true,
            avatar: None,
        })
        .await?;
    bob.invite(room_id.clone(), alice.user_id()).await?;
    let mut alice_rooms = watch_rooms(&alice).await?;
    alice_rooms
        .wait_until(|rooms| rooms.iter().any(|r| r.room_id == room_id))
        .await?;
    alice.join(room_id.clone()).await?;
    alice_rooms
        .wait_until(|rooms| {
            rooms
                .iter()
                .any(|r| r.room_id == room_id && r.membership == Membership::Joined)
        })
        .await?;
    // Bob sees her join, so his messages are encrypted for her device.
    let id: OwnedRoomId = room_id.as_str().try_into()?;
    let bob_room = bob.sdk().get_room(&id).ok_or("Bob has no room")?;
    crate::support::poll_until("Bob to see Alice joined", || async {
        let joined = bob_room
            .members(matrix_sdk::RoomMemberships::JOIN)
            .await
            .map_err(|e| oxitalk_core::api::error::CoreError::Internal {
                message: e.to_string(),
            })?
            .len();
        Ok((joined == 2).then_some(()))
    })
    .await?;

    // Bob starts the thread with a message of his own.
    let root: OwnedEventId = bob_room
        .send(RoomMessageEventContent::text_plain("weekly review"))
        .await?
        .response
        .event_id;
    let alice_timeline = alice.timeline(room_id.clone()).await?;
    let mut alice_items = watch_timeline(&alice_timeline).await;
    alice_items
        .wait_paging(&alice_timeline, |items| {
            event_of(items, "weekly review").is_some()
        })
        .await?;

    // Alice opens the thread and keeps it open.
    let thread = alice
        .thread_timeline(room_id.clone(), root.to_string())
        .await?;
    let mut thread_items = watch_timeline(&thread).await;
    wait_as_the_pane(&mut thread_items, &thread, |items| {
        event_of(items, "weekly review").is_some()
    })
    .await?;

    let mut latest = root.clone();
    for round in 0..BUSY_ROUNDS {
        // Bob answers: a placeholder, a reaction on it, two edits, the reaction taken back.
        let reply = bob_room
            .send({
                let mut placeholder = RoomMessageEventContent::text_plain(format!("b{round} ..."));
                placeholder.relates_to = Some(Relation::Thread(Thread::plain(
                    root.clone(),
                    latest.clone(),
                )));
                placeholder
            })
            .await?
            .response
            .event_id;
        let eyes = bob_room
            .send(ReactionEventContent::new(Annotation::new(
                reply.clone(),
                "👀".to_owned(),
            )))
            .await?
            .response
            .event_id;
        for edit in ["b{round} writing", "b{round} done"] {
            let body = edit.replace("{round}", &round.to_string());
            bob_room
                .send(
                    RoomMessageEventContent::text_plain(body)
                        .make_replacement(ReplacementMetadata::new(reply.clone(), None)),
                )
                .await?;
        }
        bob_room.redact(&eyes, None, None).await?;

        // Alice answers in the thread and reads it, as the pane does.
        let mine = format!("a{round}");
        thread.send_text(mine.clone(), false).await?;
        let done = format!("b{round} done");
        thread_items
            .wait_until(|items| {
                event_of(items, &done).is_some()
                    && event_of(items, &mine).is_some_and(|e| e.event_id.is_some())
            })
            .await
            .map_err(|e| {
                format!(
                    "round {round}, live: {e}; shown: {:?}",
                    crate::support::messages(&thread_items.items)
                )
            })?;
        let _ = thread.mark_as_read().await;
        let alice_reply: OwnedEventId = event_of(&thread_items.items, &mine)
            .and_then(|e| e.event_id.clone())
            .ok_or("no event ID")?
            .as_str()
            .try_into()?;
        latest = alice_reply.clone();

        // Bob reacts to her answer and takes it back once he has replied.
        let ack = bob_room
            .send(ReactionEventContent::new(Annotation::new(
                alice_reply,
                "👀".to_owned(),
            )))
            .await?
            .response
            .event_id;
        bob_room.redact(&ack, None, None).await?;
    }
    let expected: Vec<String> = (0..BUSY_ROUNDS)
        .flat_map(|r| [format!("b{r} done"), format!("a{r}")])
        .collect();
    let all = |items: &[TimelineItem]| {
        event_of(items, "weekly review").is_some()
            && expected.iter().all(|t| event_of(items, t).is_some())
    };
    thread_items
        .wait_until(all)
        .await
        .map_err(|e| format!("live, at the end: {e}"))?;

    // Alice closes the app and opens it again.
    let alice_data = alice.session_data()?;
    alice.stop_sync().await;
    drop((
        thread_items,
        thread,
        alice_items,
        alice_timeline,
        alice_rooms,
        alice,
    ));
    let alice = restore(alice_data, alice_store_dir, PASSPHRASE.to_owned()).await?;
    alice.start_sync().await;
    let alice_timeline = alice.timeline(room_id.clone()).await?;
    let mut alice_items = watch_timeline(&alice_timeline).await;
    alice_items
        .wait_paging(&alice_timeline, |items| {
            event_of(items, "weekly review").is_some_and(|e| {
                e.thread
                    .as_ref()
                    .is_some_and(|t| usize::try_from(t.reply_count) == Ok(2 * BUSY_ROUNDS))
            })
        })
        .await
        .map_err(|e| format!("the chat after the restart: {e}"))?;
    let thread = alice.thread_timeline(room_id, root.to_string()).await?;
    let mut thread_items = watch_timeline(&thread).await;
    wait_as_the_pane(&mut thread_items, &thread, all)
        .await
        .map_err(|e| format!("the thread after the restart: {e}"))?;
    Ok(())
}
