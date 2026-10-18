//! Tests against the SDK's mock homeserver, for server behavior Synapse can't be made to show
//! on demand.

// The futures of matrix-sdk-ui (the timeline in particular) are deeply nested.
#![recursion_limit = "256"]

mod support;

use std::time::Duration;

use futures_util::StreamExt;
use matrix_sdk::test_utils::mocks::MatrixMockServer;
use oxitalk_core::api::{
    error::CoreError,
    init_app,
    session::{Session, SessionChange, SessionData, restore},
    sync::SyncState,
};
use serde_json::json;
use support::{TIMEOUT, TestResult};
use wiremock::ResponseTemplate;

const PASSPHRASE: &str = "store passphrase";

async fn restored_session(
    server: &MatrixMockServer,
    store_dir: &str,
) -> Result<Session, CoreError> {
    init_app();
    restore(
        session_data(server),
        store_dir.to_owned(),
        PASSPHRASE.to_owned(),
    )
    .await
}

fn session_data(server: &MatrixMockServer) -> SessionData {
    SessionData {
        homeserver_url: server.uri(),
        user_id: "@alice:example.org".to_owned(),
        device_id: "DEVICEID".to_owned(),
        access_token: "access-token".to_owned(),
    }
}

/// A sliding-sync answer that holds the request a moment, like a server's long poll.
fn sync_ok() -> ResponseTemplate {
    ResponseTemplate::new(200)
        .set_body_json(json!({ "pos": "1" }))
        .set_delay(Duration::from_millis(50))
}

#[tokio::test(flavor = "multi_thread")]
async fn an_expired_sync_position_recovers_by_itself() -> TestResult {
    let server = MatrixMockServer::new().await;
    server.mock_versions().ok().mount().await;
    server
        .mock_sliding_sync()
        .respond_with(ResponseTemplate::new(400).set_body_json(json!({
            "errcode": "M_UNKNOWN_POS",
            "error": "Unknown position",
        })))
        .up_to_n_times(1)
        .mount()
        .await;
    server
        .mock_sliding_sync()
        .respond_with(sync_ok())
        .mount()
        .await;
    let store = tempfile::tempdir()?;
    let session = restored_session(&server, &store.path().to_string_lossy()).await?;

    let mut states = session.sync_states();
    session.start_sync().await;

    let mut seen = Vec::new();
    tokio::time::timeout(TIMEOUT, async {
        while let Some(state) = states.next().await {
            seen.push(state);
            if seen.contains(&SyncState::Offline) && seen.last() == Some(&SyncState::Running) {
                break;
            }
        }
    })
    .await
    .map_err(|_| format!("never recovered; states: {seen:?}"))?;
    assert_eq!(seen.first(), Some(&SyncState::Idle));
    Ok(())
}

#[tokio::test(flavor = "multi_thread")]
async fn a_rejected_token_is_reported_as_a_session_change() -> TestResult {
    let server = MatrixMockServer::new().await;
    server.mock_versions().ok().mount().await;
    server
        .mock_sliding_sync()
        .error_unknown_token(true)
        .mount()
        .await;
    let store = tempfile::tempdir()?;
    let session = restored_session(&server, &store.path().to_string_lossy()).await?;

    let mut changes = session.session_changes();
    session.start_sync().await;

    let change = tokio::time::timeout(TIMEOUT, changes.next()).await?;
    assert_eq!(
        change,
        Some(SessionChange::UnknownToken { soft_logout: true })
    );
    Ok(())
}

#[tokio::test(flavor = "multi_thread")]
async fn a_store_opens_only_with_its_passphrase() -> TestResult {
    let server = MatrixMockServer::new().await;
    let store = tempfile::tempdir()?;
    let store_dir = store.path().to_string_lossy().into_owned();
    drop(restored_session(&server, &store_dir).await?);

    let wrong = restore(session_data(&server), store_dir.clone(), "wrong".to_owned()).await;
    assert_eq!(wrong.err(), Some(CoreError::WrongStorePassphrase));

    let session = restored_session(&server, &store_dir).await?;
    assert_eq!(session.user_id(), "@alice:example.org");
    let data = session.session_data()?;
    assert_eq!(
        (data.user_id, data.device_id, data.access_token),
        (
            "@alice:example.org".into(),
            "DEVICEID".into(),
            "access-token".into()
        )
    );
    Ok(())
}

#[tokio::test(flavor = "multi_thread")]
async fn ids_are_checked_before_anything_is_sent() -> TestResult {
    let server = MatrixMockServer::new().await;
    let store = tempfile::tempdir()?;
    let session = restored_session(&server, &store.path().to_string_lossy()).await?;

    let bad_user = session.create_dm("alice".to_owned()).await;
    assert_eq!(
        bad_user,
        Err(CoreError::InvalidId {
            id: "alice".to_owned()
        })
    );
    let bad_room = session.join("room".to_owned()).await;
    assert_eq!(
        bad_room,
        Err(CoreError::InvalidId {
            id: "room".to_owned()
        })
    );
    let unknown = session
        .timeline("!unknown:example.org".to_owned())
        .await
        .err();
    assert_eq!(
        unknown,
        Some(CoreError::RoomNotFound {
            room_id: "!unknown:example.org".to_owned()
        })
    );
    Ok(())
}
