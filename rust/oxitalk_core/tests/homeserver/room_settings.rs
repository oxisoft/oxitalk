//! Room settings (name, topic, picture, who can join and read, encryption, the main address
//! and the room directory) on the test homeserver.

use std::error::Error;

use oxitalk_core::api::{
    error::CoreError,
    room_settings::{RoomHistory, RoomJoinRule, RoomSettings},
    rooms::NewRoom,
    session::Session,
};
use tokio::sync::mpsc;

use super::{AVATAR_PNG, TIMEOUT, TestResult, TestUser, poll_until, watch_rooms};

fn watch_settings(
    session: &Session,
    room_id: &str,
) -> Result<mpsc::UnboundedReceiver<RoomSettings>, CoreError> {
    let (sender, states) = mpsc::unbounded_channel();
    session.room_settings_updates(room_id.to_owned(), move |settings| {
        sender.send(settings).is_ok()
    })?;
    Ok(states)
}

async fn wait_for_settings(
    states: &mut mpsc::UnboundedReceiver<RoomSettings>,
    what: &str,
    done: impl Fn(&RoomSettings) -> bool,
) -> Result<RoomSettings, Box<dyn Error>> {
    tokio::time::timeout(TIMEOUT, async {
        while let Some(state) = states.recv().await {
            if done(&state) {
                return Ok(state);
            }
        }
        Err("the settings stream ended".into())
    })
    .await
    .map_err(|_| format!("timed out waiting until {what}"))?
}

async fn signed_in(user: &TestUser, store: &tempfile::TempDir) -> Result<Session, CoreError> {
    let session = user.login(&store.path().to_string_lossy()).await?;
    session.start_sync().await;
    Ok(session)
}

fn new_room(name: &str, public: bool, alias: Option<String>) -> NewRoom {
    NewRoom {
        name: name.to_owned(),
        topic: None,
        public,
        alias,
        encrypted: false,
        avatar: None,
    }
}

/// Alice edits the name, topic and picture; Bob sees each change arrive and, as a plain
/// member, may change none of them until Alice makes him a moderator, which his settings
/// show by themselves.
#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a test homeserver (test-infra/)"]
async fn room_details_are_edited_and_power_levels_gate_them() -> TestResult {
    let (alice_user, bob_user) = (TestUser::register().await?, TestUser::register().await?);
    let (alice_store, bob_store) = (tempfile::tempdir()?, tempfile::tempdir()?);
    let alice = signed_in(&alice_user, &alice_store).await?;
    let bob = signed_in(&bob_user, &bob_store).await?;

    let room = alice.create_room(new_room("Before", false, None)).await?;
    alice.invite(room.clone(), bob.user_id()).await?;
    let mut bob_rooms = watch_rooms(&bob).await?;
    bob_rooms
        .wait_until(|rooms| rooms.iter().any(|r| r.room_id == room))
        .await?;
    bob.join(room.clone()).await?;
    let mut bob_states = watch_settings(&bob, &room)?;
    let first = wait_for_settings(&mut bob_states, "Bob has the room", |s| {
        s.name.as_deref() == Some("Before")
    })
    .await?;
    assert!(!first.permissions.name && !first.permissions.topic && !first.permissions.avatar);
    assert!(!first.permissions.history && !first.permissions.encryption);
    assert_eq!(first.join_rule, RoomJoinRule::Invite);
    assert!(first.is_encrypted, "a private room is encrypted");
    assert!(matches!(
        bob.set_room_name(room.clone(), "Bob's".to_owned()).await,
        Err(CoreError::Forbidden { .. })
    ));

    // Alice's own settings: the room's power levels reach her store with a sync.
    let mut alice_states = watch_settings(&alice, &room)?;
    let alice_settings =
        wait_for_settings(&mut alice_states, "Alice may edit", |s| s.permissions.name).await?;
    assert!(alice_settings.permissions.name && alice_settings.permissions.encryption);
    assert_eq!(alice_settings.server_name, "localhost");

    alice
        .set_room_name(room.clone(), "  After  ".to_owned())
        .await?;
    alice
        .set_room_topic(room.clone(), "What we talk about".to_owned())
        .await?;
    alice
        .set_room_avatar(room.clone(), AVATAR_PNG.to_vec(), "image/png".to_owned())
        .await?;
    let edited = wait_for_settings(&mut bob_states, "Bob sees the edits", |s| {
        s.name.as_deref() == Some("After")
            && s.topic.as_deref() == Some("What we talk about")
            && s.avatar_url.is_some()
    })
    .await?;
    assert!(
        edited
            .avatar_url
            .is_some_and(|url| url.starts_with("mxc://"))
    );
    // The info header follows too. The SDK works the display name out after it has announced
    // the room's new state, so it can lag the settings by a moment.
    let details = poll_until("Bob's info header has the new name", || async {
        let details = bob.room_details(room.clone()).await?;
        Ok((details.name == "After").then_some(details))
    })
    .await?;
    assert_eq!(details.name, "After");

    alice.remove_room_avatar(room.clone()).await?;
    alice.set_room_topic(room.clone(), String::new()).await?;
    wait_for_settings(&mut bob_states, "the picture and topic are gone", |s| {
        s.avatar_url.is_none() && s.topic.is_none()
    })
    .await?;

    alice
        .set_power_level(room.clone(), bob.user_id(), 50)
        .await?;
    let moderator = wait_for_settings(&mut bob_states, "Bob may edit the name", |s| {
        s.permissions.name
    })
    .await?;
    // A moderator may send what Synapse's defaults ask 50 for (name, topic, picture,
    // address, and join rules by the state default), not what they ask 100 for (history,
    // encryption).
    assert!(moderator.permissions.topic && moderator.permissions.avatar);
    assert!(moderator.permissions.address && moderator.permissions.join_rule);
    assert!(!moderator.permissions.history && !moderator.permissions.encryption);
    bob.set_room_name(room.clone(), "Bob's".to_owned()).await?;
    wait_for_settings(&mut alice_states, "Alice sees Bob's name", |s| {
        s.name.as_deref() == Some("Bob's")
    })
    .await?;
    Ok(())
}

/// Who can join and read, and encryption: each change shows in the settings; leaving
/// "anyone", a history anyone could read becomes the members'; encryption turned on stays.
#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a test homeserver (test-infra/)"]
async fn join_rule_history_and_encryption_are_changed() -> TestResult {
    let alice_user = TestUser::register().await?;
    let alice_store = tempfile::tempdir()?;
    let alice = signed_in(&alice_user, &alice_store).await?;
    let room = alice.create_room(new_room("Open", true, None)).await?;
    let mut states = watch_settings(&alice, &room)?;
    let first = wait_for_settings(&mut states, "the room is public", |s| {
        s.join_rule == RoomJoinRule::Public
    })
    .await?;
    assert!(!first.is_encrypted);
    assert!(
        first.knock_supported,
        "the server's default room version knocks"
    );

    alice
        .set_room_history(room.clone(), RoomHistory::WorldReadable)
        .await?;
    wait_for_settings(&mut states, "anyone can read", |s| {
        s.history == RoomHistory::WorldReadable
    })
    .await?;

    alice
        .set_room_join_rule(room.clone(), RoomJoinRule::Knock)
        .await?;
    let knock = wait_for_settings(&mut states, "people ask to join", |s| {
        s.join_rule == RoomJoinRule::Knock && s.history == RoomHistory::Shared
    })
    .await?;
    assert_eq!(knock.history, RoomHistory::Shared);

    alice
        .set_room_join_rule(room.clone(), RoomJoinRule::Invite)
        .await?;
    alice
        .set_room_history(room.clone(), RoomHistory::Joined)
        .await?;
    wait_for_settings(&mut states, "invite only, members since they joined", |s| {
        s.join_rule == RoomJoinRule::Invite && s.history == RoomHistory::Joined
    })
    .await?;
    alice
        .set_room_history(room.clone(), RoomHistory::Invited)
        .await?;
    wait_for_settings(&mut states, "members since they were invited", |s| {
        s.history == RoomHistory::Invited
    })
    .await?;
    assert!(matches!(
        alice
            .set_room_join_rule(room.clone(), RoomJoinRule::Restricted)
            .await,
        Err(CoreError::Internal { .. })
    ));

    alice.enable_room_encryption(room.clone()).await?;
    wait_for_settings(&mut states, "the room is encrypted", |s| s.is_encrypted).await?;
    assert!(alice.room_details(room.clone()).await?.is_encrypted);
    Ok(())
}

/// A public room gets a new main address on the user's server; one another room has is
/// refused, a malformed one too; and the room is taken out of the directory and put back.
#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a test homeserver (test-infra/)"]
async fn the_main_address_and_directory_listing_are_changed() -> TestResult {
    let alice_user = TestUser::register().await?;
    let alice_store = tempfile::tempdir()?;
    let alice = signed_in(&alice_user, &alice_store).await?;
    let first_alias = format!("first{}", alice_user.name);
    let room = alice
        .create_room(new_room("Listed", true, Some(first_alias.clone())))
        .await?;
    let other = alice
        .create_room(new_room(
            "Other",
            true,
            Some(format!("other{}", alice_user.name)),
        ))
        .await?;
    let mut states = watch_settings(&alice, &room)?;
    wait_for_settings(&mut states, "the first address", |s| {
        s.main_address.as_deref() == Some(format!("#{first_alias}:localhost").as_str())
    })
    .await?;

    let new_alias = format!("new{}", alice_user.name);
    assert!(
        alice
            .set_room_main_address(room.clone(), format!(" #{new_alias} "))
            .await?
    );
    wait_for_settings(&mut states, "the new address", |s| {
        s.main_address.as_deref() == Some(format!("#{new_alias}:localhost").as_str())
    })
    .await?;
    // The earlier address still leads to the room.
    let joined_by = alice
        .join_by_address(format!("#{first_alias}:localhost"))
        .await?;
    assert_eq!(joined_by, room);
    // Setting it again is fine: it is this room's.
    assert!(
        alice
            .set_room_main_address(room.clone(), first_alias.clone())
            .await?
    );
    // Another room's address is refused, and nothing changes there.
    assert!(
        !alice
            .set_room_main_address(other.clone(), new_alias.clone())
            .await?
    );
    assert!(matches!(
        alice
            .set_room_main_address(room.clone(), "two words".to_owned())
            .await,
        Err(CoreError::InvalidId { .. })
    ));

    // The app lists a new public room, as Element does.
    assert!(alice.room_published(room.clone()).await?);
    alice.set_room_published(room.clone(), false).await?;
    assert!(!alice.room_published(room.clone()).await?);
    alice.set_room_published(room.clone(), true).await?;
    let listed = poll_until("the room is listed again", || async {
        Ok(alice.room_published(room.clone()).await?.then_some(()))
    })
    .await;
    listed?;
    Ok(())
}
