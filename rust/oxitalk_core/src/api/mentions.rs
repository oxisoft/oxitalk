//! Messages with mentions: the composer's text and pills turned into a body with the names,
//! a `formatted_body` with `matrix.to` links (pills in every client), and the intentional
//! mentions (`m.mentions`) that decide who is notified. Also what the composer suggests: whether
//! the user may mention the whole room, and the rooms they can link to.

use std::collections::BTreeSet;

use flutter_rust_bridge::frb;
use matrix_sdk::{
    RoomState,
    room::edit::EditedContent,
    ruma::{
        OwnedEventId, OwnedRoomAliasId, OwnedRoomId, OwnedUserId, UserId,
        events::{
            Mentions,
            room::message::{
                FormattedBody, MessageType, RoomMessageEventContentWithoutRelation,
                TextMessageEventContent,
            },
        },
    },
};

use super::{
    error::{CoreError, parse_id},
    session::Session,
    timeline::Timeline,
};

/// A piece of what the user wrote: text as typed (markdown, when that is on), or a pill.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum MessagePart {
    Text {
        text: String,
    },
    /// A user, shown and sent by `name` (their display name), linked to their ID.
    User {
        user_id: String,
        name: String,
    },
    /// A room, shown by its address when it has one, else by `name`.
    Room {
        room_id: String,
        alias: Option<String>,
        name: String,
    },
    /// `@room`: notifies everyone in the room, if the user may.
    AtRoom,
}

/// A room the user is in, to link to with `#`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MentionRoom {
    pub room_id: String,
    pub name: String,
    /// Its main address, like `#team:example.org`.
    pub alias: Option<String>,
    /// An `mxc://` URI.
    pub avatar_url: Option<String>,
}

impl Timeline {
    /// Sends what the user wrote, with its pills as links and its mentions; with `reply_to` (an
    /// event ID) as a reply to it, which also mentions its sender. In a thread's timeline it goes
    /// into the thread. Always carries `m.mentions`, empty without pills, as Element X does: a
    /// name typed as plain text then notifies no one.
    ///
    /// # Errors
    ///
    /// [`CoreError::InvalidId`] for a malformed ID in `reply_to` or a pill, or if the message
    /// can't be queued.
    pub async fn send_message(
        &self,
        parts: Vec<MessagePart>,
        reply_to: Option<String>,
        markdown: bool,
    ) -> Result<(), CoreError> {
        let composed = compose(&parts, markdown, Some(self.room().own_user_id()))?;
        let content = composed.content();
        match reply_to {
            Some(reply_to) => {
                let reply_to: OwnedEventId = parse_id(&reply_to)?;
                self.inner().send_reply(content, reply_to).await?;
            }
            None => {
                self.inner()
                    .send(content.with_relation(None).into())
                    .await?;
            }
        }
        Ok(())
    }

    /// Replaces the text of the user's message (or with `caption` the caption of their file)
    /// with what they wrote; the mentions are replaced too, and only the newly mentioned are
    /// notified.
    ///
    /// # Errors
    ///
    /// [`CoreError::InvalidId`] for a malformed pill, or if the item isn't the user's or is a
    /// local echo no longer in the timeline.
    pub async fn edit_message(
        &self,
        item: String,
        parts: Vec<MessagePart>,
        caption: bool,
        markdown: bool,
    ) -> Result<(), CoreError> {
        let composed = compose(&parts, markdown, Some(self.room().own_user_id()))?;
        let content = if caption {
            EditedContent::MediaCaption {
                formatted_caption: composed.html.clone().map(FormattedBody::html),
                caption: (!composed.body.is_empty()).then(|| composed.body.clone()),
                mentions: Some(composed.mentions),
            }
        } else {
            EditedContent::RoomMessage(composed.content())
        };
        super::timeline::edit_item(self.inner(), &item, content).await
    }
}

impl Session {
    /// Whether the user may notify the whole room with `@room` (the room's
    /// `notifications.room` power level).
    pub async fn can_mention_room(&self, room_id: String) -> bool {
        let Ok(room) = self.room(&room_id) else {
            return false;
        };
        room.power_levels()
            .await
            .is_ok_and(|levels| levels.user_can_trigger_room_notification(room.own_user_id()))
    }

    /// The rooms the user is in, to link to with `#`, by name.
    #[frb(sync)]
    #[must_use]
    pub fn mention_rooms(&self) -> Vec<MentionRoom> {
        let mut rooms: Vec<MentionRoom> = self
            .client
            .rooms()
            .into_iter()
            .filter(|room| room.state() == RoomState::Joined)
            .map(|room| {
                let alias = room.canonical_alias().map(|alias| alias.to_string());
                let name = room
                    .cached_display_name()
                    .map(|name| name.to_string())
                    .or_else(|| room.name())
                    .or_else(|| alias.clone())
                    .unwrap_or_else(|| room.room_id().to_string());
                MentionRoom {
                    room_id: room.room_id().to_string(),
                    name,
                    alias,
                    avatar_url: room.avatar_url().map(|url| url.to_string()),
                }
            })
            .collect();
        rooms.sort_by_cached_key(|room| room.name.to_lowercase());
        rooms
    }
}

/// A message built from parts; internal to the core.
#[frb(ignore)]
#[derive(Debug, Clone)]
pub(crate) struct Composed {
    /// The plain text: the typed text with the pills' names.
    pub(crate) body: String,
    /// The HTML, if there is any formatting or a pill.
    pub(crate) html: Option<String>,
    pub(crate) mentions: Mentions,
}

impl Composed {
    fn content(&self) -> RoomMessageEventContentWithoutRelation {
        let text = match &self.html {
            Some(html) => TextMessageEventContent::html(self.body.clone(), html.clone()),
            None => TextMessageEventContent::plain(self.body.clone()),
        };
        RoomMessageEventContentWithoutRelation::new(MessageType::Text(text))
            .add_mentions(self.mentions.clone())
    }
}

/// What a pill links to and shows.
enum Pill {
    User { id: OwnedUserId, name: String },
    Room { link: String, label: String },
    AtRoom,
}

/// Builds the body, HTML and mentions of `parts`. With `markdown` the text is markdown (as
/// Element sends it) and the pills become markdown links in it; without, the text is escaped
/// and only the pills are HTML. `own` is never mentioned, as the specification asks.
pub(crate) fn compose(
    parts: &[MessagePart],
    markdown: bool,
    own: Option<&UserId>,
) -> Result<Composed, CoreError> {
    let mut body = String::new();
    // Markdown source, or HTML, as it is built.
    let mut source = String::new();
    let mut user_ids = BTreeSet::new();
    let mut room = false;
    let mut has_pill = false;
    for part in parts {
        let pill = match part {
            MessagePart::Text { text } => {
                body.push_str(text);
                if markdown {
                    source.push_str(text);
                } else {
                    source.push_str(&escape_html(text).replace('\n', "<br>"));
                }
                continue;
            }
            MessagePart::User { user_id, name } => Pill::User {
                id: parse_id(user_id.trim())?,
                name: name.clone(),
            },
            MessagePart::Room {
                room_id,
                alias,
                name,
            } => {
                if let Some(alias) = alias {
                    let alias: OwnedRoomAliasId = parse_id(alias.trim())?;
                    Pill::Room {
                        link: alias.matrix_to_uri().to_string(),
                        label: alias.to_string(),
                    }
                } else {
                    let id: OwnedRoomId = parse_id(room_id.trim())?;
                    Pill::Room {
                        link: id.matrix_to_uri().to_string(),
                        label: name.clone(),
                    }
                }
            }
            MessagePart::AtRoom => Pill::AtRoom,
        };
        match pill {
            Pill::User { id, name } => {
                let name = if name.trim().is_empty() {
                    id.to_string()
                } else {
                    name
                };
                body.push_str(&name);
                push_link(
                    &mut source,
                    &id.matrix_to_uri().to_string(),
                    &name,
                    markdown,
                );
                if own != Some(&*id) {
                    user_ids.insert(id);
                }
                has_pill = true;
            }
            Pill::Room { link, label } => {
                body.push_str(&label);
                push_link(&mut source, &link, &label, markdown);
                has_pill = true;
            }
            Pill::AtRoom => {
                body.push_str("@room");
                source.push_str("@room");
                room = true;
            }
        }
    }
    let html = if markdown {
        FormattedBody::markdown(&source).map(|formatted| formatted.body)
    } else {
        has_pill.then_some(source)
    };
    let mut mentions = Mentions::with_user_ids(user_ids);
    mentions.room = room;
    Ok(Composed {
        body,
        html,
        mentions,
    })
}

fn push_link(source: &mut String, link: &str, label: &str, markdown: bool) {
    if markdown {
        source.push('[');
        source.push_str(&escape_markdown(label));
        source.push_str("](");
        source.push_str(link);
        source.push(')');
    } else {
        source.push_str("<a href=\"");
        source.push_str(&escape_html(link));
        source.push_str("\">");
        source.push_str(&escape_html(label));
        source.push_str("</a>");
    }
}

/// `text` with every ASCII punctuation character backslash-escaped, so a name stays literal
/// text inside a markdown link.
fn escape_markdown(text: &str) -> String {
    let mut escaped = String::with_capacity(text.len());
    for c in text.chars() {
        if c.is_ascii_punctuation() {
            escaped.push('\\');
        }
        escaped.push(c);
    }
    escaped
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
    use matrix_sdk::ruma::{owned_user_id, user_id};

    use super::*;

    type TestResult = Result<(), Box<dyn std::error::Error>>;
    use crate::api::rich_text::rich_text;

    fn text(text: &str) -> MessagePart {
        MessagePart::Text {
            text: text.to_owned(),
        }
    }

    fn user(id: &str, name: &str) -> MessagePart {
        MessagePart::User {
            user_id: id.to_owned(),
            name: name.to_owned(),
        }
    }

    #[test]
    fn a_user_pill_is_a_link_with_the_name_and_a_mention() -> TestResult {
        let composed = compose(
            &[text("hi "), user("@bob:acme.com", "Bob"), text(", look")],
            false,
            None,
        )?;
        assert_eq!(composed.body, "hi Bob, look");
        assert_eq!(
            composed.html.as_deref(),
            Some("hi <a href=\"https://matrix.to/#/@bob:acme.com\">Bob</a>, look")
        );
        assert_eq!(
            composed.mentions.user_ids,
            [owned_user_id!("@bob:acme.com")].into()
        );
        assert!(!composed.mentions.room);
        Ok(())
    }

    #[test]
    fn with_markdown_the_pill_is_a_markdown_link_and_the_rest_formatted() -> TestResult {
        let composed = compose(
            &[
                text("**hey** "),
                user("@bob:acme.com", "B*o_b [x]"),
                text(" and "),
                user("@eve:acme.com", "Eve"),
            ],
            true,
            None,
        )?;
        assert_eq!(composed.body, "**hey** B*o_b [x] and Eve");
        let html = composed.html.ok_or("no HTML")?;
        assert!(html.contains("<strong>hey</strong>"), "{html}");
        assert!(
            html.contains("<a href=\"https://matrix.to/#/@bob:acme.com\">B*o_b [x]</a>"),
            "{html}"
        );
        assert!(
            html.contains("<a href=\"https://matrix.to/#/@eve:acme.com\">Eve</a>"),
            "{html}"
        );
        assert_eq!(composed.mentions.user_ids.len(), 2);
        // What the app shows for it: the pills as mentions with the names.
        let spans: Vec<_> = rich_text(&html)
            .into_iter()
            .flat_map(|block| block.spans)
            .filter_map(|span| Some((span.text, span.mention?)))
            .collect();
        assert_eq!(
            spans,
            [
                ("B*o_b [x]".to_owned(), "@bob:acme.com".to_owned()),
                ("Eve".to_owned(), "@eve:acme.com".to_owned()),
            ]
        );
        Ok(())
    }

    #[test]
    fn plain_text_is_escaped_and_keeps_its_lines() -> TestResult {
        let composed = compose(
            &[text("a < b & \"c\"\nnext "), user("@bob:acme.com", "<Bob>")],
            false,
            None,
        )?;
        assert_eq!(
            composed.html.as_deref(),
            Some(
                "a &lt; b &amp; &quot;c&quot;<br>next \
                 <a href=\"https://matrix.to/#/@bob:acme.com\">&lt;Bob&gt;</a>"
            )
        );
        Ok(())
    }

    #[test]
    fn without_pills_or_formatting_there_is_no_html_and_no_one_is_mentioned() -> TestResult {
        let composed = compose(&[text("just text")], true, None)?;
        assert_eq!(composed.body, "just text");
        assert_eq!(composed.html, None);
        assert!(composed.mentions.user_ids.is_empty() && !composed.mentions.room);
        let plain = compose(&[text("just *text*")], false, None)?;
        assert_eq!(plain.html, None);
        // Still sent, empty: intentional mentions.
        let content = plain.content();
        let json = serde_json::to_value(&content)?;
        assert_eq!(json["m.mentions"], serde_json::json!({}));
        Ok(())
    }

    #[test]
    fn at_room_mentions_the_room_as_plain_text() -> TestResult {
        let composed = compose(&[MessagePart::AtRoom, text(" meeting now")], false, None)?;
        assert_eq!(composed.body, "@room meeting now");
        assert_eq!(composed.html, None);
        assert!(composed.mentions.room);
        assert!(composed.mentions.user_ids.is_empty());
        Ok(())
    }

    #[test]
    fn a_room_pill_links_to_its_address_or_id() -> TestResult {
        let composed = compose(
            &[
                text("see "),
                MessagePart::Room {
                    room_id: "!abc:acme.com".to_owned(),
                    alias: Some("#team:acme.com".to_owned()),
                    name: "Team".to_owned(),
                },
                text(" or "),
                MessagePart::Room {
                    room_id: "!xyz:acme.com".to_owned(),
                    alias: None,
                    name: "Secret".to_owned(),
                },
            ],
            false,
            None,
        )?;
        assert_eq!(composed.body, "see #team:acme.com or Secret");
        let html = composed.html.ok_or("no HTML")?;
        assert!(
            html.contains("<a href=\"https://matrix.to/#/%23team:acme.com\">#team:acme.com</a>"),
            "{html}"
        );
        assert!(
            html.contains("<a href=\"https://matrix.to/#/!xyz:acme.com\">Secret</a>"),
            "{html}"
        );
        assert!(composed.mentions.user_ids.is_empty());
        Ok(())
    }

    #[test]
    fn the_user_is_not_mentioned_by_their_own_pill() -> TestResult {
        let composed = compose(
            &[
                user("@me:acme.com", "Me"),
                text(" "),
                user("@bob:acme.com", ""),
            ],
            false,
            Some(user_id!("@me:acme.com")),
        )?;
        // A pill without a name shows the ID.
        assert_eq!(composed.body, "Me @bob:acme.com");
        assert_eq!(
            composed.mentions.user_ids,
            [owned_user_id!("@bob:acme.com")].into()
        );
        assert!(!composed.mentions.room);
        Ok(())
    }

    #[test]
    fn a_malformed_pill_is_refused() {
        assert!(matches!(
            compose(&[user("bob", "Bob")], false, None),
            Err(CoreError::InvalidId { id }) if id == "bob"
        ));
    }
}
