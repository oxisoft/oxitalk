//! One account on two devices: device A2 goes away (sync stopped, the process closed, the
//! sync position expired) while Bob writes and device A1 reads; when A2 is back, both chat
//! lists must show the same order, previews and unread counts. A room list syncs one event
//! per room, so A2 gets each room's newest event behind a gap; without the SDK's automatic
//! back-pagination (`session.rs` `build_client`) a gap ending in a reaction or an edit left A2
//! with a stale preview, the wrong place in the list and wrong unread counts.

#![allow(
    clippy::too_many_lines,
    reason = "one account's story, scenario after scenario"
)]

use std::error::Error;

use matrix_sdk::ruma::OwnedUserId;
use oxitalk_core::api::{
    room_list::{Membership, RoomListDiff, RoomSummary},
    rooms::NewRoom,
    session::{Session, restore},
    timeline::{SendState, TimelineItem, TimelineItemContent},
};

use super::{
    PASSPHRASE, TIMEOUT, TestResult, TestUser, messages, poll_until, watch_rooms, watch_timeline,
};
use crate::support::Watched;

type Rooms = Watched<RoomSummary, RoomListDiff>;

/// The test rooms in list order, as (name, last message, unread messages).
fn view(rooms: &[RoomSummary], ids: &[String]) -> Vec<(String, Option<String>, u32)> {
    rooms
        .iter()
        .filter(|r| ids.contains(&r.room_id))
        .map(|r| (r.name.clone(), r.last_message.clone(), r.unread_count))
        .collect()
}

/// Everything a chat list row shows about the counts, for the two devices to agree on.
fn counts(rooms: &[RoomSummary], ids: &[String]) -> Vec<(String, u32, u32, u32, bool)> {
    rooms
        .iter()
        .filter(|r| ids.contains(&r.room_id))
        .map(|r| {
            (
                r.name.clone(),
                r.unread_count,
                r.unread_notifications,
                r.unread_mentions,
                r.marked_unread,
            )
        })
        .collect()
}

/// Waits until the list has every test room with the wanted last messages.
#[track_caller]
fn wait_last<'a>(
    rooms: &'a mut Rooms,
    ids: &'a [String],
    wanted: &'a [(usize, &'a str)],
) -> impl Future<Output = TestResult> + 'a {
    rooms.wait_until(move |list| {
        wanted.iter().all(|(i, text)| {
            list.iter()
                .any(|r| r.room_id == ids[*i] && r.last_message.as_deref() == Some(*text))
        })
    })
}

/// Waits until both devices show the test rooms as `want` (name, last message, unread, in list
/// order), then until A2's notification and mention counts match A1's.
async fn agree(
    label: &str,
    a1: &mut Rooms,
    a2: &mut Rooms,
    ids: &[String],
    want: &[(&str, &str, u32)],
) -> TestResult {
    let want: Vec<_> = want
        .iter()
        .map(|(name, last, unread)| ((*name).to_owned(), Some((*last).to_owned()), *unread))
        .collect();
    for (device, rooms) in [("A1", &mut *a1), ("A2", &mut *a2)] {
        if !rooms
            .holds_within(TIMEOUT, |l| view(l, ids) == want)
            .await?
        {
            return Err(format!(
                "{label}: {device} shows {:?}, want {want:?}",
                view(&rooms.items, ids)
            )
            .into());
        }
    }
    let a1_counts = counts(&a1.items, ids);
    if !a2
        .holds_within(TIMEOUT, |l| counts(l, ids) == a1_counts)
        .await?
    {
        return Err(format!(
            "{label}: A2 counts {:?}, A1 {a1_counts:?}",
            counts(&a2.items, ids)
        )
        .into());
    }
    Ok(())
}

/// Sends `text` from `session` in `room_id` and waits until the server has it.
async fn send(session: &Session, room_id: &str, text: &str) -> TestResult {
    let timeline = session.timeline(room_id.to_owned()).await?;
    let mut items = watch_timeline(&timeline).await;
    timeline.send_text(text.to_owned(), false).await?;
    items
        .wait_until(|items| {
            items.iter().any(|item| {
                matches!(&item.content,
                    TimelineItemContent::Message { event, body, .. }
                    if body == text && event.send_state == SendState::Sent)
            })
        })
        .await
}

/// Opens the room on `session`, waits for `text`, marks it read and closes it again.
async fn read(session: &Session, room_id: &str, text: &str) -> TestResult {
    let timeline = session.timeline(room_id.to_owned()).await?;
    let mut items = watch_timeline(&timeline).await;
    items
        .wait_paging(&timeline, |items| {
            messages(items).iter().any(|(b, _)| *b == text)
        })
        .await?;
    timeline.mark_as_read().await?;
    Ok(())
}

#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a test homeserver (test-infra/)"]
async fn two_devices_agree_after_one_was_away() -> TestResult {
    let (alice_user, bob_user) = (TestUser::register().await?, TestUser::register().await?);
    let stores = [
        tempfile::tempdir()?,
        tempfile::tempdir()?,
        tempfile::tempdir()?,
    ];
    let a1 = alice_user
        .login(&stores[0].path().to_string_lossy())
        .await?;
    let a2_dir = stores[1].path().to_string_lossy().into_owned();
    let a2 = alice_user.login(&a2_dir).await?;
    let bob = bob_user.login(&stores[2].path().to_string_lossy()).await?;
    for s in [&a1, &a2, &bob] {
        s.start_sync().await;
    }
    let mut a1_rooms = watch_rooms(&a1).await?;
    let mut a2_rooms = watch_rooms(&a2).await?;

    // Bob makes R1..R4 (encrypted) and invites Alice; A1 joins them.
    let mut ids = Vec::new();
    for n in 1..=4 {
        let id = bob
            .create_room(NewRoom {
                name: format!("R{n}"),
                topic: None,
                public: false,
                alias: None,
                encrypted: true,
                avatar: None,
            })
            .await?;
        bob.invite(id.clone(), a1.user_id()).await?;
        ids.push(id);
    }
    for id in &ids {
        a1_rooms
            .wait_until(|l| {
                l.iter()
                    .any(|r| &r.room_id == id && r.membership == Membership::Invited)
            })
            .await?;
        a1.join(id.clone()).await?;
    }
    for rooms in [&mut a1_rooms, &mut a2_rooms] {
        rooms
            .wait_until(|l| {
                ids.iter().all(|id| {
                    l.iter().any(|r| {
                        &r.room_id == id
                            && r.membership == Membership::Joined
                            && r.name.starts_with('R')
                    })
                })
            })
            .await?;
    }
    // Bob's client must know A2's device before it writes, or A2 can't decrypt.
    let alice_id = OwnedUserId::try_from(a1.user_id())?;
    poll_until("Bob knows both of Alice's devices", || async {
        let internal = |e: String| oxitalk_core::api::error::CoreError::Internal { message: e };
        let devices = bob
            .sdk()
            .encryption()
            .get_user_devices(&alice_id)
            .await
            .map_err(|e| internal(e.to_string()))?;
        Ok((devices.devices().count() >= 2).then_some(()))
    })
    .await?;

    // Baseline, both online: A1 reads every room and A2 sees it.
    for (i, id) in ids.iter().enumerate() {
        send(&bob, id, &format!("hello R{}", i + 1)).await?;
    }
    let baseline: Vec<(usize, String)> = (0..4).map(|i| (i, format!("hello R{}", i + 1))).collect();
    let baseline: Vec<(usize, &str)> = baseline.iter().map(|(i, s)| (*i, s.as_str())).collect();
    wait_last(&mut a1_rooms, &ids, &baseline).await?;
    for (i, id) in ids.iter().enumerate() {
        read(&a1, id, &format!("hello R{}", i + 1)).await?;
    }
    agree(
        "baseline (both online)",
        &mut a1_rooms,
        &mut a2_rooms,
        &ids,
        &[
            ("R4", "hello R4", 0),
            ("R3", "hello R3", 0),
            ("R2", "hello R2", 0),
            ("R1", "hello R1", 0),
        ],
    )
    .await?;

    // Scenario 1: A2 stops syncing (app in the background), comes back.
    a2.stop_sync().await;
    for (i, text) in [
        (3, "s1 R4"),
        (2, "s1 R3"),
        (1, "s1 R2 a"),
        (0, "s1 R1"),
        (1, "s1 R2 b"),
    ] {
        send(&bob, &ids[i], text).await?;
    }
    wait_last(
        &mut a1_rooms,
        &ids,
        &[(0, "s1 R1"), (1, "s1 R2 b"), (2, "s1 R3"), (3, "s1 R4")],
    )
    .await?;
    read(&a1, &ids[1], "s1 R2 b").await?;
    read(&a1, &ids[2], "s1 R3").await?;
    send(&a1, &ids[3], "s1 alice R4").await?;
    a2.start_sync().await;
    agree(
        "scenario 1 (sync stopped)",
        &mut a1_rooms,
        &mut a2_rooms,
        &ids,
        &[
            ("R4", "s1 alice R4", 0),
            ("R2", "s1 R2 b", 0),
            ("R1", "s1 R1", 1),
            ("R3", "s1 R3", 0),
        ],
    )
    .await?;

    // Scenario 2: A2's process is closed and opened again from its store.
    let a2_data = a2.session_data()?;
    a2.stop_sync().await;
    drop(a2_rooms);
    drop(a2);
    for (i, text) in [(2, "s2 R3"), (0, "s2 R1"), (1, "s2 R2")] {
        send(&bob, &ids[i], text).await?;
    }
    wait_last(
        &mut a1_rooms,
        &ids,
        &[(0, "s2 R1"), (1, "s2 R2"), (2, "s2 R3")],
    )
    .await?;
    read(&a1, &ids[0], "s2 R1").await?;
    read(&a1, &ids[2], "s2 R3").await?;
    let a2 = restore(a2_data, a2_dir.clone(), PASSPHRASE.to_owned()).await?;
    let mut a2_rooms = watch_rooms(&a2).await?;
    a2.start_sync().await;
    agree(
        "scenario 2 (process closed, restored)",
        &mut a1_rooms,
        &mut a2_rooms,
        &ids,
        &[
            ("R2", "s2 R2", 1),
            ("R1", "s2 R1", 0),
            ("R3", "s2 R3", 0),
            ("R4", "s1 alice R4", 0),
        ],
    )
    .await?;

    // Scenario 3: a long gap, more events than a room's timeline limit.
    a2.stop_sync().await;
    for k in 0..25 {
        send(&bob, &ids[3], &format!("s3 R4 {k}")).await?;
    }
    send(&bob, &ids[2], "s3 R3").await?;
    wait_last(&mut a1_rooms, &ids, &[(3, "s3 R4 24"), (2, "s3 R3")]).await?;
    read(&a1, &ids[3], "s3 R4 24").await?;
    a2.start_sync().await;
    agree(
        "scenario 3 (25 events while away)",
        &mut a1_rooms,
        &mut a2_rooms,
        &ids,
        &[
            ("R3", "s3 R3", 1),
            ("R4", "s3 R4 24", 0),
            ("R2", "s2 R2", 1),
            ("R1", "s2 R1", 0),
        ],
    )
    .await?;

    // Scenario 4: A2's sliding sync position expired while away (long iOS suspension).
    a2.stop_sync().await;
    a2.expire_sync_sessions().await;
    send(&bob, &ids[0], "s4 R1").await?;
    send(&bob, &ids[1], "s4 R2").await?;
    wait_last(&mut a1_rooms, &ids, &[(0, "s4 R1"), (1, "s4 R2")]).await?;
    read(&a1, &ids[1], "s4 R2").await?;
    read(&a1, &ids[2], "s3 R3").await?;
    a2.start_sync().await;
    agree(
        "scenario 4 (sync position expired)",
        &mut a1_rooms,
        &mut a2_rooms,
        &ids,
        &[
            ("R2", "s4 R2", 0),
            ("R1", "s4 R1", 1),
            ("R3", "s3 R3", 0),
            ("R4", "s3 R4 24", 0),
        ],
    )
    .await?;

    // Scenario 5: the gap ends with a reaction after a message, and several messages arrive
    // unread. Without back-pagination A2 kept R2's old latest event (low in the list, old
    // preview, 0 unread) and counted 2 of R1's 4 unread messages.
    a2.stop_sync().await;
    send(&bob, &ids[3], "s5 R4").await?;
    send(&bob, &ids[1], "s5 R2 msg").await?;
    react(&bob, &a1, &ids[1], "s5 R2 msg").await?;
    send(&bob, &ids[2], "s5 R3").await?;
    for text in ["s5 R1 a", "s5 R1 b", "s5 R1 c"] {
        send(&bob, &ids[0], text).await?;
    }
    a2.start_sync().await;
    agree(
        "scenario 5 (gap ends with a reaction; 3 unread)",
        &mut a1_rooms,
        &mut a2_rooms,
        &ids,
        &[
            ("R1", "s5 R1 c", 4),
            ("R3", "s5 R3", 1),
            ("R2", "s5 R2 msg", 1),
            ("R4", "s5 R4", 1),
        ],
    )
    .await?;

    // Scenario 6: an edit of an older message while away. The SDK takes an edit as the room's
    // latest event, with the edit's time, so the room moves up (matrix-rust-sdk #4413) on both
    // devices.
    a2.stop_sync().await;
    send(&bob, &ids[2], "s6 R3").await?;
    edit(&bob, &a1, &ids[3], "s5 R4", "s5 R4 edited").await?;
    a2.start_sync().await;
    agree(
        "scenario 6 (edit while away)",
        &mut a1_rooms,
        &mut a2_rooms,
        &ids,
        &[
            ("R4", "s5 R4 edited", 1),
            ("R3", "s6 R3", 2),
            ("R1", "s5 R1 c", 4),
            ("R2", "s5 R2 msg", 1),
        ],
    )
    .await?;

    // Scenario 7: A1 reads a room while A2 is away, and the gap ends with a reaction after the
    // message A1 read up to. Without back-pagination A2 kept R3 unread with an old preview.
    a2.stop_sync().await;
    send(&bob, &ids[2], "s7 R3 a").await?;
    send(&bob, &ids[2], "s7 R3 b").await?;
    read(&a1, &ids[2], "s7 R3 b").await?;
    react(&bob, &a1, &ids[2], "s7 R3 b").await?;
    send(&bob, &ids[0], "s7 R1").await?;
    a2.start_sync().await;
    agree(
        "scenario 7 (read on A1 while away, gap ends with a reaction)",
        &mut a1_rooms,
        &mut a2_rooms,
        &ids,
        &[
            ("R1", "s7 R1", 5),
            ("R3", "s7 R3 b", 0),
            ("R4", "s5 R4 edited", 1),
            ("R2", "s5 R2 msg", 1),
        ],
    )
    .await
}

/// The message `text` in a timeline: its event ID and its reactions.
fn message<'a>(items: &'a [TimelineItem], text: &str) -> Option<(&'a str, usize)> {
    items.iter().find_map(|item| match &item.content {
        TimelineItemContent::Message { event, body, .. } if body == text => event
            .event_id
            .as_deref()
            .map(|id| (id, event.reactions.len())),
        _ => None,
    })
}

/// The event ID of the message `text` in the room, as `session` sees it.
async fn event_id(session: &Session, room_id: &str, text: &str) -> Result<String, Box<dyn Error>> {
    let timeline = session.timeline(room_id.to_owned()).await?;
    let mut items = watch_timeline(&timeline).await;
    items
        .wait_paging(&timeline, |items| message(items, text).is_some())
        .await?;
    Ok(message(&items.items, text)
        .ok_or("no event ID")?
        .0
        .to_owned())
}

/// `session` reacts to the message `text`; returns once `observer`, another user's device,
/// sees the reaction, so the server has it.
async fn react(session: &Session, observer: &Session, room_id: &str, text: &str) -> TestResult {
    let id = event_id(session, room_id, text).await?;
    session
        .timeline(room_id.to_owned())
        .await?
        .toggle_reaction(id, "👍".to_owned())
        .await?;
    let timeline = observer.timeline(room_id.to_owned()).await?;
    let mut items = watch_timeline(&timeline).await;
    items
        .wait_paging(&timeline, |items| {
            message(items, text).is_some_and(|(_, reactions)| reactions > 0)
        })
        .await
}

/// `session` edits the message `text` to `new`; returns once `observer`, another user's
/// device, sees the edit, so the server has it.
async fn edit(
    session: &Session,
    observer: &Session,
    room_id: &str,
    text: &str,
    new: &str,
) -> TestResult {
    let id = event_id(session, room_id, text).await?;
    session
        .timeline(room_id.to_owned())
        .await?
        .edit(id, new.to_owned(), false, false)
        .await?;
    let timeline = observer.timeline(room_id.to_owned()).await?;
    let mut items = watch_timeline(&timeline).await;
    items
        .wait_paging(&timeline, |items| {
            messages(items).iter().any(|(b, _)| *b == new)
        })
        .await
}
