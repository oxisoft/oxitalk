//! Tests against the SDK's mock homeserver, for server behavior Synapse can't be made to show
//! on demand.

// The futures of matrix-sdk-ui (the timeline in particular) are deeply nested.
#![recursion_limit = "256"]

mod support;

use std::time::Duration;

use futures_util::StreamExt;
#[cfg(target_os = "linux")]
use matrix_sdk::store::StateStoreDataKey;
use matrix_sdk::{cross_process_lock::CrossProcessLockConfig, test_utils::mocks::MatrixMockServer};
use oxitalk_core::api::{
    error::CoreError,
    init_app,
    server_info::{Availability, Federation, Probe},
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

    // Recovered: the sync asked again after the rejected position and runs. It may or may
    // not show Offline in between, depending on how fast it restarts.
    let asked_again = || async {
        server
            .server()
            .received_requests()
            .await
            .is_some_and(|requests| {
                requests
                    .iter()
                    .filter(|r| r.url.path().contains("simplified_msc3575"))
                    .count()
                    >= 2
            })
    };
    let mut seen = Vec::new();
    tokio::time::timeout(TIMEOUT, async {
        loop {
            tokio::select! {
                state = states.next() => match state {
                    Some(state) => seen.push(state),
                    None => break,
                },
                () = tokio::time::sleep(Duration::from_millis(100)) => {}
            }
            if seen.last() == Some(&SyncState::Running) && asked_again().await {
                break;
            }
        }
    })
    .await
    .map_err(|_| format!("never recovered; states: {seen:?}"))?;
    assert_eq!(seen.first(), Some(&SyncState::Idle));
    assert!(
        !seen.iter().any(|s| matches!(s, SyncState::Error { .. })),
        "{seen:?}"
    );
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

/// The app is the only process on its stores: no cross-process lock, whose lease the SDK
/// otherwise renews with a synced write every 50 ms for as long as the sync runs.
#[tokio::test(flavor = "multi_thread")]
async fn the_stores_are_used_by_this_process_alone() -> TestResult {
    let server = MatrixMockServer::new().await;
    let store = tempfile::tempdir()?;
    let session = restored_session(&server, &store.path().to_string_lossy()).await?;
    assert!(matches!(
        session.sdk().cross_process_lock_config(),
        CrossProcessLockConfig::SingleProcess
    ));
    Ok(())
}

/// Many reads at once share a few connections instead of opening one each.
#[cfg(target_os = "linux")]
#[tokio::test(flavor = "multi_thread")]
async fn concurrent_reads_open_few_connections() -> TestResult {
    let server = MatrixMockServer::new().await;
    let store = tempfile::tempdir()?;
    let session = restored_session(&server, &store.path().to_string_lossy()).await?;
    let reads = (0..64).map(|_| {
        let client = session.sdk().clone();
        tokio::spawn(async move {
            client
                .state_store()
                .get_kv_data(StateStoreDataKey::SyncToken)
                .await
        })
    });
    for read in futures_util::future::join_all(reads).await {
        read??;
    }
    let db = store.path().join("matrix-sdk-state.sqlite3");
    let open = std::fs::read_dir("/proc/self/fd")?
        .filter_map(|entry| std::fs::read_link(entry.ok()?.path()).ok())
        .filter(|target| *target == db)
        .count();
    assert!(open <= 4, "{open} connections to the state store");
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

/// The app drops a session from a thread of its own, without a Tokio runtime; the SDK's stores
/// still close on the runtime, instead of panicking.
#[tokio::test(flavor = "multi_thread")]
async fn a_session_can_be_dropped_outside_the_runtime() -> TestResult {
    let server = MatrixMockServer::new().await;
    server.mock_versions().ok().mount().await;
    let store = tempfile::tempdir()?;
    server
        .mock_sliding_sync()
        .respond_with(sync_ok())
        .mount()
        .await;
    let session = restored_session(&server, &store.path().to_string_lossy()).await?;
    // Syncing, as in the app: the stores have connections open.
    let mut states = session.sync_states();
    session.start_sync().await;
    tokio::time::timeout(TIMEOUT, async {
        while let Some(state) = states.next().await {
            if state == SyncState::Running {
                break;
            }
        }
    })
    .await?;
    tokio::time::sleep(Duration::from_millis(500)).await;
    drop(states);
    // As the app closes an account: sync stopped, then the session freed from its thread.
    session.stop_sync().await;
    let dropped = std::thread::spawn(move || drop(session)).join();
    assert!(dropped.is_ok(), "dropping the session panicked");
    // Time for the stores to close on the runtime.
    tokio::time::sleep(Duration::from_secs(2)).await;
    Ok(())
}

/// A session of `@alice:localhost` on `server`: its `.well-known` documents are asked of
/// `https://localhost/`, which isn't there, so nothing leaves the machine.
async fn server_info_session(
    server: &MatrixMockServer,
    store_dir: &str,
) -> Result<Session, CoreError> {
    init_app();
    restore(
        SessionData {
            user_id: "@alice:localhost".to_owned(),
            ..session_data(server)
        },
        store_dir.to_owned(),
        PASSPHRASE.to_owned(),
    )
    .await
}

async fn mount_get(server: &MatrixMockServer, at: &str, response: ResponseTemplate) {
    wiremock::Mock::given(wiremock::matchers::method("GET"))
        .and(wiremock::matchers::path(at))
        .respond_with(response)
        .mount(server.server())
        .await;
}

/// The paths of the GET requests the server got, in order.
async fn asked(server: &MatrixMockServer) -> Vec<String> {
    server
        .server()
        .received_requests()
        .await
        .unwrap_or_default()
        .iter()
        .map(|r| r.url.path().to_owned())
        .collect()
}

/// As chat.oxisoft.net: federation refused, the software told by Tuwunel's own endpoint, so
/// the endpoints after it (whose Synapse shim would say "Synapse") aren't asked.
#[tokio::test(flavor = "multi_thread")]
async fn server_info_finds_tuwunel_with_federation_disabled() -> TestResult {
    let server = MatrixMockServer::new().await;
    server.mock_versions().ok().mount().await;
    mount_get(
        &server,
        "/_matrix/federation/v1/version",
        ResponseTemplate::new(403).set_body_json(json!({
            "errcode": "M_FORBIDDEN", "error": "Federation is disabled."
        })),
    )
    .await;
    mount_get(
        &server,
        "/_tuwunel/server_version",
        ResponseTemplate::new(200).set_body_json(json!({"name": "Tuwunel", "version": "1.9.4"})),
    )
    .await;
    mount_get(
        &server,
        "/_synapse/admin/v1/server_version",
        ResponseTemplate::new(200).set_body_json(json!({"server_version": "1.9.4"})),
    )
    .await;
    mount_get(
        &server,
        "/_matrix/client/v3/login",
        ResponseTemplate::new(200).set_body_json(json!({"flows": [
            {"type": "m.login.application_service"},
            {"type": "m.login.token", "get_login_token": true},
            {"type": "m.login.password"}
        ]})),
    )
    .await;
    mount_get(
        &server,
        "/_matrix/client/v1/auth_metadata",
        ResponseTemplate::new(404).set_body_json(json!({
            "errcode": "M_UNRECOGNIZED", "error": "OIDC server not configured"
        })),
    )
    .await;
    mount_get(
        &server,
        "/_matrix/client/v3/capabilities",
        ResponseTemplate::new(200).set_body_json(json!({"capabilities": {
            "m.room_versions": {"default": "11", "available": {"10": "stable", "11": "stable"}}
        }})),
    )
    .await;
    mount_get(
        &server,
        "/_matrix/client/v1/media/config",
        ResponseTemplate::new(200).set_body_json(json!({"m.upload.size": 104_857_600})),
    )
    .await;
    let store = tempfile::tempdir()?;
    let session = server_info_session(&server, &store.path().to_string_lossy()).await?;

    let info = session.server_info().await?;

    let software = info.software.ok_or("no software")?;
    assert_eq!(software.name.as_deref(), Some("Tuwunel"));
    assert_eq!(software.version.as_deref(), Some("1.9.4"));
    assert_eq!(software.source, "/_tuwunel/server_version");
    assert_eq!(info.federation, Federation::Disabled);
    let paths = asked(&server).await;
    assert!(
        !paths
            .iter()
            .any(|p| p.starts_with("/_synapse") || p.starts_with("/_conduwuit")),
        "{paths:?}"
    );
    assert_eq!(info.server_name, "localhost");
    assert_eq!(info.user_id, "@alice:localhost");
    assert!(info.versions_known);
    assert!(info.newest_spec_version.is_some());
    let login = info.login.ok_or("no login")?;
    assert_eq!(login.flows.len(), 3);
    assert!(login.get_login_token);
    assert_eq!(info.oauth, Availability::No);
    let capabilities = info.capabilities.ok_or("no capabilities")?;
    assert_eq!(capabilities.default_room_version.as_deref(), Some("11"));
    assert_eq!(info.upload_limit_bytes, Some(104_857_600));
    assert!(!info.connection.tls);
    assert!(info.connection.round_trip_ms.is_some());
    assert!(info.connection.addresses.contains(&"127.0.0.1".to_owned()));
    // https://localhost/ isn't served: the documents are unknown, the call still succeeds.
    assert_eq!(info.well_known_client, Probe::NoAnswer);
    assert_eq!(info.well_known_support, Probe::NoAnswer);
    Ok(())
}

/// A server that answers none of the optional endpoints: every part is unknown, the
/// software endpoints are asked in order down to Synapse's, the legacy media config and the
/// unstable OAuth issuer are tried.
#[tokio::test(flavor = "multi_thread")]
async fn server_info_falls_back_when_endpoints_are_missing() -> TestResult {
    let server = MatrixMockServer::new().await;
    server.mock_versions().ok().mount().await;
    mount_get(
        &server,
        "/_matrix/media/v3/config",
        ResponseTemplate::new(200).set_body_json(json!({"m.upload.size": 1024})),
    )
    .await;
    mount_get(
        &server,
        "/_matrix/client/unstable/org.matrix.msc2965/auth_issuer",
        ResponseTemplate::new(200).set_body_json(json!({"issuer": "https://auth.localhost/"})),
    )
    .await;
    let store = tempfile::tempdir()?;
    let session = server_info_session(&server, &store.path().to_string_lossy()).await?;

    let info = session.server_info().await?;

    assert_eq!(info.software, None);
    assert_eq!(info.federation, Federation::Unknown);
    assert_eq!(info.login, None);
    assert_eq!(info.capabilities, None);
    assert_eq!(info.upload_limit_bytes, Some(1024));
    assert_eq!(info.oauth, Availability::Yes);
    assert_eq!(
        info.oauth_issuer.as_deref(),
        Some("https://auth.localhost/")
    );
    let paths = asked(&server).await;
    let order: Vec<_> = paths
        .iter()
        .filter(|p| SOFTWARE_PATHS.contains(&p.as_str()))
        .cloned()
        .collect();
    assert_eq!(order, SOFTWARE_PATHS);
    Ok(())
}

const SOFTWARE_PATHS: [&str; 4] = [
    "/_matrix/federation/v1/version",
    "/_tuwunel/server_version",
    "/_conduwuit/server_version",
    "/_synapse/admin/v1/server_version",
];

/// Synapse with federation on: the federation answer tells the software, and nothing else
/// is asked.
#[tokio::test(flavor = "multi_thread")]
async fn server_info_reads_the_software_from_federation() -> TestResult {
    let server = MatrixMockServer::new().await;
    server.mock_versions().ok().mount().await;
    mount_get(
        &server,
        "/_matrix/federation/v1/version",
        ResponseTemplate::new(200)
            .set_body_json(json!({"server": {"name": "Synapse", "version": "1.162.0"}})),
    )
    .await;
    let store = tempfile::tempdir()?;
    let session = server_info_session(&server, &store.path().to_string_lossy()).await?;

    let info = session.server_info().await?;

    assert_eq!(info.federation, Federation::Enabled);
    let software = info.software.ok_or("no software")?;
    assert_eq!(
        (software.name.as_deref(), software.version.as_deref()),
        (Some("Synapse"), Some("1.162.0"))
    );
    let paths = asked(&server).await;
    assert!(
        !paths.iter().any(|p| p.starts_with("/_tuwunel")),
        "{paths:?}"
    );
    Ok(())
}

/// A restored `@alice:localhost` in the joined room `!call:localhost`, the room's state
/// encryption answered as none.
async fn call_session(server: &MatrixMockServer, store_dir: &str) -> Result<Session, CoreError> {
    server.mock_versions().ok().mount().await;
    let session = server_info_session(server, store_dir).await?;
    server
        .sync_joined_room(session.sdk(), matrix_sdk::ruma::room_id!("!call:localhost"))
        .await;
    Ok(session)
}

async fn mount_post(server: &MatrixMockServer, at: &str, response: ResponseTemplate) {
    wiremock::Mock::given(wiremock::matchers::method("POST"))
        .and(wiremock::matchers::path(at))
        .respond_with(response)
        .mount(server.server())
        .await;
}

/// The bodies of the requests to paths starting with `prefix`, in order.
async fn bodies(server: &MatrixMockServer, prefix: &str) -> Vec<(String, serde_json::Value)> {
    server
        .server()
        .received_requests()
        .await
        .unwrap_or_default()
        .iter()
        .filter(|r| r.url.path().starts_with(prefix))
        .map(|r| {
            (
                r.url.path().to_owned(),
                serde_json::from_slice(&r.body).unwrap_or(serde_json::Value::Null),
            )
        })
        .collect()
}

/// Synapse and Tuwunel 1.9.4 serve the transports only under the unstable path; the SDK asks
/// v1 (and the well-known, not there for `localhost`) first.
#[tokio::test(flavor = "multi_thread")]
async fn call_services_fall_back_to_the_unstable_transports() -> TestResult {
    let server = MatrixMockServer::new().await;
    mount_get(
        &server,
        "/_matrix/client/v1/rtc/transports",
        ResponseTemplate::new(404)
            .set_body_json(json!({ "errcode": "M_UNRECOGNIZED", "error": "Unrecognized request" })),
    )
    .await;
    mount_get(
        &server,
        "/_matrix/client/unstable/org.matrix.msc4143/rtc/transports",
        ResponseTemplate::new(200).set_body_json(json!({ "rtc_transports": [
            { "type": "something-else", "url": "https://other" },
            { "type": "livekit", "livekit_service_url": "https://rtc.example/livekit/jwt" },
        ] })),
    )
    .await;
    let store = tempfile::tempdir()?;
    let session = server_info_session(&server, &store.path().to_string_lossy()).await?;
    assert_eq!(
        session.call_services().await?,
        ["https://rtc.example/livekit/jwt"]
    );
    Ok(())
}

/// Joining: OpenID token, `/sfu/get` with it, then the membership as Element Call writes it;
/// leaving sends empty content.
#[tokio::test(flavor = "multi_thread")]
async fn joining_a_call_asks_a_token_then_sends_the_membership() -> TestResult {
    use oxitalk_core::api::calls::{CallIntent, CallNotify};

    let server = MatrixMockServer::new().await;
    let service = format!("{}/livekit/jwt", server.uri());
    mount_get(
        &server,
        "/_matrix/client/unstable/org.matrix.msc4143/rtc/transports",
        ResponseTemplate::new(200).set_body_json(json!({ "rtc_transports": [
            { "type": "livekit", "livekit_service_url": service },
        ] })),
    )
    .await;
    mount_post(
        &server,
        "/_matrix/client/v3/user/@alice:localhost/openid/request_token",
        ResponseTemplate::new(200).set_body_json(json!({
            "access_token": "openid-token", "token_type": "Bearer",
            "matrix_server_name": "localhost", "expires_in": 3600,
        })),
    )
    .await;
    mount_post(
        &server,
        "/livekit/jwt/sfu/get",
        ResponseTemplate::new(200)
            .set_body_json(json!({ "url": "wss://sfu.example", "jwt": "the.jwt.token" })),
    )
    .await;
    wiremock::Mock::given(wiremock::matchers::method("PUT"))
        .and(wiremock::matchers::path_regex(
            "^/_matrix/client/v3/rooms/.*/state/org.matrix.msc3401.call.member/.*",
        ))
        .respond_with(ResponseTemplate::new(200).set_body_json(json!({ "event_id": "$member" })))
        .mount(server.server())
        .await;
    let store = tempfile::tempdir()?;
    let session = call_session(&server, &store.path().to_string_lossy()).await?;

    let call = session
        .join_call(
            "!call:localhost".to_owned(),
            CallIntent::Audio,
            CallNotify::None,
        )
        .await?;
    assert_eq!(call.livekit_url(), "wss://sfu.example");
    assert_eq!(call.livekit_token(), "the.jwt.token");
    assert_eq!(call.identity(), "@alice:localhost:DEVICEID");

    let token_request = bodies(&server, "/livekit/jwt/sfu/get").await;
    assert_eq!(
        token_request[0].1,
        json!({
            "room": "!call:localhost",
            "device_id": "DEVICEID",
            "openid_token": {
                "access_token": "openid-token", "token_type": "Bearer",
                "matrix_server_name": "localhost", "expires_in": 3600,
            },
        })
    );
    let state = bodies(&server, "/_matrix/client/v3/rooms/").await;
    let (path, membership) = state.first().ok_or("no membership sent")?;
    assert!(
        path.ends_with("/state/org.matrix.msc3401.call.member/_@alice:localhost_DEVICEID_m.call"),
        "{path}"
    );
    assert_eq!(membership["application"], "m.call");
    assert_eq!(membership["call_id"], "");
    assert_eq!(membership["device_id"], "DEVICEID");
    assert_eq!(membership["m.call.intent"], "audio");
    assert_eq!(
        membership["foci_preferred"][0]["livekit_service_url"],
        service
    );

    // A new token for the media (LiveKit closed the room before it connected): a new OpenID
    // token and `/sfu/get` again, same room and device.
    let renewed = call.renew_livekit_access().await?;
    assert_eq!(renewed.url, "wss://sfu.example");
    assert_eq!(renewed.token, "the.jwt.token");
    let token_requests = bodies(&server, "/livekit/jwt/sfu/get").await;
    assert_eq!(token_requests.len(), 2);
    assert_eq!(token_requests[1].1, token_requests[0].1);

    call.leave().await?;
    let state = bodies(&server, "/_matrix/client/v3/rooms/").await;
    assert_eq!(state.last().map(|(_, body)| body.clone()), Some(json!({})));
    Ok(())
}

/// A refusal from the call service is a [`CoreError::Forbidden`], and nothing is joined.
#[tokio::test(flavor = "multi_thread")]
async fn a_refused_call_token_joins_nothing() -> TestResult {
    use oxitalk_core::api::calls::{CallIntent, CallNotify};

    let server = MatrixMockServer::new().await;
    let service = format!("{}/livekit/jwt", server.uri());
    mount_get(
        &server,
        "/_matrix/client/unstable/org.matrix.msc4143/rtc/transports",
        ResponseTemplate::new(200).set_body_json(json!({ "rtc_transports": [
            { "type": "livekit", "livekit_service_url": service },
        ] })),
    )
    .await;
    mount_post(
        &server,
        "/_matrix/client/v3/user/@alice:localhost/openid/request_token",
        ResponseTemplate::new(200).set_body_json(json!({
            "access_token": "t", "token_type": "Bearer",
            "matrix_server_name": "localhost", "expires_in": 3600,
        })),
    )
    .await;
    mount_post(
        &server,
        "/livekit/jwt/sfu/get",
        ResponseTemplate::new(403).set_body_json(json!({ "errcode": "M_FORBIDDEN" })),
    )
    .await;
    let store = tempfile::tempdir()?;
    let session = call_session(&server, &store.path().to_string_lossy()).await?;
    let error = session
        .join_call(
            "!call:localhost".to_owned(),
            CallIntent::Video,
            CallNotify::Ring,
        )
        .await
        .err();
    assert!(
        matches!(error, Some(CoreError::Forbidden { .. })),
        "{error:?}"
    );
    assert_eq!(bodies(&server, "/_matrix/client/v3/rooms/").await, []);
    Ok(())
}

/// One `/v3/sync` answer, for a `sync_once` (the session's own sync isn't running).
async fn sync_once_with(
    server: &MatrixMockServer,
    session: &Session,
    batch: &str,
    rooms: serde_json::Value,
) -> TestResult {
    wiremock::Mock::given(wiremock::matchers::method("GET"))
        .and(wiremock::matchers::path("/_matrix/client/v3/sync"))
        .respond_with(
            ResponseTemplate::new(200)
                .set_body_json(json!({ "next_batch": batch, "rooms": rooms })),
        )
        .up_to_n_times(1)
        .mount(server.server())
        .await;
    session
        .sdk()
        .sync_once(matrix_sdk::config::SyncSettings::default())
        .await?;
    Ok(())
}

/// A member event of `user` in `!dm:localhost`, `membership` and from `sender`.
fn member(user: &str, membership: &str, sender: &str, is_direct: bool) -> serde_json::Value {
    json!({
        "type": "m.room.member", "state_key": user, "sender": sender,
        "content": { "membership": membership, "is_direct": is_direct },
        "event_id": format!("${user}-{membership}"), "origin_server_ts": 1,
    })
}

/// Accepting an invitation to a direct chat marks it direct (`m.direct`) even when the sync
/// brings the join before the server answers the join request; the SDK alone then saw the
/// room joined already and didn't mark it (seen on Tuwunel under load).
#[tokio::test(flavor = "multi_thread")]
async fn a_direct_invitation_joined_is_a_direct_chat_whatever_comes_first() -> TestResult {
    let server = MatrixMockServer::new().await;
    server.mock_versions().ok().mount().await;
    let store = tempfile::tempdir()?;
    let session = server_info_session(&server, &store.path().to_string_lossy()).await?;
    let (alice, bob) = ("@alice:localhost", "@bob:localhost");
    sync_once_with(
        &server,
        &session,
        "1",
        json!({ "invite": { "!dm:localhost": { "invite_state": { "events": [
            { "type": "m.room.create", "state_key": "", "sender": bob,
              "content": { "room_version": "11" } },
            { "type": "m.room.member", "state_key": bob, "sender": bob,
              "content": { "membership": "join" } },
            { "type": "m.room.member", "state_key": alice, "sender": bob,
              "content": { "membership": "invite", "is_direct": true } },
        ] } } } }),
    )
    .await?;
    let invited = session
        .sdk()
        .get_room(matrix_sdk::ruma::room_id!("!dm:localhost"))
        .ok_or("no invitation")?;
    assert!(
        invited.is_direct().await?,
        "the invitation is to a direct chat"
    );

    // The server answers the join late; the sync with the join comes first.
    wiremock::Mock::given(wiremock::matchers::method("POST"))
        .and(wiremock::matchers::path_regex(
            "^/_matrix/client/v3/(join/|rooms/[^/]+/join$)",
        ))
        .respond_with(
            ResponseTemplate::new(200)
                .set_body_json(json!({ "room_id": "!dm:localhost" }))
                .set_delay(Duration::from_millis(1500)),
        )
        .mount(server.server())
        .await;
    let joined = [
        json!({ "type": "m.room.create", "state_key": "", "sender": bob,
                "content": { "room_version": "11" }, "event_id": "$create",
                "origin_server_ts": 1 }),
        member(bob, "join", bob, false),
        member(alice, "join", alice, false),
    ];
    wiremock::Mock::given(wiremock::matchers::method("GET"))
        .and(wiremock::matchers::path(
            "/_matrix/client/v3/rooms/!dm:localhost/members",
        ))
        .respond_with(ResponseTemplate::new(200).set_body_json(json!({ "chunk": joined })))
        .mount(server.server())
        .await;
    wiremock::Mock::given(wiremock::matchers::method("PUT"))
        .and(wiremock::matchers::path(format!(
            "/_matrix/client/v3/user/{alice}/account_data/m.direct"
        )))
        .respond_with(ResponseTemplate::new(200).set_body_json(json!({})))
        .mount(server.server())
        .await;
    let join = session.join("!dm:localhost".to_owned());
    let sync = async {
        tokio::time::sleep(Duration::from_millis(300)).await;
        sync_once_with(
            &server,
            &session,
            "2",
            json!({ "join": { "!dm:localhost": {
                "state": { "events": joined },
                "timeline": { "events": [], "limited": false },
            } } }),
        )
        .await
    };
    let (joined_result, synced) = tokio::join!(join, sync);
    synced?;
    joined_result?;

    let marks = bodies(
        &server,
        &format!("/_matrix/client/v3/user/{alice}/account_data/m.direct"),
    )
    .await;
    let (_, content) = marks.last().ok_or("the chat wasn't marked direct")?;
    assert_eq!(content[bob], json!(["!dm:localhost"]), "{content}");
    Ok(())
}
