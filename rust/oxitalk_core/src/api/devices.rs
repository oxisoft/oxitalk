//! The account's devices (its sessions): which there are, renaming them, verifying another
//! one, and signing others out.

use std::{collections::HashMap, time::Duration};

use flutter_rust_bridge::frb;
use futures_util::{FutureExt, Stream, StreamExt, stream};
use matrix_sdk::{
    Client, HttpError,
    encryption::{VerificationState, identities::DeviceUpdates},
    ruma::{
        OwnedDeviceId, UserId,
        api::{
            client::{
                device::Device as ServerDevice,
                uiaa::{AuthData, MatrixUserIdentifier, Password, UserIdentifier},
            },
            error::ErrorKind,
        },
        events::key::verification::VerificationMethod,
    },
};

use super::{error::CoreError, session::Session, verification::Verification};
use crate::frb_generated::StreamSink;

/// How long a burst of device changes is gathered before the list is fetched again: a sync
/// often brings several at once.
const CHANGES_SETTLE: Duration = Duration::from_millis(300);

/// One device the account is signed in on, as the server and the encryption know it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DeviceInfo {
    pub device_id: String,
    /// The name the user (or the app at login) gave it, if any.
    pub display_name: Option<String>,
    /// When the server last saw it, in milliseconds since the Unix epoch, if it tells.
    pub last_seen_ts: Option<i64>,
    /// The IP address it was last seen from, if the server tells.
    pub last_seen_ip: Option<String>,
    /// The device the app runs on.
    pub is_this_device: bool,
    /// Signed by the account's identity: this device's own verification status, another's
    /// cross-signature by the account.
    pub verified: bool,
}

impl Session {
    /// The account's devices: this one first, then the others, the last seen first.
    ///
    /// # Errors
    ///
    /// As the server answers.
    pub async fn devices(&self) -> Result<Vec<DeviceInfo>, CoreError> {
        device_list(&self.client).await
    }

    /// Sends the account's [`Self::devices`] now, then whenever they may have changed: a
    /// device signed in or out, renamed, or verified. A failed fetch sends nothing; the next
    /// change tries again.
    #[allow(
        clippy::unused_async,
        reason = "async so flutter_rust_bridge runs it on its tokio runtime, which spawn needs"
    )]
    pub async fn subscribe_devices(&self, sink: StreamSink<Vec<DeviceInfo>>) {
        let mut lists = self.device_lists();
        self.spawn(async move {
            while let Some(list) = lists.next().await {
                if sink.add(list).is_err() {
                    break;
                }
            }
        });
    }

    /// Like [`Self::subscribe_devices`], for Rust callers.
    #[frb(ignore)]
    pub fn device_lists(&self) -> impl Stream<Item = Vec<DeviceInfo>> + Send + Unpin + 'static {
        let client = self.client.clone();
        Box::pin(
            stream::once(async move {
                // Listening before the first fetch, so no change falls between the two.
                let changes = device_changes(client.clone()).await;
                stream::once(std::future::ready(()))
                    .chain(changes)
                    .filter_map(move |()| {
                        let client = client.clone();
                        async move {
                            device_list(&client)
                                .await
                                .inspect_err(|error| {
                                    tracing::warn!("can't list the devices: {error}");
                                })
                                .ok()
                        }
                    })
            })
            .flatten(),
        )
    }

    /// Gives the account's device `device_id` (this one too) the name `name`.
    ///
    /// # Errors
    ///
    /// As the server answers.
    pub async fn rename_device(&self, device_id: String, name: String) -> Result<(), CoreError> {
        self.client
            .rename_device(&OwnedDeviceId::from(device_id), &name)
            .await?;
        Ok(())
    }

    /// Signs the account's devices `device_ids` out; this one logs out with
    /// [`Self::logout`] instead. The server asks for the account's password: without
    /// `password` this fails with [`CoreError::PasswordNeeded`], so the app can ask for it
    /// and call again.
    ///
    /// # Errors
    ///
    /// [`CoreError::PasswordNeeded`], [`CoreError::WrongPassword`], [`CoreError::Internal`]
    /// if `device_ids` holds this device, otherwise as the server answers.
    pub async fn sign_out_devices(
        &self,
        device_ids: Vec<String>,
        password: Option<String>,
    ) -> Result<(), CoreError> {
        let user_id = self.client.user_id().ok_or(CoreError::SessionExpired)?;
        let this_device = self.client.device_id().ok_or(CoreError::SessionExpired)?;
        let devices: Vec<OwnedDeviceId> = device_ids.into_iter().map(Into::into).collect();
        if devices.iter().any(|device| device == this_device) {
            return Err(CoreError::internal(
                &"this device logs out, it isn't signed out",
            ));
        }
        if devices.is_empty() {
            return Ok(());
        }
        let Err(error) = self.client.delete_devices(&devices, None).await else {
            return Ok(());
        };
        let Some(info) = error.as_uiaa_response() else {
            return Err(error.into());
        };
        let Some(password) = password else {
            return Err(CoreError::PasswordNeeded);
        };
        let mut auth = Password::new(
            UserIdentifier::Matrix(MatrixUserIdentifier::new(user_id.to_string())),
            password,
        );
        auth.session.clone_from(&info.session);
        match self
            .client
            .delete_devices(&devices, Some(AuthData::Password(auth)))
            .await
        {
            Ok(_) => Ok(()),
            Err(error) if is_wrong_password(&error) => Err(CoreError::WrongPassword),
            Err(error) => Err(error.into()),
        }
    }

    /// Asks the account's device `device_id` to verify with this one, by emoji. The other
    /// device shows the request; the [`Verification`] follows it as for this device's own.
    ///
    /// # Errors
    ///
    /// [`CoreError::Internal`] if this device doesn't have the other's keys (yet), otherwise
    /// as the server answers.
    pub async fn verify_device(&self, device_id: String) -> Result<Verification, CoreError> {
        let user_id = self.client.user_id().ok_or(CoreError::SessionExpired)?;
        let device = self
            .client
            .encryption()
            .get_device(user_id, &OwnedDeviceId::from(device_id))
            .await
            .map_err(|error| CoreError::internal(&error))?
            .ok_or_else(|| CoreError::internal(&"the device's keys are not known"))?;
        let request = device
            .request_verification_with_methods(vec![VerificationMethod::SasV1])
            .await?;
        Ok(Verification::new(request))
    }
}

/// The server's list merged with what the encryption knows, in the order the app shows it.
async fn device_list(client: &Client) -> Result<Vec<DeviceInfo>, CoreError> {
    let user_id = client.user_id().ok_or(CoreError::SessionExpired)?;
    let this_device = client.device_id().ok_or(CoreError::SessionExpired)?;
    let response = client.devices().await?;
    let signed = cross_signed(client, user_id).await;
    let this_verified =
        client.encryption().verification_state().get() == VerificationState::Verified;
    let mut list: Vec<DeviceInfo> = response
        .devices
        .into_iter()
        .map(|device| {
            let is_this_device = device.device_id == this_device;
            let verified = if is_this_device {
                this_verified
            } else {
                signed.get(&device.device_id).copied().unwrap_or(false)
            };
            device_info(device, is_this_device, verified)
        })
        .collect();
    sort_devices(&mut list);
    Ok(list)
}

/// Whether each of the user's devices the encryption knows is cross-signed by the account.
async fn cross_signed(client: &Client, user_id: &UserId) -> HashMap<OwnedDeviceId, bool> {
    match client.encryption().get_user_devices(user_id).await {
        Ok(devices) => devices
            .devices()
            .map(|device| {
                (
                    device.device_id().to_owned(),
                    device.is_cross_signed_by_owner(),
                )
            })
            .collect(),
        Err(error) => {
            tracing::warn!("can't read the devices' keys: {error}");
            HashMap::new()
        }
    }
}

fn device_info(device: ServerDevice, is_this_device: bool, verified: bool) -> DeviceInfo {
    DeviceInfo {
        device_id: device.device_id.to_string(),
        display_name: device.display_name.filter(|name| !name.trim().is_empty()),
        last_seen_ts: device.last_seen_ts.map(|ts| ts.0.into()),
        last_seen_ip: device.last_seen_ip,
        is_this_device,
        verified,
    }
}

/// This device first, then the last seen first; never seen last, by ID.
fn sort_devices(list: &mut [DeviceInfo]) {
    list.sort_by(|a, b| {
        b.is_this_device
            .cmp(&a.is_this_device)
            .then_with(|| b.last_seen_ts.cmp(&a.last_seen_ts))
            .then_with(|| a.device_id.cmp(&b.device_id))
    });
}

/// A signal whenever the user's devices may have changed: the encryption's device and
/// identity updates (sign-ins, sign-outs, renames and new signatures arrive as those),
/// gathered over [`CHANGES_SETTLE`]. Updates only about other users' devices are left out.
async fn device_changes(client: Client) -> impl Stream<Item = ()> + Send + 'static {
    let updates = match (client.user_id(), client.encryption().devices_stream().await) {
        (Some(user_id), Ok(updates)) => {
            let user_id = user_id.to_owned();
            updates
                .filter(move |update| std::future::ready(concerns(update, &user_id)))
                .boxed()
        }
        (_, Err(error)) => {
            tracing::warn!("no device updates: {error}");
            stream::empty().boxed()
        }
        (None, Ok(_)) => stream::empty().boxed(),
    };
    stream::unfold(updates, |mut updates| async move {
        updates.next().await?;
        tokio::time::sleep(CHANGES_SETTLE).await;
        // The rest of the burst, without waiting for more.
        while let Some(Some(_)) = updates.next().now_or_never() {}
        Some(((), updates))
    })
}

/// Whether the update may be about the user's own devices. One with no new or changed
/// device at all is a deletion or an identity change, which may be the user's.
fn concerns(update: &DeviceUpdates, user_id: &UserId) -> bool {
    let empty = update.new.is_empty() && update.changed.is_empty();
    empty || update.new.contains_key(user_id) || update.changed.contains_key(user_id)
}

/// The server's refusal of the password: it asks again with `M_FORBIDDEN`, or answers it.
fn is_wrong_password(error: &HttpError) -> bool {
    match error.as_uiaa_response() {
        Some(info) => info
            .auth_error
            .as_ref()
            .is_none_or(|error| error.kind == ErrorKind::Forbidden),
        None => error.client_api_error_kind() == Some(&ErrorKind::Forbidden),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn device(id: &str, seen: Option<i64>, this: bool) -> DeviceInfo {
        DeviceInfo {
            device_id: id.to_owned(),
            display_name: None,
            last_seen_ts: seen,
            last_seen_ip: None,
            is_this_device: this,
            verified: false,
        }
    }

    #[test]
    fn this_device_comes_first_then_the_last_seen() {
        let mut list = vec![
            device("OLD", Some(10), false),
            device("NEVER", None, false),
            device("THIS", Some(5), true),
            device("NEW", Some(20), false),
        ];
        sort_devices(&mut list);
        let ids: Vec<_> = list.iter().map(|d| d.device_id.as_str()).collect();
        assert_eq!(ids, ["THIS", "NEW", "OLD", "NEVER"]);
    }

    #[test]
    fn a_blank_name_is_no_name() {
        let mut server = ServerDevice::new(OwnedDeviceId::from("ABC"));
        server.display_name = Some("  ".to_owned());
        assert_eq!(device_info(server, false, false).display_name, None);
    }

    #[test]
    fn an_update_without_devices_may_be_the_users() {
        let me = matrix_sdk::ruma::user_id!("@me:example.org");
        assert!(concerns(&DeviceUpdates::default(), me));
    }
}
