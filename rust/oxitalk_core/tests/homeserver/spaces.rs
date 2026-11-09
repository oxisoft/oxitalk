//! Spaces on the test homeserver: a space made with a room in it, joined by another user,
//! browsed, the room joined from it, and the space left with the room.

use futures_util::StreamExt;
use matrix_sdk::ruma::{
    OwnedRoomId, OwnedServerName,
    api::client::room::create_room::v3::{
        CreationContent, Request as CreateRoomRequest, RoomPreset,
    },
    events::space::child::SpaceChildEventContent,
    room::RoomType,
    serde::Raw,
};
use oxitalk_core::api::{rooms::NewRoom, session::Session, spaces::SpaceSummary};

use super::{TestResult, TestUser, poll_until, watch_rooms};

/// The session's spaces as they are now.
async fn spaces_now(session: &Session) -> Vec<SpaceSummary> {
    session
        .spaces_updates()
        .await
        .next()
        .await
        .unwrap_or_default()
}

#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a test homeserver (test-infra/)"]
async fn a_space_is_joined_browsed_and_left_with_its_rooms() -> TestResult {
    let (alice_user, bob_user) = (TestUser::register().await?, TestUser::register().await?);
    let (alice_store, bob_store) = (tempfile::tempdir()?, tempfile::tempdir()?);
    let alice = alice_user
        .login(&alice_store.path().to_string_lossy())
        .await?;
    let bob = bob_user.login(&bob_store.path().to_string_lossy()).await?;
    alice.start_sync().await;
    bob.start_sync().await;

    let mut request = CreateRoomRequest::new();
    request.name = Some("Acme".to_owned());
    request.preset = Some(RoomPreset::PublicChat);
    let mut creation = CreationContent::new();
    creation.room_type = Some(RoomType::Space);
    request.creation_content = Some(Raw::new(&creation)?);
    let space = alice.sdk().create_room(request).await?;
    let room_id = alice
        .create_room(NewRoom {
            name: "Lobby".to_owned(),
            topic: None,
            public: true,
            alias: None,
            encrypted: false,
            avatar: None,
        })
        .await?;
    let server: OwnedServerName = alice
        .sdk()
        .user_id()
        .ok_or("no user")?
        .server_name()
        .to_owned();
    let child: OwnedRoomId = room_id.as_str().try_into()?;
    space
        .send_state_event_for_key(&child, SpaceChildEventContent::new(vec![server]))
        .await?;
    let space_id = space.room_id().to_string();

    // Bob joins the space: it shows as a space in his room list and as his one space, with
    // no rooms yet.
    let mut bob_rooms = watch_rooms(&bob).await?;
    bob.join(space_id.clone()).await?;
    bob_rooms
        .wait_until(|rooms| rooms.iter().any(|r| r.room_id == space_id && r.is_space))
        .await?;
    poll_until("Bob has the space, empty", || async {
        let spaces = spaces_now(&bob).await;
        Ok(
            (spaces.len() == 1 && spaces[0].space_id == space_id && spaces[0].room_ids.is_empty())
                .then_some(()),
        )
    })
    .await?;

    // Browsing it lists the room, not joined, with a server to join through.
    let children = bob.space_children(space_id.clone()).await?;
    let lobby = children
        .iter()
        .find(|c| c.room_id == room_id)
        .ok_or("the room isn't in the space's children")?;
    assert!(!lobby.joined);
    assert_eq!(lobby.name, "Lobby");
    let via = lobby.via.first().ok_or("no server to join through")?;
    bob.join_by_address(format!("https://matrix.to/#/{room_id}?via={via}"))
        .await?;
    poll_until("the joined room is in Bob's space", || async {
        let spaces = spaces_now(&bob).await;
        Ok(spaces
            .first()
            .is_some_and(|s| s.room_ids.contains(&room_id))
            .then_some(()))
    })
    .await?;

    // Leaving the space offers the room; leaving with it leaves both.
    let preview = bob.leave_space_preview(space_id.clone()).await?;
    assert_eq!(
        preview
            .iter()
            .map(|r| r.room_id.as_str())
            .collect::<Vec<_>>(),
        [room_id.as_str()]
    );
    bob.leave_space(space_id.clone(), vec![room_id.clone()])
        .await?;
    bob_rooms
        .wait_until(|rooms| {
            !rooms
                .iter()
                .any(|r| r.room_id == space_id || r.room_id == room_id)
        })
        .await?;
    poll_until("Bob has no space left", || async {
        Ok(spaces_now(&bob).await.is_empty().then_some(()))
    })
    .await?;
    Ok(())
}
