//! The account's devices on the test homeserver: listing, renaming, verifying one from the
//! list and signing others out.

use std::{error::Error, sync::Arc};

use futures_util::{Stream, StreamExt};
use oxitalk_core::api::verification::VerificationFlowState;
use oxitalk_core::api::{
    devices::DeviceInfo, error::CoreError, session::Session, verification::VerificationStatus,
};

use super::{
    TIMEOUT, TestResult, TestUser, drive_flow, wait_for_flow, wait_for_status, wait_until_known,
    watch_flow,
};

/// Takes device lists until one satisfies `done`, and returns it.
async fn wait_for_devices(
    lists: &mut (impl Stream<Item = Vec<DeviceInfo>> + Unpin),
    what: &str,
    done: impl Fn(&[DeviceInfo]) -> bool,
) -> Result<Vec<DeviceInfo>, Box<dyn Error>> {
    tokio::time::timeout(TIMEOUT, async {
        while let Some(list) = lists.next().await {
            if done(&list) {
                return Ok(list);
            }
        }
        Err("the device stream ended".into())
    })
    .await
    .map_err(|_| format!("timed out waiting until {what}"))?
}

fn find<'a>(list: &'a [DeviceInfo], device_id: &str) -> Option<&'a DeviceInfo> {
    list.iter().find(|device| device.device_id == device_id)
}

async fn two_devices(
    user: &TestUser,
) -> Result<(Session, Session, Vec<tempfile::TempDir>), Box<dyn Error>> {
    let (first_store, second_store) = (tempfile::tempdir()?, tempfile::tempdir()?);
    let first = user.login(&first_store.path().to_string_lossy()).await?;
    first.start_sync().await;
    wait_for_status(&first, VerificationStatus::Verified).await?;
    let second = user.login(&second_store.path().to_string_lossy()).await?;
    second.start_sync().await;
    wait_for_status(&second, VerificationStatus::Unverified).await?;
    Ok((first, second, vec![first_store, second_store]))
}

/// Both devices list each other, this one first; a rename shows on both, and the list
/// follows it.
#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a test homeserver (test-infra/)"]
async fn the_devices_are_listed_and_renamed() -> TestResult {
    let user = TestUser::register().await?;
    let (first, second, _stores) = two_devices(&user).await?;
    let first_id = first.session_data()?.device_id;
    let second_id = second.session_data()?.device_id;

    let list = first.devices().await?;
    assert_eq!(list.len(), 2, "{list:?}");
    assert_eq!(list[0].device_id, first_id);
    assert!(list[0].is_this_device && list[0].verified, "{list:?}");
    assert_eq!(list[0].display_name.as_deref(), Some("OxiTalk"));
    let other = find(&list, &second_id).ok_or("the second device is missing")?;
    assert!(!other.is_this_device && !other.verified, "{other:?}");

    let list = second.devices().await?;
    assert_eq!(list[0].device_id, second_id);
    assert!(list[0].is_this_device && !list[0].verified, "{list:?}");
    // Once the keys are there, the unverified device sees the other one verified too.
    let mut seconds = second.device_lists();
    wait_for_devices(&mut seconds, "the second sees the first verified", |list| {
        find(list, &first_id).is_some_and(|d| !d.is_this_device && d.verified)
    })
    .await?;

    // A rename of another device and of this one, read back from both sides.
    let mut lists = first.device_lists();
    wait_for_devices(&mut lists, "the first list arrives", |list| list.len() == 2).await?;
    first
        .rename_device(second_id.clone(), "Phone".to_owned())
        .await?;
    second
        .rename_device(second_id.clone(), "My phone".to_owned())
        .await?;
    first
        .rename_device(first_id.clone(), "Laptop".to_owned())
        .await?;
    let list = second.devices().await?;
    assert_eq!(
        find(&list, &second_id).and_then(|d| d.display_name.as_deref()),
        Some("My phone")
    );
    assert_eq!(
        find(&list, &first_id).and_then(|d| d.display_name.as_deref()),
        Some("Laptop")
    );
    wait_for_devices(&mut lists, "the rename shows in the list", |list| {
        find(list, &second_id).and_then(|d| d.display_name.as_deref()) == Some("My phone")
    })
    .await?;
    Ok(())
}

/// Signing another device out asks the password, refuses a wrong one, and the list follows
/// it; this device can't be signed out from there.
#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a test homeserver (test-infra/)"]
async fn other_devices_are_signed_out_with_the_password() -> TestResult {
    let user = TestUser::register().await?;
    let (first, second, _stores) = two_devices(&user).await?;
    let first_id = first.session_data()?.device_id;
    let second_id = second.session_data()?.device_id;
    // As in the app, where a device to sign out has been there a while: one whose keys
    // never arrived can't be seen leaving.
    wait_until_known(&first, &second).await?;
    let mut lists = first.device_lists();
    wait_for_devices(&mut lists, "both devices are listed", |list| {
        list.len() == 2
    })
    .await?;

    let own = first.sign_out_devices(vec![first_id.clone()], None).await;
    assert!(matches!(own, Err(CoreError::Internal { .. })), "{own:?}");

    let needed = first.sign_out_devices(vec![second_id.clone()], None).await;
    assert_eq!(needed, Err(CoreError::PasswordNeeded));
    let wrong = first
        .sign_out_devices(vec![second_id.clone()], Some("not the password".to_owned()))
        .await;
    assert_eq!(wrong, Err(CoreError::WrongPassword));
    assert_eq!(first.devices().await?.len(), 2);

    first
        .sign_out_devices(vec![second_id.clone()], Some(user.password.clone()))
        .await?;
    let list = first.devices().await?;
    assert_eq!(list.len(), 1, "{list:?}");
    assert_eq!(list[0].device_id, first_id);
    // Without anything done here: the sync tells the device is gone.
    wait_for_devices(
        &mut lists,
        "the signed-out device leaves the list",
        |list| find(list, &second_id).is_none(),
    )
    .await?;
    Ok(())
}

/// A verified device asks another one from its list; after the emoji the list shows that one
/// verified.
#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a test homeserver (test-infra/)"]
async fn a_device_in_the_list_is_verified_from_there() -> TestResult {
    let user = TestUser::register().await?;
    let (first, second, _stores) = two_devices(&user).await?;
    let second_id = second.session_data()?.device_id;
    wait_until_known(&first, &second).await?;
    wait_until_known(&second, &first).await?;
    let mut lists = first.device_lists();

    let mut requests = second.verification_requests();
    let asking = Arc::new(first.verify_device(second_id.clone()).await?);
    let mut asking_states = watch_flow(&asking);
    let info = tokio::time::timeout(TIMEOUT, requests.next())
        .await?
        .ok_or("no request arrived")?;
    assert_eq!(info.device_id, first.session_data()?.device_id);
    let answering = Arc::new(second.verification(info.flow_id).await?);
    let mut answering_states = drive_flow(&answering);
    wait_for_flow(&mut answering_states, |s| {
        *s == VerificationFlowState::Requested
    })
    .await?;
    answering.accept().await?;
    wait_for_flow(&mut asking_states, |s| *s == VerificationFlowState::Ready).await?;
    asking.start_sas().await?;
    let is_keys =
        |s: &VerificationFlowState| matches!(s, VerificationFlowState::KeysExchanged { .. });
    let asked = wait_for_flow(&mut asking_states, is_keys).await?;
    let answered = wait_for_flow(&mut answering_states, is_keys).await?;
    assert_eq!(asked, answered);
    asking.confirm().await?;
    answering.confirm().await?;
    wait_for_flow(&mut asking_states, |s| *s == VerificationFlowState::Done).await?;
    wait_for_status(&second, VerificationStatus::Verified).await?;
    wait_for_devices(&mut lists, "the other device shows verified", |list| {
        find(list, &second_id).is_some_and(|d| d.verified)
    })
    .await?;

    let unknown = first.verify_device("NOSUCHDEVICE".to_owned()).await;
    assert!(
        matches!(unknown, Err(CoreError::Internal { .. })),
        "{unknown:?}"
    );
    Ok(())
}
