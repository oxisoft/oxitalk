//! Jitsi group calls as Element Web and Desktop start them, for servers that offer no
//! MatrixRTC (LiveKit) call service but a Jitsi server in their `.well-known`.
//!
//! - **The conference** is a room widget: room state `im.vector.modular.widgets`, the state key
//!   is the widget's ID, content `{type: "jitsi", url, name, data: {conferenceId, domain,
//!   isAudioOnly, roomName, isVideoChannel, auth?}}`. Element also accepts the type `m.jitsi`;
//!   a widget with empty content (or without `type` and `url`) was removed: the conference is
//!   over. Element treats any Jitsi widget in the room as an ongoing conference. Wire format:
//!   element-web `src/utils/WidgetUtils.ts` (`setRoomWidget`, `addJitsiWidget`,
//!   `getRoomWidgets`), `src/widgets/WidgetType.ts`; older widgets without `data` carry the
//!   conference in the URL (`?confId=`, element-web `stores/widgets/WidgetMessaging.ts`
//!   `rawData`, whose domain for them is `meet.element.io`) or in its fragment
//!   (`#conferenceDomain=…&conferenceId=…&isAudioOnly=…`).
//! - **The server's Jitsi** is `preferredDomain` of `io.element.jitsi` or the older
//!   `im.vector.riot.jitsi` in `https://<server name>/.well-known/matrix/client` (element-web
//!   `src/widgets/Jitsi.ts`). A Jitsi server that wants a Matrix sign-in says so in
//!   `https://<domain>/.well-known/element/jitsi` (`auth: "openidtoken-jwt"`).
//! - **Joining** happens outside the app for now: `https://<domain>/<conferenceId>` opens in the
//!   browser, or in the Jitsi Meet app where it takes such links.
//! - **Signing in** (`openidtoken-jwt`, prosody-mod-auth-matrix-user-verification): the
//!   conference ID is the room ID in base32, and the join link carries `?jwt=`, a JWT made here
//!   as Element's wrapper makes it (element-web `src/vector/jitsi/index.ts` `createJWTToken`):
//!   HS256 with the key `notused` (Prosody checks the Matrix OpenID token inside with the
//!   homeserver, not the signature), `iss`/`sub` the domain, `aud` `https://<domain>`, `room`
//!   `*`, `context.matrix` the OpenID token, room ID and server name, `context.user` the name.
//!   jitsi.securium.ch wants it (2026-11-03: anonymous XMPP refused with "JWT token must be
//!   provided with OpenID token and room ID").
//!
//! The sync asks for no widget state, and with sliding sync (MSC4186) the SDK stores only the
//! state it asked for, not state events in the timeline; the room list's `required_state` is
//! fixed inside matrix-sdk-ui. So a room's widgets come from one sliding sync request for that
//! room's widgets only, when the room is opened, and then from the timeline's widget events
//! (event handlers see them). The chat list can't tell which rooms have a conference.

use std::{collections::HashMap, time::Duration};

use base64::{Engine, engine::general_purpose::URL_SAFE_NO_PAD};
use flutter_rust_bridge::frb;
use matrix_sdk::{
    Client, Room,
    deserialized_responses::RawAnySyncOrStrippedState,
    reqwest::{self, Url},
    ruma::{
        MilliSecondsSinceUnixEpoch, OwnedUserId,
        api::client::account::request_openid_token,
        events::{AnySyncStateEvent, StateEventType},
        serde::Raw,
    },
};
use serde_json::{Value, json};
use tokio::sync::mpsc;

use super::{
    error::{CoreError, parse_id},
    session::Session,
};
use crate::frb_generated::StreamSink;

/// The room state event of a room's widgets (Element's, not yet `m.widget`).
pub(crate) const WIDGETS_TYPE: &str = "im.vector.modular.widgets";
/// The widget types of a Jitsi conference: Element writes the legacy one, accepts both.
const JITSI_TYPES: [&str; 2] = ["jitsi", "m.jitsi"];
/// The domain of a widget that names none (element-web `WidgetMessaging.rawData`).
const V1_DOMAIN: &str = "meet.element.io";
/// The `.well-known/matrix/client` keys of the server's Jitsi, newest first.
const WELL_KNOWN_KEYS: [&str; 2] = ["io.element.jitsi", "im.vector.riot.jitsi"];
/// The connection of the one-off sliding sync request that reads a room's widgets.
const WIDGETS_CONN_ID: &str = "oxitalk-widgets";
const REQUEST_TIMEOUT: Duration = Duration::from_secs(10);
/// The sign-in of a Jitsi server with Matrix user verification, as Element names it.
const OPENID_JWT: &str = "openidtoken-jwt";
/// The JWT's key: Prosody doesn't check it (element-web `createJWTToken`).
const JWT_KEY: &[u8] = b"notused";

/// A Jitsi conference going on in a room, as an Element widget says.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct JitsiConference {
    pub room_id: String,
    /// The widget's ID, its state key.
    pub widget_id: String,
    /// The Jitsi server, e.g. `meet.example.org`.
    pub domain: String,
    pub conference_id: String,
    /// Started as a voice call.
    pub audio_only: bool,
    /// Who added the widget.
    pub creator_user_id: String,
    /// Their name in the room, if they have one.
    pub creator_name: Option<String>,
    /// When the widget was added, in ms since the Unix epoch.
    pub started_at_ms: i64,
    /// The conference in a browser or the Jitsi Meet app, without a sign-in.
    pub join_url: String,
    /// The Jitsi server wants a Matrix sign-in (`openidtoken-jwt`): join with
    /// [`Session::jitsi_join_url`], which adds it.
    pub needs_sign_in: bool,
}

/// The Jitsi conferences of a room, newest first. Empty: none.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RoomJitsi {
    pub room_id: String,
    pub conferences: Vec<JitsiConference>,
}

impl RoomJitsi {
    /// The conference to show and join: the newest.
    #[frb(sync)]
    #[must_use]
    pub fn current(&self) -> Option<JitsiConference> {
        self.conferences.first().cloned()
    }
}

/// What a Jitsi widget's state event says.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct JitsiWidget {
    pub(crate) widget_id: String,
    pub(crate) sender: String,
    pub(crate) origin_server_ts: i64,
    pub(crate) domain: String,
    pub(crate) conference_id: String,
    pub(crate) audio_only: bool,
    pub(crate) auth: Option<String>,
}

/// The parameters of a URL's query and of its fragment (where Element's wrapper URL keeps
/// them), the query first. Template placeholders (`$domain`) are left out.
fn url_params(url: &Url) -> Vec<(String, String)> {
    let mut params: Vec<(String, String)> = url.query_pairs().into_owned().collect();
    if let Some(fragment) = url.fragment()
        && let Ok(parsed) = Url::parse(&format!("http://fragment/?{fragment}"))
    {
        params.extend(parsed.query_pairs().into_owned());
    }
    params.retain(|(_, value)| !value.is_empty() && !value.starts_with('$'));
    params
}

fn param<'a>(params: &'a [(String, String)], names: &[&str]) -> Option<&'a str> {
    names.iter().find_map(|name| {
        params
            .iter()
            .find(|(key, _)| key == name)
            .map(|(_, value)| value.as_str())
    })
}

/// A plain host name (or `host:port`), so that it makes the join URL's host and nothing more.
fn valid_domain(domain: &str) -> Option<String> {
    let url = Url::parse(&format!("https://{domain}/")).ok()?;
    let host = url.host_str()?;
    let expected = match url.port() {
        Some(port) => format!("{host}:{port}"),
        None => host.to_owned(),
    };
    (expected.eq_ignore_ascii_case(domain) && url.username().is_empty()).then_some(expected)
}

/// Reads a widget state event (`state_key`, `sender`, `origin_server_ts`, `content`). `None`
/// for anything but a Jitsi conference: another widget, a removed one (empty content), one
/// without a conference ID or with a domain that isn't a host name.
pub(crate) fn parse_jitsi_widget(event: &Value) -> Option<JitsiWidget> {
    if event
        .get("type")
        .and_then(Value::as_str)
        .is_some_and(|kind| kind != WIDGETS_TYPE)
    {
        return None;
    }
    let content = event.get("content")?.as_object()?;
    let kind = content.get("type")?.as_str()?;
    let url = content.get("url")?.as_str()?;
    // Element shows a widget only with both (`WidgetUtils.getRoomWidgets`).
    if !JITSI_TYPES.contains(&kind) || url.is_empty() {
        return None;
    }
    let data = content.get("data").and_then(Value::as_object);
    let text = |key: &str| {
        data.and_then(|data| data.get(key))
            .and_then(Value::as_str)
            .filter(|value| !value.is_empty() && !value.starts_with('$'))
            .map(ToOwned::to_owned)
    };
    let params = Url::parse(url)
        .map(|url| url_params(&url))
        .unwrap_or_default();
    let conference_id = text("conferenceId")
        .or_else(|| param(&params, &["confId", "conferenceId"]).map(ToOwned::to_owned))?;
    let domain = text("domain")
        .or_else(|| param(&params, &["conferenceDomain"]).map(ToOwned::to_owned))
        .unwrap_or_else(|| V1_DOMAIN.to_owned());
    let audio_only = match data.and_then(|data| data.get("isAudioOnly")) {
        Some(Value::Bool(audio_only)) => *audio_only,
        Some(Value::String(audio_only)) => audio_only == "true",
        _ => param(&params, &["isAudioOnly", "isAudioConf"]) == Some("true"),
    };
    Some(JitsiWidget {
        widget_id: event.get("state_key")?.as_str()?.to_owned(),
        sender: event.get("sender")?.as_str()?.to_owned(),
        origin_server_ts: event.get("origin_server_ts")?.as_i64()?,
        domain: valid_domain(&domain)?,
        conference_id,
        audio_only,
        auth: text("auth").or_else(|| param(&params, &["auth"]).map(ToOwned::to_owned)),
    })
}

/// `https://<domain>/<conference>`, which the browser and the Jitsi Meet app open; a voice
/// conference starts without video (Jitsi's `config.startAudioOnly`).
///
/// # Errors
///
/// [`CoreError::Internal`] for a domain that isn't a host name.
pub(crate) fn join_url(
    domain: &str,
    conference_id: &str,
    audio_only: bool,
) -> Result<String, CoreError> {
    let host = valid_domain(domain)
        .ok_or_else(|| CoreError::internal(&format!("not a Jitsi domain: {domain}")))?;
    let mut url = Url::parse(&format!("https://{host}/")).map_err(|e| CoreError::internal(&e))?;
    url.path_segments_mut()
        .map_err(|()| CoreError::internal(&"no path"))?
        .clear()
        .push(conference_id);
    if audio_only {
        url.set_fragment(Some("config.startAudioOnly=true"));
    }
    Ok(url.to_string())
}

/// The server's Jitsi domain in its `.well-known/matrix/client`.
pub(crate) fn parse_jitsi_well_known(body: &Value) -> Option<String> {
    WELL_KNOWN_KEYS
        .iter()
        .find_map(|key| valid_domain(body.get(key)?.get("preferredDomain")?.as_str()?.trim()))
}

/// The widget events that are in force: for each state key the newest of the two sources.
pub(crate) fn merge_widget_events(stored: Vec<Value>, fetched: &[Value]) -> Vec<Value> {
    fn key_and_time(event: &Value) -> Option<(String, i64)> {
        Some((
            event.get("state_key")?.as_str()?.to_owned(),
            event.get("origin_server_ts")?.as_i64()?,
        ))
    }
    let mut newest: HashMap<String, (i64, Value)> = HashMap::new();
    // The store first: at the same time, it wins.
    for event in stored.into_iter().chain(fetched.iter().cloned()) {
        let Some((key, time)) = key_and_time(&event) else {
            continue;
        };
        match newest.get(&key) {
            Some((known, _)) if *known >= time => {}
            _ => {
                newest.insert(key, (time, event));
            }
        }
    }
    newest.into_values().map(|(_, event)| event).collect()
}

/// The Jitsi widgets in force, newest first.
pub(crate) fn jitsi_widgets(events: &[Value]) -> Vec<JitsiWidget> {
    let mut widgets: Vec<JitsiWidget> = events.iter().filter_map(parse_jitsi_widget).collect();
    widgets.sort_by(|a, b| {
        b.origin_server_ts
            .cmp(&a.origin_server_ts)
            .then_with(|| a.widget_id.cmp(&b.widget_id))
    });
    widgets
}

/// `len` random characters of `alphabet`.
fn random_string(alphabet: &[u8], len: usize) -> Result<String, CoreError> {
    let alphabet_len = u8::try_from(alphabet.len()).map_err(|e| CoreError::internal(&e))?;
    // Bytes at or above the last whole multiple are dropped, so every character is as likely.
    let limit = 256 - 256 % u16::from(alphabet_len);
    let mut out = String::with_capacity(len);
    while out.len() < len {
        let mut bytes = [0_u8; 32];
        getrandom::fill(&mut bytes).map_err(|error| CoreError::internal(&error))?;
        for byte in bytes {
            if u16::from(byte) < limit && out.len() < len {
                out.push(char::from(alphabet[usize::from(byte % alphabet_len)]));
            }
        }
    }
    Ok(out)
}

const LOWERCASE: &[u8] = b"abcdefghijklmnopqrstuvwxyz";
const ALPHANUMERIC: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";

/// A new conference ID as Element makes one for a server without sign-in: `Jitsi` and 24
/// random lowercase letters, the first capitalised (`JitsiAbcdef…`).
pub(crate) fn new_conference_id() -> Result<String, CoreError> {
    let letters = random_string(LOWERCASE, 24)?;
    let (first, rest) = letters.split_at(1);
    Ok(format!("Jitsi{}{rest}", first.to_ascii_uppercase()))
}

/// The widget event's content for a new conference. The URL is the conference itself:
/// Element renders Jitsi widgets with its own wrapper from `data` whatever the URL, and other
/// clients that open a widget's URL land in the conference.
pub(crate) fn widget_content(
    domain: &str,
    conference_id: &str,
    audio_only: bool,
    room_name: Option<&str>,
    auth: Option<&str>,
) -> Result<Value, CoreError> {
    let mut data = json!({
        "conferenceId": conference_id,
        "isAudioOnly": audio_only,
        "isVideoChannel": false,
        "domain": domain,
    });
    if let Some(object) = data.as_object_mut() {
        if let Some(name) = room_name {
            object.insert("roomName".to_owned(), json!(name));
        }
        if let Some(auth) = auth {
            object.insert("auth".to_owned(), json!(auth));
        }
    }
    Ok(json!({
        "type": "jitsi",
        "url": join_url(domain, conference_id, false)?,
        "name": "Jitsi",
        "data": data,
    }))
}

/// RFC 4648 base32, upper case, without padding (Element: rfc4648 `base32.stringify` with
/// `pad: false`).
pub(crate) fn base32(bytes: &[u8]) -> String {
    const ALPHABET: &[u8; 32] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
    let mut out = String::with_capacity(bytes.len().div_ceil(5) * 8);
    let mut buffer: u32 = 0;
    let mut bits = 0;
    for byte in bytes {
        buffer = (buffer << 8) | u32::from(*byte);
        bits += 8;
        while bits >= 5 {
            bits -= 5;
            out.push(char::from(ALPHABET[((buffer >> bits) & 31) as usize]));
        }
    }
    if bits > 0 {
        out.push(char::from(ALPHABET[((buffer << (5 - bits)) & 31) as usize]));
    }
    out
}

/// The conference ID Element uses on a Jitsi with Matrix sign-in: the room ID in base32, which
/// the server reads back to check that the user is in the room.
pub(crate) fn signed_in_conference_id(room_id: &str) -> String {
    base32(room_id.as_bytes())
}

/// The JWT Element's Jitsi wrapper makes for a Jitsi with Matrix sign-in.
pub(crate) fn jitsi_jwt(
    domain: &str,
    room_id: &str,
    openid_token: &str,
    server_name: &str,
    display_name: Option<&str>,
) -> String {
    let mut user = serde_json::Map::new();
    if let Some(name) = display_name {
        user.insert("name".to_owned(), json!(name));
    }
    let header = json!({"alg": "HS256", "typ": "JWT"});
    let payload = json!({
        "iss": domain,
        "sub": domain,
        "aud": format!("https://{domain}"),
        "room": "*",
        "context": {
            "matrix": {
                "token": openid_token,
                "room_id": room_id,
                "server_name": server_name,
            },
            "user": user,
        },
    });
    let signed = format!(
        "{}.{}",
        URL_SAFE_NO_PAD.encode(header.to_string()),
        URL_SAFE_NO_PAD.encode(payload.to_string())
    );
    let key = ring::hmac::Key::new(ring::hmac::HMAC_SHA256, JWT_KEY);
    let signature = ring::hmac::sign(&key, signed.as_bytes());
    format!("{signed}.{}", URL_SAFE_NO_PAD.encode(signature.as_ref()))
}

/// [`join_url`] with the sign-in `jwt` in its query.
pub(crate) fn signed_in_join_url(
    domain: &str,
    conference_id: &str,
    audio_only: bool,
    jwt: &str,
) -> Result<String, CoreError> {
    let mut url = Url::parse(&join_url(domain, conference_id, audio_only)?)
        .map_err(|error| CoreError::internal(&error))?;
    url.query_pairs_mut().append_pair("jwt", jwt);
    Ok(url.to_string())
}

fn now_ms() -> i64 {
    i64::from(MilliSecondsSinceUnixEpoch::now().get())
}

/// The room's widget events in the store.
async fn stored_widget_events(room: &Room) -> Vec<Value> {
    let Ok(events) = room
        .get_state_events(StateEventType::from(WIDGETS_TYPE))
        .await
    else {
        return Vec::new();
    };
    events
        .into_iter()
        .filter_map(|event| match event {
            RawAnySyncOrStrippedState::Sync(raw) => raw.deserialize_as::<Value>().ok(),
            RawAnySyncOrStrippedState::Stripped(_) => None,
        })
        .collect()
}

async fn conferences(room: &Room, events: &[Value]) -> RoomJitsi {
    let mut conferences = Vec::new();
    for widget in jitsi_widgets(events) {
        let creator_name = match parse_id::<OwnedUserId>(&widget.sender) {
            Ok(user) => match room.get_member_no_sync(&user).await {
                Ok(Some(member)) => member.display_name().map(ToOwned::to_owned),
                _ => None,
            },
            Err(_) => None,
        };
        let Ok(url) = join_url(&widget.domain, &widget.conference_id, widget.audio_only) else {
            continue;
        };
        conferences.push(JitsiConference {
            room_id: room.room_id().to_string(),
            widget_id: widget.widget_id,
            domain: widget.domain,
            conference_id: widget.conference_id,
            audio_only: widget.audio_only,
            creator_user_id: widget.sender,
            creator_name,
            started_at_ms: widget.origin_server_ts,
            join_url: url,
            needs_sign_in: widget.auth.as_deref() == Some(OPENID_JWT),
        });
    }
    RoomJitsi {
        room_id: room.room_id().to_string(),
        conferences,
    }
}

/// The room's widget events as the server has them now: one sliding sync request on a
/// connection of its own, for this room's widgets only (the app's sync asks for none). Empty
/// when the server doesn't answer; nothing is stored.
async fn fetch_widget_events(client: &Client, room_id: &str) -> Vec<Value> {
    match try_fetch_widget_events(client, room_id).await {
        Ok(events) => events,
        Err(error) => {
            tracing::info!(%error, "couldn't read the room's widgets from the server");
            Vec::new()
        }
    }
}

async fn try_fetch_widget_events(client: &Client, room_id: &str) -> Result<Vec<Value>, CoreError> {
    let token = client.access_token().ok_or(CoreError::SessionExpired)?;
    let mut url = client.homeserver();
    url.path_segments_mut()
        .map_err(|()| CoreError::internal(&"the homeserver URL can't have a path"))?
        .pop_if_empty()
        .extend([
            "_matrix",
            "client",
            "unstable",
            "org.matrix.simplified_msc3575",
            "sync",
        ]);
    let body = json!({
        "conn_id": WIDGETS_CONN_ID,
        "room_subscriptions": {
            room_id: {
                "required_state": [[WIDGETS_TYPE, "*"]],
                "timeline_limit": 0,
            },
        },
    });
    let response = client
        .http_client()
        .post(url)
        .bearer_auth(token)
        .header(reqwest::header::CONTENT_TYPE, "application/json")
        .body(body.to_string())
        .timeout(REQUEST_TIMEOUT)
        .send()
        .await
        .map_err(|error| CoreError::Network {
            message: error.to_string(),
        })?;
    if !response.status().is_success() {
        return Err(CoreError::internal(&format!(
            "sliding sync answered {}",
            response.status()
        )));
    }
    let body: Value = serde_json::from_slice(
        &response
            .bytes()
            .await
            .map_err(|error| CoreError::internal(&error))?,
    )
    .map_err(|error| CoreError::internal(&error))?;
    Ok(widget_events_of(&body, room_id))
}

/// The widget events of `room_id` in a sliding sync response.
pub(crate) fn widget_events_of(body: &Value, room_id: &str) -> Vec<Value> {
    body.get("rooms")
        .and_then(|rooms| rooms.get(room_id))
        .and_then(|room| room.get("required_state"))
        .and_then(Value::as_array)
        .map(|events| {
            events
                .iter()
                .filter(|event| event.get("type").and_then(Value::as_str) == Some(WIDGETS_TYPE))
                .cloned()
                .collect()
        })
        .unwrap_or_default()
}

/// `GET url` and the Jitsi domain in it: `Ok(None)` when the document is missing or names
/// none, `Err` when the server can't be reached.
pub(crate) async fn fetch_jitsi_domain(
    http: &reqwest::Client,
    url: &str,
) -> Result<Option<String>, CoreError> {
    let response = http
        .get(url)
        .timeout(REQUEST_TIMEOUT)
        .send()
        .await
        .map_err(|error| CoreError::Network {
            message: error.to_string(),
        })?;
    if !response.status().is_success() {
        return Ok(None);
    }
    let body: Value = response
        .bytes()
        .await
        .ok()
        .and_then(|bytes| serde_json::from_slice(&bytes).ok())
        .unwrap_or(Value::Null);
    Ok(parse_jitsi_well_known(&body))
}

/// The sign-in a Jitsi server wants (`https://<domain>/.well-known/element/jitsi`), `None`
/// when it wants none or doesn't say.
async fn jitsi_auth(http: &reqwest::Client, domain: &str) -> Option<String> {
    let response = http
        .get(format!("https://{domain}/.well-known/element/jitsi"))
        .timeout(REQUEST_TIMEOUT)
        .send()
        .await
        .ok()?;
    if !response.status().is_success() {
        return None;
    }
    let body: Value = serde_json::from_slice(&response.bytes().await.ok()?).ok()?;
    body.get("auth")?.as_str().map(ToOwned::to_owned)
}

impl Session {
    /// The Jitsi server this account's homeserver names for group calls
    /// (`.well-known/matrix/client`, `io.element.jitsi` or `im.vector.riot.jitsi`
    /// `preferredDomain`), e.g. `meet.example.org`; `None` when it names none. Asked once per
    /// session.
    ///
    /// # Errors
    ///
    /// [`CoreError::SessionExpired`], or [`CoreError::Network`] when the server can't be
    /// reached (not kept: the next call asks again).
    pub async fn jitsi_domain(&self) -> Result<Option<String>, CoreError> {
        if let Some(known) = self.jitsi_domain.get() {
            return Ok(known.clone());
        }
        let user = self.client.user_id().ok_or(CoreError::SessionExpired)?;
        let url = format!("https://{}/.well-known/matrix/client", user.server_name());
        let domain = fetch_jitsi_domain(self.client.http_client(), &url).await?;
        // Two asking at once: the first answer stays.
        let _ = self.jitsi_domain.set(domain.clone());
        Ok(domain)
    }

    /// The room's Jitsi conferences now, from the store and the server.
    ///
    /// # Errors
    ///
    /// [`CoreError::InvalidId`] or [`CoreError::RoomNotFound`].
    pub async fn jitsi_conferences(&self, room_id: String) -> Result<RoomJitsi, CoreError> {
        let room = self.room(&room_id)?;
        let fetched = fetch_widget_events(&self.client, &room_id).await;
        let events = merge_widget_events(stored_widget_events(&room).await, &fetched);
        Ok(conferences(&room, &events).await)
    }

    /// Sends the room's Jitsi conferences as the store knows them (usually none), then as the
    /// server has them, then after every widget event the sync brings for the room.
    ///
    /// # Errors
    ///
    /// [`CoreError::InvalidId`] or [`CoreError::RoomNotFound`].
    #[allow(
        clippy::unused_async,
        clippy::unused_async_trait_impl,
        reason = "async so flutter_rust_bridge runs it on its tokio runtime, which spawn needs"
    )]
    pub async fn subscribe_jitsi_conferences(
        &self,
        room_id: String,
        sink: StreamSink<RoomJitsi>,
    ) -> Result<(), CoreError> {
        self.jitsi_conference_updates(room_id, move |jitsi| sink.add(jitsi).is_ok())
    }

    /// Like [`Self::subscribe_jitsi_conferences`], for Rust callers: `emit` gets each state and
    /// returns `false` to stop. Must run on a tokio runtime.
    ///
    /// # Errors
    ///
    /// As [`Self::jitsi_conferences`].
    #[frb(ignore)]
    pub fn jitsi_conference_updates(
        &self,
        room_id: String,
        emit: impl Fn(RoomJitsi) -> bool + Send + 'static,
    ) -> Result<(), CoreError> {
        let room = self.room(&room_id)?;
        let client = self.client.clone();
        // The sync stores no widget state (it asks for none), but hands the timeline's state
        // events to event handlers: the widget events that come while the room is followed.
        let (sender, mut received) = mpsc::unbounded_channel::<Value>();
        let handler = self.client.add_room_event_handler(
            room.room_id(),
            move |event: Raw<AnySyncStateEvent>| {
                let sender = sender.clone();
                async move {
                    let is_widget = event.get_field::<String>("type").ok().flatten().as_deref()
                        == Some(WIDGETS_TYPE);
                    if let Some(event) = is_widget
                        .then(|| event.deserialize_as::<Value>().ok())
                        .flatten()
                    {
                        let _ = sender.send(event);
                    }
                }
            },
        );
        let guard = self.client.event_handler_drop_guard(handler);
        self.spawn(async move {
            let _guard = guard;
            let mut known = stored_widget_events(&room).await;
            let mut last = conferences(&room, &known).await;
            if !emit(last.clone()) {
                return;
            }
            known = merge_widget_events(known, &fetch_widget_events(&client, &room_id).await);
            loop {
                let now = conferences(&room, &known).await;
                if now != last {
                    last = now.clone();
                    if !emit(now) {
                        return;
                    }
                }
                let Some(event) = received.recv().await else {
                    return;
                };
                let mut new = vec![event];
                while let Ok(event) = received.try_recv() {
                    new.push(event);
                }
                known = merge_widget_events(known, &new);
            }
        });
        Ok(())
    }

    /// Whether the user may add a Jitsi conference to the room (send its widget state event).
    ///
    /// # Errors
    ///
    /// [`CoreError::InvalidId`] or [`CoreError::RoomNotFound`].
    pub async fn can_start_jitsi_conference(&self, room_id: String) -> Result<bool, CoreError> {
        let room = self.room(&room_id)?;
        Ok(room.power_levels().await.is_ok_and(|levels| {
            levels.user_can_send_state(room.own_user_id(), StateEventType::from(WIDGETS_TYPE))
        }))
    }

    /// Starts a Jitsi conference in the room as Element does (a Jitsi widget on the server's
    /// Jitsi domain, a new random conference), or returns the one going on there.
    ///
    /// # Errors
    ///
    /// [`CoreError::Forbidden`] when the room doesn't let the user add widgets;
    /// [`CoreError::Internal`] when the server names no Jitsi server or its Jitsi wants a
    /// Matrix sign-in; otherwise as the server answers.
    pub async fn start_jitsi_conference(
        &self,
        room_id: String,
        audio_only: bool,
    ) -> Result<JitsiConference, CoreError> {
        let room = self.room(&room_id)?;
        if let Some(going) = self.jitsi_conferences(room_id.clone()).await?.current() {
            return Ok(going);
        }
        if !self.can_start_jitsi_conference(room_id.clone()).await? {
            return Err(CoreError::Forbidden {
                message: "the room doesn't let this user add widgets".to_owned(),
            });
        }
        let domain = self
            .jitsi_domain()
            .await?
            .ok_or_else(|| CoreError::internal(&"the server names no Jitsi server"))?;
        let auth = jitsi_auth(self.client.http_client(), &domain).await;
        let signed_in = match auth.as_deref() {
            None => false,
            Some(OPENID_JWT) => true,
            Some(other) => {
                return Err(CoreError::internal(&format!(
                    "the Jitsi server wants a sign-in OxiTalk doesn't know ({other})"
                )));
            }
        };
        let conference_id = if signed_in {
            signed_in_conference_id(&room_id)
        } else {
            new_conference_id()?
        };
        let widget_id = random_string(ALPHANUMERIC, 24)?;
        let room_name = room.cached_display_name().map(|name| name.to_string());
        let content = widget_content(
            &domain,
            &conference_id,
            audio_only,
            room_name.as_deref(),
            auth.as_deref(),
        )?;
        room.send_state_event_raw(WIDGETS_TYPE, &widget_id, content)
            .await
            .map_err(|error| CoreError::from_sdk(&error))?;
        let own = room.own_user_id().to_owned();
        let creator_name = room
            .get_member_no_sync(&own)
            .await
            .ok()
            .flatten()
            .and_then(|member| member.display_name().map(ToOwned::to_owned));
        Ok(JitsiConference {
            room_id,
            widget_id,
            join_url: join_url(&domain, &conference_id, audio_only)?,
            domain,
            conference_id,
            audio_only,
            creator_user_id: own.to_string(),
            creator_name,
            started_at_ms: now_ms(),
            needs_sign_in: signed_in,
        })
    }

    /// The link that joins a room's Jitsi conference in the browser or the Jitsi Meet app. On a
    /// Jitsi with Matrix sign-in (`needs_sign_in`) it carries a JWT with a fresh OpenID token
    /// of the user's (it proves who they are, nothing more, for about an hour), as Element's
    /// wrapper hands Jitsi.
    ///
    /// # Errors
    ///
    /// [`CoreError::RoomNotFound`]; [`CoreError::Internal`] for a domain that isn't a host
    /// name; otherwise as the homeserver answers the OpenID token request.
    pub async fn jitsi_join_url(
        &self,
        room_id: String,
        domain: String,
        conference_id: String,
        audio_only: bool,
        needs_sign_in: bool,
    ) -> Result<String, CoreError> {
        if !needs_sign_in {
            return join_url(&domain, &conference_id, audio_only);
        }
        let room = self.room(&room_id)?;
        let own = room.own_user_id().to_owned();
        let openid = self
            .client
            .send(request_openid_token::v3::Request::new(own.clone()))
            .await
            .map_err(CoreError::from)?;
        let name = match room.get_member_no_sync(&own).await {
            Ok(Some(member)) => member.display_name().map(ToOwned::to_owned),
            _ => None,
        };
        let jwt = jitsi_jwt(
            &domain,
            &room_id,
            &openid.access_token,
            openid.matrix_server_name.as_str(),
            name.as_deref(),
        );
        signed_in_join_url(&domain, &conference_id, audio_only, &jwt)
    }

    /// Ends the room's Jitsi conference `widget_id` for everyone, as Element's "Remove for
    /// everyone": the widget's state event with empty content.
    ///
    /// # Errors
    ///
    /// [`CoreError::Forbidden`] when the room doesn't let the user; otherwise as the server
    /// answers.
    pub async fn end_jitsi_conference(
        &self,
        room_id: String,
        widget_id: String,
    ) -> Result<(), CoreError> {
        let room = self.room(&room_id)?;
        room.send_state_event_raw(WIDGETS_TYPE, &widget_id, json!({}))
            .await
            .map_err(|error| CoreError::from_sdk(&error))?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[allow(
        clippy::needless_pass_by_value,
        reason = "the tests pass json! literals"
    )]
    fn widget(state_key: &str, ts: i64, content: Value) -> Value {
        json!({
            "type": WIDGETS_TYPE,
            "state_key": state_key,
            "sender": "@alex:chat.securium.ch",
            "origin_server_ts": ts,
            "event_id": format!("${state_key}{ts}"),
            "content": content,
        })
    }

    /// What Element Web writes (`WidgetUtils.addJitsiWidget`).
    fn element_widget() -> Value {
        widget(
            "abcWidget",
            1000,
            json!({
                "type": "jitsi",
                "url": "https://app.element.io/jitsi.html?confId=JitsiAbcdefghijklmnopqrstuvwx#conferenceDomain=$domain&conferenceId=$conferenceId&isAudioOnly=$isAudioOnly&startWithAudioMuted=$startWithAudioMuted",
                "name": "Jitsi",
                "data": {
                    "conferenceId": "JitsiAbcdefghijklmnopqrstuvwx",
                    "roomName": "Team",
                    "isAudioOnly": false,
                    "isVideoChannel": false,
                    "domain": "jitsi.securium.ch",
                },
            }),
        )
    }

    #[test]
    fn an_element_jitsi_widget_is_a_conference() -> Result<(), String> {
        let parsed = parse_jitsi_widget(&element_widget()).ok_or("not read")?;
        assert_eq!(
            parsed,
            JitsiWidget {
                widget_id: "abcWidget".to_owned(),
                sender: "@alex:chat.securium.ch".to_owned(),
                origin_server_ts: 1000,
                domain: "jitsi.securium.ch".to_owned(),
                conference_id: "JitsiAbcdefghijklmnopqrstuvwx".to_owned(),
                audio_only: false,
                auth: None,
            }
        );
        Ok(())
    }

    #[test]
    fn the_m_jitsi_type_counts_too_and_audio_only_is_read() -> Result<(), String> {
        let mut event = element_widget();
        event["content"]["type"] = json!("m.jitsi");
        event["content"]["data"]["isAudioOnly"] = json!(true);
        let parsed = parse_jitsi_widget(&event).ok_or("not read")?;
        assert!(parsed.audio_only);
        Ok(())
    }

    #[test]
    fn a_removed_widget_and_other_widgets_are_no_conference() {
        assert!(parse_jitsi_widget(&widget("abcWidget", 2000, json!({}))).is_none());
        let mut other = element_widget();
        other["content"]["type"] = json!("m.custom");
        assert!(parse_jitsi_widget(&other).is_none());
        let mut no_url = element_widget();
        no_url["content"]["url"] = json!("");
        assert!(parse_jitsi_widget(&no_url).is_none());
        let mut not_widgets = element_widget();
        not_widgets["type"] = json!("m.room.topic");
        assert!(parse_jitsi_widget(&not_widgets).is_none());
    }

    #[test]
    fn without_data_the_conference_comes_from_the_url() -> Result<(), String> {
        // The wrapper URL with its fragment filled in.
        let event = widget(
            "w1",
            5,
            json!({
                "type": "jitsi",
                "url": "https://example.org/jitsi.html#conferenceDomain=jitsi.securium.ch&conferenceId=Weekly%20sync&isAudioOnly=true",
            }),
        );
        let parsed = parse_jitsi_widget(&event).ok_or("not read")?;
        assert_eq!(parsed.domain, "jitsi.securium.ch");
        assert_eq!(parsed.conference_id, "Weekly sync");
        assert!(parsed.audio_only);

        // A v1 widget: only `confId` in the query; its domain is Element's default.
        let v1 = widget(
            "w2",
            5,
            json!({
                "type": "jitsi",
                "url": "https://scalar.vector.im/api/widgets/jitsi.html?confId=OldConf&isAudioConf=false#conferenceDomain=$domain",
            }),
        );
        let parsed = parse_jitsi_widget(&v1).ok_or("v1 not read")?;
        assert_eq!(parsed.domain, "meet.element.io");
        assert_eq!(parsed.conference_id, "OldConf");
        assert!(!parsed.audio_only);
        Ok(())
    }

    #[test]
    fn data_without_a_domain_takes_the_one_in_the_url() -> Result<(), String> {
        let mut event = element_widget();
        if let Some(data) = event["content"]["data"].as_object_mut() {
            data.remove("domain");
        }
        event["content"]["url"] = json!(
            "https://chat.example/jitsi.html#conferenceDomain=jitsi.securium.ch&conferenceId=$conferenceId"
        );
        let parsed = parse_jitsi_widget(&event).ok_or("not read")?;
        assert_eq!(parsed.domain, "jitsi.securium.ch");
        assert_eq!(parsed.conference_id, "JitsiAbcdefghijklmnopqrstuvwx");
        Ok(())
    }

    #[test]
    fn a_widget_without_a_conference_or_with_a_bad_domain_is_skipped() -> Result<(), String> {
        let no_conference = widget(
            "w",
            5,
            json!({"type": "jitsi", "url": "https://example.org/jitsi.html#conferenceId=$conferenceId"}),
        );
        assert!(parse_jitsi_widget(&no_conference).is_none());
        for bad in ["evil.example/path", "user@evil.example", "a b"] {
            let mut event = element_widget();
            event["content"]["data"]["domain"] = json!(bad);
            assert!(parse_jitsi_widget(&event).is_none(), "{bad}");
        }
        // An empty domain is no domain: Element's default for widgets that name none.
        let mut empty = element_widget();
        empty["content"]["data"]["domain"] = json!("");
        let parsed = parse_jitsi_widget(&empty).ok_or("not read")?;
        assert_eq!(parsed.domain, V1_DOMAIN);
        Ok(())
    }

    #[test]
    fn the_sign_in_a_widget_names_is_read() -> Result<(), String> {
        let mut event = element_widget();
        event["content"]["data"]["auth"] = json!("openidtoken-jwt");
        let parsed = parse_jitsi_widget(&event).ok_or("not read")?;
        assert_eq!(parsed.auth.as_deref(), Some("openidtoken-jwt"));
        Ok(())
    }

    #[test]
    fn join_urls_open_the_conference() -> Result<(), CoreError> {
        assert_eq!(
            join_url("jitsi.securium.ch", "JitsiAbc", false)?,
            "https://jitsi.securium.ch/JitsiAbc"
        );
        assert_eq!(
            join_url("jitsi.securium.ch", "Weekly sync/1", true)?,
            "https://jitsi.securium.ch/Weekly%20sync%2F1#config.startAudioOnly=true"
        );
        assert_eq!(
            join_url("meet.example:8443", "X", false)?,
            "https://meet.example:8443/X"
        );
        assert!(join_url("evil.example/x", "X", false).is_err());
        Ok(())
    }

    #[test]
    fn the_well_known_names_the_jitsi_domain() {
        // chat.securium.ch, 2026-11-03.
        let securium = json!({
            "m.homeserver": {"base_url": "https://chat.securium.ch"},
            "im.vector.riot.jitsi": {"preferredDomain": "jitsi.securium.ch"},
        });
        assert_eq!(
            parse_jitsi_well_known(&securium).as_deref(),
            Some("jitsi.securium.ch")
        );
        let both = json!({
            "io.element.jitsi": {"preferredDomain": "new.example"},
            "im.vector.riot.jitsi": {"preferredDomain": "old.example"},
        });
        assert_eq!(
            parse_jitsi_well_known(&both).as_deref(),
            Some("new.example")
        );
        assert_eq!(
            parse_jitsi_well_known(&json!({"m.homeserver": {"base_url": "https://x"}})),
            None
        );
        assert_eq!(
            parse_jitsi_well_known(&json!({"im.vector.riot.jitsi": {"preferredDomain": "a/b"}})),
            None
        );
    }

    #[test]
    fn the_newest_event_of_each_widget_counts() {
        let stored = vec![element_widget()];
        // The server says the widget was removed later, and has another one.
        let fetched = vec![
            widget("abcWidget", 2000, json!({})),
            widget(
                "second",
                1500,
                json!({"type": "jitsi", "url": "https://x/jitsi.html?confId=Second"}),
            ),
        ];
        let merged = merge_widget_events(stored, &fetched);
        let widgets = jitsi_widgets(&merged);
        assert_eq!(widgets.len(), 1);
        assert_eq!(widgets[0].widget_id, "second");

        // The store has a newer event than the server's answer: it wins.
        let merged = merge_widget_events(
            vec![widget("abcWidget", 3000, json!({}))],
            &[element_widget()],
        );
        assert_eq!(jitsi_widgets(&merged), Vec::new());
    }

    #[test]
    fn conferences_are_newest_first() {
        let mut newer = element_widget();
        newer["state_key"] = json!("newer");
        newer["origin_server_ts"] = json!(9000);
        let widgets = jitsi_widgets(&[element_widget(), newer]);
        let ids: Vec<&str> = widgets.iter().map(|w| w.widget_id.as_str()).collect();
        assert_eq!(ids, ["newer", "abcWidget"]);
    }

    #[test]
    fn a_new_conference_looks_like_elements_and_reads_back() -> Result<(), String> {
        let id = new_conference_id().map_err(|e| e.to_string())?;
        assert_eq!(id.len(), 29);
        assert!(id.starts_with("Jitsi"));
        assert!(id[5..6].chars().all(|c| c.is_ascii_uppercase()));
        assert!(id[6..].chars().all(|c| c.is_ascii_lowercase()));
        assert_ne!(new_conference_id().map_err(|e| e.to_string())?, id);

        let content = widget_content("jitsi.securium.ch", &id, true, Some("Team"), None)
            .map_err(|e| e.to_string())?;
        assert_eq!(content["type"], "jitsi");
        assert_eq!(content["name"], "Jitsi");
        assert_eq!(content["data"]["roomName"], "Team");
        assert_eq!(content["data"]["isVideoChannel"], false);
        let parsed =
            parse_jitsi_widget(&widget("mine", 1, content)).ok_or("our own widget not read")?;
        assert_eq!(parsed.conference_id, id);
        assert_eq!(parsed.domain, "jitsi.securium.ch");
        assert!(parsed.audio_only);
        Ok(())
    }

    #[test]
    fn base32_is_rfc_4648_without_padding() {
        // RFC 4648 section 10 test vectors, padding dropped.
        for (input, output) in [
            ("", ""),
            ("f", "MY"),
            ("fo", "MZXQ"),
            ("foo", "MZXW6"),
            ("foob", "MZXW6YQ"),
            ("fooba", "MZXW6YTB"),
            ("foobar", "MZXW6YTBOI"),
        ] {
            assert_eq!(base32(input.as_bytes()), output, "{input}");
        }
        assert_eq!(signed_in_conference_id("!abc:x.y"), "EFQWEYZ2PAXHS");
    }

    #[test]
    fn a_signed_in_conference_carries_elements_jwt() -> Result<(), Box<dyn std::error::Error>> {
        let jwt = jitsi_jwt(
            "jitsi.securium.ch",
            "!room:chat.securium.ch",
            "openid-token",
            "chat.securium.ch",
            Some("Alex"),
        );
        let parts: Vec<&str> = jwt.split('.').collect();
        assert_eq!(parts.len(), 3);
        let header: Value = serde_json::from_slice(&URL_SAFE_NO_PAD.decode(parts[0])?)?;
        assert_eq!(header, json!({"alg": "HS256", "typ": "JWT"}));
        let payload: Value = serde_json::from_slice(&URL_SAFE_NO_PAD.decode(parts[1])?)?;
        assert_eq!(
            payload,
            json!({
                "iss": "jitsi.securium.ch",
                "sub": "jitsi.securium.ch",
                "aud": "https://jitsi.securium.ch",
                "room": "*",
                "context": {
                    "matrix": {
                        "token": "openid-token",
                        "room_id": "!room:chat.securium.ch",
                        "server_name": "chat.securium.ch",
                    },
                    "user": {"name": "Alex"},
                },
            })
        );
        // HS256 with Element's key.
        let key = ring::hmac::Key::new(ring::hmac::HMAC_SHA256, b"notused");
        let signature = URL_SAFE_NO_PAD.decode(parts[2])?;
        ring::hmac::verify(
            &key,
            format!("{}.{}", parts[0], parts[1]).as_bytes(),
            &signature,
        )
        .map_err(|_| "bad signature")?;

        let url = signed_in_join_url("jitsi.securium.ch", "EFQWEYZ2PAXHS", true, &jwt)?;
        assert_eq!(
            url,
            format!("https://jitsi.securium.ch/EFQWEYZ2PAXHS?jwt={jwt}#config.startAudioOnly=true")
        );
        Ok(())
    }

    #[test]
    fn a_signed_in_widget_names_its_sign_in() -> Result<(), String> {
        let content = widget_content(
            "jitsi.securium.ch",
            "EFQWEYZ2PAXHS",
            false,
            None,
            Some(OPENID_JWT),
        )
        .map_err(|e| e.to_string())?;
        assert_eq!(content["data"]["auth"], OPENID_JWT);
        assert_eq!(content["data"].get("roomName"), None);
        let parsed = parse_jitsi_widget(&widget("w", 1, content)).ok_or("not read")?;
        assert_eq!(parsed.auth.as_deref(), Some(OPENID_JWT));
        Ok(())
    }

    #[test]
    fn widget_ids_are_alphanumeric() -> Result<(), CoreError> {
        let id = random_string(ALPHANUMERIC, 24)?;
        assert_eq!(id.len(), 24);
        assert!(id.chars().all(|c| c.is_ascii_alphanumeric()));
        Ok(())
    }

    #[test]
    fn widget_events_are_read_from_a_sliding_sync_answer() {
        let body = json!({
            "pos": "1",
            "rooms": {
                "!r:x": {
                    "required_state": [element_widget(), {"type": "m.room.create", "state_key": ""}],
                },
            },
        });
        assert_eq!(widget_events_of(&body, "!r:x"), vec![element_widget()]);
        assert_eq!(widget_events_of(&body, "!other:x"), Vec::<Value>::new());
        assert_eq!(widget_events_of(&json!({}), "!r:x"), Vec::<Value>::new());
    }

    #[tokio::test]
    async fn the_jitsi_domain_is_fetched_from_the_well_known()
    -> Result<(), Box<dyn std::error::Error>> {
        use wiremock::{
            Mock, MockServer, ResponseTemplate,
            matchers::{method, path},
        };
        let server = MockServer::start().await;
        Mock::given(method("GET"))
            .and(path("/.well-known/matrix/client"))
            .respond_with(ResponseTemplate::new(200).set_body_json(json!({
                "m.homeserver": {"base_url": "https://chat.securium.ch"},
                "im.vector.riot.jitsi": {"preferredDomain": "jitsi.securium.ch"},
            })))
            .mount(&server)
            .await;
        let _ = rustls::crypto::ring::default_provider().install_default();
        let http = reqwest::Client::new();
        let url = format!("{}/.well-known/matrix/client", server.uri());
        assert_eq!(
            fetch_jitsi_domain(&http, &url).await?.as_deref(),
            Some("jitsi.securium.ch")
        );
        let missing = format!("{}/.well-known/none", server.uri());
        assert_eq!(fetch_jitsi_domain(&http, &missing).await?, None);
        Ok(())
    }
}
