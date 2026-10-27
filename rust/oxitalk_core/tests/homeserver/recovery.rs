//! Recovery on the test homeserver: setting it up, the key verifying another device, and
//! changing the key.

use std::error::Error;

use futures_util::{Stream, StreamExt};
use oxitalk_core::api::{
    error::CoreError,
    recovery::{EncryptionStatus, RecoveryProgress, RecoveryStatus},
    session::Session,
    verification::VerificationStatus,
};

use super::{TIMEOUT, TestResult, TestUser, wait_for_status, wait_until_known};

/// Takes statuses until one satisfies `done`, and returns it.
async fn wait_for_encryption(
    statuses: &mut (impl Stream<Item = EncryptionStatus> + Unpin),
    what: &str,
    done: impl Fn(&EncryptionStatus) -> bool,
) -> Result<EncryptionStatus, Box<dyn Error>> {
    tokio::time::timeout(TIMEOUT, async {
        while let Some(status) = statuses.next().await {
            if done(&status) {
                return Ok(status);
            }
        }
        Err("the status stream ended".into())
    })
    .await
    .map_err(|_| format!("timed out waiting until {what}"))?
}

async fn logged_in(user: &TestUser, store: &tempfile::TempDir) -> Result<Session, Box<dyn Error>> {
    let session = user.login(&store.path().to_string_lossy()).await?;
    session.start_sync().await;
    Ok(session)
}

/// Recovery is off for a new account; setting it up turns it on, with progress, and the key
/// verifies a second device, which then has recovery on as well. Changing the key makes the
/// old one stop working and the new one work.
#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a test homeserver (test-infra/)"]
async fn recovery_is_set_up_and_its_key_changed() -> TestResult {
    let user = TestUser::register().await?;
    let stores = [
        tempfile::tempdir()?,
        tempfile::tempdir()?,
        tempfile::tempdir()?,
    ];
    let first = logged_in(&user, &stores[0]).await?;
    wait_for_status(&first, VerificationStatus::Verified).await?;
    let mut statuses = first.encryption_statuses();
    wait_for_encryption(&mut statuses, "recovery is off, the backup on", |s| {
        s.recovery == RecoveryStatus::Disabled && s.backup_enabled
    })
    .await?;
    assert!(first.is_last_device().await?);
    assert_eq!(
        first.reset_recovery_key().await,
        Err(CoreError::RecoveryNotSetUp)
    );

    let mut progress = first.recovery_progresses();
    let key = first.enable_recovery().await?;
    assert!(key.split_whitespace().count() >= 12, "not a recovery key");
    wait_for_encryption(&mut statuses, "recovery is on", |s| {
        s.recovery == RecoveryStatus::Enabled && s.backup_enabled
    })
    .await?;
    let mut steps = Vec::new();
    // Every step up to the last, however slowly they come.
    while steps.last() != Some(&RecoveryProgress::Done) {
        match tokio::time::timeout(TIMEOUT, progress.next()).await {
            Ok(Some(step)) => steps.push(step),
            Ok(None) | Err(_) => break,
        }
    }
    assert_eq!(steps.last(), Some(&RecoveryProgress::Done), "{steps:?}");
    assert!(
        steps.contains(&RecoveryProgress::CreatingRecoveryKey),
        "{steps:?}"
    );

    // A second device lacks the secrets until it enters the key.
    let second = logged_in(&user, &stores[1]).await?;
    wait_for_status(&second, VerificationStatus::Unverified).await?;
    let mut second_statuses = second.encryption_statuses();
    wait_for_encryption(&mut second_statuses, "the second is incomplete", |s| {
        s.recovery == RecoveryStatus::Incomplete
    })
    .await?;
    wait_until_known(&first, &second).await?;
    assert!(!first.is_last_device().await?);
    second.recover(key.clone()).await?;
    wait_for_status(&second, VerificationStatus::Verified).await?;
    wait_for_encryption(&mut second_statuses, "the second has it all", |s| {
        s.recovery == RecoveryStatus::Enabled && s.backup_enabled
    })
    .await?;

    // A new key: the old one no longer opens the secrets, the new one does.
    let new_key = first.reset_recovery_key().await?;
    assert_ne!(new_key, key);
    wait_for_encryption(&mut first.encryption_statuses(), "recovery stays on", |s| {
        s.recovery == RecoveryStatus::Enabled
    })
    .await?;
    let third = logged_in(&user, &stores[2]).await?;
    wait_for_status(&third, VerificationStatus::Unverified).await?;
    assert_eq!(third.recover(key).await, Err(CoreError::WrongRecoveryKey));
    third.recover(new_key).await?;
    wait_for_status(&third, VerificationStatus::Verified).await?;
    Ok(())
}
