//! Searching a chat on the device, on the test homeserver.

use oxitalk_core::api::{
    search::SearchResults,
    timeline::{MediaKind, TimelineItemContent},
};

use super::{
    TestResult, event_of, joined_dm,
    pins::{id_of, public_room_with, wait_sent},
    poll_until, watch_timeline,
};

fn texts(results: &SearchResults) -> Vec<&str> {
    results.hits.iter().map(|hit| hit.text.as_str()).collect()
}

/// Search finds the decrypted messages of an encrypted chat as they are after edits, leaves
/// deleted ones out, and finds files by name.
#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a test homeserver (test-infra/)"]
async fn search_finds_decrypted_edited_messages_and_files() -> TestResult {
    let (alice, bob, room_id, _stores) = joined_dm().await?;
    let timeline = alice.timeline(room_id.clone()).await?;
    let mut items = watch_timeline(&timeline).await;
    for body in ["the blue whale", "a red fox", "secret blue"] {
        timeline.send_text(body.to_owned(), false).await?;
    }
    timeline
        .send_data(
            b"%PDF-1.4 plan".to_vec(),
            "Holiday-Plan.pdf".to_owned(),
            "application/pdf".to_owned(),
            None,
            false,
            false,
        )
        .await?;
    wait_sent(&mut items, &["the blue whale", "a red fox", "secret blue"]).await?;
    let fox = id_of(&items.items, "a red fox")?;
    let whale = id_of(&items.items, "the blue whale")?;
    let secret = id_of(&items.items, "secret blue")?;
    timeline
        .edit(fox.clone(), "a red and blue fox".to_owned(), false, false)
        .await?;
    timeline.redact(secret, None).await?;

    let bob_timeline = bob.timeline(room_id.clone()).await?;
    let mut bob_items = watch_timeline(&bob_timeline).await;
    bob_items
        .wait_until(|items| {
            event_of(items, "a red and blue fox").is_some()
                && items.iter().any(|item| {
                    matches!(&item.content, TimelineItemContent::Media { media, .. }
                        if media.filename == "Holiday-Plan.pdf")
                })
                && items
                    .iter()
                    .any(|item| matches!(item.content, TimelineItemContent::Redacted { .. }))
        })
        .await?;

    // The store is written as the events arrive; ask until it has caught up.
    let blue = poll_until(
        "Bob's search has the edit and not the deleted message",
        || {
            let (bob, room_id) = (&bob, room_id.clone());
            async move {
                let results = bob.search_room(room_id, "BLUE".to_owned(), 50).await?;
                Ok(
                    (texts(&results) == ["a red and blue fox", "the blue whale"])
                        .then_some(results),
                )
            }
        },
    )
    .await?;
    assert_eq!(blue.total, 2);
    assert_eq!(blue.hits[0].event_id, fox);
    assert_eq!(blue.hits[1].event_id, whale);
    assert_eq!(blue.hits[1].sender, alice.user_id());
    assert!(blue.hits.iter().all(|hit| hit.thread_root.is_none()));
    assert!(blue.searched >= 3, "{}", blue.searched);

    let file = bob
        .search_room(room_id.clone(), "holiday".to_owned(), 50)
        .await?;
    assert_eq!(file.hits.len(), 1);
    assert_eq!(file.hits[0].filename.as_deref(), Some("Holiday-Plan.pdf"));
    assert_eq!(file.hits[0].media_kind, Some(MediaKind::File));
    let secret = bob
        .search_room(room_id.clone(), "secret".to_owned(), 50)
        .await?;
    assert_eq!(secret.total, 0);
    let old = bob.search_room(room_id, "red fox".to_owned(), 50).await?;
    assert_eq!(old.total, 0, "the text before the edit was found");
    Ok(())
}

/// A member who joined late has only the latest messages; loading the history lets search
/// find every one.
#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a test homeserver (test-infra/)"]
async fn search_reaches_back_by_loading_the_history() -> TestResult {
    let bodies: Vec<_> = (0..60).map(|i| format!("needle {i}")).collect();
    let (_alice, bob, room_id, _ids, _stores) = public_room_with(&bodies).await?;
    let before = bob
        .search_room(room_id.clone(), "needle".to_owned(), 500)
        .await?;
    assert!(before.total < 60, "{}", before.total);

    let mut start = false;
    for _ in 0..20 {
        start = bob.search_load_older(room_id.clone(), 30).await?;
        if start {
            break;
        }
    }
    assert!(start, "never reached the start of the room");
    let after = bob
        .search_room(room_id.clone(), "needle".to_owned(), 500)
        .await?;
    assert_eq!(after.total, 60);
    assert_eq!(after.hits[0].text, "needle 59");
    assert_eq!(after.hits[59].text, "needle 0");
    let limited = bob.search_room(room_id, "needle 1".to_owned(), 5).await?;
    // needle 1 and 10 to 19.
    assert_eq!(limited.total, 11);
    assert_eq!(limited.hits.len(), 5);
    Ok(())
}
