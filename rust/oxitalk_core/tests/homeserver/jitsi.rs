//! Jitsi conferences as Element widgets on the test homeserver: one added by another member
//! shows live and its removal ends it; one added before the user joined (so in no timeline
//! the user synced) is read from the server; adding widgets takes a moderator.

use std::error::Error;

use matrix_sdk::ruma::{OwnedRoomId, events::room::message::RoomMessageEventContent};
use oxitalk_core::api::{
    jitsi::RoomJitsi, room_list::Membership, rooms::NewRoom, session::Session,
};
use serde_json::{Value, json};
use tokio::sync::mpsc;

use super::{TIMEOUT, TestResult, TestUser, watch_rooms};

const WIDGETS: &str = "im.vector.modular.widgets";

/// The content Element Web writes for a video conference on `jitsi.example.org`.
fn element_widget(conference: &str) -> Value {
    json!({
        "type": "jitsi",
        "url": format!("https://app.element.io/jitsi.html?confId={conference}#conferenceDomain=$domain&conferenceId=$conferenceId&isAudioOnly=$isAudioOnly"),
        "name": "Jitsi",
        "data": {
            "conferenceId": conference,
            "roomName": "Team",
            "isAudioOnly": false,
            "isVideoChannel": false,
            "domain": "jitsi.example.org",
        },
    })
}

fn watch_jitsi(
    session: &Session,
    room_id: &str,
) -> Result<mpsc::UnboundedReceiver<RoomJitsi>, Box<dyn Error>> {
    let (sender, receiver) = mpsc::unbounded_channel();
    session
        .jitsi_conference_updates(room_id.to_owned(), move |jitsi| sender.send(jitsi).is_ok())?;
    Ok(receiver)
}

async fn next_matching(
    receiver: &mut mpsc::UnboundedReceiver<RoomJitsi>,
    what: &str,
    wanted: impl Fn(&RoomJitsi) -> bool,
) -> Result<RoomJitsi, Box<dyn Error>> {
    let mut last = None;
    let found = tokio::time::timeout(TIMEOUT, async {
        while let Some(value) = receiver.recv().await {
            if wanted(&value) {
                return Some(value);
            }
            last = Some(value);
        }
        None
    })
    .await;
    match found {
        Ok(Some(value)) => Ok(value),
        _ => Err(format!("timed out waiting for {what}; last: {last:?}").into()),
    }
}

fn sdk_room(session: &Session, room_id: &str) -> Result<matrix_sdk::Room, Box<dyn Error>> {
    let id: OwnedRoomId = room_id.try_into()?;
    Ok(session.sdk().get_room(&id).ok_or("no room")?)
}

/// Alice's new group room with Bob in it, as a plain member.
async fn team(
    before_bob: impl AsyncFnOnce(&Session, &str) -> TestResult,
) -> Result<(Session, Session, String, Vec<tempfile::TempDir>), Box<dyn Error>> {
    let (alice_user, bob_user) = (TestUser::register().await?, TestUser::register().await?);
    let stores = vec![tempfile::tempdir()?, tempfile::tempdir()?];
    let alice = alice_user
        .login(&stores[0].path().to_string_lossy())
        .await?;
    let bob = bob_user.login(&stores[1].path().to_string_lossy()).await?;
    alice.start_sync().await;
    bob.start_sync().await;
    let room_id = alice
        .create_room(NewRoom {
            name: "Team".to_owned(),
            topic: None,
            public: false,
            alias: None,
            encrypted: false,
            avatar: None,
        })
        .await?;
    before_bob(&alice, &room_id).await?;
    alice.invite(room_id.clone(), bob.user_id()).await?;
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

#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a test homeserver (test-infra/)"]
async fn a_jitsi_conference_added_by_another_member_shows_until_it_is_removed() -> TestResult {
    let (alice, bob, room_id, _stores) = team(async |_, _| Ok(())).await?;
    let mut bob_jitsi = watch_jitsi(&bob, &room_id)?;
    next_matching(&mut bob_jitsi, "no conference yet", |j| {
        j.conferences.is_empty()
    })
    .await?;

    // Only the room's moderators may add widgets (state_default 50), as in Element.
    assert!(alice.can_start_jitsi_conference(room_id.clone()).await?);
    assert!(!bob.can_start_jitsi_conference(room_id.clone()).await?);

    // Alice starts a conference the way Element Web does.
    sdk_room(&alice, &room_id)?
        .send_state_event_raw(WIDGETS, "aliceWidget", element_widget("JitsiAbcdef"))
        .await?;
    let shown = next_matching(&mut bob_jitsi, "Alice's conference", |j| {
        !j.conferences.is_empty()
    })
    .await?;
    let conference = shown.current().ok_or("no current conference")?;
    assert_eq!(conference.widget_id, "aliceWidget");
    assert_eq!(conference.domain, "jitsi.example.org");
    assert_eq!(conference.conference_id, "JitsiAbcdef");
    assert_eq!(conference.join_url, "https://jitsi.example.org/JitsiAbcdef");
    assert_eq!(conference.creator_user_id, alice.user_id());
    assert!(!conference.audio_only);
    assert!(!conference.needs_sign_in);

    // On a Jitsi with Matrix sign-in, Bob's link carries a JWT with his OpenID token.
    let link = bob
        .jitsi_join_url(
            room_id.clone(),
            "jitsi.example.org".to_owned(),
            "EFQWEYZ2PAXHS".to_owned(),
            false,
            true,
        )
        .await?;
    let jwt = link
        .strip_prefix("https://jitsi.example.org/EFQWEYZ2PAXHS?jwt=")
        .ok_or(format!("not a signed-in link: {link}"))?;
    let payload = jwt.split('.').nth(1).ok_or("not a JWT")?;
    let payload: Value = serde_json::from_slice(&base64::Engine::decode(
        &base64::engine::general_purpose::URL_SAFE_NO_PAD,
        payload,
    )?)?;
    assert_eq!(payload["context"]["matrix"]["room_id"], room_id.as_str());
    let server = bob.user_id();
    let server = server.split_once(':').ok_or("no server name")?.1;
    assert_eq!(payload["context"]["matrix"]["server_name"], server);
    assert!(
        payload["context"]["matrix"]["token"]
            .as_str()
            .is_some_and(|token| !token.is_empty())
    );
    assert_eq!(
        bob.jitsi_join_url(
            room_id.clone(),
            "jitsi.example.org".to_owned(),
            "JitsiAbcdef".to_owned(),
            true,
            false,
        )
        .await?,
        "https://jitsi.example.org/JitsiAbcdef#config.startAudioOnly=true"
    );

    // She removes it ("Remove for everyone"): the conference is over for Bob.
    alice
        .end_jitsi_conference(room_id.clone(), "aliceWidget".to_owned())
        .await?;
    next_matching(&mut bob_jitsi, "the conference removed", |j| {
        j.conferences.is_empty()
    })
    .await?;
    assert_eq!(
        bob.jitsi_conferences(room_id).await?.conferences,
        Vec::new()
    );
    Ok(())
}

#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a test homeserver (test-infra/)"]
async fn a_jitsi_conference_started_before_the_user_joined_is_read_from_the_server() -> TestResult {
    // The widget is in the room's state before Bob joins and far behind the newest messages,
    // so no sync of Bob's brings it (the room list asks for no widget state).
    let (_alice, bob, room_id, _stores) = team(async |alice: &Session, room_id: &str| {
        let room = sdk_room(alice, room_id).map_err(|e| e.to_string())?;
        room.send_state_event_raw(WIDGETS, "earlier", element_widget("JitsiEarlier"))
            .await?;
        for n in 0..5 {
            room.send(RoomMessageEventContent::text_plain(format!("message {n}")))
                .await?;
        }
        Ok(())
    })
    .await?;
    let jitsi = bob.jitsi_conferences(room_id.clone()).await?;
    let conference = jitsi
        .current()
        .ok_or("the earlier conference isn't found")?;
    assert_eq!(conference.widget_id, "earlier");
    assert_eq!(conference.conference_id, "JitsiEarlier");

    // The live stream has it too, once it asked the server.
    let mut bob_jitsi = watch_jitsi(&bob, &room_id)?;
    next_matching(&mut bob_jitsi, "the earlier conference, live", |j| {
        j.current().is_some_and(|c| c.widget_id == "earlier")
    })
    .await?;
    Ok(())
}
