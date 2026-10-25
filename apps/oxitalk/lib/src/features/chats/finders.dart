import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../matrix/api/matrix.dart';
import '../../ui/avatar.dart';

/// How long typing pauses before the server is asked.
const _searchDelay = Duration(milliseconds: 300);

final _userId = RegExp(r'^@[^:\s]+:\S+$');
final _roomAddress = RegExp(r'^[#!][^:\s]+:\S+$');

/// Whether [text] names a room: `#alias:server`, `!id:server`, or a matrix.to or `matrix:`
/// link.
bool isRoomAddress(String text) =>
    _roomAddress.hasMatch(text) ||
    text.contains('matrix.to/') ||
    text.startsWith('matrix:');

/// A search field over a list that fills the rest of a dialog.
class _FinderDialog extends StatelessWidget {
  const _FinderDialog({
    required this.title,
    required this.field,
    required this.children,
    this.above,
    this.action,
    super.key,
  });

  final String title;
  final TextField field;
  final List<Widget> children;

  /// Shown between the field and the list.
  final Widget? above;

  /// The main button, beside Cancel.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return AlertDialog(
      title: Text(title),
      contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      content: SizedBox(
        width: math.min(460, size.width - 48),
        height: math.min(520, size.height * 0.7),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            field,
            ?above,
            const SizedBox(height: 8),
            Expanded(child: ListView(children: children)),
          ],
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ?action,
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelMedium
          ?.copyWith(color: Theme.of(context).colorScheme.primary),
    ),
  );
}

class _Note extends StatelessWidget {
  const _Note(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodyMedium
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );
}

/// Picks someone to chat with: people the user knows, filtered as they type, then matches
/// from the server's user directory; a typed full user ID can be picked as it is. Gives back
/// the user ID.
Widget newChatDialog({
  required String account,
  required MatrixSession session,
}) => PeopleDialog(
  account: account,
  session: session,
  keyPrefix: 'newChat',
  title: 'New chat',
);

/// Picks people to invite to a room, as [newChatDialog] finds them; several can be ticked.
/// [members] are greyed at the end, not to be picked: user ID → what they are (`In the
/// room`, `Invited`). Gives back the picked user IDs.
Widget inviteDialog({
  required String account,
  required MatrixSession session,
  required Map<String, String> members,
}) => PeopleDialog(
  account: account,
  session: session,
  keyPrefix: 'invite',
  title: 'Invite to this room',
  members: members,
  multiple: true,
);

/// The people finder behind [newChatDialog] and [inviteDialog]. One pick pops the user ID;
/// with [multiple], picks are ticked and the Invite button pops the list of them.
class PeopleDialog extends StatefulWidget {
  const PeopleDialog({
    required this.account,
    required this.session,
    required this.keyPrefix,
    required this.title,
    this.members = const {},
    this.multiple = false,
    super.key,
  });

  final String account;
  final MatrixSession session;

  /// Starts the keys of its widgets, for tests: `<keyPrefix>.search` and so on.
  final String keyPrefix;
  final String title;
  final Map<String, String> members;
  final bool multiple;

  @override
  State<PeopleDialog> createState() => _PeopleDialogState();
}

class _PeopleDialogState extends State<PeopleDialog> {
  final _term = TextEditingController();
  List<Person>? _known;
  List<Person> _found = const [];

  /// The term [_found] answers, and whether a search for the current one is running.
  String _foundFor = '';
  var _searching = false;
  Timer? _delay;

  /// Ticked so far, with [multiple]: user ID → the person, in the order ticked.
  final _picked = <String, Person>{};

  Key _key(String name) => Key('${widget.keyPrefix}.$name');

  @override
  void initState() {
    super.initState();
    unawaited(_loadKnown());
    _term.addListener(_changed);
  }

  Future<void> _loadKnown() async {
    List<Person> known;
    try {
      known = await widget.session.knownPeople();
    } on MatrixFailure {
      known = const [];
    }
    if (mounted) setState(() => _known = known);
  }

  void _changed() {
    _delay?.cancel();
    final term = _term.text.trim();
    setState(() => _searching = term.isNotEmpty);
    if (term.isEmpty) return;
    _delay = Timer(_searchDelay, () => unawaited(_search(term)));
  }

  Future<void> _search(String term) async {
    List<Person> found;
    try {
      found = await widget.session.searchPeople(term);
    } on MatrixFailure {
      found = const [];
    }
    // A later search has started meanwhile.
    if (!mounted || term != _term.text.trim()) return;
    setState(() {
      _found = found;
      _foundFor = term;
      _searching = false;
    });
  }

  @override
  void dispose() {
    _delay?.cancel();
    _term.dispose();
    super.dispose();
  }

  static bool _matches(Person person, String term) =>
      '${person.userId} ${person.displayName ?? ''}'.toLowerCase().contains(
        term.toLowerCase(),
      );

  /// What the list offers now, in order: the typed ID, people known, people found, and
  /// the room's members (not to be picked).
  ({
    String? typed,
    List<Person> known,
    List<Person> found,
    List<Person> members,
  })
  _items() {
    final term = _term.text.trim();
    final members = widget.members;
    final known = [
      for (final person in _known ?? const <Person>[])
        if (!members.containsKey(person.userId) && _matches(person, term))
          person,
    ];
    final knownIds = {for (final person in known) person.userId};
    final found = term.isEmpty || _foundFor != term
        ? const <Person>[]
        : [
            for (final person in _found)
              if (!knownIds.contains(person.userId) &&
                  !members.containsKey(person.userId))
                person,
          ];
    // Members with what is known of them; the rest by ID alone.
    final everyone = {
      for (final person in [...?_known, ..._found]) person.userId: person,
    };
    final inRoom = [
      for (final userId in members.keys)
        if (_matches(everyone[userId] ?? Person(userId), term))
          everyone[userId] ?? Person(userId),
    ];
    final listed = {
      ...knownIds,
      for (final person in found) person.userId,
      ...members.keys,
    };
    final typed = _userId.hasMatch(term) && !listed.contains(term)
        ? term
        : null;
    return (typed: typed, known: known, found: found, members: inRoom);
  }

  void _pick(Person person) {
    if (!widget.multiple) {
      Navigator.of(context).pop(person.userId);
      return;
    }
    setState(() {
      if (_picked.remove(person.userId) == null) {
        _picked[person.userId] = person;
        // Ready for the next name.
        _term.clear();
      }
    });
  }

  void _submit() {
    final items = _items();
    final typed = items.typed;
    final first = typed != null
        ? Person(typed)
        : items.known.firstOrNull ?? items.found.firstOrNull;
    if (first != null) {
      _pick(first);
    } else if (widget.multiple && _picked.isNotEmpty) {
      _done();
    }
  }

  void _done() => Navigator.of(context).pop(_picked.keys.toList());

  Widget _tile(Person person) {
    final name = person.displayName ?? person.userId;
    final picked = _picked.containsKey(person.userId);
    return ListTile(
      key: _key('person.${person.userId}'),
      leading: MatrixAvatar(
        account: widget.account,
        url: person.avatarUrl,
        name: name,
        seed: person.userId,
        radius: 18,
      ),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: person.displayName == null
          ? null
          : Text(person.userId, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: widget.multiple
          ? Icon(
              picked
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: picked ? Theme.of(context).colorScheme.primary : null,
            )
          : null,
      onTap: () => _pick(person),
    );
  }

  Widget _memberTile(Person person) {
    final name = person.displayName ?? person.userId;
    return Opacity(
      opacity: 0.5,
      child: ListTile(
        key: _key('member.${person.userId}'),
        enabled: false,
        leading: MatrixAvatar(
          account: widget.account,
          url: person.avatarUrl,
          name: name,
          seed: person.userId,
          radius: 18,
        ),
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Text(
          widget.members[person.userId] ?? '',
          style: Theme.of(context).textTheme.labelMedium,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final term = _term.text.trim();
    final items = _items();
    final typed = items.typed;
    return _FinderDialog(
      key: Key(widget.keyPrefix),
      title: widget.title,
      field: TextField(
        key: _key('search'),
        controller: _term,
        autofocus: true,
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.search_rounded),
          hintText: 'Name or @name:server.org',
        ),
        onSubmitted: (_) => _submit(),
      ),
      above: _picked.isEmpty
          ? null
          : Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final person in _picked.values)
                    InputChip(
                      key: _key('chip.${person.userId}'),
                      avatar: MatrixAvatar(
                        account: widget.account,
                        url: person.avatarUrl,
                        name: person.displayName ?? person.userId,
                        seed: person.userId,
                        radius: 12,
                      ),
                      label: Text(person.displayName ?? person.userId),
                      onDeleted: () =>
                          setState(() => _picked.remove(person.userId)),
                    ),
                ],
              ),
            ),
      action: widget.multiple
          ? FilledButton(
              key: _key('send'),
              onPressed: _picked.isEmpty ? null : _done,
              child: Text(
                _picked.length < 2 ? 'Invite' : 'Invite ${_picked.length}',
              ),
            )
          : null,
      children: [
        if (typed != null)
          ListTile(
            key: _key('typed'),
            leading: const IconAvatar(
              radius: 18,
              icon: Icons.person_add_alt_rounded,
              iconSize: 20,
            ),
            title: Text(
              widget.multiple ? 'Add $typed' : 'Chat with $typed',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => _pick(Person(typed)),
          ),
        if (_known == null)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (items.known.isNotEmpty) ...[
          const _Header('People you know'),
          ...items.known.map(_tile),
        ],
        if (items.found.isNotEmpty) ...[
          const _Header('On the server'),
          ...items.found.map(_tile),
        ],
        if (_searching && term.isNotEmpty)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Center(
              child: SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else if (_known != null &&
            typed == null &&
            items.known.isEmpty &&
            items.found.isEmpty)
          _Note(
            key: _key('none'),
            term.isEmpty
                ? 'Type a name, or a full user ID like @name:server.org.'
                : 'No one found. Type their full user ID, like @name:server.org.',
          ),
        if (items.members.isNotEmpty) ...[
          const _Header('Already here'),
          ...items.members.map(_memberTile),
        ],
      ],
    );
  }
}

/// What the Join dialog gives back: the room or address to join, or — [joined] — the ID
/// of a room the user is in already, to open.
typedef JoinChoice = ({String target, bool joined});

/// Picks a room to join from the server's public directory, the most joined first and
/// those the user is in greyed at the end; a typed address or link can be joined as it is.
class JoinRoomDialog extends StatefulWidget {
  const JoinRoomDialog({
    required this.account,
    required this.session,
    super.key,
  });

  final String account;
  final MatrixSession session;

  @override
  State<JoinRoomDialog> createState() => _JoinRoomDialogState();
}

class _JoinRoomDialogState extends State<JoinRoomDialog> {
  final _term = TextEditingController();

  /// The directory as the server answered the last search; `null` while loading.
  List<PublicRoom>? _rooms;
  var _failed = false;
  Timer? _delay;

  @override
  void initState() {
    super.initState();
    unawaited(_load(null));
    _term.addListener(_changed);
  }

  void _changed() {
    _delay?.cancel();
    final term = _term.text.trim();
    setState(() {});
    if (isRoomAddress(term)) return;
    _delay = Timer(
      _searchDelay,
      () => unawaited(_load(term.isEmpty ? null : term)),
    );
  }

  Future<void> _load(String? term) async {
    try {
      final rooms = await widget.session.publicRooms(term);
      if (!mounted || (term ?? '') != _term.text.trim()) return;
      setState(() {
        _rooms = rooms;
        _failed = false;
      });
    } on MatrixFailure {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
    _term.dispose();
    super.dispose();
  }

  /// The directory filtered by what is typed now, so the list follows typing at once.
  List<PublicRoom> _visible() {
    final term = _term.text.trim().toLowerCase();
    return [
      for (final room in _rooms ?? const <PublicRoom>[])
        if (term.isEmpty ||
            '${room.name ?? ''} ${room.alias ?? ''} ${room.topic ?? ''}'
                .toLowerCase()
                .contains(term))
          room,
    ];
  }

  void _pick(PublicRoom room) => Navigator.of(context).pop((
    target: room.joined ? room.roomId : room.alias ?? room.roomId,
    joined: room.joined,
  ));

  void _submit() {
    final term = _term.text.trim();
    if (isRoomAddress(term)) {
      Navigator.of(context).pop((target: term, joined: false));
      return;
    }
    final first = _visible().firstOrNull;
    if (first != null) _pick(first);
  }

  Widget _tile(PublicRoom room) {
    final name = room.name ?? room.alias ?? room.roomId;
    final theme = Theme.of(context);
    final topic = room.topic;
    final tile = ListTile(
      key: Key('joinRoom.room.${room.roomId}'),
      leading: MatrixAvatar(
        account: widget.account,
        url: room.avatarUrl,
        name: name,
        seed: room.roomId,
        radius: 18,
      ),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        topic ?? room.alias ?? '',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: room.joined
          ? Text('Joined', style: theme.textTheme.labelMedium)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.person_outline_rounded,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 2),
                Text('${room.members}', style: theme.textTheme.labelMedium),
              ],
            ),
      onTap: () => _pick(room),
    );
    return room.joined ? Opacity(opacity: 0.5, child: tile) : tile;
  }

  @override
  Widget build(BuildContext context) {
    final term = _term.text.trim();
    final typed = isRoomAddress(term) ? term : null;
    final visible = _visible();
    final rooms = _rooms;
    return _FinderDialog(
      key: const Key('joinRoom'),
      title: 'Join a room',
      field: TextField(
        key: const Key('joinRoom.address'),
        controller: _term,
        autofocus: true,
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.search_rounded),
          hintText: 'Search, or #room:server.org or a link',
        ),
        onSubmitted: (_) => _submit(),
      ),
      children: [
        if (typed != null)
          ListTile(
            key: const Key('joinRoom.typed'),
            leading: const IconAvatar(
              radius: 18,
              icon: Icons.login_rounded,
              iconSize: 20,
            ),
            title: Text(
              'Join $typed',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: _submit,
          ),
        if (_failed)
          const _Note(
            key: Key('joinRoom.failed'),
            'Can’t load your server’s room directory. You can still join by address.',
          )
        else if (rooms == null)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (visible.isEmpty && typed == null)
          _Note(
            key: const Key('joinRoom.none'),
            rooms.isEmpty && term.isEmpty
                ? 'Your server lists no public rooms. Join one by its address, '
                      'like #room:server.org, or paste a link.'
                : 'No public room matches. Join one by its address, like '
                      '#room:server.org, or paste a link.',
          )
        else ...[
          if (visible.isNotEmpty) const _Header('Public rooms on your server'),
          ...visible.map(_tile),
        ],
      ],
    );
  }
}
