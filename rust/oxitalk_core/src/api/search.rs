//! Searching one room's messages for a text, on this device only, so it works the same in
//! end-to-end encrypted rooms: the event cache store keeps every event the client has seen
//! (from the sync, from paging back, from threads), decrypted, in the encrypted SQLite store.
//! A search reads the room's messages from there; [`Session::search_load_older`] pages the
//! room's history back from the server into the store, to search further back.

use std::collections::HashMap;

use matrix_sdk::{
    Room,
    cross_process_lock::MappedCrossProcessLockState,
    deserialized_responses::TimelineEvent,
    ruma::{OwnedUserId, events::room::message::sanitize::remove_plain_reply_fallback},
};
use serde_json::Value;

use super::{error::CoreError, session::Session, timeline::MediaKind};

/// One message that contains the searched text.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SearchHit {
    pub event_id: String,
    /// The thread's first event, for a reply in a thread (which shows only in the thread).
    pub thread_root: Option<String>,
    pub sender: String,
    pub sender_name: Option<String>,
    /// An `mxc://` URI.
    pub sender_avatar_url: Option<String>,
    pub timestamp_ms: i64,
    /// The message's text as it is now (after edits), or a file's caption.
    pub text: String,
    /// A file's name, for a file message.
    pub filename: Option<String>,
    pub media_kind: Option<MediaKind>,
}

/// What a search found.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SearchResults {
    /// The newest first; at most the `limit` asked for.
    pub hits: Vec<SearchHit>,
    /// How many messages matched, also beyond the limit.
    pub total: u32,
    /// How many messages of the room were searched (edits not counted).
    pub searched: u32,
    /// The time of the oldest message searched, if any.
    pub oldest_ms: Option<i64>,
}

impl Session {
    /// Searches the room's messages this device has for `query`: case-insensitive, in the
    /// text, a file's caption and its name. Nothing goes to the server. Deleted messages are
    /// left out, edited ones are searched as they are now.
    ///
    /// # Errors
    ///
    /// [`CoreError::InvalidId`], [`CoreError::RoomNotFound`], or
    /// [`CoreError::Internal`] if the store can't be read.
    pub async fn search_room(
        &self,
        room_id: String,
        query: String,
        limit: u32,
    ) -> Result<SearchResults, CoreError> {
        let room = self.room(&room_id)?;
        let events = stored_messages(&self.client, &room).await?;
        let mut results = search(&events, &query, limit as usize);
        add_profiles(&room, &mut results.hits).await;
        Ok(results)
    }

    /// Pages the room's history back from where the device has it, by about `events` events,
    /// so that a search reaches further back. Encrypted events are decrypted as they come,
    /// when the device has their keys. Returns `true` once the room's first event is reached.
    ///
    /// # Errors
    ///
    /// [`CoreError::InvalidId`], [`CoreError::RoomNotFound`], or as the server answers.
    pub async fn search_load_older(&self, room_id: String, events: u32) -> Result<bool, CoreError> {
        let room = self.room(&room_id)?;
        let (cache, _handles) = self
            .client
            .event_cache()
            .ok_or_else(|| CoreError::internal(&"no event cache"))?
            .room(room.room_id())
            .await
            .map_err(|error| CoreError::internal(&error))?;
        let pagination = cache.pagination();
        let mut loaded = 0usize;
        // Bounded: a page of only state events adds no message but still counts.
        for _ in 0..MAX_PAGES {
            let outcome = pagination
                .run_backwards_once(PAGE_SIZE)
                .await
                .map_err(|error| CoreError::internal(&error))?;
            if outcome.reached_start {
                return Ok(true);
            }
            loaded += outcome.events.len().max(1);
            if loaded >= events as usize {
                break;
            }
        }
        Ok(false)
    }
}

/// Events asked for per back-pagination request.
const PAGE_SIZE: u16 = 100;

/// The most requests one [`Session::search_load_older`] makes.
const MAX_PAGES: usize = 50;

/// The room's `m.room.message` and `m.room.redaction` events in the event cache store, as
/// JSON.
async fn stored_messages(
    client: &matrix_sdk::Client,
    room: &Room,
) -> Result<Vec<Value>, CoreError> {
    let store = match client
        .event_cache_store()
        .lock()
        .await
        .map_err(|error| CoreError::internal(&error))?
    {
        MappedCrossProcessLockState::Clean(store) | MappedCrossProcessLockState::Dirty(store) => {
            store
        }
    };
    let mut events = Vec::new();
    for event_type in ["m.room.message", "m.room.redaction"] {
        let stored: Vec<TimelineEvent> = store
            .get_room_events(room.room_id(), Some(event_type), None)
            .await
            .map_err(|error| CoreError::internal(&error))?;
        events.extend(
            stored
                .iter()
                .filter_map(|event| serde_json::from_str(event.raw().json().get()).ok()),
        );
    }
    Ok(events)
}

/// A message as stored, with what a search needs.
struct Message<'a> {
    event_id: &'a str,
    sender: &'a str,
    timestamp_ms: i64,
    content: &'a Value,
    thread_root: Option<&'a str>,
}

fn message(event: &Value) -> Option<Message<'_>> {
    let content = event.get("content")?;
    Some(Message {
        event_id: event.get("event_id")?.as_str()?,
        sender: event.get("sender")?.as_str()?,
        timestamp_ms: event.get("origin_server_ts")?.as_i64()?,
        content,
        thread_root: relation(content, "m.thread"),
    })
}

/// The event a relation of type `rel_type` points to.
fn relation<'a>(content: &'a Value, rel_type: &str) -> Option<&'a str> {
    let relates_to = content.get("m.relates_to")?;
    (relates_to.get("rel_type")?.as_str()? == rel_type)
        .then(|| relates_to.get("event_id")?.as_str())
        .flatten()
}

/// What a message is searched by: its text (or a file's caption) and a file's name.
fn searchable(content: &Value) -> Option<(String, Option<String>, Option<MediaKind>)> {
    let msgtype = content.get("msgtype")?.as_str()?;
    let body = content.get("body")?.as_str()?;
    let kind = match msgtype {
        "m.image" => Some(MediaKind::Image),
        "m.video" => Some(MediaKind::Video),
        "m.audio" => Some(MediaKind::Audio),
        "m.file" => Some(MediaKind::File),
        _ => None,
    };
    if kind.is_none() {
        return Some((remove_plain_reply_fallback(body).to_owned(), None, None));
    }
    // A file: `body` is the caption when `filename` is there and differs, else the name.
    let filename = content.get("filename").and_then(Value::as_str);
    Some(match filename {
        Some(name) if name != body => (body.to_owned(), Some(name.to_owned()), kind),
        _ => (String::new(), Some(body.to_owned()), kind),
    })
}

/// Searches `events` (messages and redactions, in any order) for `query`.
fn search(events: &[Value], query: &str, limit: usize) -> SearchResults {
    let needle = query.trim().to_lowercase();
    let mut redacted = std::collections::HashSet::new();
    // The latest valid edit of each message: (timestamp, sender, new content).
    let mut edits: HashMap<&str, (i64, &str, &Value)> = HashMap::new();
    let mut originals = Vec::new();
    for event in events {
        if event.get("type").and_then(Value::as_str) == Some("m.room.redaction") {
            if let Some(target) = event
                .get("redacts")
                .or_else(|| event.get("content")?.get("redacts"))
                .and_then(Value::as_str)
            {
                redacted.insert(target);
            }
            continue;
        }
        let Some(message) = message(event) else {
            continue;
        };
        if let Some(target) = relation(message.content, "m.replace") {
            if let Some(new_content) = message.content.get("m.new_content") {
                let newer = edits
                    .get(target)
                    .is_none_or(|(timestamp, ..)| *timestamp < message.timestamp_ms);
                if newer {
                    edits.insert(target, (message.timestamp_ms, message.sender, new_content));
                }
            }
            continue;
        }
        originals.push(message);
    }
    let mut searched = 0u32;
    let mut oldest_ms = None;
    let mut hits = Vec::new();
    for message in originals {
        if redacted.contains(message.event_id) {
            continue;
        }
        // Only the sender's own edits count, as the SDK checks.
        let content = match edits.get(message.event_id) {
            Some((_, sender, new_content)) if *sender == message.sender => *new_content,
            _ => message.content,
        };
        let Some((text, filename, media_kind)) = searchable(content) else {
            continue;
        };
        searched += 1;
        oldest_ms =
            Some(oldest_ms.map_or(message.timestamp_ms, |o: i64| o.min(message.timestamp_ms)));
        let found = !needle.is_empty()
            && (text.to_lowercase().contains(&needle)
                || filename
                    .as_ref()
                    .is_some_and(|name| name.to_lowercase().contains(&needle)));
        if found {
            hits.push(SearchHit {
                event_id: message.event_id.to_owned(),
                thread_root: message.thread_root.map(ToOwned::to_owned),
                sender: message.sender.to_owned(),
                sender_name: None,
                sender_avatar_url: None,
                timestamp_ms: message.timestamp_ms,
                text,
                filename,
                media_kind,
            });
        }
    }
    hits.sort_by(|a, b| {
        b.timestamp_ms
            .cmp(&a.timestamp_ms)
            .then_with(|| b.event_id.cmp(&a.event_id))
    });
    let total = u32::try_from(hits.len()).unwrap_or(u32::MAX);
    hits.truncate(limit);
    SearchResults {
        hits,
        total,
        searched,
        oldest_ms,
    }
}

/// Fills in the senders' names and pictures from the room's members.
async fn add_profiles(room: &Room, hits: &mut [SearchHit]) {
    let mut profiles: HashMap<String, (Option<String>, Option<String>)> = HashMap::new();
    for hit in hits.iter_mut() {
        if !profiles.contains_key(&hit.sender) {
            let profile = match OwnedUserId::try_from(hit.sender.as_str()) {
                Ok(user) => match room.get_member_no_sync(&user).await {
                    Ok(Some(member)) => (
                        member.display_name().map(ToOwned::to_owned),
                        member.avatar_url().map(ToString::to_string),
                    ),
                    _ => (None, None),
                },
                Err(_) => (None, None),
            };
            profiles.insert(hit.sender.clone(), profile);
        }
        if let Some((name, avatar)) = profiles.get(&hit.sender) {
            hit.sender_name.clone_from(name);
            hit.sender_avatar_url.clone_from(avatar);
        }
    }
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::*;

    fn text(id: &str, sender: &str, ts: i64, body: &str) -> Value {
        json!({
            "type": "m.room.message", "event_id": id, "sender": sender,
            "origin_server_ts": ts, "content": { "msgtype": "m.text", "body": body },
        })
    }

    const NONE: [&str; 0] = [];

    fn ids(results: &SearchResults) -> Vec<&str> {
        results
            .hits
            .iter()
            .map(|hit| hit.event_id.as_str())
            .collect()
    }

    #[test]
    fn finds_text_case_insensitively_newest_first() {
        let events = [
            text("$1", "@a:x", 1, "Pizza tonight?"),
            text("$2", "@b:x", 2, "no"),
            text("$3", "@a:x", 3, "PIZZA again"),
            text("$4", "@a:x", 4, "Größe"),
        ];
        let results = search(&events, "pizza", 10);
        assert_eq!(ids(&results), ["$3", "$1"]);
        assert_eq!(results.total, 2);
        assert_eq!(results.searched, 4);
        assert_eq!(results.oldest_ms, Some(1));
        assert_eq!(ids(&search(&events, "GRÖSSE", 10)), NONE);
        assert_eq!(ids(&search(&events, "grÖße", 10)), ["$4"]);
        assert_eq!(ids(&search(&events, "  ", 10)), NONE);
    }

    #[test]
    fn the_limit_keeps_the_newest_and_counts_all() {
        let events: Vec<_> = (1..=5)
            .map(|i| text(&format!("${i}"), "@a:x", i, "hit"))
            .collect();
        let results = search(&events, "hit", 2);
        assert_eq!(ids(&results), ["$5", "$4"]);
        assert_eq!(results.total, 5);
    }

    #[test]
    fn edits_replace_the_text_only_by_the_sender() {
        let edit = |id: &str, sender: &str, ts: i64, target: &str, body: &str| {
            json!({
                "type": "m.room.message", "event_id": id, "sender": sender, "origin_server_ts": ts,
                "content": {
                    "msgtype": "m.text", "body": format!("* {body}"),
                    "m.new_content": { "msgtype": "m.text", "body": body },
                    "m.relates_to": { "rel_type": "m.replace", "event_id": target },
                },
            })
        };
        let events = [
            text("$1", "@a:x", 1, "old words"),
            edit("$2", "@a:x", 3, "$1", "newest words"),
            edit("$3", "@a:x", 2, "$1", "middle words"),
            text("$4", "@a:x", 4, "untouched"),
            edit("$5", "@mallory:x", 5, "$4", "forged"),
        ];
        assert_eq!(ids(&search(&events, "newest", 10)), ["$1"]);
        assert_eq!(ids(&search(&events, "old", 10)), NONE);
        assert_eq!(ids(&search(&events, "middle", 10)), NONE);
        assert_eq!(ids(&search(&events, "forged", 10)), NONE);
        assert_eq!(ids(&search(&events, "untouched", 10)), ["$4"]);
        assert_eq!(search(&events, "words", 10).searched, 2);
    }

    #[test]
    fn deleted_messages_and_reply_quotes_are_left_out() {
        let events = [
            text("$1", "@a:x", 1, "secret"),
            json!({ "type": "m.room.redaction", "event_id": "$2", "sender": "@a:x",
                    "origin_server_ts": 2, "redacts": "$1", "content": {} }),
            text("$3", "@a:x", 3, "secret two"),
            json!({ "type": "m.room.redaction", "event_id": "$4", "sender": "@a:x",
                    "origin_server_ts": 4, "content": { "redacts": "$3" } }),
            // Redacted in the store already: no body.
            json!({ "type": "m.room.message", "event_id": "$5", "sender": "@a:x",
                    "origin_server_ts": 5, "content": {} }),
            text("$6", "@b:x", 6, "> <@a:x> secret\n\nwhat secret?"),
            text("$7", "@b:x", 7, "> <@a:x> quoted only\n\nfine"),
        ];
        assert_eq!(ids(&search(&events, "secret", 10)), ["$6"]);
        assert_eq!(ids(&search(&events, "quoted", 10)), NONE);
    }

    #[test]
    fn files_are_found_by_caption_and_name_and_threads_kept() {
        let events = [
            json!({ "type": "m.room.message", "event_id": "$1", "sender": "@a:x",
                    "origin_server_ts": 1,
                    "content": { "msgtype": "m.file", "body": "Report-Q3.pdf" } }),
            json!({ "type": "m.room.message", "event_id": "$2", "sender": "@a:x",
                    "origin_server_ts": 2,
                    "content": { "msgtype": "m.image", "body": "our cat", "filename": "IMG_1.jpg",
                                 "m.relates_to": { "rel_type": "m.thread", "event_id": "$root" } } }),
        ];
        let report = search(&events, "q3", 10);
        assert_eq!(ids(&report), ["$1"]);
        assert_eq!(report.hits[0].filename.as_deref(), Some("Report-Q3.pdf"));
        assert_eq!(report.hits[0].text, "");
        assert_eq!(report.hits[0].media_kind, Some(MediaKind::File));
        let cat = search(&events, "cat", 10);
        assert_eq!(ids(&cat), ["$2"]);
        assert_eq!(cat.hits[0].thread_root.as_deref(), Some("$root"));
        assert_eq!(cat.hits[0].text, "our cat");
        assert_eq!(ids(&search(&events, "img_1", 10)), ["$2"]);
    }
}
