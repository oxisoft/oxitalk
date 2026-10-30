//! Unsent drafts of the composer: one per room and one per thread, kept in the account's own
//! encrypted state store through the SDK's composer drafts (`Room::save_composer_draft`), so
//! they survive switching chats, accounts and a restart. They never leave the device.
//!
//! A draft is stored as the SDK's [`ComposerDraft`]: the plain text with the pills' names, and,
//! when there are pills, an HTML version in which each pill is an `<a>` with
//! `data-mention-type` and the ID, which [`Draft`] is read back from.

use flutter_rust_bridge::frb;
use matrix_sdk::{
    ComposerDraft, ComposerDraftType, Room, RoomState,
    ruma::{EventId, OwnedEventId, UserId},
};
use matrix_sdk_ui::timeline::{EmbeddedEvent, TimelineDetails};
use ruma::html::{Html, NodeRef};

use super::{
    error::{CoreError, parse_id},
    mentions::MessagePart,
    session::Session,
    timeline::{
        EventInfo, Readers, SendState, Timeline, TimelineItem, TimelineItemContent, formatted_text,
        item, media_message,
    },
};

/// What the composer held when the user left it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Draft {
    /// The text and pills, as typed (not trimmed).
    pub parts: Vec<MessagePart>,
    pub kind: DraftKind,
}

/// Whether a draft is a new message, or answers or edits one.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DraftKind {
    NewMessage,
    Reply { event_id: String },
    Edit { event_id: String },
}

/// The chat list's line for a room with a draft.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DraftPreview {
    pub room_id: String,
    /// The draft's first line that has text, the pills by name.
    pub text: String,
}

impl Session {
    /// Keeps `draft` as the room's draft, or the thread's that starts at `thread_root`. A draft
    /// without text removes the stored one.
    ///
    /// # Errors
    ///
    /// [`CoreError::InvalidId`], [`CoreError::RoomNotFound`], or if the store fails.
    pub async fn save_draft(
        &self,
        room_id: String,
        thread_root: Option<String>,
        draft: Draft,
    ) -> Result<(), CoreError> {
        let thread = thread_id(thread_root.as_deref())?;
        save(&self.room(&room_id)?, thread.as_deref(), &draft).await
    }

    /// The room's draft (or the thread's), if one was kept.
    ///
    /// # Errors
    ///
    /// As [`Session::save_draft`].
    pub async fn load_draft(
        &self,
        room_id: String,
        thread_root: Option<String>,
    ) -> Result<Option<Draft>, CoreError> {
        let thread = thread_id(thread_root.as_deref())?;
        load(&self.room(&room_id)?, thread.as_deref()).await
    }

    /// Forgets the room's draft (or the thread's): after sending, or when the composer is
    /// emptied.
    ///
    /// # Errors
    ///
    /// As [`Session::save_draft`].
    pub async fn clear_draft(
        &self,
        room_id: String,
        thread_root: Option<String>,
    ) -> Result<(), CoreError> {
        let thread = thread_id(thread_root.as_deref())?;
        clear(&self.room(&room_id)?, thread.as_deref()).await
    }

    /// The rooms the user is in that have a draft of their own (thread drafts aren't listed),
    /// with its first line, for the chat list.
    pub async fn draft_previews(&self) -> Vec<DraftPreview> {
        let mut previews = Vec::new();
        for room in self.client.rooms() {
            if room.state() != RoomState::Joined {
                continue;
            }
            // A draft that can't be read shows as none; opening the chat says why.
            if let Ok(Some(draft)) = room.load_composer_draft(None).await
                && let Some(text) = first_line(&draft.plain_text)
            {
                previews.push(DraftPreview {
                    room_id: room.room_id().to_string(),
                    text,
                });
            }
        }
        previews
    }
}

impl Timeline {
    /// The message a restored draft answers or edits, to show above the composer again:
    /// from this timeline, or for a reply also from the store or the server. `None` if it
    /// can't be found any more (the draft's text is kept without it); an edit needs the message
    /// in the timeline, as the SDK only edits what it has loaded.
    ///
    /// # Errors
    ///
    /// [`CoreError::InvalidId`] for a malformed event ID.
    pub async fn draft_target(
        &self,
        event_id: String,
        reply: bool,
    ) -> Result<Option<TimelineItem>, CoreError> {
        let id: OwnedEventId = parse_id(&event_id)?;
        let own = self.room().own_user_id().to_owned();
        let items = self.inner().items().await;
        let found = items.iter().find(|candidate| {
            candidate
                .as_event()
                .and_then(|event| event.event_id())
                .is_some_and(|event| event == id)
        });
        if let Some(found) = found {
            return Ok(Some(item(found, &own, &Readers::default())));
        }
        if !reply {
            return Ok(None);
        }
        let Ok(event) = self.room().load_or_fetch_event(&id, None).await else {
            return Ok(None);
        };
        let Ok(Some(embedded)) = self.inner().make_replied_to(event).await else {
            return Ok(None);
        };
        Ok(embedded_item(&embedded, &id, &own))
    }
}

/// A message found outside the timeline as the timeline would show it; `None` for anything
/// that isn't a message.
fn embedded_item(event: &EmbeddedEvent, id: &EventId, own: &UserId) -> Option<TimelineItem> {
    let message = event.content.as_message()?;
    let profile = match &event.sender_profile {
        TimelineDetails::Ready(profile) => Some(profile),
        _ => None,
    };
    let info = EventInfo {
        event_id: Some(id.to_string()),
        transaction_id: None,
        sender: event.sender.to_string(),
        sender_name: profile.and_then(|p| p.display_name.clone()),
        sender_avatar_url: profile.and_then(|p| p.avatar_url.as_ref().map(ToString::to_string)),
        timestamp_ms: event.timestamp.0.into(),
        is_own: event.sender == own,
        send_state: SendState::Sent,
        upload_percent: None,
        reactions: Vec::new(),
        in_reply_to: None,
        thread: None,
        is_edited: message.is_edited(),
        is_editable: false,
        read_by: Vec::new(),
    };
    let content = match media_message(message.msgtype()) {
        Some(media) => TimelineItemContent::Media { event: info, media },
        None => TimelineItemContent::Message {
            event: info,
            body: message.body().to_owned(),
            formatted: formatted_text(message.msgtype()),
        },
    };
    Some(TimelineItem {
        id: format!("draft-target-{id}"),
        content,
    })
}

fn thread_id(thread_root: Option<&str>) -> Result<Option<OwnedEventId>, CoreError> {
    thread_root.map(parse_id).transpose()
}

/// Stores `draft` for `room` (or its thread), or removes the stored one if it has no text.
pub(crate) async fn save(
    room: &Room,
    thread: Option<&EventId>,
    draft: &Draft,
) -> Result<(), CoreError> {
    match composer_draft(draft) {
        Some(stored) => room.save_composer_draft(stored, thread).await?,
        None => room.clear_composer_draft(thread).await?,
    }
    Ok(())
}

pub(crate) async fn load(
    room: &Room,
    thread: Option<&EventId>,
) -> Result<Option<Draft>, CoreError> {
    Ok(room
        .load_composer_draft(thread)
        .await?
        .map(|stored| draft_of(&stored)))
}

pub(crate) async fn clear(room: &Room, thread: Option<&EventId>) -> Result<(), CoreError> {
    room.clear_composer_draft(thread).await?;
    Ok(())
}

/// The SDK's form of `draft`; `None` if there is nothing but white space in it.
pub(crate) fn composer_draft(draft: &Draft) -> Option<ComposerDraft> {
    let empty = draft.parts.iter().all(|part| match part {
        MessagePart::Text { text } => text.trim().is_empty(),
        _ => false,
    });
    if empty {
        return None;
    }
    let mut plain = String::new();
    let mut html = String::new();
    let mut has_pill = false;
    for part in &draft.parts {
        match part {
            MessagePart::Text { text } => {
                plain.push_str(text);
                html.push_str(&escape_html(text).replace('\n', "<br>"));
            }
            MessagePart::User { user_id, name } => {
                let label = if name.trim().is_empty() {
                    user_id
                } else {
                    name
                };
                plain.push_str(label);
                push_pill(&mut html, "user", user_id, None, label);
                has_pill = true;
            }
            MessagePart::Room {
                room_id,
                alias,
                name,
            } => {
                plain.push_str(alias.as_deref().unwrap_or(name));
                push_pill(&mut html, "room", room_id, alias.as_deref(), name);
                has_pill = true;
            }
            MessagePart::AtRoom => {
                plain.push_str("@room");
                html.push_str("<a href=\"#\" data-mention-type=\"at-room\">@room</a>");
                has_pill = true;
            }
        }
    }
    Some(ComposerDraft {
        plain_text: plain,
        html_text: has_pill.then_some(html),
        draft_type: match &draft.kind {
            DraftKind::NewMessage => ComposerDraftType::NewMessage,
            DraftKind::Reply { event_id } => match parse_id(event_id) {
                Ok(event_id) => ComposerDraftType::Reply { event_id },
                Err(_) => ComposerDraftType::NewMessage,
            },
            DraftKind::Edit { event_id } => match parse_id(event_id) {
                Ok(event_id) => ComposerDraftType::Edit { event_id },
                Err(_) => ComposerDraftType::NewMessage,
            },
        },
        attachments: Vec::new(),
    })
}

/// The draft back from the SDK's form. A draft from another client without our pill markup
/// comes back as its plain text.
#[frb(ignore)]
pub(crate) fn draft_of(stored: &ComposerDraft) -> Draft {
    let parts = match &stored.html_text {
        Some(html) if html.contains("data-mention-type") => parts_of_html(html),
        _ => vec![MessagePart::Text {
            text: stored.plain_text.clone(),
        }],
    };
    Draft {
        parts,
        kind: match &stored.draft_type {
            ComposerDraftType::NewMessage => DraftKind::NewMessage,
            ComposerDraftType::Reply { event_id } => DraftKind::Reply {
                event_id: event_id.to_string(),
            },
            ComposerDraftType::Edit { event_id } => DraftKind::Edit {
                event_id: event_id.to_string(),
            },
        },
    }
}

/// A pill as a link: `<a href="https://matrix.to/#/…" data-mention-type="…" data-id="…">`.
fn push_pill(html: &mut String, kind: &str, id: &str, alias: Option<&str>, label: &str) {
    let id = escape_html(id);
    html.push_str("<a href=\"https://matrix.to/#/");
    html.push_str(&id);
    html.push_str("\" data-mention-type=\"");
    html.push_str(kind);
    html.push_str("\" data-id=\"");
    html.push_str(&id);
    html.push('"');
    if let Some(alias) = alias {
        html.push_str(" data-alias=\"");
        html.push_str(&escape_html(alias));
        html.push('"');
    }
    html.push('>');
    html.push_str(&escape_html(label));
    html.push_str("</a>");
}

fn parts_of_html(html: &str) -> Vec<MessagePart> {
    let document = Html::parse(html);
    let mut parts = Vec::new();
    for child in document.children() {
        read_node(&child, &mut parts);
    }
    parts
}

fn read_node(node: &NodeRef, parts: &mut Vec<MessagePart>) {
    if let Some(text) = node.as_text() {
        push_text(parts, &text.borrow());
        return;
    }
    let Some(element) = node.as_element() else {
        for child in node.children() {
            read_node(&child, parts);
        }
        return;
    };
    match &*element.name.local {
        "br" => push_text(parts, "\n"),
        "a" => {
            let attrs = element.attrs.borrow();
            let attr = |name: &str| {
                attrs
                    .iter()
                    .find(|attr| &*attr.name.local == name)
                    .map(|attr| attr.value.to_string())
            };
            let label: String = node
                .children()
                .filter_map(|child| child.as_text().map(|text| text.borrow().to_string()))
                .collect();
            let pill = match (attr("data-mention-type").as_deref(), attr("data-id")) {
                (Some("user"), Some(user_id)) => Some(MessagePart::User {
                    user_id,
                    name: label.clone(),
                }),
                (Some("room"), Some(room_id)) => Some(MessagePart::Room {
                    room_id,
                    alias: attr("data-alias"),
                    name: label.clone(),
                }),
                (Some("at-room"), _) => Some(MessagePart::AtRoom),
                _ => None,
            };
            match pill {
                Some(pill) => parts.push(pill),
                None => push_text(parts, &label),
            }
        }
        _ => {
            for child in node.children() {
                read_node(&child, parts);
            }
        }
    }
}

/// Adds `text`, joined to the text before it.
fn push_text(parts: &mut Vec<MessagePart>, text: &str) {
    if text.is_empty() {
        return;
    }
    if let Some(MessagePart::Text { text: last }) = parts.last_mut() {
        last.push_str(text);
    } else {
        parts.push(MessagePart::Text {
            text: text.to_owned(),
        });
    }
}

fn first_line(text: &str) -> Option<String> {
    text.lines()
        .map(str::trim)
        .find(|line| !line.is_empty())
        .map(str::to_owned)
}

fn escape_html(text: &str) -> String {
    let mut escaped = String::with_capacity(text.len());
    for c in text.chars() {
        match c {
            '&' => escaped.push_str("&amp;"),
            '<' => escaped.push_str("&lt;"),
            '>' => escaped.push_str("&gt;"),
            '"' => escaped.push_str("&quot;"),
            c => escaped.push(c),
        }
    }
    escaped
}

#[cfg(test)]
mod tests {
    use matrix_sdk::{
        Client,
        ruma::{owned_event_id, room_id},
        test_utils::mocks::MatrixMockServer,
    };

    use super::*;

    type TestResult = Result<(), Box<dyn std::error::Error>>;

    fn text(text: &str) -> MessagePart {
        MessagePart::Text {
            text: text.to_owned(),
        }
    }

    fn rich_draft() -> Draft {
        Draft {
            parts: vec![
                text("hi "),
                MessagePart::User {
                    user_id: "@bob:example.org".to_owned(),
                    name: "Bob <B&B>".to_owned(),
                },
                text(" see\n"),
                MessagePart::Room {
                    room_id: "!team:example.org".to_owned(),
                    alias: Some("#team:example.org".to_owned()),
                    name: "Team".to_owned(),
                },
                text(" and "),
                MessagePart::Room {
                    room_id: "!other:example.org".to_owned(),
                    alias: None,
                    name: "Other \"room\"".to_owned(),
                },
                text(", "),
                MessagePart::AtRoom,
                text(" "),
            ],
            kind: DraftKind::Reply {
                event_id: "$answered:example.org".to_owned(),
            },
        }
    }

    #[test]
    fn a_draft_with_pills_comes_back_as_it_was() -> TestResult {
        let draft = rich_draft();
        let stored = composer_draft(&draft).ok_or("the draft has text")?;
        assert_eq!(
            stored.plain_text,
            "hi Bob <B&B> see\n#team:example.org and Other \"room\", @room "
        );
        let html = stored.html_text.as_deref().ok_or("pills make HTML")?;
        assert!(html.contains("data-id=\"@bob:example.org\">Bob &lt;B&amp;B&gt;</a>"));
        assert!(html.contains("<br>"));
        assert_eq!(
            stored.draft_type,
            ComposerDraftType::Reply {
                event_id: owned_event_id!("$answered:example.org")
            }
        );
        assert_eq!(draft_of(&stored), draft);
        Ok(())
    }

    #[test]
    fn plain_text_has_no_html_and_white_space_is_no_draft() -> TestResult {
        let draft = Draft {
            parts: vec![text("  two\nlines  ")],
            kind: DraftKind::Edit {
                event_id: "$mine:example.org".to_owned(),
            },
        };
        let stored = composer_draft(&draft).ok_or("the draft has text")?;
        assert_eq!(stored.html_text, None);
        assert_eq!(stored.plain_text, "  two\nlines  ");
        assert_eq!(draft_of(&stored), draft);
        let blank = Draft {
            parts: vec![text(" \n ")],
            kind: DraftKind::NewMessage,
        };
        assert_eq!(composer_draft(&blank), None);
        let nothing = Draft {
            parts: Vec::new(),
            kind: DraftKind::NewMessage,
        };
        assert_eq!(composer_draft(&nothing), None);
        Ok(())
    }

    #[test]
    fn a_draft_from_another_client_comes_back_as_text() {
        let stored = ComposerDraft {
            plain_text: "hello Bob".to_owned(),
            html_text: Some("<strong>hello</strong> Bob".to_owned()),
            draft_type: ComposerDraftType::NewMessage,
            attachments: Vec::new(),
        };
        assert_eq!(draft_of(&stored).parts, vec![text("hello Bob")]);
    }

    #[test]
    fn the_preview_is_the_first_line_with_text() {
        assert_eq!(
            first_line("\n  \n  hello \nworld"),
            Some("hello".to_owned())
        );
        assert_eq!(first_line(" \n "), None);
    }

    async fn client_with_store(server: &MatrixMockServer, dir: &std::path::Path) -> Client {
        server
            .client_builder()
            .on_builder(|builder| builder.sqlite_store(dir, Some("store passphrase")))
            .build()
            .await
    }

    /// Room and thread drafts are kept apart, keep their kind, and survive closing and
    /// reopening the encrypted store, as on an app restart.
    #[tokio::test(flavor = "multi_thread")]
    async fn drafts_are_kept_per_room_and_thread_across_a_restart() -> TestResult {
        crate::api::init_app();
        let server = MatrixMockServer::new().await;
        let store = tempfile::tempdir()?;
        let room_a = room_id!("!a:example.org");
        let room_b = room_id!("!b:example.org");
        let root = owned_event_id!("$root:example.org");

        let client = client_with_store(&server, store.path()).await;
        let a = server.sync_joined_room(&client, room_a).await;
        let b = server.sync_joined_room(&client, room_b).await;
        assert_eq!(load(&a, None).await, Ok(None));

        let room_draft = rich_draft();
        let thread_draft = Draft {
            parts: vec![text("in the thread")],
            kind: DraftKind::Edit {
                event_id: "$mine:example.org".to_owned(),
            },
        };
        let other_draft = Draft {
            parts: vec![text("for B")],
            kind: DraftKind::NewMessage,
        };
        save(&a, None, &room_draft).await?;
        save(&a, Some(&root), &thread_draft).await?;
        save(&b, None, &other_draft).await?;

        assert_eq!(load(&a, None).await, Ok(Some(room_draft.clone())));
        assert_eq!(load(&a, Some(&root)).await, Ok(Some(thread_draft.clone())));
        assert_eq!(load(&b, None).await, Ok(Some(other_draft.clone())));
        assert_eq!(load(&b, Some(&root)).await, Ok(None));
        drop((a, b));
        drop(client);

        // The same store opened again.
        let client = client_with_store(&server, store.path()).await;
        let a = match client.get_room(room_a) {
            Some(known) => known,
            None => server.sync_joined_room(&client, room_a).await,
        };
        assert_eq!(load(&a, None).await, Ok(Some(room_draft)));
        assert_eq!(load(&a, Some(&root)).await, Ok(Some(thread_draft.clone())));

        // Clearing the room's draft leaves the thread's.
        clear(&a, None).await?;
        assert_eq!(load(&a, None).await, Ok(None));
        assert_eq!(load(&a, Some(&root)).await, Ok(Some(thread_draft)));

        // Saving an emptied composer removes the thread's draft.
        let emptied = Draft {
            parts: vec![text("   ")],
            kind: DraftKind::NewMessage,
        };
        save(&a, Some(&root), &emptied).await?;
        assert_eq!(load(&a, Some(&root)).await, Ok(None));
        Ok(())
    }
}
