import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../matrix/api/matrix.dart';

/// Whether [entry] is a membership or profile change: the kind Element folds together and
/// Settings › Messages can hide.
bool isMembershipNotice(TimelineEntry entry) =>
    entry is NoticeEntry &&
    (entry.notice is MembershipNotice || entry.notice is ProfileNotice);

/// For each position in [entries], the start of the run of two or more consecutive
/// membership notices it is in; `null` outside such a run.
List<int?> noticeRunStarts(List<TimelineEntry> entries) {
  final starts = List<int?>.filled(entries.length, null);
  var i = 0;
  while (i < entries.length) {
    if (!isMembershipNotice(entries[i])) {
      i++;
      continue;
    }
    var end = i;
    while (end + 1 < entries.length && isMembershipNotice(entries[end + 1])) {
      end++;
    }
    if (end > i) {
      for (var p = i; p <= end; p++) {
        starts[p] = i;
      }
    }
    i = end + 1;
  }
  return starts;
}

/// The one line a notice shows. [ownUserId] names the account, as "you". [missedCalls] are
/// the rings (by event ID) that stopped on this device unanswered.
String noticeText(
  NoticeEntry entry, {
  String? ownUserId,
  Set<String> missedCalls = const {},
}) {
  final actor = entry.isOwn ? 'You' : (entry.senderName ?? entry.sender);
  String user(String id, String? name, {bool own = false}) =>
      own || id == ownUserId ? 'you' : (name ?? _shortId(id));
  String capital(String text) =>
      text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);
  String possessive(String who) => who == 'you' ? 'your' : '$who’s';
  final their = entry.isOwn ? 'your' : 'their';
  return switch (entry.notice) {
    MembershipNotice(
      :final userId,
      :final userName,
      :final userIsOwn,
      :final change,
      :final reason,
    ) =>
      () {
        final whom = user(userId, userName, own: userIsOwn);
        final who = capital(whom);
        final because = reason == null ? '' : ': $reason';
        return switch (change) {
          MembershipChange.joined => '$who joined',
          MembershipChange.left => '$who left$because',
          MembershipChange.invited => '$actor invited $whom',
          MembershipChange.inviteAccepted => '$who accepted the invite',
          MembershipChange.inviteDeclined => '$who declined the invite',
          MembershipChange.inviteRevoked =>
            '$actor withdrew the invite for $whom',
          MembershipChange.kicked => '$actor removed $whom$because',
          MembershipChange.banned => '$actor banned $whom$because',
          MembershipChange.kickedAndBanned =>
            '$actor removed and banned $whom$because',
          MembershipChange.unbanned => '$actor unbanned $whom',
          MembershipChange.knocked => '$who asked to join',
          MembershipChange.knockAccepted => '$actor let $whom join',
          MembershipChange.knockRetracted => '$who no longer asks to join',
          MembershipChange.knockDenied =>
            '$actor declined ${possessive(whom)} request to join',
        };
      }(),
    ProfileNotice(
      :final oldName,
      :final newName,
      :final nameChanged,
      :final avatarChanged,
      :final avatarRemoved,
    ) =>
      () {
        // As Element: by the name they had.
        final who = entry.isOwn ? 'You' : (oldName ?? actor);
        final picture = avatarRemoved
            ? 'removed $their profile picture'
            : 'changed $their profile picture';
        if (!nameChanged) return '$who $picture';
        final name = switch (newName) {
          final name? when oldName == null => 'set $their name to $name',
          final name? => 'changed $their name to $name',
          null => 'removed $their name',
        };
        return avatarChanged ? '$who $name and $picture' : '$who $name';
      }(),
    RoomCreatedNotice() => '$actor created the room',
    RoomNameNotice(:final name?) => '$actor changed the room name to $name',
    RoomNameNotice() => '$actor removed the room name',
    RoomTopicNotice(:final topic?) => '$actor changed the topic to “$topic”',
    RoomTopicNotice() => '$actor removed the topic',
    RoomAvatarNotice(removed: true) => '$actor removed the room picture',
    RoomAvatarNotice() => '$actor changed the room picture',
    RoomAliasNotice(:final alias?) => '$actor set the room address to $alias',
    RoomAliasNotice() => '$actor removed the room address',
    EncryptionNotice() => '$actor turned on end-to-end encryption',
    HistoryVisibilityNotice(:final visibility) => switch (visibility) {
      HistoryVisibilityKind.invited =>
        '$actor made new history visible to members from when they’re invited',
      HistoryVisibilityKind.joined =>
        '$actor made new history visible to members from when they join',
      HistoryVisibilityKind.shared =>
        '$actor made the history visible to all members',
      HistoryVisibilityKind.worldReadable =>
        '$actor made the history visible to anyone',
      HistoryVisibilityKind.other => '$actor changed who can see the history',
    },
    JoinRuleNotice(:final rule) => switch (rule) {
      JoinRuleKind.public => '$actor made the room public',
      JoinRuleKind.invite => '$actor made the room invite only',
      JoinRuleKind.knock => '$actor let people ask to join',
      JoinRuleKind.restricted =>
        '$actor made the room open to members of a space',
      JoinRuleKind.other => '$actor changed who can join',
    },
    PowerLevelsNotice(:final changes) => switch (changes) {
      [] => '$actor changed the room’s permissions',
      [final change] => () {
        final whom = user(change.userId, null);
        return '$actor made $whom ${_role(change.newLevel)}';
      }(),
      _ => '$actor changed the roles of ${changes.length} people',
    },
    PinnedNotice(added: true, removed: false) => '$actor pinned a message',
    PinnedNotice(added: false, removed: true) => '$actor unpinned a message',
    PinnedNotice() => '$actor changed the pinned messages',
    RoomUpgradedNotice() => '$actor upgraded this room',
    PollNotice(:final question) => '$actor started a poll: $question',
    StickerNotice(:final body) => '$actor sent a sticker: $body',
    LocationNotice(:final body) when body.startsWith('geo:') || body.isEmpty =>
      '$actor shared a location',
    LocationNotice(:final body) => '$actor shared a location: $body',
    LiveLocationNotice() => '$actor started sharing $their live location',
    CallNotice(:final video, :final declinedBy, :final ongoing) => () {
      final kind = switch (video) {
        true => 'a video call',
        false => 'a voice call',
        null => 'a call',
      };
      final declined = declinedBy.isEmpty
          ? ''
          : ' · declined by ${declinedBy.map((id) => user(id, null)).join(', ')}';
      if (!entry.isOwn &&
          !ongoing &&
          missedCalls.contains(entry.eventId) &&
          !declinedBy.contains(ownUserId)) {
        return 'Missed ${kind.substring(2)} from $actor';
      }
      return '$actor started $kind${ongoing ? ' · in progress' : ''}$declined';
    }(),
  };
}

String _role(int level) => level >= 100
    ? 'an admin'
    : level >= 50
    ? 'a moderator'
    : 'a regular member';

/// `alice` for `@alice:example.org`.
String _shortId(String userId) {
  final local = userId.startsWith('@') ? userId.substring(1) : userId;
  final colon = local.indexOf(':');
  return colon > 0 ? local.substring(0, colon) : local;
}

/// What a folded run of membership notices says: "3 people joined, 1 left".
String noticeRunSummary(Iterable<NoticeEntry> run) {
  final groups = <String, Set<String>>{};
  void add(String kind, String user) => (groups[kind] ??= <String>{}).add(user);
  for (final entry in run) {
    switch (entry.notice) {
      case MembershipNotice(:final userId, :final change):
        add(switch (change) {
          MembershipChange.joined ||
          MembershipChange.inviteAccepted ||
          MembershipChange.knockAccepted => 'joined',
          MembershipChange.left ||
          MembershipChange.inviteDeclined ||
          MembershipChange.knockRetracted => 'left',
          MembershipChange.invited => 'invited',
          MembershipChange.kicked ||
          MembershipChange.inviteRevoked ||
          MembershipChange.knockDenied => 'removed',
          MembershipChange.banned ||
          MembershipChange.kickedAndBanned => 'banned',
          MembershipChange.unbanned => 'unbanned',
          MembershipChange.knocked => 'knocked',
        }, userId);
      case ProfileNotice(:final userId):
        add('profile', userId);
      case _:
    }
  }
  final parts = <String>[];
  for (final kind in const [
    'joined',
    'left',
    'invited',
    'removed',
    'banned',
    'unbanned',
    'knocked',
    'profile',
  ]) {
    final n = groups[kind]?.length ?? 0;
    if (n == 0) continue;
    final who = parts.isEmpty ? '$n ${n == 1 ? 'person' : 'people'}' : '$n';
    final was = n == 1 ? 'was' : 'were';
    parts.add(switch (kind) {
      'joined' => '$who joined',
      'left' => '$who left',
      'invited' => '$who $was invited',
      'removed' => '$who $was removed',
      'banned' => '$who $was banned',
      'unbanned' => '$who $was unbanned',
      'knocked' => '$who asked to join',
      _ => '$who changed their profile',
    });
  }
  return parts.join(', ');
}

/// A notice: a small centred line in muted text.
class NoticeLine extends StatelessWidget {
  const NoticeLine({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 3),
    child: Center(
      child: Text(
        text,
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: context.oxi.muted, fontSize: 12.5),
      ),
    ),
  );
}

/// A folded run of membership notices: its summary, opening to show each.
class NoticeRunLine extends StatelessWidget {
  const NoticeRunLine({
    required this.summary,
    required this.expanded,
    required this.onToggle,
    super.key,
  });

  final String summary;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final muted = context.oxi.muted;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Center(
        child: Semantics(
          button: true,
          expanded: expanded,
          child: InkWell(
            customBorder: OxiShapes.small,
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: muted,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 16,
                    color: muted,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
