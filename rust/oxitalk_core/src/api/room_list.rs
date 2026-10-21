//! The room list: every room the user is in or invited to, newest activity first, delivered as
//! batches of diffs against the list the app holds.

use flutter_rust_bridge::frb;
use futures_util::{StreamExt, future::join_all, stream};
use matrix_sdk::{
    Client, Room, RoomState,
    notification_settings::NotificationSettings,
    ruma::{
        OwnedRoomId,
        events::{
            AnySyncMessageLikeEvent, AnySyncTimelineEvent, SyncMessageLikeEvent,
            room::message::Relation,
        },
    },
    serde_helpers::extract_thread_root,
};
use matrix_sdk_ui::{
    eyeball_im::VectorDiff,
    room_list_service::{RoomListItem, filters::new_filter_non_left},
    timeline::{LatestEventValue, RoomExt},
};

use super::{
    error::CoreError,
    notifications::{RoomNotificationMode, room_modes, settings_changes},
    session::Session,
    timeline::{dart_int, msgtype_preview, preview_text},
};
use crate::frb_generated::StreamSink;

/// How many rooms the list holds. M0 has no paging; this is far above any real account.
const ROOM_LIST_LIMIT: usize = 10_000;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RoomSummary {
    pub room_id: String,
    /// The display name, computed by the SDK from the room's name, alias or members.
    pub name: String,
    /// An `mxc://` URI: the room's avatar or, in a direct chat without one, the other
    /// person's.
    pub avatar_url: Option<String>,
    pub membership: Membership,
    /// The body of the latest message, if the latest event is a text message.
    pub last_message: Option<String>,
    /// When the latest event happened, in milliseconds since the Unix epoch.
    pub last_activity_ms: Option<i64>,
    /// Unread messages, notifying or not; Element shows them as a dot only.
    pub unread_count: u32,
    /// Unread messages that notify by the push rules: all of them, only mentions and keywords,
    /// or none in a muted room.
    pub unread_notifications: u32,
    /// Unread messages that mention the user (or @room) or contain a keyword.
    pub unread_mentions: u32,
    /// Marked unread by the user, here or in another client.
    pub marked_unread: bool,
    /// The room's own notification mode; `None` while it follows the account default.
    pub notification_mode: Option<RoomNotificationMode>,
    /// The account default the room follows without a mode of its own.
    pub default_notification_mode: RoomNotificationMode,
    pub is_dm: bool,
    pub is_encrypted: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Membership {
    Joined,
    Invited,
    Knocked,
    Left,
    Banned,
}

/// One change to the room list. Indexes refer to the list as it is when the diff is applied;
/// the diffs in a batch are applied in order.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RoomListDiff {
    Append { values: Vec<RoomSummary> },
    Clear,
    PushFront { value: RoomSummary },
    PushBack { value: RoomSummary },
    PopFront,
    PopBack,
    Insert { index: u32, value: RoomSummary },
    Set { index: u32, value: RoomSummary },
    Remove { index: u32 },
    Truncate { length: u32 },
    Reset { values: Vec<RoomSummary> },
}

impl Session {
    /// Sends the room list as batches of diffs. The first batch is a `Reset` with the whole
    /// list.
    ///
    /// # Errors
    ///
    /// If the SDK's room list can't be set up.
    pub async fn subscribe_rooms(
        &self,
        sink: StreamSink<Vec<RoomListDiff>>,
    ) -> Result<(), CoreError> {
        self.room_list_updates(move |batch| sink.add(batch).is_ok())
            .await
    }

    /// Like [`Self::subscribe_rooms`], for Rust callers: `emit` gets each batch and returns
    /// `false` to stop.
    ///
    /// # Errors
    ///
    /// As [`Self::subscribe_rooms`].
    #[frb(ignore)]
    pub async fn room_list_updates(
        &self,
        emit: impl Fn(Vec<RoomListDiff>) -> bool + Send + 'static,
    ) -> Result<(), CoreError> {
        let room_list = self
            .sync
            .room_list_service()
            .all_rooms()
            .await
            .map_err(|error| CoreError::internal(&error))?;
        let settings = self.notification_settings.clone();
        let client = self.client.clone();
        // Subscribed before the list is read, so no change falls in between.
        let settings_changed = settings_changes(settings.subscribe_to_changes());
        self.spawn(async move {
            let (entries, controller) = room_list.entries_with_dynamic_adapters(ROOM_LIST_LIMIT);
            controller.set_filter(Box::new(new_filter_non_left()));
            let list_updates = entries
                .map(ListInput::Diffs)
                .chain(stream::once(async { ListInput::End }));
            let mut inputs = Box::pin(stream::select(
                list_updates,
                settings_changed.map(|()| ListInput::SettingsChanged),
            ));
            // The list as the app has it, to know which rooms a settings change affects.
            let mut shown = Vec::new();
            while let Some(input) = inputs.next().await {
                let batch = match input {
                    ListInput::Diffs(diffs) => {
                        join_all(
                            diffs
                                .into_iter()
                                .map(|diff| room_list_diff(&settings, diff)),
                        )
                        .await
                    }
                    ListInput::SettingsChanged => mode_changes(&client, &settings, &shown).await,
                    ListInput::End => break,
                };
                if batch.is_empty() {
                    continue;
                }
                for diff in &batch {
                    apply_diff(&mut shown, diff.clone());
                }
                if !emit(batch) {
                    break;
                }
            }
        });
        Ok(())
    }
}

/// What the room list task waits for.
enum ListInput {
    Diffs(Vec<VectorDiff<RoomListItem>>),
    /// The push rules changed. The SDK's list doesn't send the rooms again for that alone
    /// (checked on Synapse and Tuwunel, 2026-10-21), so the task does.
    SettingsChanged,
    /// The SDK's list ended.
    End,
}

/// `Set` diffs for the rooms in `shown` whose notification modes are no longer what they
/// show.
async fn mode_changes(
    client: &Client,
    settings: &NotificationSettings,
    shown: &[RoomSummary],
) -> Vec<RoomListDiff> {
    let mut changes = Vec::new();
    for (index, summary) in shown.iter().enumerate() {
        let Some(room) = OwnedRoomId::try_from(summary.room_id.as_str())
            .ok()
            .and_then(|id| client.get_room(&id))
        else {
            continue;
        };
        let modes = room_modes(settings, &room).await;
        if summary.notification_mode != modes.user_defined
            || summary.default_notification_mode != modes.default
        {
            changes.push(RoomListDiff::Set {
                index: dart_int(index),
                value: RoomSummary {
                    notification_mode: modes.user_defined,
                    default_notification_mode: modes.default,
                    ..summary.clone()
                },
            });
        }
    }
    changes
}

/// Applies `diff` to `list` as the app does. An index out of range (which the SDK never
/// sends) changes nothing.
fn apply_diff(list: &mut Vec<RoomSummary>, diff: RoomListDiff) {
    let at = |index: u32| usize::try_from(index).unwrap_or(usize::MAX);
    match diff {
        RoomListDiff::Append { values } => list.extend(values),
        RoomListDiff::Clear => list.clear(),
        RoomListDiff::PushFront { value } => list.insert(0, value),
        RoomListDiff::PushBack { value } => list.push(value),
        RoomListDiff::PopFront => {
            if !list.is_empty() {
                list.remove(0);
            }
        }
        RoomListDiff::PopBack => {
            list.pop();
        }
        RoomListDiff::Insert { index, value } => {
            if at(index) <= list.len() {
                list.insert(at(index), value);
            }
        }
        RoomListDiff::Set { index, value } => {
            if let Some(slot) = list.get_mut(at(index)) {
                *slot = value;
            }
        }
        RoomListDiff::Remove { index } => {
            if at(index) < list.len() {
                list.remove(at(index));
            }
        }
        RoomListDiff::Truncate { length } => list.truncate(at(length)),
        RoomListDiff::Reset { values } => *list = values,
    }
}

async fn room_list_diff(
    settings: &NotificationSettings,
    diff: VectorDiff<RoomListItem>,
) -> RoomListDiff {
    match diff {
        VectorDiff::Append { values } => RoomListDiff::Append {
            values: summaries(settings, values).await,
        },
        VectorDiff::Clear => RoomListDiff::Clear,
        VectorDiff::PushFront { value } => RoomListDiff::PushFront {
            value: summary(settings, value).await,
        },
        VectorDiff::PushBack { value } => RoomListDiff::PushBack {
            value: summary(settings, value).await,
        },
        VectorDiff::PopFront => RoomListDiff::PopFront,
        VectorDiff::PopBack => RoomListDiff::PopBack,
        VectorDiff::Insert { index, value } => RoomListDiff::Insert {
            index: dart_int(index),
            value: summary(settings, value).await,
        },
        VectorDiff::Set { index, value } => RoomListDiff::Set {
            index: dart_int(index),
            value: summary(settings, value).await,
        },
        VectorDiff::Remove { index } => RoomListDiff::Remove {
            index: dart_int(index),
        },
        VectorDiff::Truncate { length } => RoomListDiff::Truncate {
            length: dart_int(length),
        },
        VectorDiff::Reset { values } => RoomListDiff::Reset {
            values: summaries(settings, values).await,
        },
    }
}

async fn summaries(
    settings: &NotificationSettings,
    rooms: impl IntoIterator<Item = RoomListItem>,
) -> Vec<RoomSummary> {
    join_all(rooms.into_iter().map(|room| summary(settings, room))).await
}

/// When the newest message the SDK has loaded is a reply in a thread: the newest message
/// outside threads and its time (`None` inside if there is none loaded). `None` otherwise: the
/// SDK's latest event is what the list shows.
///
/// The one piece of logic of ours in the core (bkv, 2026-10-20): replies in a thread stay in
/// it, as Telegram's comments do, so the chat list never shows one. The SDK's latest event
/// includes them and doesn't say it is in a thread; only the core can read the SDK's event
/// cache to tell and to look further back. A thread reply of the user's that is still being
/// sent isn't in the cache yet, so it shows until the server has it.
async fn thread_free_preview(room: &Room) -> Option<Option<(String, i64)>> {
    let (cache, _handles) = room
        .client()
        .event_cache()?
        .room(room.room_id())
        .await
        .ok()?;
    let events = cache.events().await.ok()?;
    let mut messages = events.iter().rev().filter_map(|event| {
        let Ok(AnySyncTimelineEvent::MessageLike(AnySyncMessageLikeEvent::RoomMessage(
            SyncMessageLikeEvent::Original(message),
        ))) = event.raw().deserialize()
        else {
            return None;
        };
        // An edit changes an older message; that message is what the list shows.
        if matches!(message.content.relates_to, Some(Relation::Replacement(_))) {
            return None;
        }
        Some((extract_thread_root(event.raw()).is_some(), message))
    });
    let (newest_in_thread, _) = messages.next()?;
    if !newest_in_thread {
        return None;
    }
    Some(
        messages
            .find(|(in_thread, _)| !in_thread)
            .map(|(_, message)| {
                (
                    msgtype_preview(&message.content.msgtype),
                    message.origin_server_ts.0.into(),
                )
            }),
    )
}

async fn summary(settings: &NotificationSettings, room: RoomListItem) -> RoomSummary {
    let room = room.into_inner();
    let (last_message, last_activity_ms) = match RoomExt::latest_event(&room).await {
        LatestEventValue::Remote {
            timestamp, content, ..
        }
        | LatestEventValue::Local {
            timestamp, content, ..
        } => match thread_free_preview(&room).await {
            Some(Some((text, at))) => (Some(text), Some(at)),
            Some(None) => (None, Some(timestamp.0.into())),
            None => (
                content.as_message().map(preview_text),
                Some(timestamp.0.into()),
            ),
        },
        LatestEventValue::RemoteInvite { timestamp, .. } => (None, Some(timestamp.0.into())),
        LatestEventValue::None => (None, None),
    };
    // A store read error only loses the DM marker; the room still shows.
    let is_dm = room.is_direct().await.unwrap_or(false);
    let avatar_url = match room.avatar_url() {
        Some(url) => Some(url),
        None if is_dm => match room.heroes().await.as_slice() {
            [other] => other.avatar_url.clone(),
            _ => None,
        },
        None => None,
    };
    let modes = room_modes(settings, &room).await;
    RoomSummary {
        room_id: room.room_id().to_string(),
        name: room
            .cached_display_name()
            .map_or_else(|| room.room_id().to_string(), |name| name.to_string()),
        avatar_url: avatar_url.map(|url| url.to_string()),
        membership: match room.state() {
            RoomState::Joined => Membership::Joined,
            RoomState::Invited => Membership::Invited,
            RoomState::Knocked => Membership::Knocked,
            RoomState::Left => Membership::Left,
            RoomState::Banned => Membership::Banned,
        },
        last_message,
        last_activity_ms,
        unread_count: count(room.num_unread_messages()),
        unread_notifications: count(room.num_unread_notifications()),
        unread_mentions: count(room.num_unread_mentions()),
        marked_unread: room.is_marked_unread(),
        notification_mode: modes.user_defined,
        default_notification_mode: modes.default,
        is_dm,
        is_encrypted: room.encryption_state().is_encrypted(),
    }
}

fn count(value: u64) -> u32 {
    u32::try_from(value).unwrap_or(u32::MAX)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn room(id: &str) -> RoomSummary {
        RoomSummary {
            room_id: id.to_owned(),
            name: id.to_owned(),
            avatar_url: None,
            membership: Membership::Joined,
            last_message: None,
            last_activity_ms: None,
            unread_count: 0,
            unread_notifications: 0,
            unread_mentions: 0,
            marked_unread: false,
            notification_mode: None,
            default_notification_mode: RoomNotificationMode::AllMessages,
            is_dm: false,
            is_encrypted: false,
        }
    }

    fn ids(list: &[RoomSummary]) -> Vec<&str> {
        list.iter().map(|room| room.room_id.as_str()).collect()
    }

    #[test]
    fn diffs_apply_as_the_app_applies_them() {
        let mut list = Vec::new();
        apply_diff(
            &mut list,
            RoomListDiff::Reset {
                values: vec![room("b")],
            },
        );
        apply_diff(&mut list, RoomListDiff::PushFront { value: room("a") });
        apply_diff(&mut list, RoomListDiff::PushBack { value: room("d") });
        apply_diff(
            &mut list,
            RoomListDiff::Insert {
                index: 2,
                value: room("c"),
            },
        );
        assert_eq!(ids(&list), ["a", "b", "c", "d"]);
        apply_diff(
            &mut list,
            RoomListDiff::Set {
                index: 1,
                value: room("B"),
            },
        );
        apply_diff(&mut list, RoomListDiff::Remove { index: 2 });
        assert_eq!(ids(&list), ["a", "B", "d"]);
        apply_diff(&mut list, RoomListDiff::PopFront);
        apply_diff(&mut list, RoomListDiff::PopBack);
        apply_diff(
            &mut list,
            RoomListDiff::Append {
                values: vec![room("e"), room("f")],
            },
        );
        apply_diff(&mut list, RoomListDiff::Truncate { length: 2 });
        assert_eq!(ids(&list), ["B", "e"]);
        apply_diff(&mut list, RoomListDiff::Clear);
        assert_eq!(ids(&list), Vec::<&str>::new());
    }

    #[test]
    fn diffs_out_of_range_change_nothing() {
        let mut list = vec![room("a")];
        apply_diff(
            &mut list,
            RoomListDiff::Set {
                index: 5,
                value: room("x"),
            },
        );
        apply_diff(
            &mut list,
            RoomListDiff::Insert {
                index: 5,
                value: room("x"),
            },
        );
        apply_diff(&mut list, RoomListDiff::Remove { index: 5 });
        assert_eq!(ids(&list), ["a"]);
        list.clear();
        apply_diff(&mut list, RoomListDiff::PopFront);
        apply_diff(&mut list, RoomListDiff::PopBack);
        assert_eq!(ids(&list), Vec::<&str>::new());
    }
}
