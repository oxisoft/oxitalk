//! What the client can find out about an account's homeserver: where it is, which software
//! runs it, which Matrix versions and features it has, how one signs in, what an account may
//! change, how big an upload may be, whom to ask for help, and how the connection to it goes.
//!
//! Every request goes to the account's own homeserver (its base URL, or its server name for
//! `.well-known`) through the account's own HTTP client; the addresses come from the system's
//! resolver. Each part is filled in as far as the server answers; one that doesn't answer
//! leaves its part unknown and never fails the whole call.

use std::{
    net::{IpAddr, ToSocketAddrs},
    time::{Duration, Instant},
};

use flutter_rust_bridge::frb;
use futures_util::future::{join, join5};
use matrix_sdk::{Client, reqwest};
use serde_json::Value;

use super::{error::CoreError, session::Session};

/// How long one request may take before its part counts as unanswered.
const REQUEST_TIMEOUT: Duration = Duration::from_secs(8);

/// Whether a document the server may publish is there.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Probe {
    /// It answered with the document.
    Found,
    /// It answered that there is none (or with something that isn't one).
    NotFound,
    /// No answer: the host can't be reached, or it took too long.
    NoAnswer,
}

/// Whether the server talks to other Matrix servers.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Federation {
    /// `/_matrix/federation/v1/version` answered with the server's software.
    Enabled,
    /// The server refused it (`M_FORBIDDEN`, e.g. "Federation is disabled.").
    Disabled,
    /// No answer that tells either way (not served on this address, or no answer).
    Unknown,
}

/// Whether the server offers something; `Unknown` when it didn't answer.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Availability {
    Yes,
    No,
    Unknown,
}

/// The software the homeserver runs, and where that was read.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ServerSoftware {
    /// "Synapse", "Tuwunel", …; `None` if the server told only its version.
    pub name: Option<String>,
    pub version: Option<String>,
    /// The endpoint (path) or header that told it.
    pub source: String,
}

/// One entry of `unstable_features` in `/_matrix/client/versions`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct UnstableFeature {
    pub id: String,
    /// Whether the server says it is on.
    pub enabled: bool,
    /// What it is, for the features worth naming; `None` for the rest.
    pub label: Option<String>,
    /// The app uses it when the server has it.
    pub used_by_app: bool,
}

/// How one can sign in to the server.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LoginInfo {
    /// The flow types of `GET /_matrix/client/v3/login`, in the server's order.
    pub flows: Vec<String>,
    /// `m.login.token` with `get_login_token`: a signed-in device may sign in another one.
    pub get_login_token: bool,
    /// The names of the single sign-on providers, if `m.login.sso` lists them.
    pub sso_providers: Vec<String>,
}

/// One room version the server can create rooms with.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RoomVersion {
    pub version: String,
    /// "stable" in the capabilities; anything else counts as unstable.
    pub stable: bool,
}

/// What an account may do on the server (`/_matrix/client/v3/capabilities`), with the spec's
/// defaults for what the server leaves out.
#[derive(Debug, Clone, PartialEq, Eq)]
#[allow(
    clippy::struct_excessive_bools,
    reason = "each is one capability of its own, as the server lists them"
)]
pub struct ServerCapabilities {
    pub change_password: bool,
    pub set_display_name: bool,
    pub set_avatar: bool,
    pub change_3pids: bool,
    /// The server lets a signed-in device make a login token for another one.
    pub get_login_token: bool,
    pub default_room_version: Option<String>,
    /// Ordered by version number.
    pub room_versions: Vec<RoomVersion>,
}

/// One contact of `/.well-known/matrix/support`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SupportContact {
    /// `m.role.admin`, `m.role.security`, or another role.
    pub role: String,
    pub matrix_id: Option<String>,
    pub email_address: Option<String>,
}

/// `/.well-known/matrix/support`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SupportInfo {
    pub contacts: Vec<SupportContact>,
    pub support_page: Option<String>,
}

/// How the app reaches the server.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ConnectionInfo {
    /// The host of the base URL.
    pub host: String,
    /// The port in use (the scheme's default if the URL has none).
    pub port: Option<u16>,
    /// The addresses the system's resolver gives for the host; empty if it gives none.
    pub addresses: Vec<String>,
    /// How long one `GET /_matrix/client/versions` took, in milliseconds, if it was answered.
    pub round_trip_ms: Option<u64>,
    /// The base URL is `https`.
    pub tls: bool,
    /// The HTTP version of that answer, e.g. "HTTP/2.0".
    pub http_version: Option<String>,
}

/// Everything [`Session::server_info`] found out.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ServerInfo {
    /// The account it is about.
    pub user_id: String,
    /// The base URL the account's client uses.
    pub homeserver_url: String,
    /// The domain of the user ID.
    pub server_name: String,
    /// `https://<server name>/.well-known/matrix/client`.
    pub well_known_client: Probe,
    /// Its `m.homeserver.base_url`.
    pub well_known_base_url: Option<String>,
    /// `https://<server name>/.well-known/matrix/server`.
    pub well_known_server: Probe,
    /// Its `m.server`: where other servers reach this one.
    pub server_delegation: Option<String>,
    pub software: Option<ServerSoftware>,
    pub federation: Federation,
    /// Whether `/_matrix/client/versions` answered.
    pub versions_known: bool,
    /// Every version it lists, oldest first.
    pub spec_versions: Vec<String>,
    /// The newest of [`Self::spec_versions`].
    pub newest_spec_version: Option<String>,
    /// The named features first (those the app uses first), then the rest by ID.
    pub unstable_features: Vec<UnstableFeature>,
    pub login: Option<LoginInfo>,
    /// Sign-in through OAuth 2.0 / OIDC (e.g. Matrix Authentication Service).
    pub oauth: Availability,
    /// The OAuth issuer, if the server names one.
    pub oauth_issuer: Option<String>,
    pub capabilities: Option<ServerCapabilities>,
    /// The largest upload the server takes, in bytes, if it tells.
    pub upload_limit_bytes: Option<u64>,
    /// `https://<server name>/.well-known/matrix/support`.
    pub well_known_support: Probe,
    pub support: Option<SupportInfo>,
    pub connection: ConnectionInfo,
}

impl Session {
    /// What can be found out about this account's homeserver; see [`ServerInfo`]. Each
    /// session is one account, so the app asks the picked account's session.
    ///
    /// # Errors
    ///
    /// [`CoreError::SessionExpired`] if the session has been logged out. A part the server
    /// doesn't answer is left unknown instead.
    pub async fn server_info(&self) -> Result<ServerInfo, CoreError> {
        server_info_of(&self.client).await
    }
}

/// [`Session::server_info`] for any client, so tests can point one at a mock server.
///
/// # Errors
///
/// As [`Session::server_info`].
async fn server_info_of(client: &Client) -> Result<ServerInfo, CoreError> {
    let user_id = client
        .user_id()
        .ok_or(CoreError::SessionExpired)?
        .to_owned();
    let server_name = user_id.server_name().to_string();
    let base = client.homeserver();
    let probe = Prober {
        http: client.http_client().clone(),
        base: base.as_str().trim_end_matches('/').to_owned(),
        token: client.access_token(),
    };
    let well_known = |path: &str| format!("https://{server_name}/.well-known/matrix/{path}");

    let host = base.host_str().unwrap_or_default().to_owned();
    let port = base.port_or_known_default();
    let (
        (versions, software_and_federation, login, oauth, capabilities),
        (upload_limit, well_known_client, well_known_server, well_known_support, addresses),
    ) = join(
        join5(
            probe.timed_get("/_matrix/client/versions"),
            detect_software(&probe),
            probe.get("/_matrix/client/v3/login", Auth::No),
            detect_oauth(&probe),
            probe.get("/_matrix/client/v3/capabilities", Auth::Yes),
        ),
        join5(
            upload_limit(&probe),
            probe.get_url(&well_known("client")),
            probe.get_url(&well_known("server")),
            probe.get_url(&well_known("support")),
            resolve(host.clone(), port),
        ),
    )
    .await;

    let (versions, round_trip) = versions;
    let (software, federation) = software_and_federation;
    let (spec_versions, unstable_features) = versions
        .as_ref()
        .and_then(Answer::ok_json)
        .map(parse_versions)
        .unwrap_or_default();
    let (well_known_client, well_known_base_url) =
        probe_document(well_known_client.as_ref(), parse_well_known_client);
    let (well_known_server, server_delegation) =
        probe_document(well_known_server.as_ref(), parse_well_known_server);
    let (well_known_support, support) = probe_document(well_known_support.as_ref(), |body| {
        Some(parse_support(body))
    });
    let (oauth, oauth_issuer) = oauth;
    Ok(ServerInfo {
        user_id: user_id.to_string(),
        homeserver_url: base.to_string(),
        server_name,
        well_known_client,
        well_known_base_url,
        well_known_server,
        server_delegation,
        software: software.or_else(|| {
            versions
                .as_ref()
                .and_then(|a| a.server_header.as_deref())
                .and_then(software_from_header)
        }),
        federation,
        versions_known: versions.as_ref().and_then(Answer::ok_json).is_some(),
        newest_spec_version: newest_version(&spec_versions),
        spec_versions,
        unstable_features,
        login: login.as_ref().and_then(Answer::ok_json).map(parse_login),
        oauth,
        oauth_issuer,
        capabilities: capabilities
            .as_ref()
            .and_then(Answer::ok_json)
            .map(parse_capabilities),
        upload_limit_bytes: upload_limit,
        well_known_support,
        support,
        connection: ConnectionInfo {
            host,
            port,
            addresses,
            round_trip_ms: round_trip
                .map(|elapsed| u64::try_from(elapsed.as_millis()).unwrap_or(u64::MAX)),
            tls: base.scheme() == "https",
            http_version: versions.and_then(|a| a.http_version),
        },
    })
}

/// One answer of the server: its status, its body if it is JSON, and a few headers.
#[frb(ignore)]
#[derive(Debug, Clone, Default, PartialEq)]
pub(crate) struct Answer {
    pub(crate) status: u16,
    pub(crate) body: Option<Value>,
    pub(crate) server_header: Option<String>,
    pub(crate) http_version: Option<String>,
}

impl Answer {
    fn ok_json(&self) -> Option<&Value> {
        if (200..300).contains(&self.status) {
            self.body.as_ref().filter(|body| body.is_object())
        } else {
            None
        }
    }

    fn errcode(&self) -> Option<&str> {
        self.body.as_ref()?.get("errcode")?.as_str()
    }
}

#[derive(Clone, Copy)]
enum Auth {
    Yes,
    No,
}

/// Requests on the account's homeserver with its own HTTP client.
struct Prober {
    http: reqwest::Client,
    /// The base URL without a trailing `/`.
    base: String,
    token: Option<String>,
}

impl Prober {
    /// `GET <base><path>`; `None` without an answer.
    async fn get(&self, path: &str, auth: Auth) -> Option<Answer> {
        self.request(&format!("{}{path}", self.base), auth).await
    }

    /// `GET url`, without the access token: the `.well-known` documents are public.
    async fn get_url(&self, url: &str) -> Option<Answer> {
        self.request(url, Auth::No).await
    }

    /// [`Self::get`] without the token, and how long it took.
    async fn timed_get(&self, path: &str) -> (Option<Answer>, Option<Duration>) {
        let start = Instant::now();
        let answer = self.get(path, Auth::No).await;
        let elapsed = answer.as_ref().map(|_| start.elapsed());
        (answer, elapsed)
    }

    async fn request(&self, url: &str, auth: Auth) -> Option<Answer> {
        let mut request = self.http.get(url).timeout(REQUEST_TIMEOUT);
        if let (Auth::Yes, Some(token)) = (auth, &self.token) {
            request = request.bearer_auth(token);
        }
        let response = request
            .send()
            .await
            .inspect_err(|error| tracing::debug!("server info: {url}: {error}"))
            .ok()?;
        let status = response.status().as_u16();
        let server_header = response
            .headers()
            .get("server")
            .and_then(|value| value.to_str().ok())
            .map(ToOwned::to_owned);
        let http_version = Some(format!("{:?}", response.version()));
        let bytes = response.bytes().await.ok()?;
        Some(Answer {
            status,
            body: serde_json::from_slice(&bytes).ok(),
            server_header,
            http_version,
        })
    }
}

/// The endpoints that tell the server's software, in the order they are tried. The first
/// one is also the one that tells about federation.
pub(crate) const SOFTWARE_ENDPOINTS: [&str; 4] = [
    "/_matrix/federation/v1/version",
    "/_tuwunel/server_version",
    "/_conduwuit/server_version",
    "/_synapse/admin/v1/server_version",
];

/// Asks [`SOFTWARE_ENDPOINTS`] in order until one tells the software.
async fn detect_software(probe: &Prober) -> (Option<ServerSoftware>, Federation) {
    let mut federation = Federation::Unknown;
    for (index, path) in SOFTWARE_ENDPOINTS.iter().enumerate() {
        let answer = probe.get(path, Auth::No).await;
        if index == 0 {
            federation = parse_federation(answer.as_ref());
        }
        if let Some(software) = answer
            .as_ref()
            .and_then(Answer::ok_json)
            .and_then(|body| parse_software(path, body))
        {
            return (Some(software), federation);
        }
    }
    (None, federation)
}

/// Federation from the answer of `/_matrix/federation/v1/version`.
pub(crate) fn parse_federation(answer: Option<&Answer>) -> Federation {
    let Some(answer) = answer else {
        return Federation::Unknown;
    };
    if answer
        .ok_json()
        .is_some_and(|body| body.get("server").is_some_and(Value::is_object))
    {
        Federation::Enabled
    } else if answer.errcode() == Some("M_FORBIDDEN") {
        Federation::Disabled
    } else {
        Federation::Unknown
    }
}

/// The software in the JSON answer of `path`, one of [`SOFTWARE_ENDPOINTS`].
pub(crate) fn parse_software(path: &str, body: &Value) -> Option<ServerSoftware> {
    let text = |value: Option<&Value>| {
        value
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .map(ToOwned::to_owned)
    };
    let (name, version) = if path.starts_with("/_matrix/federation") {
        let server = body.get("server")?;
        (text(server.get("name")), text(server.get("version")))
    } else if path.starts_with("/_synapse") {
        // Synapse answers only its version; others answer here too for compatibility, which
        // is why their own endpoints are asked first.
        let version = text(body.get("server_version"));
        (version.as_ref().map(|_| "Synapse".to_owned()), version)
    } else {
        (text(body.get("name")), text(body.get("version")))
    };
    (name.is_some() || version.is_some()).then(|| ServerSoftware {
        name,
        version,
        source: path.to_owned(),
    })
}

/// The software in a `Server` header, only for the names homeservers use: a reverse proxy
/// names itself there too.
pub(crate) fn software_from_header(header: &str) -> Option<ServerSoftware> {
    const KNOWN: [&str; 6] = [
        "Synapse",
        "Tuwunel",
        "conduwuit",
        "Conduit",
        "continuwuity",
        "Dendrite",
    ];
    let (name, version) = header
        .split_whitespace()
        .next()
        .map(|product| product.split_once('/').unwrap_or((product, "")))?;
    let known = KNOWN
        .iter()
        .find(|known| known.eq_ignore_ascii_case(name))?;
    Some(ServerSoftware {
        name: Some((*known).to_owned()),
        version: (!version.is_empty()).then(|| version.to_owned()),
        source: "Server header".to_owned(),
    })
}

/// OAuth from `/_matrix/client/v1/auth_metadata`, then the unstable `auth_issuer`.
async fn detect_oauth(probe: &Prober) -> (Availability, Option<String>) {
    let metadata = probe
        .get("/_matrix/client/v1/auth_metadata", Auth::No)
        .await;
    if let found @ (Availability::Yes, _) = parse_oauth(metadata.as_ref()) {
        return found;
    }
    let issuer = probe
        .get(
            "/_matrix/client/unstable/org.matrix.msc2965/auth_issuer",
            Auth::No,
        )
        .await;
    match (parse_oauth(metadata.as_ref()), parse_oauth(issuer.as_ref())) {
        (_, found @ (Availability::Yes, _)) => found,
        ((Availability::No, _), _) | (_, (Availability::No, _)) => (Availability::No, None),
        _ => (Availability::Unknown, None),
    }
}

/// OAuth from one answer of either endpoint: yes with an issuer, no for any other answer.
pub(crate) fn parse_oauth(answer: Option<&Answer>) -> (Availability, Option<String>) {
    match answer {
        None => (Availability::Unknown, None),
        Some(answer) => match answer
            .ok_json()
            .and_then(|body| body.get("issuer"))
            .and_then(Value::as_str)
        {
            Some(issuer) => (Availability::Yes, Some(issuer.to_owned())),
            None => (Availability::No, None),
        },
    }
}

/// The upload limit from the authenticated media config, then the legacy one.
async fn upload_limit(probe: &Prober) -> Option<u64> {
    if let Some(limit) = probe
        .get("/_matrix/client/v1/media/config", Auth::Yes)
        .await
        .as_ref()
        .and_then(Answer::ok_json)
        .and_then(parse_upload_limit)
    {
        return Some(limit);
    }
    probe
        .get("/_matrix/media/v3/config", Auth::Yes)
        .await
        .as_ref()
        .and_then(Answer::ok_json)
        .and_then(parse_upload_limit)
}

pub(crate) fn parse_upload_limit(body: &Value) -> Option<u64> {
    body.get("m.upload.size")?.as_u64()
}

/// The addresses of `host`, as the system resolves them, without repeats.
async fn resolve(host: String, port: Option<u16>) -> Vec<String> {
    let host = host
        .trim_start_matches('[')
        .trim_end_matches(']')
        .to_owned();
    if host.is_empty() {
        return Vec::new();
    }
    if let Ok(ip) = host.parse::<IpAddr>() {
        return vec![ip.to_string()];
    }
    let lookup = tokio::task::spawn_blocking(move || {
        (host.as_str(), port.unwrap_or(443))
            .to_socket_addrs()
            .map(|addresses| addresses.map(|a| a.ip()).collect::<Vec<_>>())
    });
    let ips = match tokio::time::timeout(REQUEST_TIMEOUT, lookup).await {
        Ok(Ok(Ok(ips))) => ips,
        _ => Vec::new(),
    };
    let mut seen = Vec::new();
    for ip in ips {
        let ip = ip.to_string();
        if !seen.contains(&ip) {
            seen.push(ip);
        }
    }
    seen
}

/// Whether a `.well-known` document is there, and what `parse` reads from it.
fn probe_document<T>(
    answer: Option<&Answer>,
    parse: impl Fn(&Value) -> Option<T>,
) -> (Probe, Option<T>) {
    match answer {
        None => (Probe::NoAnswer, None),
        Some(answer) => match answer.ok_json() {
            Some(body) => (Probe::Found, parse(body)),
            None => (Probe::NotFound, None),
        },
    }
}

pub(crate) fn parse_well_known_client(body: &Value) -> Option<String> {
    Some(
        body.get("m.homeserver")?
            .get("base_url")?
            .as_str()?
            .to_owned(),
    )
}

pub(crate) fn parse_well_known_server(body: &Value) -> Option<String> {
    Some(body.get("m.server")?.as_str()?.to_owned())
}

pub(crate) fn parse_support(body: &Value) -> SupportInfo {
    let text = |value: &Value, key: &str| {
        value
            .get(key)
            .and_then(Value::as_str)
            .map(ToOwned::to_owned)
    };
    let contacts = body
        .get("contacts")
        .and_then(Value::as_array)
        .map(|contacts| {
            contacts
                .iter()
                .filter(|c| c.is_object())
                .map(|c| SupportContact {
                    role: text(c, "role").unwrap_or_default(),
                    matrix_id: text(c, "matrix_id"),
                    email_address: text(c, "email_address"),
                })
                .collect()
        })
        .unwrap_or_default();
    SupportInfo {
        contacts,
        support_page: text(body, "support_page"),
    }
}

/// The unstable features worth naming: ID, label, and whether the app uses it.
const FEATURE_LABELS: [(&str, &str, bool); 20] = [
    (
        "org.matrix.simplified_msc3575",
        "Simplified sliding sync (MSC4186)",
        true,
    ),
    (
        "org.matrix.msc3916.stable",
        "Authenticated media (MSC3916)",
        true,
    ),
    ("org.matrix.msc3440.stable", "Threads (MSC3440)", true),
    (
        "org.matrix.msc3916",
        "Authenticated media, draft (MSC3916)",
        false,
    ),
    ("org.matrix.e2e_cross_signing", "Cross-signing", false),
    ("org.matrix.msc4260", "Report users (MSC4260)", false),
    ("org.matrix.msc4151", "Report rooms (MSC4151)", false),
    ("org.matrix.msc3266", "Room previews (MSC3266)", false),
    (
        "org.matrix.msc4108",
        "Sign in with a QR code (MSC4108)",
        false,
    ),
    ("org.matrix.msc3882", "Login tokens (MSC3882)", false),
    (
        "org.matrix.msc4306",
        "Thread subscriptions (MSC4306)",
        false,
    ),
    (
        "org.matrix.msc4028",
        "Push for all encrypted events (MSC4028)",
        false,
    ),
    ("org.matrix.msc3814", "Dehydrated devices (MSC3814)", false),
    ("org.matrix.msc4140", "Delayed events (MSC4140)", false),
    ("org.matrix.msc4133", "Extended profiles (MSC4133)", false),
    (
        "org.matrix.msc3827.stable",
        "Room types in the directory (MSC3827)",
        false,
    ),
    (
        "org.matrix.msc3881",
        "Push rules per device (MSC3881)",
        false,
    ),
    (
        "org.matrix.msc3026.busy_presence",
        "Busy presence (MSC3026)",
        false,
    ),
    (
        "uk.half-shot.msc2666.query_mutual_rooms",
        "Mutual rooms (MSC2666)",
        false,
    ),
    (
        "org.matrix.msc3575",
        "Sliding sync, old proxy (MSC3575)",
        false,
    ),
];

/// The versions (oldest first) and the unstable features of `/_matrix/client/versions`.
pub(crate) fn parse_versions(body: &Value) -> (Vec<String>, Vec<UnstableFeature>) {
    let mut versions: Vec<String> = body
        .get("versions")
        .and_then(Value::as_array)
        .map(|list| {
            list.iter()
                .filter_map(Value::as_str)
                .map(ToOwned::to_owned)
                .collect()
        })
        .unwrap_or_default();
    versions.sort_by_key(|v| version_key(v));
    versions.dedup();
    let mut features: Vec<UnstableFeature> = body
        .get("unstable_features")
        .and_then(Value::as_object)
        .map(|map| {
            map.iter()
                .map(|(id, on)| {
                    let known = FEATURE_LABELS.iter().find(|(known, ..)| known == id);
                    UnstableFeature {
                        id: id.clone(),
                        enabled: on.as_bool().unwrap_or(false),
                        label: known.map(|(_, label, _)| (*label).to_owned()),
                        used_by_app: known.is_some_and(|(.., used)| *used),
                    }
                })
                .collect()
        })
        .unwrap_or_default();
    let rank = |f: &UnstableFeature| {
        FEATURE_LABELS
            .iter()
            .position(|(known, ..)| *known == f.id)
            .unwrap_or(usize::MAX)
    };
    features.sort_by(|a, b| rank(a).cmp(&rank(b)).then_with(|| a.id.cmp(&b.id)));
    (versions, features)
}

/// Orders spec versions: `r0.x.y` before `v1.x`, numbers by value; unknown shapes last.
fn version_key(version: &str) -> (u8, Vec<u64>, String) {
    let (era, rest) = match version.as_bytes().first() {
        Some(b'r') => (0, &version[1..]),
        Some(b'v') => (1, &version[1..]),
        _ => (2, version),
    };
    let numbers = rest
        .split('.')
        .map(|part| part.parse().unwrap_or(0))
        .collect();
    (era, numbers, version.to_owned())
}

pub(crate) fn newest_version(sorted: &[String]) -> Option<String> {
    sorted
        .iter()
        .filter(|v| version_key(v).0 < 2)
        .max_by_key(|v| version_key(v))
        .cloned()
}

pub(crate) fn parse_login(body: &Value) -> LoginInfo {
    let flows = body
        .get("flows")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    let mut info = LoginInfo {
        flows: Vec::new(),
        get_login_token: false,
        sso_providers: Vec::new(),
    };
    for flow in &flows {
        let Some(kind) = flow.get("type").and_then(Value::as_str) else {
            continue;
        };
        info.flows.push(kind.to_owned());
        if kind == "m.login.token" {
            info.get_login_token |= flow
                .get("get_login_token")
                .and_then(Value::as_bool)
                .unwrap_or(false);
        }
        if kind == "m.login.sso" {
            for provider in flow
                .get("identity_providers")
                .and_then(Value::as_array)
                .into_iter()
                .flatten()
            {
                if let Some(name) = provider
                    .get("name")
                    .or_else(|| provider.get("id"))
                    .and_then(Value::as_str)
                {
                    info.sso_providers.push(name.to_owned());
                }
            }
        }
    }
    info
}

pub(crate) fn parse_capabilities(body: &Value) -> ServerCapabilities {
    let caps = body.get("capabilities").cloned().unwrap_or(Value::Null);
    // A capability the server leaves out has the spec's default: allowed.
    let enabled = |key: &str, default: bool| {
        caps.get(key)
            .and_then(|c| c.get("enabled"))
            .and_then(Value::as_bool)
            .unwrap_or(default)
    };
    // Matrix 1.16's m.profile_fields, when present, says the same for the profile fields.
    let profile_field = |field: &str| -> Option<bool> {
        let fields = caps.get("m.profile_fields")?;
        if !fields
            .get("enabled")
            .and_then(Value::as_bool)
            .unwrap_or(true)
        {
            return Some(false);
        }
        let listed = |key: &str| {
            fields
                .get(key)
                .and_then(Value::as_array)
                .map(|list| list.iter().any(|f| f.as_str() == Some(field)))
        };
        Some(match (listed("allowed"), listed("disallowed")) {
            (Some(allowed), _) => allowed,
            (None, Some(disallowed)) => !disallowed,
            (None, None) => true,
        })
    };
    let room_versions = caps.get("m.room_versions");
    let mut available: Vec<RoomVersion> = room_versions
        .and_then(|r| r.get("available"))
        .and_then(Value::as_object)
        .map(|map| {
            map.iter()
                .map(|(version, stability)| RoomVersion {
                    version: version.clone(),
                    stable: stability.as_str() == Some("stable"),
                })
                .collect()
        })
        .unwrap_or_default();
    // Room versions are numbers ("1" to "12"); unstable ones are named, after them.
    available.sort_by_key(|r| {
        (
            r.version.parse::<u64>().map_or(1, |_| 0),
            version_key(&r.version),
        )
    });
    let old_display_name = enabled("m.set_displayname", true);
    let old_avatar = enabled("m.set_avatar_url", true);
    ServerCapabilities {
        change_password: enabled("m.change_password", true),
        set_display_name: profile_field("displayname").unwrap_or(old_display_name),
        set_avatar: profile_field("avatar_url").unwrap_or(old_avatar),
        change_3pids: enabled("m.3pid_changes", true),
        get_login_token: enabled("m.get_login_token", false),
        default_room_version: room_versions
            .and_then(|r| r.get("default"))
            .and_then(Value::as_str)
            .map(ToOwned::to_owned),
        room_versions: available,
    }
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::*;

    fn answer(status: u16, body: Value) -> Answer {
        Answer {
            status,
            body: Some(body),
            ..Answer::default()
        }
    }

    #[test]
    fn federation_disabled_is_told_by_m_forbidden() {
        // chat.oxisoft.net (Tuwunel 1.9.4), 2026-10-26.
        let refused = answer(
            403,
            json!({"errcode": "M_FORBIDDEN", "error": "Federation is disabled."}),
        );
        assert_eq!(parse_federation(Some(&refused)), Federation::Disabled);
        let enabled = answer(
            200,
            json!({"server": {"name": "Synapse", "version": "1.162.0"}}),
        );
        assert_eq!(parse_federation(Some(&enabled)), Federation::Enabled);
        assert_eq!(
            parse_federation(Some(&answer(404, json!({"errcode": "M_UNRECOGNIZED"})))),
            Federation::Unknown
        );
        assert_eq!(parse_federation(None), Federation::Unknown);
    }

    #[test]
    fn the_software_is_read_from_each_endpoint() {
        let tuwunel = json!({"name": "Tuwunel", "version": "1.9.4"});
        assert_eq!(
            parse_software("/_tuwunel/server_version", &tuwunel),
            Some(ServerSoftware {
                name: Some("Tuwunel".to_owned()),
                version: Some("1.9.4".to_owned()),
                source: "/_tuwunel/server_version".to_owned(),
            })
        );
        // Tuwunel's compatibility answer there would read as Synapse: it is asked last.
        let synapse = parse_software(
            "/_synapse/admin/v1/server_version",
            &json!({"server_version": "1.162.0"}),
        );
        assert_eq!(synapse.and_then(|s| s.name), Some("Synapse".to_owned()));
        let federation = parse_software(
            "/_matrix/federation/v1/version",
            &json!({"server": {"name": "conduwuit", "version": "0.5.0"}}),
        );
        assert_eq!(federation.and_then(|s| s.version), Some("0.5.0".to_owned()));
        assert_eq!(parse_software("/_tuwunel/server_version", &json!({})), None);
        assert_eq!(SOFTWARE_ENDPOINTS[0], "/_matrix/federation/v1/version");
        assert_eq!(SOFTWARE_ENDPOINTS[3], "/_synapse/admin/v1/server_version");
    }

    #[test]
    fn only_homeserver_names_count_in_the_server_header() {
        let synapse = software_from_header("Synapse/1.162.0 (b=matrix-org)");
        assert_eq!(
            synapse.map(|s| (s.name, s.version)),
            Some((Some("Synapse".to_owned()), Some("1.162.0".to_owned())))
        );
        assert_eq!(software_from_header("nginx/1.27.0"), None);
    }

    #[test]
    fn versions_are_ordered_and_features_named() {
        let body = json!({
            "versions": ["v1.11", "r0.0.1", "v1.2", "v1.19", "r0.6.1", "v1.9"],
            "unstable_features": {
                "org.example.thing": true,
                "org.matrix.simplified_msc3575": true,
                "org.matrix.msc3916.stable": false,
            }
        });
        let (versions, features) = parse_versions(&body);
        assert_eq!(
            versions,
            ["r0.0.1", "r0.6.1", "v1.2", "v1.9", "v1.11", "v1.19"]
        );
        assert_eq!(newest_version(&versions), Some("v1.19".to_owned()));
        assert_eq!(features[0].id, "org.matrix.simplified_msc3575");
        assert_eq!(
            features[0].label.as_deref(),
            Some("Simplified sliding sync (MSC4186)")
        );
        assert!(features[0].used_by_app && features[0].enabled);
        assert!(!features[1].enabled);
        assert_eq!(features[2].id, "org.example.thing");
        assert_eq!(features[2].label, None);
        assert_eq!(parse_versions(&json!({})), (Vec::new(), Vec::new()));
    }

    #[test]
    fn login_flows_and_oauth_are_read() {
        let login = parse_login(&json!({"flows": [
            {"type": "m.login.application_service"},
            {"type": "m.login.token", "get_login_token": true},
            {"type": "m.login.password"},
            {"type": "m.login.sso", "identity_providers": [{"id": "gh", "name": "GitHub"}]},
        ]}));
        assert_eq!(
            login.flows,
            [
                "m.login.application_service",
                "m.login.token",
                "m.login.password",
                "m.login.sso"
            ]
        );
        assert!(login.get_login_token);
        assert_eq!(login.sso_providers, ["GitHub"]);

        let unconfigured = answer(
            404,
            json!({"errcode": "M_UNRECOGNIZED", "error": "OIDC server not configured"}),
        );
        assert_eq!(parse_oauth(Some(&unconfigured)), (Availability::No, None));
        let mas = answer(200, json!({"issuer": "https://auth.example.org/"}));
        assert_eq!(
            parse_oauth(Some(&mas)),
            (
                Availability::Yes,
                Some("https://auth.example.org/".to_owned())
            )
        );
        assert_eq!(parse_oauth(None), (Availability::Unknown, None));
    }

    #[test]
    fn capabilities_fall_back_to_the_spec_defaults() {
        let caps = parse_capabilities(&json!({"capabilities": {
            "m.change_password": {"enabled": false},
            "m.room_versions": {
                "default": "11",
                "available": {"10": "stable", "2": "stable", "11": "stable",
                              "org.matrix.msc2176": "unstable"}
            },
            "m.profile_fields": {"enabled": true, "disallowed": ["avatar_url"]}
        }}));
        assert!(!caps.change_password);
        assert!(caps.set_display_name);
        assert!(!caps.set_avatar);
        assert!(caps.change_3pids);
        assert!(!caps.get_login_token);
        assert_eq!(caps.default_room_version.as_deref(), Some("11"));
        let versions: Vec<_> = caps
            .room_versions
            .iter()
            .map(|r| (r.version.as_str(), r.stable))
            .collect();
        assert_eq!(
            versions,
            [
                ("2", true),
                ("10", true),
                ("11", true),
                ("org.matrix.msc2176", false)
            ]
        );
        let empty = parse_capabilities(&json!({}));
        assert!(empty.change_password && empty.set_avatar && empty.room_versions.is_empty());
    }

    #[test]
    fn well_known_documents_and_limits_are_read() {
        assert_eq!(
            parse_well_known_client(
                &json!({"m.homeserver": {"base_url": "https://chat.oxisoft.net/"}})
            ),
            Some("https://chat.oxisoft.net/".to_owned())
        );
        assert_eq!(
            parse_well_known_server(&json!({"m.server": "chat.oxisoft.net:443"})),
            Some("chat.oxisoft.net:443".to_owned())
        );
        let support = parse_support(&json!({
            "contacts": [{"role": "m.role.admin", "email_address": "admin@example.org"}],
            "support_page": "https://example.org/help"
        }));
        assert_eq!(
            support,
            SupportInfo {
                contacts: vec![SupportContact {
                    role: "m.role.admin".to_owned(),
                    matrix_id: None,
                    email_address: Some("admin@example.org".to_owned()),
                }],
                support_page: Some("https://example.org/help".to_owned()),
            }
        );
        // chat.oxisoft.net has no support document: 404 M_NOT_FOUND.
        let missing = answer(404, json!({"errcode": "M_NOT_FOUND"}));
        assert_eq!(
            probe_document(Some(&missing), |body| Some(parse_support(body))),
            (Probe::NotFound, None)
        );
        assert_eq!(
            probe_document(None, |body| Some(parse_support(body))),
            (Probe::NoAnswer, None)
        );
        assert_eq!(
            parse_upload_limit(&json!({"m.upload.size": 52_428_800})),
            Some(52_428_800)
        );
        assert_eq!(parse_upload_limit(&json!({})), None);
    }
}
