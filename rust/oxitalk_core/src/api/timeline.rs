//! A room's timeline: its events oldest first, delivered as batches of diffs, plus paging back
//! and sending.

use std::{
    collections::HashSet,
    sync::{Arc, Mutex, PoisonError},
};

use flutter_rust_bridge::frb;
use futures_util::StreamExt;
use matrix_sdk::{
    attachment::{AttachmentInfo, BaseImageInfo},
    room::edit::EditedContent,
    ruma::{
        OwnedEventId, OwnedRoomId, UInt, UserId,
        api::client::receipt::create_receipt::v3::ReceiptType,
        events::room::{
            MediaSource,
            message::{
                FormattedBody, MessageFormat, MessageType, RoomMessageEventContent,
                RoomMessageEventContentWithoutRelation, TextMessageEventContent,
            },
        },
    },
};
use matrix_sdk_ui::{
    eyeball_im::VectorDiff,
    timeline::{
        self, AttachmentConfig, AttachmentSource, EventSendState, EventTimelineItem,
        InReplyToDetails, RoomExt, SendTarget, TimelineDetails, TimelineEventItemId,
        TimelineItemKind, VirtualTimelineItem,
    },
};
use tokio::task::AbortHandle;

use super::{
    error::{CoreError, parse_id},
    media_prep::prepare_image,
    rich_text::{RichBlock, plain_line, rich_text},
    session::Session,
};
use crate::frb_generated::StreamSink;

/// An open room timeline. Dropping it stops its stream.
#[frb(opaque)]
#[derive(Debug)]
pub struct Timeline {
    inner: Arc<timeline::Timeline>,
    tasks: Mutex<Vec<AbortHandle>>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TimelineItem {
    /// Stable for the item's life in this timeline, also across a local echo turning into the
    /// sent event.
    pub id: String,
    pub content: TimelineItemContent,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TimelineItemContent {
    /// A text message (for other message types without a file, their fallback body), and
    /// its formatting if it has any.
    Message {
        event: EventInfo,
        body: String,
        formatted: Option<Vec<RichBlock>>,
    },
    /// An image, video, audio or other file.
    Media {
        event: EventInfo,
        media: MediaMessage,
    },
    /// An encrypted event whose key hasn't arrived (yet).
    UnableToDecrypt { event: EventInfo },
    /// A message that was deleted.
    Redacted { event: EventInfo },
    /// Any other event; M0 doesn't show them.
    OtherEvent { event: EventInfo },
    /// The start of a day, in milliseconds since the Unix epoch.
    DateDivider { timestamp_ms: i64 },
    /// Where the user stopped reading.
    ReadMarker,
    /// Nothing older exists.
    TimelineStart,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EventInfo {
    /// `None` until the server has accepted a local echo.
    pub event_id: Option<String>,
    /// A local echo's ID until then. The event ID, or else this, names the event in the
    /// timeline's actions.
    pub transaction_id: Option<String>,
    pub sender: String,
    pub sender_name: Option<String>,
    /// An `mxc://` URI.
    pub sender_avatar_url: Option<String>,
    pub timestamp_ms: i64,
    pub is_own: bool,
    pub send_state: SendState,
    /// While an attachment uploads: how far, from 0 to 100.
    pub upload_percent: Option<u32>,
    /// The reactions, in the order they were first given.
    pub reactions: Vec<Reaction>,
    /// The message this one answers.
    pub in_reply_to: Option<ReplyQuote>,
    pub is_edited: bool,
    /// Whether the user can edit it: their own text message or caption.
    pub is_editable: bool,
}

/// One emoji (or other key) given to a message, by whom.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Reaction {
    pub key: String,
    /// The user IDs, first given first.
    pub senders: Vec<String>,
    /// Whether the user is among them.
    pub mine: bool,
}

/// What a reply shows of the message it answers.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ReplyQuote {
    pub event_id: String,
    /// `None` until the original is loaded.
    pub sender: Option<String>,
    pub sender_name: Option<String>,
    /// The original's text, or a file's name; `None` until loaded.
    pub text: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MediaKind {
    Image,
    Video,
    Audio,
    File,
}

/// A file in a message. [`Session::media_content`] and [`Session::media_thumbnail`] fetch it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MediaMessage {
    pub kind: MediaKind,
    /// Where the file is (and its key, in an encrypted room), as JSON to hand back to the core.
    pub source: String,
    /// The same for a thumbnail the sender attached, if any.
    pub thumbnail: Option<String>,
    pub filename: String,
    /// Text the sender wrote with the file.
    pub caption: Option<String>,
    /// The caption's formatting, if it has any.
    pub formatted_caption: Option<Vec<RichBlock>>,
    pub mime_type: Option<String>,
    /// In bytes.
    pub size: Option<i64>,
    pub width: Option<u32>,
    pub height: Option<u32>,
    pub duration_ms: Option<i64>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SendState {
    Sending,
    Sent,
    Failed,
}

/// One change to the timeline. Indexes refer to the list as it is when the diff is applied;
/// the diffs in a batch are applied in order.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TimelineDiff {
    Append { values: Vec<TimelineItem> },
    Clear,
    PushFront { value: TimelineItem },
    PushBack { value: TimelineItem },
    PopFront,
    PopBack,
    Insert { index: u32, value: TimelineItem },
    Set { index: u32, value: TimelineItem },
    Remove { index: u32 },
    Truncate { length: u32 },
    Reset { values: Vec<TimelineItem> },
}

impl Session {
    /// Opens the timeline of a room the user is in.
    ///
    /// # Errors
    ///
    /// [`CoreError::InvalidId`], or [`CoreError::RoomNotFound`] for a room the session doesn't
    /// know.
    pub async fn timeline(&self, room_id: String) -> Result<Timeline, CoreError> {
        let id: OwnedRoomId = parse_id(&room_id)?;
        let room = self
            .client
            .get_room(&id)
            .ok_or(CoreError::RoomNotFound { room_id })?;
        Ok(Timeline::new(
            Arc::new(room.timeline().await?),
            Mutex::default(),
        ))
    }
}

impl Timeline {
    /// The room of this timeline.
    pub(crate) fn room(&self) -> &matrix_sdk::Room {
        self.inner.room()
    }

    pub(crate) fn new(inner: Arc<timeline::Timeline>, tasks: Mutex<Vec<AbortHandle>>) -> Self {
        Self { inner, tasks }
    }

    /// Sends the items as batches of diffs. The first batch is a `Reset` with every item
    /// loaded so far.
    pub async fn subscribe_items(&self, sink: StreamSink<Vec<TimelineDiff>>) {
        self.item_updates(move |batch| sink.add(batch).is_ok())
            .await;
    }

    /// Like [`Self::subscribe_items`], for Rust callers: `emit` gets each batch and returns
    /// `false` to stop.
    #[frb(ignore)]
    pub async fn item_updates(&self, emit: impl Fn(Vec<TimelineDiff>) -> bool + Send + 'static) {
        let (items, stream) = self.inner.subscribe().await;
        let own = self.inner.room().own_user_id().to_owned();
        let inner = self.inner.clone();
        let mut fetching = HashSet::new();
        fetch_missing_replies(&inner, items.iter(), &mut fetching);
        let first = vec![TimelineDiff::Reset {
            values: items.iter().map(|i| item(i, &own)).collect(),
        }];
        let handle = tokio::spawn(async move {
            if !emit(first) {
                return;
            }
            let mut stream = Box::pin(stream);
            while let Some(diffs) = stream.next().await {
                for diff in &diffs {
                    match diff {
                        VectorDiff::Append { values } | VectorDiff::Reset { values } => {
                            fetch_missing_replies(&inner, values.iter(), &mut fetching);
                        }
                        VectorDiff::PushFront { value }
                        | VectorDiff::PushBack { value }
                        | VectorDiff::Insert { value, .. }
                        | VectorDiff::Set { value, .. } => {
                            fetch_missing_replies(&inner, [value], &mut fetching);
                        }
                        _ => {}
                    }
                }
                if !emit(diffs.into_iter().map(|d| timeline_diff(d, &own)).collect()) {
                    break;
                }
            }
        })
        .abort_handle();
        let mut tasks = self.tasks.lock().unwrap_or_else(PoisonError::into_inner);
        tasks.retain(|task| !task.is_finished());
        tasks.push(handle);
    }

    /// Loads up to `count` older events. Returns `true` once the start of the room is reached.
    ///
    /// # Errors
    ///
    /// As the server answers.
    pub async fn paginate_back(&self, count: u16) -> Result<bool, CoreError> {
        Ok(self.inner.paginate_backwards(count).await?)
    }

    /// Marks the room read up to its latest event: a read receipt, which the room's other
    /// members see, and the read marker, which the user's other devices go by. Nothing is
    /// sent when both are there already.
    ///
    /// # Errors
    ///
    /// As the server answers.
    pub async fn mark_as_read(&self) -> Result<(), CoreError> {
        self.inner.mark_as_read(ReceiptType::Read).await?;
        self.inner.mark_as_read(ReceiptType::FullyRead).await?;
        Ok(())
    }

    /// Queues a plain-text message. It shows at once as a local echo in [`SendState::Sending`];
    /// the room is encrypted transparently if it is an encrypted room.
    ///
    /// # Errors
    ///
    /// Only if the message can't be queued; a failed send shows as [`SendState::Failed`].
    pub async fn send_text(&self, body: String, markdown: bool) -> Result<(), CoreError> {
        let content = if markdown {
            RoomMessageEventContent::text_markdown(body)
        } else {
            RoomMessageEventContent::text_plain(body)
        };
        self.inner.send(content.into()).await?;
        Ok(())
    }

    /// Sends a plain-text reply to the event `reply_to`.
    ///
    /// # Errors
    ///
    /// [`CoreError::InvalidId`], or if the reply can't be queued.
    pub async fn send_reply(
        &self,
        body: String,
        reply_to: String,
        markdown: bool,
    ) -> Result<(), CoreError> {
        let reply_to: OwnedEventId = parse_id(&reply_to)?;
        self.inner
            .send_reply(text_content(body, markdown), reply_to)
            .await?;
        Ok(())
    }

    /// Gives the item the user's reaction `key` (an emoji), or takes it back if they gave it
    /// already. `item` is an event ID, or a local echo's transaction ID.
    ///
    /// # Errors
    ///
    /// If the item isn't in the timeline, or the reaction can't be queued.
    pub async fn toggle_reaction(&self, item: String, key: String) -> Result<(), CoreError> {
        self.inner.toggle_reaction(&item_id(&item)?, &key).await?;
        Ok(())
    }

    /// Replaces the text of the user's message, or with `caption` the caption of their file
    /// (an empty one removes it).
    ///
    /// # Errors
    ///
    /// If the item isn't the user's or isn't in the timeline.
    pub async fn edit(
        &self,
        item: String,
        body: String,
        caption: bool,
        markdown: bool,
    ) -> Result<(), CoreError> {
        let content = if caption {
            EditedContent::MediaCaption {
                formatted_caption: markdown.then(|| FormattedBody::markdown(&body)).flatten(),
                caption: (!body.is_empty()).then_some(body),
                mentions: None,
            }
        } else {
            EditedContent::RoomMessage(text_content(body, markdown))
        };
        self.inner.edit(&item_id(&item)?, content).await?;
        Ok(())
    }

    /// Deletes the item for everyone; a local echo is just not sent.
    ///
    /// # Errors
    ///
    /// If the item isn't in the timeline, or the user may not delete it.
    pub async fn redact(&self, item: String, reason: Option<String>) -> Result<(), CoreError> {
        self.inner
            .redact(&item_id(&item)?, reason.as_deref())
            .await?;
        Ok(())
    }

    /// Sends a local echo whose sending failed once more.
    ///
    /// # Errors
    ///
    /// If the item isn't in the timeline.
    pub async fn retry_send(&self, item: String) -> Result<(), CoreError> {
        self.inner
            .retry_send(&item_id(&item)?, SendTarget::Event)
            .await?;
        Ok(())
    }

    /// Whether the user may delete other people's messages here (a moderator's right).
    pub async fn can_redact_others(&self) -> bool {
        let room = self.inner.room();
        room.power_levels()
            .await
            .is_ok_and(|levels| levels.user_can_redact_event_of_other(room.own_user_id()))
    }

    /// Sends the file at `path` with an optional caption; see [`Self::send_data`].
    ///
    /// # Errors
    ///
    /// [`CoreError::Internal`] if the file can't be read, otherwise as [`Self::send_data`].
    pub async fn send_file(
        &self,
        path: String,
        mime_type: String,
        caption: Option<String>,
        compress: bool,
        markdown: bool,
    ) -> Result<(), CoreError> {
        let data = std::fs::read(&path).map_err(|error| CoreError::internal(&error))?;
        let filename = std::path::Path::new(&path).file_name().map_or_else(
            || "file".to_owned(),
            |name| name.to_string_lossy().into_owned(),
        );
        self.send_data(data, filename, mime_type, caption, compress, markdown)
            .await
    }

    /// Sends `data` as a file named `filename` of type `mime_type`, with an optional caption.
    /// It shows at once as a local echo with its upload progress, and is encrypted in an
    /// encrypted room. An image is sent with its size; with `compress`, a big photo is
    /// scaled to 2048 pixels and sent as JPEG.
    ///
    /// # Errors
    ///
    /// [`CoreError::Internal`] for a malformed `mime_type`, or if it can't be queued.
    pub async fn send_data(
        &self,
        data: Vec<u8>,
        filename: String,
        mime_type: String,
        caption: Option<String>,
        compress: bool,
        markdown: bool,
    ) -> Result<(), CoreError> {
        let mut config = AttachmentConfig {
            caption: caption
                .filter(|caption| !caption.is_empty())
                .map(|caption| {
                    if markdown {
                        TextMessageEventContent::markdown(caption)
                    } else {
                        TextMessageEventContent::plain(caption)
                    }
                }),
            ..AttachmentConfig::default()
        };
        let (data, filename, mime_type) = if mime_type.starts_with("image/") {
            let image = prepare_image(data, filename, mime_type, compress);
            config.info = Some(AttachmentInfo::Image(BaseImageInfo {
                width: image.width.map(UInt::from),
                height: image.height.map(UInt::from),
                size: UInt::new(image.data.len() as u64),
                blurhash: None,
                is_animated: None,
            }));
            (image.data, image.filename, image.mime_type)
        } else {
            (data, filename, mime_type)
        };
        let mime_type: mime::Mime = mime_type
            .parse()
            .map_err(|error| CoreError::internal(&error))?;
        self.inner
            .send_attachment(
                AttachmentSource::Data {
                    bytes: data,
                    filename,
                },
                mime_type,
                config,
            )
            .use_send_queue()
            .await?;
        Ok(())
    }

    /// Sends the message `item` (an event ID) again in the user's room `to_room`, as it is
    /// now (after edits), without what it answered; a file is sent again without uploading.
    ///
    /// # Errors
    ///
    /// [`CoreError::InvalidId`], [`CoreError::RoomNotFound`], [`CoreError::Internal`] if the
    /// item isn't a loaded message, or if it can't be queued.
    pub async fn forward(&self, item: String, to_room: String) -> Result<(), CoreError> {
        let event_id: OwnedEventId = parse_id(&item)?;
        let to_id: OwnedRoomId = parse_id(&to_room)?;
        let event = self
            .inner
            .item_by_event_id(&event_id)
            .await
            .ok_or_else(|| CoreError::internal(&"the message isn't loaded"))?;
        let msgtype = event
            .content()
            .as_message()
            .ok_or_else(|| CoreError::internal(&"not a message"))?
            .msgtype()
            .clone();
        let room = self
            .inner
            .room()
            .client()
            .get_room(&to_id)
            .ok_or(CoreError::RoomNotFound { room_id: to_room })?;
        room.send_queue()
            .send(RoomMessageEventContent::new(msgtype).into())
            .await
            .map_err(|error| CoreError::internal(&error))?;
        Ok(())
    }
}

impl Drop for Timeline {
    fn drop(&mut self) {
        let tasks = self.tasks.get_mut().unwrap_or_else(PoisonError::into_inner);
        for task in tasks.drain(..) {
            task.abort();
        }
    }
}

/// Asks the server for the originals of replies that show without them; each once.
fn fetch_missing_replies<'a>(
    timeline: &Arc<timeline::Timeline>,
    items: impl IntoIterator<Item = &'a Arc<timeline::TimelineItem>>,
    fetching: &mut HashSet<OwnedEventId>,
) {
    for event in items.into_iter().filter_map(|item| item.as_event()) {
        let missing = event
            .content()
            .in_reply_to()
            .is_some_and(|reply| matches!(reply.event, TimelineDetails::Unavailable));
        if let (true, Some(id)) = (missing, event.event_id())
            && fetching.insert(id.to_owned())
        {
            let timeline = timeline.clone();
            let id = id.to_owned();
            // A failure leaves the quote without its text.
            tokio::spawn(async move {
                let _ = timeline.fetch_details_for_event(&id).await;
            });
        }
    }
}

fn timeline_diff(diff: VectorDiff<Arc<timeline::TimelineItem>>, own: &UserId) -> TimelineDiff {
    let item = |value: &timeline::TimelineItem| item(value, own);
    let items = |values: matrix_sdk_ui::eyeball_im::Vector<Arc<timeline::TimelineItem>>| {
        values.iter().map(|i| item(i)).collect()
    };
    match diff {
        VectorDiff::Append { values } => TimelineDiff::Append {
            values: items(values),
        },
        VectorDiff::Clear => TimelineDiff::Clear,
        VectorDiff::PushFront { value } => TimelineDiff::PushFront {
            value: item(&value),
        },
        VectorDiff::PushBack { value } => TimelineDiff::PushBack {
            value: item(&value),
        },
        VectorDiff::PopFront => TimelineDiff::PopFront,
        VectorDiff::PopBack => TimelineDiff::PopBack,
        VectorDiff::Insert { index, value } => TimelineDiff::Insert {
            index: dart_int(index),
            value: item(&value),
        },
        VectorDiff::Set { index, value } => TimelineDiff::Set {
            index: dart_int(index),
            value: item(&value),
        },
        VectorDiff::Remove { index } => TimelineDiff::Remove {
            index: dart_int(index),
        },
        VectorDiff::Truncate { length } => TimelineDiff::Truncate {
            length: dart_int(length),
        },
        VectorDiff::Reset { values } => TimelineDiff::Reset {
            values: items(values),
        },
    }
}

/// A list index or length as a `u32`, which Dart gets as an `int` (a `usize` would be a
/// `BigInt`). No list comes near `u32::MAX`.
pub(crate) fn dart_int(value: usize) -> u32 {
    u32::try_from(value).unwrap_or(u32::MAX)
}

fn item(item: &timeline::TimelineItem, own: &UserId) -> TimelineItem {
    let content = match item.kind() {
        TimelineItemKind::Event(event) => event_content(event, own),
        TimelineItemKind::Virtual(VirtualTimelineItem::DateDivider(timestamp)) => {
            TimelineItemContent::DateDivider {
                timestamp_ms: timestamp.0.into(),
            }
        }
        TimelineItemKind::Virtual(VirtualTimelineItem::ReadMarker) => {
            TimelineItemContent::ReadMarker
        }
        TimelineItemKind::Virtual(VirtualTimelineItem::TimelineStart) => {
            TimelineItemContent::TimelineStart
        }
    };
    TimelineItem {
        id: item.unique_id().0.clone(),
        content,
    }
}

fn event_content(event: &EventTimelineItem, own: &UserId) -> TimelineItemContent {
    let content = event.content();
    let info = EventInfo {
        event_id: event.event_id().map(ToString::to_string),
        transaction_id: event.transaction_id().map(ToString::to_string),
        sender: event.sender().to_string(),
        sender_name: match event.sender_profile() {
            TimelineDetails::Ready(profile) => profile.display_name.clone(),
            _ => None,
        },
        sender_avatar_url: match event.sender_profile() {
            TimelineDetails::Ready(profile) => profile.avatar_url.as_ref().map(ToString::to_string),
            _ => None,
        },
        timestamp_ms: event.timestamp().0.into(),
        is_own: event.is_own(),
        send_state: match event.send_state() {
            Some(EventSendState::NotSentYet { .. }) => SendState::Sending,
            Some(EventSendState::SendingFailed { .. }) => SendState::Failed,
            Some(EventSendState::Sent { .. }) | None => SendState::Sent,
        },
        upload_percent: match event.send_state() {
            Some(EventSendState::NotSentYet {
                progress: Some(progress),
            }) if progress.progress.total > 0 => Some(
                u32::try_from(progress.progress.current * 100 / progress.progress.total)
                    .unwrap_or(100),
            ),
            _ => None,
        },
        reactions: event
            .reactions()
            .iter()
            .map(|(key, senders)| Reaction {
                key: key.clone(),
                senders: senders.keys().map(ToString::to_string).collect(),
                mine: senders.contains_key(own),
            })
            .collect(),
        in_reply_to: content.in_reply_to().map(|reply| reply_quote(&reply)),
        is_edited: content
            .as_message()
            .is_some_and(timeline::Message::is_edited),
        is_editable: event.is_editable(),
    };
    if content.is_redacted() {
        TimelineItemContent::Redacted { event: info }
    } else if let Some(media) = content
        .as_message()
        .and_then(|m| media_message(m.msgtype()))
    {
        TimelineItemContent::Media { event: info, media }
    } else if let Some(message) = content.as_message() {
        TimelineItemContent::Message {
            event: info,
            body: message.body().to_owned(),
            formatted: formatted_text(message.msgtype()),
        }
    } else if content.is_unable_to_decrypt() {
        TimelineItemContent::UnableToDecrypt { event: info }
    } else {
        TimelineItemContent::OtherEvent { event: info }
    }
}

/// The file in a message, if it has one.
pub(crate) fn media_message(msgtype: &MessageType) -> Option<MediaMessage> {
    let media = |kind, source: &MediaSource, filename: &str, caption: Option<&str>| MediaMessage {
        kind,
        source: source_json(source),
        thumbnail: None,
        filename: filename.to_owned(),
        caption: caption.map(ToOwned::to_owned),
        formatted_caption: None,
        mime_type: None,
        size: None,
        width: None,
        height: None,
        duration_ms: None,
    };
    Some(match msgtype {
        MessageType::Image(image) => {
            let mut m = media(
                MediaKind::Image,
                &image.source,
                image.filename(),
                image.caption(),
            );
            m.formatted_caption = image.formatted_caption().and_then(rich_html);
            if let Some(info) = &image.info {
                m.thumbnail = info.thumbnail_source.as_ref().map(source_json);
                m.mime_type.clone_from(&info.mimetype);
                m.size = info.size.map(int);
                m.width = info.width.map(small);
                m.height = info.height.map(small);
            }
            m
        }
        MessageType::Video(video) => {
            let mut m = media(
                MediaKind::Video,
                &video.source,
                video.filename(),
                video.caption(),
            );
            m.formatted_caption = video.formatted_caption().and_then(rich_html);
            if let Some(info) = &video.info {
                m.thumbnail = info.thumbnail_source.as_ref().map(source_json);
                m.mime_type.clone_from(&info.mimetype);
                m.size = info.size.map(int);
                m.width = info.width.map(small);
                m.height = info.height.map(small);
                m.duration_ms = info.duration.map(millis);
            }
            m
        }
        MessageType::Audio(audio) => {
            let mut m = media(
                MediaKind::Audio,
                &audio.source,
                audio.filename(),
                audio.caption(),
            );
            m.formatted_caption = audio.formatted_caption().and_then(rich_html);
            if let Some(info) = &audio.info {
                m.mime_type.clone_from(&info.mimetype);
                m.size = info.size.map(int);
                m.duration_ms = info.duration.map(millis);
            }
            m
        }
        MessageType::File(file) => {
            let mut m = media(
                MediaKind::File,
                &file.source,
                file.filename(),
                file.caption(),
            );
            m.formatted_caption = file.formatted_caption().and_then(rich_html);
            if let Some(info) = &file.info {
                m.thumbnail = info.thumbnail_source.as_ref().map(source_json);
                m.mime_type.clone_from(&info.mimetype);
                m.size = info.size.map(int);
            }
            m
        }
        _ => return None,
    })
}

/// A message as one line of plain text, for the chat list: its formatted text (or a file's
/// formatted caption) without the markup, else its body.
pub(crate) fn preview_text(message: &timeline::Message) -> String {
    let blocks = formatted_text(message.msgtype())
        .or_else(|| media_message(message.msgtype()).and_then(|media| media.formatted_caption));
    match blocks {
        Some(blocks) => plain_line(&blocks),
        None => message.body().to_owned(),
    }
}

/// The formatting of a text, notice or emote message, if it has any.
fn formatted_text(msgtype: &MessageType) -> Option<Vec<RichBlock>> {
    match msgtype {
        MessageType::Text(text) => text.formatted.as_ref(),
        MessageType::Notice(notice) => notice.formatted.as_ref(),
        MessageType::Emote(emote) => emote.formatted.as_ref(),
        _ => None,
    }
    .and_then(rich_html)
}

/// The blocks of an HTML body; `None` for another format, or if nothing is left to show.
fn rich_html(formatted: &FormattedBody) -> Option<Vec<RichBlock>> {
    if formatted.format != MessageFormat::Html {
        return None;
    }
    Some(rich_text(&formatted.body)).filter(|blocks| !blocks.is_empty())
}

fn source_json(source: &MediaSource) -> String {
    // A media source is plain data; serializing it can't fail.
    serde_json::to_string(source).unwrap_or_default()
}

fn int(value: UInt) -> i64 {
    i64::from(value)
}

fn small(value: UInt) -> u32 {
    u32::try_from(u64::from(value)).unwrap_or(u32::MAX)
}

fn millis(duration: std::time::Duration) -> i64 {
    i64::try_from(duration.as_millis()).unwrap_or(i64::MAX)
}

fn reply_quote(reply: &InReplyToDetails) -> ReplyQuote {
    let mut quote = ReplyQuote {
        event_id: reply.event_id.to_string(),
        sender: None,
        sender_name: None,
        text: None,
    };
    if let TimelineDetails::Ready(original) = &reply.event {
        quote.sender = Some(original.sender.to_string());
        if let TimelineDetails::Ready(profile) = &original.sender_profile {
            quote.sender_name.clone_from(&profile.display_name);
        }
        quote.text = original.content.as_message().map(|message| {
            media_message(message.msgtype()).map_or_else(
                || message.body().to_owned(),
                |media| media.caption.unwrap_or(media.filename),
            )
        });
        if original.content.is_redacted() {
            quote.text = Some("Message deleted".to_owned());
        }
    }
    quote
}

/// An item named by its event ID (`$…`) or, while a local echo, its transaction ID.
fn item_id(id: &str) -> Result<TimelineEventItemId, CoreError> {
    if id.starts_with('$') {
        Ok(TimelineEventItemId::EventId(parse_id(id)?))
    } else {
        Ok(TimelineEventItemId::TransactionId(id.into()))
    }
}

/// A text message's content: from markdown (sent as HTML too, if it has any formatting), or
/// as typed.
fn text_content(body: String, markdown: bool) -> RoomMessageEventContentWithoutRelation {
    if markdown {
        RoomMessageEventContentWithoutRelation::text_markdown(body)
    } else {
        RoomMessageEventContentWithoutRelation::text_plain(body)
    }
}
