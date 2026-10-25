import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../matrix/api/matrix.dart';
import '../../ui/avatar.dart';
import '../../ui/format.dart';
import 'jump.dart';
import 'pins.dart';

/// What a chat's search has found, and which hit is shown.
@immutable
final class ChatSearch {
  const ChatSearch({
    this.open = false,
    this.query = '',
    this.results,
    this.index = 0,
    this.searching = false,
    this.loadingOlder = false,
    this.reachedStart = false,
    this.showList = false,
    this.serial = 0,
    this.error,
  });

  final bool open;
  final String query;

  /// `null` until the first search of [query] is back.
  final SearchResults? results;

  /// Which hit is shown, counted from the newest.
  final int index;
  final bool searching;

  /// Whether more of the chat's history is being loaded from the server.
  final bool loadingOlder;

  /// Whether the device has the chat's history from its first message.
  final bool reachedStart;
  final bool showList;

  /// Counts the moves between hits, so moving to the same hit again shows it again.
  final int serial;
  final MatrixFailure? error;

  SearchHit? get current => results?.hits.elementAtOrNull(index);

  ChatSearch copyWith({
    bool? open,
    String? query,
    SearchResults? results,
    bool clearResults = false,
    int? index,
    bool? searching,
    bool? loadingOlder,
    bool? reachedStart,
    bool? showList,
    int? serial,
    MatrixFailure? error,
    bool clearError = false,
  }) => ChatSearch(
    open: open ?? this.open,
    query: query ?? this.query,
    results: clearResults ? null : results ?? this.results,
    index: index ?? this.index,
    searching: searching ?? this.searching,
    loadingOlder: loadingOlder ?? this.loadingOlder,
    reachedStart: reachedStart ?? this.reachedStart,
    showList: showList ?? this.showList,
    serial: serial ?? this.serial,
    error: clearError ? null : error ?? this.error,
  );
}

/// The search of each open chat.
final chatSearchProvider = NotifierProvider.family
    .autoDispose<ChatSearchNotifier, ChatSearch, ChatKey>(
      ChatSearchNotifier.new,
    );

/// Searches a chat on this device (the core reads the decrypted messages it stored, so
/// encrypted chats are searched too) and loads more of its history when asked, or when
/// nothing is found.
final class ChatSearchNotifier extends Notifier<ChatSearch> {
  ChatSearchNotifier(this.chat);

  final ChatKey chat;
  Timer? _debounce;

  /// How many events one "search older messages" loads.
  static const historyStep = 500;

  @override
  ChatSearch build() {
    ref.onDispose(() => _debounce?.cancel());
    return const ChatSearch();
  }

  MatrixSession? get _session =>
      ref.read(accountsProvider).value?.byId(chat.$1);

  void open() {
    if (!state.open) state = state.copyWith(open: true);
  }

  /// Closes the search and takes away the hit's highlight.
  void close() {
    _debounce?.cancel();
    state = ChatSearch(serial: state.serial + 1);
    ref.read(chatJumpProvider(chat).notifier).clearHighlight();
  }

  void toggleList() => state = state.copyWith(showList: !state.showList);

  /// Searches for [query] once the user stops typing for a moment.
  void setQuery(String query) {
    _debounce?.cancel();
    state = state.copyWith(query: query, clearError: true);
    if (query.trim().isEmpty) {
      state = state.copyWith(clearResults: true, index: 0, searching: false);
      ref.read(chatJumpProvider(chat).notifier).clearHighlight();
      return;
    }
    _debounce = Timer(
      const Duration(milliseconds: 300),
      () => unawaited(search()),
    );
  }

  /// Searches for the current query now. The newest hit is shown, or with [keep] the one
  /// shown before, if it is still found. Finding nothing loads older history once.
  Future<void> search({String? keep, bool autoLoad = true}) async {
    final session = _session;
    final query = state.query;
    if (session == null || query.trim().isEmpty) return;
    state = state.copyWith(searching: true, clearError: true);
    try {
      final results = await session.searchRoom(chat.$2, query);
      if (!ref.mounted || state.query != query || !state.open) return;
      final kept = keep == null
          ? -1
          : results.hits.indexWhere((hit) => hit.eventId == keep);
      final index = kept < 0 ? 0 : kept;
      // Moved only if another hit is shown now.
      final moved =
          results.hits.elementAtOrNull(index)?.eventId !=
          state.current?.eventId;
      state = state.copyWith(
        results: results,
        index: index,
        searching: false,
        serial: moved ? state.serial + 1 : state.serial,
      );
      if (results.hits.isEmpty && autoLoad && !state.reachedStart) {
        await loadOlder();
      }
    } on MatrixFailure catch (failure) {
      if (!ref.mounted) return;
      state = state.copyWith(searching: false, error: failure);
    }
  }

  /// Loads more of the chat's history from the server, then searches again, keeping the
  /// hit shown.
  Future<void> loadOlder() async {
    final session = _session;
    if (session == null || state.loadingOlder || state.reachedStart) return;
    final shown = state.current?.eventId;
    state = state.copyWith(loadingOlder: true, clearError: true);
    try {
      final start = await session.searchLoadOlder(chat.$2, events: historyStep);
      if (!ref.mounted) return;
      state = state.copyWith(loadingOlder: false, reachedStart: start);
      await search(keep: shown, autoLoad: false);
    } on MatrixFailure catch (failure) {
      if (!ref.mounted) return;
      state = state.copyWith(loadingOlder: false, error: failure);
    }
  }

  /// The next older hit (Enter); past the oldest found, older history is loaded first.
  Future<void> older() async {
    final hits = state.results?.hits ?? const [];
    if (state.index + 1 < hits.length) {
      state = state.copyWith(index: state.index + 1, serial: state.serial + 1);
      return;
    }
    if (state.reachedStart || hits.isEmpty) return;
    final count = hits.length;
    await loadOlder();
    if (!ref.mounted) return;
    final now = state.results?.hits ?? const [];
    if (now.length > count && state.index + 1 < now.length) {
      state = state.copyWith(index: state.index + 1, serial: state.serial + 1);
    }
  }

  /// The next newer hit (Shift+Enter).
  void newer() {
    if (state.index > 0) {
      state = state.copyWith(index: state.index - 1, serial: state.serial + 1);
    }
  }

  void select(int index) =>
      state = state.copyWith(index: index, serial: state.serial + 1);
}

/// Under the chat's header while searching: the text, how many hits and which one, older
/// and newer (Enter and Shift+Enter), the list of hits, and closing (Esc). The shown hit is
/// scrolled to in the chat and highlighted.
class ChatSearchBar extends ConsumerStatefulWidget {
  const ChatSearchBar({required this.account, required this.roomId, super.key});

  final String account;
  final String roomId;

  @override
  ConsumerState<ChatSearchBar> createState() => _ChatSearchBarState();
}

class _ChatSearchBarState extends ConsumerState<ChatSearchBar> {
  final _text = TextEditingController();
  final _focus = FocusNode();

  ChatKey get _chat => (widget.account, widget.roomId);

  ChatSearchNotifier get _search =>
      ref.read(chatSearchProvider(_chat).notifier);

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    _text.text = ref.read(chatSearchProvider(_chat)).query;
    // Typing goes to the search at once, also when the header button kept the focus.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
    // Each move to a hit shows it in the chat (or its thread).
    ref.listenManual(chatSearchProvider(_chat), (previous, next) {
      final hit = next.current;
      if (hit == null || !next.open || next.serial == previous?.serial) return;
      showInChat(
        context,
        ref,
        account: widget.account,
        roomId: widget.roomId,
        eventId: hit.eventId,
        threadRoot: hit.threadRoot,
        keepHighlight: true,
      );
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Runs [action] from a button, then gives the focus back to the text, so Enter and
  /// Shift+Enter go on stepping through the hits.
  void _keepTyping(VoidCallback action) {
    action();
    _focus.requestFocus();
  }

  /// Esc closes the search wherever the focus is in the chat, unless something there (like
  /// a reply being written) took it first.
  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape ||
        !(ModalRoute.of(context)?.isCurrent ?? true)) {
      return false;
    }
    _search.close();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final search = ref.watch(chatSearchProvider(_chat));
    final theme = Theme.of(context);
    final results = search.results;
    final hits = results?.hits ?? const <SearchHit>[];
    final small = theme.textTheme.bodySmall;
    return Material(
      key: const Key('search.bar'),
      color: theme.colorScheme.surfaceContainerLow,
      elevation: 1,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 0),
            child: Row(
              children: [
                const Icon(Icons.search_rounded, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: CallbackShortcuts(
                    bindings: {
                      const SingleActivator(LogicalKeyboardKey.enter): () =>
                          unawaited(_search.older()),
                      const SingleActivator(
                        LogicalKeyboardKey.enter,
                        shift: true,
                      ): _search.newer,
                      const SingleActivator(LogicalKeyboardKey.escape):
                          _search.close,
                    },
                    child: TextField(
                      key: const Key('search.field'),
                      controller: _text,
                      focusNode: _focus,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      decoration: const InputDecoration(
                        hintText: 'Search this chat',
                        border: InputBorder.none,
                        isDense: true,
                      ),
                      onChanged: _search.setQuery,
                      onSubmitted: (_) {
                        unawaited(_search.older());
                        _focus.requestFocus();
                      },
                    ),
                  ),
                ),
                if (search.searching || search.loadingOlder)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                Text(
                  _countLabel(search),
                  key: const Key('search.count'),
                  style: small,
                ),
                IconButton(
                  key: const Key('search.older'),
                  tooltip: 'Older match (Enter)',
                  icon: const Icon(Icons.keyboard_arrow_up_rounded),
                  onPressed:
                      hits.isEmpty ||
                          (search.index + 1 >= hits.length &&
                              search.reachedStart)
                      ? null
                      : () => _keepTyping(() => unawaited(_search.older())),
                ),
                IconButton(
                  key: const Key('search.newer'),
                  tooltip: 'Newer match (Shift+Enter)',
                  icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  onPressed: search.index > 0
                      ? () => _keepTyping(_search.newer)
                      : null,
                ),
                IconButton(
                  key: const Key('search.list'),
                  tooltip: search.showList ? 'Hide the list' : 'Show all',
                  isSelected: search.showList,
                  icon: const Icon(Icons.format_list_bulleted_rounded),
                  onPressed: () => _keepTyping(_search.toggleList),
                ),
                IconButton(
                  key: const Key('search.close'),
                  tooltip: 'Close search (Esc)',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: _search.close,
                ),
              ],
            ),
          ),
          if (search.query.trim().isNotEmpty && results != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(40, 0, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _scopeLabel(search),
                      key: const Key('search.scope'),
                      style: small,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (!search.reachedStart)
                    OutlinedButton(
                      key: const Key('search.loadOlder'),
                      onPressed: search.loadingOlder
                          ? null
                          : () => unawaited(_search.loadOlder()),
                      child: const Text('Search older messages'),
                    ),
                ],
              ),
            ),
          if (search.showList && hits.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: ListView.builder(
                key: const Key('search.results'),
                shrinkWrap: true,
                itemCount: hits.length,
                itemBuilder: (context, i) => _HitTile(
                  account: widget.account,
                  hit: hits[i],
                  query: search.query,
                  selected: i == search.index,
                  onTap: () => _search.select(i),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _countLabel(ChatSearch search) {
    final results = search.results;
    if (search.query.trim().isEmpty || results == null) return '';
    if (results.hits.isEmpty) return search.loadingOlder ? '' : 'No results';
    final more = results.total > results.hits.length ? '+' : '';
    return '${search.index + 1} of ${results.hits.length}$more';
  }

  static String _scopeLabel(ChatSearch search) {
    final results = search.results;
    if (search.error case final error?) {
      return 'Can’t search further: ${error.kind.name}';
    }
    if (results == null) return '';
    if (search.reachedStart) return 'Searched the whole chat on this device';
    final oldest = results.oldest;
    final count = results.searched == 1
        ? '1 message'
        : '${results.searched} messages';
    if (oldest == null) return 'Searched $count on this device';
    final day = dayLabel(oldest);
    final since = switch (day) {
      'Today' || 'Yesterday' => day.toLowerCase(),
      _ => day,
    };
    return 'Searched $count on this device, back to $since';
  }
}

/// Ctrl+F (Cmd+F) opens the chat's search; nothing to see.
class SearchShortcut extends ConsumerStatefulWidget {
  const SearchShortcut({
    required this.account,
    required this.roomId,
    super.key,
  });

  final String account;
  final String roomId;

  @override
  ConsumerState<SearchShortcut> createState() => _SearchShortcutState();
}

class _SearchShortcutState extends ConsumerState<SearchShortcut> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.keyF ||
        !(keyboard.isControlPressed || keyboard.isMetaPressed) ||
        !(ModalRoute.of(context)?.isCurrent ?? true)) {
      return false;
    }
    ref
        .read(chatSearchProvider((widget.account, widget.roomId)).notifier)
        .open();
    return true;
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// One hit in the list: who, when, and the text with the match marked.
class _HitTile extends StatelessWidget {
  const _HitTile({
    required this.account,
    required this.hit,
    required this.query,
    required this.selected,
    required this.onTap,
  });

  final String account;
  final SearchHit hit;
  final String query;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = hit.senderName ?? hit.sender;
    final text = [
      if (hit.filename case final name?) '📎 $name',
      if (hit.text.isNotEmpty) hit.text,
    ].join('  ');
    return ListTile(
      key: Key('search.hit.${hit.eventId}'),
      dense: true,
      selected: selected,
      selectedTileColor: context.oxi.selectedRow,
      leading: MatrixAvatar(
        account: account,
        url: hit.senderAvatarUrl,
        name: name,
        seed: hit.sender,
        radius: 14,
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          if (hit.threadRoot != null) ...[
            const Icon(Icons.forum_outlined, size: 14),
            const SizedBox(width: 4),
          ],
          Text(listTime(hit.time), style: theme.textTheme.bodySmall),
        ],
      ),
      subtitle: Text.rich(
        TextSpan(
          children: highlightMatches(
            text,
            query,
            TextStyle(
              backgroundColor: OxiBrand.yellow.withValues(
                alpha: context.isDark ? 0.3 : 0.6,
              ),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: onTap,
    );
  }
}

/// [text] as spans with every case-insensitive match of [query] in [style]; a long text
/// starts shortly before the first match.
List<TextSpan> highlightMatches(String text, String query, TextStyle style) {
  final needle = query.trim().toLowerCase();
  final lower = text.toLowerCase();
  // Lower-casing can change the length (rarely); then nothing is marked.
  if (needle.isEmpty || lower.length != text.length) {
    return [TextSpan(text: text)];
  }
  var start = 0;
  final first = lower.indexOf(needle);
  var prefix = '';
  if (first > 40) {
    start = first - 30;
    prefix = '…';
  }
  final spans = <TextSpan>[if (prefix.isNotEmpty) TextSpan(text: prefix)];
  var at = start;
  while (true) {
    final found = lower.indexOf(needle, at);
    if (found < 0) break;
    if (found > at) spans.add(TextSpan(text: text.substring(at, found)));
    spans.add(
      TextSpan(
        text: text.substring(found, found + needle.length),
        style: style,
      ),
    );
    at = found + needle.length;
  }
  if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
  return spans;
}
