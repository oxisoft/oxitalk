//! The timeline's small notices: what happened in a room besides messages (who joined or
//! left, a new name or topic, a poll, a call), as data the app turns into one line.

use matrix_sdk::ruma::{
    UserId,
    events::{
        StateEventContentChange,
        room::{
            history_visibility::HistoryVisibility as SdkHistoryVisibility,
            join_rules::JoinRule as SdkJoinRule,
            message::MessageType,
            power_levels::{
                PossiblyRedactedRoomPowerLevelsEventContent, RoomPowerLevelsEventContent,
            },
        },
    },
};
use matrix_sdk_ui::timeline::{
    AnyOtherStateEventContentChange as Other, MemberProfileChange, MembershipChange as Sdk,
    MsgLikeKind, RoomMembershipChange, RoomPinnedEventsChange, TimelineItemContent as Content,
};

/// What a notice says happened. The actor is the event's sender (see `EventInfo`).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RoomNotice {
    /// Someone's membership changed; `user_id` is whose, which needn't be the sender's (an
    /// invite, a kick, a ban).
    Membership {
        user_id: String,
        /// Their name as the event tells it.
        user_name: Option<String>,
        /// The user is the account's own.
        user_is_own: bool,
        change: MembershipKind,
        /// Why, as the sender wrote (a kick, a ban, leaving).
        reason: Option<String>,
    },
    /// A member changed their name or picture.
    Profile {
        user_id: String,
        /// The name before, if it changed.
        old_name: Option<String>,
        /// The name after, if it changed; `None` with `name_changed` for a removed name.
        new_name: Option<String>,
        name_changed: bool,
        avatar_changed: bool,
        /// The picture was taken away, not replaced.
        avatar_removed: bool,
    },
    RoomCreated,
    /// The room's name changed; `None` (or empty) removed it.
    RoomName {
        name: Option<String>,
    },
    RoomTopic {
        topic: Option<String>,
    },
    RoomAvatar {
        removed: bool,
    },
    /// The room's main address changed; `None` removed it.
    RoomAlias {
        alias: Option<String>,
    },
    EncryptionEnabled,
    HistoryVisibility {
        visibility: HistoryVisibilityKind,
    },
    JoinRules {
        rule: JoinRuleKind,
    },
    /// Members' roles changed; `changes` lists those of users, empty when only the room's
    /// rules changed.
    PowerLevels {
        changes: Vec<PowerLevelChange>,
    },
    /// The pinned messages changed: only pins added, only removed, or both.
    Pinned {
        added: bool,
        removed: bool,
    },
    /// The room was replaced by a newer version.
    RoomUpgraded,
    Poll {
        question: String,
    },
    Sticker {
        body: String,
    },
    /// A location (`body` is the sender's description, often a `geo:` URI).
    Location {
        body: String,
    },
    LiveLocation,
    /// A call invitation (the old 1:1 calls), or a call started in the room.
    Call,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MembershipKind {
    Joined,
    Left,
    Invited,
    InviteAccepted,
    InviteDeclined,
    InviteRevoked,
    Kicked,
    Banned,
    KickedAndBanned,
    Unbanned,
    Knocked,
    KnockAccepted,
    KnockRetracted,
    KnockDenied,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HistoryVisibilityKind {
    /// Members see what was said from when they were invited.
    Invited,
    /// From when they joined.
    Joined,
    /// Everything, once they are members.
    Shared,
    /// Anyone, members or not.
    WorldReadable,
    Other,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum JoinRuleKind {
    Public,
    Invite,
    Knock,
    /// Members of some other room (a space) can join.
    Restricted,
    Other,
}

/// One user's role change.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PowerLevelChange {
    pub user_id: String,
    /// The level before; the room's default for users if they had none.
    pub old_level: i64,
    pub new_level: i64,
}

/// The notice for `content`, if it is one the app shows; `None` for messages and for events
/// it hides (a redacted state event, a policy rule, the first settings of a new room).
pub(crate) fn notice(content: &Content, own: &UserId) -> Option<RoomNotice> {
    match content {
        Content::MsgLike(msg) => match &msg.kind {
            MsgLikeKind::Message(message) => match message.msgtype() {
                MessageType::Location(location) => Some(RoomNotice::Location {
                    body: location.body.clone(),
                }),
                _ => None,
            },
            MsgLikeKind::Poll(poll) => Some(RoomNotice::Poll {
                question: poll.results().question,
            }),
            MsgLikeKind::Sticker(sticker) => Some(RoomNotice::Sticker {
                body: sticker.content().body.clone(),
            }),
            MsgLikeKind::LiveLocation(_) => Some(RoomNotice::LiveLocation),
            MsgLikeKind::Redacted | MsgLikeKind::UnableToDecrypt(_) | MsgLikeKind::Other(_) => None,
        },
        Content::MembershipChange(change) => membership(change, own),
        Content::ProfileChange(change) => profile(change),
        Content::OtherState(state) => other_state(state.content()),
        Content::CallInvite | Content::RtcNotification { .. } => Some(RoomNotice::Call),
        Content::FailedToParseMessageLike { .. } | Content::FailedToParseState { .. } => None,
    }
}

fn membership(change: &RoomMembershipChange, own: &UserId) -> Option<RoomNotice> {
    let kind = match change.change()? {
        Sdk::Joined => MembershipKind::Joined,
        Sdk::Left => MembershipKind::Left,
        Sdk::Invited => MembershipKind::Invited,
        Sdk::InvitationAccepted => MembershipKind::InviteAccepted,
        Sdk::InvitationRejected => MembershipKind::InviteDeclined,
        Sdk::InvitationRevoked => MembershipKind::InviteRevoked,
        Sdk::Kicked => MembershipKind::Kicked,
        Sdk::Banned => MembershipKind::Banned,
        Sdk::KickedAndBanned => MembershipKind::KickedAndBanned,
        Sdk::Unbanned => MembershipKind::Unbanned,
        Sdk::Knocked => MembershipKind::Knocked,
        Sdk::KnockAccepted => MembershipKind::KnockAccepted,
        Sdk::KnockRetracted => MembershipKind::KnockRetracted,
        Sdk::KnockDenied => MembershipKind::KnockDenied,
        Sdk::None | Sdk::Error | Sdk::NotImplemented => return None,
    };
    let reason = match change.content() {
        StateEventContentChange::Original { content, .. } => content
            .reason
            .clone()
            .filter(|reason| !reason.trim().is_empty()),
        StateEventContentChange::Redacted(_) => None,
    };
    Some(RoomNotice::Membership {
        user_id: change.user_id().to_string(),
        user_name: change.display_name().filter(|name| !name.trim().is_empty()),
        user_is_own: change.user_id() == own,
        change: kind,
        reason,
    })
}

fn profile(change: &MemberProfileChange) -> Option<RoomNotice> {
    let name = change.displayname_change().filter(|c| c.old != c.new);
    let avatar = change.avatar_url_change().filter(|c| c.old != c.new);
    if name.is_none() && avatar.is_none() {
        return None;
    }
    Some(RoomNotice::Profile {
        user_id: change.user_id().to_string(),
        old_name: name.and_then(|c| c.old.clone()),
        new_name: name.and_then(|c| c.new.clone()),
        name_changed: name.is_some(),
        avatar_changed: avatar.is_some(),
        avatar_removed: avatar.is_some_and(|c| c.new.is_none()),
    })
}

/// A state event other than a membership, if it is worth a line. The room's first settings
/// (join rules, history visibility, power levels without an earlier version) come with its
/// creation and are left out, as the creation says it all.
fn other_state(content: &Other) -> Option<RoomNotice> {
    match content {
        Other::RoomCreate(_) => Some(RoomNotice::RoomCreated),
        Other::RoomName(StateEventContentChange::Original { content, .. }) => {
            Some(RoomNotice::RoomName {
                name: Some(content.name.clone()).filter(|name| !name.trim().is_empty()),
            })
        }
        Other::RoomTopic(StateEventContentChange::Original { content, .. }) => {
            Some(RoomNotice::RoomTopic {
                topic: Some(content.topic.clone()).filter(|topic| !topic.trim().is_empty()),
            })
        }
        Other::RoomAvatar(StateEventContentChange::Original { content, .. }) => {
            Some(RoomNotice::RoomAvatar {
                removed: content.url.is_none(),
            })
        }
        Other::RoomCanonicalAlias(StateEventContentChange::Original {
            content,
            prev_content,
        }) => {
            let before = prev_content.as_ref().and_then(|prev| prev.alias.as_ref());
            // Only the main address is told; alt aliases alone change nothing shown.
            (before != content.alias.as_ref()).then(|| RoomNotice::RoomAlias {
                alias: content.alias.as_ref().map(ToString::to_string),
            })
        }
        Other::RoomEncryption(StateEventContentChange::Original { .. }) => {
            Some(RoomNotice::EncryptionEnabled)
        }
        Other::RoomHistoryVisibility(StateEventContentChange::Original {
            content,
            prev_content: Some(prev),
        }) if prev.history_visibility != content.history_visibility => {
            Some(RoomNotice::HistoryVisibility {
                visibility: match content.history_visibility {
                    SdkHistoryVisibility::Invited => HistoryVisibilityKind::Invited,
                    SdkHistoryVisibility::Joined => HistoryVisibilityKind::Joined,
                    SdkHistoryVisibility::Shared => HistoryVisibilityKind::Shared,
                    SdkHistoryVisibility::WorldReadable => HistoryVisibilityKind::WorldReadable,
                    _ => HistoryVisibilityKind::Other,
                },
            })
        }
        Other::RoomJoinRules(StateEventContentChange::Original {
            content,
            prev_content: Some(prev),
        }) if prev.join_rule != content.join_rule => Some(RoomNotice::JoinRules {
            rule: match content.join_rule {
                SdkJoinRule::Public => JoinRuleKind::Public,
                SdkJoinRule::Invite => JoinRuleKind::Invite,
                SdkJoinRule::Knock => JoinRuleKind::Knock,
                SdkJoinRule::Restricted(_) | SdkJoinRule::KnockRestricted(_) => {
                    JoinRuleKind::Restricted
                }
                _ => JoinRuleKind::Other,
            },
        }),
        Other::RoomPowerLevels(StateEventContentChange::Original {
            content,
            prev_content: Some(prev),
        }) => Some(RoomNotice::PowerLevels {
            changes: power_level_changes(prev, content),
        }),
        Other::RoomPinnedEvents(change @ StateEventContentChange::Original { .. }) => {
            let change = RoomPinnedEventsChange::from(change);
            Some(RoomNotice::Pinned {
                added: !matches!(change, RoomPinnedEventsChange::Removed),
                removed: !matches!(change, RoomPinnedEventsChange::Added),
            })
        }
        Other::RoomTombstone(StateEventContentChange::Original { .. }) => {
            Some(RoomNotice::RoomUpgraded)
        }
        _ => None,
    }
}

/// The users whose level differs between `prev` and `content`, in user ID order.
fn power_level_changes(
    prev: &PossiblyRedactedRoomPowerLevelsEventContent,
    content: &RoomPowerLevelsEventContent,
) -> Vec<PowerLevelChange> {
    let old_default = i64::from(prev.users_default);
    let new_default = i64::from(content.users_default);
    let mut users: Vec<_> = prev.users.keys().chain(content.users.keys()).collect();
    users.sort();
    users.dedup();
    users
        .into_iter()
        .filter_map(|user| {
            let old_level = prev
                .users
                .get(user)
                .map_or(old_default, |level| i64::from(*level));
            let new_level = content
                .users
                .get(user)
                .map_or(new_default, |level| i64::from(*level));
            (old_level != new_level).then(|| PowerLevelChange {
                user_id: user.to_string(),
                old_level,
                new_level,
            })
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::*;

    #[test]
    fn power_level_changes_list_the_users_whose_level_changed() -> Result<(), serde_json::Error> {
        let prev: PossiblyRedactedRoomPowerLevelsEventContent = serde_json::from_value(json!({
            "users": { "@admin:x": 100, "@mod:x": 50, "@gone:x": 50 },
            "users_default": 0,
        }))?;
        let content: RoomPowerLevelsEventContent = serde_json::from_value(json!({
            "users": { "@admin:x": 100, "@mod:x": 100, "@new:x": 50 },
            "users_default": 0,
        }))?;
        let change = |user: &str, old_level, new_level| PowerLevelChange {
            user_id: user.to_owned(),
            old_level,
            new_level,
        };
        assert_eq!(
            power_level_changes(&prev, &content),
            vec![
                change("@gone:x", 50, 0),
                change("@mod:x", 50, 100),
                change("@new:x", 0, 50),
            ]
        );
        Ok(())
    }

    #[test]
    fn a_new_default_counts_for_users_without_a_level() -> Result<(), serde_json::Error> {
        let prev: PossiblyRedactedRoomPowerLevelsEventContent =
            serde_json::from_value(json!({ "users": { "@a:x": 0 } }))?;
        let content: RoomPowerLevelsEventContent =
            serde_json::from_value(json!({ "users": {}, "users_default": 0 }))?;
        assert_eq!(power_level_changes(&prev, &content), vec![]);
        Ok(())
    }
}
