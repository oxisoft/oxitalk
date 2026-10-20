//! Shared by the integration tests: keeping a local copy of a diffed list, the way the app
//! does, and waiting until it shows something.

#![allow(dead_code, reason = "each test crate uses only some of the helpers")]

use std::{error::Error, time::Duration};

use oxitalk_core::api::{
    room_list::{RoomListDiff, RoomSummary},
    session::Session,
    timeline::{Timeline, TimelineDiff, TimelineItem, TimelineItemContent},
};
use tokio::sync::mpsc;

pub(crate) type TestResult = Result<(), Box<dyn Error>>;

/// Long enough for a sync round trip and key exchange on a slow CI runner.
pub(crate) const TIMEOUT: Duration = Duration::from_secs(60);

/// Applies one diff to `$list`; the room list and the timeline diffs have the same cases.
macro_rules! apply {
    ($list:expr, $diff:expr, $Diff:ident) => {
        match $diff {
            $Diff::Append { values } => $list.extend(values),
            $Diff::Clear => $list.clear(),
            $Diff::PushFront { value } => $list.insert(0, value),
            $Diff::PushBack { value } => $list.push(value),
            $Diff::PopFront => {
                $list.remove(0);
            }
            $Diff::PopBack => {
                $list.pop();
            }
            $Diff::Insert { index, value } => $list.insert(index as usize, value),
            $Diff::Set { index, value } => $list[index as usize] = value,
            $Diff::Remove { index } => {
                $list.remove(index as usize);
            }
            $Diff::Truncate { length } => $list.truncate(length as usize),
            $Diff::Reset { values } => *$list = values,
        }
    };
}

/// A list kept up to date from batches of diffs.
pub(crate) struct Watched<T, D> {
    batches: mpsc::UnboundedReceiver<Vec<D>>,
    apply: fn(&mut Vec<T>, D),
    pub(crate) items: Vec<T>,
}

impl<T, D> Watched<T, D> {
    /// Applies batches until `done` holds for the list.
    pub(crate) async fn wait_until(&mut self, done: impl Fn(&[T]) -> bool) -> TestResult {
        tokio::time::timeout(TIMEOUT, async {
            while !done(&self.items) {
                let batch = self.batches.recv().await.ok_or("the stream ended")?;
                for diff in batch {
                    (self.apply)(&mut self.items, diff);
                }
            }
            Ok::<_, Box<dyn Error>>(())
        })
        .await
        .map_err(|_| "timed out waiting for the list")?
    }
}

pub(crate) async fn watch_rooms(
    session: &Session,
) -> Result<Watched<RoomSummary, RoomListDiff>, Box<dyn Error>> {
    let (sender, batches) = mpsc::unbounded_channel();
    session
        .room_list_updates(move |batch| sender.send(batch).is_ok())
        .await?;
    Ok(Watched {
        batches,
        apply: |list, diff| apply!(list, diff, RoomListDiff),
        items: Vec::new(),
    })
}

pub(crate) async fn watch_timeline(timeline: &Timeline) -> Watched<TimelineItem, TimelineDiff> {
    let (sender, batches) = mpsc::unbounded_channel();
    timeline
        .item_updates(move |batch| sender.send(batch).is_ok())
        .await;
    Watched {
        batches,
        apply: |list, diff| apply!(list, diff, TimelineDiff),
        items: Vec::new(),
    }
}

/// The text messages in a timeline, as `(body, is_own)`.
pub(crate) fn messages(items: &[TimelineItem]) -> Vec<(&str, bool)> {
    items
        .iter()
        .filter_map(|item| match &item.content {
            TimelineItemContent::Message { event, body, .. } => Some((body.as_str(), event.is_own)),
            _ => None,
        })
        .collect()
}
