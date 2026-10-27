import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../matrix/api/matrix.dart';
import '../../util/log.dart';
import 'mentions/composer_controller.dart';
import 'message_actions.dart';

/// What a composer held when the user left it, as it was: the text with its pills, and the
/// message it answered or edited. Kept for this run, so coming back is instant.
final class LiveDraft {
  const LiveDraft({required this.text, required this.pills, this.mode});

  /// The text, a [pillChar] for each pill.
  final String text;
  final List<MessagePart> pills;
  final ComposerMode? mode;

  bool get isEmpty => text.trim().isEmpty && mode == null;

  /// The parts as typed: the text between the pills, nothing trimmed.
  List<MessagePart> get parts {
    final parts = <MessagePart>[];
    final buffer = StringBuffer();
    var pill = 0;
    for (final char in text.split('')) {
      if (char == pillChar && pill < pills.length) {
        if (buffer.isNotEmpty) parts.add(TextPart(buffer.toString()));
        buffer.clear();
        parts.add(pills[pill++]);
      } else {
        buffer.write(char);
      }
    }
    if (buffer.isNotEmpty) parts.add(TextPart(buffer.toString()));
    return parts;
  }

  /// The form the account's store keeps. A reply or edit of a message not yet sent (no event
  /// ID) is kept as a new message.
  ComposerDraft get stored {
    final mode = this.mode;
    final eventId = mode == null ? null : eventFields(mode.entry)?.meta.eventId;
    return ComposerDraft(
      parts,
      type: switch (mode) {
        _ when eventId == null => DraftType.newMessage,
        Replying() => DraftType.reply,
        Editing() => DraftType.edit,
        null => DraftType.newMessage,
      },
      eventId: eventId,
    );
  }
}

/// The text and pills of [parts] as the composer holds them: a [pillChar] for each pill.
(String, List<MessagePart>) composerContent(List<MessagePart> parts) {
  final text = StringBuffer();
  final pills = <MessagePart>[];
  for (final part in parts) {
    if (part is TextPart) {
      // A stray pill character would stand for a pill that isn't there.
      text.write(part.text.replaceAll(pillChar, ''));
    } else {
      text.write(pillChar);
      pills.add(part);
    }
  }
  return (text.toString(), pills);
}

/// The drafts of one account: the chat list's "Draft:" lines (room → first line) as its
/// state, and the composers' drafts kept for this run. The account's encrypted store holds
/// them across restarts; nothing is sent to the server.
final draftsProvider =
    NotifierProvider.family<Drafts, Map<String, String>, String>(Drafts.new);

/// Room and thread (`null` for the room's own composer).
typedef DraftKey = (String, String?);

final class Drafts extends Notifier<Map<String, String>> {
  Drafts(this.account);

  final String account;
  final _live = <DraftKey, LiveDraft>{};

  /// The store's work for each draft, in order, so a late save can't bring back a draft
  /// that was cleared.
  final _queue = <DraftKey, Future<void>>{};

  @override
  Map<String, String> build() {
    ref.listen(
      accountsProvider.select((accounts) => accounts.value?.byId(account)),
      (_, session) {
        if (session != null) unawaited(_loadPreviews(session));
      },
      fireImmediately: true,
    );
    return const {};
  }

  MatrixSession? get _session =>
      ref.read(accountsProvider).value?.byId(account);

  Future<void> _loadPreviews(MatrixSession session) async {
    try {
      final previews = await session.draftPreviews();
      // What this run changed since wins over what was stored.
      state = {...previews, ...state};
    } on MatrixFailure catch (failure) {
      appLog(LogLevel.warn, 'drafts', 'previews: ${failure.kind.name}');
    }
  }

  /// The draft kept this run for the room (or thread), if any.
  LiveDraft? live(String roomId, String? thread) => _live[(roomId, thread)];

  /// The draft in the account's store, after any pending saves.
  Future<ComposerDraft?> stored(String roomId, String? thread) async {
    final key = (roomId, thread);
    await _queue[key];
    try {
      return await _session?.loadDraft(roomId, thread: thread);
    } on MatrixFailure catch (failure) {
      appLog(LogLevel.warn, 'drafts', 'load: ${failure.kind.name}');
      return null;
    }
  }

  /// Keeps [draft] for the room (or thread) and stores it; an empty one is forgotten. With
  /// [leaving] the chat list's line follows at once.
  void keep(
    String roomId,
    String? thread,
    LiveDraft draft, {
    required bool leaving,
  }) {
    // The whole app is closing: nothing to keep it in.
    if (!ref.mounted) return;
    final key = (roomId, thread);
    if (draft.isEmpty) {
      _live.remove(key);
    } else {
      _live[key] = draft;
    }
    final stored = draft.stored;
    _enqueue(key, (session) async {
      stored.hasText
          ? await session.saveDraft(roomId, stored, thread: thread)
          : await session.clearDraft(roomId, thread: thread);
    });
    // After the frame: a composer leaves while the widget tree is being torn down.
    if (leaving && thread == null) {
      scheduleMicrotask(() => _preview(roomId, stored));
    }
  }

  /// Forgets the room's (or thread's) draft: the message was sent.
  void clear(String roomId, String? thread) {
    if (!ref.mounted) return;
    final key = (roomId, thread);
    _live.remove(key);
    _enqueue(key, (session) => session.clearDraft(roomId, thread: thread));
    if (thread == null) _preview(roomId, null);
  }

  void _preview(String roomId, ComposerDraft? draft) {
    if (!ref.mounted) return;
    final line = draft != null && draft.hasText ? draft.firstLine : null;
    if (state[roomId] == line) return;
    state = {
      for (final MapEntry(:key, :value) in state.entries)
        if (key != roomId) key: value,
      roomId: ?line,
    };
  }

  void _enqueue(DraftKey key, Future<void> Function(MatrixSession) work) {
    final session = _session;
    if (session == null) return;
    final previous = _queue[key] ?? Future<void>.value();
    late final Future<void> next;
    next = previous
        .then((_) => work(session))
        .catchError((Object error) {
          appLog(LogLevel.warn, 'drafts', 'store: $error');
        })
        .whenComplete(() {
          if (identical(_queue[key], next)) _queue.remove(key);
        });
    _queue[key] = next;
  }
}
