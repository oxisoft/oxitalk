//! Calls on the test homeserver: membership, ringing, declining and the media keys, as Element
//! Call has them on a server without sticky or delayed events. Only the Matrix side, which runs
//! on the plain test servers; the LiveKit token needs the RTC pod (`test-infra/rtc/up.sh`) and
//! runs with `OXITALK_TEST_RTC=1`.

use std::error::Error;

use oxitalk_core::api::{
    calls::{
        ActiveCall, CallIntent, CallMediaKey, CallNotify, IncomingCallEnd, IncomingCallUpdate,
        RoomCall,
    },
    rooms::NewRoom,
    session::Session,
};
use tokio::sync::mpsc;

use super::{TIMEOUT, TestResult, TestUser, joined_dm, watch_rooms};
use oxitalk_core::api::room_list::Membership;

/// The call service written in memberships when the test runs without an SFU.
const NO_MEDIA_SERVICE: &str = "http://localhost:8091";

fn watch_call(
    session: &Session,
    room_id: &str,
) -> Result<mpsc::UnboundedReceiver<RoomCall>, Box<dyn Error>> {
    let (sender, receiver) = mpsc::unbounded_channel();
    session.room_call_updates(room_id.to_owned(), move |call| sender.send(call).is_ok())?;
    Ok(receiver)
}

fn watch_incoming(session: &Session) -> mpsc::UnboundedReceiver<IncomingCallUpdate> {
    let (sender, receiver) = mpsc::unbounded_channel();
    session.incoming_call_updates(move |update| sender.send(update).is_ok());
    receiver
}

fn watch_keys(call: &ActiveCall) -> mpsc::UnboundedReceiver<CallMediaKey> {
    let (sender, receiver) = mpsc::unbounded_channel();
    call.media_key_updates(move |key| sender.send(key).is_ok());
    receiver
}

/// The next value `wanted` accepts, within the test timeout.
async fn next_matching<T: std::fmt::Debug>(
    receiver: &mut mpsc::UnboundedReceiver<T>,
    what: &str,
    wanted: impl Fn(&T) -> bool,
) -> Result<T, Box<dyn Error>> {
    tokio::time::timeout(TIMEOUT, async {
        loop {
            let value = receiver.recv().await.ok_or("the stream ended")?;
            if wanted(&value) {
                return Ok::<_, Box<dyn Error>>(value);
            }
        }
    })
    .await
    .map_err(|_| format!("timed out waiting for {what}"))?
}

fn devices(call: &RoomCall) -> Vec<String> {
    call.participants
        .iter()
        .map(|p| p.identity.clone())
        .collect()
}

/// The types of the room's call notifications, as the user reads them (decrypted).
async fn notification_types(user: &Session, room_id: &str) -> Result<Vec<String>, Box<dyn Error>> {
    let room_id: ruma::OwnedRoomId = room_id.try_into()?;
    let room = user.sdk().get_room(&room_id).ok_or("no room")?;
    let messages = room
        .messages(matrix_sdk::room::MessagesOptions::backward())
        .await?;
    Ok(messages
        .chunk
        .iter()
        .filter_map(|event| event.raw().get_field::<String>("type").ok().flatten())
        .filter(|kind| kind.contains("rtc.notification"))
        .collect())
}

async fn join(
    session: &Session,
    room_id: &str,
    notify: CallNotify,
) -> Result<ActiveCall, Box<dyn Error>> {
    Ok(session
        .join_call_with(
            room_id.to_owned(),
            CallIntent::Video,
            notify,
            Some(NO_MEDIA_SERVICE.to_owned()),
        )
        .await?)
}

#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a test homeserver (test-infra/)"]
async fn a_ringing_call_is_answered_with_keys_both_ways_and_ends() -> TestResult {
    let (alice, bob, room_id, _stores) = joined_dm().await?;
    let mut bob_rings = watch_incoming(&bob);
    let mut bob_call = watch_call(&bob, &room_id)?;
    let mut alice_call = watch_call(&alice, &room_id)?;
    next_matching(&mut bob_call, "no call yet", |call| !call.is_active()).await?;

    // Alice starts a video call and rings Bob.
    let alice_in = join(&alice, &room_id, CallNotify::Ring).await?;
    let alice_identity = alice_in.identity();
    assert!(alice_identity.starts_with(&format!("{}:", alice.user_id())));
    let ring = next_matching(&mut bob_rings, "the ring", |update| {
        matches!(update, IncomingCallUpdate::Ringing { .. })
    })
    .await?;
    let IncomingCallUpdate::Ringing { call: ring } = ring else {
        return Err("not a ring".into());
    };
    assert_eq!(ring.room_id, room_id);
    assert_eq!(ring.sender_id, alice.user_id());
    assert!(ring.ring, "a direct chat rings");
    assert_eq!(ring.intent, Some(CallIntent::Video));
    // One notification, of the type Element Call reads: two would show and ring twice.
    assert_eq!(
        notification_types(&bob, &room_id).await?,
        ["org.matrix.msc4075.rtc.notification"]
    );
    let seen = next_matching(&mut bob_call, "Alice in the call", |call| {
        devices(call) == [alice_identity.clone()]
    })
    .await?;
    assert_eq!(seen.intent, Some(CallIntent::Video));
    assert_eq!(seen.service_url.as_deref(), Some(NO_MEDIA_SERVICE));
    assert!(seen.participants[0].is_own_user.eq(&false));

    // Alice's first key is hers at once.
    let mut alice_keys = watch_keys(&alice_in);
    let alice_first = next_matching(&mut alice_keys, "Alice's own key", |key| key.is_own).await?;
    assert_eq!((alice_first.index, alice_first.key.len()), (0, 16));
    assert_eq!(alice_first.identity, alice_identity);

    // Bob answers: the ring stops, and each gets the other's key, Olm-encrypted.
    let bob_in = join(&bob, &room_id, CallNotify::None).await?;
    let bob_identity = bob_in.identity();
    let stopped = next_matching(&mut bob_rings, "the ring to stop", |update| {
        matches!(update, IncomingCallUpdate::Ended { .. })
    })
    .await?;
    assert!(
        matches!(
            stopped,
            IncomingCallUpdate::Ended {
                reason: IncomingCallEnd::Answered,
                ..
            }
        ),
        "{stopped:?}"
    );
    let mut bob_keys = watch_keys(&bob_in);
    let bob_own = next_matching(&mut bob_keys, "Bob's own key", |key| key.is_own).await?;
    let alice_at_bob = next_matching(&mut bob_keys, "Alice's key at Bob", |key| {
        key.identity == alice_identity
    })
    .await?;
    assert_eq!(alice_at_bob.key, alice_first.key);
    assert!(!alice_at_bob.is_own);
    let bob_at_alice = next_matching(&mut alice_keys, "Bob's key at Alice", |key| {
        key.identity == bob_identity
    })
    .await?;
    assert_eq!(bob_at_alice.key, bob_own.key);
    next_matching(&mut alice_call, "both in the call", |call| {
        call.participants.len() == 2
    })
    .await?;

    // Bob hangs up: Alice sees him gone and makes a new key (index 1).
    bob_in.leave().await?;
    next_matching(&mut alice_call, "Bob gone", |call| {
        devices(call) == [alice_identity.clone()]
    })
    .await?;
    let rotated = next_matching(&mut alice_keys, "Alice's new key", |key| {
        key.is_own && key.index == 1
    })
    .await?;
    assert_ne!(rotated.key, alice_first.key);

    // Alice hangs up: nobody is in the call any more, for either.
    alice_in.leave().await?;
    next_matching(&mut bob_call, "the call over", |call| !call.is_active()).await?;
    next_matching(&mut alice_call, "the call over", |call| !call.is_active()).await?;
    Ok(())
}

#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a test homeserver (test-infra/)"]
async fn declining_stops_the_ring_and_hanging_up_stops_another() -> TestResult {
    let (alice, bob, room_id, _stores) = joined_dm().await?;
    let mut bob_rings = watch_incoming(&bob);

    let first = join(&alice, &room_id, CallNotify::Ring).await?;
    let IncomingCallUpdate::Ringing { call: ring } =
        next_matching(&mut bob_rings, "the ring", |u| {
            matches!(u, IncomingCallUpdate::Ringing { .. })
        })
        .await?
    else {
        return Err("not a ring".into());
    };
    bob.decline_call(room_id.clone(), ring.notification_event_id.clone())
        .await?;
    let declined = next_matching(&mut bob_rings, "the ring to stop", |u| {
        matches!(u, IncomingCallUpdate::Ended { .. })
    })
    .await?;
    assert!(
        matches!(
            &declined,
            IncomingCallUpdate::Ended { reason: IncomingCallEnd::Declined, notification_event_id, .. }
                if *notification_event_id == ring.notification_event_id
        ),
        "{declined:?}"
    );
    first.leave().await?;

    // A second call, given up by the caller before Bob answers.
    let mut bob_call = watch_call(&bob, &room_id)?;
    next_matching(&mut bob_call, "no call", |call| !call.is_active()).await?;
    let second = join(&alice, &room_id, CallNotify::Ring).await?;
    next_matching(&mut bob_rings, "the second ring", |u| {
        matches!(u, IncomingCallUpdate::Ringing { call } if call.notification_event_id != ring.notification_event_id)
    })
    .await?;
    second.leave().await?;
    let ended = next_matching(&mut bob_rings, "the second ring to stop", |u| {
        matches!(u, IncomingCallUpdate::Ended { .. })
    })
    .await?;
    assert!(
        matches!(
            ended,
            IncomingCallUpdate::Ended {
                reason: IncomingCallEnd::CallEnded,
                ..
            }
        ),
        "{ended:?}"
    );
    Ok(())
}

#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a test homeserver (test-infra/)"]
async fn members_of_a_new_room_may_join_its_calls_and_are_notified() -> TestResult {
    let (alice_user, bob_user) = (TestUser::register().await?, TestUser::register().await?);
    let stores = [tempfile::tempdir()?, tempfile::tempdir()?];
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
            encrypted: true,
            avatar: None,
        })
        .await?;
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
    let mut alice_rings = watch_incoming(&alice);

    // Bob, a plain member (power level 0), starts the room's call; Alice is notified, not rung.
    let bob_in = join(&bob, &room_id, CallNotify::Notify).await?;
    let IncomingCallUpdate::Ringing { call } =
        next_matching(&mut alice_rings, "the notification", |u| {
            matches!(u, IncomingCallUpdate::Ringing { .. })
        })
        .await?
    else {
        return Err("not a ring".into());
    };
    assert!(!call.ring, "a group is notified, not rung");
    assert_eq!(call.sender_id, bob.user_id());
    bob_in.leave().await?;
    Ok(())
}

#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs a test homeserver (test-infra/)"]
async fn a_membership_left_behind_by_a_crash_is_taken_back() -> TestResult {
    let (alice, bob, room_id, _stores) = joined_dm().await?;
    let mut bob_call = watch_call(&bob, &room_id)?;
    next_matching(&mut bob_call, "no call", |call| !call.is_active()).await?;
    // What a killed app leaves: this device's membership, and nothing here keeping it up.
    let device = alice.sdk().device_id().ok_or("no device")?.to_string();
    let room = alice
        .sdk()
        .get_room(<&ruma::RoomId>::try_from(room_id.as_str())?)
        .ok_or("no room")?;
    room.send_state_event_raw(
        "org.matrix.msc3401.call.member",
        &format!("_{}_{device}_m.call", alice.user_id()),
        serde_json::json!({
            "application": "m.call", "call_id": "", "scope": "m.room", "device_id": device,
            "expires": 1_800_000,
            "focus_active": { "type": "livekit", "focus_selection": "multi_sfu" },
            "foci_preferred": [{ "type": "livekit", "livekit_service_url": NO_MEDIA_SERVICE }],
        }),
    )
    .await?;
    next_matching(&mut bob_call, "the stale membership", RoomCall::is_active).await?;
    // The app starts again and watches the room's call: it takes the membership back.
    let mut alice_call = watch_call(&alice, &room_id)?;
    next_matching(&mut bob_call, "the stale membership gone", |call| {
        !call.is_active()
    })
    .await?;
    next_matching(&mut alice_call, "the stale membership gone", |call| {
        !call.is_active()
    })
    .await?;
    Ok(())
}

#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs the RTC pod (test-infra/rtc/up.sh) and OXITALK_TEST_RTC=1"]
async fn the_call_service_gives_a_livekit_token() -> TestResult {
    if std::env::var("OXITALK_TEST_RTC").as_deref() != Ok("1") {
        return Ok(());
    }
    let (alice, _bob, room_id, _stores) = joined_dm().await?;
    let services = alice.call_services().await?;
    assert_eq!(services, [NO_MEDIA_SERVICE]);
    let call = alice
        .join_call(room_id.clone(), CallIntent::Audio, CallNotify::None)
        .await?;
    assert_eq!(call.livekit_url(), "ws://localhost:7890");
    // The token's subject is the LiveKit identity Element Call expects.
    let payload = call
        .livekit_token()
        .split('.')
        .nth(1)
        .ok_or("not a JWT")?
        .to_owned();
    let claims: serde_json::Value =
        serde_json::from_slice(&base64_url_decode(&payload).ok_or("not base64")?)?;
    assert_eq!(claims["sub"], call.identity());
    assert_eq!(claims["video"]["roomJoin"], true);
    call.leave().await?;
    Ok(())
}

fn base64_url_decode(text: &str) -> Option<Vec<u8>> {
    const ALPHABET: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
    let mut bits: u32 = 0;
    let mut count = 0;
    let mut out = Vec::new();
    for byte in text.bytes() {
        let value = u32::try_from(ALPHABET.iter().position(|&c| c == byte)?).ok()?;
        bits = (bits << 6) | value;
        count += 6;
        if count >= 8 {
            count -= 8;
            out.push(u8::try_from((bits >> count) & 0xff).ok()?);
        }
    }
    Some(out)
}
