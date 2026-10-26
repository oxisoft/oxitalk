//! Verifying this device: with another of the user's devices by comparing emoji, or with the
//! recovery key. The SDK's states, passed through; what to do in each belongs to the app.

use std::sync::{Arc, Mutex, PoisonError};

use flutter_rust_bridge::frb;
use futures_util::{
    Stream, StreamExt,
    future::{self, Either},
    stream::{self, BoxStream},
};
use matrix_sdk::{
    Client,
    encryption::{
        VerificationState,
        identities::RequestVerificationError,
        recovery::RecoveryError,
        secret_storage::SecretStorageError,
        verification::{
            CancelInfo, SasState, SasVerification, VerificationRequest, VerificationRequestState,
        },
    },
    ruma::events::key::verification::{
        VerificationMethod, request::ToDeviceKeyVerificationRequestEvent,
    },
};

use super::{error::CoreError, session::Session};
use crate::frb_generated::StreamSink;

/// [`VerificationState`], one to one: whether this device is signed by its user's identity.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum VerificationStatus {
    /// Not known yet, e.g. right after login before the keys are fetched.
    Unknown,
    Verified,
    Unverified,
}

/// A verification request from another device of the user, as it arrives.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct VerificationRequestInfo {
    pub flow_id: String,
    pub device_id: String,
    pub device_name: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct VerificationEmoji {
    pub symbol: String,
    pub description: String,
}

/// The request's [`VerificationRequestState`], then, once it has become an emoji verification,
/// the [`SasState`]: one to one, in one stream.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum VerificationFlowState {
    /// We sent the request; waiting for the other device to accept.
    Created,
    /// The other device sent the request; [`Verification::accept`] it or cancel.
    Requested,
    /// Both sides accepted; either may [`Verification::start_sas`].
    Ready,
    /// We started the emoji verification; waiting for the other device to accept it.
    SasCreated,
    /// The other device started the emoji verification; [`Verification::accept_sas`] it.
    SasStarted,
    /// Both sides agreed on the emoji verification; the keys are being exchanged.
    SasAccepted,
    /// Compare these on both devices, then [`Verification::confirm`] or
    /// [`Verification::mismatch`]. `emojis` is `None` if the other side can't show emoji.
    KeysExchanged {
        emojis: Option<Vec<VerificationEmoji>>,
        decimals: Vec<u16>,
    },
    /// We confirmed; waiting for the other device.
    Confirmed,
    Done,
    Cancelled {
        reason: String,
        by_us: bool,
    },
}

impl Session {
    /// Sends the current [`VerificationStatus`], then every change.
    #[allow(
        clippy::unused_async,
        reason = "async so flutter_rust_bridge runs it on its tokio runtime, which spawn needs"
    )]
    pub async fn subscribe_verification_status(&self, sink: StreamSink<VerificationStatus>) {
        let mut statuses = self.verification_statuses();
        self.spawn(async move {
            while let Some(status) = statuses.next().await {
                if sink.add(status).is_err() {
                    break;
                }
            }
        });
    }

    /// The current [`VerificationStatus`], then every change, for Rust callers.
    #[frb(ignore)]
    pub fn verification_statuses(
        &self,
    ) -> impl Stream<Item = VerificationStatus> + Send + Unpin + 'static {
        let states = self.client.encryption().verification_state();
        stream::iter([states.get()])
            .chain(states)
            .map(verification_status)
    }

    /// Verifies this device with the recovery key or the security phrase, and turns on the key
    /// backup with it.
    ///
    /// # Errors
    ///
    /// [`CoreError::WrongRecoveryKey`], [`CoreError::RecoveryNotSetUp`] if the account has no
    /// recovery, or as the server answers.
    pub async fn recover(&self, key: String) -> Result<(), CoreError> {
        self.client
            .encryption()
            .recovery()
            .recover(&key)
            .await
            .map_err(|error| recovery_error(&error))
    }

    /// Asks the user's other devices to verify this one.
    ///
    /// # Errors
    ///
    /// [`CoreError::Internal`] if the account has no cross-signing identity yet, or as the
    /// server answers.
    pub async fn request_self_verification(&self) -> Result<Verification, CoreError> {
        let encryption = self.client.encryption();
        let user_id = self.client.user_id().ok_or(CoreError::SessionExpired)?;
        let identity = encryption
            .request_user_identity(user_id)
            .await
            .map_err(|error| CoreError::from_sdk(&error))?
            .ok_or_else(|| CoreError::internal(&"the account has no cross-signing identity"))?;
        let request = identity
            .request_verification_with_methods(vec![VerificationMethod::SasV1])
            .await
            .map_err(|error| match error {
                RequestVerificationError::Sdk(error) => CoreError::from_sdk(&error),
                other @ RequestVerificationError::RoomCreation(_) => CoreError::internal(&other),
            })?;
        Ok(Verification::new(request))
    }

    /// Sends every verification request that arrives from another device of the user.
    #[allow(
        clippy::unused_async,
        reason = "async so flutter_rust_bridge runs it on its tokio runtime, which spawn needs"
    )]
    pub async fn subscribe_verification_requests(&self, sink: StreamSink<VerificationRequestInfo>) {
        let mut requests = self.verification_requests();
        self.spawn(async move {
            while let Some(request) = requests.next().await {
                if sink.add(request).is_err() {
                    break;
                }
            }
        });
    }

    /// Every verification request from another device of the user, for Rust callers.
    #[frb(ignore)]
    pub fn verification_requests(
        &self,
    ) -> impl Stream<Item = VerificationRequestInfo> + Send + Unpin + 'static {
        let client = self.client.clone();
        // The subscriber only holds the handler weakly; the stream keeps both.
        let handler = client.observe_events::<ToDeviceKeyVerificationRequestEvent, ()>();
        let events = handler.subscribe();
        Box::pin(
            events
                .filter_map(move |(event, ())| {
                    let client = client.clone();
                    let _keep = &handler;
                    async move { request_info(&client, &event).await }
                })
                .boxed(),
        )
    }

    /// Opens a request that arrived through [`Self::subscribe_verification_requests`].
    ///
    /// # Errors
    ///
    /// [`CoreError::Internal`] if the request is unknown, e.g. already cancelled.
    pub async fn verification(&self, flow_id: String) -> Result<Verification, CoreError> {
        let user_id = self.client.user_id().ok_or(CoreError::SessionExpired)?;
        self.client
            .encryption()
            .get_verification_request(user_id, flow_id)
            .await
            .map(Verification::new)
            .ok_or_else(|| CoreError::internal(&"unknown verification request"))
    }
}

/// One verification with another device: the request and, once started, the emoji
/// verification.
#[frb(opaque)]
#[derive(Debug)]
pub struct Verification {
    request: VerificationRequest,
    sas: Arc<Mutex<Option<SasVerification>>>,
}

impl Verification {
    pub(crate) fn new(request: VerificationRequest) -> Self {
        let sas = match request.state() {
            VerificationRequestState::Transitioned { verification } => verification.sas(),
            _ => None,
        };
        Self {
            request,
            sas: Arc::new(Mutex::new(sas)),
        }
    }

    /// Sends the current [`VerificationFlowState`], then every change, until it is done or
    /// cancelled.
    pub async fn subscribe_states(&self, sink: StreamSink<VerificationFlowState>) {
        self.state_updates(move |state| sink.add(state).is_ok())
            .await;
    }

    /// Like [`Self::subscribe_states`], for Rust callers: `emit` gets each state and returns
    /// `false` to stop.
    #[frb(ignore)]
    pub async fn state_updates(&self, mut emit: impl FnMut(VerificationFlowState) -> bool) {
        let mut requests = stream::iter([self.request.state()])
            .chain(self.request.changes())
            .boxed();
        let mut requests_ended = false;
        // The emoji verification being followed. When both devices start one at once, the
        // SDK keeps one of them and the request transitions again, to that one.
        let mut sas_states: Option<BoxStream<'static, SasState>> = None;
        loop {
            let update = match (&mut sas_states, requests_ended) {
                (None, true) => return,
                (None, false) => requests
                    .next()
                    .await
                    .map_or(Update::RequestEnded, Update::Request),
                (Some(sas), true) => sas.next().await.map_or(Update::SasEnded, Update::Sas),
                (Some(sas), false) => match future::select(requests.next(), sas.next()).await {
                    Either::Left((state, _)) => state.map_or(Update::RequestEnded, Update::Request),
                    Either::Right((state, _)) => state.map_or(Update::SasEnded, Update::Sas),
                },
            };
            let state = match update {
                Update::Request(VerificationRequestState::Transitioned { verification }) => {
                    if let Some(sas) = verification.sas() {
                        self.set_sas(sas.clone());
                        sas_states = Some(stream::iter([sas.state()]).chain(sas.changes()).boxed());
                    }
                    continue;
                }
                Update::Request(state) => request_state(&state),
                Update::Sas(state) => sas_state(&state),
                Update::RequestEnded => {
                    requests_ended = true;
                    continue;
                }
                Update::SasEnded => {
                    sas_states = None;
                    continue;
                }
            };
            let last = matches!(
                state,
                VerificationFlowState::Done | VerificationFlowState::Cancelled { .. }
            );
            if !emit(state) || last {
                return;
            }
        }
    }

    /// Accepts a request from the other device, offering emoji verification.
    ///
    /// # Errors
    ///
    /// As the server answers.
    pub async fn accept(&self) -> Result<(), CoreError> {
        self.request
            .accept_with_methods(vec![VerificationMethod::SasV1])
            .await
            .map_err(|error| CoreError::from_sdk(&error))
    }

    /// Starts the emoji verification once the request is ready.
    ///
    /// # Errors
    ///
    /// As the server answers.
    pub async fn start_sas(&self) -> Result<(), CoreError> {
        let sas = self
            .request
            .start_sas()
            .await
            .map_err(|error| CoreError::from_sdk(&error))?
            .ok_or_else(|| CoreError::internal(&"the request is not ready for emoji"))?;
        // The request's state stream takes over if the SDK keeps the other device's instead.
        let mut slot = self.sas.lock().unwrap_or_else(PoisonError::into_inner);
        if slot.is_none() {
            *slot = Some(sas);
        }
        Ok(())
    }

    /// Accepts the emoji verification the other device started.
    ///
    /// # Errors
    ///
    /// As the server answers.
    pub async fn accept_sas(&self) -> Result<(), CoreError> {
        self.sas()?
            .accept()
            .await
            .map_err(|error| CoreError::from_sdk(&error))
    }

    /// The emoji match.
    ///
    /// # Errors
    ///
    /// As the server answers.
    pub async fn confirm(&self) -> Result<(), CoreError> {
        self.sas()?
            .confirm()
            .await
            .map_err(|error| CoreError::from_sdk(&error))
    }

    /// The emoji don't match; cancels the verification.
    ///
    /// # Errors
    ///
    /// As the server answers.
    pub async fn mismatch(&self) -> Result<(), CoreError> {
        self.sas()?
            .mismatch()
            .await
            .map_err(|error| CoreError::from_sdk(&error))
    }

    /// Cancels the verification at any point.
    ///
    /// # Errors
    ///
    /// As the server answers.
    pub async fn cancel(&self) -> Result<(), CoreError> {
        let sas = self
            .sas
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .clone();
        match sas {
            Some(sas) => sas.cancel().await,
            None => self.request.cancel().await,
        }
        .map_err(|error| CoreError::from_sdk(&error))
    }

    fn sas(&self) -> Result<SasVerification, CoreError> {
        self.sas
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .clone()
            .ok_or_else(|| CoreError::internal(&"the emoji verification has not started"))
    }

    fn set_sas(&self, sas: SasVerification) {
        *self.sas.lock().unwrap_or_else(PoisonError::into_inner) = Some(sas);
    }
}

async fn request_info(
    client: &Client,
    event: &ToDeviceKeyVerificationRequestEvent,
) -> Option<VerificationRequestInfo> {
    if Some(event.sender.as_ref()) != client.user_id() {
        return None;
    }
    let request = client
        .encryption()
        .get_verification_request(&event.sender, &event.content.transaction_id)
        .await?;
    let VerificationRequestState::Requested {
        other_device_data, ..
    } = request.state()
    else {
        return None;
    };
    Some(VerificationRequestInfo {
        flow_id: request.flow_id().to_owned(),
        device_id: other_device_data.device_id().to_string(),
        device_name: other_device_data.display_name().map(str::to_owned),
    })
}

enum Update {
    Request(VerificationRequestState),
    Sas(SasState),
    RequestEnded,
    SasEnded,
}

fn verification_status(state: VerificationState) -> VerificationStatus {
    match state {
        VerificationState::Unknown => VerificationStatus::Unknown,
        VerificationState::Verified => VerificationStatus::Verified,
        VerificationState::Unverified => VerificationStatus::Unverified,
    }
}

fn request_state(state: &VerificationRequestState) -> VerificationFlowState {
    match state {
        VerificationRequestState::Created { .. } => VerificationFlowState::Created,
        VerificationRequestState::Requested { .. } => VerificationFlowState::Requested,
        VerificationRequestState::Ready { .. } => VerificationFlowState::Ready,
        // Handled by the caller, which follows the emoji verification's states from then on.
        VerificationRequestState::Transitioned { .. } => VerificationFlowState::SasStarted,
        VerificationRequestState::Done => VerificationFlowState::Done,
        VerificationRequestState::Cancelled(info) => cancelled(info),
    }
}

fn sas_state(state: &SasState) -> VerificationFlowState {
    match state {
        SasState::Created { .. } => VerificationFlowState::SasCreated,
        SasState::Started { .. } => VerificationFlowState::SasStarted,
        SasState::Accepted { .. } => VerificationFlowState::SasAccepted,
        SasState::KeysExchanged { emojis, decimals } => VerificationFlowState::KeysExchanged {
            emojis: emojis.as_ref().map(|emojis| {
                emojis
                    .emojis
                    .iter()
                    .map(|emoji| VerificationEmoji {
                        symbol: emoji.symbol.to_owned(),
                        description: emoji.description.to_owned(),
                    })
                    .collect()
            }),
            decimals: vec![decimals.0, decimals.1, decimals.2],
        },
        SasState::Confirmed => VerificationFlowState::Confirmed,
        SasState::Done { .. } => VerificationFlowState::Done,
        SasState::Cancelled(info) => cancelled(info),
    }
}

fn cancelled(info: &CancelInfo) -> VerificationFlowState {
    VerificationFlowState::Cancelled {
        reason: info.reason().to_owned(),
        by_us: info.cancelled_by_us(),
    }
}

fn recovery_error(error: &RecoveryError) -> CoreError {
    match error {
        RecoveryError::SecretStorage(SecretStorageError::SecretStorageKey(_)) => {
            CoreError::WrongRecoveryKey
        }
        RecoveryError::SecretStorage(SecretStorageError::MissingKeyInfo { .. }) => {
            CoreError::RecoveryNotSetUp
        }
        RecoveryError::Sdk(error)
        | RecoveryError::SecretStorage(SecretStorageError::Sdk(error)) => {
            CoreError::from_sdk(error)
        }
        other => CoreError::internal(other),
    }
}
