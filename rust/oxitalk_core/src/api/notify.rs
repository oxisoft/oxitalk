//! The messages to show as OS notifications while the app runs, as Element X decides them: the
//! push rules say which events notify, encrypted ones are decrypted here first (the server
//! can't see a mention inside them), and the user's own messages, ignored users and events
//! from before the app was listening are left out. The app shows them; this only picks them.

use std::{
    collections::{HashSet, VecDeque},
    future::ready,
    time::Duration,
};

use flutter_rust_bridge::frb;
use futures_util::{Stream, StreamExt, stream};
use matrix_sdk::{
    Client, Room,
    deserialized_responses::{RawAnySyncOrStrippedTimelineEvent, TimelineEvent, TimelineEventKind},
    room::PushContext,
    ruma::{
        MilliSecondsSinceUnixEpoch, OwnedEventId, OwnedUserId, UserId,
        events::{
            AnyStrippedStateEvent, AnySyncMessageLikeEvent, AnySyncTimelineEvent,
            SyncMessageLikeEvent,
            room::{encrypted::OriginalSyncRoomEncryptedEvent, message::Relation},
        },
        push::Action,
        serde::Raw,
    },
    serde_helpers::extract_thread_root,
    sync::Notification,
};
use tokio::{
    sync::broadcast::{self, error::RecvError},
    time::{Instant, timeout},
};

use super::{session::Session, timeline::msgtype_preview};
use crate::frb_generated::StreamSink;

/// How many events wait for a slow subscriber before the oldest are dropped.
const CHANNEL_CAPACITY: usize = 256;

/// How long an encrypted event may wait for its key, as the SDK's notification client waits.
const DECRYPTION_DEADLINE: Duration = Duration::from_secs(10);

/// Events older than this before the subscription are history, not news: the first syncs
/// bring the latest events of every room again.
const HISTORY_SLACK_MS: u64 = 30_000;

/// How many event IDs are remembered so an event the sync sends again (a room's timeline
/// grows when it is opened) notifies once.
const SEEN_LIMIT: usize = 2_000;

/// How many events are worked on at once; one waiting for its key doesn't hold up the rest.
const CONCURRENCY: usize = 16;

/// A message (or invitation) to show as an OS notification.
#[derive(Debug, Clone, PartialEq, Eq)]
#[allow(
    clippy::struct_excessive_bools,
    reason = "independent facts the app reads, not a state machine"
)]
pub struct NotificationItem {
    pub room_id: String,
    /// `None` only for an invitation whose event the server sent without an ID.
    pub event_id: Option<String>,
    /// The thread the message is a reply in.
    pub thread_root: Option<String>,
    pub room_name: String,
    pub sender_id: String,
    /// The sender's display name in the room, else their user ID.
    pub sender_name: String,
    /// An `mxc://` URI.
    pub sender_avatar: Option<String>,
    /// The message as one line of text; `None` when there is none to show (an event that
    /// stayed encrypted, an invitation, a poll).
    pub body_preview: Option<String>,
    pub is_dm: bool,
    /// The push rules highlight it: it mentions the user, @room or one of their keywords.
    pub is_highlight: bool,
    /// The push rules ask for a sound.
    pub sound: bool,
    pub is_invite: bool,
    /// When it was sent, in milliseconds since the Unix epoch.
    pub timestamp_ms: i64,
}

/// What the sync hands over, before it is checked.
#[derive(Clone)]
#[frb(ignore)]
pub(crate) enum Candidate {
    /// A plain event, or one the sync decrypted, with the actions the SDK computed for it.
    Event {
        room: Room,
        event: Raw<AnySyncTimelineEvent>,
        actions: Vec<Action>,
    },
    /// An event the sync couldn't decrypt. Its actions were computed on the encrypted event,
    /// which hides mentions, so they are computed again once it is decrypted.
    Undecrypted {
        room: Room,
        event: Raw<AnySyncTimelineEvent>,
    },
    Invite {
        room: Room,
        event: Raw<AnyStrippedStateEvent>,
        actions: Vec<Action>,
    },
}

/// Hooks the client's sync up to a channel of candidates. The SDK only adds notification
/// handlers, so this runs once per client and every subscription listens to the channel.
pub(crate) async fn register(client: &Client) -> broadcast::Sender<Candidate> {
    let (sender, _) = broadcast::channel(CHANNEL_CAPACITY);
    let notifications = sender.clone();
    // Both handlers only pass the event on: the sync waits for them, and an encrypted event
    // waits for a key that a later sync brings.
    client
        .register_notification_handler(move |notification: Notification, room: Room, _: Client| {
            let notifications = notifications.clone();
            async move {
                let candidate = match notification.event {
                    // An undecrypted event comes through the handler below, for every
                    // room, as the rules for the decrypted event may differ.
                    RawAnySyncOrStrippedTimelineEvent::Sync(event) if is_encrypted(&event) => {
                        return;
                    }
                    RawAnySyncOrStrippedTimelineEvent::Sync(event) => Candidate::Event {
                        room,
                        event,
                        actions: notification.actions,
                    },
                    RawAnySyncOrStrippedTimelineEvent::Stripped(event) => Candidate::Invite {
                        room,
                        event,
                        actions: notification.actions,
                    },
                };
                // Without a subscriber there is nobody to tell.
                notifications.send(candidate).ok();
            }
        })
        .await;
    let undecrypted = sender.clone();
    // The sync hands decrypted events to handlers by their decrypted type, so this sees only
    // the ones it couldn't decrypt.
    client.add_event_handler(
        move |event: Raw<OriginalSyncRoomEncryptedEvent>, room: Room| {
            let undecrypted = undecrypted.clone();
            async move {
                undecrypted
                    .send(Candidate::Undecrypted {
                        room,
                        event: event.cast_unchecked(),
                    })
                    .ok();
            }
        },
    );
    sender
}

impl Session {
    /// Sends every message that should show as an OS notification from now on: it notifies
    /// by the push rules (decrypted first if it is encrypted), and it isn't the user's own.
    #[allow(
        clippy::unused_async,
        reason = "async so flutter_rust_bridge runs it on its tokio runtime, which spawn needs"
    )]
    pub async fn subscribe_notifications(&self, sink: StreamSink<NotificationItem>) {
        let mut items = self.notification_items();
        self.spawn(async move {
            while let Some(item) = items.next().await {
                if sink.add(item).is_err() {
                    break;
                }
            }
        });
    }

    /// Like [`Self::subscribe_notifications`], for Rust callers.
    #[frb(ignore)]
    pub fn notification_items(
        &self,
    ) -> impl Stream<Item = NotificationItem> + Send + Unpin + 'static {
        let receiver = self.notification_candidates.subscribe();
        let client = self.client.clone();
        let since = MilliSecondsSinceUnixEpoch::now()
            .get()
            .saturating_sub(HISTORY_SLACK_MS.try_into().unwrap_or_default());
        let since = i64::from(since);
        let candidates = stream::unfold(receiver, |mut receiver| async move {
            loop {
                match receiver.recv().await {
                    Ok(candidate) => return Some((candidate, receiver)),
                    // Too many at once: the oldest are lost, the rest still show.
                    Err(RecvError::Lagged(_)) => {}
                    Err(RecvError::Closed) => return None,
                }
            }
        });
        let mut seen = Seen::default();
        Box::pin(
            candidates
                .map(move |candidate| {
                    let client = client.clone();
                    async move { item(&client, candidate, since).await }
                })
                .buffer_unordered(CONCURRENCY)
                .filter_map(move |item| ready(item.filter(|item| seen.first_time(item)))),
        )
    }
}

/// The event IDs already sent, the latest [`SEEN_LIMIT`].
#[derive(Default)]
#[frb(ignore)]
struct Seen {
    order: VecDeque<String>,
    ids: HashSet<String>,
}

impl Seen {
    fn first_time(&mut self, item: &NotificationItem) -> bool {
        let key = match &item.event_id {
            Some(id) => id.clone(),
            None => format!("invite {}", item.room_id),
        };
        if !self.ids.insert(key.clone()) {
            return false;
        }
        self.order.push_back(key);
        if self.order.len() > SEEN_LIMIT
            && let Some(oldest) = self.order.pop_front()
        {
            self.ids.remove(&oldest);
        }
        true
    }
}

fn is_encrypted(event: &Raw<AnySyncTimelineEvent>) -> bool {
    event.get_field::<String>("type").ok().flatten().as_deref() == Some("m.room.encrypted")
}

/// What every event says about itself, read before anything slow is done with it.
#[frb(ignore)]
struct Header {
    event_id: Option<OwnedEventId>,
    sender: OwnedUserId,
    timestamp_ms: i64,
}

fn header<T>(event: &Raw<T>) -> Option<Header> {
    let timestamp: Option<MilliSecondsSinceUnixEpoch> =
        event.get_field("origin_server_ts").ok().flatten();
    Some(Header {
        event_id: event.get_field("event_id").ok().flatten(),
        sender: event.get_field("sender").ok().flatten()?,
        timestamp_ms: timestamp.map_or(0, |ts| ts.0.into()),
    })
}

/// Whether an event from `header` may notify at all: not the user's own, not from someone
/// they ignore, not from before the app listened.
async fn may_notify(client: &Client, own: &UserId, header: &Header, since: i64) -> bool {
    header.sender != own
        && header.timestamp_ms >= since
        && !client.is_user_ignored(&header.sender).await
}

async fn item(client: &Client, candidate: Candidate, since: i64) -> Option<NotificationItem> {
    let own = client.user_id()?.to_owned();
    match candidate {
        Candidate::Event {
            room,
            event,
            actions,
        } => {
            let header = header(&event)?;
            if !may_notify(client, &own, &header, since).await {
                return None;
            }
            message_item(&room, &event, &actions, header).await
        }
        Candidate::Undecrypted { room, event } => {
            let header = header(&event)?;
            if !may_notify(client, &own, &header, since).await {
                return None;
            }
            let push_context = room.push_context().await.ok().flatten();
            let decrypted = wait_for_decryption(client, &room, &event, push_context.as_ref()).await;
            let (event, actions) = if let Some(decrypted) = decrypted {
                let actions = decrypted.push_actions().map(<[Action]>::to_vec);
                (decrypted.into_raw(), actions)
            } else {
                // Never decrypted: the rules for the encrypted event, as the server would
                // push it, and no text.
                let actions = match &push_context {
                    Some(context) => Some(context.for_event(&event).await),
                    None => None,
                };
                (event, actions)
            };
            message_item(&room, &event, &actions.unwrap_or_default(), header).await
        }
        Candidate::Invite {
            room,
            event,
            actions,
        } => {
            let header = header(&event)?;
            // An invitation is about the user: its state key is their ID.
            let invited: Option<OwnedUserId> = event.get_field("state_key").ok().flatten();
            if invited.as_deref() != Some(&*own) || !notifies(&actions) {
                return None;
            }
            if !may_notify(client, &own, &header, since).await {
                return None;
            }
            Some(NotificationItem {
                is_invite: true,
                ..base_item(&room, &actions, header).await
            })
        }
    }
}

fn notifies(actions: &[Action]) -> bool {
    actions.iter().any(Action::should_notify)
}

async fn message_item(
    room: &Room,
    event: &Raw<AnySyncTimelineEvent>,
    actions: &[Action],
    header: Header,
) -> Option<NotificationItem> {
    if !notifies(actions) {
        return None;
    }
    let body_preview = match event.deserialize() {
        Ok(AnySyncTimelineEvent::MessageLike(AnySyncMessageLikeEvent::RoomMessage(
            SyncMessageLikeEvent::Original(message),
        ))) => {
            // An edit changes a message the user was told about already.
            if matches!(message.content.relates_to, Some(Relation::Replacement(_))) {
                return None;
            }
            Some(msgtype_preview(&message.content.msgtype))
        }
        Ok(AnySyncTimelineEvent::MessageLike(AnySyncMessageLikeEvent::Sticker(
            SyncMessageLikeEvent::Original(sticker),
        ))) => Some(sticker.content.body),
        _ => None,
    };
    Some(NotificationItem {
        thread_root: extract_thread_root(event).map(|root| root.to_string()),
        body_preview,
        ..base_item(room, actions, header).await
    })
}

/// What a notification shows for any event: the room, the sender and the rules' tweaks.
async fn base_item(room: &Room, actions: &[Action], header: Header) -> NotificationItem {
    let member = room.get_member_no_sync(&header.sender).await.ok().flatten();
    NotificationItem {
        room_id: room.room_id().to_string(),
        event_id: header.event_id.map(|id| id.to_string()),
        thread_root: None,
        room_name: room
            .cached_display_name()
            .map_or_else(|| room.room_id().to_string(), |name| name.to_string()),
        sender_id: header.sender.to_string(),
        sender_name: member.as_ref().map_or_else(
            || header.sender.to_string(),
            |member| member.name().to_owned(),
        ),
        sender_avatar: member
            .as_ref()
            .and_then(|member| member.avatar_url())
            .map(ToString::to_string),
        body_preview: None,
        // A store read error only loses the DM marker.
        is_dm: room.is_direct().await.unwrap_or(false),
        is_highlight: actions.iter().any(Action::is_highlight),
        sound: actions.iter().any(|action| action.sound().is_some()),
        is_invite: false,
        timestamp_ms: header.timestamp_ms,
    }
}

/// Decrypts `event` once its key arrives, as the SDK's notification client does while the
/// app's own sync runs: try, then try again whenever keys for the room arrive, until
/// [`DECRYPTION_DEADLINE`]. `None` if it stays encrypted.
async fn wait_for_decryption(
    client: &Client,
    room: &Room,
    event: &Raw<AnySyncTimelineEvent>,
    push_context: Option<&PushContext>,
) -> Option<TimelineEvent> {
    // Subscribed before the first try, so a key arriving in between isn't missed.
    let keys = client.encryption().room_keys_received_stream().await;
    let deadline = Instant::now() + DECRYPTION_DEADLINE;
    let mut keys = keys.map(Box::pin);
    loop {
        match try_decrypt(room, event, push_context).await {
            Decryption::Decrypted(event) => return Some(*event),
            Decryption::Hopeless => return None,
            Decryption::MissingKey => {}
        }
        let keys = keys.as_mut()?;
        // Wait for a key of this room, or for keys that may have been missed.
        loop {
            let remaining = deadline.saturating_duration_since(Instant::now());
            match timeout(remaining, keys.next()).await {
                Ok(Some(Ok(received))) => {
                    if received.iter().any(|key| key.room_id == room.room_id()) {
                        break;
                    }
                }
                Ok(Some(Err(_))) => break,
                Ok(None) | Err(_) => return None,
            }
        }
    }
}

#[frb(ignore)]
enum Decryption {
    Decrypted(Box<TimelineEvent>),
    MissingKey,
    /// Waiting won't help (e.g. the sender withheld the key).
    Hopeless,
}

async fn try_decrypt(
    room: &Room,
    event: &Raw<AnySyncTimelineEvent>,
    push_context: Option<&PushContext>,
) -> Decryption {
    let decrypted = room
        .decrypt_event(
            event.cast_ref_unchecked::<OriginalSyncRoomEncryptedEvent>(),
            push_context,
        )
        .await;
    match decrypted {
        Ok(event) => match &event.kind {
            TimelineEventKind::UnableToDecrypt { utd_info, .. } => {
                if utd_info.reason.is_missing_room_key() {
                    Decryption::MissingKey
                } else {
                    Decryption::Hopeless
                }
            }
            _ => Decryption::Decrypted(Box::new(event)),
        },
        Err(_) => Decryption::Hopeless,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn item(event_id: Option<&str>, room_id: &str) -> NotificationItem {
        NotificationItem {
            room_id: room_id.to_owned(),
            event_id: event_id.map(ToOwned::to_owned),
            thread_root: None,
            room_name: room_id.to_owned(),
            sender_id: "@bob:example.org".to_owned(),
            sender_name: "Bob".to_owned(),
            sender_avatar: None,
            body_preview: None,
            is_dm: false,
            is_highlight: false,
            sound: false,
            is_invite: event_id.is_none(),
            timestamp_ms: 0,
        }
    }

    #[test]
    fn an_event_sent_again_notifies_once() {
        let mut seen = Seen::default();
        assert!(seen.first_time(&item(Some("$a"), "!r")));
        assert!(!seen.first_time(&item(Some("$a"), "!r")));
        assert!(seen.first_time(&item(Some("$b"), "!r")));
        assert!(seen.first_time(&item(None, "!r")));
        assert!(!seen.first_time(&item(None, "!r")));
        assert!(seen.first_time(&item(None, "!other")));
    }

    #[test]
    fn the_oldest_seen_ids_are_forgotten() {
        let mut seen = Seen::default();
        for n in 0..=SEEN_LIMIT {
            assert!(seen.first_time(&item(Some(&format!("${n}")), "!r")));
        }
        assert_eq!(seen.ids.len(), SEEN_LIMIT);
        assert!(seen.first_time(&item(Some("$0"), "!r")));
        assert!(!seen.first_time(&item(Some(&format!("${SEEN_LIMIT}")), "!r")));
    }

    #[test]
    fn only_encrypted_events_count_as_encrypted() -> Result<(), serde_json::Error> {
        let encrypted: Raw<AnySyncTimelineEvent> =
            serde_json::from_str(r#"{"type":"m.room.encrypted","content":{}}"#)?;
        let message: Raw<AnySyncTimelineEvent> =
            serde_json::from_str(r#"{"type":"m.room.message","content":{}}"#)?;
        assert!(is_encrypted(&encrypted));
        assert!(!is_encrypted(&message));
        Ok(())
    }
}
