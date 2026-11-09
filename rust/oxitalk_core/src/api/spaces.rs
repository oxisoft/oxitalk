//! Matrix spaces, through the SDK's `SpaceService`: the account's top-level joined spaces with
//! the joined rooms inside each (recursively), a space's children for browsing, and leaving a
//! space with the rooms the user picks. Nothing is written to account data: the app keeps the
//! selected space itself, so Element is unaffected.

use std::collections::HashSet;

use flutter_rust_bridge::frb;
use futures_util::{Stream, StreamExt, stream};
use matrix_sdk::{
    Client, RoomState,
    ruma::{OwnedRoomId, room::RoomType},
};
use matrix_sdk_ui::{
    eyeball_im::{Vector, VectorDiff},
    spaces::{
        SpaceFilter, SpaceRoom, SpaceRoomList, SpaceService,
        leave::{LeaveSpaceHandle, LeaveSpaceRoom},
        room_list::SpaceRoomListPaginationState,
    },
};
use tokio::sync::broadcast;

use super::{
    error::{CoreError, parse_id},
    session::Session,
};
use crate::frb_generated::StreamSink;

/// How many pages of a space's children [`Session::space_children`] reads at most; the
/// server's page is about 20 rooms.
const MAX_CHILD_PAGES: usize = 50;

/// One of the account's top-level joined spaces, in the order Element shows them.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SpaceSummary {
    pub space_id: String,
    pub name: String,
    /// An `mxc://` URI.
    pub avatar_url: Option<String>,
    /// The space's main address, like `#team:example.org`.
    pub alias: Option<String>,
    /// The joined rooms in the space or in any space below it, each once. Subspaces aren't
    /// listed themselves; direct chats are only there if someone added them.
    pub room_ids: Vec<String>,
}

/// A room or subspace in a space, as the server's hierarchy lists it: joined or not.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SpaceChild {
    pub room_id: String,
    pub name: String,
    pub topic: Option<String>,
    /// An `mxc://` URI.
    pub avatar_url: Option<String>,
    pub alias: Option<String>,
    pub joined_members: u32,
    pub is_space: bool,
    /// The user is in it.
    pub joined: bool,
    /// The servers to join it through, as the space names them.
    pub via: Vec<String>,
    /// The space's admins suggest it.
    pub suggested: bool,
}

/// A joined room that leaving a space can leave too.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SpaceLeaveRoom {
    pub room_id: String,
    pub name: String,
    pub is_space: bool,
    /// The user is its last admin: nobody could manage it after.
    pub last_admin: bool,
}

impl Session {
    /// Sends the account's top-level joined spaces, then the whole list again whenever it or
    /// the rooms in a space change.
    pub async fn subscribe_spaces(&self, sink: StreamSink<Vec<SpaceSummary>>) {
        let mut updates = self.spaces_updates().await;
        self.spawn(async move {
            while let Some(spaces) = updates.next().await {
                if sink.add(spaces).is_err() {
                    break;
                }
            }
        });
    }

    /// Like [`Self::subscribe_spaces`], for Rust callers.
    #[frb(ignore)]
    pub async fn spaces_updates(
        &self,
    ) -> impl Stream<Item = Vec<SpaceSummary>> + Send + Unpin + 'static {
        snapshots(self.client.clone(), &self.spaces).await
    }

    /// The rooms and subspaces directly in the space, joined or not, in the space's order.
    ///
    /// # Errors
    ///
    /// [`CoreError::InvalidId`], otherwise as the server answers.
    pub async fn space_children(&self, space_id: String) -> Result<Vec<SpaceChild>, CoreError> {
        let id: OwnedRoomId = parse_id(&space_id)?;
        let list = self.spaces.space_room_list(id).await;
        all_children(&list).await
    }

    /// The joined rooms (and subspaces) inside the space that leaving it could leave too,
    /// the space itself left out.
    ///
    /// # Errors
    ///
    /// [`CoreError::InvalidId`], or [`CoreError::RoomNotFound`] for a space the user isn't in.
    pub async fn leave_space_preview(
        &self,
        space_id: String,
    ) -> Result<Vec<SpaceLeaveRoom>, CoreError> {
        let id: OwnedRoomId = parse_id(&space_id)?;
        let handle = self
            .spaces
            .leave_space(&id)
            .await
            .map_err(|_| CoreError::RoomNotFound { room_id: space_id })?;
        Ok(leave_rooms(handle.rooms(), &id))
    }

    /// Leaves the space and, of the rooms [`Self::leave_space_preview`] listed, those in
    /// `also_leave`; the rooms inside first, the space last.
    ///
    /// # Errors
    ///
    /// [`CoreError::InvalidId`], [`CoreError::RoomNotFound`], otherwise as the server
    /// answers; the rooms left before the error stay left.
    pub async fn leave_space(
        &self,
        space_id: String,
        also_leave: Vec<String>,
    ) -> Result<(), CoreError> {
        let id: OwnedRoomId = parse_id(&space_id)?;
        let handle = self
            .spaces
            .leave_space(&id)
            .await
            .map_err(|_| CoreError::RoomNotFound {
                room_id: space_id.clone(),
            })?;
        leave_chosen(&handle, &id, also_leave).await
    }
}

/// Leaves `space_id` and the rooms of `also_leave` that `handle` lists.
async fn leave_chosen(
    handle: &LeaveSpaceHandle,
    space_id: &OwnedRoomId,
    also_leave: Vec<String>,
) -> Result<(), CoreError> {
    let chosen: HashSet<String> = also_leave.into_iter().collect();
    handle
        .leave(|room| {
            &room.space_room.room_id == space_id
                || chosen.contains(room.space_room.room_id.as_str())
        })
        .await
        .map_err(|error| CoreError::internal(&error))
}

/// What the snapshot task waits for.
enum SpacesInput {
    Filters(Vec<VectorDiff<SpaceFilter>>),
    /// A sync changed some rooms: one may have been joined or left inside a space.
    Rooms,
}

/// The first snapshot, then a new one whenever it changes.
pub(crate) async fn snapshots(
    client: Client,
    service: &SpaceService,
) -> impl Stream<Item = Vec<SpaceSummary>> + Send + Unpin + 'static {
    // Subscribed before the first snapshot, so no change falls in between.
    let room_updates = client.subscribe_to_all_room_updates();
    let (initial, filter_diffs) = service.subscribe_to_space_filters().await;
    let room_changes = Box::pin(stream::unfold(room_updates, |mut receiver| async move {
        match receiver.recv().await {
            // A lagging receiver missed some updates; a new snapshot covers them.
            Ok(_) | Err(broadcast::error::RecvError::Lagged(_)) => {
                Some((SpacesInput::Rooms, receiver))
            }
            Err(broadcast::error::RecvError::Closed) => None,
        }
    }));

    let inputs = Box::pin(stream::select(
        filter_diffs.map(SpacesInput::Filters),
        room_changes,
    ));
    let first = snapshot(&client, &initial);
    Box::pin(
        stream::once(std::future::ready(first.clone())).chain(stream::unfold(
            (inputs, initial, first, client),
            |(mut inputs, mut filters, mut last, client)| async move {
                loop {
                    match inputs.next().await? {
                        SpacesInput::Filters(diffs) => {
                            for diff in diffs {
                                diff.apply(&mut filters);
                            }
                        }
                        SpacesInput::Rooms => {}
                    }
                    let next = snapshot(&client, &filters);
                    if next != last {
                        last.clone_from(&next);
                        return Some((next, (inputs, filters, last, client)));
                    }
                }
            },
        )),
    )
}

/// The top-level spaces of the SDK's space filters, each with the joined rooms of its own
/// filter (its direct children) and of the subspace filters after it (their descendants,
/// recursively), each room once.
pub(crate) fn snapshot(client: &Client, filters: &Vector<SpaceFilter>) -> Vec<SpaceSummary> {
    let mut spaces: Vec<(SpaceSummary, HashSet<OwnedRoomId>)> = Vec::new();
    for filter in filters {
        if filter.level == 0 {
            spaces.push((summary_of(&filter.space_room), HashSet::new()));
        }
        // A subspace filter belongs to the top-level space before it.
        let Some((space, seen)) = spaces.last_mut() else {
            continue;
        };
        for id in &filter.descendants {
            if !seen.insert(id.clone()) {
                continue;
            }
            let joined_room = client
                .get_room(id)
                .is_some_and(|room| room.state() == RoomState::Joined && !room.is_space());
            if joined_room {
                space.room_ids.push(id.to_string());
            }
        }
    }
    spaces.into_iter().map(|(space, _)| space).collect()
}

fn summary_of(space: &SpaceRoom) -> SpaceSummary {
    SpaceSummary {
        space_id: space.room_id.to_string(),
        name: space.display_name.clone(),
        avatar_url: space.avatar_url.as_ref().map(ToString::to_string),
        alias: space.canonical_alias.as_ref().map(ToString::to_string),
        room_ids: Vec::new(),
    }
}

/// Every page of the list's children.
pub(crate) async fn all_children(list: &SpaceRoomList) -> Result<Vec<SpaceChild>, CoreError> {
    for _ in 0..MAX_CHILD_PAGES {
        if list.pagination_state() == (SpaceRoomListPaginationState::Idle { end_reached: true }) {
            break;
        }
        list.paginate()
            .await
            .map_err(|error| CoreError::internal(&error))?;
    }
    Ok(list.rooms().await.iter().map(child_of).collect())
}

fn child_of(room: &SpaceRoom) -> SpaceChild {
    SpaceChild {
        room_id: room.room_id.to_string(),
        name: room.display_name.clone(),
        topic: room.topic.clone().filter(|topic| !topic.trim().is_empty()),
        avatar_url: room.avatar_url.as_ref().map(ToString::to_string),
        alias: room.canonical_alias.as_ref().map(ToString::to_string),
        joined_members: u32::try_from(room.num_joined_members).unwrap_or(u32::MAX),
        is_space: room.room_type == Some(RoomType::Space),
        joined: room.state == Some(RoomState::Joined),
        via: room.via.iter().map(ToString::to_string).collect(),
        suggested: room.suggested,
    }
}

fn leave_rooms(rooms: &[LeaveSpaceRoom], space_id: &OwnedRoomId) -> Vec<SpaceLeaveRoom> {
    rooms
        .iter()
        .filter(|room| &room.space_room.room_id != space_id)
        .map(|room| SpaceLeaveRoom {
            room_id: room.space_room.room_id.to_string(),
            name: room.space_room.display_name.clone(),
            is_space: room.space_room.room_type == Some(RoomType::Space),
            last_admin: room.is_last_owner,
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use std::{
        sync::atomic::{AtomicUsize, Ordering},
        time::Duration,
    };

    use matrix_sdk::{
        config::SyncSettings,
        ruma::{OwnedRoomId, RoomId, owned_room_id},
        test_utils::mocks::MatrixMockServer,
    };
    use matrix_sdk_ui::room_list_service::RoomListItem;
    use serde_json::{Value, json};
    use wiremock::ResponseTemplate;

    use super::*;
    use crate::api::room_list::summary;

    type TestResult = Result<(), Box<dyn std::error::Error>>;

    const ME: &str = "@example:localhost";

    fn state(kind: &str, key: &str, content: &Value) -> Value {
        json!({
            "type": kind,
            "state_key": key,
            "content": content,
            "sender": ME,
            "event_id": format!("${kind}-{key}-{}", content.to_string().len()),
            "origin_server_ts": 1_700_000_000_000_u64,
        })
    }

    /// A joined room's state: create (a space with `space`), the user's membership, a name,
    /// and an `m.space.child` for each of `children`.
    fn joined(name: &str, space: bool, children: &[&str]) -> Value {
        let mut create = json!({ "creator": ME, "room_version": "10" });
        if space {
            create["type"] = json!("m.space");
        }
        let mut events = vec![
            state("m.room.create", "", &create),
            state("m.room.member", ME, &json!({ "membership": "join" })),
            state("m.room.name", "", &json!({ "name": name })),
            state("m.room.power_levels", "", &json!({ "users": { ME: 100 } })),
        ];
        for child in children {
            events.push(state(
                "m.space.child",
                child,
                &json!({ "via": ["localhost"] }),
            ));
        }
        json!({
            "state": { "events": events },
            "timeline": { "events": [], "limited": false },
            "summary": { "m.joined_member_count": 1 },
        })
    }

    /// A new sync token each time, as a server gives.
    fn next_batch() -> String {
        static BATCH: AtomicUsize = AtomicUsize::new(0);
        format!("s{}", BATCH.fetch_add(1, Ordering::Relaxed))
    }

    async fn sync(server: &MatrixMockServer, client: &Client, rooms: Value) -> TestResult {
        let _scope = server
            .mock_sync()
            .ok_json(json!({ "next_batch": next_batch(), "rooms": rooms }))
            .mount_as_scoped()
            .await;
        client.sync_once(SyncSettings::default()).await?;
        Ok(())
    }

    async fn client(server: &MatrixMockServer) -> Client {
        server.mock_room_state_encryption().plain().mount().await;
        server.client_builder().build().await
    }

    fn id(id: &str) -> Result<OwnedRoomId, Box<dyn std::error::Error>> {
        Ok(RoomId::parse(id)?)
    }

    async fn current(client: &Client, service: &SpaceService) -> Vec<SpaceSummary> {
        snapshot(client, &Vector::from(service.space_filters().await))
    }

    fn rooms_of<'a>(spaces: &'a [SpaceSummary], space: &str) -> Vec<&'a str> {
        let mut ids: Vec<&str> = spaces
            .iter()
            .find(|summary| summary.space_id == space)
            .map(|summary| summary.room_ids.iter().map(String::as_str).collect())
            .unwrap_or_default();
        ids.sort_unstable();
        ids
    }

    /// A space with a room and a subspace, the subspace with a room and a subspace of its
    /// own with one more: the top-level space holds all three rooms, the subspaces aren't
    /// top-level spaces and aren't listed as rooms.
    #[tokio::test(flavor = "multi_thread")]
    async fn a_space_holds_the_rooms_of_its_subspaces_at_every_depth() -> TestResult {
        crate::api::init_app();
        let server = MatrixMockServer::new().await;
        let client = client(&server).await;
        sync(
            &server,
            &client,
            json!({ "join": {
                "!top:localhost": joined("Top", true, &["!r1:localhost", "!sub:localhost"]),
                "!sub:localhost": joined("Sub", true, &["!r2:localhost", "!deep:localhost"]),
                "!deep:localhost": joined("Deep", true, &["!r3:localhost"]),
                "!r1:localhost": joined("One", false, &[]),
                "!r2:localhost": joined("Two", false, &[]),
                "!r3:localhost": joined("Three", false, &[]),
                "!outside:localhost": joined("Outside", false, &[]),
            }}),
        )
        .await?;
        let service = SpaceService::new(client.clone()).await;

        let spaces = current(&client, &service).await;
        assert_eq!(
            spaces
                .iter()
                .map(|space| space.space_id.as_str())
                .collect::<Vec<_>>(),
            ["!top:localhost"]
        );
        assert_eq!(spaces[0].name, "Top");
        assert_eq!(
            rooms_of(&spaces, "!top:localhost"),
            ["!r1:localhost", "!r2:localhost", "!r3:localhost"]
        );
        Ok(())
    }

    /// Two spaces that name each other as children (servers don't stop it) give one
    /// top-level space with the rooms of both, and no endless loop.
    #[tokio::test(flavor = "multi_thread")]
    async fn spaces_in_a_cycle_end() -> TestResult {
        crate::api::init_app();
        let server = MatrixMockServer::new().await;
        let client = client(&server).await;
        sync(
            &server,
            &client,
            json!({ "join": {
                "!a:localhost": joined("A", true, &["!b:localhost", "!ra:localhost"]),
                "!b:localhost": joined("B", true, &["!a:localhost", "!rb:localhost"]),
                "!ra:localhost": joined("Ra", false, &[]),
                "!rb:localhost": joined("Rb", false, &[]),
            }}),
        )
        .await?;
        let service = SpaceService::new(client.clone()).await;

        let spaces = current(&client, &service).await;
        assert_eq!(spaces.len(), 1, "{spaces:?}");
        assert_eq!(
            rooms_of(&spaces, &spaces[0].space_id),
            ["!ra:localhost", "!rb:localhost"]
        );
        Ok(())
    }

    /// A room in two spaces is in both; a child the user hasn't joined is in neither.
    #[tokio::test(flavor = "multi_thread")]
    async fn a_room_in_two_spaces_is_in_both_and_unjoined_ones_in_none() -> TestResult {
        crate::api::init_app();
        let server = MatrixMockServer::new().await;
        let client = client(&server).await;
        sync(
            &server,
            &client,
            json!({ "join": {
                "!a:localhost": joined("A", true, &["!shared:localhost", "!notjoined:localhost"]),
                "!b:localhost": joined("B", true, &["!shared:localhost"]),
                "!shared:localhost": joined("Shared", false, &[]),
            }}),
        )
        .await?;
        let service = SpaceService::new(client.clone()).await;

        let spaces = current(&client, &service).await;
        assert_eq!(spaces.len(), 2);
        assert_eq!(rooms_of(&spaces, "!a:localhost"), ["!shared:localhost"]);
        assert_eq!(rooms_of(&spaces, "!b:localhost"), ["!shared:localhost"]);
        Ok(())
    }

    /// The stream sends the spaces at once, and again when a room inside one is joined.
    #[tokio::test(flavor = "multi_thread")]
    async fn the_snapshot_follows_a_room_joined_in_a_space() -> TestResult {
        crate::api::init_app();
        let server = MatrixMockServer::new().await;
        let client = client(&server).await;
        sync(
            &server,
            &client,
            json!({ "join": {
                "!a:localhost": joined("A", true, &["!later:localhost"]),
            }}),
        )
        .await?;
        let service = SpaceService::new(client.clone()).await;
        let mut updates = snapshots(client.clone(), &service).await;

        let first = tokio::time::timeout(Duration::from_secs(10), updates.next())
            .await?
            .ok_or("no first snapshot")?;
        assert_eq!(rooms_of(&first, "!a:localhost"), Vec::<&str>::new());

        sync(
            &server,
            &client,
            json!({ "join": { "!later:localhost": joined("Later", false, &[]) } }),
        )
        .await?;
        let next = tokio::time::timeout(Duration::from_secs(10), updates.next())
            .await?
            .ok_or("no snapshot after the join")?;
        assert_eq!(rooms_of(&next, "!a:localhost"), ["!later:localhost"]);
        Ok(())
    }

    /// The chat list's summary tells a space from a room.
    #[tokio::test(flavor = "multi_thread")]
    async fn the_room_summary_tells_a_space() -> TestResult {
        crate::api::init_app();
        let server = MatrixMockServer::new().await;
        let client = client(&server).await;
        sync(
            &server,
            &client,
            json!({ "join": {
                "!a:localhost": joined("A", true, &[]),
                "!r:localhost": joined("R", false, &[]),
            }}),
        )
        .await?;
        let settings = client.notification_settings().await;
        let space = client.get_room(&id("!a:localhost")?).ok_or("no space")?;
        let room = client.get_room(&id("!r:localhost")?).ok_or("no room")?;
        assert!(summary(&settings, RoomListItem::from(space)).await.is_space);
        assert!(!summary(&settings, RoomListItem::from(room)).await.is_space);
        Ok(())
    }

    fn hierarchy_room(id: &str, name: &str, space: bool) -> Value {
        let mut room = json!({
            "room_id": id,
            "name": name,
            "num_joined_members": 3,
            "world_readable": false,
            "guest_can_join": false,
            "join_rule": "public",
            "children_state": [],
        });
        if space {
            room["room_type"] = json!("m.space");
        }
        room
    }

    fn child_state(id: &str) -> Value {
        json!({
            "type": "m.space.child",
            "state_key": id,
            "content": { "via": ["other.org"] },
            "sender": "@admin:other.org",
            "origin_server_ts": 1_700_000_000_000_u64,
        })
    }

    /// The children come from every page of the server's hierarchy, joined ones marked, the
    /// space itself left out.
    #[tokio::test(flavor = "multi_thread")]
    async fn the_children_are_read_page_by_page() -> TestResult {
        crate::api::init_app();
        let server = MatrixMockServer::new().await;
        let client = client(&server).await;
        sync(
            &server,
            &client,
            json!({ "join": {
                "!a:localhost": joined("A", true, &["!in:localhost"]),
                "!in:localhost": joined("Joined", false, &[]),
            }}),
        )
        .await?;
        let mut space = hierarchy_room("!a:localhost", "A", true);
        space["children_state"] = json!([
            child_state("!in:localhost"),
            child_state("!out:other.org"),
            child_state("!sub:other.org"),
        ]);
        server
            .mock_get_hierarchy()
            .respond_with(ResponseTemplate::new(200).set_body_json(json!({
                "rooms": [space, hierarchy_room("!in:localhost", "Joined", false)],
                "next_batch": "page2",
            })))
            .up_to_n_times(1)
            .mount()
            .await;
        server
            .mock_get_hierarchy()
            .ok_json(json!({
                "rooms": [
                    hierarchy_room("!out:other.org", "Not joined", false),
                    hierarchy_room("!sub:other.org", "Subspace", true),
                ],
            }))
            .mount()
            .await;
        let list = SpaceRoomList::new(client.clone(), owned_room_id!("!a:localhost")).await;

        let children = all_children(&list).await?;
        let mut seen: Vec<(&str, bool, bool)> = children
            .iter()
            .map(|child| (child.room_id.as_str(), child.joined, child.is_space))
            .collect();
        seen.sort_unstable();
        assert_eq!(
            seen,
            [
                ("!in:localhost", true, false),
                ("!out:other.org", false, false),
                ("!sub:other.org", false, true),
            ]
        );
        let out = children
            .iter()
            .find(|child| child.room_id == "!out:other.org")
            .ok_or("no child")?;
        assert_eq!(out.via, ["other.org"]);
        assert_eq!(out.name, "Not joined");
        assert_eq!(out.joined_members, 3);
        Ok(())
    }

    /// Leaving lists the joined rooms inside (not the space, not unjoined children) and
    /// leaves the space with only the rooms picked.
    #[tokio::test(flavor = "multi_thread")]
    async fn leaving_a_space_leaves_only_the_rooms_picked() -> TestResult {
        crate::api::init_app();
        let server = MatrixMockServer::new().await;
        let client = client(&server).await;
        sync(
            &server,
            &client,
            json!({ "join": {
                "!a:localhost": joined("A", true, &["!keep:localhost", "!go:localhost", "!x:localhost"]),
                "!keep:localhost": joined("Keep", false, &[]),
                "!go:localhost": joined("Go", false, &[]),
            }}),
        )
        .await?;
        let service = SpaceService::new(client.clone()).await;
        let space = id("!a:localhost")?;
        let handle = service.leave_space(&space).await?;

        let mut preview: Vec<(String, bool)> = leave_rooms(handle.rooms(), &space)
            .into_iter()
            .map(|room| (room.room_id, room.last_admin))
            .collect();
        preview.sort_unstable();
        assert_eq!(
            preview,
            [
                ("!go:localhost".to_owned(), true),
                ("!keep:localhost".to_owned(), true),
            ]
        );

        // One mock answers for every room; the requests tell which were left.
        server.mock_room_leave().ok(&space).mount().await;
        leave_chosen(&handle, &space, vec!["!go:localhost".to_owned()]).await?;
        let left: Vec<String> = server
            .server()
            .received_requests()
            .await
            .unwrap_or_default()
            .iter()
            .filter(|request| request.url.path().ends_with("/leave"))
            .map(|request| request.url.path().to_owned())
            .collect();
        assert_eq!(left.len(), 2, "{left:?}");
        assert!(!left.iter().any(|path| path.contains("keep")), "{left:?}");
        Ok(())
    }
}
