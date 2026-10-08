//! Tests against the Synapse test homeserver in `test-infra/`. They are ignored by a plain
//! `cargo test`; `scripts/ci.sh` starts the server and runs them with `--ignored`.

use std::{
    error::Error,
    time::{SystemTime, UNIX_EPOCH},
};

use matrix_sdk::{
    Client,
    ruma::api::client::{account::register::v3::Request as RegistrationRequest, uiaa},
};

type TestResult = Result<(), Box<dyn Error>>;

/// `OXITALK_TEST_HOMESERVER`, or the port `test-infra/compose.yaml` publishes.
fn homeserver_url() -> String {
    std::env::var("OXITALK_TEST_HOMESERVER").unwrap_or_else(|_| "http://localhost:8008".to_owned())
}

async fn client() -> Result<Client, Box<dyn Error>> {
    oxitalk_core::api::init_app();
    Ok(Client::builder()
        .homeserver_url(homeserver_url())
        .build()
        .await?)
}

/// A user name no earlier run has taken: the server keeps its data until `compose down -v`.
fn unique_username() -> Result<String, Box<dyn Error>> {
    let nanos = SystemTime::now().duration_since(UNIX_EPOCH)?.as_nanos();
    Ok(format!("user{nanos}"))
}

#[tokio::test]
#[ignore = "needs the Synapse test homeserver (test-infra/)"]
async fn registers_a_user_and_logs_in() -> TestResult {
    let username = unique_username()?;
    let password = format!("{username}-password");

    let mut request = RegistrationRequest::new();
    request.username = Some(username.clone());
    request.password = Some(password.clone());
    request.auth = Some(uiaa::AuthData::Dummy(uiaa::Dummy::new()));
    client().await?.matrix_auth().register(request).await?;

    let client = client().await?;
    client
        .matrix_auth()
        .login_username(&username, &password)
        .await?;

    assert_eq!(
        client.user_id().map(ToString::to_string),
        Some(format!("@{username}:localhost"))
    );
    Ok(())
}
