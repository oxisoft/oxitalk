//! Shared by the integration tests: keeping a local copy of a diffed list, the way the app
//! does, and waiting until it shows something.

#![allow(dead_code, reason = "each test crate uses only some of the helpers")]

use std::{error::Error, future::Future, time::Duration};

use futures_util::{Stream, StreamExt};
use oxitalk_core::api::{
    error::CoreError,
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
    /// Applies batches until `done` holds for the list or `within` passed: `false` then.
    pub(crate) async fn holds_within(
        &mut self,
        within: Duration,
        done: impl Fn(&[T]) -> bool,
    ) -> Result<bool, Box<dyn Error>> {
        let waited = tokio::time::timeout(within, async {
            while !done(&self.items) {
                let batch = self.batches.recv().await.ok_or("the stream ended")?;
                for diff in batch {
                    (self.apply)(&mut self.items, diff);
                }
            }
            Ok::<_, Box<dyn Error>>(())
        })
        .await;
        match waited {
            Ok(result) => result.map(|()| true),
            Err(_) => Ok(false),
        }
    }

    /// Applies batches until `done` holds for the list. A timeout names the caller's line, so
    /// a failure on CI tells which wait it was.
    #[track_caller]
    pub(crate) fn wait_until<'a>(
        &'a mut self,
        done: impl Fn(&[T]) -> bool + 'a,
    ) -> impl Future<Output = TestResult> + 'a {
        let at = std::panic::Location::caller();
        async move {
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
            .map_err(|_| format!("timed out waiting for the list at {at}"))?
        }
    }
}

/// Calls `check` until it returns a value: for state that reaches the store with a later sync.
/// The shared pattern for anything a test reads after an action: wait for the condition with
/// a deadline, never for a fixed time or a single sync.
pub(crate) async fn poll_until<T, F, Fut>(what: &str, mut check: F) -> Result<T, Box<dyn Error>>
where
    F: FnMut() -> Fut,
    Fut: Future<Output = Result<Option<T>, CoreError>>,
{
    tokio::time::timeout(TIMEOUT, async {
        loop {
            if let Some(value) = check().await? {
                return Ok::<_, CoreError>(value);
            }
            tokio::time::sleep(Duration::from_millis(200)).await;
        }
    })
    .await
    .map_err(|_| format!("timed out waiting until {what}"))?
    .map_err(Into::into)
}

/// Takes values from `updates` until one satisfies `done`, within [`TIMEOUT`]: for streams of
/// whole states, where the sync may send an earlier state again before the awaited one.
pub(crate) async fn next_matching<T: std::fmt::Debug>(
    updates: &mut (impl Stream<Item = T> + Unpin),
    what: &str,
    done: impl Fn(&T) -> bool,
) -> Result<T, Box<dyn Error>> {
    let mut last = None;
    let found = tokio::time::timeout(TIMEOUT, async {
        while let Some(value) = updates.next().await {
            if done(&value) {
                return Some(value);
            }
            last = Some(value);
        }
        None
    })
    .await;
    match found {
        Ok(Some(value)) => Ok(value),
        Ok(None) => Err(format!("the stream ended before {what}; last: {last:?}").into()),
        Err(_) => Err(format!("timed out waiting until {what}; last: {last:?}").into()),
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
