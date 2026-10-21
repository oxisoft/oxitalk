//! Notification settings, kept as push rules on the server the way Element and Element X keep
//! them, so a room muted here is muted there too: a mode per room, the account's defaults for
//! direct and group chats, @room mentions, invitations and keywords. Nothing here shows a
//! notification; it decides which messages count as notifying.

use flutter_rust_bridge::frb;
use futures_util::{Stream, StreamExt, stream};
use matrix_sdk::{
    Room,
    notification_settings::{
        IsEncrypted, IsOneToOne, NotificationSettings,
        RoomNotificationMode as SdkRoomNotificationMode,
    },
    ruma::{
        OwnedRoomId,
        push::{PredefinedOverrideRuleId, RuleKind},
    },
};
use tokio::sync::broadcast::{Receiver, error::RecvError};

use super::{
    error::{CoreError, parse_id},
    session::Session,
};
use crate::frb_generated::StreamSink;

/// What a room notifies for, as Element names the choices.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RoomNotificationMode {
    AllMessages,
    /// Only messages that mention the user (or @room) or contain one of their keywords.
    MentionsAndKeywordsOnly,
    /// Nothing; the room has no count badge either.
    Mute,
}

/// One kind of chat whose encrypted and unencrypted defaults differ, which only older clients
/// leave behind. Element X shows the kind as "All messages" and offers to fix it.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct InconsistentDefault {
    /// Direct chats (rooms of exactly two people), else group chats.
    pub one_to_one: bool,
    /// Which of the two rules is not "All messages", so the fix sets that one.
    pub encrypted: bool,
}

/// The account's notification settings.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NotificationSettingsState {
    /// The default for direct chats (rooms of exactly two people).
    pub dm_default: RoomNotificationMode,
    /// The default for every other room.
    pub group_default: RoomNotificationMode,
    /// Whether @room notifies; `None` if the server has no such rule.
    pub room_mentions: Option<bool>,
    /// Whether an invitation notifies; `None` if the server has no such rule.
    pub invites: Option<bool>,
    /// The words that make a message notify wherever it is sent, as typed.
    pub keywords: Vec<String>,
    /// Defaults left inconsistent by another client; empty when all is well.
    pub inconsistent: Vec<InconsistentDefault>,
}

/// A room's own mode and the account default it falls back to, for the room list.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) struct RoomModes {
    pub(crate) user_defined: Option<RoomNotificationMode>,
    pub(crate) default: RoomNotificationMode,
}

impl Session {
    /// Sends the account's notification settings, then the settings after every change, made
    /// here or on another device.
    #[allow(
        clippy::unused_async,
        reason = "async so flutter_rust_bridge runs it on its tokio runtime, which spawn needs"
    )]
    pub async fn subscribe_notification_settings(
        &self,
        sink: StreamSink<NotificationSettingsState>,
    ) {
        let mut updates = self.notification_settings_updates();
        self.spawn(async move {
            while let Some(state) = updates.next().await {
                if sink.add(state).is_err() {
                    break;
                }
            }
        });
    }

    /// Like [`Self::subscribe_notification_settings`], for Rust callers.
    #[frb(ignore)]
    pub fn notification_settings_updates(
        &self,
    ) -> impl Stream<Item = NotificationSettingsState> + Send + Unpin + 'static {
        let settings = self.notification_settings.clone();
        // Subscribed before the first read, so no change falls in between.
        let changes = settings_changes(settings.subscribe_to_changes());
        Box::pin(stream::once(async {}).chain(changes).then(move |()| {
            let settings = settings.clone();
            async move { settings_state(&settings).await }
        }))
    }

    /// The account's notification settings as they are now.
    pub async fn notification_settings(&self) -> NotificationSettingsState {
        settings_state(&self.notification_settings).await
    }

    /// Gives a room its own mode, or with `None` lets it follow the account's default again.
    ///
    /// # Errors
    ///
    /// [`CoreError::InvalidId`] for a malformed room ID, otherwise as the server answers.
    pub async fn set_room_notification_mode(
        &self,
        room_id: String,
        mode: Option<RoomNotificationMode>,
    ) -> Result<(), CoreError> {
        let room_id: OwnedRoomId = parse_id(&room_id)?;
        let settings = &self.notification_settings;
        match mode {
            Some(mode) => {
                settings
                    .set_room_notification_mode(&room_id, mode.into())
                    .await?;
            }
            None => settings.delete_user_defined_room_rules(&room_id).await?,
        }
        Ok(())
    }

    /// Sets the default for direct chats (`one_to_one`) or group chats, for encrypted and
    /// unencrypted rooms alike, as Element X does. A default can't be `Mute`.
    ///
    /// # Errors
    ///
    /// [`CoreError::Internal`] for [`RoomNotificationMode::Mute`], otherwise as the server
    /// answers.
    pub async fn set_default_notification_mode(
        &self,
        one_to_one: bool,
        mode: RoomNotificationMode,
    ) -> Result<(), CoreError> {
        if mode == RoomNotificationMode::Mute {
            return Err(CoreError::Internal {
                message: "a default notification mode can't be Mute".to_owned(),
            });
        }
        for encrypted in [true, false] {
            self.notification_settings
                .set_default_room_notification_mode(
                    IsEncrypted::from(encrypted),
                    IsOneToOne::from(one_to_one),
                    mode.into(),
                )
                .await?;
        }
        Ok(())
    }

    /// Makes inconsistent defaults consistent again as Element X does: the rule that isn't
    /// "All messages" becomes it.
    ///
    /// # Errors
    ///
    /// As the server answers.
    pub async fn fix_inconsistent_notification_defaults(&self) -> Result<(), CoreError> {
        let state = settings_state(&self.notification_settings).await;
        for wrong in state.inconsistent {
            self.notification_settings
                .set_default_room_notification_mode(
                    IsEncrypted::from(wrong.encrypted),
                    IsOneToOne::from(wrong.one_to_one),
                    SdkRoomNotificationMode::AllMessages,
                )
                .await?;
        }
        Ok(())
    }

    /// Whether @room notifies. Sets the legacy rule too where the server has it, as Element
    /// Web keeps both.
    ///
    /// # Errors
    ///
    /// As the server answers.
    pub async fn set_room_mentions_enabled(&self, enabled: bool) -> Result<(), CoreError> {
        let settings = &self.notification_settings;
        settings
            .set_push_rule_enabled(
                RuleKind::Override,
                PredefinedOverrideRuleId::IsRoomMention,
                enabled,
            )
            .await?;
        #[allow(deprecated, reason = "the legacy rule Element Web keeps in step")]
        let legacy = PredefinedOverrideRuleId::RoomNotif;
        match settings
            .set_push_rule_enabled(RuleKind::Override, legacy, enabled)
            .await
        {
            Err(error) if !error.is_rule_not_found() => Err(error.into()),
            _ => Ok(()),
        }
    }

    /// Whether an invitation to a room notifies.
    ///
    /// # Errors
    ///
    /// As the server answers.
    pub async fn set_invites_enabled(&self, enabled: bool) -> Result<(), CoreError> {
        Ok(self
            .notification_settings
            .set_push_rule_enabled(
                RuleKind::Override,
                PredefinedOverrideRuleId::InviteForMe,
                enabled,
            )
            .await?)
    }

    /// Makes messages containing `keyword` notify (in rooms that aren't muted).
    ///
    /// # Errors
    ///
    /// [`CoreError::InvalidId`] for an empty keyword, otherwise as the server answers.
    pub async fn add_notification_keyword(&self, keyword: String) -> Result<(), CoreError> {
        let keyword = keyword.trim();
        if keyword.is_empty() {
            return Err(CoreError::InvalidId { id: String::new() });
        }
        Ok(self
            .notification_settings
            .add_keyword(keyword.to_owned())
            .await?)
    }

    /// # Errors
    ///
    /// As the server answers.
    pub async fn remove_notification_keyword(&self, keyword: String) -> Result<(), CoreError> {
        Ok(self.notification_settings.remove_keyword(&keyword).await?)
    }

    /// Marks a room unread (or not) for the user's devices, as Element's "Mark as unread".
    ///
    /// # Errors
    ///
    /// [`CoreError::InvalidId`] or [`CoreError::RoomNotFound`], otherwise as the server
    /// answers.
    pub async fn set_marked_unread(&self, room_id: String, unread: bool) -> Result<(), CoreError> {
        Ok(self.room(&room_id)?.set_unread_flag(unread).await?)
    }

    /// Marks a room read up to its latest message and takes away its unread mark, as Element's
    /// "Mark as read" in the room list.
    ///
    /// # Errors
    ///
    /// [`CoreError::InvalidId`] or [`CoreError::RoomNotFound`], otherwise as the server
    /// answers.
    pub async fn mark_room_read(&self, room_id: String) -> Result<(), CoreError> {
        let room = self.room(&room_id)?;
        // A timeline knows the latest event that counts, as Element X goes by it too.
        self.timeline(room_id).await?.mark_as_read().await?;
        Ok(room.set_unread_flag(false).await?)
    }
}

/// A unit for every change to the push rules; a lagging receiver only skips some.
pub(crate) fn settings_changes(
    receiver: Receiver<()>,
) -> impl Stream<Item = ()> + Send + Unpin + 'static {
    Box::pin(stream::unfold(receiver, |mut receiver| async move {
        match receiver.recv().await {
            Ok(()) | Err(RecvError::Lagged(_)) => Some(((), receiver)),
            Err(RecvError::Closed) => None,
        }
    }))
}

/// The room's own mode and its default: a room of exactly two people follows the direct chat
/// default, as the SDK and Element X decide.
pub(crate) async fn room_modes(settings: &NotificationSettings, room: &Room) -> RoomModes {
    let user_defined = settings
        .get_user_defined_room_notification_mode(room.room_id())
        .await
        .map(Into::into);
    let default = settings
        .get_default_room_notification_mode(
            IsEncrypted::from(room.encryption_state().is_encrypted()),
            IsOneToOne::from(room.active_members_count() == 2),
        )
        .await
        .into();
    RoomModes {
        user_defined,
        default,
    }
}

async fn settings_state(settings: &NotificationSettings) -> NotificationSettingsState {
    let mut inconsistent = Vec::new();
    let mut default_for = async |one_to_one: bool| {
        let mode = |encrypted: bool| {
            settings.get_default_room_notification_mode(
                IsEncrypted::from(encrypted),
                IsOneToOne::from(one_to_one),
            )
        };
        let (encrypted, unencrypted) = (mode(true).await, mode(false).await);
        let (shown, wrong) = consistent_default(encrypted.into(), unencrypted.into());
        if let Some(encrypted) = wrong {
            inconsistent.push(InconsistentDefault {
                one_to_one,
                encrypted,
            });
        }
        shown
    };
    let dm_default = default_for(true).await;
    let group_default = default_for(false).await;
    #[allow(deprecated, reason = "the legacy rule older servers have instead")]
    let legacy_room_mention = PredefinedOverrideRuleId::RoomNotif;
    let room_mentions = match settings
        .is_push_rule_enabled(RuleKind::Override, PredefinedOverrideRuleId::IsRoomMention)
        .await
    {
        Ok(enabled) => Some(enabled),
        Err(_) => settings
            .is_push_rule_enabled(RuleKind::Override, legacy_room_mention)
            .await
            .ok(),
    };
    let invites = settings
        .is_push_rule_enabled(RuleKind::Override, PredefinedOverrideRuleId::InviteForMe)
        .await
        .ok();
    NotificationSettingsState {
        dm_default,
        group_default,
        room_mentions,
        invites,
        keywords: settings.enabled_keywords().await.into_iter().collect(),
        inconsistent,
    }
}

/// The default to show for a kind of chat from its encrypted and unencrypted rules, and, if
/// they differ, which one to fix (`true`: the encrypted one), as Element X decides.
fn consistent_default(
    encrypted: RoomNotificationMode,
    unencrypted: RoomNotificationMode,
) -> (RoomNotificationMode, Option<bool>) {
    if encrypted == unencrypted {
        (encrypted, None)
    } else {
        (
            RoomNotificationMode::AllMessages,
            Some(encrypted != RoomNotificationMode::AllMessages),
        )
    }
}

impl From<SdkRoomNotificationMode> for RoomNotificationMode {
    fn from(mode: SdkRoomNotificationMode) -> Self {
        match mode {
            SdkRoomNotificationMode::AllMessages => Self::AllMessages,
            SdkRoomNotificationMode::MentionsAndKeywordsOnly => Self::MentionsAndKeywordsOnly,
            SdkRoomNotificationMode::Mute => Self::Mute,
        }
    }
}

impl From<RoomNotificationMode> for SdkRoomNotificationMode {
    fn from(mode: RoomNotificationMode) -> Self {
        match mode {
            RoomNotificationMode::AllMessages => Self::AllMessages,
            RoomNotificationMode::MentionsAndKeywordsOnly => Self::MentionsAndKeywordsOnly,
            RoomNotificationMode::Mute => Self::Mute,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    use RoomNotificationMode::{AllMessages, MentionsAndKeywordsOnly, Mute};

    #[test]
    fn equal_defaults_show_as_they_are() {
        assert_eq!(
            consistent_default(MentionsAndKeywordsOnly, MentionsAndKeywordsOnly),
            (MentionsAndKeywordsOnly, None)
        );
        assert_eq!(
            consistent_default(AllMessages, AllMessages),
            (AllMessages, None)
        );
    }

    #[test]
    fn differing_defaults_show_all_messages_and_name_the_rule_to_fix() {
        assert_eq!(
            consistent_default(MentionsAndKeywordsOnly, AllMessages),
            (AllMessages, Some(true))
        );
        assert_eq!(
            consistent_default(AllMessages, MentionsAndKeywordsOnly),
            (AllMessages, Some(false))
        );
    }

    #[test]
    fn modes_map_both_ways() {
        for mode in [AllMessages, MentionsAndKeywordsOnly, Mute] {
            let sdk: SdkRoomNotificationMode = mode.into();
            assert_eq!(RoomNotificationMode::from(sdk), mode);
        }
    }
}
