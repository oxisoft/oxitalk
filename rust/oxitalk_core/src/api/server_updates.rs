//! Whether the account is an admin of its homeserver, and for admins only, whether the
//! server software (and the call media server) is on its latest release.
//!
//! The admin check asks only the user's own homeserver. The release check asks the
//! software's release page (GitHub, GitLab or Forgejo), so the app makes it only for an
//! account that administers the server and has the check on: other users never contact
//! those sites.

use std::{fmt::Write as _, time::Duration};

use matrix_sdk::{Client, RoomState, ruma::OwnedRoomAliasId};
use serde_json::Value;

use super::{error::CoreError, session::Session};

/// How long one request may take.
const REQUEST_TIMEOUT: Duration = Duration::from_secs(10);

/// How the installed version compares with the latest release.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ReleaseStatus {
    /// The installed version is the latest release (or newer).
    UpToDate,
    /// A newer release is out.
    Outdated,
    /// The installed version isn't known or can't be compared.
    Unknown,
    /// The project has stopped; there will be no newer release.
    Discontinued,
}

/// The latest release of a server project, and how the installed version compares.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ReleaseCheck {
    /// The project's name as shown: "Synapse", "LiveKit", …
    pub project: String,
    /// The latest release's version, without a leading `v`.
    pub latest: String,
    /// Where the release is described.
    pub url: String,
    pub status: ReleaseStatus,
    /// Something to know about the project, e.g. that it only gets security fixes.
    pub note: Option<String>,
}

/// Where a project publishes its releases.
enum Source {
    GitHub(&'static str),
    GitLab(&'static str),
    Forgejo(&'static str, &'static str),
    /// Archived: its last release, and where it was.
    Archived(&'static str, &'static str),
}

struct Project {
    name: &'static str,
    source: Source,
    note: Option<&'static str>,
}

/// The project behind [key]: a homeserver's software name as it reports it (any case), or
/// `livekit` / `lk-jwt-service`.
fn project(key: &str) -> Option<Project> {
    let (name, source, note) = match key.trim().to_ascii_lowercase().as_str() {
        "synapse" => ("Synapse", Source::GitHub("element-hq/synapse"), None),
        "tuwunel" => ("Tuwunel", Source::GitHub("matrix-construct/tuwunel"), None),
        "continuwuity" => (
            "Continuwuity",
            Source::Forgejo("forgejo.ellis.link", "continuwuation/continuwuity"),
            None,
        ),
        "conduit" => ("Conduit", Source::GitLab("famedly/conduit"), None),
        "dendrite" => (
            "Dendrite",
            Source::GitHub("element-hq/dendrite"),
            Some("Dendrite is in maintenance mode: security fixes only."),
        ),
        "conduwuit" => (
            "conduwuit",
            Source::Archived("0.4.6", "https://github.com/girlbossceo/conduwuit"),
            Some("conduwuit is discontinued; its successors are Tuwunel and Continuwuity."),
        ),
        "livekit" => ("LiveKit", Source::GitHub("livekit/livekit"), None),
        "lk-jwt-service" => (
            "lk-jwt-service",
            Source::GitHub("element-hq/lk-jwt-service"),
            None,
        ),
        _ => return None,
    };
    Some(Project { name, source, note })
}

impl Session {
    /// Whether this account administers its homeserver: Synapse's admin API says so, or
    /// the account is in the server's admin room `#admins:<server>` (Tuwunel,
    /// Continuwuity, conduwuit, Conduit). Asks only the homeserver.
    ///
    /// # Errors
    ///
    /// [`CoreError::SessionExpired`] if the session has been logged out; a server that
    /// doesn't answer counts as not admin.
    pub async fn is_server_admin(&self) -> Result<bool, CoreError> {
        is_server_admin_of(&self.client).await
    }

    /// The latest release of [project] (a homeserver software name as it reports it, or
    /// `livekit` / `lk-jwt-service`) and how [installed] compares; `None` for a project
    /// not followed or a release page that doesn't answer. Asks the project's release
    /// page, so the app calls it only for server admins who have the check on.
    pub async fn latest_release(
        &self,
        project: String,
        installed: Option<String>,
    ) -> Option<ReleaseCheck> {
        latest_release_of(&self.client, &project, installed.as_deref()).await
    }
}

async fn is_server_admin_of(client: &Client) -> Result<bool, CoreError> {
    let user_id = client
        .user_id()
        .ok_or(CoreError::SessionExpired)?
        .to_owned();
    let alias = OwnedRoomAliasId::try_from(format!("#admins:{}", user_id.server_name()));
    let in_admin_room = async {
        let Ok(alias) = alias else { return false };
        match client.resolve_room_alias(&alias).await {
            Ok(found) => client
                .get_room(&found.room_id)
                .is_some_and(|room| room.state() == RoomState::Joined),
            Err(_) => false,
        }
    };
    let synapse_admin = async {
        let Some(token) = client.access_token() else {
            return false;
        };
        let base = client.homeserver();
        let url = format!(
            "{}/_synapse/admin/v1/users/{}/admin",
            base.as_str().trim_end_matches('/'),
            urlencode(user_id.as_str()),
        );
        let Ok(response) = client
            .http_client()
            .get(url)
            .bearer_auth(token)
            .timeout(REQUEST_TIMEOUT)
            .send()
            .await
        else {
            return false;
        };
        if !response.status().is_success() {
            return false;
        }
        response
            .bytes()
            .await
            .ok()
            .and_then(|body| serde_json::from_slice::<Value>(&body).ok())
            .and_then(|body| body.get("admin")?.as_bool())
            .unwrap_or(false)
    };
    let (room, synapse) = futures_util::future::join(in_admin_room, synapse_admin).await;
    Ok(room || synapse)
}

/// Percent-encodes a user ID for a path segment.
fn urlencode(value: &str) -> String {
    let mut out = String::with_capacity(value.len() * 3);
    for byte in value.bytes() {
        if byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_' | b'.' | b'~') {
            out.push(char::from(byte));
        } else {
            let _ = write!(out, "%{byte:02X}");
        }
    }
    out
}

async fn latest_release_of(
    client: &Client,
    key: &str,
    installed: Option<&str>,
) -> Option<ReleaseCheck> {
    let project = project(key)?;
    let note = project.note.map(str::to_owned);
    let (latest, url) = match project.source {
        Source::Archived(version, url) => {
            return Some(ReleaseCheck {
                project: project.name.to_owned(),
                latest: version.to_owned(),
                url: url.to_owned(),
                status: ReleaseStatus::Discontinued,
                note,
            });
        }
        Source::GitHub(repo) => {
            let body = get_json(
                client,
                &format!("https://api.github.com/repos/{repo}/releases/latest"),
            )
            .await?;
            parse_release(&body)?
        }
        Source::Forgejo(host, repo) => {
            let body = get_json(
                client,
                &format!("https://{host}/api/v1/repos/{repo}/releases/latest"),
            )
            .await?;
            parse_release(&body)?
        }
        Source::GitLab(repo) => {
            let body = get_json(
                client,
                &format!(
                    "https://gitlab.com/api/v4/projects/{}/releases?per_page=1",
                    urlencode(repo)
                ),
            )
            .await?;
            let release = body.as_array()?.first()?;
            let (latest, _) = parse_release(release)?;
            let url = release
                .pointer("/_links/self")
                .and_then(Value::as_str)
                .map_or_else(
                    || format!("https://gitlab.com/{repo}/-/releases"),
                    str::to_owned,
                );
            (latest, url)
        }
    };
    Some(ReleaseCheck {
        project: project.name.to_owned(),
        status: compare(installed, &latest),
        latest,
        url,
        note,
    })
}

async fn get_json(client: &Client, url: &str) -> Option<Value> {
    let response = client
        .http_client()
        .get(url)
        .header("user-agent", "OxiTalk")
        .header("accept", "application/json")
        .timeout(REQUEST_TIMEOUT)
        .send()
        .await
        .inspect_err(|error| tracing::debug!("release check: {url}: {error}"))
        .ok()?;
    if !response.status().is_success() {
        tracing::debug!("release check: {url}: {}", response.status());
        return None;
    }
    serde_json::from_slice(&response.bytes().await.ok()?).ok()
}

/// A release's version (without `v`) and page, from GitHub's, Forgejo's or GitLab's answer.
fn parse_release(body: &Value) -> Option<(String, String)> {
    let tag = body.get("tag_name")?.as_str()?;
    let version = tag.trim_start_matches(['v', 'V']).to_owned();
    let url = body
        .get("html_url")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_owned();
    Some((version, url))
}

/// The leading numbers of a version: `1.9.4` of `v1.9.4`, `1.9.4 (abc)`, `1.9.4-rc1`.
fn numbers(version: &str) -> Option<Vec<u64>> {
    let core = version
        .trim()
        .trim_start_matches(['v', 'V'])
        .split(|c: char| !(c.is_ascii_digit() || c == '.'))
        .next()?;
    let parts: Vec<u64> = core
        .split('.')
        .filter(|part| !part.is_empty())
        .map(str::parse)
        .collect::<Result<_, _>>()
        .ok()?;
    (!parts.is_empty()).then_some(parts)
}

/// How [installed] compares with [latest]; a pre-release of the latest counts as older.
pub(crate) fn compare(installed: Option<&str>, latest: &str) -> ReleaseStatus {
    let (Some(installed), Some(latest_numbers)) = (installed, numbers(latest)) else {
        return ReleaseStatus::Unknown;
    };
    let Some(mut have) = numbers(installed) else {
        return ReleaseStatus::Unknown;
    };
    let mut want = latest_numbers;
    let len = have.len().max(want.len());
    have.resize(len, 0);
    want.resize(len, 0);
    match have.cmp(&want) {
        std::cmp::Ordering::Greater => ReleaseStatus::UpToDate,
        std::cmp::Ordering::Less => ReleaseStatus::Outdated,
        std::cmp::Ordering::Equal => {
            let pre = installed
                .trim()
                .trim_start_matches(['v', 'V'])
                .split_once('-')
                .is_some_and(|(_, rest)| {
                    let rest = rest.to_ascii_lowercase();
                    rest.starts_with("rc") || rest.starts_with("alpha") || rest.starts_with("beta")
                });
            if pre {
                ReleaseStatus::Outdated
            } else {
                ReleaseStatus::UpToDate
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::*;

    #[test]
    fn versions_compare_by_their_numbers() {
        assert_eq!(compare(Some("1.9.4"), "1.9.4"), ReleaseStatus::UpToDate);
        assert_eq!(compare(Some("v1.9.4"), "1.9.4"), ReleaseStatus::UpToDate);
        assert_eq!(compare(Some("1.162.0"), "1.164.1"), ReleaseStatus::Outdated);
        assert_eq!(compare(Some("1.10.0"), "1.9.4"), ReleaseStatus::UpToDate);
        assert_eq!(compare(Some("1.9"), "1.9.0"), ReleaseStatus::UpToDate);
        assert_eq!(
            compare(Some("1.9.4 (abc123)"), "1.9.4"),
            ReleaseStatus::UpToDate
        );
        assert_eq!(compare(Some("1.9.4-rc1"), "1.9.4"), ReleaseStatus::Outdated);
        assert_eq!(compare(Some("1.9.5-rc1"), "1.9.4"), ReleaseStatus::UpToDate);
        assert_eq!(compare(None, "1.9.4"), ReleaseStatus::Unknown);
        assert_eq!(compare(Some("main"), "1.9.4"), ReleaseStatus::Unknown);
    }

    #[test]
    fn the_projects_followed() {
        for key in [
            "Synapse",
            "Tuwunel",
            "continuwuity",
            "Conduit",
            "Dendrite",
            "conduwuit",
            "livekit",
            "lk-jwt-service",
        ] {
            assert!(project(key).is_some(), "{key}");
        }
        assert!(project("nginx").is_none());
    }

    #[test]
    fn a_release_answer_gives_its_version_and_page() {
        let github = json!({"tag_name": "v1.164.1", "html_url": "https://github.com/element-hq/synapse/releases/tag/v1.164.1"});
        assert_eq!(
            parse_release(&github),
            Some((
                "1.164.1".to_owned(),
                "https://github.com/element-hq/synapse/releases/tag/v1.164.1".to_owned()
            ))
        );
        assert_eq!(parse_release(&json!({})), None);
    }

    #[test]
    fn user_ids_are_encoded_for_a_path() {
        assert_eq!(
            urlencode("@alex:chat.oxisoft.net"),
            "%40alex%3Achat.oxisoft.net"
        );
        assert_eq!(urlencode("famedly/conduit"), "famedly%2Fconduit");
    }
}
