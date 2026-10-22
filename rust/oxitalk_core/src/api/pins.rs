//! A room's pinned messages, as Element X shows them: which events are pinned (in the order
//! they were pinned), whether the user may pin, pinning and unpinning, and a timeline of only
//! the pinned messages with their content, kept up to date.

use std::{
    collections::HashMap,
    sync::{Arc, Mutex, PoisonError},
};

use flutter_rust_bridge::frb;
use matrix_sdk::{
    Room,
    ruma::{OwnedEventId, OwnedRoomId, events::StateEventType},
};
use matrix_sdk_ui::{
    room_list_service::{RoomListService, State},
    timeline::TimelineFocus,
};
use tokio::task::AbortHandle;

use super::{
    error::{CoreError, parse_id},
    session::Session,
    timeline::Timeline,
};
use crate::frb_generated::StreamSink;

/// The pins of a room. While it lives, the sync follows the room closely, as Element X does
/// for an open room: only then does it bring the room's `m.room.pinned_events`. Dropping it
/// stops its stream.
#[frb(opaque)]
pub struct Pins {
    room: Room,
    room_list: Arc<RoomListService>,
    subscriptions: Arc<Mutex<HashMap<OwnedRoomId, usize>>>,
    tasks: Mutex<Vec<AbortHandle>>,
}

impl std::fmt::Debug for Pins {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Pins")
            .field("room", &self.room.room_id())
            .finish_non_exhaustive()
    }
}

/// Which events of a room are pinned, and whether the user may change that.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RoomPins {
    /// The pinned event IDs in the order they were pinned: the last one was pinned last.
    pub event_ids: Vec<String>,
    /// Whether the user may pin and unpin (the power level for `m.room.pinned_events`).
    pub can_pin: bool,
}

impl Session {
    /// The pins of a room the user is in.
    ///
    /// # Errors
    ///
    /// [`CoreError::InvalidId`] or [`CoreError::RoomNotFound`].
    pub async fn pins(&self, room_id: String) -> Result<Pins, CoreError> {
        let room = self.room(&room_id)?;
        let room_list = self.sync.room_list_service();
        let subscribed: Vec<OwnedRoomId> = {
            let mut subscriptions = self
                .room_subscriptions
                .lock()
                .unwrap_or_else(PoisonError::into_inner);
            *subscriptions.entry(room.room_id().to_owned()).or_default() += 1;
            subscriptions.keys().cloned().collect()
        };
        let ids: Vec<_> = subscribed.iter().map(AsRef::as_ref).collect();
        room_list.set_room_subscriptions(&ids).await;
        Ok(Pins {
            room,
            room_list,
            subscriptions: self.room_subscriptions.clone(),
            tasks: Mutex::default(),
        })
    }

    /// A timeline of only the room's pinned messages, oldest first, with their reactions and
    /// edits. It loads them from the server when they aren't stored yet, decrypts them in an
    /// encrypted room, and follows pinning and unpinning.
    ///
    /// # Errors
    ///
    /// [`CoreError::InvalidId`], [`CoreError::RoomNotFound`], or if it can't be built.
    pub async fn pinned_timeline(&self, room_id: String) -> Result<Timeline, CoreError> {
        self.focused_timeline(room_id, TimelineFocus::PinnedEvents)
            .await
    }
}

impl Pins {
    /// Sends the pins now and after every change.
    pub async fn subscribe(&self, sink: StreamSink<RoomPins>) {
        self.updates(move |pins| sink.add(pins).is_ok()).await;
    }

    /// Like [`Self::subscribe`], for Rust callers: `emit` gets each state and returns `false`
    /// to stop.
    #[frb(ignore)]
    #[allow(
        clippy::unused_async,
        reason = "async so flutter_rust_bridge runs it on its tokio runtime, which spawn needs"
    )]
    pub async fn updates(&self, emit: impl Fn(RoomPins) -> bool + Send + 'static) {
        let room = self.room.clone();
        let mut infos = room.subscribe_info();
        let handle = tokio::spawn(async move {
            // Until the sync brings the room's pins, they are asked for once.
            let fetched = if room.pinned_event_ids().is_none() {
                room.load_pinned_events().await.ok().flatten()
            } else {
                None
            };
            let mut last = room_pins(&room, fetched.as_deref()).await;
            if !emit(last.clone()) {
                return;
            }
            // Every change to the room's info, a new pin or power level among them.
            while infos.next().await.is_some() {
                let pins = room_pins(&room, fetched.as_deref()).await;
                if pins != last {
                    last = pins.clone();
                    if !emit(pins) {
                        break;
                    }
                }
            }
        })
        .abort_handle();
        let mut tasks = self.tasks.lock().unwrap_or_else(PoisonError::into_inner);
        tasks.retain(|task| !task.is_finished());
        tasks.push(handle);
    }

    /// Pins the event `event_id`, as the last pin. Returns `false` if it was pinned already.
    ///
    /// # Errors
    ///
    /// [`CoreError::InvalidId`], or as the server answers ([`CoreError::Forbidden`] without
    /// the power level).
    pub async fn pin(&self, event_id: String) -> Result<bool, CoreError> {
        let event_id: OwnedEventId = parse_id(&event_id)?;
        Ok(self.room.pin_event(&event_id).await?)
    }

    /// Unpins the event `event_id`. Returns `false` if it wasn't pinned.
    ///
    /// # Errors
    ///
    /// As [`Self::pin`].
    pub async fn unpin(&self, event_id: String) -> Result<bool, CoreError> {
        let event_id: OwnedEventId = parse_id(&event_id)?;
        Ok(self.room.unpin_event(&event_id).await?)
    }
}

impl Drop for Pins {
    fn drop(&mut self) {
        let tasks = self.tasks.get_mut().unwrap_or_else(PoisonError::into_inner);
        for task in tasks.drain(..) {
            task.abort();
        }
        let mut subscriptions = self
            .subscriptions
            .lock()
            .unwrap_or_else(PoisonError::into_inner);
        let room_id = self.room.room_id();
        if let Some(count) = subscriptions.get_mut(room_id) {
            *count -= 1;
            if *count == 0 {
                subscriptions.remove(room_id);
                self.room_list.remove_room_subscriptions(&[room_id]);
            }
        }
    }
}

/// Puts the room subscriptions back after the sliding sync session expired, until the room
/// list service is gone.
///
/// When the server answers `M_UNKNOWN_POS`, the SDK resets the session and drops every room
/// subscription (`SlidingSync::expire_session`), and the sync recovers without them: the
/// subscribed rooms then no longer bring their `m.room.pinned_events`, which only a room
/// subscription asks for. Synapse answers so whenever a long poll cancelled to add a
/// subscription still finishes on the server after the request that replaced it: its
/// position wipes out the new one. So every time the room list (re)starts or recovers, the
/// rooms the app still wants are subscribed again; a subscription that is already there is
/// left as it is.
pub(crate) async fn keep_room_subscriptions(
    room_list: Arc<RoomListService>,
    subscriptions: Arc<Mutex<HashMap<OwnedRoomId, usize>>>,
) {
    let mut states = room_list.state();
    let mut after_error = false;
    while let Some(state) = states.next().await {
        let resubscribe = match state {
            State::Error { .. } | State::Terminated { .. } => {
                after_error = true;
                false
            }
            State::Init | State::SettingUp | State::Recovering => true,
            State::Running => after_error,
        };
        if !resubscribe {
            continue;
        }
        after_error = false;
        let subscribed: Vec<OwnedRoomId> = subscriptions
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .keys()
            .cloned()
            .collect();
        if !subscribed.is_empty() {
            let ids: Vec<_> = subscribed.iter().map(AsRef::as_ref).collect();
            room_list.set_room_subscriptions(&ids).await;
        }
    }
}

/// The room's pins from its state, else `fetched` (from the server, before the sync had them).
async fn room_pins(room: &Room, fetched: Option<&[OwnedEventId]>) -> RoomPins {
    let can_pin = room.power_levels().await.is_ok_and(|levels| {
        levels.user_can_send_state(room.own_user_id(), StateEventType::RoomPinnedEvents)
    });
    let ids = room.pinned_event_ids();
    RoomPins {
        event_ids: ids
            .as_deref()
            .or(fetched)
            .unwrap_or_default()
            .iter()
            .map(ToString::to_string)
            .collect(),
        can_pin,
    }
}
