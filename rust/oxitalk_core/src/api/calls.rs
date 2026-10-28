//! Voice and video calls: MatrixRTC signalling as Element Call speaks it on servers without
//! sticky (MSC4354) or delayed (MSC4140) events, which is every server OxiTalk targets today.
//!
//! - **Membership**: one `org.matrix.msc3401.call.member` room state event per device (state
//!   key `_@user:server_DEVICE_m.call`), application `m.call`, `call_id` `""` (the room's
//!   call), a LiveKit transport by its `livekit_service_url`, and an expiry that the joined
//!   device pushes forward before it runs out. Leaving sends empty content. Wire format:
//!   matrix-js-sdk `src/matrixrtc/MembershipManager.ts` (`makeMyMembership`,
//!   `makeMembershipStateKey`) and `membershipData/session.ts`.
//! - **Media**: LiveKit, joined with a token from the transport's lk-jwt-service (`/sfu/get`,
//!   with an OpenID token from the homeserver). The participant identity there is
//!   `@user:server:DEVICE`.
//! - **Media keys**: each device makes its own 16-byte key, sends it Olm-encrypted to every other
//!   device in the call as `io.element.call.encryption_keys`, shares it with new joiners and
//!   makes a new one when someone leaves (matrix-js-sdk `RTCEncryptionManager.ts`,
//!   `ToDeviceKeyTransport.ts`). The app hands the keys to LiveKit's frame encryption.
//! - **Ringing**: an `m.rtc.notification` (MSC4075) when the user starts a call, `ring` in a
//!   direct chat and `notification` elsewhere, sent under the unstable type Element Call sends
//!   and reads (`org.matrix.msc4075.rtc.notification`), which matrix-rust-sdk reads too; both
//!   types are read. Declining is an `org.matrix.msc4310.rtc.decline` (MSC4310).

use std::{
    collections::{BTreeMap, HashSet},
    fmt,
    sync::{Arc, Mutex, PoisonError},
    time::{Duration, Instant},
};

use base64::{
    Engine,
    engine::general_purpose::{STANDARD, STANDARD_NO_PAD},
};
use flutter_rust_bridge::frb;
use matrix_sdk::{
    Client, Room,
    deserialized_responses::{RawAnySyncOrStrippedState, TimelineEvent},
    event_handler::EventHandlerDropGuard,
    ruma::{
        MilliSecondsSinceUnixEpoch, OwnedEventId, OwnedRoomId, OwnedUserId,
        api::client::account::request_openid_token,
        events::{
            AnySyncTimelineEvent, AnyToDeviceEvent, AnyToDeviceEventContent, StateEventType,
            ToDeviceEventType, room::encrypted::OriginalSyncRoomEncryptedEvent,
            rtc::decline::RtcDeclineEventContent,
        },
        serde::Raw,
        to_device::DeviceIdOrAllDevices,
    },
};
use serde_json::{Value, json};
use tokio::{
    runtime::Handle,
    sync::{broadcast, mpsc, watch},
    task::AbortHandle,
};

use super::{
    error::{CoreError, parse_id},
    session::Session,
};
use crate::frb_generated::StreamSink;

/// The room state event that says a device is in a call.
pub(crate) const CALL_MEMBER_TYPE: &str = "org.matrix.msc3401.call.member";
/// The to-device event that carries a device's media key.
const KEYS_TYPE: &str = "io.element.call.encryption_keys";
/// The ringing event, stable (MSC4075 as ruma and matrix-rust-sdk have it).
const NOTIFICATION_TYPE: &str = "m.rtc.notification";
/// The ringing event as Element Call (matrix-js-sdk `EventType.RTCNotification`) sends it.
const NOTIFICATION_TYPE_UNSTABLE: &str = "org.matrix.msc4075.rtc.notification";
/// The call's slot, as matrix-js-sdk names the room's call (`computeSlotId`).
const ROOM_SLOT_ID: &str = "m.call#ROOM";

/// How long a membership is valid without a refresh when it doesn't say
/// (matrix-js-sdk `DEFAULT_EXPIRE_DURATION`).
const DEFAULT_EXPIRES_MS: i64 = 4 * 60 * 60 * 1000;
/// How long each of our memberships is valid; the joined device pushes it forward by this much
/// before it runs out. Without delayed events a crashed device shows in the call until then,
/// so it is shorter than Element's 4 hours.
const MEMBERSHIP_EXPIRY_MS: i64 = 30 * 60 * 1000;
/// How long before the expiry the membership is refreshed.
const MEMBERSHIP_REFRESH_HEADROOM_MS: i64 = 60 * 1000;

/// How long a ring lasts. MSC4075 caps it at 2 minutes (matrix-js-sdk
/// `RTC_NOTIFICATION_MAX_LIFETIME_MS`).
const RING_LIFETIME_MS: i64 = 60 * 1000;
const MAX_RING_LIFETIME_MS: i64 = 2 * 60 * 1000;
/// A sender clock further ahead than this is not trusted (matrix-js-sdk
/// `RTC_NOTIFICATION_MAX_SENDER_TS_AHEAD_MS`).
const MAX_SENDER_TS_AHEAD_MS: i64 = 20 * 1000;

/// A new own key is used this long after it was sent, so it reaches the others first
/// (matrix-js-sdk `RTCEncryptionManager`, `useKeyDelay` as joined).
const NEW_KEY_DELAY: Duration = Duration::from_secs(1);
/// Someone joining within this time of the key's creation gets the current key instead of a
/// new one (matrix-js-sdk `keyRotationGracePeriodMs`).
const KEY_GRACE_PERIOD: Duration = Duration::from_secs(10);

/// How long a ring waits for the call it is about to show up in the room's state.
const CALL_STATE_WAIT: Duration = Duration::from_secs(5);
/// How long an encrypted ring is retried while its room key is on the way.
const DECRYPT_RETRY: Duration = Duration::from_secs(12);

/// Audio only, or video too.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CallIntent {
    Audio,
    Video,
}

impl CallIntent {
    fn parse(value: &str) -> Option<Self> {
        match value {
            "audio" => Some(Self::Audio),
            "video" => Some(Self::Video),
            _ => None,
        }
    }

    fn as_str(self) -> &'static str {
        match self {
            Self::Audio => "audio",
            Self::Video => "video",
        }
    }
}

/// Whom to tell that the user started a call.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CallNotify {
    /// Nobody: the user joins a call that is already going on.
    None,
    /// Ring the other members' devices (a direct chat).
    Ring,
    /// Notify the room without ringing (a group).
    Notify,
}

/// One device in a room's call.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CallParticipant {
    pub user_id: String,
    pub device_id: String,
    /// Its name in LiveKit, `@user:server:DEVICE`.
    pub identity: String,
    /// The member's name in the room, if they have one.
    pub display_name: Option<String>,
    pub avatar_url: Option<String>,
    /// What the device said it joined for, if it said.
    pub intent: Option<CallIntent>,
    /// When it joined, in ms since the Unix epoch.
    pub joined_at_ms: i64,
    /// When its membership runs out unless it is refreshed.
    pub expires_at_ms: i64,
    /// The user's own account (any device).
    pub is_own_user: bool,
    /// This very device.
    pub is_this_device: bool,
}

/// A room's call as its state says: who is in it, oldest first. No participants, no call.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RoomCall {
    pub room_id: String,
    pub participants: Vec<CallParticipant>,
    /// The intent the participants agree on, if they all say the same.
    pub intent: Option<CallIntent>,
    /// The LiveKit service the oldest participant uses, which joining uses too.
    pub service_url: Option<String>,
}

impl RoomCall {
    /// Whether anybody is in the call.
    #[frb(sync)]
    #[must_use]
    pub fn is_active(&self) -> bool {
        !self.participants.is_empty()
    }
}

/// A media key for LiveKit's frame encryption: the key `key` at `index` of `identity`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CallMediaKey {
    /// The LiveKit participant identity, `@user:server:DEVICE`.
    pub identity: String,
    pub index: u32,
    /// 16 random bytes; LiveKit derives the AES key from them (HKDF).
    pub key: Vec<u8>,
    /// This device's own key, the one it encrypts with.
    pub is_own: bool,
}

/// A ring addressed to the user.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct IncomingCall {
    pub room_id: String,
    /// The `m.rtc.notification` event, to decline it.
    pub notification_event_id: String,
    pub sender_id: String,
    pub sender_name: Option<String>,
    pub sender_avatar_url: Option<String>,
    pub intent: Option<CallIntent>,
    /// `true` for a ring (a direct chat), `false` for a notification (a group).
    pub ring: bool,
    /// When the ring stops by itself, in ms since the Unix epoch.
    pub expires_at_ms: i64,
}

/// Why a ring stopped.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum IncomingCallEnd {
    /// Nobody answered in time.
    Expired,
    /// The caller hung up; nobody is in the call any more.
    CallEnded,
    /// The user joined, here or on another device.
    Answered,
    /// The user declined, here or on another device.
    Declined,
}

/// A ring starting or stopping.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum IncomingCallUpdate {
    Ringing {
        call: IncomingCall,
    },
    Ended {
        room_id: String,
        notification_event_id: String,
        reason: IncomingCallEnd,
    },
}

/// One `org.matrix.msc3401.call.member` event for the room's call, still valid or not.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct RtcMembership {
    pub(crate) state_key: String,
    pub(crate) user_id: String,
    pub(crate) device_id: String,
    pub(crate) created_ts: i64,
    pub(crate) expires_at: i64,
    pub(crate) intent: Option<CallIntent>,
    pub(crate) service_url: Option<String>,
    pub(crate) event_id: Option<String>,
}

impl RtcMembership {
    pub(crate) fn identity(&self) -> String {
        format!("{}:{}", self.user_id, self.device_id)
    }
}

/// Reads a call membership state event (`sender`, `state_key`, `origin_server_ts`,
/// `content`). `None` for anything but a device in the room's own `m.call` (a left device's
/// empty content, another application, a breakout `call_id`, the 2023 list format).
pub(crate) fn parse_membership(event: &Value) -> Option<RtcMembership> {
    let content = event.get("content")?.as_object()?;
    let sender = event.get("sender")?.as_str()?;
    let state_key = event.get("state_key")?.as_str()?;
    let origin = event.get("origin_server_ts")?.as_i64()?;
    if content.get("application")?.as_str()? != "m.call"
        || !content.get("call_id")?.as_str()?.is_empty()
        || content
            .get("scope")
            .is_some_and(|scope| scope.as_str() != Some("m.room"))
    {
        return None;
    }
    // A user can only speak for their own devices: the state key starts with their ID
    // (optionally after an underscore, matrix-js-sdk `makeMembershipStateKey`).
    let owner = state_key.strip_prefix('_').unwrap_or(state_key);
    if !owner.starts_with(sender)
        || !owner[sender.len()..].starts_with('_') && owner.len() != sender.len()
    {
        return None;
    }
    let device_id = content.get("device_id")?.as_str()?;
    content.get("focus_active")?.get("type")?.as_str()?;
    let created_ts = content
        .get("created_ts")
        .and_then(Value::as_i64)
        .unwrap_or(origin);
    let expires = content
        .get("expires")
        .and_then(Value::as_i64)
        .unwrap_or(DEFAULT_EXPIRES_MS);
    let service_url = content
        .get("foci_preferred")
        .and_then(Value::as_array)
        .and_then(|foci| {
            foci.iter().find_map(|focus| {
                (focus.get("type")?.as_str()? == "livekit")
                    .then(|| focus.get("livekit_service_url")?.as_str())
                    .flatten()
                    .map(ToOwned::to_owned)
            })
        });
    Some(RtcMembership {
        state_key: state_key.to_owned(),
        user_id: sender.to_owned(),
        device_id: device_id.to_owned(),
        created_ts,
        expires_at: created_ts.saturating_add(expires),
        intent: content
            .get("m.call.intent")
            .and_then(Value::as_str)
            .and_then(CallIntent::parse),
        service_url,
        event_id: event
            .get("event_id")
            .and_then(Value::as_str)
            .map(ToOwned::to_owned),
    })
}

/// The memberships still valid at `now`, oldest first.
pub(crate) fn active_memberships(events: &[Value], now: i64) -> Vec<RtcMembership> {
    let mut memberships: Vec<RtcMembership> = events
        .iter()
        .filter_map(parse_membership)
        .filter(|membership| membership.expires_at > now)
        .collect();
    memberships.sort_by(|a, b| {
        a.created_ts
            .cmp(&b.created_ts)
            .then_with(|| a.state_key.cmp(&b.state_key))
    });
    memberships
}

/// The state key of a device's membership, as matrix-js-sdk makes it for room versions without
/// owned state events (MSC3757/MSC3779): `_@user:server_DEVICE_m.call`.
pub(crate) fn membership_state_key(user_id: &str, device_id: &str) -> String {
    format!("_{user_id}_{device_id}_m.call")
}

/// The content of the device's membership, valid for `expires` ms from `created_ts` (the first
/// event's own time when `None`).
pub(crate) fn membership_content(
    device_id: &str,
    identity: &str,
    room_id: &str,
    service_url: &str,
    intent: CallIntent,
    expires: i64,
    created_ts: Option<i64>,
) -> Value {
    let mut content = json!({
        "application": "m.call",
        "call_id": "",
        "scope": "m.room",
        "device_id": device_id,
        "membershipID": identity,
        "expires": expires,
        "m.call.intent": intent.as_str(),
        "focus_active": { "type": "livekit", "focus_selection": "multi_sfu" },
        "foci_preferred": [{
            "type": "livekit",
            "livekit_service_url": service_url,
            "livekit_alias": room_id,
        }],
    });
    if let (Some(created_ts), Some(object)) = (created_ts, content.as_object_mut()) {
        object.insert("created_ts".to_owned(), json!(created_ts));
    }
    content
}

/// The content of a ring or notification for the call the membership `membership_event_id`
/// joined, addressed to `user_ids` (and with `room` to the whole room).
pub(crate) fn notification_content(
    notify: CallNotify,
    intent: CallIntent,
    membership_event_id: &str,
    user_ids: &[String],
    room: bool,
    now: i64,
) -> Value {
    json!({
        "slot_id": ROOM_SLOT_ID,
        "m.mentions": { "user_ids": user_ids, "room": room },
        "notification_type": if notify == CallNotify::Ring { "ring" } else { "notification" },
        "m.relates_to": { "rel_type": "m.reference", "event_id": membership_event_id },
        "sender_ts": now,
        "lifetime": RING_LIFETIME_MS,
        "m.call.intent": intent.as_str(),
    })
}

/// When a ring stops counting, as MSC4075 says: from the sender's clock unless it is too far
/// ahead of the server's, for at most two minutes.
pub(crate) fn ring_expiry(sender_ts: i64, origin_server_ts: i64, lifetime: i64) -> i64 {
    let basis = if sender_ts - origin_server_ts > MAX_SENDER_TS_AHEAD_MS {
        origin_server_ts
    } else {
        sender_ts
    };
    basis.saturating_add(lifetime.clamp(0, MAX_RING_LIFETIME_MS))
}

/// What a ring event says, if it is one addressed to `own` that is still ringing at `now`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct Ring {
    pub(crate) event_id: String,
    pub(crate) sender: String,
    pub(crate) intent: Option<CallIntent>,
    /// `ring`, not just `notification`.
    pub(crate) rings: bool,
    pub(crate) expires_at: i64,
}

pub(crate) fn parse_ring(event: &Value, own: &str, now: i64) -> Option<Ring> {
    let event_type = event.get("type")?.as_str()?;
    if event_type != NOTIFICATION_TYPE && event_type != NOTIFICATION_TYPE_UNSTABLE {
        return None;
    }
    let sender = event.get("sender")?.as_str()?;
    if sender == own {
        return None;
    }
    let content = event.get("content")?;
    let origin = event.get("origin_server_ts")?.as_i64()?;
    let sender_ts = content.get("sender_ts")?.as_i64()?;
    let lifetime = content.get("lifetime")?.as_i64()?;
    let expires_at = ring_expiry(sender_ts, origin, lifetime);
    if expires_at <= now {
        return None;
    }
    let mentions = content.get("m.mentions")?;
    let to_room = mentions.get("room").and_then(Value::as_bool) == Some(true);
    let to_user = mentions
        .get("user_ids")
        .and_then(Value::as_array)
        .is_some_and(|users| users.iter().any(|user| user.as_str() == Some(own)));
    if !to_room && !to_user {
        return None;
    }
    Some(Ring {
        event_id: event.get("event_id")?.as_str()?.to_owned(),
        sender: sender.to_owned(),
        intent: content
            .get("m.call.intent")
            .and_then(Value::as_str)
            .and_then(CallIntent::parse),
        rings: content.get("notification_type").and_then(Value::as_str) == Some("ring"),
        expires_at,
    })
}

/// A received media key: who sent it (`identity`) and the key.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct ReceivedKey {
    pub(crate) user_id: String,
    pub(crate) device_id: String,
    pub(crate) index: u32,
    pub(crate) key: Vec<u8>,
}

/// Reads an `io.element.call.encryption_keys` content for `room_id`, sent by `sender` from the
/// device the Olm session vouches for (`verified_device`). Keys sent in the clear, for another
/// room, or claiming another device than the Olm session's are dropped.
pub(crate) fn parse_key(
    content: &Value,
    sender: &str,
    verified_device: Option<&str>,
    room_id: &str,
) -> Option<ReceivedKey> {
    if content.get("room_id")?.as_str()? != room_id {
        return None;
    }
    let media_key = content
        .get("media_key")
        .filter(|key| key.is_object())
        .or_else(|| content.get("keys"))?;
    let encoded = media_key.get("key")?.as_str()?;
    let index = u32::try_from(media_key.get("index")?.as_u64()?).ok()?;
    let key = STANDARD
        .decode(encoded)
        .or_else(|_| STANDARD_NO_PAD.decode(encoded))
        .ok()
        .filter(|key| !key.is_empty())?;
    let device_id = content.get("member")?.get("claimed_device_id")?.as_str()?;
    if verified_device.is_some_and(|verified| verified != device_id) {
        return None;
    }
    Some(ReceivedKey {
        user_id: sender.to_owned(),
        device_id: device_id.to_owned(),
        index,
        key,
    })
}

/// The content of the to-device message that gives our key to the others.
pub(crate) fn key_content(
    room_id: &str,
    identity: &str,
    device_id: &str,
    index: u32,
    key: &[u8],
) -> Value {
    let media_key = json!({ "index": index, "key": STANDARD.encode(key) });
    json!({
        "room_id": room_id,
        "member_id": identity,
        "media_key": media_key,
        // Deprecated, still read by older Element Call (matrix-js-sdk ToDeviceKeyTransport).
        "keys": media_key,
        "member": { "claimed_device_id": device_id, "id": identity },
    })
}

/// A device in the call, as the key distribution counts it: a new `created_ts` is a new join.
type Peer = (String, String, i64);

/// What our key has to do after the call's members changed.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum KeyPlan {
    /// Nothing changed for the key.
    Keep,
    /// Send the current key to these newcomers.
    Share(Vec<Peer>),
    /// Make a new key and send it to everybody.
    Rotate(Vec<Peer>),
}

/// matrix-js-sdk's rule (`RTCEncryptionManager.rolloutOutboundKey`): a new key when someone
/// left; for someone joining, the current key while it is young, else a new one.
pub(crate) fn plan_keys(shared_with: &[Peer], current: &[Peer], key_age: Duration) -> KeyPlan {
    let shared: Vec<&Peer> = shared_with
        .iter()
        // Someone who joined again (a new created_ts) dropped their keys: they count as new.
        .filter(|old| {
            !current
                .iter()
                .any(|new| new.0 == old.0 && new.1 == old.1 && new.2 != old.2)
        })
        .collect();
    let left = shared.iter().any(|old| !current.contains(old));
    let joined: Vec<Peer> = current
        .iter()
        .filter(|new| !shared.contains(new))
        .cloned()
        .collect();
    if left {
        KeyPlan::Rotate(current.to_vec())
    } else if joined.is_empty() {
        KeyPlan::Keep
    } else if key_age < KEY_GRACE_PERIOD {
        KeyPlan::Share(joined)
    } else {
        KeyPlan::Rotate(current.to_vec())
    }
}

fn now_ms() -> i64 {
    i64::from(MilliSecondsSinceUnixEpoch::now().get())
}

fn random_key() -> Result<Vec<u8>, CoreError> {
    let mut key = vec![0_u8; 16];
    getrandom::fill(&mut key).map_err(|error| CoreError::internal(&error))?;
    Ok(key)
}

/// The room's call memberships from its state, as JSON events.
async fn membership_events(room: &Room) -> Vec<Value> {
    let Ok(events) = room
        .get_state_events(StateEventType::from(CALL_MEMBER_TYPE))
        .await
    else {
        return Vec::new();
    };
    events
        .into_iter()
        .filter_map(|event| match event {
            RawAnySyncOrStrippedState::Sync(raw) => raw.deserialize_as::<Value>().ok(),
            RawAnySyncOrStrippedState::Stripped(_) => None,
        })
        .collect()
}

async fn room_call(room: &Room, own_user: &str, own_device: &str, now: i64) -> RoomCall {
    let memberships = active_memberships(&membership_events(room).await, now);
    let mut participants = Vec::with_capacity(memberships.len());
    for membership in &memberships {
        let (display_name, avatar_url) = match parse_id::<OwnedUserId>(&membership.user_id) {
            Ok(user) => match room.get_member_no_sync(&user).await {
                Ok(Some(member)) => (
                    member.display_name().map(ToOwned::to_owned),
                    member.avatar_url().map(ToString::to_string),
                ),
                _ => (None, None),
            },
            Err(_) => (None, None),
        };
        participants.push(CallParticipant {
            user_id: membership.user_id.clone(),
            device_id: membership.device_id.clone(),
            identity: membership.identity(),
            display_name,
            avatar_url,
            intent: membership.intent,
            joined_at_ms: membership.created_ts,
            expires_at_ms: membership.expires_at,
            is_own_user: membership.user_id == own_user,
            is_this_device: membership.user_id == own_user && membership.device_id == own_device,
        });
    }
    let mut intents = memberships.iter().filter_map(|m| m.intent);
    let intent = intents
        .next()
        .filter(|first| intents.all(|other| other == *first));
    RoomCall {
        room_id: room.room_id().to_string(),
        participants,
        intent,
        service_url: memberships.iter().find_map(|m| m.service_url.clone()),
    }
}

/// How long until the first of these memberships runs out, for a recount then.
fn next_expiry(call: &RoomCall, now: i64) -> Option<Duration> {
    call.participants
        .iter()
        .map(|participant| participant.expires_at_ms)
        .min()
        .map(|at| Duration::from_millis(u64::try_from(at - now).unwrap_or(0) + 50))
}

impl Session {
    fn own_ids(&self) -> Result<(String, String), CoreError> {
        let user = self.client.user_id().ok_or(CoreError::SessionExpired)?;
        let device = self.client.device_id().ok_or(CoreError::SessionExpired)?;
        Ok((user.to_string(), device.to_string()))
    }

    /// The room's call now.
    ///
    /// # Errors
    ///
    /// [`CoreError::InvalidId`], [`CoreError::RoomNotFound`] or [`CoreError::SessionExpired`].
    pub async fn room_call(&self, room_id: String) -> Result<RoomCall, CoreError> {
        let room = self.room(&room_id)?;
        let (user, device) = self.own_ids()?;
        Ok(room_call(&room, &user, &device, now_ms()).await)
    }

    /// Sends the room's call now, then after every change: someone joining, leaving, or their
    /// membership running out.
    ///
    /// # Errors
    ///
    /// As [`Self::room_call`].
    #[allow(
        clippy::unused_async,
        clippy::unused_async_trait_impl,
        reason = "async so flutter_rust_bridge runs it on its tokio runtime, which spawn needs"
    )]
    pub async fn subscribe_room_call(
        &self,
        room_id: String,
        sink: StreamSink<RoomCall>,
    ) -> Result<(), CoreError> {
        self.room_call_updates(room_id, move |call| sink.add(call).is_ok())
    }

    /// Like [`Self::subscribe_room_call`], for Rust callers: `emit` gets each state and returns
    /// `false` to stop. Must run on a tokio runtime.
    ///
    /// # Errors
    ///
    /// As [`Self::room_call`].
    #[frb(ignore)]
    pub fn room_call_updates(
        &self,
        room_id: String,
        emit: impl Fn(RoomCall) -> bool + Send + 'static,
    ) -> Result<(), CoreError> {
        let room = self.room(&room_id)?;
        let (user, device) = self.own_ids()?;
        let mut infos = room.subscribe_info();
        let joined_here = self.active_calls.clone();
        self.spawn(async move {
            let mut last: Option<RoomCall> = None;
            let mut cleaned = false;
            loop {
                let now = now_ms();
                let call = room_call(&room, &user, &device, now).await;
                // A membership of this device that no call here keeps up was left behind by a
                // crash or a kill: take it back, once.
                if !cleaned
                    && call.participants.iter().any(|p| p.is_this_device)
                    && !lock(&joined_here).contains(room.room_id())
                {
                    cleaned = true;
                    let key = membership_state_key(&user, &device);
                    if let Err(error) = room
                        .send_state_event_raw(CALL_MEMBER_TYPE, &key, json!({}))
                        .await
                    {
                        tracing::warn!(%error, "couldn't take back a stale call membership");
                    }
                }
                let wake = next_expiry(&call, now);
                if last.as_ref() != Some(&call) {
                    last = Some(call.clone());
                    if !emit(call) {
                        return;
                    }
                }
                let changed = async {
                    match wake {
                        Some(after) => tokio::time::timeout(after, infos.next())
                            .await
                            .map_or(Some(()), |info| info.map(|_| ())),
                        None => infos.next().await.map(|_| ()),
                    }
                };
                if changed.await.is_none() {
                    return;
                }
            }
        });
        Ok(())
    }

    /// The LiveKit services the homeserver offers for calls (MSC4143 `rtc/transports`, Synapse's
    /// unstable path, then the well-known `org.matrix.msc4143.rtc_foci`), as their
    /// `livekit_service_url`s. Empty when it offers none.
    ///
    /// # Errors
    ///
    /// [`CoreError::SessionExpired`], or [`CoreError::Network`] when the server can't be
    /// reached.
    pub async fn call_services(&self) -> Result<Vec<String>, CoreError> {
        let mut urls = match self.client.discover_rtc_transports().await {
            Ok(Some(transports)) => livekit_urls(
                transports
                    .iter()
                    .map(|t| (t.transport_type().to_owned(), t.data().into_owned())),
            ),
            Ok(None) => Vec::new(),
            Err(error) => {
                tracing::info!(%error, "no v1 rtc/transports");
                Vec::new()
            }
        };
        if urls.is_empty() {
            urls = self.unstable_rtc_transports().await?;
        }
        Ok(urls)
    }

    /// `GET /_matrix/client/unstable/org.matrix.msc4143/rtc/transports`, which Synapse serves
    /// (it has no v1 path yet).
    async fn unstable_rtc_transports(&self) -> Result<Vec<String>, CoreError> {
        let token = self
            .client
            .access_token()
            .ok_or(CoreError::SessionExpired)?;
        let url = self.homeserver_path(&[
            "_matrix",
            "client",
            "unstable",
            "org.matrix.msc4143",
            "rtc",
            "transports",
        ])?;
        let response = self
            .client
            .http_client()
            .get(url)
            .bearer_auth(token)
            .timeout(Duration::from_secs(10))
            .send()
            .await
            .map_err(|error| CoreError::Network {
                message: error.to_string(),
            })?;
        if !response.status().is_success() {
            return Ok(Vec::new());
        }
        let body: Value = serde_json::from_slice(
            &response
                .bytes()
                .await
                .map_err(|error| CoreError::internal(&error))?,
        )
        .unwrap_or(Value::Null);
        let transports = body
            .get("rtc_transports")
            .and_then(Value::as_array)
            .cloned()
            .unwrap_or_default();
        Ok(livekit_urls(transports.into_iter().filter_map(|t| {
            let mut object = t.as_object()?.clone();
            let kind = object.remove("type")?.as_str()?.to_owned();
            Some((kind, object))
        })))
    }

    fn homeserver_path(&self, segments: &[&str]) -> Result<matrix_sdk::reqwest::Url, CoreError> {
        let mut url = self.client.homeserver();
        url.path_segments_mut()
            .map_err(|()| CoreError::internal(&"the homeserver URL can't have a path"))?
            .pop_if_empty()
            .extend(segments);
        Ok(url)
    }

    /// Joins the room's call (starting it if nobody is in it) with this device: a LiveKit token,
    /// then the membership, kept fresh until [`ActiveCall::leave`]; then rings or notifies as
    /// `notify` says. The returned call has the LiveKit address and token and streams the media
    /// keys.
    ///
    /// # Errors
    ///
    /// [`CoreError::RoomNotFound`]; [`CoreError::Internal`] when the server offers no call
    /// service; [`CoreError::Forbidden`] when the room doesn't let the user join calls or the
    /// call service refuses; otherwise as the servers answer.
    pub async fn join_call(
        &self,
        room_id: String,
        intent: CallIntent,
        notify: CallNotify,
    ) -> Result<ActiveCall, CoreError> {
        self.join_call_with(room_id, intent, notify, None).await
    }

    /// [`Self::join_call`], for Rust callers. With `no_media`, only the Matrix side: the call
    /// service `no_media` names is written in the membership but no LiveKit token is asked
    /// (the tests of the signalling run on servers without an SFU).
    ///
    /// # Errors
    ///
    /// As [`Self::join_call`].
    #[frb(ignore)]
    pub async fn join_call_with(
        &self,
        room_id: String,
        intent: CallIntent,
        notify: CallNotify,
        no_media: Option<String>,
    ) -> Result<ActiveCall, CoreError> {
        let room = self.room(&room_id)?;
        let (user, device) = self.own_ids()?;
        let identity = format!("{user}:{device}");
        // Everybody on the oldest member's SFU, as Element Call does; else ours.
        let existing = room_call(&room, &user, &device, now_ms()).await;
        let service_url = match (existing.service_url.clone(), &no_media) {
            (Some(url), _) => url,
            (None, Some(url)) => url.clone(),
            (None, None) => self
                .call_services()
                .await?
                .into_iter()
                .next()
                .ok_or_else(|| CoreError::Internal {
                    message: "the homeserver offers no call service (rtc/transports)".to_owned(),
                })?,
        };
        let (livekit_url, livekit_token) = if no_media.is_some() {
            (String::new(), String::new())
        } else {
            livekit_token(&self.client, &room_id, &service_url, &device).await?
        };

        lock(&self.active_calls).insert(room.room_id().to_owned());
        let state_key = membership_state_key(&user, &device);
        let joined_at = now_ms();
        let content = membership_content(
            &device,
            &identity,
            &room_id,
            &service_url,
            intent,
            MEMBERSHIP_EXPIRY_MS,
            None,
        );
        let sent = match room
            .send_state_event_raw(CALL_MEMBER_TYPE, &state_key, content)
            .await
        {
            Ok(sent) => sent,
            Err(error) => {
                lock(&self.active_calls).remove(room.room_id());
                return Err(error.into());
            }
        };

        let inner = Arc::new(CallInner {
            client: self.client.clone(),
            room: room.clone(),
            user,
            device,
            identity,
            state_key,
            service_url,
            livekit_url,
            livekit_token,
            intent,
            active_calls: self.active_calls.clone(),
            keys: broadcast::channel(64).0,
            known_keys: Mutex::default(),
            tasks: Mutex::default(),
            left: Mutex::new(false),
            runtime: Handle::current(),
        });
        inner.start(joined_at);

        if notify != CallNotify::None
            && let Err(error) = inner.notify(notify, &sent.event_id).await
        {
            tracing::warn!(%error, "couldn't ring the call");
        }
        Ok(ActiveCall { inner })
    }

    /// Declines the ring `notification_event_id` in the room, for all the user's devices and
    /// the caller (MSC4310).
    ///
    /// # Errors
    ///
    /// [`CoreError::InvalidId`], [`CoreError::RoomNotFound`], or as the server answers.
    pub async fn decline_call(
        &self,
        room_id: String,
        notification_event_id: String,
    ) -> Result<(), CoreError> {
        let room = self.room(&room_id)?;
        let event_id: OwnedEventId = parse_id(&notification_event_id)?;
        room.send(RtcDeclineEventContent::new(event_id)).await?;
        Ok(())
    }

    /// Sends every ring addressed to the user from now on, and when each one stops. A ring
    /// counts while it is fresh (MSC4075 lifetime), the call it is about is going on and the
    /// user is not in it yet.
    #[allow(
        clippy::unused_async,
        reason = "async so flutter_rust_bridge runs it on its tokio runtime, which spawn needs"
    )]
    pub async fn subscribe_incoming_calls(&self, sink: StreamSink<IncomingCallUpdate>) {
        self.incoming_call_updates(move |update| sink.add(update).is_ok());
    }

    /// Like [`Self::subscribe_incoming_calls`], for Rust callers. Must run on a tokio runtime.
    #[frb(ignore)]
    pub fn incoming_call_updates(
        &self,
        emit: impl Fn(IncomingCallUpdate) -> bool + Send + Sync + 'static,
    ) {
        let Ok((user, device)) = self.own_ids() else {
            return;
        };
        let (sender, mut receiver) = mpsc::unbounded_channel::<(Room, Value)>();
        let plain = {
            let sender = sender.clone();
            self.client
                .add_event_handler(move |event: Raw<AnySyncTimelineEvent>, room: Room| {
                    let sender = sender.clone();
                    async move {
                        if let Some(value) = ring_event(&event) {
                            let _ = sender.send((room, value));
                        }
                    }
                })
        };
        // A ring in an encrypted room may come before its room key: retry it for a while.
        let encrypted = {
            let sender = sender.clone();
            let own = user.clone();
            self.client.add_event_handler(
                move |event: Raw<OriginalSyncRoomEncryptedEvent>, room: Room| {
                    let sender = sender.clone();
                    let own = own.clone();
                    async move {
                        tokio::spawn(retry_decrypt(room, event, own, sender));
                    }
                },
            )
        };
        let guards = (
            self.client.event_handler_drop_guard(plain),
            self.client.event_handler_drop_guard(encrypted),
        );
        let emit = Arc::new(emit);
        let client = self.client.clone();
        self.spawn(async move {
            let _guards = guards;
            let ringing: Arc<Mutex<HashSet<OwnedRoomId>>> = Arc::default();
            while let Some((room, event)) = receiver.recv().await {
                let Some(ring) = parse_ring(&event, &user, now_ms()) else {
                    continue;
                };
                if !lock(&ringing).insert(room.room_id().to_owned()) {
                    // Already ringing for this room (the same ring under its other type).
                    continue;
                }
                let emit = emit.clone();
                let ringing = ringing.clone();
                let client = client.clone();
                let (user, device) = (user.clone(), device.clone());
                tokio::spawn(async move {
                    follow_ring(&client, &room, ring, &user, &device, &*emit).await;
                    lock(&ringing).remove(room.room_id());
                });
            }
        });
    }
}

fn livekit_urls(
    transports: impl Iterator<Item = (String, serde_json::Map<String, Value>)>,
) -> Vec<String> {
    transports
        .filter(|(kind, _)| kind == "livekit")
        .filter_map(|(_, data)| {
            data.get("livekit_service_url")
                .and_then(Value::as_str)
                .map(ToOwned::to_owned)
        })
        .collect()
}

/// The event as JSON if it is a ring (either type).
fn ring_event(event: &Raw<AnySyncTimelineEvent>) -> Option<Value> {
    let value = event.deserialize_as::<Value>().ok()?;
    matches!(
        value.get("type").and_then(Value::as_str),
        Some(NOTIFICATION_TYPE | NOTIFICATION_TYPE_UNSTABLE)
    )
    .then_some(value)
}

async fn retry_decrypt(
    room: Room,
    event: Raw<OriginalSyncRoomEncryptedEvent>,
    own: String,
    sender: mpsc::UnboundedSender<(Room, Value)>,
) {
    // Only for fresh events: an old one can't ring any more.
    let fresh = event
        .get_field::<i64>("origin_server_ts")
        .ok()
        .flatten()
        .is_some_and(|ts| now_ms() - ts < MAX_RING_LIFETIME_MS);
    let from_other = event
        .get_field::<String>("sender")
        .ok()
        .flatten()
        .is_some_and(|sender| sender != own);
    if !fresh || !from_other {
        return;
    }
    let decrypted = retry_until(DECRYPT_RETRY, || async {
        decrypted(room.decrypt_event(&event, None).await)
    })
    .await;
    if let Some(value) = decrypted.as_ref().and_then(|event| ring_event(event.raw())) {
        let _ = sender.send((room, value));
    }
}

/// The event if it could be read. A missing room key is no error for the SDK: it gives the
/// event back as unable to decrypt, which must count as not decrypted yet.
fn decrypted<E>(result: Result<TimelineEvent, E>) -> Option<TimelineEvent> {
    result.ok().filter(|event| !event.kind.is_utd())
}

/// Calls `attempt` after growing waits (0.5 s, then doubling up to 3 s) until it gives a value
/// or `limit` has passed.
async fn retry_until<T, F, Fut>(limit: Duration, mut attempt: F) -> Option<T>
where
    F: FnMut() -> Fut,
    Fut: Future<Output = Option<T>>,
{
    let started = Instant::now();
    let mut wait = Duration::from_millis(500);
    while started.elapsed() < limit {
        tokio::time::sleep(wait).await;
        wait = (wait * 2).min(Duration::from_secs(3));
        if let Some(value) = attempt().await {
            return Some(value);
        }
    }
    None
}

/// Shows one ring until it stops: emits `Ringing` once the call is seen going on, then `Ended`.
async fn follow_ring(
    client: &Client,
    room: &Room,
    ring: Ring,
    own_user: &str,
    own_device: &str,
    emit: &(dyn Fn(IncomingCallUpdate) -> bool + Send + Sync),
) {
    let mut infos = room.subscribe_info();
    let Ok(event_id) = parse_id::<OwnedEventId>(&ring.event_id) else {
        return;
    };
    let (_decline_guard, mut decline_events) = room.subscribe_to_call_decline_events(&event_id);
    let own_user_id: Option<OwnedUserId> = parse_id(own_user).ok();
    let ended = |reason| IncomingCallUpdate::Ended {
        room_id: room.room_id().to_string(),
        notification_event_id: ring.event_id.clone(),
        reason,
    };

    // The call's membership may come a sync after the ring.
    let deadline = Instant::now() + CALL_STATE_WAIT;
    loop {
        let call = room_call(room, own_user, own_device, now_ms()).await;
        if call.participants.iter().any(|p| p.is_own_user) {
            return;
        }
        if call.is_active() {
            break;
        }
        let left = deadline.saturating_duration_since(Instant::now());
        if left.is_zero() || tokio::time::timeout(left, infos.next()).await.is_err() {
            return;
        }
    }

    let (sender_name, sender_avatar_url) = match parse_id::<OwnedUserId>(&ring.sender) {
        Ok(user) => match room.get_member_no_sync(&user).await {
            Ok(Some(member)) => (
                member.display_name().map(ToOwned::to_owned),
                member.avatar_url().map(ToString::to_string),
            ),
            _ => (None, None),
        },
        Err(_) => (None, None),
    };
    let call = IncomingCall {
        room_id: room.room_id().to_string(),
        notification_event_id: ring.event_id.clone(),
        sender_id: ring.sender.clone(),
        sender_name,
        sender_avatar_url,
        intent: ring.intent,
        ring: ring.rings,
        expires_at_ms: ring.expires_at,
    };
    if !emit(IncomingCallUpdate::Ringing { call }) {
        return;
    }
    let _ = client;
    loop {
        let left = Duration::from_millis(u64::try_from(ring.expires_at - now_ms()).unwrap_or(0));
        tokio::select! {
            () = tokio::time::sleep(left) => {
                emit(ended(IncomingCallEnd::Expired));
                return;
            }
            declined = decline_events.recv() => {
                match declined {
                    Ok(user) if Some(&user) == own_user_id.as_ref() => {
                        emit(ended(IncomingCallEnd::Declined));
                        return;
                    }
                    Ok(_) | Err(broadcast::error::RecvError::Lagged(_)) => {}
                    Err(broadcast::error::RecvError::Closed) => return,
                }
            }
            info = infos.next() => {
                if info.is_none() {
                    return;
                }
                let call = room_call(room, own_user, own_device, now_ms()).await;
                if call.participants.iter().any(|p| p.is_own_user) {
                    emit(ended(IncomingCallEnd::Answered));
                    return;
                }
                if !call.is_active() {
                    emit(ended(IncomingCallEnd::CallEnded));
                    return;
                }
            }
        }
    }
}

/// A LiveKit address and token for the room's call from the lk-jwt-service at `service_url`:
/// an OpenID token from the homeserver, then `POST {service_url}/sfu/get`.
async fn livekit_token(
    client: &Client,
    room_id: &str,
    service_url: &str,
    device_id: &str,
) -> Result<(String, String), CoreError> {
    let user = client
        .user_id()
        .ok_or(CoreError::SessionExpired)?
        .to_owned();
    let openid = client
        .send(request_openid_token::v3::Request::new(user))
        .await?;
    let body = json!({
        "room": room_id,
        "openid_token": {
            "access_token": openid.access_token,
            "token_type": openid.token_type.to_string(),
            "matrix_server_name": openid.matrix_server_name.to_string(),
            "expires_in": openid.expires_in.as_secs(),
        },
        "device_id": device_id,
    });
    let url = format!("{}/sfu/get", service_url.trim_end_matches('/'));
    let response = client
        .http_client()
        .post(url)
        .header("Content-Type", "application/json")
        .body(body.to_string())
        .timeout(Duration::from_secs(20))
        .send()
        .await
        .map_err(|error| CoreError::Network {
            message: format!("the call service can't be reached: {error}"),
        })?;
    let status = response.status().as_u16();
    let bytes = response
        .bytes()
        .await
        .map_err(|error| CoreError::internal(&error))?;
    if !(200..300).contains(&status) {
        let message = format!(
            "the call service answered HTTP {status}: {}",
            String::from_utf8_lossy(&bytes)
        );
        return Err(if status == 401 || status == 403 {
            CoreError::Forbidden { message }
        } else {
            CoreError::Internal { message }
        });
    }
    let answer: Value =
        serde_json::from_slice(&bytes).map_err(|error| CoreError::internal(&error))?;
    let url = answer.get("url").and_then(Value::as_str);
    let jwt = answer.get("jwt").and_then(Value::as_str);
    match (url, jwt) {
        (Some(url), Some(jwt)) => Ok((url.to_owned(), jwt.to_owned())),
        _ => Err(CoreError::internal(&"the call service sent no url or jwt")),
    }
}

fn lock<T>(mutex: &Mutex<T>) -> std::sync::MutexGuard<'_, T> {
    mutex.lock().unwrap_or_else(PoisonError::into_inner)
}

/// Where and how to join a call's media: the LiveKit server and an access token for it.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct LiveKitAccess {
    /// The LiveKit server (`wss://…`).
    pub url: String,
    pub token: String,
}

/// This device in a room's call. Its membership is kept fresh and its media keys go out and
/// come in until [`Self::leave`]; dropping it leaves too.
#[frb(opaque)]
pub struct ActiveCall {
    inner: Arc<CallInner>,
}

struct CallInner {
    client: Client,
    room: Room,
    user: String,
    device: String,
    identity: String,
    state_key: String,
    service_url: String,
    livekit_url: String,
    livekit_token: String,
    intent: CallIntent,
    /// The session's rooms with a call joined here, which stale-membership cleaning skips.
    active_calls: Arc<Mutex<HashSet<OwnedRoomId>>>,
    keys: broadcast::Sender<CallMediaKey>,
    /// Every key so far, latest per identity and index, for a late subscriber.
    known_keys: Mutex<BTreeMap<(String, u32), CallMediaKey>>,
    tasks: Mutex<Vec<AbortHandle>>,
    left: Mutex<bool>,
    runtime: Handle,
}

impl fmt::Debug for ActiveCall {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("ActiveCall")
            .field("room_id", &self.inner.room.room_id())
            .field("identity", &self.inner.identity)
            .finish_non_exhaustive()
    }
}

impl ActiveCall {
    #[frb(sync)]
    #[must_use]
    pub fn room_id(&self) -> String {
        self.inner.room.room_id().to_string()
    }

    /// The LiveKit server to connect to (`wss://…`).
    #[frb(sync)]
    #[must_use]
    pub fn livekit_url(&self) -> String {
        self.inner.livekit_url.clone()
    }

    /// The LiveKit access token.
    #[frb(sync)]
    #[must_use]
    pub fn livekit_token(&self) -> String {
        self.inner.livekit_token.clone()
    }

    /// This device's identity in LiveKit, `@user:server:DEVICE`.
    #[frb(sync)]
    #[must_use]
    pub fn identity(&self) -> String {
        self.inner.identity.clone()
    }

    /// The lk-jwt-service the call uses.
    #[frb(sync)]
    #[must_use]
    pub fn service_url(&self) -> String {
        self.inner.service_url.clone()
    }

    #[frb(sync)]
    #[must_use]
    pub fn intent(&self) -> CallIntent {
        self.inner.intent
    }

    /// A new LiveKit address and token from the call's lk-jwt-service, which also creates the
    /// LiveKit room again if it is gone. A token can name a room that LiveKit closes before the
    /// media connects: lk-jwt-service hands out the existing room ("reused") while LiveKit's
    /// departure timeout (20 s after the last participant left) is running, and a connect after
    /// it ran out gets "requested room does not exist". The media then retries with this.
    ///
    /// # Errors
    ///
    /// As [`Session::join_call`] for the token.
    pub async fn renew_livekit_access(&self) -> Result<LiveKitAccess, CoreError> {
        let (url, token) = livekit_token(
            &self.inner.client,
            self.inner.room.room_id().as_str(),
            &self.inner.service_url,
            &self.inner.device,
        )
        .await?;
        Ok(LiveKitAccess { url, token })
    }

    /// Sends every media key so far (ours and the others'), then each new one.
    #[allow(
        clippy::unused_async,
        reason = "async so flutter_rust_bridge runs it on its tokio runtime, which spawn needs"
    )]
    pub async fn subscribe_media_keys(&self, sink: StreamSink<CallMediaKey>) {
        self.media_key_updates(move |key| sink.add(key).is_ok());
    }

    /// Like [`Self::subscribe_media_keys`], for Rust callers.
    #[frb(ignore)]
    pub fn media_key_updates(&self, emit: impl Fn(CallMediaKey) -> bool + Send + 'static) {
        let mut receiver = self.inner.keys.subscribe();
        let known: Vec<CallMediaKey> = lock(&self.inner.known_keys).values().cloned().collect();
        let task = tokio::spawn(async move {
            for key in known {
                if !emit(key) {
                    return;
                }
            }
            loop {
                match receiver.recv().await {
                    Ok(key) => {
                        if !emit(key) {
                            return;
                        }
                    }
                    Err(broadcast::error::RecvError::Lagged(_)) => {}
                    Err(broadcast::error::RecvError::Closed) => return,
                }
            }
        });
        lock(&self.inner.tasks).push(task.abort_handle());
    }

    /// Leaves the call: the membership goes (empty content), keys stop. Calling it again does
    /// nothing.
    ///
    /// # Errors
    ///
    /// As the server answers the membership; the call is left here anyway.
    pub async fn leave(&self) -> Result<(), CoreError> {
        self.inner.leave().await
    }
}

impl Drop for ActiveCall {
    fn drop(&mut self) {
        if *lock(&self.inner.left) {
            return;
        }
        let inner = self.inner.clone();
        self.inner.runtime.spawn(async move {
            if let Err(error) = inner.leave().await {
                tracing::warn!(%error, "couldn't leave a dropped call");
            }
        });
    }
}

impl CallInner {
    fn start(self: &Arc<Self>, joined_at: i64) {
        let mut tasks = lock(&self.tasks);
        tasks.push(tokio::spawn(self.clone().keep_membership(joined_at)).abort_handle());
        tasks.push(tokio::spawn(self.clone().distribute_keys()).abort_handle());
    }

    async fn leave(&self) -> Result<(), CoreError> {
        {
            let mut left = lock(&self.left);
            if *left {
                return Ok(());
            }
            *left = true;
        }
        for task in lock(&self.tasks).drain(..) {
            task.abort();
        }
        lock(&self.active_calls).remove(self.room.room_id());
        let mut result = Ok(());
        for attempt in 0..3 {
            match self
                .room
                .send_state_event_raw(CALL_MEMBER_TYPE, &self.state_key, json!({}))
                .await
            {
                Ok(_) => return Ok(()),
                Err(error) => {
                    tracing::warn!(%error, attempt, "couldn't leave the call");
                    result = Err(error.into());
                    tokio::time::sleep(Duration::from_secs(1)).await;
                }
            }
        }
        result
    }

    /// Pushes the membership's expiry forward shortly before it runs out, keeping the time it
    /// first joined (`created_ts`).
    async fn keep_membership(self: Arc<Self>, joined_at: i64) {
        let mut iteration: i64 = 1;
        loop {
            let refresh_at =
                joined_at + MEMBERSHIP_EXPIRY_MS * iteration - MEMBERSHIP_REFRESH_HEADROOM_MS;
            let wait = u64::try_from(refresh_at - now_ms()).unwrap_or(0);
            tokio::time::sleep(Duration::from_millis(wait)).await;
            // The first event's own time, as the others count from it.
            let created_ts = active_memberships(&membership_events(&self.room).await, 0)
                .into_iter()
                .find(|m| m.state_key == self.state_key)
                .map_or(joined_at, |m| m.created_ts);
            let expires = (now_ms() - created_ts) + MEMBERSHIP_EXPIRY_MS;
            let content = membership_content(
                &self.device,
                &self.identity,
                self.room.room_id().as_str(),
                &self.service_url,
                self.intent,
                expires,
                Some(created_ts),
            );
            match self
                .room
                .send_state_event_raw(CALL_MEMBER_TYPE, &self.state_key, content)
                .await
            {
                Ok(_) => iteration += 1,
                Err(error) => {
                    tracing::warn!(%error, "couldn't refresh the call membership");
                    tokio::time::sleep(Duration::from_secs(5)).await;
                }
            }
        }
    }

    /// Rings or notifies the room's other members about the call our membership
    /// `membership_event_id` started.
    async fn notify(
        &self,
        notify: CallNotify,
        membership_event_id: &OwnedEventId,
    ) -> Result<(), CoreError> {
        let own = self.room.own_user_id().to_owned();
        let others: Vec<String> = self
            .room
            .members(matrix_sdk::RoomMemberships::ACTIVE)
            .await?
            .into_iter()
            .map(|member| member.user_id().to_string())
            .filter(|user| *user != own.as_str())
            .collect();
        let content = notification_content(
            notify,
            self.intent,
            membership_event_id.as_str(),
            &others,
            notify == CallNotify::Notify,
            now_ms(),
        );
        // The unstable type: Element Call (matrix-js-sdk `EventType.RTCNotification`) reads
        // only that one, and matrix-rust-sdk (Element X, OxiTalk) reads both (ruma
        // `unstable-msc4075`). Both types at once would show and ring twice there.
        self.room
            .send_raw(NOTIFICATION_TYPE_UNSTABLE, content)
            .await?;
        Ok(())
    }

    fn publish_key(&self, key: CallMediaKey) {
        lock(&self.known_keys).insert((key.identity.clone(), key.index), key.clone());
        let _ = self.keys.send(key);
    }

    /// The media keys the others send us for this call, while the guard is kept.
    fn listen_for_keys(&self) -> (EventHandlerDropGuard, mpsc::UnboundedReceiver<ReceivedKey>) {
        let (sender, received) = mpsc::unbounded_channel::<ReceivedKey>();
        let room_id = self.room.room_id().to_string();
        let handler = self.client.add_event_handler({
            let room_id = room_id.clone();
            move |event: Raw<AnyToDeviceEvent>,
                  info: Option<matrix_sdk::deserialized_responses::EncryptionInfo>| {
                let sender = sender.clone();
                let room_id = room_id.clone();
                async move {
                    // Only Olm-encrypted keys count (matrix-js-sdk drops clear ones too).
                    let Some(info) = info else { return };
                    let Ok(value) = event.deserialize_as::<Value>() else {
                        return;
                    };
                    if value.get("type").and_then(Value::as_str) != Some(KEYS_TYPE) {
                        return;
                    }
                    let Some(content) = value.get("content") else {
                        return;
                    };
                    if let Some(key) = parse_key(
                        content,
                        info.sender.as_str(),
                        info.sender_device.as_deref().map(ruma::DeviceId::as_str),
                        &room_id,
                    ) {
                        let _ = sender.send(key);
                    }
                }
            }
        });

        (self.client.event_handler_drop_guard(handler), received)
    }

    /// Our key out to every device in the call, theirs in to the app, until the call is left.
    async fn distribute_keys(self: Arc<Self>) {
        let (_guard, mut received) = self.listen_for_keys();

        let Ok(mut key) = random_key() else { return };
        let mut index: u32 = 0;
        let mut created = Instant::now();
        let mut shared_with: Vec<Peer> = Vec::new();
        self.publish_key(CallMediaKey {
            identity: self.identity.clone(),
            index,
            key: key.clone(),
            is_own: true,
        });

        let mut infos = self.room.subscribe_info();
        // A membership change rings `members_changed`; the loop reads the latest state.
        let (changed_tx, mut changed) = watch::channel(());
        let watcher = tokio::spawn(async move {
            while infos.next().await.is_some() {
                if changed_tx.send(()).is_err() {
                    return;
                }
            }
        });
        lock(&self.tasks).push(watcher.abort_handle());
        let mut check = true;
        loop {
            if check {
                check = false;
                let current: Vec<Peer> =
                    active_memberships(&membership_events(&self.room).await, now_ms())
                        .into_iter()
                        .filter(|m| !(m.user_id == self.user && m.device_id == self.device))
                        .map(|m| (m.user_id, m.device_id, m.created_ts))
                        .collect();
                match plan_keys(&shared_with, &current, created.elapsed()) {
                    KeyPlan::Keep => shared_with = current,
                    KeyPlan::Share(joined) => {
                        self.send_key(index, &key, &joined).await;
                        shared_with = current;
                    }
                    KeyPlan::Rotate(everybody) => {
                        let Ok(new_key) = random_key() else { return };
                        key = new_key;
                        index = (index + 1) % 256;
                        created = Instant::now();
                        self.send_key(index, &key, &everybody).await;
                        shared_with = current;
                        // Give the key a moment to arrive before encrypting with it.
                        let this = self.clone();
                        let (own_key, own_index) = (key.clone(), index);
                        let delayed = tokio::spawn(async move {
                            tokio::time::sleep(NEW_KEY_DELAY).await;
                            this.publish_key(CallMediaKey {
                                identity: this.identity.clone(),
                                index: own_index,
                                key: own_key,
                                is_own: true,
                            });
                        });
                        lock(&self.tasks).push(delayed.abort_handle());
                    }
                }
            }
            tokio::select! {
                changed = changed.changed() => {
                    if changed.is_err() {
                        return;
                    }
                    check = true;
                }
                key = received.recv() => {
                    let Some(key) = key else { return };
                    self.publish_key(CallMediaKey {
                        identity: format!("{}:{}", key.user_id, key.device_id),
                        index: key.index,
                        key: key.key,
                        is_own: false,
                    });
                }
            }
        }
    }

    /// Sends our key to these devices, Olm-encrypted; devices we don't know yet are looked up
    /// once and tried again.
    async fn send_key(&self, index: u32, key: &[u8], peers: &[Peer]) {
        if peers.is_empty() {
            return;
        }
        let content = key_content(
            self.room.room_id().as_str(),
            &self.identity,
            &self.device,
            index,
            key,
        );
        let Ok(raw) = Raw::<AnyToDeviceEventContent>::from_json_string(content.to_string()) else {
            return;
        };
        let mut recipients: BTreeMap<OwnedUserId, Vec<DeviceIdOrAllDevices>> = BTreeMap::new();
        for (user, device, _) in peers {
            if let Ok(user) = parse_id::<OwnedUserId>(user) {
                recipients
                    .entry(user)
                    .or_default()
                    .push(DeviceIdOrAllDevices::DeviceId(device.as_str().into()));
            }
        }
        let event_type = ToDeviceEventType::from(KEYS_TYPE);
        for attempt in 0..2 {
            match self
                .client
                .send_encrypted_to_device(&event_type, recipients.clone(), raw.clone())
                .await
            {
                Ok(failures) if failures.is_empty() => return,
                Ok(failures) => {
                    tracing::info!(?failures, attempt, "call key not delivered to some devices");
                    // Unknown devices: ask the server for those users' devices, then retry them.
                    recipients.retain(|user, _| failures.contains_key(user));
                    for (user, devices) in &failures {
                        let _ = self.client.encryption().request_user_identity(user).await;
                        recipients.insert(
                            user.clone(),
                            devices
                                .iter()
                                .map(|d| DeviceIdOrAllDevices::DeviceId(d.clone()))
                                .collect(),
                        );
                    }
                }
                Err(error) => {
                    tracing::warn!(%error, attempt, "couldn't send the call key");
                    tokio::time::sleep(Duration::from_secs(1)).await;
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    use matrix_sdk::deserialized_responses::{UnableToDecryptInfo, UnableToDecryptReason};

    fn ring_raw(kind: &str) -> Raw<AnySyncTimelineEvent> {
        Raw::from_json(
            serde_json::value::to_raw_value(&json!({
                "type": kind,
                "sender": "@alice:x",
                "event_id": "$ring",
                "origin_server_ts": 1,
                "content": {},
            }))
            .unwrap_or_default(),
        )
    }

    fn no_key_yet() -> TimelineEvent {
        TimelineEvent::from_utd(
            ring_raw("m.room.encrypted"),
            UnableToDecryptInfo {
                session_id: Some("s".to_owned()),
                reason: UnableToDecryptReason::MissingMegolmSession {
                    withheld_code: None,
                },
            },
        )
    }

    /// The SDK answers a ring whose room key hasn't come with Ok(unable to decrypt): that is
    /// tried again, so the ring shows once the key comes (on Tuwunel under load it came 2 s
    /// after the ring, and the ring was dropped at the first try).
    #[tokio::test]
    async fn an_encrypted_ring_is_read_once_its_key_comes() -> Result<(), &'static str> {
        assert!(decrypted(Ok::<_, ()>(no_key_yet())).is_none());
        assert!(decrypted(Err::<TimelineEvent, _>(())).is_none());
        let mut tries = 0;
        let read = retry_until(Duration::from_secs(5), || {
            tries += 1;
            let result = if tries < 3 {
                Ok::<_, ()>(no_key_yet())
            } else {
                Ok(TimelineEvent::from_plaintext(ring_raw(NOTIFICATION_TYPE)))
            };
            async move { decrypted(result) }
        })
        .await
        .ok_or("not read after the key came")?;
        assert_eq!(tries, 3);
        assert!(ring_event(read.raw()).is_some());
        Ok(())
    }

    #[tokio::test]
    async fn an_encrypted_ring_without_a_key_is_given_up() {
        let mut tries = 0;
        let read = retry_until(Duration::from_millis(1200), || {
            tries += 1;
            async { decrypted(Ok::<_, ()>(no_key_yet())) }
        })
        .await;
        assert!(read.is_none());
        assert_eq!(tries, 2, "0.5 s, then 1 s");
    }

    fn member_event(sender: &str, device: &str, content: &Value, origin: i64) -> Value {
        json!({
            "type": CALL_MEMBER_TYPE,
            "sender": sender,
            "state_key": membership_state_key(sender, device),
            "origin_server_ts": origin,
            "event_id": format!("$m{device}"),
            "content": content.clone(),
        })
    }

    fn joined(device: &str, created: Option<i64>, expires: i64) -> Value {
        membership_content(
            device,
            &format!("@a:x:{device}"),
            "!r:x",
            "https://rtc.x/livekit/jwt",
            CallIntent::Video,
            expires,
            created,
        )
    }

    #[test]
    fn our_membership_reads_back_as_element_call_writes_it() -> Result<(), &'static str> {
        let content = joined("DEV", None, MEMBERSHIP_EXPIRY_MS);
        assert_eq!(content["application"], "m.call");
        assert_eq!(content["call_id"], "");
        assert_eq!(content["scope"], "m.room");
        assert_eq!(content["membershipID"], "@a:x:DEV");
        assert_eq!(content["focus_active"]["type"], "livekit");
        assert_eq!(content["focus_active"]["focus_selection"], "multi_sfu");
        assert_eq!(
            content["foci_preferred"][0]["livekit_service_url"],
            "https://rtc.x/livekit/jwt"
        );
        assert!(content.get("created_ts").is_none());
        assert_eq!(membership_state_key("@a:x", "DEV"), "_@a:x_DEV_m.call");

        let event = member_event("@a:x", "DEV", &content, 1_000);
        let membership = parse_membership(&event).ok_or("no membership")?;
        assert_eq!(membership.created_ts, 1_000);
        assert_eq!(membership.expires_at, 1_000 + MEMBERSHIP_EXPIRY_MS);
        assert_eq!(membership.intent, Some(CallIntent::Video));
        assert_eq!(membership.identity(), "@a:x:DEV");
        assert_eq!(
            membership.service_url.as_deref(),
            Some("https://rtc.x/livekit/jwt")
        );
        Ok(())
    }

    #[test]
    fn a_refresh_keeps_the_first_join_time() -> Result<(), &'static str> {
        let event = member_event("@a:x", "DEV", &joined("DEV", Some(500), 9_000), 7_000);
        let membership = parse_membership(&event).ok_or("no membership")?;
        assert_eq!(membership.created_ts, 500);
        assert_eq!(membership.expires_at, 9_500);
        Ok(())
    }

    #[test]
    fn left_expired_foreign_and_other_calls_are_not_members() {
        let left = member_event("@a:x", "DEV", &json!({}), 1);
        assert_eq!(parse_membership(&left), None);

        let mut other_call = joined("DEV", None, 10);
        other_call["call_id"] = json!("breakout");
        assert_eq!(
            parse_membership(&member_event("@a:x", "DEV", &other_call, 1)),
            None
        );

        let mut other_app = joined("DEV", None, 10);
        other_app["application"] = json!("m.game");
        assert_eq!(
            parse_membership(&member_event("@a:x", "DEV", &other_app, 1)),
            None
        );

        // Bob can't put Alice in a call.
        let mut forged = member_event("@b:x", "DEV", &joined("DEV", None, 10), 1);
        forged["state_key"] = json!(membership_state_key("@a:x", "DEV"));
        assert_eq!(parse_membership(&forged), None);
        // Nor can @a:x.evil speak for @a:x.
        let mut prefix = member_event("@a:x", "DEV", &joined("DEV", None, 10), 1);
        prefix["sender"] = json!("@a:x.e");
        prefix["state_key"] = json!("_@a:x.e_DEV_m.call");
        assert!(parse_membership(&prefix).is_some());
        prefix["sender"] = json!("@a:x");
        assert_eq!(parse_membership(&prefix), None);

        let events = vec![
            member_event("@a:x", "OLD", &joined("OLD", Some(100), 50), 100),
            member_event("@b:x", "NEW", &joined("NEW", Some(300), 10_000), 300),
            member_event("@c:x", "MID", &joined("MID", Some(200), 10_000), 200),
        ];
        let active = active_memberships(&events, 1_000);
        let devices: Vec<&str> = active.iter().map(|m| m.device_id.as_str()).collect();
        assert_eq!(devices, ["MID", "NEW"]);
    }

    #[test]
    fn element_calls_older_state_key_without_underscore_is_read() {
        let mut event = member_event("@a:x", "DEV", &joined("DEV", None, 10), 1);
        event["state_key"] = json!("@a:x_DEV_m.call");
        assert!(parse_membership(&event).is_some());
    }

    #[test]
    fn rings_count_while_fresh_and_addressed_to_us() -> Result<(), &'static str> {
        let content = notification_content(
            CallNotify::Ring,
            CallIntent::Audio,
            "$member",
            &["@me:x".to_owned()],
            false,
            10_000,
        );
        assert_eq!(content["notification_type"], "ring");
        assert_eq!(content["m.relates_to"]["rel_type"], "m.reference");
        assert_eq!(content["m.relates_to"]["event_id"], "$member");
        assert_eq!(content["slot_id"], "m.call#ROOM");
        let event = |kind: &str, sender: &str, content: &Value, origin: i64| {
            json!({ "type": kind, "sender": sender, "event_id": "$ring",
                    "origin_server_ts": origin, "content": content })
        };
        let ring = parse_ring(
            &event(NOTIFICATION_TYPE_UNSTABLE, "@caller:x", &content, 10_100),
            "@me:x",
            20_000,
        )
        .ok_or("no ring")?;
        assert!(ring.rings);
        assert_eq!(ring.intent, Some(CallIntent::Audio));
        assert_eq!(ring.expires_at, 10_000 + RING_LIFETIME_MS);
        assert!(
            parse_ring(
                &event(NOTIFICATION_TYPE, "@caller:x", &content, 10_100),
                "@me:x",
                20_000
            )
            .is_some()
        );
        // Too late, our own, or for someone else.
        assert!(
            parse_ring(
                &event(NOTIFICATION_TYPE, "@caller:x", &content, 10_100),
                "@me:x",
                80_000
            )
            .is_none()
        );
        assert!(
            parse_ring(
                &event(NOTIFICATION_TYPE, "@me:x", &content, 10_100),
                "@me:x",
                20_000
            )
            .is_none()
        );
        assert!(
            parse_ring(
                &event(NOTIFICATION_TYPE, "@caller:x", &content, 10_100),
                "@other:x",
                20_000
            )
            .is_none()
        );
        // A notification to the whole room is for us too.
        let group = notification_content(
            CallNotify::Notify,
            CallIntent::Video,
            "$m",
            &[],
            true,
            10_000,
        );
        let notified = parse_ring(
            &event(NOTIFICATION_TYPE, "@caller:x", &group, 10_100),
            "@me:x",
            20_000,
        )
        .ok_or("no notification")?;
        assert!(!notified.rings);
        Ok(())
    }

    #[test]
    fn a_sender_clock_far_ahead_counts_from_the_server_and_lifetimes_are_capped() {
        assert_eq!(ring_expiry(100_000, 10_000, 30_000), 40_000);
        assert_eq!(ring_expiry(15_000, 10_000, 30_000), 45_000);
        assert_eq!(
            ring_expiry(10_000, 10_000, 600_000),
            10_000 + MAX_RING_LIFETIME_MS
        );
    }

    #[test]
    fn keys_go_out_and_come_back_as_element_call_sends_them() -> Result<(), &'static str> {
        let key = [7_u8; 16];
        let content = key_content("!r:x", "@a:x:DEV", "DEV", 3, &key);
        assert_eq!(content["media_key"], content["keys"]);
        assert_eq!(content["member"]["claimed_device_id"], "DEV");
        assert_eq!(content["member_id"], "@a:x:DEV");
        assert_eq!(content["media_key"]["key"], "BwcHBwcHBwcHBwcHBwcHBw==");

        let read = parse_key(&content, "@a:x", Some("DEV"), "!r:x").ok_or("no key")?;
        assert_eq!(read.index, 3);
        assert_eq!(read.key, key);
        assert_eq!(read.device_id, "DEV");
        // Another room, or a device the Olm session doesn't vouch for.
        assert!(parse_key(&content, "@a:x", Some("DEV"), "!other:x").is_none());
        assert!(parse_key(&content, "@a:x", Some("EVIL"), "!r:x").is_none());
        // Only the deprecated `keys`, unpadded base64.
        let old = json!({ "room_id": "!r:x", "keys": { "index": 0, "key": "BwcHBwcHBwcHBwcHBwcHBw" },
                          "member": { "claimed_device_id": "DEV" } });
        assert_eq!(
            parse_key(&old, "@a:x", None, "!r:x").map(|k| k.key),
            Some(key.to_vec())
        );
        Ok(())
    }

    #[test]
    fn keys_are_shared_with_joiners_and_rotated_when_someone_leaves() {
        let a = ("@a:x".to_owned(), "A".to_owned(), 1);
        let b = ("@b:x".to_owned(), "B".to_owned(), 2);
        let young = Duration::from_secs(1);
        let old = Duration::from_secs(60);
        assert_eq!(plan_keys(&[], &[], young), KeyPlan::Keep);
        assert_eq!(
            plan_keys(&[], std::slice::from_ref(&a), young),
            KeyPlan::Share(vec![a.clone()])
        );
        assert_eq!(
            plan_keys(std::slice::from_ref(&a), &[a.clone(), b.clone()], young),
            KeyPlan::Share(vec![b.clone()])
        );
        assert_eq!(
            plan_keys(std::slice::from_ref(&a), &[a.clone(), b.clone()], old),
            KeyPlan::Rotate(vec![a.clone(), b.clone()])
        );
        assert_eq!(
            plan_keys(&[a.clone(), b.clone()], std::slice::from_ref(&a), young),
            KeyPlan::Rotate(vec![a.clone()])
        );
        // B joined again (new created_ts): B gets the key again, nobody counts as gone.
        let b_again = ("@b:x".to_owned(), "B".to_owned(), 9);
        assert_eq!(
            plan_keys(&[a.clone(), b], &[a, b_again.clone()], young),
            KeyPlan::Share(vec![b_again])
        );
    }

    #[test]
    fn livekit_transports_are_picked_by_type() {
        let mut livekit = serde_json::Map::new();
        livekit.insert("livekit_service_url".to_owned(), json!("https://rtc.x/jwt"));
        let mut other = serde_json::Map::new();
        other.insert("url".to_owned(), json!("https://other"));
        let urls = livekit_urls(
            [("livekit".to_owned(), livekit), ("other".to_owned(), other)].into_iter(),
        );
        assert_eq!(urls, ["https://rtc.x/jwt"]);
    }
}
