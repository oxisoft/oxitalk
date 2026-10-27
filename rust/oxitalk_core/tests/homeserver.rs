//! Tests against a test homeserver in `test-infra/`, Synapse or Tuwunel (`OXITALK_TEST_HOMESERVER`).
//! They are ignored by a plain `cargo test`; `scripts/ci.sh` starts both servers and runs them
//! with `--ignored` on each.

// The futures of matrix-sdk-ui (the timeline in particular) are deeply nested.
#![recursion_limit = "256"]

#[path = "homeserver/devices.rs"]
mod devices;
#[path = "homeserver/drafts.rs"]
mod drafts;
#[path = "homeserver/membership.rs"]
mod membership;
#[path = "homeserver/mentions.rs"]
mod mentions;
#[path = "homeserver/pins.rs"]
mod pins;
#[path = "homeserver/recovery.rs"]
mod recovery;
#[path = "homeserver/room_settings.rs"]
mod room_settings;
#[path = "homeserver/search.rs"]
mod search;
mod support;

use std::{
    error::Error,
    sync::Arc,
    time::{Duration, SystemTime, UNIX_EPOCH},
};

use futures_util::{Stream, StreamExt};

use matrix_sdk::{
    Client,
    attachment::{AttachmentConfig, AttachmentInfo, BaseFileInfo},
    notification_settings::{IsEncrypted, IsOneToOne},
    ruma::{
        OwnedDeviceId, OwnedEventId, OwnedRoomId, OwnedUserId,
        api::client::{
            account::register::v3::Request as RegistrationRequest,
            room::{
                Visibility,
                create_room::v3::{Request as CreateRoomRequest, RoomPreset},
            },
            uiaa,
        },
        events::{Mentions, room::message::RoomMessageEventContent},
        push::{AnyPushRuleRef, RuleKind},
        serde::Raw,
    },
};
use oxitalk_core::api::{
    error::CoreError,
    init_app,
    notifications::{InconsistentDefault, NotificationSettingsState, RoomNotificationMode},
    notify::NotificationItem,
    rich_text::BlockKind,
    room_info::{MemberRole, RoomMember},
    room_list::{Membership, RoomSummary},
    rooms::{NewRoom, RoomAvatar},
    sections::{CustomSection, RoomTags, SectionSettings, SectionsUpdate},
    session::{Session, login, restore},
    threads::ThreadSummary,
    timeline::{EventInfo, MediaKind, MediaMessage, SendState, TimelineItem, TimelineItemContent},
    verification::{Verification, VerificationFlowState, VerificationStatus},
    voice::{encode_voice, playable_wav},
};
use serde_json::json;
use support::{TIMEOUT, TestResult, messages, poll_until, watch_rooms, watch_timeline};
use tokio::sync::mpsc;

const PASSPHRASE: &str = "store passphrase";

/// A 64×64 PNG.
const AVATAR_PNG: &[u8] = include_bytes!("support/avatar.png");

/// `OXITALK_TEST_HOMESERVER`, or the port `test-infra/compose.yaml` publishes.
fn homeserver_url() -> String {
    std::env::var("OXITALK_TEST_HOMESERVER").unwrap_or_else(|_| "http://localhost:8008".to_owned())
}

/// A freshly registered user. Registration isn't part of the app; the test uses the SDK for it.
struct TestUser {
    name: String,
    password: String,
}

impl TestUser {
    async fn register() -> Result<Self, Box<dyn Error>> {
        init_app();
        // A name no earlier run has taken: the server keeps its data until `compose down -v`.
        let nanos = SystemTime::now().duration_since(UNIX_EPOCH)?.as_nanos();
        let name = format!("user{nanos}");
        let password = format!("{name}-password");

        let mut request = RegistrationRequest::new();
        request.username = Some(name.clone());
        request.password = Some(password.clone());
        request.auth = Some(uiaa::AuthData::Dummy(uiaa::Dummy::new()));
        // No device for the registration: the tests count the account's devices.
        request.inhibit_login = true;
        let client = Client::builder()
            .homeserver_url(homeserver_url())
            .build()
            .await?;
        client.matrix_auth().register(request).await?;
        Ok(Self { name, password })
    }

    async fn login(&self, store_dir: &str) -> Result<Session, CoreError> {
        login(
            homeserver_url(),
            self.name.clone(),
            self.password.clone(),
            store_dir.to_owned(),
            PASSPHRASE.to_owned(),
        )
        .await
    }
}

#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a test homeserver (test-infra/)"]
async fn logs_in_and_rejects_a_wrong_password() -> TestResult {
    let user = TestUser::register().await?;
    let store = tempfile::tempdir()?;

    let wrong = TestUser {
        name: user.name.clone(),
        password: "wrong".to_owned(),
    };
    let error = wrong.login(&store.path().to_string_lossy()).await.err();
    assert!(
        matches!(error, Some(CoreError::Forbidden { .. })),
        "{error:?}"
    );

    let session = user.login(&store.path().to_string_lossy()).await?;
    assert_eq!(session.user_id(), format!("@{}:localhost", user.name));
    Ok(())
}

/// The M0.3 exit test: an encrypted DM in both directions, then one side restarts on its store.
#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a test homeserver (test-infra/)"]
async fn encrypted_dm_both_ways_and_after_a_restore() -> TestResult {
    let (alice_user, bob_user) = (TestUser::register().await?, TestUser::register().await?);
    let (alice_store, bob_store) = (tempfile::tempdir()?, tempfile::tempdir()?);
    let bob_store_dir = bob_store.path().to_string_lossy().into_owned();
    let alice = alice_user
        .login(&alice_store.path().to_string_lossy())
        .await?;
    let bob = bob_user.login(&bob_store_dir).await?;
    alice.start_sync().await;
    bob.start_sync().await;

    // Alice opens a DM; Bob sees the invite and joins.
    let room_id = alice.create_dm(bob.user_id()).await?;
    let mut bob_rooms = watch_rooms(&bob).await?;
    bob_rooms
        .wait_until(|rooms| {
            rooms
                .iter()
                .any(|r| r.room_id == room_id && r.membership == Membership::Invited)
        })
        .await?;
    bob.join(room_id.clone()).await?;
    bob_rooms
        .wait_until(|rooms| {
            rooms.iter().any(|r| {
                r.room_id == room_id && r.membership == Membership::Joined && r.is_encrypted
            })
        })
        .await?;

    // Alice → Bob, Bob → Alice.
    let alice_timeline = alice.timeline(room_id.clone()).await?;
    let mut alice_items = watch_timeline(&alice_timeline).await;
    let bob_timeline = bob.timeline(room_id.clone()).await?;
    let mut bob_items = watch_timeline(&bob_timeline).await;

    alice_timeline
        .send_text("hello Bob".to_owned(), false)
        .await?;
    bob_items
        .wait_until(|items| messages(items).contains(&("hello Bob", false)))
        .await?;
    bob_timeline
        .send_text("hello Alice".to_owned(), false)
        .await?;
    alice_items
        .wait_until(|items| messages(items).contains(&("hello Alice", false)))
        .await?;
    alice_items
        .wait_until(|items| {
            items.iter().any(|item| {
                matches!(&item.content, TimelineItemContent::Message { event, body, .. }
                    if body == "hello Bob" && event.is_own && event.send_state == SendState::Sent)
            })
        })
        .await?;

    // Bob quits: the app keeps only the session data and its store.
    let bob_data = bob.session_data()?;
    bob.stop_sync().await;
    drop((bob_items, bob_timeline, bob_rooms, bob));

    let wrong = restore(bob_data.clone(), bob_store_dir.clone(), "wrong".to_owned()).await;
    assert_eq!(wrong.err(), Some(CoreError::WrongStorePassphrase));

    // Bob restarts: the old messages still decrypt, and new ones arrive.
    let bob = restore(bob_data, bob_store_dir, PASSPHRASE.to_owned()).await?;
    bob.start_sync().await;
    let bob_timeline = bob.timeline(room_id).await?;
    let mut bob_items = watch_timeline(&bob_timeline).await;
    bob_timeline.paginate_back(20).await?;
    bob_items
        .wait_until(|items| {
            let messages = messages(items);
            messages.contains(&("hello Bob", false)) && messages.contains(&("hello Alice", true))
        })
        .await?;

    alice_timeline
        .send_text("after the restart".to_owned(), false)
        .await?;
    bob_items
        .wait_until(|items| messages(items).contains(&("after the restart", false)))
        .await?;
    Ok(())
}

/// A new device of an account is verified by an existing one, comparing emoji.
/// A profile picture shows on the user's DM in the other side's room list and on their
/// messages, and downloads as a thumbnail.
#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a test homeserver (test-infra/)"]
async fn profile_pictures_show_on_dms_and_messages() -> TestResult {
    let (alice_user, bob_user) = (TestUser::register().await?, TestUser::register().await?);
    let (alice_store, bob_store) = (tempfile::tempdir()?, tempfile::tempdir()?);
    let alice = alice_user
        .login(&alice_store.path().to_string_lossy())
        .await?;
    let bob = bob_user.login(&bob_store.path().to_string_lossy()).await?;

    assert_eq!(alice.own_profile().await?.avatar_url, None);
    alice
        .set_avatar(AVATAR_PNG.to_vec(), "image/png".to_owned())
        .await?;
    let avatar = alice
        .own_profile()
        .await?
        .avatar_url
        .ok_or("no avatar after setting one")?;
    let thumbnail = bob.thumbnail(avatar.clone(), 64).await?;
    assert!(thumbnail.starts_with(b"\x89PNG") || thumbnail.starts_with(b"\xff\xd8"));
    assert!(matches!(
        bob.thumbnail("not an mxc".to_owned(), 64).await,
        Err(CoreError::InvalidId { .. })
    ));

    alice.start_sync().await;
    bob.start_sync().await;
    let room_id = alice.create_dm(bob.user_id()).await?;
    let mut bob_rooms = watch_rooms(&bob).await?;
    bob_rooms
        .wait_until(|rooms| rooms.iter().any(|r| r.room_id == room_id))
        .await?;
    bob.join(room_id.clone()).await?;
    bob_rooms
        .wait_until(|rooms| {
            rooms.iter().any(|r| {
                r.room_id == room_id
                    && r.membership == Membership::Joined
                    && r.avatar_url.as_ref() == Some(&avatar)
            })
        })
        .await?;

    let alice_timeline = alice.timeline(room_id.clone()).await?;
    alice_timeline
        .send_text("look at me".to_owned(), false)
        .await?;
    let bob_timeline = bob.timeline(room_id).await?;
    let mut bob_items = watch_timeline(&bob_timeline).await;
    bob_items
        .wait_until(|items| {
            items.iter().any(|item| {
                matches!(&item.content, TimelineItemContent::Message { event, body, .. }
                    if body == "look at me" && event.sender_avatar_url.as_ref() == Some(&avatar))
            })
        })
        .await?;

    alice.remove_avatar().await?;
    assert_eq!(alice.own_profile().await?.avatar_url, None);
    Ok(())
}

/// Sections as Element keeps them: a room moves between sections by its tags, one at a time,
/// and the user's sections are saved in Element's settings without losing the rest of them.
#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a test homeserver (test-infra/)"]
async fn rooms_move_between_sections_as_in_element() -> TestResult {
    const ACME: &str = "element.io.section.acme";
    let (alice_user, bob_user) = (TestUser::register().await?, TestUser::register().await?);
    let (alice_store, bob_store) = (tempfile::tempdir()?, tempfile::tempdir()?);
    let alice = alice_user
        .login(&alice_store.path().to_string_lossy())
        .await?;
    let bob = bob_user.login(&bob_store.path().to_string_lossy()).await?;

    // Element's settings already hold other things, and a section with more than a name.
    alice
        .sdk()
        .account()
        .set_account_data_raw(
            "im.vector.web.settings".into(),
            Raw::from_json_string(
                json!({
                    "someOtherSetting": true,
                    "RoomList.CustomSectionData": {
                        ACME: { "tag": ACME, "name": "Acme", "spaceId": "home-space" },
                    },
                })
                .to_string(),
            )?,
        )
        .await?;
    alice.start_sync().await;
    let room_id = alice.create_dm(bob.user_id()).await?;
    let mut sections = alice.sections_updates().await;
    let tags_of = |rooms: &[RoomTags]| {
        rooms
            .iter()
            .find(|room| room.room_id == room_id)
            .map(|room| room.tags.clone())
    };

    wait_for_sections(&mut sections, "the Acme section", |update| {
        matches!(update, SectionsUpdate::Settings { settings }
            if settings.sections.iter().any(|s| s.tag == ACME && s.name == "Acme"))
    })
    .await?;

    alice
        .set_room_section(room_id.clone(), Some("m.favourite".to_owned()))
        .await?;
    wait_for_sections(&mut sections, "the room in Favourites", |update| {
        matches!(update, SectionsUpdate::Rooms { rooms }
            if tags_of(rooms) == Some(vec!["m.favourite".to_owned()]))
    })
    .await?;
    alice
        .set_room_section(room_id.clone(), Some(ACME.to_owned()))
        .await?;
    wait_for_sections(&mut sections, "the room in Acme", |update| {
        matches!(update, SectionsUpdate::Rooms { rooms }
            if tags_of(rooms) == Some(vec![ACME.to_owned()]))
    })
    .await?;
    alice.set_room_section(room_id.clone(), None).await?;
    wait_for_sections(&mut sections, "the room in no section", |update| {
        matches!(update, SectionsUpdate::Rooms { rooms } if tags_of(rooms) == Some(vec![]))
    })
    .await?;
    assert!(matches!(
        alice
            .set_room_section(room_id.clone(), Some("u.work".to_owned()))
            .await,
        Err(CoreError::InvalidId { .. })
    ));

    // Renamed, with a new order; the rest of Element's settings stays.
    let order = vec![
        ACME.to_owned(),
        "im.vector.fake.direct".to_owned(),
        "chats".to_owned(),
    ];
    alice
        .save_section_settings(SectionSettings {
            sections: vec![CustomSection {
                tag: ACME.to_owned(),
                name: "Acme Corp".to_owned(),
            }],
            order: order.clone(),
        })
        .await?;
    wait_for_sections(&mut sections, "the renamed, reordered settings", |update| {
        matches!(update, SectionsUpdate::Settings { settings }
            if settings.order == order && settings.sections[0].name == "Acme Corp")
    })
    .await?;
    let stored = alice
        .sdk()
        .account()
        .account_data_raw("im.vector.web.settings".into())
        .await?
        .ok_or("no settings")?;
    let stored: serde_json::Value = serde_json::from_str(stored.json().get())?;
    assert_eq!(stored["someOtherSetting"], json!(true));
    assert_eq!(
        stored["RoomList.CustomSectionData"][ACME]["spaceId"],
        json!("home-space")
    );
    Ok(())
}

/// Reading a chat clears its unread count, here and for the user's other devices.
#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a test homeserver (test-infra/)"]
async fn marking_a_chat_read_clears_its_unread_count() -> TestResult {
    let (alice_user, bob_user) = (TestUser::register().await?, TestUser::register().await?);
    let (alice_store, bob_store) = (tempfile::tempdir()?, tempfile::tempdir()?);
    let alice = alice_user
        .login(&alice_store.path().to_string_lossy())
        .await?;
    let bob = bob_user.login(&bob_store.path().to_string_lossy()).await?;
    alice.start_sync().await;
    bob.start_sync().await;

    let room_id = alice.create_dm(bob.user_id()).await?;
    let mut bob_rooms = watch_rooms(&bob).await?;
    bob_rooms
        .wait_until(|rooms| rooms.iter().any(|r| r.room_id == room_id))
        .await?;
    bob.join(room_id.clone()).await?;
    let alice_timeline = alice.timeline(room_id.clone()).await?;
    alice_timeline.send_text("one".to_owned(), false).await?;
    alice_timeline.send_text("two".to_owned(), false).await?;
    let unread = |rooms: &[RoomSummary]| {
        rooms
            .iter()
            .find(|r| r.room_id == room_id)
            .map(|r| r.unread_count)
    };
    bob_rooms
        .wait_until(|rooms| unread(rooms) == Some(2))
        .await?;

    let bob_timeline = bob.timeline(room_id.clone()).await?;
    let mut bob_items = watch_timeline(&bob_timeline).await;
    bob_items
        .wait_until(|items| messages(items).contains(&("two", false)))
        .await?;
    bob_timeline.mark_as_read().await?;
    bob_rooms
        .wait_until(|rooms| unread(rooms) == Some(0))
        .await?;
    // Again, with nothing new: nothing to send, no error.
    bob_timeline.mark_as_read().await?;
    Ok(())
}

/// Alice and Bob in an encrypted DM that Bob has joined, with the room ID.
async fn joined_dm() -> Result<(Session, Session, String, Vec<tempfile::TempDir>), Box<dyn Error>> {
    let (alice_user, bob_user) = (TestUser::register().await?, TestUser::register().await?);
    let stores = vec![tempfile::tempdir()?, tempfile::tempdir()?];
    let alice = alice_user
        .login(&stores[0].path().to_string_lossy())
        .await?;
    let bob = bob_user.login(&stores[1].path().to_string_lossy()).await?;
    alice.start_sync().await;
    bob.start_sync().await;
    let room_id = alice.create_dm(bob.user_id()).await?;
    let mut bob_rooms = watch_rooms(&bob).await?;
    bob_rooms
        .wait_until(|rooms| rooms.iter().any(|r| r.room_id == room_id))
        .await?;
    bob.join(room_id.clone()).await?;
    bob_rooms
        .wait_until(|rooms| {
            rooms
                .iter()
                .any(|r| r.room_id == room_id && r.membership == Membership::Joined)
        })
        .await?;
    Ok((alice, bob, room_id, stores))
}

/// The media message of `kind` in `items`, once there is one.
fn media_of(items: &[TimelineItem], kind: MediaKind) -> Option<MediaMessage> {
    items.iter().find_map(|item| match &item.content {
        TimelineItemContent::Media { media, .. } if media.kind == kind => Some(media.clone()),
        _ => None,
    })
}

/// Pictures and files arrive decrypted, are cached, and can be saved; the media timeline
/// keeps only them and the links.
#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a test homeserver (test-infra/)"]
async fn pictures_and_files_arrive_and_are_cached() -> TestResult {
    let (alice, bob, room_id, _stores) = joined_dm().await?;
    let room = alice
        .sdk()
        .get_room(&room_id.parse::<OwnedRoomId>()?)
        .ok_or("no room")?;
    let notes = b"meeting notes".to_vec();
    room.send_attachment(
        "pic.png",
        &mime::IMAGE_PNG,
        AVATAR_PNG.to_vec(),
        AttachmentConfig::new(),
    )
    .await?;
    room.send_attachment(
        "notes.txt",
        &mime::TEXT_PLAIN,
        notes.clone(),
        AttachmentConfig::new().info(AttachmentInfo::File(BaseFileInfo {
            size: Some(13_u32.into()),
        })),
    )
    .await?;
    let alice_timeline = alice.timeline(room_id.clone()).await?;
    alice_timeline
        .send_text("no link".to_owned(), false)
        .await?;
    alice_timeline
        .send_text("see https://oxisoft.io/docs".to_owned(), false)
        .await?;

    let bob_timeline = bob.timeline(room_id.clone()).await?;
    let mut items = watch_timeline(&bob_timeline).await;
    // Paging back as the app does while the user scrolls up: a sync that arrives later can put
    // the newest messages after a gap, with the files behind it.
    let paging = async {
        loop {
            if let Err(error) = bob_timeline.paginate_back(20).await {
                return error;
            }
            tokio::time::sleep(Duration::from_millis(300)).await;
        }
    };
    tokio::select! {
        found = items.wait_until(|items| {
            media_of(items, MediaKind::Image).is_some()
                && media_of(items, MediaKind::File).is_some()
        }) => found?,
        error = paging => return Err(error.into()),
    }
    let image = media_of(&items.items, MediaKind::Image).ok_or("no image")?;
    let file = media_of(&items.items, MediaKind::File).ok_or("no file")?;
    assert_eq!(
        (image.filename.as_str(), file.filename.as_str()),
        ("pic.png", "notes.txt")
    );
    assert_eq!(image.mime_type.as_deref(), Some("image/png"));
    assert_eq!(file.size, Some(13));
    // Encrypted on the server, decrypted here.
    assert!(image.source.contains("\"key\""));
    assert_eq!(bob.media_content(image.source.clone()).await?, AVATAR_PNG);
    let thumbnail = bob
        .media_thumbnail(image.source.clone(), image.thumbnail.clone(), 96)
        .await?;
    assert!(thumbnail.starts_with(b"\x89PNG") || thumbnail.starts_with(b"\xff\xd8"));
    let saved = tempfile::tempdir()?.keep().join("notes.txt");
    bob.save_media(file.source.clone(), saved.to_string_lossy().into_owned())
        .await?;
    assert_eq!(std::fs::read(&saved)?, notes);
    assert!(matches!(
        bob.media_content("{}".to_owned()).await,
        Err(CoreError::InvalidId { .. })
    ));

    // Cached: the size shows; cleared, it is fetched again.
    bob.set_media_retention(Some(7)).await?;
    assert!(bob.media_cache_size().await?.unwrap_or_default() > 0);
    bob.clear_media_cache().await?;
    bob.set_media_retention(None).await?;
    assert_eq!(bob.media_content(image.source).await?, AVATAR_PNG);

    let gallery = bob.media_timeline(room_id).await?;
    let mut gallery_items = watch_timeline(&gallery).await;
    gallery.paginate_back(50).await?;
    gallery_items
        .wait_until(|items| {
            media_of(items, MediaKind::Image).is_some()
                && media_of(items, MediaKind::File).is_some()
                && messages(items)
                    .iter()
                    .any(|(body, _)| body.contains("https://"))
        })
        .await?;
    assert!(
        !messages(&gallery_items.items)
            .iter()
            .any(|(body, _)| *body == "no link")
    );
    Ok(())
}

/// The info screen's details and members of a direct chat.
#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a test homeserver (test-infra/)"]
async fn a_direct_chat_shows_its_details_and_members() -> TestResult {
    let (alice, bob, room_id, _stores) = joined_dm().await?;
    // The SDK marks the DM in account data (m.direct), which Alice's store has after a sync;
    // Bob's identity (cross-signing) is uploaded by his client after login.
    let details = poll_until("Alice knows the room as a DM with Bob", || async {
        let details = alice.room_details(room_id.clone()).await?;
        Ok((details.dm_user_id.is_some() && details.dm_user_verified.is_some()).then_some(details))
    })
    .await?;
    assert!(details.is_encrypted);
    assert_eq!(details.dm_user_id.as_deref(), Some(bob.user_id().as_str()));
    // Alice hasn't verified Bob.
    assert_eq!(details.dm_user_verified, Some(false));
    let members = alice.room_members(room_id.clone()).await?;
    let ids: Vec<_> = members.iter().map(|m| m.user_id.clone()).collect();
    assert_eq!(members.len(), 2, "{ids:?}");
    assert!(ids.contains(&alice.user_id()) && ids.contains(&bob.user_id()));
    // Alice made the room.
    let alice_member = members
        .iter()
        .find(|m| m.user_id == alice.user_id())
        .ok_or("no Alice")?;
    assert_eq!(alice_member.role, MemberRole::Admin);
    assert!(matches!(
        bob.room_details("!nowhere:localhost".to_owned()).await,
        Err(CoreError::RoomNotFound { .. })
    ));
    Ok(())
}

/// The event of the text message `body` in `items`, once there is one.
fn event_of<'a>(items: &'a [TimelineItem], body: &str) -> Option<&'a EventInfo> {
    items.iter().find_map(|item| match &item.content {
        TimelineItemContent::Message { event, body: b, .. } if b == body => Some(event),
        _ => None,
    })
}

/// A reply in a thread stays in the thread: the main timeline shows only the thread's first
/// message with how many replies it has and the latest; the thread and the room's thread list
/// show the rest.
#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a test homeserver (test-infra/)"]
async fn replies_in_a_thread_stay_in_it() -> TestResult {
    let (alice, bob, room_id, _stores) = joined_dm().await?;
    let alice_timeline = alice.timeline(room_id.clone()).await?;
    let mut alice_items = watch_timeline(&alice_timeline).await;
    alice_timeline.send_text("lunch?".to_owned(), false).await?;
    let bob_timeline = bob.timeline(room_id.clone()).await?;
    let mut bob_items = watch_timeline(&bob_timeline).await;
    bob_items
        .wait_until(|items| event_of(items, "lunch?").is_some_and(|e| e.event_id.is_some()))
        .await?;
    let root = event_of(&bob_items.items, "lunch?")
        .and_then(|e| e.event_id.clone())
        .ok_or("no event ID")?;

    let bob_thread = bob.thread_timeline(room_id.clone(), root.clone()).await?;
    bob_thread.send_text("pizza".to_owned(), false).await?;

    // Alice: the first message carries the thread; the reply isn't in the main timeline.
    alice_items
        .wait_until(|items| {
            event_of(items, "lunch?").is_some_and(|e| {
                e.thread.as_ref().is_some_and(|thread| {
                    thread.reply_count == 1
                        && thread
                            .latest
                            .as_ref()
                            .is_some_and(|latest| latest.text.as_deref() == Some("pizza"))
                })
            })
        })
        .await?;
    assert!(event_of(&alice_items.items, "pizza").is_none());

    // The thread has its first message, then the reply, which Alice answers there.
    let alice_thread = alice.thread_timeline(room_id.clone(), root.clone()).await?;
    let mut thread_items = watch_timeline(&alice_thread).await;
    alice_thread.paginate_back(20).await?;
    thread_items
        .wait_until(|items| {
            event_of(items, "lunch?").is_some() && event_of(items, "pizza").is_some()
        })
        .await?;
    alice_thread.send_text("deal".to_owned(), false).await?;
    alice_items
        .wait_until(|items| {
            event_of(items, "lunch?")
                .is_some_and(|e| e.thread.as_ref().is_some_and(|t| t.reply_count == 2))
        })
        .await?;
    assert!(event_of(&alice_items.items, "deal").is_none());

    // The room's thread list.
    let list = alice.thread_list(room_id).await?;
    let (sender, mut lists) = mpsc::unbounded_channel();
    list.updates(move |threads| sender.send(threads).is_ok())
        .await;
    list.paginate().await?;
    let found = tokio::time::timeout(TIMEOUT, async {
        while let Some(threads) = lists.recv().await {
            if let Some(thread) = threads
                .into_iter()
                .find(|t: &ThreadSummary| t.root_event_id == root)
                && thread.reply_count == 2
            {
                return Some(thread);
            }
        }
        None
    })
    .await
    .map_err(|_| "the thread never showed in the list with both replies")?
    .ok_or("the list stream ended")?;
    assert_eq!(found.root.text.as_deref(), Some("lunch?"));
    assert_eq!(found.root.sender, alice.user_id());
    assert_eq!(
        found.latest.and_then(|latest| latest.text).as_deref(),
        Some("deal")
    );
    Ok(())
}

/// The chat list shows the newest message outside threads, even under a newer reply in one.
#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a test homeserver (test-infra/)"]
async fn the_chat_list_shows_no_thread_replies() -> TestResult {
    let (alice, _bob, room_id, _stores) = joined_dm().await?;
    let timeline = alice.timeline(room_id.clone()).await?;
    let mut items = watch_timeline(&timeline).await;
    timeline.send_text("lunch?".to_owned(), false).await?;
    items
        .wait_until(|items| event_of(items, "lunch?").is_some_and(|e| e.event_id.is_some()))
        .await?;
    let root = event_of(&items.items, "lunch?")
        .and_then(|e| e.event_id.clone())
        .ok_or("no event ID")?;
    let thread = alice.thread_timeline(room_id.clone(), root).await?;
    timeline.send_text("main after".to_owned(), false).await?;
    thread.send_text("late in thread".to_owned(), false).await?;
    items
        .wait_until(|items| {
            event_of(items, "lunch?")
                .is_some_and(|e| e.thread.as_ref().is_some_and(|t| t.reply_count == 1))
        })
        .await?;
    let mut rooms = watch_rooms(&alice).await?;
    rooms
        .wait_until(|rooms| {
            rooms
                .iter()
                .any(|r| r.room_id == room_id && r.last_message.as_deref() == Some("main after"))
        })
        .await?;
    Ok(())
}

/// Reactions, replies, edits and deletions reach the other side.
#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a test homeserver (test-infra/)"]
async fn reactions_replies_edits_and_deletions_reach_the_other_side() -> TestResult {
    let (alice, bob, room_id, _stores) = joined_dm().await?;
    let alice_timeline = alice.timeline(room_id.clone()).await?;
    let mut alice_items = watch_timeline(&alice_timeline).await;
    let bob_timeline = bob.timeline(room_id).await?;
    let mut bob_items = watch_timeline(&bob_timeline).await;
    alice_timeline.send_text("hello".to_owned(), false).await?;
    bob_items
        .wait_until(|items| event_of(items, "hello").is_some_and(|e| e.event_id.is_some()))
        .await?;
    let id = event_of(&bob_items.items, "hello")
        .and_then(|e| e.event_id.clone())
        .ok_or("no event ID")?;

    bob_timeline
        .toggle_reaction(id.clone(), "👍".to_owned())
        .await?;
    let bob_id = bob.user_id();
    alice_items
        .wait_until(|items| {
            event_of(items, "hello").is_some_and(|e| {
                e.reactions.len() == 1
                    && e.reactions[0].key == "👍"
                    && e.reactions[0].senders == [bob_id.clone()]
                    && !e.reactions[0].mine
            })
        })
        .await?;
    bob_items
        .wait_until(|items| {
            event_of(items, "hello").is_some_and(|e| e.reactions.first().is_some_and(|r| r.mine))
        })
        .await?;

    bob_timeline
        .send_reply("hi back".to_owned(), id.clone(), false)
        .await?;
    alice_items
        .wait_until(|items| {
            event_of(items, "hi back").is_some_and(|e| {
                e.in_reply_to.as_ref().is_some_and(|quote| {
                    quote.event_id == id && quote.text.as_deref() == Some("hello")
                })
            })
        })
        .await?;

    alice_timeline
        .edit(id.clone(), "hello there".to_owned(), false, false)
        .await?;
    bob_items
        .wait_until(|items| event_of(items, "hello there").is_some_and(|e| e.is_edited))
        .await?;
    alice_timeline.redact(id.clone(), None).await?;
    bob_items
        .wait_until(|items| {
            items.iter().any(|item| {
                matches!(&item.content, TimelineItemContent::Redacted { event }
                    if event.event_id.as_deref() == Some(id.as_str()))
            })
        })
        .await?;
    // A DM makes both of them admins, who may delete each other's messages.
    assert!(alice_timeline.can_redact_others().await);
    Ok(())
}

/// A big photo goes compressed with its caption; forwarding sends the same file again
/// without uploading; recent emojis are kept in the account.
#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a test homeserver (test-infra/)"]
async fn photos_go_compressed_with_a_caption_and_forward() -> TestResult {
    let (alice, bob, room_id, _stores) = joined_dm().await?;
    let photo = noise_png(2600, 1300)?;
    let alice_timeline = alice.timeline(room_id.clone()).await?;
    alice_timeline
        .send_data(
            photo.clone(),
            "beach.png".to_owned(),
            "image/png".to_owned(),
            Some("At the beach".to_owned()),
            true,
            true,
        )
        .await?;
    let bob_timeline = bob.timeline(room_id.clone()).await?;
    let mut bob_items = watch_timeline(&bob_timeline).await;
    bob_timeline.paginate_back(20).await?;
    bob_items
        .wait_until(|items| media_of(items, MediaKind::Image).is_some())
        .await?;
    let image = media_of(&bob_items.items, MediaKind::Image).ok_or("no image")?;
    assert_eq!(image.filename, "beach.jpg");
    assert_eq!(image.caption.as_deref(), Some("At the beach"));
    assert_eq!((image.width, image.height), (Some(2048), Some(1024)));
    let sent = bob.media_content(image.source.clone()).await?;
    assert!(sent.starts_with(b"\xff\xd8") && sent.len() < photo.len());

    // Forwarded to another chat of Bob's: the same file, not uploaded again.
    let event_id = bob_items
        .items
        .iter()
        .find_map(|item| match &item.content {
            TimelineItemContent::Media { event, .. } => event.event_id.clone(),
            _ => None,
        })
        .ok_or("no event ID")?;
    let other = bob.create_dm(alice.user_id()).await?;
    bob_timeline.forward(event_id, other.clone()).await?;
    let other_timeline = bob.timeline(other).await?;
    let mut other_items = watch_timeline(&other_timeline).await;
    other_items
        .wait_until(|items| {
            media_of(items, MediaKind::Image).is_some_and(|m| m.source == image.source)
        })
        .await?;

    alice.add_recent_emoji("🎉".to_owned()).await?;
    assert_eq!(
        alice.recent_emojis().await?.first().map(String::as_str),
        Some("🎉")
    );
    Ok(())
}

/// Voice messages go as Element sends them (Ogg Opus, marked as voice, with a length and a
/// waveform), also as a reply and into a thread.
#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a test homeserver (test-infra/)"]
async fn voice_messages_and_videos_arrive_as_such() -> TestResult {
    let (alice, bob, room_id, _stores) = joined_dm().await?;
    let alice_timeline = alice.timeline(room_id.clone()).await?;
    let mut alice_items = watch_timeline(&alice_timeline).await;
    alice_timeline
        .send_text("how was it?".to_owned(), false)
        .await?;
    alice_items
        .wait_until(|items| event_of(items, "how was it?").is_some_and(|e| e.event_id.is_some()))
        .await?;
    let question = event_of(&alice_items.items, "how was it?")
        .and_then(|e| e.event_id.clone())
        .ok_or("no event ID")?;

    let bob_timeline = bob.timeline(room_id.clone()).await?;
    let mut bob_items = watch_timeline(&bob_timeline).await;
    bob_items
        .wait_until(|items| event_of(items, "how was it?").is_some())
        .await?;
    // Two seconds of a tone at 44.1 kHz, as a recorder might give them.
    let clip = encode_voice(tone(44_100, 2.0), 44_100, 1)?;
    assert_eq!(clip.duration_ms, 2000);
    bob_timeline
        .send_voice(
            clip.data.clone(),
            clip.duration_ms,
            clip.waveform.clone(),
            Some(question.clone()),
        )
        .await?;

    let voice_of = |items: &[TimelineItem]| {
        items.iter().find_map(|item| match &item.content {
            TimelineItemContent::Media { event, media } if media.is_voice => {
                Some((event.clone(), media.clone()))
            }
            _ => None,
        })
    };
    alice_items
        .wait_until(|items| voice_of(items).is_some_and(|(event, _)| event.event_id.is_some()))
        .await?;
    let (event, voice) = voice_of(&alice_items.items).ok_or("no voice message")?;
    assert_eq!(voice.kind, MediaKind::Audio);
    assert_eq!(voice.mime_type.as_deref(), Some("audio/ogg"));
    assert_eq!(voice.duration_ms, Some(2000));
    assert_eq!(voice.size, i64::try_from(clip.data.len()).ok());
    let waveform = voice.waveform.clone().ok_or("no waveform")?;
    assert_eq!(waveform.len(), 100);
    assert!(waveform.iter().any(|point| *point > 1000));
    assert_eq!(
        event.in_reply_to.map(|reply| reply.event_id),
        Some(question.clone())
    );
    // The event as Element reads it.
    let room = alice
        .sdk()
        .get_room(&room_id.parse::<OwnedRoomId>()?)
        .ok_or("no room")?;
    let voice_id = event.event_id.ok_or("no event ID")?;
    let raw = room
        .event(&voice_id.parse::<OwnedEventId>()?, None)
        .await?
        .raw()
        .json()
        .get()
        .to_owned();
    assert!(raw.contains("org.matrix.msc3245.voice"), "{raw}");
    assert!(raw.contains("org.matrix.msc1767.audio"), "{raw}");
    // It plays: the file decodes to as much sound as was sent.
    let wav = playable_wav(alice.media_content(voice.source).await?).ok_or("not Ogg Opus")?;
    assert!((wav.len() - 44) / 2 >= 95_000, "{} bytes", wav.len());

    // Into a thread, as anything sent there.
    let thread = bob
        .thread_timeline(room_id.clone(), question.clone())
        .await?;
    thread
        .send_voice(clip.data, clip.duration_ms, clip.waveform, None)
        .await?;
    alice_items
        .wait_until(|items| {
            event_of(items, "how was it?")
                .is_some_and(|e| e.thread.as_ref().is_some_and(|t| t.reply_count == 1))
        })
        .await?;

    Ok(())
}

/// A recorded video goes with its length and shape, and a thumbnail made of the photo taken as
/// it started, cut to its shape.
#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a test homeserver (test-infra/)"]
async fn recorded_videos_go_with_a_thumbnail() -> TestResult {
    let (alice, bob, room_id, _stores) = joined_dm().await?;
    let alice_timeline = alice.timeline(room_id.clone()).await?;
    let bob_timeline = bob.timeline(room_id.clone()).await?;
    let mut bob_items = watch_timeline(&bob_timeline).await;
    let video = b"\0\0\0\x18ftypmp42 not really a video".to_vec();
    alice_timeline
        .send_video(
            video.clone(),
            "video.mp4".to_owned(),
            "video/mp4".to_owned(),
            Some(noise_png(1600, 1200)?),
            Some(1280),
            Some(720),
            3_500,
            None,
        )
        .await?;
    bob_items
        .wait_until(|items| media_of(items, MediaKind::Video).is_some())
        .await?;
    let sent = media_of(&bob_items.items, MediaKind::Video).ok_or("no video")?;
    assert_eq!(sent.mime_type.as_deref(), Some("video/mp4"));
    assert_eq!(sent.duration_ms, Some(3_500));
    assert_eq!((sent.width, sent.height), (Some(1280), Some(720)));
    assert_eq!(sent.size, i64::try_from(video.len()).ok());
    assert!(!sent.is_voice);
    let thumbnail = bob
        .media_thumbnail(sent.source.clone(), sent.thumbnail.clone(), 320)
        .await?;
    assert!(sent.thumbnail.is_some() && thumbnail.starts_with(b"\xff\xd8"));
    assert_eq!(bob.media_content(sent.source).await?, video);
    Ok(())
}

/// `seconds` of mono sound at `rate`: a tone that swells and fades.
fn tone(rate: u32, seconds: f64) -> Vec<i16> {
    let count = (f64::from(rate) * seconds).round();
    let mut pcm = Vec::new();
    let mut index = 0.0;
    while index < count {
        let t = index / f64::from(rate);
        let level = (t / seconds * std::f64::consts::PI).sin() * 12_000.0;
        let sample = (std::f64::consts::TAU * 330.0 * t).sin() * level;
        // Within ±12 000.
        #[allow(clippy::cast_possible_truncation)]
        pcm.push(sample.round() as i16);
        index += 1.0;
    }
    pcm
}

/// A PNG of noise, which compresses badly, like a photo.
fn noise_png(width: u32, height: u32) -> Result<Vec<u8>, Box<dyn Error>> {
    let byte = |value: u32| u8::try_from(value % 256).unwrap_or_default();
    let image = image::RgbImage::from_fn(width, height, |x, y| {
        image::Rgb([byte(x * 7 + y * 13), byte(x ^ y), byte(x * y)])
    });
    let mut data = Vec::new();
    image::DynamicImage::ImageRgb8(image).write_to(
        &mut std::io::Cursor::new(&mut data),
        image::ImageFormat::Png,
    )?;
    Ok(data)
}

/// Markdown goes as Element sends it, and arrives as formatted blocks; plain text stays plain.
#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a test homeserver (test-infra/)"]
async fn markdown_arrives_formatted() -> TestResult {
    let (alice, bob, room_id, _stores) = joined_dm().await?;
    let alice_timeline = alice.timeline(room_id.clone()).await?;
    alice_timeline
        .send_text("just *text*".to_owned(), false)
        .await?;
    alice_timeline
        .send_text(
            "**Battery low:** at *20 %*\n\n- one\n- two".to_owned(),
            true,
        )
        .await?;
    let bob_timeline = bob.timeline(room_id).await?;
    let mut items = watch_timeline(&bob_timeline).await;
    bob_timeline.paginate_back(20).await?;
    let formatted_of = |items: &[TimelineItem], start: &str| {
        items.iter().find_map(|item| match &item.content {
            TimelineItemContent::Message {
                body, formatted, ..
            } if body.starts_with(start) => Some(formatted.clone()),
            _ => None,
        })
    };
    items
        .wait_until(|items| {
            formatted_of(items, "**Battery").is_some() && formatted_of(items, "just").is_some()
        })
        .await?;
    let blocks = formatted_of(&items.items, "**Battery")
        .flatten()
        .ok_or("no formatting")?;
    assert_eq!(blocks[0].spans[0].text, "Battery low:");
    assert!(blocks[0].spans[0].bold);
    assert!(blocks[0].spans.iter().any(|s| s.italic && s.text == "20 %"));
    assert_eq!(
        blocks[1].kind,
        BlockKind::ListItem {
            number: None,
            depth: 1
        }
    );
    assert_eq!(formatted_of(&items.items, "just"), Some(None));

    // The chat list shows the latest message as plain text, without the markdown.
    let mut rooms = watch_rooms(&bob).await?;
    rooms
        .wait_until(|rooms| {
            rooms
                .iter()
                .any(|r| r.last_message.as_deref() == Some("Battery low: at 20 % one two"))
        })
        .await?;
    Ok(())
}

/// The other side sees the user typing, and stopping.
#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a test homeserver (test-infra/)"]
async fn typing_shows_on_the_other_side() -> TestResult {
    let (alice, bob, room_id, _stores) = joined_dm().await?;
    // The room list subscribes the rooms whose typing comes with the sync.
    let _bob_rooms = watch_rooms(&bob).await?;
    let mut typing = bob.typing_updates();
    let alice_timeline = alice.timeline(room_id.clone()).await?;
    let alice_id = alice.user_id();
    let mut wait_for = async |typing_now: bool| -> TestResult {
        tokio::time::timeout(TIMEOUT, async {
            while let Some(update) = typing.next().await {
                let alice_typing = update
                    .names
                    .iter()
                    .any(|name| alice_id.contains(name.as_str()));
                if update.room_id == room_id && alice_typing == typing_now {
                    return Ok(());
                }
            }
            Err("the stream ended".into())
        })
        .await
        .map_err(|_| format!("timed out waiting for typing = {typing_now}"))?
    };
    alice_timeline.set_typing(true).await?;
    wait_for(true).await?;
    alice_timeline.set_typing(false).await?;
    wait_for(false).await?;
    Ok(())
}

/// A private room is made encrypted, with its topic and picture, and someone invited joins;
/// a public one with an address is joined by that address.
#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a test homeserver (test-infra/)"]
async fn rooms_are_created_joined_and_invited_to() -> TestResult {
    let (alice_user, bob_user) = (TestUser::register().await?, TestUser::register().await?);
    let (alice_store, bob_store) = (tempfile::tempdir()?, tempfile::tempdir()?);
    let alice = alice_user
        .login(&alice_store.path().to_string_lossy())
        .await?;
    let bob = bob_user.login(&bob_store.path().to_string_lossy()).await?;
    alice.start_sync().await;
    bob.start_sync().await;

    let private = alice
        .create_room(NewRoom {
            name: "Team".to_owned(),
            topic: Some("Where the team talks".to_owned()),
            public: false,
            alias: None,
            // Ignored: a private room is always encrypted.
            encrypted: false,
            avatar: Some(RoomAvatar {
                data: AVATAR_PNG.to_vec(),
                mime_type: "image/png".to_owned(),
            }),
        })
        .await?;
    alice.invite(private.clone(), bob.user_id()).await?;
    let mut bob_rooms = watch_rooms(&bob).await?;
    bob_rooms
        .wait_until(|rooms| rooms.iter().any(|r| r.room_id == private))
        .await?;
    bob.join(private.clone()).await?;
    // The picture is set after the room is created; it reaches Alice's store with a sync.
    let details = poll_until("the room's picture is in Alice's store", || async {
        let details = alice.room_details(private.clone()).await?;
        Ok(details.avatar_url.is_some().then_some(details))
    })
    .await?;
    assert_eq!(details.name, "Team");
    assert_eq!(details.topic.as_deref(), Some("Where the team talks"));
    assert!(details.is_encrypted);

    let alias = format!("pub{}", alice_user.name);
    let public = alice
        .create_room(NewRoom {
            name: "Open".to_owned(),
            topic: None,
            public: true,
            alias: Some(alias.clone()),
            encrypted: false,
            avatar: None,
        })
        .await?;
    let joined = bob.join_by_address(format!("#{alias}:localhost")).await?;
    assert_eq!(joined, public);
    // The room's state reaches Bob's store with the next sync.
    let details = tokio::time::timeout(TIMEOUT, async {
        loop {
            let details = bob.room_details(public.clone()).await?;
            if details.alias.is_some() {
                return Ok::<_, CoreError>(details);
            }
            tokio::time::sleep(Duration::from_millis(200)).await;
        }
    })
    .await??;
    assert_eq!(details.alias, Some(format!("#{alias}:localhost")));
    assert!(!details.is_encrypted);
    assert!(matches!(
        bob.join_by_address("not a room".to_owned()).await,
        Err(CoreError::InvalidId { .. })
    ));
    Ok(())
}

/// People known from shared chats and from the server's directory; public rooms the most
/// joined first, the ones already joined last.
#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a test homeserver (test-infra/)"]
async fn people_and_public_rooms_are_found() -> TestResult {
    let (alice, bob, room_id, _stores) = joined_dm().await?;
    // The DM's members and its partner (m.direct) reach Alice's store with a sync.
    let known = poll_until("Bob is among Alice's known people", || async {
        let known = alice.known_people(50).await?;
        Ok(known
            .iter()
            .any(|p| p.user_id == bob.user_id())
            .then_some(known))
    })
    .await?;
    assert!(!known.iter().any(|p| p.user_id == alice.user_id()));
    assert_eq!(alice.dm_with(bob.user_id())?, Some(room_id));

    let bob_name = bob.user_id()[1..]
        .split(':')
        .next()
        .unwrap_or_default()
        .to_owned();
    // The server's user directory catches up with new users and rooms in the background.
    tokio::time::timeout(TIMEOUT, async {
        loop {
            let found = alice.search_people(bob_name.clone(), 10).await?;
            if found.iter().any(|p| p.user_id == bob.user_id()) {
                return Ok::<_, CoreError>(());
            }
            tokio::time::sleep(Duration::from_millis(300)).await;
        }
    })
    .await
    .map_err(|_| "Bob never showed in the user directory")??;

    // Two rooms in the directory: Bob is in "Big", not in "Small".
    // Unique to this run: earlier runs' rooms stay in the directory.
    let tag = bob_name.clone();
    let publish = async |name: String| -> Result<String, Box<dyn Error>> {
        let mut request = CreateRoomRequest::new();
        request.name = Some(name);
        request.visibility = Visibility::Public;
        request.preset = Some(RoomPreset::PublicChat);
        Ok(alice
            .sdk()
            .create_room(request)
            .await?
            .room_id()
            .to_string())
    };
    let big = publish(format!("Big {tag}")).await?;
    let small = publish(format!("Small {tag}")).await?;
    bob.join(big.clone()).await?;
    // The directory lists them once the server's room statistics catch up.
    let rooms = tokio::time::timeout(TIMEOUT, async {
        loop {
            let rooms = bob.public_rooms(Some(tag.clone()), 50).await?;
            if rooms.len() == 2 {
                return Ok::<_, CoreError>(rooms);
            }
            tokio::time::sleep(Duration::from_millis(300)).await;
        }
    })
    .await
    .map_err(|_| "the rooms never showed in the directory")??;
    let order: Vec<_> = rooms
        .iter()
        .map(|r| (r.room_id.clone(), r.joined))
        .collect();
    assert_eq!(order, vec![(small.clone(), false), (big, true)]);
    assert_eq!(rooms[0].members, 1);
    let only = bob.public_rooms(Some(format!("Small {tag}")), 50).await?;
    assert_eq!(
        only.iter().map(|r| r.room_id.clone()).collect::<Vec<_>>(),
        vec![small]
    );
    Ok(())
}

/// The room's creator makes a member a moderator, the moderator may not touch the admin,
/// and members are removed, banned and unbanned.
#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a test homeserver (test-infra/)"]
async fn members_get_roles_and_are_removed_and_banned() -> TestResult {
    let (alice_user, bob_user) = (TestUser::register().await?, TestUser::register().await?);
    let (alice_store, bob_store) = (tempfile::tempdir()?, tempfile::tempdir()?);
    let alice = alice_user
        .login(&alice_store.path().to_string_lossy())
        .await?;
    let bob = bob_user.login(&bob_store.path().to_string_lossy()).await?;
    alice.start_sync().await;
    bob.start_sync().await;
    let room = alice
        .create_room(NewRoom {
            name: "Staff".to_owned(),
            topic: None,
            public: false,
            alias: None,
            encrypted: true,
            avatar: None,
        })
        .await?;
    alice.invite(room.clone(), bob.user_id()).await?;
    let mut bob_rooms = watch_rooms(&bob).await?;
    bob_rooms
        .wait_until(|rooms| rooms.iter().any(|r| r.room_id == room))
        .await?;
    bob.join(room.clone()).await?;

    // Waits until `session` sees `user` in the room as `wanted` says.
    let member_of = async |session: &Session,
                           user: String,
                           wanted: fn(&RoomMember) -> bool,
                           what: &str|
           -> Result<RoomMember, Box<dyn Error>> {
        Ok(tokio::time::timeout(TIMEOUT, async {
            loop {
                let members = session.room_members(room.clone()).await?;
                if let Some(member) = members.iter().find(|m| m.user_id == user && wanted(m)) {
                    return Ok::<_, CoreError>(member.clone());
                }
                tokio::time::sleep(Duration::from_millis(300)).await;
            }
        })
        .await
        .map_err(|_| format!("timed out waiting until {what}"))??)
    };

    // The room's power levels reach Alice's store with a sync; until then she shows as 0.
    let details = poll_until("the room's power levels are in Alice's store", || async {
        let details = alice.room_details(room.clone()).await?;
        Ok((details.own_power_level != Some(0)).then_some(details))
    })
    .await?;
    // The creator: 100 in rooms before version 12, above every number (`None`) from it on,
    // which depends on the server's default room version.
    assert!(
        details.own_power_level.is_none_or(|level| level >= 100),
        "{:?}",
        details.own_power_level
    );
    let plain = member_of(
        &alice,
        bob.user_id(),
        |m| !m.invited,
        "Alice sees Bob joined",
    )
    .await?;
    assert_eq!(plain.role, MemberRole::Member);
    assert!(plain.can_change_role && plain.can_remove && plain.can_ban && !plain.can_unban);

    alice
        .set_power_level(room.clone(), bob.user_id(), 50)
        .await?;
    let moderator = member_of(
        &bob,
        bob.user_id(),
        |m| m.power_level == Some(50),
        "Bob sees himself a moderator",
    )
    .await?;
    assert_eq!(moderator.role, MemberRole::Moderator);
    // A moderator may not change, remove or ban the admin above them.
    let admin = member_of(&bob, alice.user_id(), |_| true, "Bob sees Alice").await?;
    assert!(!admin.can_change_role && !admin.can_remove && !admin.can_ban);
    assert!(
        bob.set_power_level(room.clone(), alice.user_id(), 0)
            .await
            .is_err()
    );

    alice
        .ban_member(room.clone(), bob.user_id(), Some("testing".to_owned()))
        .await?;
    let banned = member_of(&alice, bob.user_id(), |m| m.banned, "Alice sees Bob banned").await?;
    assert!(banned.can_unban && !banned.can_ban && !banned.can_remove);
    alice.unban_member(room.clone(), bob.user_id()).await?;
    wait_until_gone(&alice, &room, &bob.user_id(), "after the unban").await?;

    // An invite is withdrawn by removing the invited person.
    alice.invite(room.clone(), bob.user_id()).await?;
    member_of(
        &alice,
        bob.user_id(),
        |m| m.invited,
        "Alice sees Bob invited",
    )
    .await?;
    alice
        .remove_member(room.clone(), bob.user_id(), None)
        .await?;
    wait_until_gone(&alice, &room, &bob.user_id(), "after the removal").await?;
    Ok(())
}

/// Waits until `user` is no longer among the members `session` lists for `room`.
async fn wait_until_gone(session: &Session, room: &str, user: &str, when: &str) -> TestResult {
    tokio::time::timeout(TIMEOUT, async {
        loop {
            let members = session.room_members(room.to_owned()).await?;
            if !members.iter().any(|m| m.user_id == user) {
                return Ok::<_, CoreError>(());
            }
            tokio::time::sleep(Duration::from_millis(300)).await;
        }
    })
    .await
    .map_err(|_| format!("{user} still listed {when}"))??;
    Ok(())
}

#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a test homeserver (test-infra/)"]
async fn a_new_device_is_verified_with_emoji_by_another() -> TestResult {
    let user = TestUser::register().await?;
    let (first_store, second_store) = (tempfile::tempdir()?, tempfile::tempdir()?);

    // The first login creates the account's identity, which verifies that device.
    let first = user.login(&first_store.path().to_string_lossy()).await?;
    first.start_sync().await;
    wait_for_status(&first, VerificationStatus::Verified).await?;
    let second = user.login(&second_store.path().to_string_lossy()).await?;
    second.start_sync().await;
    wait_for_status(&second, VerificationStatus::Unverified).await?;
    wait_until_known(&first, &second).await?;

    // The new device asks; the first one gets the request and accepts it.
    let mut requests = first.verification_requests();
    let asking = Arc::new(second.request_self_verification().await?);
    let mut asking_states = watch_flow(&asking);
    let info = tokio::time::timeout(TIMEOUT, requests.next())
        .await?
        .ok_or("no request arrived")?;
    assert_eq!(info.device_id, second.session_data()?.device_id);
    let answering = Arc::new(first.verification(info.flow_id).await?);
    let mut answering_states = watch_flow(&answering);
    wait_for_flow(&mut answering_states, |s| {
        *s == VerificationFlowState::Requested
    })
    .await?;
    answering.accept().await?;

    // The new device starts the emoji; the other accepts; both see the same ones.
    wait_for_flow(&mut asking_states, |s| *s == VerificationFlowState::Ready).await?;
    asking.start_sas().await?;
    wait_for_flow(&mut answering_states, |s| {
        *s == VerificationFlowState::SasStarted
    })
    .await?;
    answering.accept_sas().await?;
    let is_keys =
        |s: &VerificationFlowState| matches!(s, VerificationFlowState::KeysExchanged { .. });
    let asking_emoji = wait_for_flow(&mut asking_states, is_keys).await?;
    let answering_emoji = wait_for_flow(&mut answering_states, is_keys).await?;
    assert_eq!(asking_emoji, answering_emoji);
    assert!(
        matches!(&asking_emoji, VerificationFlowState::KeysExchanged { emojis: Some(e), .. } if e.len() == 7),
        "{asking_emoji:?}"
    );

    asking.confirm().await?;
    answering.confirm().await?;
    wait_for_flow(&mut asking_states, |s| *s == VerificationFlowState::Done).await?;
    wait_for_flow(&mut answering_states, |s| *s == VerificationFlowState::Done).await?;
    wait_for_status(&second, VerificationStatus::Verified).await?;
    Ok(())
}

/// Both devices start the emoji at the same moment, as OxiTalk and Fractal do: the SDK keeps
/// one start, and the side whose start was dropped follows the one kept.
#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a test homeserver (test-infra/)"]
async fn both_devices_starting_the_emoji_still_verify() -> TestResult {
    let user = TestUser::register().await?;
    let (first_store, second_store) = (tempfile::tempdir()?, tempfile::tempdir()?);
    let first = user.login(&first_store.path().to_string_lossy()).await?;
    first.start_sync().await;
    wait_for_status(&first, VerificationStatus::Verified).await?;
    let second = user.login(&second_store.path().to_string_lossy()).await?;
    second.start_sync().await;
    wait_for_status(&second, VerificationStatus::Unverified).await?;
    wait_until_known(&first, &second).await?;

    let mut requests = first.verification_requests();
    let asking = Arc::new(second.request_self_verification().await?);
    let mut asking_states = drive_flow(&asking);
    let info = tokio::time::timeout(TIMEOUT, requests.next())
        .await?
        .ok_or("no request arrived")?;
    let answering = Arc::new(first.verification(info.flow_id).await?);
    let mut answering_states = drive_flow(&answering);
    wait_for_flow(&mut answering_states, |s| {
        *s == VerificationFlowState::Requested
    })
    .await?;
    answering.accept().await?;
    wait_for_flow(&mut asking_states, |s| *s == VerificationFlowState::Ready).await?;
    wait_for_flow(&mut answering_states, |s| {
        *s == VerificationFlowState::Ready
    })
    .await?;

    let (asked, answered) = tokio::join!(asking.start_sas(), answering.start_sas());
    asked?;
    answered?;

    let is_keys =
        |s: &VerificationFlowState| matches!(s, VerificationFlowState::KeysExchanged { .. });
    let asking_emoji = wait_for_flow(&mut asking_states, is_keys).await?;
    let answering_emoji = wait_for_flow(&mut answering_states, is_keys).await?;
    assert_eq!(asking_emoji, answering_emoji);
    asking.confirm().await?;
    answering.confirm().await?;
    wait_for_flow(&mut asking_states, |s| *s == VerificationFlowState::Done).await?;
    wait_for_flow(&mut answering_states, |s| *s == VerificationFlowState::Done).await?;
    wait_for_status(&second, VerificationStatus::Verified).await?;
    Ok(())
}

/// The recovery key verifies a new device, and its history decrypts from the key backup.
#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a test homeserver (test-infra/)"]
async fn the_recovery_key_verifies_and_restores_history() -> TestResult {
    let (user, other) = (TestUser::register().await?, TestUser::register().await?);
    let (first_store, second_store) = (tempfile::tempdir()?, tempfile::tempdir()?);

    // The first device writes a message, then sets up recovery (not in the app yet).
    let first = user.login(&first_store.path().to_string_lossy()).await?;
    first.start_sync().await;
    wait_for_status(&first, VerificationStatus::Verified).await?;
    let room_id = first
        .create_dm(format!("@{}:localhost", other.name))
        .await?;
    let timeline = first.timeline(room_id.clone()).await?;
    let mut items = watch_timeline(&timeline).await;
    timeline
        .send_text("before the new device".to_owned(), false)
        .await?;
    items
        .wait_until(|items| {
            items.iter().any(|item| {
                matches!(&item.content, TimelineItemContent::Message { event, body, .. }
                    if body == "before the new device" && event.send_state == SendState::Sent)
            })
        })
        .await?;
    let recovery_key = first.sdk().encryption().recovery().enable().await?;

    let second = user.login(&second_store.path().to_string_lossy()).await?;
    second.start_sync().await;
    wait_for_status(&second, VerificationStatus::Unverified).await?;
    let wrong = second.recover("EsTc 1234 not the key".to_owned()).await;
    assert_eq!(wrong, Err(CoreError::WrongRecoveryKey));
    second.recover(recovery_key).await?;
    wait_for_status(&second, VerificationStatus::Verified).await?;

    // The message from before this device existed decrypts.
    let timeline = second.timeline(room_id).await?;
    let mut items = watch_timeline(&timeline).await;
    timeline.paginate_back(20).await?;
    items
        .wait_until(|items| messages(items).contains(&("before the new device", true)))
        .await?;
    Ok(())
}

/// Takes section updates until one satisfies `done`.
async fn wait_for_sections(
    updates: &mut (impl Stream<Item = SectionsUpdate> + Unpin),
    what: &str,
    done: impl Fn(&SectionsUpdate) -> bool,
) -> TestResult {
    tokio::time::timeout(TIMEOUT, async {
        while let Some(update) = updates.next().await {
            if done(&update) {
                return Ok(());
            }
        }
        Err("the stream ended".into())
    })
    .await
    .map_err(|_| format!("timed out waiting for sections: {what}"))?
}

async fn wait_for_status(session: &Session, wanted: VerificationStatus) -> TestResult {
    let mut statuses = session.verification_statuses();
    tokio::time::timeout(TIMEOUT, async {
        while let Some(status) = statuses.next().await {
            if status == wanted {
                return Ok(());
            }
        }
        Err("the status stream ended")
    })
    .await
    .map_err(|_| format!("timed out waiting for {wanted:?}"))??;
    Ok(())
}

/// Waits until `session` has the keys of `other`, another device of the same user. The SDK
/// ignores a verification request from a device whose keys it doesn't have yet; a person takes
/// long enough to ask that it always has them, a test may not.
async fn wait_until_known(session: &Session, other: &Session) -> TestResult {
    let user_id = OwnedUserId::try_from(other.user_id())?;
    let device_id = OwnedDeviceId::from(other.session_data()?.device_id);
    tokio::time::timeout(TIMEOUT, async {
        loop {
            let device = session
                .sdk()
                .encryption()
                .get_device(&user_id, &device_id)
                .await?;
            if device.is_some() {
                return Ok::<_, Box<dyn Error>>(());
            }
            tokio::time::sleep(Duration::from_millis(100)).await;
        }
    })
    .await
    .map_err(|_| "the other device's keys never arrived")??;
    Ok(())
}

fn watch_flow(verification: &Arc<Verification>) -> mpsc::UnboundedReceiver<VerificationFlowState> {
    let (sender, states) = mpsc::unbounded_channel();
    let verification = Arc::clone(verification);
    tokio::spawn(async move {
        verification
            .state_updates(move |state| sender.send(state).is_ok())
            .await;
    });
    states
}

/// Like [`watch_flow`], accepting an emoji verification the other side started, as the app
/// does.
fn drive_flow(verification: &Arc<Verification>) -> mpsc::UnboundedReceiver<VerificationFlowState> {
    let (sender, states) = mpsc::unbounded_channel();
    let driven = Arc::clone(verification);
    tokio::spawn(async move {
        let accepting = Arc::clone(&driven);
        driven
            .state_updates(move |state| {
                if state == VerificationFlowState::SasStarted {
                    let accepting = Arc::clone(&accepting);
                    tokio::spawn(async move { accepting.accept_sas().await });
                }
                sender.send(state).is_ok()
            })
            .await;
    });
    states
}

async fn wait_for_flow(
    states: &mut mpsc::UnboundedReceiver<VerificationFlowState>,
    wanted: impl Fn(&VerificationFlowState) -> bool,
) -> Result<VerificationFlowState, Box<dyn Error>> {
    tokio::time::timeout(TIMEOUT, async {
        while let Some(state) = states.recv().await {
            if wanted(&state) {
                return Ok(state);
            }
            if let VerificationFlowState::Cancelled { .. } = state {
                return Err(format!("cancelled: {state:?}"));
            }
        }
        Err("the flow ended".to_owned())
    })
    .await
    .map_err(|_| "timed out waiting for the verification")?
    .map_err(Into::into)
}

/// Waits until the notification settings satisfy `done`, and returns them.
async fn wait_for_settings(
    updates: &mut (impl Stream<Item = NotificationSettingsState> + Unpin),
    what: &str,
    done: impl Fn(&NotificationSettingsState) -> bool,
) -> Result<NotificationSettingsState, Box<dyn Error>> {
    let mut last = None;
    let found = tokio::time::timeout(TIMEOUT, async {
        while let Some(state) = updates.next().await {
            if done(&state) {
                return Some(state);
            }
            last = Some(state);
        }
        None
    })
    .await;
    match found {
        Ok(Some(state)) => Ok(state),
        Ok(None) => Err("the settings stream ended".into()),
        Err(_) => Err(format!("timed out waiting until {what}; last: {last:?}").into()),
    }
}

/// Every account setting goes to the server as push rules and comes back, as Element X reads
/// them; defaults another client left inconsistent are found and fixed as Element X fixes them.
#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a test homeserver (test-infra/)"]
async fn notification_settings_round_trip() -> TestResult {
    let user = TestUser::register().await?;
    let store = tempfile::tempdir()?;
    let session = user.login(&store.path().to_string_lossy()).await?;
    session.start_sync().await;
    let mut updates = session.notification_settings_updates();

    let first = wait_for_settings(&mut updates, "the first settings arrive", |_| true).await?;
    assert_eq!(first.dm_default, RoomNotificationMode::AllMessages);
    assert_eq!(first.group_default, RoomNotificationMode::AllMessages);
    assert!(first.inconsistent.is_empty(), "{first:?}");

    session
        .set_default_notification_mode(false, RoomNotificationMode::MentionsAndKeywordsOnly)
        .await?;
    session
        .set_default_notification_mode(true, RoomNotificationMode::MentionsAndKeywordsOnly)
        .await?;
    wait_for_settings(&mut updates, "both defaults are mentions only", |s| {
        s.group_default == RoomNotificationMode::MentionsAndKeywordsOnly
            && s.dm_default == RoomNotificationMode::MentionsAndKeywordsOnly
            && s.inconsistent.is_empty()
    })
    .await?;
    assert!(
        session
            .set_default_notification_mode(true, RoomNotificationMode::Mute)
            .await
            .is_err()
    );

    session.set_room_mentions_enabled(false).await?;
    session.set_invites_enabled(false).await?;
    session
        .add_notification_keyword(" pineapple ".to_owned())
        .await?;
    wait_for_settings(&mut updates, "@room, invites and a keyword are set", |s| {
        s.room_mentions == Some(false) && s.invites == Some(false) && s.keywords == ["pineapple"]
    })
    .await?;
    // Removing a keyword that isn't there is fine.
    session
        .remove_notification_keyword("never-added".to_owned())
        .await?;
    session.set_room_mentions_enabled(true).await?;
    session.set_invites_enabled(true).await?;
    session
        .remove_notification_keyword("pineapple".to_owned())
        .await?;
    wait_for_settings(&mut updates, "they are back", |s| {
        s.room_mentions == Some(true) && s.invites == Some(true) && s.keywords.is_empty()
    })
    .await?;

    // An older client sets only the unencrypted group rule back to "All messages".
    session
        .sdk()
        .notification_settings()
        .await
        .set_default_room_notification_mode(
            IsEncrypted::No,
            IsOneToOne::No,
            matrix_sdk::notification_settings::RoomNotificationMode::AllMessages,
        )
        .await?;
    let state = wait_for_settings(&mut updates, "another client made them inconsistent", |s| {
        !s.inconsistent.is_empty()
    })
    .await?;
    assert_eq!(
        state.inconsistent,
        [InconsistentDefault {
            one_to_one: false,
            encrypted: true
        }]
    );
    assert_eq!(state.group_default, RoomNotificationMode::AllMessages);
    session.fix_inconsistent_notification_defaults().await?;
    let state = wait_for_settings(&mut updates, "they are fixed", |s| {
        s.inconsistent.is_empty()
    })
    .await?;
    assert_eq!(state.group_default, RoomNotificationMode::AllMessages);
    assert_eq!(
        state.dm_default,
        RoomNotificationMode::MentionsAndKeywordsOnly
    );
    Ok(())
}

/// The room's mode in the list follows every change, though the SDK's list doesn't send the
/// room again for it; a muted room counts no notifications while its unread count grows, and
/// one for mentions and keywords counts only those.
#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a test homeserver (test-infra/)"]
async fn muted_and_mentions_only_rooms_count_as_element_counts() -> TestResult {
    let (alice, bob, room_id, _stores) = joined_dm().await?;
    let mut bob_rooms = watch_rooms(&bob).await?;
    let room = |rooms: &[RoomSummary]| rooms.iter().find(|r| r.room_id == room_id).cloned();
    bob_rooms
        .wait_until(|rooms| room(rooms).is_some())
        .await
        .map_err(|error| format!("{error}: {:?}", room(&bob_rooms.items)))?;
    // Two members: the default is the one for direct chats, and the summary says so.
    bob_rooms
        .wait_until(|rooms| room(rooms).is_some_and(|r| r.is_one_to_one))
        .await
        .map_err(|error| format!("{error}: {:?}", room(&bob_rooms.items)))?;
    let summary = room(&bob_rooms.items).ok_or("no room")?;
    assert_eq!(summary.notification_mode, None);
    assert_eq!(
        summary.default_notification_mode,
        RoomNotificationMode::AllMessages
    );

    bob.set_room_notification_mode(room_id.clone(), Some(RoomNotificationMode::Mute))
        .await?;
    bob_rooms
        .wait_until(|rooms| {
            room(rooms).is_some_and(|r| r.notification_mode == Some(RoomNotificationMode::Mute))
        })
        .await
        .map_err(|error| format!("{error}: {:?}", room(&bob_rooms.items)))?;
    let alice_timeline = alice.timeline(room_id.clone()).await?;
    alice_timeline.send_text("one".to_owned(), false).await?;
    alice_timeline.send_text("two".to_owned(), false).await?;
    bob_rooms
        .wait_until(|rooms| room(rooms).is_some_and(|r| r.unread_count == 2))
        .await
        .map_err(|error| format!("{error}: {:?}", room(&bob_rooms.items)))?;
    let summary = room(&bob_rooms.items).ok_or("no room")?;
    assert_eq!(
        (summary.unread_notifications, summary.unread_mentions),
        (0, 0)
    );

    let bob_timeline = bob.timeline(room_id.clone()).await?;
    let mut bob_items = watch_timeline(&bob_timeline).await;
    bob_items
        .wait_until(|items| messages(items).contains(&("two", false)))
        .await?;
    bob_timeline.mark_as_read().await?;
    bob_rooms
        .wait_until(|rooms| room(rooms).is_some_and(|r| r.unread_count == 0))
        .await
        .map_err(|error| format!("{error}: {:?}", room(&bob_rooms.items)))?;

    // Mentions and keywords only: chatter doesn't notify; a keyword does, a mention
    // highlights.
    bob.add_notification_keyword("pineapple".to_owned()).await?;
    bob.set_room_notification_mode(
        room_id.clone(),
        Some(RoomNotificationMode::MentionsAndKeywordsOnly),
    )
    .await?;
    bob_rooms
        .wait_until(|rooms| {
            room(rooms).is_some_and(|r| {
                r.notification_mode == Some(RoomNotificationMode::MentionsAndKeywordsOnly)
            })
        })
        .await
        .map_err(|error| format!("{error}: {:?}", room(&bob_rooms.items)))?;
    alice_timeline
        .send_text("chatter".to_owned(), false)
        .await?;
    alice_timeline
        .send_text("I like pineapple".to_owned(), false)
        .await?;
    let bob_id: OwnedUserId = bob.user_id().try_into()?;
    let alice_room = alice
        .sdk()
        .get_room(&OwnedRoomId::try_from(room_id.clone())?)
        .ok_or("no room")?;
    // Through the send queue the timeline uses too, so it goes after the two above.
    alice_room
        .send_queue()
        .send(
            RoomMessageEventContent::text_plain("Bob, look")
                .add_mentions(Mentions::with_user_ids([bob_id]))
                .into(),
        )
        .await?;
    bob_rooms
        .wait_until(|rooms| room(rooms).is_some_and(|r| r.unread_count == 3))
        .await
        .map_err(|error| format!("{error}: {:?}", room(&bob_rooms.items)))?;
    bob_rooms
        .wait_until(|rooms| {
            room(rooms).is_some_and(|r| r.unread_notifications == 2 && r.unread_mentions == 1)
        })
        .await
        .map_err(|error| format!("{error}: {:?}", room(&bob_rooms.items)))?;

    // Back to the default.
    bob.set_room_notification_mode(room_id.clone(), None)
        .await?;
    bob_rooms
        .wait_until(|rooms| room(rooms).is_some_and(|r| r.notification_mode.is_none()))
        .await
        .map_err(|error| format!("{error}: {:?}", room(&bob_rooms.items)))?;
    Ok(())
}

/// Marking a chat unread shows on the list (and in Element); marking it read clears both the
/// mark and the count.
#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a test homeserver (test-infra/)"]
async fn chats_are_marked_unread_and_read() -> TestResult {
    let (alice, bob, room_id, _stores) = joined_dm().await?;
    let mut bob_rooms = watch_rooms(&bob).await?;
    let room = |rooms: &[RoomSummary]| rooms.iter().find(|r| r.room_id == room_id).cloned();
    // Back to the default when it is the default already: nothing to delete, no error.
    bob.set_room_notification_mode(room_id.clone(), None)
        .await?;
    bob.set_marked_unread(room_id.clone(), true).await?;
    bob_rooms
        .wait_until(|rooms| room(rooms).is_some_and(|r| r.marked_unread))
        .await
        .map_err(|error| format!("{error}: {:?}", room(&bob_rooms.items)))?;
    alice
        .timeline(room_id.clone())
        .await?
        .send_text("hello".to_owned(), false)
        .await?;
    bob_rooms
        .wait_until(|rooms| room(rooms).is_some_and(|r| r.unread_count == 1))
        .await?;
    bob.mark_room_read(room_id.clone()).await?;
    bob_rooms
        .wait_until(|rooms| room(rooms).is_some_and(|r| !r.marked_unread && r.unread_count == 0))
        .await?;
    assert!(matches!(
        bob.set_marked_unread("!nope:localhost".to_owned(), true)
            .await,
        Err(CoreError::RoomNotFound { .. })
    ));
    Ok(())
}

/// The OS notifications `session` would show, as they come.
fn watch_notifications(session: &Session) -> mpsc::UnboundedReceiver<NotificationItem> {
    let mut items = session.notification_items();
    let (sender, receiver) = mpsc::unbounded_channel();
    tokio::spawn(async move {
        while let Some(item) = items.next().await {
            if sender.send(item).is_err() {
                break;
            }
        }
    });
    receiver
}

/// The next notification: every message that shouldn't notify was sent before the one that
/// should, so one that wrongly notifies comes first and fails the test.
async fn next_notification(
    notifications: &mut mpsc::UnboundedReceiver<NotificationItem>,
) -> Result<NotificationItem, Box<dyn Error>> {
    Ok(tokio::time::timeout(TIMEOUT, notifications.recv())
        .await
        .map_err(|_| "timed out waiting for a notification")?
        .ok_or("the notifications stream ended")?)
}

/// Nothing more notifies for a while (an encrypted event may wait for its key first).
async fn no_more_notifications(
    notifications: &mut mpsc::UnboundedReceiver<NotificationItem>,
) -> TestResult {
    let more = tokio::time::timeout(Duration::from_secs(5), notifications.recv()).await;
    if let Ok(Some(item)) = more {
        return Err(format!("unexpected notification: {item:?}").into());
    }
    Ok(())
}

/// Waits until the push rules `session`'s sync judges events by (not only its settings
/// copy) give the room exactly the rules of `kinds`, so the next message meets them.
async fn wait_for_room_rules(session: &Session, room_id: &str, kinds: &[RuleKind]) -> TestResult {
    poll_until("the sync has the room's push rules", || async {
        let rules = session
            .sdk()
            .account()
            .push_rules()
            .await
            .map_err(|error| CoreError::Internal {
                message: error.to_string(),
            })?;
        let found: Vec<RuleKind> = rules
            .iter()
            .filter(|rule| rule.rule_id() == room_id)
            .filter_map(|rule| match rule {
                AnyPushRuleRef::Override(_) => Some(RuleKind::Override),
                AnyPushRuleRef::Room(_) => Some(RuleKind::Room),
                _ => None,
            })
            .collect();
        Ok(
            (found.len() == kinds.len() && kinds.iter().all(|kind| found.contains(kind)))
                .then_some(()),
        )
    })
    .await
}

/// Sends `text` mentioning `user` through the send queue the timeline uses, so it goes after
/// what the timeline sent before.
async fn send_mention(session: &Session, room_id: &str, text: &str, user: &str) -> TestResult {
    let user: OwnedUserId = user.try_into()?;
    let room = session
        .sdk()
        .get_room(&OwnedRoomId::try_from(room_id)?)
        .ok_or("no room")?;
    room.send_queue()
        .send(
            RoomMessageEventContent::text_plain(text)
                .add_mentions(Mentions::with_user_ids([user]))
                .into(),
        )
        .await?;
    Ok(())
}

/// In an encrypted DM: the other person's message notifies with its decrypted text, the
/// user's own doesn't, a muted room doesn't, and a room for mentions only notifies only for
/// the mention, which the server can't see inside the encrypted event.
#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a test homeserver (test-infra/)"]
async fn encrypted_messages_notify_by_the_push_rules() -> TestResult {
    let (alice, bob, room_id, _stores) = joined_dm().await?;
    let mut notifications = watch_notifications(&bob);
    let alice_timeline = alice.timeline(room_id.clone()).await?;

    alice_timeline
        .send_text("hello Bob".to_owned(), false)
        .await?;
    let item = next_notification(&mut notifications).await?;
    assert_eq!(item.body_preview.as_deref(), Some("hello Bob"), "{item:?}");
    assert_eq!(item.room_id, room_id);
    assert_eq!(item.sender_id, alice.user_id());
    assert!(item.event_id.is_some());
    // As the chat list marks the room: Bob's side never marks it direct on Tuwunel (seen
    // 2026-10-21), on Synapse it does.
    let bob_room = bob
        .sdk()
        .get_room(&OwnedRoomId::try_from(room_id.as_str())?)
        .ok_or("no room")?;
    assert_eq!(item.is_dm, bob_room.is_direct().await?);
    assert!(!item.is_highlight && !item.is_invite);
    assert!(item.thread_root.is_none());
    // The default rule for a direct chat rings.
    assert!(item.sound);

    // The user's own message, then messages in a muted room.
    bob.timeline(room_id.clone())
        .await?
        .send_text("from Bob".to_owned(), false)
        .await?;
    bob.set_room_notification_mode(room_id.clone(), Some(RoomNotificationMode::Mute))
        .await?;
    wait_for_room_rules(&bob, &room_id, &[RuleKind::Override]).await?;
    alice_timeline
        .send_text("while muted".to_owned(), false)
        .await?;

    // Mentions only: chatter is quiet, the mention notifies and highlights.
    bob.set_room_notification_mode(
        room_id.clone(),
        Some(RoomNotificationMode::MentionsAndKeywordsOnly),
    )
    .await?;
    wait_for_room_rules(&bob, &room_id, &[RuleKind::Room]).await?;
    alice_timeline
        .send_text("chatter".to_owned(), false)
        .await?;
    send_mention(&alice, &room_id, "Bob, look", &bob.user_id()).await?;
    let item = next_notification(&mut notifications).await?;
    assert_eq!(item.body_preview.as_deref(), Some("Bob, look"), "{item:?}");
    assert!(item.is_highlight);
    no_more_notifications(&mut notifications).await
}

/// In an unencrypted group: a message notifies with the room's name and no DM mark, a thread
/// reply names its thread, and mentions only works there too.
#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a test homeserver (test-infra/)"]
async fn group_messages_notify_with_their_thread() -> TestResult {
    let (alice_user, bob_user) = (TestUser::register().await?, TestUser::register().await?);
    let (alice_store, bob_store) = (tempfile::tempdir()?, tempfile::tempdir()?);
    let alice = alice_user
        .login(&alice_store.path().to_string_lossy())
        .await?;
    let bob = bob_user.login(&bob_store.path().to_string_lossy()).await?;
    alice.start_sync().await;
    bob.start_sync().await;
    let room_id = alice
        .create_room(NewRoom {
            name: "Open".to_owned(),
            topic: None,
            public: true,
            alias: None,
            encrypted: false,
            avatar: None,
        })
        .await?;
    bob.join(room_id.clone()).await?;
    let mut bob_rooms = watch_rooms(&bob).await?;
    bob_rooms
        .wait_until(|rooms| {
            rooms.iter().any(|r| {
                r.room_id == room_id && r.membership == Membership::Joined && r.name == "Open"
            })
        })
        .await?;
    let mut notifications = watch_notifications(&bob);
    let alice_timeline = alice.timeline(room_id.clone()).await?;

    alice_timeline
        .send_text("welcome".to_owned(), false)
        .await?;
    let item = next_notification(&mut notifications).await?;
    assert_eq!(item.body_preview.as_deref(), Some("welcome"), "{item:?}");
    assert_eq!(item.room_name, "Open");
    assert!(!item.is_dm && !item.is_highlight);
    let root = item.event_id.ok_or("no event ID")?;

    alice
        .thread_timeline(room_id.clone(), root.clone())
        .await?
        .send_text("in the thread".to_owned(), false)
        .await?;
    let item = next_notification(&mut notifications).await?;
    assert_eq!(
        item.body_preview.as_deref(),
        Some("in the thread"),
        "{item:?}"
    );
    assert_eq!(item.thread_root.as_deref(), Some(root.as_str()));

    bob.set_room_notification_mode(
        room_id.clone(),
        Some(RoomNotificationMode::MentionsAndKeywordsOnly),
    )
    .await?;
    wait_for_room_rules(&bob, &room_id, &[RuleKind::Room]).await?;
    alice_timeline
        .send_text("chatter".to_owned(), false)
        .await?;
    send_mention(&alice, &room_id, "Bob, look", &bob.user_id()).await?;
    let item = next_notification(&mut notifications).await?;
    assert_eq!(item.body_preview.as_deref(), Some("Bob, look"), "{item:?}");
    assert!(item.is_highlight);
    no_more_notifications(&mut notifications).await
}
