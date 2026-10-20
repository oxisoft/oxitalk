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
    super.key,
  });

  final String title;
  final TextField field;
  final List<Widget> children;

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
            const SizedBox(height: 8),
            Expanded(child: ListView(children: children)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
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
class NewChatDialog extends StatefulWidget {
  const NewChatDialog({
    required this.account,
    required this.session,
    super.key,
  });

  final String account;
  final MatrixSession session;

  @override
  State<NewChatDialog> createState() => _NewChatDialogState();
}

class _NewChatDialogState extends State<NewChatDialog> {
  final _term = TextEditingController();
  List<Person>? _known;
  List<Person> _found = const [];

  /// The term [_found] answers, and whether a search for the current one is running.
  String _foundFor = '';
  var _searching = false;
  Timer? _delay;

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

  /// What the list offers now, in order: the typed ID, people known, people found.
  ({String? typed, List<Person> known, List<Person> found}) _items() {
    final term = _term.text.trim();
    final known = [
      for (final person in _known ?? const <Person>[])
        if (_matches(person, term)) person,
    ];
    final knownIds = {for (final person in known) person.userId};
    final found = term.isEmpty || _foundFor != term
        ? const <Person>[]
        : [
            for (final person in _found)
              if (!knownIds.contains(person.userId)) person,
          ];
    final listed = {...knownIds, for (final person in found) person.userId};
    final typed = _userId.hasMatch(term) && !listed.contains(term)
        ? term
        : null;
    return (typed: typed, known: known, found: found);
  }

  void _pick(String userId) => Navigator.of(context).pop(userId);

  void _submit() {
    final items = _items();
    final first =
        items.typed ??
        items.known.firstOrNull?.userId ??
        items.found.firstOrNull?.userId;
    if (first != null) _pick(first);
  }

  Widget _tile(Person person) {
    final name = person.displayName ?? person.userId;
    return ListTile(
      key: Key('newChat.person.${person.userId}'),
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
      onTap: () => _pick(person.userId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final term = _term.text.trim();
    final items = _items();
    final typed = items.typed;
    return _FinderDialog(
      key: const Key('newChat'),
      title: 'New chat',
      field: TextField(
        key: const Key('newChat.search'),
        controller: _term,
        autofocus: true,
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.search_rounded),
          hintText: 'Name or @name:server.org',
        ),
        onSubmitted: (_) => _submit(),
      ),
      children: [
        if (typed != null)
          ListTile(
            key: const Key('newChat.typed'),
            leading: const CircleAvatar(
              radius: 18,
              child: Icon(Icons.person_add_alt_rounded, size: 20),
            ),
            title: Text('Chat with $typed'),
            onTap: () => _pick(typed),
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
            key: const Key('newChat.none'),
            term.isEmpty
                ? 'Type a name, or a full user ID like @name:server.org.'
                : 'No one found. Type their full user ID, like @name:server.org.',
          ),
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
            leading: const CircleAvatar(
              radius: 18,
              child: Icon(Icons.login_rounded, size: 20),
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
