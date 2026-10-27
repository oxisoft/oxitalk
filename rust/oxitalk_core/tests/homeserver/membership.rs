//! Leaving rooms, declining invitations, what an invitation shows, and the room events the
//! timeline shows as notices, on the test homeserver.

use std::error::Error;

use matrix_sdk::ruma::{
    OwnedRoomId,
    events::room::message::{LocationMessageEventContent, MessageType, RoomMessageEventContent},
};
use oxitalk_core::api::{
    notices::{MembershipKind, PowerLevelChange, RoomNotice},
    room_list::Membership,
    rooms::NewRoom,
    session::Session,
    timeline::{TimelineItem, TimelineItemContent},
};

use super::{TIMEOUT, TestResult, TestUser, poll_until, watch_rooms, watch_timeline};

/// Two logged-in, syncing users, Alice with a display name.
async fn two_users() -> Result<(Session, Session, Vec<tempfile::TempDir>), Box<dyn Error>> {
    let (alice_user, bob_user) = (TestUser::register().await?, TestUser::register().await?);
    let stores = vec![tempfile::tempdir()?, tempfile::tempdir()?];
    let alice = alice_user
        .login(&stores[0].path().to_string_lossy())
        .await?;
    let bob = bob_user.login(&stores[1].path().to_string_lossy()).await?;
    alice
        .sdk()
        .account()
        .set_display_name(Some("Alice"))
        .await?;
    alice.start_sync().await;
    bob.start_sync().await;
    Ok((alice, bob, stores))
}

async fn private_room(session: &Session, name: &str) -> Result<String, Box<dyn Error>> {
    Ok(session
        .create_room(NewRoom {
            name: name.to_owned(),
            topic: Some("Where the team talks".to_owned()),
            public: false,
            alias: None,
            encrypted: true,
            avatar: None,
        })
        .await?)
}

/// Waits until `session`'s room list has `room` as `membership`, or without it for `None`.
async fn wait_for_room(
    session: &Session,
    room: &str,
    membership: Option<Membership>,
) -> TestResult {
    let mut rooms = watch_rooms(session).await?;
    rooms
        .wait_until(|rooms| {
            let found = rooms.iter().find(|r| r.room_id == room);
            found.map(|r| r.membership) == membership
        })
        .await
}

/// An invitation shows the room and who sent it; declining drops it from the list, and a new
/// one can be accepted.
#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a test homeserver (test-infra/)"]
async fn invitations_show_who_invited_and_are_declined_or_accepted() -> TestResult {
    let (alice, bob, _stores) = two_users().await?;
    let room = private_room(&alice, "Team").await?;
    alice.invite(room.clone(), bob.user_id()).await?;
    wait_for_room(&bob, &room, Some(Membership::Invited)).await?;

    let details = poll_until("the invitation has its name", || async {
        // Without the inviter until the invitation's member event is stored.
        let details = bob.invite_details(room.clone()).await?;
        Ok((details.name == "Team" && details.inviter_id.is_some()).then_some(details))
    })
    .await?;
    assert_eq!(details.room_id, room);
    assert_eq!(details.topic.as_deref(), Some("Where the team talks"));
    assert!(!details.is_dm);
    assert_eq!(details.inviter_id, Some(alice.user_id()));
    assert_eq!(details.inviter_name.as_deref(), Some("Alice"));
    // Only for an invited room.
    assert!(alice.invite_details(room.clone()).await.is_err());

    bob.leave(room.clone()).await?;
    wait_for_room(&bob, &room, None).await?;
    // Alice sees the invitation declined.
    let alice_timeline = alice.timeline(room.clone()).await?;
    let mut items = watch_timeline(&alice_timeline).await;
    items
        .wait_until(|items| {
            membership_of(items, &bob.user_id()).contains(&MembershipKind::InviteDeclined)
        })
        .await?;

    // Asked again, Bob accepts.
    alice.invite(room.clone(), bob.user_id()).await?;
    wait_for_room(&bob, &room, Some(Membership::Invited)).await?;
    bob.join(room.clone()).await?;
    wait_for_room(&bob, &room, Some(Membership::Joined)).await?;
    items
        .wait_until(|items| {
            membership_of(items, &bob.user_id()).contains(&MembershipKind::InviteAccepted)
        })
        .await?;

    // A direct chat's invitation says so, with the inviter's name as its name.
    let dm = alice.create_dm(bob.user_id()).await?;
    wait_for_room(&bob, &dm, Some(Membership::Invited)).await?;
    let details = poll_until("the DM invitation has the inviter", || async {
        let details = bob.invite_details(dm.clone()).await?;
        Ok(details.inviter_name.is_some().then_some(details))
    })
    .await?;
    assert!(details.is_dm);
    assert_eq!(details.name, "Alice");
    assert_eq!(details.inviter_id, Some(alice.user_id()));
    Ok(())
}

/// Leaving tells what it costs first, then drops the room from the list; the others see it.
#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a test homeserver (test-infra/)"]
async fn leaving_warns_first_and_drops_the_room() -> TestResult {
    let (alice, bob, _stores) = two_users().await?;
    let room = private_room(&alice, "Staff").await?;
    let alone = poll_until("Alice's power levels are in her store", || async {
        let info = alice.leave_info(room.clone()).await?;
        Ok(info.only_member.then_some(info))
    })
    .await?;
    // Alone, she isn't the last admin of anyone.
    assert!(alone.needs_invite_to_rejoin && !alone.last_admin && !alone.is_dm);

    alice.invite(room.clone(), bob.user_id()).await?;
    wait_for_room(&bob, &room, Some(Membership::Invited)).await?;
    bob.join(room.clone()).await?;
    let info = poll_until("Alice sees Bob joined", || async {
        let info = alice.leave_info(room.clone()).await?;
        Ok((!info.only_member).then_some(info))
    })
    .await?;
    assert!(info.last_admin, "{info:?}");
    assert!(info.needs_invite_to_rejoin);
    // Bob's store gets the room's members and power levels with his next syncs.
    let bob_info = poll_until("Bob sees Alice in the room", || async {
        let info = bob.leave_info(room.clone()).await?;
        Ok((!info.only_member).then_some(info))
    })
    .await?;
    assert!(!bob_info.last_admin && !bob_info.only_member);

    // Bob as a second admin: Alice is no longer the last one.
    alice
        .set_power_level(room.clone(), bob.user_id(), 100)
        .await?;
    poll_until("Bob is an admin too", || async {
        let info = alice.leave_info(room.clone()).await?;
        Ok((!info.last_admin).then_some(()))
    })
    .await?;

    let alice_timeline = alice.timeline(room.clone()).await?;
    let mut items = watch_timeline(&alice_timeline).await;
    bob.leave(room.clone()).await?;
    wait_for_room(&bob, &room, None).await?;
    items
        .wait_until(|items| membership_of(items, &bob.user_id()).contains(&MembershipKind::Left))
        .await?;
    // Leaving again is nothing.
    bob.leave(room.clone()).await?;
    Ok(())
}

/// Membership, profile and room changes, and a location, show as notices with who did what.
#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a test homeserver (test-infra/)"]
async fn room_events_show_as_notices() -> TestResult {
    let (alice, bob, _stores) = two_users().await?;
    let room = private_room(&alice, "Notices").await?;
    alice.invite(room.clone(), bob.user_id()).await?;
    wait_for_room(&bob, &room, Some(Membership::Invited)).await?;
    bob.join(room.clone()).await?;
    wait_for_room(&bob, &room, Some(Membership::Joined)).await?;

    let room_id = OwnedRoomId::try_from(room.as_str())?;
    let sdk_room = poll_until("Alice has the room", || async {
        Ok(alice.sdk().get_room(&room_id))
    })
    .await?;
    sdk_room.set_name("Renamed".to_owned()).await?;
    sdk_room.set_room_topic("New topic").await?;
    alice
        .set_power_level(room.clone(), bob.user_id(), 50)
        .await?;
    bob.sdk().account().set_display_name(Some("Bobby")).await?;
    sdk_room
        .send(RoomMessageEventContent::new(MessageType::Location(
            LocationMessageEventContent::new("The office".to_owned(), "geo:52.23,21.01".to_owned()),
        )))
        .await?;
    alice
        .remove_member(room.clone(), bob.user_id(), Some("testing".to_owned()))
        .await?;

    let timeline = alice.timeline(room.clone()).await?;
    let mut items = watch_timeline(&timeline).await;
    let bob_id = bob.user_id();
    let wanted = |items: &[TimelineItem]| {
        let notices = notices(items);
        let has = |f: &dyn Fn(&RoomNotice) -> bool| notices.iter().any(|(_, n)| f(n));
        has(&|n| matches!(n, RoomNotice::RoomCreated))
            && has(
                &|n| matches!(n, RoomNotice::RoomName { name } if name.as_deref() == Some("Renamed")),
            )
            && has(
                &|n| matches!(n, RoomNotice::RoomTopic { topic } if topic.as_deref() == Some("New topic")),
            )
            && has(&|n| matches!(n, RoomNotice::EncryptionEnabled))
            && has(&|n| matches!(n, RoomNotice::Location { body } if body == "The office"))
            && has(
                &|n| matches!(n, RoomNotice::PowerLevels { changes } if changes == &[PowerLevelChange { user_id: bob_id.clone(), old_level: 0, new_level: 50 }]),
            )
            && has(
                &|n| matches!(n, RoomNotice::Profile { user_id, new_name, name_changed: true, .. } if user_id == &bob_id && new_name.as_deref() == Some("Bobby")),
            )
            && has(
                &|n| matches!(n, RoomNotice::Membership { user_id, change: MembershipKind::Invited, user_is_own: false, .. } if user_id == &bob_id),
            )
            && has(
                &|n| matches!(n, RoomNotice::Membership { user_id, change: MembershipKind::InviteAccepted, .. } if user_id == &bob_id),
            )
            && has(
                &|n| matches!(n, RoomNotice::Membership { user_id, change: MembershipKind::Kicked, reason, .. } if user_id == &bob_id && reason.as_deref() == Some("testing")),
            )
    };
    tokio::time::timeout(TIMEOUT, async {
        while !items
            .holds_within(std::time::Duration::from_secs(1), wanted)
            .await?
        {
            timeline.paginate_back(50).await?;
        }
        Ok::<_, Box<dyn Error>>(())
    })
    .await
    .map_err(|_| format!("timed out; notices: {:#?}", notices(&items.items)))??;

    let notices = notices(&items.items);
    // Alice's own: created, joined (her own), sent by her.
    assert!(notices.iter().any(|(own, n)| *own
        && matches!(
            n,
            RoomNotice::Membership {
                change: MembershipKind::Joined,
                user_is_own: true,
                ..
            }
        )));
    // The room's first settings aren't told: just one power levels notice, Bob's.
    assert_eq!(
        notices
            .iter()
            .filter(|(_, n)| matches!(n, RoomNotice::PowerLevels { .. }))
            .count(),
        1,
        "{notices:#?}"
    );
    assert!(
        !notices.iter().any(|(_, n)| matches!(
            n,
            RoomNotice::JoinRules { .. } | RoomNotice::HistoryVisibility { .. }
        )),
        "{notices:#?}"
    );
    Ok(())
}

/// The membership changes of `user` in `items`, oldest first.
fn membership_of(items: &[TimelineItem], user: &str) -> Vec<MembershipKind> {
    notices(items)
        .into_iter()
        .filter_map(|(_, notice)| match notice {
            RoomNotice::Membership {
                user_id, change, ..
            } if user_id == user => Some(change),
            _ => None,
        })
        .collect()
}

/// The notices in `items`, with whether the user sent each.
fn notices(items: &[TimelineItem]) -> Vec<(bool, RoomNotice)> {
    items
        .iter()
        .filter_map(|item| match &item.content {
            TimelineItemContent::Notice { event, notice } => Some((event.is_own, notice.clone())),
            _ => None,
        })
        .collect()
}
