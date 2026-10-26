import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../matrix/api/models.dart';
import '../../../ui/avatar.dart';

/// What the user is typing to mention: `@` or `#` at the start or after a space, then the
/// letters typed so far up to the cursor.
typedef MentionQuery = ({String trigger, String text, int start, int end});

/// The `@…` or `#…` being typed before the cursor in [value], if any.
MentionQuery? mentionQueryAt(TextEditingValue value) {
  final selection = value.selection;
  if (!selection.isValid || !selection.isCollapsed) return null;
  final text = value.text;
  final end = selection.baseOffset;
  if (end > text.length) return null;
  var start = end;
  while (start > 0) {
    final char = text[start - 1];
    if (char == '@' || char == '#') {
      final before = start - 1 == 0 ? ' ' : text[start - 2];
      if (before.trim().isEmpty || before == '\uFFFC') {
        return (
          trigger: char,
          text: text.substring(start, end),
          start: start - 1,
          end: end,
        );
      }
      return null;
    }
    if (char.trim().isEmpty || char == '\uFFFC') return null;
    start--;
  }
  return null;
}

/// One thing the popup offers.
final class MentionSuggestion {
  const MentionSuggestion({
    required this.part,
    required this.title,
    required this.subtitle,
    required this.seed,
    this.avatarUrl,
  });

  /// What picking it inserts.
  final MessagePart part;
  final String title;
  final String subtitle;

  /// For the avatar's colour.
  final String seed;
  final String? avatarUrl;
}

/// How many suggestions show at most.
const maxSuggestions = 6;

/// How well [query] matches [name] and [id]: lower is better, `null` for no match. The name
/// starting with it first, then a word of the name, then the ID's local part, then anywhere.
int? matchRank(String query, String name, String id) {
  final q = query.toLowerCase();
  if (q.isEmpty) return 4;
  final n = name.toLowerCase();
  final local = id.toLowerCase().replaceFirst(RegExp('^[@#!]'), '');
  if (n.startsWith(q)) return 0;
  if (n.split(RegExp(r'\s+')).any((word) => word.startsWith(q))) return 1;
  if (local.startsWith(q)) return 2;
  if (n.contains(q)) return 3;
  if (local.contains(q)) return 5;
  return null;
}

/// The members matching [query], best first, then `@room` when [canMentionRoom] and it
/// matches; [own] is left out, as are banned members.
List<MentionSuggestion> memberSuggestions(
  String query,
  List<RoomMember> members, {
  required String own,
  required bool canMentionRoom,
}) {
  final ranked = <(int, String, MentionSuggestion)>[];
  for (final member in members) {
    if (member.userId == own || member.banned) continue;
    final name = member.displayName ?? member.userId;
    final rank = matchRank(query, name, member.userId);
    if (rank == null) continue;
    ranked.add((
      rank,
      name.toLowerCase(),
      MentionSuggestion(
        part: UserPill(member.userId, name),
        title: name,
        subtitle: member.userId,
        seed: member.userId,
        avatarUrl: member.avatarUrl,
      ),
    ));
  }
  ranked.sort((a, b) {
    final byRank = a.$1.compareTo(b.$1);
    return byRank != 0 ? byRank : a.$2.compareTo(b.$2);
  });
  final room =
      canMentionRoom &&
          'room'.startsWith(query.toLowerCase()) &&
          query.isNotEmpty
      ? const MentionSuggestion(
          part: AtRoomPill(),
          title: '@room',
          subtitle: 'Notify everyone in this room',
          seed: '@room',
        )
      : null;
  return [
    // `@r…` puts @room first; an empty query keeps it out of the way.
    ?room,
    for (final (_, _, suggestion) in ranked) suggestion,
  ].take(maxSuggestions).toList();
}

/// The rooms matching [query] by name or address, best first.
List<MentionSuggestion> roomSuggestions(String query, List<MentionRoom> rooms) {
  final ranked = <(int, String, MentionSuggestion)>[];
  for (final room in rooms) {
    final rank = matchRank(query, room.name, room.alias ?? room.roomId);
    if (rank == null) continue;
    ranked.add((
      rank,
      room.name.toLowerCase(),
      MentionSuggestion(
        part: RoomPill(roomId: room.roomId, name: room.name, alias: room.alias),
        title: room.name,
        subtitle: room.alias ?? '',
        seed: room.roomId,
        avatarUrl: room.avatarUrl,
      ),
    ));
  }
  ranked.sort((a, b) {
    final byRank = a.$1.compareTo(b.$1);
    return byRank != 0 ? byRank : a.$2.compareTo(b.$2);
  });
  return [for (final (_, _, suggestion) in ranked) suggestion]
      .take(maxSuggestions)
      .toList();
}

/// The list of suggestions above the composer: avatar, name, ID; [selected] is lit, a tap
/// picks.
class MentionSuggestionList extends StatelessWidget {
  const MentionSuggestionList({
    required this.account,
    required this.suggestions,
    required this.selected,
    required this.onPick,
    super.key,
  });

  final String account;
  final List<MentionSuggestion> suggestions;
  final int selected;
  final void Function(MentionSuggestion) onPick;

  @override
  Widget build(BuildContext context) {
    final palette = context.oxi;
    return Material(
      key: const Key('mentions.popup'),
      color: palette.panel,
      elevation: 6,
      shape: OxiShapes.cut(8).copyWith(side: BorderSide(color: palette.line)),
      clipBehavior: Clip.antiAlias,
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 4),
        children: [
          for (final (index, suggestion) in suggestions.indexed)
            ListTile(
              key: Key('mentions.item.${suggestion.seed}'),
              dense: true,
              selected: index == selected,
              selectedTileColor: palette.selectedRow,
              selectedColor: Theme.of(context).colorScheme.onSurface,
              leading: suggestion.part is AtRoomPill
                  ? const IconAvatar(icon: Icons.campaign_outlined, radius: 16)
                  : MatrixAvatar(
                      account: account,
                      url: suggestion.avatarUrl,
                      name: suggestion.title,
                      seed: suggestion.seed,
                      radius: 16,
                    ),
              title: Text(
                suggestion.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: suggestion.subtitle.isEmpty
                  ? null
                  : Text(
                      suggestion.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
              onTap: () => onPick(suggestion),
            ),
        ],
      ),
    );
  }
}
