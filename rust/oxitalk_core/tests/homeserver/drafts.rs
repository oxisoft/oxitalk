//! Composer drafts on the test homeserver: kept per room and thread in the account's store, and
//! the message a draft answers found again, in the timeline or outside it.

use oxitalk_core::api::{
    drafts::{Draft, DraftKind, DraftPreview},
    mentions::MessagePart,
    timeline::TimelineItemContent,
};

use super::{
    TestResult, joined_dm,
    pins::{id_of, wait_sent},
    watch_timeline,
};

fn text(text: &str) -> Vec<MessagePart> {
    vec![MessagePart::Text {
        text: text.to_owned(),
    }]
}

fn body_of(item: Option<&oxitalk_core::api::timeline::TimelineItem>) -> Option<&str> {
    match &item?.content {
        TimelineItemContent::Message { body, .. } => Some(body),
        _ => None,
    }
}

#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a test homeserver (test-infra/)"]
async fn drafts_are_kept_per_room_and_thread_and_find_their_message() -> TestResult {
    let (alice, _bob, room_id, _stores) = joined_dm().await?;
    let timeline = alice.timeline(room_id.clone()).await?;
    let mut items = watch_timeline(&timeline).await;
    timeline.send_text("answer me".to_owned(), false).await?;
    timeline
        .send_text("a thread starts here".to_owned(), false)
        .await?;
    wait_sent(&mut items, &["answer me", "a thread starts here"]).await?;
    let answered = id_of(&items.items, "answer me")?;
    let root = id_of(&items.items, "a thread starts here")?;

    let room_draft = Draft {
        parts: [
            text("first line\nsecond "),
            vec![MessagePart::User {
                user_id: alice.user_id(),
                name: "Alice".to_owned(),
            }],
        ]
        .concat(),
        kind: DraftKind::Reply {
            event_id: answered.clone(),
        },
    };
    let thread_draft = Draft {
        parts: text("in the thread"),
        kind: DraftKind::NewMessage,
    };
    alice
        .save_draft(room_id.clone(), None, room_draft.clone())
        .await?;
    alice
        .save_draft(room_id.clone(), Some(root.clone()), thread_draft.clone())
        .await?;
    assert_eq!(
        alice.load_draft(room_id.clone(), None).await?,
        Some(room_draft)
    );
    assert_eq!(
        alice
            .load_draft(room_id.clone(), Some(root.clone()))
            .await?,
        Some(thread_draft)
    );
    // Only the room's own draft is in the chat list.
    assert_eq!(
        alice.draft_previews().await,
        vec![DraftPreview {
            room_id: room_id.clone(),
            text: "first line".to_owned(),
        }]
    );

    // In the chat's timeline: found there, for a reply and an edit alike.
    let found = timeline.draft_target(answered.clone(), true).await?;
    assert_eq!(body_of(found.as_ref()), Some("answer me"));
    let found = timeline.draft_target(answered.clone(), false).await?;
    assert_eq!(body_of(found.as_ref()), Some("answer me"));
    // An unknown event: none, so the app drops the banner and keeps the text.
    let gone = format!("$gone{}", &answered[1..]);
    assert_eq!(timeline.draft_target(gone.clone(), true).await?, None);

    // Not in the thread's timeline: a reply still finds it in the room, an edit doesn't.
    let thread = alice.thread_timeline(room_id.clone(), root.clone()).await?;
    let found = thread.draft_target(answered.clone(), true).await?;
    assert_eq!(body_of(found.as_ref()), Some("answer me"));
    assert_eq!(thread.draft_target(answered.clone(), false).await?, None);

    alice.clear_draft(room_id.clone(), None).await?;
    assert_eq!(alice.load_draft(room_id.clone(), None).await?, None);
    assert_eq!(alice.draft_previews().await, Vec::<DraftPreview>::new());
    assert!(
        alice
            .load_draft(room_id.clone(), Some(root.clone()))
            .await?
            .is_some()
    );
    Ok(())
}
