//! Tests against the Synapse test homeserver in `test-infra/`. They are ignored by a plain
//! `cargo test`; `scripts/ci.sh` starts the server and runs them with `--ignored`.

// The futures of matrix-sdk-ui (the timeline in particular) are deeply nested.
#![recursion_limit = "256"]

mod support;

use std::{
    error::Error,
    time::{SystemTime, UNIX_EPOCH},
};

use matrix_sdk::{
    Client,
    ruma::api::client::{account::register::v3::Request as RegistrationRequest, uiaa},
};
use oxitalk_core::api::{
    error::CoreError,
    init_app,
    room_list::Membership,
    session::{Session, login, restore},
    timeline::{SendState, TimelineItemContent},
};
use support::{TestResult, messages, watch_rooms, watch_timeline};

const PASSPHRASE: &str = "store passphrase";

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
