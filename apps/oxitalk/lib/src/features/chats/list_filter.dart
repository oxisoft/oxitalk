import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../matrix/api/matrix.dart';
import 'room_groups.dart';

/// What the chat list is filtered by, per account; kept in memory only, so a restart starts
/// with the whole list again.
final listFilterProvider = NotifierProvider.family<ListFilter, String, String>(
  ListFilter.new,
);

class ListFilter extends Notifier<String> {
  ListFilter(this.account);

  /// The user ID of the account whose list it filters.
  final String account;

  @override
  String build() => '';

  void set(String text) => state = text;

  void clear() => state = '';
}

/// The people of the account's direct chats, by room: their user IDs and names, so a
/// filter finds a chat by `@user:server` as well. Asked only while the list is filtered.
final dmPeopleProvider = FutureProvider.autoDispose
    .family<Map<String, List<String>>, String>((ref, account) async {
      final session = ref.watch(
        accountsProvider.select((accounts) => accounts.value?.byId(account)),
      );
      if (session == null) return const {};
      final byRoom = <String, List<String>>{};
      for (final person in await session.knownPeople()) {
        final roomId = session.dmWith(person.userId);
        if (roomId == null) continue;
        byRoom.putIfAbsent(roomId, () => []).addAll([
          person.userId,
          ?person.displayName,
        ]);
      }
      return byRoom;
    });

/// [text] in lower case without accents, so `Zoë` and `ZOE` both find `zoe`.
String foldForSearch(String text) {
  final out = StringBuffer();
  for (final rune in text.toLowerCase().runes) {
    // Combining marks, as in an `e` followed by U+0301, add nothing.
    if (rune >= 0x0300 && rune <= 0x036F) continue;
    final char = String.fromCharCode(rune);
    out.write(_plain[char] ?? char);
  }
  return out.toString();
}

/// Lower-case letters with accents and the plain letters they are searched as.
const _accented = {
  'a': 'àáâãäåāăąǎ',
  'ae': 'æ',
  'c': 'çćĉċč',
  'd': 'ďđð',
  'e': 'èéêëēĕėęěə',
  'g': 'ĝğġģ',
  'h': 'ĥħ',
  'i': 'ìíîïĩīĭįıǐ',
  'j': 'ĵ',
  'k': 'ķ',
  'l': 'ĺļľŀł',
  'n': 'ñńņňŉ',
  'o': 'òóôõöøōŏőǒ',
  'oe': 'œ',
  'r': 'ŕŗř',
  's': 'śŝşšș',
  'ss': 'ß',
  't': 'ţťŧț',
  'th': 'þ',
  'u': 'ùúûüũūŭůűųǔ',
  'w': 'ŵ',
  'y': 'ýÿŷ',
  'z': 'źżž',
  'е': 'ё',
  'и': 'й',
};

final _plain = {
  for (final MapEntry(key: plain, value: letters) in _accented.entries)
    for (final letter in letters.split('')) letter: plain,
};

/// Whether [room] is one the filter [query] asks for: every word of it, in any case and
/// with or without accents, is part of the room's name or, for a direct chat, of the other
/// person's name or user name ([people]: their user IDs and names). Whole IDs, with their
/// server, count only for a word that looks like one (`@bob:acme`, `!abc`, `:acme.com`), so
/// a short word doesn't find every chat on the server.
bool roomMatches(Room room, String query, {List<String> people = const []}) {
  final words = foldForSearch(query)
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty);
  if (words.isEmpty) return true;
  final userIds = [
    for (final value in people)
      if (value.startsWith('@') && value.contains(':')) value,
  ];
  final names = foldForSearch(
    [
      room.name,
      for (final value in people)
        if (userIds.contains(value))
          value.substring(1, value.indexOf(':'))
        else
          value,
    ].join('\n'),
  );
  final ids = foldForSearch([room.id, ...userIds].join('\n'));
  return words.every(
    (word) =>
        names.contains(word) ||
        ((word.startsWith('@') || word.startsWith('!') || word.contains(':')) &&
            ids.contains(word)),
  );
}

/// [groups] with only the rooms [matches] keeps, in their order; sections left empty are
/// left out.
List<RoomGroup> filterGroups(
  List<RoomGroup> groups,
  bool Function(Room room) matches,
) => [
  for (final group in groups)
    if (group.rooms.where(matches).toList() case final rooms
        when rooms.isNotEmpty)
      RoomGroup(group.tag, group.title, rooms),
];
