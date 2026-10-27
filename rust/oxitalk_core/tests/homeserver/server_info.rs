//! What the app finds out about the test homeserver.

use oxitalk_core::api::server_info::{Federation, Probe};

use super::{TestResult, TestUser, homeserver_url};

/// The basics every homeserver answers, and the software found by its own endpoint:
/// `OXITALK_TEST_SOFTWARE` (e.g. "Tuwunel") names the one expected, if set.
#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a test homeserver (test-infra/)"]
async fn the_server_info_tells_the_test_homeserver() -> TestResult {
    let user = TestUser::register().await?;
    let store = tempfile::tempdir()?;
    let session = user.login(&store.path().to_string_lossy()).await?;

    let info = session.server_info().await?;
    // Shown with any failure below.
    let dump = format!("{info:#?}");

    assert_eq!(info.server_name, "localhost");
    assert_eq!(
        info.homeserver_url.trim_end_matches('/'),
        homeserver_url().trim_end_matches('/')
    );
    assert!(info.versions_known);
    assert!(info.newest_spec_version.is_some());
    let login = info.login.ok_or("no login flows")?;
    assert!(login.flows.iter().any(|flow| flow == "m.login.password"));
    let capabilities = info.capabilities.ok_or("no capabilities")?;
    assert!(capabilities.default_room_version.is_some());
    capabilities
        .room_versions
        .first()
        .ok_or_else(|| format!("no room versions: {dump}"))?;
    assert!(info.upload_limit_bytes.is_some());
    assert!(!info.connection.tls);
    assert!(info.connection.round_trip_ms.is_some());
    assert!(
        info.connection
            .addresses
            .iter()
            .any(|ip| ip == "127.0.0.1" || ip == "::1"),
        "{:?}",
        info.connection.addresses
    );
    // https://localhost/ isn't served.
    assert_eq!(info.well_known_client, Probe::NoAnswer);
    let software = info
        .software
        .ok_or_else(|| format!("no software: {dump}"))?;
    if let Ok(expected) = std::env::var("OXITALK_TEST_SOFTWARE") {
        assert_eq!(software.name.as_deref(), Some(expected.as_str()), "{dump}");
        if expected == "Tuwunel" {
            // test-infra/tuwunel.toml has allow_federation = false, as chat.oxisoft.net.
            assert_eq!(software.source, "/_tuwunel/server_version");
            assert_eq!(info.federation, Federation::Disabled);
        }
    }
    Ok(())
}
