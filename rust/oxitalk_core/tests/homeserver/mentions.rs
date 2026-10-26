//! Mentions, and other people (profile, ignoring, reporting), on the test homeserver.

use std::{error::Error, time::Duration};

use futures_util::StreamExt;
use matrix_sdk::{
    Client,
    ruma::{
        OwnedEventId, OwnedRoomId,
        api::Direction,
        api::client::{message::get_message_events, room::get_room_event},
    },
};
use oxitalk_core::api::{
    mentions::MessagePart,
    rich_text::RichSpan,
    rooms::NewRoom,
    session::Session,
    timeline::{TimelineItem, TimelineItemContent},
    verification::VerificationFlowState,
};
use serde_json::{Value, json};

use super::{
    TestResult, TestUser, event_of, homeserver_url, joined_dm, poll_until, watch_rooms,
    watch_timeline,
};
use crate::support::TIMEOUT;

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

/// A plain SDK client of `user`, to read events as the server has them.
async fn raw_client(user: &TestUser) -> Result<Client, Box<dyn Error>> {
    let client = Client::builder()
        .homeserver_url(homeserver_url())
        .build()
        .await?;
    client
        .matrix_auth()
        .login_username(&user.name, &user.password)
        .send()
        .await?;
    Ok(client)
}

/// The event `event_id` as the server has it.
async fn raw_event(
    client: &Client,
    room_id: &str,
    event_id: &str,
) -> Result<Value, Box<dyn Error>> {
    let room: OwnedRoomId = room_id.try_into()?;
    let event: OwnedEventId = event_id.try_into()?;
    let response = client
        .send(get_room_event::v3::Request::new(room, event))
        .await?;
    Ok(serde_json::from_str(response.event.json().get())?)
}

/// The latest events of the room, newest first, as the server has them.
async fn raw_latest(client: &Client, room_id: &str) -> Result<Vec<Value>, Box<dyn Error>> {
    let room: OwnedRoomId = room_id.try_into()?;
    let mut request = get_message_events::v3::Request::new(room, Direction::Backward);
    request.limit = 30u32.into();
    let response = client.send(request).await?;
    response
        .chunk
        .iter()
        .map(|event| Ok(serde_json::from_str(event.json().get())?))
        .collect()
}

/// The event ID of the message whose body is `body`, once the server has it.
async fn sent_id(
    items: &mut crate::support::Watched<TimelineItem, oxitalk_core::api::timeline::TimelineDiff>,
    body: &str,
) -> Result<String, Box<dyn Error>> {
    items
        .wait_until(|items| event_of(items, body).is_some_and(|e| e.event_id.is_some()))
        .await?;
    Ok(event_of(&items.items, body)
        .and_then(|event| event.event_id.clone())
        .ok_or("no event ID")?)
}

/// A public, unencrypted room of Alice's (so a plain client can read its events) that Bob
/// joined.
async fn public_room(
    alice: &Session,
    bob: &Session,
    alias: &str,
) -> Result<String, Box<dyn Error>> {
    let room_id = alice
        .create_room(NewRoom {
            name: "Mentions".to_owned(),
            topic: None,
            public: true,
            alias: Some(alias.to_owned()),
            encrypted: false,
            avatar: None,
        })
        .await?;
    bob.join_by_address(room_id.clone()).await?;
    let mut alice_rooms = watch_rooms(alice).await?;
    alice_rooms
        .wait_until(|rooms| rooms.iter().any(|r| r.room_id == room_id))
        .await?;
    // Bob's membership reaches Alice's store.
    poll_until("Bob is a member for Alice", || async {
        let members = alice.room_members(room_id.clone()).await?;
        Ok(members
            .iter()
            .any(|m| m.user_id == bob.user_id() && !m.invited)
            .then_some(()))
    })
    .await?;
    Ok(room_id)
}

/// Alice and Bob in a public room of Alice's, a plain client of Bob's to read the events as the
/// server has them, and the stores to keep.
struct Mentioning {
    alice: Session,
    bob: Session,
    raw: Client,
    room_id: String,
    bob_id: String,
    _stores: [tempfile::TempDir; 2],
}

async fn mentioning(alias_prefix: &str) -> Result<Mentioning, Box<dyn Error>> {
    let (alice_user, bob_user) = (TestUser::register().await?, TestUser::register().await?);
    let stores = [tempfile::tempdir()?, tempfile::tempdir()?];
    let alice = alice_user
        .login(&stores[0].path().to_string_lossy())
        .await?;
    let bob = bob_user.login(&stores[1].path().to_string_lossy()).await?;
    alice.start_sync().await;
    bob.start_sync().await;
    let alias = format!("{alias_prefix}{}", alice_user.name);
    let room_id = public_room(&alice, &bob, &alias).await?;
    let bob_id = bob.user_id();
    let raw = raw_client(&bob_user).await?;
    Ok(Mentioning {
        alice,
        bob,
        raw,
        room_id,
        bob_id,
        _stores: stores,
    })
}

/// A pill goes as the name in the body, a `matrix.to` link in the HTML and an intentional
/// mention; a reply also mentions the replied-to sender; `@room` mentions the room, which only
/// Alice (the admin) may; `#` lists the rooms with their address.
#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a test homeserver (test-infra/)"]
async fn mentions_go_as_pills_and_intentional_mentions() -> TestResult {
    let Mentioning {
        alice,
        bob,
        raw,
        room_id,
        bob_id,
        _stores,
    } = mentioning("m").await?;
    let alias = "m";
    assert!(alice.can_mention_room(room_id.clone()).await);
    assert!(!bob.can_mention_room(room_id.clone()).await);
    let rooms = alice.mention_rooms();
    let listed = rooms
        .iter()
        .find(|room| room.room_id == room_id)
        .ok_or("the room isn't listed for #")?;
    assert_eq!(listed.name, "Mentions");
    assert!(
        listed
            .alias
            .as_deref()
            .is_some_and(|a| a.starts_with(&format!("#{alias}user"))),
        "{listed:?}"
    );

    let timeline = alice.timeline(room_id.clone()).await?;
    let mut items = watch_timeline(&timeline).await;
    // A pill with markdown on.
    timeline
        .send_message(
            vec![text("hi **"), user(&bob_id, "Bob"), text("**!")],
            None,
            true,
        )
        .await?;
    let first = sent_id(&mut items, "hi **Bob**!").await?;
    let event = raw_event(&raw, &room_id, &first).await?;
    let content = &event["content"];
    assert_eq!(content["body"], "hi **Bob**!");
    assert_eq!(content["format"], "org.matrix.custom.html");
    let link = format!("<a href=\"https://matrix.to/#/{bob_id}\">Bob</a>");
    assert!(
        content["formatted_body"]
            .as_str()
            .is_some_and(|html| html.contains(&format!("<strong>{link}</strong>"))),
        "{content}"
    );
    assert_eq!(content["m.mentions"], json!({ "user_ids": [bob_id] }));
    // Alice sees her own pill as a mention.
    let mention = first_mention(&items.items);
    let mention = mention.ok_or("no mention in Alice's own message")?;
    assert_eq!(mention.text, "Bob");
    assert_eq!(mention.mention.as_deref(), Some(bob_id.as_str()));

    // Without markdown, no pills: no HTML, but empty intentional mentions.
    timeline
        .send_message(vec![text("plain *text*")], None, false)
        .await?;
    let plain = sent_id(&mut items, "plain *text*").await?;
    let content = raw_event(&raw, &room_id, &plain).await?["content"].clone();
    assert_eq!(content.get("formatted_body"), None);
    assert_eq!(content["m.mentions"], json!({}));

    // Bob writes; Alice answers without a pill, which mentions him as the replied-to sender.
    let bob_timeline = bob.timeline(room_id.clone()).await?;
    bob_timeline
        .send_message(vec![text("question?")], None, false)
        .await?;
    let question = sent_id(&mut items, "question?").await?;
    timeline
        .send_message(vec![text("answer")], Some(question.clone()), false)
        .await?;
    let answer = sent_id(&mut items, "answer").await?;
    let content = raw_event(&raw, &room_id, &answer).await?["content"].clone();
    assert_eq!(
        content["m.relates_to"]["m.in_reply_to"]["event_id"],
        question
    );
    assert_eq!(content["m.mentions"], json!({ "user_ids": [bob_id] }));

    // @room, and a room pill.
    timeline
        .send_message(
            vec![
                MessagePart::AtRoom,
                text(" see "),
                MessagePart::Room {
                    room_id: room_id.clone(),
                    alias: listed.alias.clone(),
                    name: listed.name.clone(),
                },
            ],
            None,
            false,
        )
        .await?;
    let room_alias = listed.alias.clone().ok_or("no alias")?;
    let at_room = sent_id(&mut items, &format!("@room see {room_alias}")).await?;
    let content = raw_event(&raw, &room_id, &at_room).await?["content"].clone();
    assert_eq!(content["m.mentions"], json!({ "room": true }));
    assert!(
        content["formatted_body"]
            .as_str()
            .is_some_and(|html| html.starts_with("@room see <a href=\"https://matrix.to/#/%23")),
        "{content}"
    );

    Ok(())
}

/// An edit keeps the new content's mentions and notifies only the newly mentioned; a thread
/// reply carries its mentions too.
#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a test homeserver (test-infra/)"]
async fn edits_and_thread_replies_keep_their_mentions() -> TestResult {
    let Mentioning {
        alice,
        bob,
        raw,
        room_id,
        bob_id,
        _stores,
    } = mentioning("e").await?;
    let timeline = alice.timeline(room_id.clone()).await?;
    let mut items = watch_timeline(&timeline).await;
    timeline
        .send_message(vec![text("hi "), user(&bob_id, "Bob")], None, false)
        .await?;
    let first = sent_id(&mut items, "hi Bob").await?;
    let bob_timeline = bob.timeline(room_id.clone()).await?;
    bob_timeline
        .send_message(vec![text("question?")], None, false)
        .await?;
    let question = sent_id(&mut items, "question?").await?;

    // Edit the first message: Bob was mentioned already, so the edit doesn't notify him again,
    // but its new content keeps the mention.
    timeline
        .edit_message(
            first.clone(),
            vec![text("hello "), user(&bob_id, "Bob")],
            false,
            false,
        )
        .await?;
    let edit = poll_until("the edit is on the server", || async {
        let latest = raw_latest(&raw, &room_id).await.map_err(|e| {
            oxitalk_core::api::error::CoreError::Internal {
                message: e.to_string(),
            }
        })?;
        Ok(latest.into_iter().find(|event| {
            event["content"]["m.relates_to"]["rel_type"] == "m.replace"
                && event["content"]["m.relates_to"]["event_id"] == first.as_str()
        }))
    })
    .await?;
    let content = &edit["content"];
    assert_eq!(content["m.new_content"]["body"], "hello Bob");
    assert_eq!(
        content["m.new_content"]["m.mentions"],
        json!({ "user_ids": [bob_id] })
    );
    assert_eq!(content["m.mentions"], json!({}));
    items
        .wait_until(|items| event_of(items, "hello Bob").is_some())
        .await?;

    // A pill in a thread reply.
    let thread = alice
        .thread_timeline(room_id.clone(), question.clone())
        .await?;
    let mut thread_items = watch_timeline(&thread).await;
    thread
        .send_message(vec![user(&bob_id, "Bob"), text(" in thread")], None, false)
        .await?;
    let in_thread = sent_id(&mut thread_items, "Bob in thread").await?;
    let content = raw_event(&raw, &room_id, &in_thread).await?["content"].clone();
    assert_eq!(content["m.relates_to"]["rel_type"], "m.thread");
    assert_eq!(content["m.relates_to"]["event_id"], question);
    assert_eq!(content["m.mentions"]["user_ids"], json!([bob_id]));
    Ok(())
}

/// Bob's profile as Alice sees it; reporting him and one of his messages is accepted; and
/// verifying him starts a request in their direct chat.
#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a test homeserver (test-infra/)"]
async fn users_and_messages_are_reported_and_verification_asked() -> TestResult {
    let (alice, bob, room_id, _stores) = joined_dm().await?;
    let bob_id = bob.user_id();

    let profile = alice
        .user_profile(bob_id.clone(), Some(room_id.clone()))
        .await?;
    assert_eq!(profile.user_id, bob_id);
    assert_eq!(profile.dm_room_id.as_deref(), Some(room_id.as_str()));
    assert!(!profile.ignored);
    assert_ne!(profile.verified, Some(true));
    // Without the room, from the server.
    let profile = alice.user_profile(bob_id.clone(), None).await?;
    assert_eq!(profile.user_id, bob_id);
    assert!(alice.user_profile("bob".to_owned(), None).await.is_err());

    let timeline = alice.timeline(room_id.clone()).await?;
    let mut items = watch_timeline(&timeline).await;
    let bob_timeline = bob.timeline(room_id.clone()).await?;
    bob_timeline
        .send_message(vec![text("before")], None, false)
        .await?;
    let before = sent_id(&mut items, "before").await?;

    // Reports.
    alice
        .report_event(room_id.clone(), before.clone(), Some("rude".to_owned()))
        .await?;
    alice
        .report_user(bob_id.clone(), Some("spam".to_owned()))
        .await?;
    alice.report_user(bob_id.clone(), None).await?;

    // Verify: the request goes to Bob in the direct chat.
    let verification = alice.verify_user(bob_id.clone()).await?;
    let (sender, mut states) = tokio::sync::mpsc::unbounded_channel();
    let follow = async {
        verification
            .state_updates(move |state| sender.send(state).is_ok())
            .await;
    };
    let first_state = async {
        tokio::time::timeout(TIMEOUT, states.recv())
            .await
            .ok()
            .flatten()
    };
    let (_, state) = tokio::join!(
        tokio::time::timeout(Duration::from_secs(3), follow),
        first_state
    );
    assert_eq!(state, Some(VerificationFlowState::Created));
    let mut bob_items = watch_timeline(&bob_timeline).await;
    bob_timeline.paginate_back(20).await?;
    assert!(
        bob_items
            .holds_within(TIMEOUT, |items| items.iter().any(|item| matches!(
                &item.content,
                TimelineItemContent::OtherEvent { event } | TimelineItemContent::Message { event, .. }
                    if event.sender == alice.user_id() && !event.is_own
                        && item_is_request(item)
            )))
            .await?,
        "Bob got no verification request"
    );
    verification.cancel().await?;
    Ok(())
}

/// Ignoring Bob hides his new messages until Alice unignores him, on her list of ignored users
/// as it changes.
#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a test homeserver (test-infra/)"]
async fn ignored_users_are_hidden_until_unignored() -> TestResult {
    let (alice, bob, room_id, _stores) = joined_dm().await?;
    let bob_id = bob.user_id();
    let bob_timeline = bob.timeline(room_id.clone()).await?;
    // Ignore.
    let mut lists = alice.ignored_user_lists();
    let first = tokio::time::timeout(TIMEOUT, lists.next())
        .await?
        .ok_or("no list")?;
    assert_eq!(first, Vec::<String>::new());
    alice.ignore_user(bob_id.clone()).await?;
    let list = tokio::time::timeout(TIMEOUT, lists.next())
        .await?
        .ok_or("no list")?;
    assert_eq!(list, std::slice::from_ref(&bob_id));
    assert_eq!(alice.ignored_users().await?, std::slice::from_ref(&bob_id));
    assert!(alice.user_profile(bob_id.clone(), None).await?.ignored);
    assert!(alice.ignore_user(alice.user_id()).await.is_err());

    // The timeline is cleared and reloaded; Bob's message from while he is ignored never shows.
    let timeline = alice.timeline(room_id.clone()).await?;
    let mut items = watch_timeline(&timeline).await;
    bob_timeline
        .send_message(vec![text("while ignored")], None, false)
        .await?;
    let mut bob_items = watch_timeline(&bob_timeline).await;
    sent_id(&mut bob_items, "while ignored").await?;
    timeline.paginate_back(20).await?;
    assert!(
        !items
            .holds_within(Duration::from_secs(5), |items| event_of(
                items,
                "while ignored"
            )
            .is_some())
            .await?,
        "a message of an ignored user showed"
    );

    alice.unignore_user(bob_id.clone()).await?;
    let list = tokio::time::timeout(TIMEOUT, lists.next())
        .await?
        .ok_or("no list")?;
    assert_eq!(list, Vec::<String>::new());
    let timeline = alice.timeline(room_id.clone()).await?;
    let mut items = watch_timeline(&timeline).await;
    bob_timeline
        .send_message(vec![text("after")], None, false)
        .await?;
    sent_id(&mut items, "after").await?;

    Ok(())
}

/// The first mention pill in a timeline.
fn first_mention(items: &[TimelineItem]) -> Option<RichSpan> {
    items.iter().find_map(|item| match &item.content {
        TimelineItemContent::Message {
            formatted: Some(blocks),
            ..
        } => blocks
            .iter()
            .flat_map(|block| &block.spans)
            .find(|span| span.mention.is_some())
            .cloned(),
        _ => None,
    })
}

/// Whether the item is a verification request: the timeline shows them as other events (or,
/// in older SDKs, as a message with the fallback body).
fn item_is_request(item: &TimelineItem) -> bool {
    match &item.content {
        TimelineItemContent::OtherEvent { .. } => true,
        TimelineItemContent::Message { body, .. } => body.contains("verif"),
        _ => false,
    }
}
