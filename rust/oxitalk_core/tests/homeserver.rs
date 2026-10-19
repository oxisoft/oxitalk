//! Tests against the Synapse test homeserver in `test-infra/`. They are ignored by a plain
//! `cargo test`; `scripts/ci.sh` starts the server and runs them with `--ignored`.

// The futures of matrix-sdk-ui (the timeline in particular) are deeply nested.
#![recursion_limit = "256"]

mod support;

use std::{
    error::Error,
    sync::Arc,
    time::{SystemTime, UNIX_EPOCH},
};

use futures_util::{Stream, StreamExt};

use matrix_sdk::{
    Client,
    ruma::{
        api::client::{account::register::v3::Request as RegistrationRequest, uiaa},
        serde::Raw,
    },
};
use oxitalk_core::api::{
    error::CoreError,
    init_app,
    room_list::Membership,
    sections::{CustomSection, RoomTags, SectionSettings, SectionsUpdate},
    session::{Session, login, restore},
    timeline::{SendState, TimelineItemContent},
    verification::{Verification, VerificationFlowState, VerificationStatus},
};
use serde_json::json;
use support::{TIMEOUT, TestResult, messages, watch_rooms, watch_timeline};
use tokio::sync::mpsc;

const PASSPHRASE: &str = "store passphrase";

/// A 64×64 PNG.
const AVATAR_PNG: &[u8] = include_bytes!("support/avatar.png");

/// `OXITALK_TEST_HOMESERVER`, or the port `test-infra/compose.yaml` publishes.
fn homeserver_url() -> String {
    std::env::var("OXITALK_TEST_HOMESERVER").unwrap_or_else(|_| "http://localhost:8008".to_owned())
}

/// A freshly registered user. Registration isn't part of the app; the test uses the SDK for it.
struct TestUser {
    name: String,
    password: String,
}

impl TestUser {
    async fn register() -> Result<Self, Box<dyn Error>> {
        init_app();
        // A name no earlier run has taken: the server keeps its data until `compose down -v`.
        let nanos = SystemTime::now().duration_since(UNIX_EPOCH)?.as_nanos();
        let name = format!("user{nanos}");
        let password = format!("{name}-password");

        let mut request = RegistrationRequest::new();
        request.username = Some(name.clone());
        request.password = Some(password.clone());
        request.auth = Some(uiaa::AuthData::Dummy(uiaa::Dummy::new()));
        let client = Client::builder()
            .homeserver_url(homeserver_url())
            .build()
            .await?;
        client.matrix_auth().register(request).await?;
        Ok(Self { name, password })
    }

    async fn login(&self, store_dir: &str) -> Result<Session, CoreError> {
        login(
            homeserver_url(),
            self.name.clone(),
            self.password.clone(),
            store_dir.to_owned(),
            PASSPHRASE.to_owned(),
        )
        .await
    }
}

#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs the Synapse test homeserver (test-infra/)"]
async fn logs_in_and_rejects_a_wrong_password() -> TestResult {
    let user = TestUser::register().await?;
    let store = tempfile::tempdir()?;

    let wrong = TestUser {
        name: user.name.clone(),
        password: "wrong".to_owned(),
    };
    let error = wrong.login(&store.path().to_string_lossy()).await.err();
    assert!(
        matches!(error, Some(CoreError::Forbidden { .. })),
        "{error:?}"
    );

    let session = user.login(&store.path().to_string_lossy()).await?;
    assert_eq!(session.user_id(), format!("@{}:localhost", user.name));
    Ok(())
}

/// The M0.3 exit test: an encrypted DM in both directions, then one side restarts on its store.
#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs the Synapse test homeserver (test-infra/)"]
async fn encrypted_dm_both_ways_and_after_a_restore() -> TestResult {
    let (alice_user, bob_user) = (TestUser::register().await?, TestUser::register().await?);
    let (alice_store, bob_store) = (tempfile::tempdir()?, tempfile::tempdir()?);
    let bob_store_dir = bob_store.path().to_string_lossy().into_owned();
    let alice = alice_user
        .login(&alice_store.path().to_string_lossy())
        .await?;
    let bob = bob_user.login(&bob_store_dir).await?;
    alice.start_sync().await;
    bob.start_sync().await;

    // Alice opens a DM; Bob sees the invite and joins.
    let room_id = alice.create_dm(bob.user_id()).await?;
    let mut bob_rooms = watch_rooms(&bob).await?;
    bob_rooms
        .wait_until(|rooms| {
            rooms
                .iter()
                .any(|r| r.room_id == room_id && r.membership == Membership::Invited)
        })
        .await?;
    bob.join(room_id.clone()).await?;
    bob_rooms
        .wait_until(|rooms| {
            rooms.iter().any(|r| {
                r.room_id == room_id && r.membership == Membership::Joined && r.is_encrypted
            })
        })
        .await?;

    // Alice → Bob, Bob → Alice.
    let alice_timeline = alice.timeline(room_id.clone()).await?;
    let mut alice_items = watch_timeline(&alice_timeline).await;
    let bob_timeline = bob.timeline(room_id.clone()).await?;
    let mut bob_items = watch_timeline(&bob_timeline).await;

    alice_timeline.send_text("hello Bob".to_owned()).await?;
    bob_items
        .wait_until(|items| messages(items).contains(&("hello Bob", false)))
        .await?;
    bob_timeline.send_text("hello Alice".to_owned()).await?;
    alice_items
        .wait_until(|items| messages(items).contains(&("hello Alice", false)))
        .await?;
    alice_items
        .wait_until(|items| {
            items.iter().any(|item| {
                matches!(&item.content, TimelineItemContent::Message { event, body }
                    if body == "hello Bob" && event.is_own && event.send_state == SendState::Sent)
            })
        })
        .await?;

    // Bob quits: the app keeps only the session data and its store.
    let bob_data = bob.session_data()?;
    bob.stop_sync().await;
    drop((bob_items, bob_timeline, bob_rooms, bob));

    let wrong = restore(bob_data.clone(), bob_store_dir.clone(), "wrong".to_owned()).await;
    assert_eq!(wrong.err(), Some(CoreError::WrongStorePassphrase));

    // Bob restarts: the old messages still decrypt, and new ones arrive.
    let bob = restore(bob_data, bob_store_dir, PASSPHRASE.to_owned()).await?;
    bob.start_sync().await;
    let bob_timeline = bob.timeline(room_id).await?;
    let mut bob_items = watch_timeline(&bob_timeline).await;
    bob_timeline.paginate_back(20).await?;
    bob_items
        .wait_until(|items| {
            let messages = messages(items);
            messages.contains(&("hello Bob", false)) && messages.contains(&("hello Alice", true))
        })
        .await?;

    alice_timeline
        .send_text("after the restart".to_owned())
        .await?;
    bob_items
        .wait_until(|items| messages(items).contains(&("after the restart", false)))
        .await?;
    Ok(())
}

/// A new device of an account is verified by an existing one, comparing emoji.
/// A profile picture shows on the user's DM in the other side's room list and on their
/// messages, and downloads as a thumbnail.
#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs the Synapse test homeserver (test-infra/)"]
async fn profile_pictures_show_on_dms_and_messages() -> TestResult {
    let (alice_user, bob_user) = (TestUser::register().await?, TestUser::register().await?);
    let (alice_store, bob_store) = (tempfile::tempdir()?, tempfile::tempdir()?);
    let alice = alice_user
        .login(&alice_store.path().to_string_lossy())
        .await?;
    let bob = bob_user.login(&bob_store.path().to_string_lossy()).await?;

    assert_eq!(alice.own_profile().await?.avatar_url, None);
    alice
        .set_avatar(AVATAR_PNG.to_vec(), "image/png".to_owned())
        .await?;
    let avatar = alice
        .own_profile()
        .await?
        .avatar_url
        .ok_or("no avatar after setting one")?;
    let thumbnail = bob.thumbnail(avatar.clone(), 64).await?;
    assert!(thumbnail.starts_with(b"\x89PNG") || thumbnail.starts_with(b"\xff\xd8"));
    assert!(matches!(
        bob.thumbnail("not an mxc".to_owned(), 64).await,
        Err(CoreError::InvalidId { .. })
    ));

    alice.start_sync().await;
    bob.start_sync().await;
    let room_id = alice.create_dm(bob.user_id()).await?;
    let mut bob_rooms = watch_rooms(&bob).await?;
    bob_rooms
        .wait_until(|rooms| rooms.iter().any(|r| r.room_id == room_id))
        .await?;
    bob.join(room_id.clone()).await?;
    bob_rooms
        .wait_until(|rooms| {
            rooms.iter().any(|r| {
                r.room_id == room_id
                    && r.membership == Membership::Joined
                    && r.avatar_url.as_ref() == Some(&avatar)
            })
        })
        .await?;

    let alice_timeline = alice.timeline(room_id.clone()).await?;
    alice_timeline.send_text("look at me".to_owned()).await?;
    let bob_timeline = bob.timeline(room_id).await?;
    let mut bob_items = watch_timeline(&bob_timeline).await;
    bob_items
        .wait_until(|items| {
            items.iter().any(|item| {
                matches!(&item.content, TimelineItemContent::Message { event, body }
                    if body == "look at me" && event.sender_avatar_url.as_ref() == Some(&avatar))
            })
        })
        .await?;

    alice.remove_avatar().await?;
    assert_eq!(alice.own_profile().await?.avatar_url, None);
    Ok(())
}

/// Sections as Element keeps them: a room moves between sections by its tags, one at a time,
/// and the user's sections are saved in Element's settings without losing the rest of them.
#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs the Synapse test homeserver (test-infra/)"]
async fn rooms_move_between_sections_as_in_element() -> TestResult {
    const ACME: &str = "element.io.section.acme";
    let (alice_user, bob_user) = (TestUser::register().await?, TestUser::register().await?);
    let (alice_store, bob_store) = (tempfile::tempdir()?, tempfile::tempdir()?);
    let alice = alice_user
        .login(&alice_store.path().to_string_lossy())
        .await?;
    let bob = bob_user.login(&bob_store.path().to_string_lossy()).await?;

    // Element's settings already hold other things, and a section with more than a name.
    alice
        .sdk()
        .account()
        .set_account_data_raw(
            "im.vector.web.settings".into(),
            Raw::from_json_string(
                json!({
                    "someOtherSetting": true,
                    "RoomList.CustomSectionData": {
                        ACME: { "tag": ACME, "name": "Acme", "spaceId": "home-space" },
                    },
                })
                .to_string(),
            )?,
        )
        .await?;
    alice.start_sync().await;
    let room_id = alice.create_dm(bob.user_id()).await?;
    let mut sections = alice.sections_updates().await;
    let tags_of = |rooms: &[RoomTags]| {
        rooms
            .iter()
            .find(|room| room.room_id == room_id)
            .map(|room| room.tags.clone())
    };

    wait_for_sections(&mut sections, |update| {
        matches!(update, SectionsUpdate::Settings { settings }
            if settings.sections.iter().any(|s| s.tag == ACME && s.name == "Acme"))
    })
    .await?;

    alice
        .set_room_section(room_id.clone(), Some("m.favourite".to_owned()))
        .await?;
    wait_for_sections(&mut sections, |update| {
        matches!(update, SectionsUpdate::Rooms { rooms }
            if tags_of(rooms) == Some(vec!["m.favourite".to_owned()]))
    })
    .await?;
    alice
        .set_room_section(room_id.clone(), Some(ACME.to_owned()))
        .await?;
    wait_for_sections(&mut sections, |update| {
        matches!(update, SectionsUpdate::Rooms { rooms }
            if tags_of(rooms) == Some(vec![ACME.to_owned()]))
    })
    .await?;
    alice.set_room_section(room_id.clone(), None).await?;
    wait_for_sections(&mut sections, |update| {
        matches!(update, SectionsUpdate::Rooms { rooms } if tags_of(rooms) == Some(vec![]))
    })
    .await?;
    assert!(matches!(
        alice
            .set_room_section(room_id.clone(), Some("u.work".to_owned()))
            .await,
        Err(CoreError::InvalidId { .. })
    ));

    // Renamed, with a new order; the rest of Element's settings stays.
    let order = vec![
        ACME.to_owned(),
        "im.vector.fake.direct".to_owned(),
        "chats".to_owned(),
    ];
    alice
        .save_section_settings(SectionSettings {
            sections: vec![CustomSection {
                tag: ACME.to_owned(),
                name: "Acme Corp".to_owned(),
            }],
            order: order.clone(),
        })
        .await?;
    wait_for_sections(&mut sections, |update| {
        matches!(update, SectionsUpdate::Settings { settings }
            if settings.order == order && settings.sections[0].name == "Acme Corp")
    })
    .await?;
    let stored = alice
        .sdk()
        .account()
        .account_data_raw("im.vector.web.settings".into())
        .await?
        .ok_or("no settings")?;
    let stored: serde_json::Value = serde_json::from_str(stored.json().get())?;
    assert_eq!(stored["someOtherSetting"], json!(true));
    assert_eq!(
        stored["RoomList.CustomSectionData"][ACME]["spaceId"],
        json!("home-space")
    );
    Ok(())
}

#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs the Synapse test homeserver (test-infra/)"]
async fn a_new_device_is_verified_with_emoji_by_another() -> TestResult {
    let user = TestUser::register().await?;
    let (first_store, second_store) = (tempfile::tempdir()?, tempfile::tempdir()?);

    // The first login creates the account's identity, which verifies that device.
    let first = user.login(&first_store.path().to_string_lossy()).await?;
    first.start_sync().await;
    wait_for_status(&first, VerificationStatus::Verified).await?;
    let second = user.login(&second_store.path().to_string_lossy()).await?;
    second.start_sync().await;
    wait_for_status(&second, VerificationStatus::Unverified).await?;

    // The new device asks; the first one gets the request and accepts it.
    let mut requests = first.verification_requests();
    let asking = Arc::new(second.request_self_verification().await?);
    let mut asking_states = watch_flow(&asking);
    let info = tokio::time::timeout(TIMEOUT, requests.next())
        .await?
        .ok_or("no request arrived")?;
    assert_eq!(info.device_id, second.session_data()?.device_id);
    let answering = Arc::new(first.verification(info.flow_id).await?);
    let mut answering_states = watch_flow(&answering);
    wait_for_flow(&mut answering_states, |s| {
        *s == VerificationFlowState::Requested
    })
    .await?;
    answering.accept().await?;

    // The new device starts the emoji; the other accepts; both see the same ones.
    wait_for_flow(&mut asking_states, |s| *s == VerificationFlowState::Ready).await?;
    asking.start_sas().await?;
    wait_for_flow(&mut answering_states, |s| {
        *s == VerificationFlowState::SasStarted
    })
    .await?;
    answering.accept_sas().await?;
    let is_keys =
        |s: &VerificationFlowState| matches!(s, VerificationFlowState::KeysExchanged { .. });
    let asking_emoji = wait_for_flow(&mut asking_states, is_keys).await?;
    let answering_emoji = wait_for_flow(&mut answering_states, is_keys).await?;
    assert_eq!(asking_emoji, answering_emoji);
    assert!(
        matches!(&asking_emoji, VerificationFlowState::KeysExchanged { emojis: Some(e), .. } if e.len() == 7),
        "{asking_emoji:?}"
    );

    asking.confirm().await?;
    answering.confirm().await?;
    wait_for_flow(&mut asking_states, |s| *s == VerificationFlowState::Done).await?;
    wait_for_flow(&mut answering_states, |s| *s == VerificationFlowState::Done).await?;
    wait_for_status(&second, VerificationStatus::Verified).await?;
    Ok(())
}

/// Both devices start the emoji at the same moment, as OxiTalk and Fractal do: the SDK keeps
/// one start, and the side whose start was dropped follows the one kept.
#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs the Synapse test homeserver (test-infra/)"]
async fn both_devices_starting_the_emoji_still_verify() -> TestResult {
    let user = TestUser::register().await?;
    let (first_store, second_store) = (tempfile::tempdir()?, tempfile::tempdir()?);
    let first = user.login(&first_store.path().to_string_lossy()).await?;
    first.start_sync().await;
    wait_for_status(&first, VerificationStatus::Verified).await?;
    let second = user.login(&second_store.path().to_string_lossy()).await?;
    second.start_sync().await;
    wait_for_status(&second, VerificationStatus::Unverified).await?;

    let mut requests = first.verification_requests();
    let asking = Arc::new(second.request_self_verification().await?);
    let mut asking_states = drive_flow(&asking);
    let info = tokio::time::timeout(TIMEOUT, requests.next())
        .await?
        .ok_or("no request arrived")?;
    let answering = Arc::new(first.verification(info.flow_id).await?);
    let mut answering_states = drive_flow(&answering);
    wait_for_flow(&mut answering_states, |s| {
        *s == VerificationFlowState::Requested
    })
    .await?;
    answering.accept().await?;
    wait_for_flow(&mut asking_states, |s| *s == VerificationFlowState::Ready).await?;
    wait_for_flow(&mut answering_states, |s| {
        *s == VerificationFlowState::Ready
    })
    .await?;

    let (asked, answered) = tokio::join!(asking.start_sas(), answering.start_sas());
    asked?;
    answered?;

    let is_keys =
        |s: &VerificationFlowState| matches!(s, VerificationFlowState::KeysExchanged { .. });
    let asking_emoji = wait_for_flow(&mut asking_states, is_keys).await?;
    let answering_emoji = wait_for_flow(&mut answering_states, is_keys).await?;
    assert_eq!(asking_emoji, answering_emoji);
    asking.confirm().await?;
    answering.confirm().await?;
    wait_for_flow(&mut asking_states, |s| *s == VerificationFlowState::Done).await?;
    wait_for_flow(&mut answering_states, |s| *s == VerificationFlowState::Done).await?;
    wait_for_status(&second, VerificationStatus::Verified).await?;
    Ok(())
}

/// The recovery key verifies a new device, and its history decrypts from the key backup.
#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs the Synapse test homeserver (test-infra/)"]
async fn the_recovery_key_verifies_and_restores_history() -> TestResult {
    let (user, other) = (TestUser::register().await?, TestUser::register().await?);
    let (first_store, second_store) = (tempfile::tempdir()?, tempfile::tempdir()?);

    // The first device writes a message, then sets up recovery (not in the app yet).
    let first = user.login(&first_store.path().to_string_lossy()).await?;
    first.start_sync().await;
    wait_for_status(&first, VerificationStatus::Verified).await?;
    let room_id = first
        .create_dm(format!("@{}:localhost", other.name))
        .await?;
    let timeline = first.timeline(room_id.clone()).await?;
    let mut items = watch_timeline(&timeline).await;
    timeline
        .send_text("before the new device".to_owned())
        .await?;
    items
        .wait_until(|items| {
            items.iter().any(|item| {
                matches!(&item.content, TimelineItemContent::Message { event, body }
                    if body == "before the new device" && event.send_state == SendState::Sent)
            })
        })
        .await?;
    let recovery_key = first.sdk().encryption().recovery().enable().await?;

    let second = user.login(&second_store.path().to_string_lossy()).await?;
    second.start_sync().await;
    wait_for_status(&second, VerificationStatus::Unverified).await?;
    let wrong = second.recover("EsTc 1234 not the key".to_owned()).await;
    assert_eq!(wrong, Err(CoreError::WrongRecoveryKey));
    second.recover(recovery_key).await?;
    wait_for_status(&second, VerificationStatus::Verified).await?;

    // The message from before this device existed decrypts.
    let timeline = second.timeline(room_id).await?;
    let mut items = watch_timeline(&timeline).await;
    timeline.paginate_back(20).await?;
    items
        .wait_until(|items| messages(items).contains(&("before the new device", true)))
        .await?;
    Ok(())
}

/// Takes section updates until one satisfies `done`.
async fn wait_for_sections(
    updates: &mut (impl Stream<Item = SectionsUpdate> + Unpin),
    done: impl Fn(&SectionsUpdate) -> bool,
) -> TestResult {
    tokio::time::timeout(TIMEOUT, async {
        while let Some(update) = updates.next().await {
            if done(&update) {
                return Ok(());
            }
        }
        Err("the stream ended".into())
    })
    .await
    .map_err(|_| "timed out waiting for sections")?
}

async fn wait_for_status(session: &Session, wanted: VerificationStatus) -> TestResult {
    let mut statuses = session.verification_statuses();
    tokio::time::timeout(TIMEOUT, async {
        while let Some(status) = statuses.next().await {
            if status == wanted {
                return Ok(());
            }
        }
        Err("the status stream ended")
    })
    .await
    .map_err(|_| format!("timed out waiting for {wanted:?}"))??;
    Ok(())
}

fn watch_flow(verification: &Arc<Verification>) -> mpsc::UnboundedReceiver<VerificationFlowState> {
    let (sender, states) = mpsc::unbounded_channel();
    let verification = Arc::clone(verification);
    tokio::spawn(async move {
        verification
            .state_updates(move |state| sender.send(state).is_ok())
            .await;
    });
    states
}

/// Like [`watch_flow`], accepting an emoji verification the other side started, as the app
/// does.
fn drive_flow(verification: &Arc<Verification>) -> mpsc::UnboundedReceiver<VerificationFlowState> {
    let (sender, states) = mpsc::unbounded_channel();
    let driven = Arc::clone(verification);
    tokio::spawn(async move {
        let accepting = Arc::clone(&driven);
        driven
            .state_updates(move |state| {
                if state == VerificationFlowState::SasStarted {
                    let accepting = Arc::clone(&accepting);
                    tokio::spawn(async move { accepting.accept_sas().await });
                }
                sender.send(state).is_ok()
            })
            .await;
    });
    states
}

async fn wait_for_flow(
    states: &mut mpsc::UnboundedReceiver<VerificationFlowState>,
    wanted: impl Fn(&VerificationFlowState) -> bool,
) -> Result<VerificationFlowState, Box<dyn Error>> {
    tokio::time::timeout(TIMEOUT, async {
        while let Some(state) = states.recv().await {
            if wanted(&state) {
                return Ok(state);
            }
            if let VerificationFlowState::Cancelled { .. } = state {
                return Err(format!("cancelled: {state:?}"));
            }
        }
        Err("the flow ended".to_owned())
    })
    .await
    .map_err(|_| "timed out waiting for the verification")?
    .map_err(Into::into)
}
