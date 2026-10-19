//! Room list sections, kept the way Element keeps them so both apps show the same: a room is in
//! a section by a room tag (`m.favourite`, `m.lowpriority`, or `element.io.section.<id>` for a
//! section the user made), and the user's sections and their order are Element settings in
//! the `im.vector.web.settings` account data.

use flutter_rust_bridge::frb;
use futures_util::{Stream, StreamExt, stream};
use matrix_sdk::{
    Client, Room,
    ruma::{
        OwnedRoomId,
        events::{
            AnyGlobalAccountDataEvent, GlobalAccountDataEventType, RoomAccountDataEvent,
            tag::{TagEventContent, TagInfo, TagName},
        },
        serde::Raw,
    },
};
use serde_json::{Map, Value};

use super::{
    error::{CoreError, parse_id},
    session::Session,
};
use crate::frb_generated::StreamSink;

/// The account data event with Element's account-wide settings.
const SETTINGS_EVENT_TYPE: &str = "im.vector.web.settings";
/// `{ "<tag>": { "tag": "<tag>", "name": "…", … } }`
const SECTION_DATA_KEY: &str = "RoomList.CustomSectionData";
/// The order of the sections that can move: the user's, People and Rooms.
const SECTION_ORDER_KEY: &str = "RoomList.OrderedCustomSections";
const CUSTOM_SECTION_PREFIX: &str = "element.io.section.";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CustomSection {
    /// `element.io.section.<id>`; the room tag of the rooms in it.
    pub tag: String,
    pub name: String,
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct SectionSettings {
    /// The sections the user made.
    pub sections: Vec<CustomSection>,
    /// The order of the sections that can move, as Element stores it: the user's section tags,
    /// `im.vector.fake.direct` for People and `chats` for Rooms. May name sections that no
    /// longer exist, or miss some.
    pub order: Vec<String>,
}

/// The tags of one room.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RoomTags {
    pub room_id: String,
    pub tags: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SectionsUpdate {
    Settings {
        settings: SectionSettings,
    },
    /// The tags of these rooms; other rooms keep theirs.
    Rooms {
        rooms: Vec<RoomTags>,
    },
}

impl Session {
    /// Sends the section settings and the tags of every room, then every change to either.
    pub async fn subscribe_sections(&self, sink: StreamSink<SectionsUpdate>) {
        let mut updates = self.sections_updates().await;
        self.spawn(async move {
            while let Some(update) = updates.next().await {
                if sink.add(update).is_err() {
                    break;
                }
            }
        });
    }

    /// Like [`Self::subscribe_sections`], for Rust callers.
    #[frb(ignore)]
    pub async fn sections_updates(
        &self,
    ) -> impl Stream<Item = SectionsUpdate> + Send + Unpin + 'static {
        let client = self.client.clone();
        // Subscribed before reading the store, so no change falls in between.
        let settings_handler = client.observe_events::<Raw<AnyGlobalAccountDataEvent>, ()>();
        let tags_handler = client.observe_events::<RoomAccountDataEvent<TagEventContent>, Room>();
        let settings_changes = settings_handler
            .subscribe()
            .filter_map(|(event, ())| async move {
                let event_type = event.get_field::<String>("type").ok().flatten();
                if event_type.as_deref() != Some(SETTINGS_EVENT_TYPE) {
                    return None;
                }
                let content = event.get_field::<Map<String, Value>>("content").ok()??;
                Some(SectionsUpdate::Settings {
                    settings: section_settings(&content),
                })
            });
        let tag_changes = tags_handler
            .subscribe()
            .map(|(event, room)| SectionsUpdate::Rooms {
                rooms: vec![RoomTags {
                    room_id: room.room_id().to_string(),
                    tags: event.content.tags.keys().map(ToString::to_string).collect(),
                }],
            });

        let mut rooms = Vec::new();
        for room in client.rooms() {
            // A store read error only loses the room's tags; it shows in its default section.
            let tags = room.tags().await.ok().flatten().unwrap_or_default();
            rooms.push(RoomTags {
                room_id: room.room_id().to_string(),
                tags: tags.keys().map(ToString::to_string).collect(),
            });
        }
        let first = vec![
            SectionsUpdate::Settings {
                settings: section_settings(&stored_settings(&client).await),
            },
            SectionsUpdate::Rooms { rooms },
        ];
        Box::pin(
            stream::iter(first).chain(
                stream::select(settings_changes, tag_changes)
                    // The subscribers only hold the handlers weakly; the stream keeps them.
                    .map(move |update| {
                        let _keep = (&settings_handler, &tags_handler);
                        update
                    }),
            ),
        )
    }

    /// Puts a room in the section with `tag` (`m.favourite`, `m.lowpriority` or a section the
    /// user made), or with `None` in its default section (People or Rooms). A room is in one
    /// section at a time; the one it was in is left.
    ///
    /// # Errors
    ///
    /// [`CoreError::InvalidId`] for a malformed room ID or a tag that isn't a section's,
    /// [`CoreError::RoomNotFound`], otherwise as the server answers.
    pub async fn set_room_section(
        &self,
        room_id: String,
        tag: Option<String>,
    ) -> Result<(), CoreError> {
        if let Some(tag) = &tag
            && !is_section_tag(tag)
        {
            return Err(CoreError::InvalidId { id: tag.clone() });
        }
        let id: OwnedRoomId = parse_id(&room_id)?;
        let room = self
            .client
            .get_room(&id)
            .ok_or(CoreError::RoomNotFound { room_id })?;
        let current = room
            .tags()
            .await
            .map_err(|error| CoreError::internal(&error))?;
        for old in current.unwrap_or_default().keys() {
            let name = old.to_string();
            if is_section_tag(&name) && Some(&name) != tag.as_ref() {
                room.remove_tag(old.clone()).await?;
            }
        }
        if let Some(tag) = tag {
            room.set_tag(TagName::from(tag.as_str()), TagInfo::new())
                .await?;
        }
        Ok(())
    }

    /// Saves the user's sections and their order, keeping every other Element setting and
    /// whatever else Element stores with a section.
    ///
    /// # Errors
    ///
    /// [`CoreError::InvalidId`] for a section tag without the `element.io.section.` prefix,
    /// otherwise as the server answers.
    pub async fn save_section_settings(&self, settings: SectionSettings) -> Result<(), CoreError> {
        if let Some(bad) = settings
            .sections
            .iter()
            .find(|section| !section.tag.starts_with(CUSTOM_SECTION_PREFIX))
        {
            return Err(CoreError::InvalidId {
                id: bad.tag.clone(),
            });
        }
        let mut content = stored_settings(&self.client).await;
        let old_data = match content.remove(SECTION_DATA_KEY) {
            Some(Value::Object(data)) => data,
            _ => Map::new(),
        };
        let mut data = Map::new();
        for section in settings.sections {
            let mut entry = match old_data.get(&section.tag) {
                Some(Value::Object(entry)) => entry.clone(),
                _ => Map::new(),
            };
            entry.insert("tag".to_owned(), Value::String(section.tag.clone()));
            entry.insert("name".to_owned(), Value::String(section.name));
            data.insert(section.tag, Value::Object(entry));
        }
        content.insert(SECTION_DATA_KEY.to_owned(), Value::Object(data));
        content.insert(
            SECTION_ORDER_KEY.to_owned(),
            Value::Array(settings.order.into_iter().map(Value::String).collect()),
        );
        let raw = Raw::from_json_string(Value::Object(content).to_string())
            .map_err(|error| CoreError::internal(&error))?;
        self.client
            .account()
            .set_account_data_raw(GlobalAccountDataEventType::from(SETTINGS_EVENT_TYPE), raw)
            .await?;
        Ok(())
    }
}

fn is_section_tag(tag: &str) -> bool {
    tag == "m.favourite" || tag == "m.lowpriority" || tag.starts_with(CUSTOM_SECTION_PREFIX)
}

/// Element's settings as the store has them; empty if there are none or they can't be read.
async fn stored_settings(client: &Client) -> Map<String, Value> {
    let raw = client
        .account()
        .account_data_raw(GlobalAccountDataEventType::from(SETTINGS_EVENT_TYPE))
        .await;
    match raw {
        Ok(Some(raw)) => serde_json::from_str(raw.json().get()).unwrap_or_default(),
        _ => Map::new(),
    }
}

/// The section settings in Element's settings, leaving out what Element would ignore too.
fn section_settings(content: &Map<String, Value>) -> SectionSettings {
    let mut sections = Vec::new();
    if let Some(Value::Object(data)) = content.get(SECTION_DATA_KEY) {
        for (key, entry) in data {
            let tag = entry.get("tag").and_then(Value::as_str);
            let name = entry.get("name").and_then(Value::as_str);
            if let (Some(tag), Some(name)) = (tag, name)
                && tag == key
                && tag.starts_with(CUSTOM_SECTION_PREFIX)
            {
                sections.push(CustomSection {
                    tag: tag.to_owned(),
                    name: name.to_owned(),
                });
            }
        }
    }
    let order = match content.get(SECTION_ORDER_KEY) {
        Some(Value::Array(order)) => order
            .iter()
            .filter_map(Value::as_str)
            .map(ToOwned::to_owned)
            .collect(),
        _ => Vec::new(),
    };
    SectionSettings { sections, order }
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::*;

    #[test]
    fn reads_elements_section_settings_and_skips_malformed_ones() {
        let content = json!({
            "RoomList.CustomSectionData": {
                "element.io.section.a": { "tag": "element.io.section.a", "name": "Acme", "spaceId": "home-space" },
                "element.io.section.b": { "tag": "element.io.section.other", "name": "Mismatch" },
                "element.io.section.c": { "tag": "element.io.section.c" },
                "u.work": { "tag": "u.work", "name": "Not a section" },
            },
            "RoomList.OrderedCustomSections": ["im.vector.fake.direct", "element.io.section.a", "chats", 7],
            "someOtherSetting": true,
        });
        let Value::Object(content) = content else {
            unreachable!()
        };
        assert_eq!(
            section_settings(&content),
            SectionSettings {
                sections: vec![CustomSection {
                    tag: "element.io.section.a".to_owned(),
                    name: "Acme".to_owned(),
                }],
                order: vec![
                    "im.vector.fake.direct".to_owned(),
                    "element.io.section.a".to_owned(),
                    "chats".to_owned(),
                ],
            }
        );
        assert_eq!(section_settings(&Map::new()), SectionSettings::default());
    }

    #[test]
    fn only_section_tags_are_section_tags() {
        assert!(is_section_tag("m.favourite"));
        assert!(is_section_tag("m.lowpriority"));
        assert!(is_section_tag("element.io.section.x"));
        assert!(!is_section_tag("u.work"));
        assert!(!is_section_tag("chats"));
    }
}
