import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
import '../../matrix/api/matrix.dart';
import '../../ui/avatar.dart';
import 'emoji.dart';
import 'media_views.dart';
import 'pins.dart';

/// The parts every message has, whatever its content.
typedef EventFields = ({
  String sender,
  String? senderName,
  String? senderAvatarUrl,
  DateTime time,
  bool isOwn,
  SendState sendState,
  EventMeta meta,
});

/// [entry]'s [EventFields], if it is a message (of any kind).
EventFields? eventFields(TimelineEntry entry) => switch (entry) {
  MessageEntry() => (
    sender: entry.sender,
    senderName: entry.senderName,
    senderAvatarUrl: entry.senderAvatarUrl,
    time: entry.time,
    isOwn: entry.isOwn,
    sendState: entry.sendState,
    meta: entry.meta,
  ),
  MediaEntry() => (
    sender: entry.sender,
    senderName: entry.senderName,
    senderAvatarUrl: entry.senderAvatarUrl,
    time: entry.time,
    isOwn: entry.isOwn,
    sendState: entry.sendState,
    meta: entry.meta,
  ),
  UndecryptableEntry() => (
    sender: entry.sender,
    senderName: entry.senderName,
    senderAvatarUrl: entry.senderAvatarUrl,
    time: entry.time,
    isOwn: entry.isOwn,
    sendState: SendState.sent,
    meta: entry.meta,
  ),
  RedactedEntry() => (
    sender: entry.sender,
    senderName: entry.senderName,
    senderAvatarUrl: entry.senderAvatarUrl,
    time: entry.time,
    isOwn: entry.isOwn,
    sendState: SendState.sent,
    meta: entry.meta,
  ),
  DayDivider() => null,
};

/// What the composer is doing besides writing a new message.
sealed class ComposerMode {
  const ComposerMode(this.entry);

  final TimelineEntry entry;
}

final class Replying extends ComposerMode {
  const Replying(super.entry);
}

final class Editing extends ComposerMode {
  const Editing(super.entry);
}

/// Whether the composer of a chat (or of a thread in it) answers or edits a message; `null`
/// for a new one.
final composerModeProvider = NotifierProvider.family
    .autoDispose<ComposerModeNotifier, ComposerMode?, ComposerKey>(
      ComposerModeNotifier.new,
    );

/// Account, room, and the thread's first event ID (`null` for the chat itself).
typedef ComposerKey = (String, String, String?);

final class ComposerModeNotifier extends Notifier<ComposerMode?> {
  ComposerModeNotifier(this.chat);

  final ComposerKey chat;

  @override
  ComposerMode? build() => null;

  void set(ComposerMode? mode) => state = mode;
}

/// The text a message shows: its body, or its file's caption or name.
String messageText(TimelineEntry entry) => switch (entry) {
  MessageEntry(:final body) => body,
  MediaEntry(:final media) => media.caption ?? media.filename,
  _ => '',
};

/// What the user does with one message of a chat, or of a thread in it; failures show as a
/// snack bar.
final class MessageActions {
  MessageActions(
    this._context,
    this._ref,
    this.account,
    this.roomId, {
    this.thread,
  });

  final BuildContext _context;
  final WidgetRef _ref;
  final String account;
  final String roomId;

  /// The thread's first event ID, when the message is in a thread's view.
  final String? thread;

  RoomTimeline? get _timeline =>
      _ref.read(roomTimelineProvider(account, roomId, thread: thread)).value;

  Future<void> _run(
    String what,
    Future<void> Function(RoomTimeline) call,
  ) async {
    final messenger = ScaffoldMessenger.of(_context);
    final timeline = _timeline;
    if (timeline == null) return;
    try {
      await call(timeline);
    } on MatrixFailure catch (failure) {
      messenger.showSnackBar(
        SnackBar(content: Text('$what: ${failure.kind.name}')),
      );
    }
  }

  /// Gives (or takes back) the reaction [key] on [entry].
  Future<void> toggleReaction(TimelineEntry entry, String key) async {
    final ref = eventFields(entry)?.meta.ref;
    if (ref == null) return;
    rememberEmoji(_ref, account, key);
    await _run('Can’t react', (t) => t.toggleReaction(ref, key));
  }

  /// Asks for an emoji and reacts with it.
  Future<void> react(TimelineEntry entry) async {
    final emoji = await pickReaction(_context, account);
    if (emoji != null) await toggleReaction(entry, emoji);
  }

  void reply(TimelineEntry entry) => _ref
      .read(composerModeProvider((account, roomId, thread)).notifier)
      .set(Replying(entry));

  void edit(TimelineEntry entry) => _ref
      .read(composerModeProvider((account, roomId, thread)).notifier)
      .set(Editing(entry));

  /// Opens the thread that starts at [entry], beside the chat (or as a page of its own).
  void openThread(TimelineEntry entry) {
    final eventId = eventFields(entry)?.meta.eventId;
    if (eventId != null) _context.go(Routes.thread(roomId, eventId));
  }

  void copy(TimelineEntry entry) =>
      unawaited(Clipboard.setData(ClipboardData(text: messageText(entry))));

  Future<void> delete(TimelineEntry entry) async {
    final ref = eventFields(entry)?.meta.ref;
    if (ref == null) return;
    final sure = await showDialog<bool>(
      context: _context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this message?'),
        content: const Text('It is removed for everyone in the chat.'),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('message.deleteConfirm'),
            style: OxiButtons.destructiveFilled(context),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (sure ?? false) await _run('Can’t delete', (t) => t.redact(ref));
  }

  Future<void> retry(TimelineEntry entry) async {
    final ref = eventFields(entry)?.meta.ref;
    if (ref != null) await _run('Can’t send', (t) => t.retrySend(ref));
  }

  /// Asks for a chat of this account and sends the message there too.
  Future<void> forward(TimelineEntry entry) async {
    final eventId = eventFields(entry)?.meta.eventId;
    if (eventId == null) return;
    final messenger = ScaffoldMessenger.of(_context);
    final room = await showDialog<Room>(
      context: _context,
      builder: (_) => _ForwardDialog(account: account),
    );
    if (room == null) return;
    await _run('Can’t forward', (t) => t.forward(eventId, room.id));
    messenger.showSnackBar(
      SnackBar(content: Text('Forwarded to ${room.name}')),
    );
  }

  Future<void> save(MediaEntry entry) =>
      saveMediaAs(_context, _ref, account, entry.media);

  /// Pins [entry] to the top of the chat, or unpins it.
  Future<void> setPin(TimelineEntry entry, {required bool pinned}) async {
    final eventId = eventFields(entry)?.meta.eventId;
    if (eventId == null) return;
    await setPinned(
      _context,
      _ref,
      account: account,
      roomId: roomId,
      eventId: eventId,
      pinned: pinned,
    );
  }

  /// What can be done with [entry], in the order the menus show it.
  List<MessageAction> actions(
    TimelineEntry entry, {
    required bool canRedactOthers,
  }) {
    final fields = eventFields(entry);
    if (fields == null || entry is RedactedEntry) return const [];
    final sent = fields.meta.eventId != null;
    return [
      if (sent && entry is! UndecryptableEntry) ...[
        MessageAction(
          'react',
          'React…',
          Icons.add_reaction_outlined,
          () => unawaited(react(entry)),
        ),
        MessageAction(
          'reply',
          'Reply',
          Icons.reply_rounded,
          () => reply(entry),
        ),
        if (thread == null)
          MessageAction(
            'thread',
            'Reply in thread',
            Icons.forum_outlined,
            () => openThread(entry),
          ),
      ],
      if (entry is MessageEntry || entry is MediaEntry)
        MessageAction(
          'copy',
          'Copy message',
          Icons.copy_rounded,
          () => copy(entry),
        ),
      if (sent && (entry is MessageEntry || entry is MediaEntry))
        MessageAction(
          'forward',
          'Forward…',
          Icons.shortcut_rounded,
          () => unawaited(forward(entry)),
        ),
      if (fields.meta.eventId case final eventId?
          when entry is! UndecryptableEntry && canPin(_ref, account, roomId))
        isPinned(_ref, account, roomId, eventId)
            ? MessageAction(
                'unpin',
                'Unpin',
                Icons.push_pin_rounded,
                () => unawaited(setPin(entry, pinned: false)),
              )
            : MessageAction(
                'pin',
                'Pin',
                Icons.push_pin_outlined,
                () => unawaited(setPin(entry, pinned: true)),
              ),
      if (fields.meta.isEditable)
        MessageAction('edit', 'Edit', Icons.edit_outlined, () => edit(entry)),
      if (entry is MediaEntry)
        MessageAction(
          'save',
          'Save as…',
          Icons.download_rounded,
          () => unawaited(save(entry)),
        ),
      if (fields.sendState == SendState.failed)
        MessageAction(
          'retry',
          'Retry',
          Icons.refresh_rounded,
          () => unawaited(retry(entry)),
        ),
      if (fields.isOwn || canRedactOthers)
        MessageAction(
          'delete',
          'Delete',
          Icons.delete_outline_rounded,
          () => unawaited(delete(entry)),
          destructive: true,
        ),
    ];
  }

  /// The menu items for [entry], in the order the menu shows them.
  List<ContextMenuButtonItem> menuItems(
    TimelineEntry entry, {
    required bool canRedactOthers,
    required VoidCallback close,
  }) => [
    for (final action in actions(entry, canRedactOthers: canRedactOthers))
      ContextMenuButtonItem(
        label: action.label,
        onPressed: () {
          close();
          action.run();
        },
      ),
  ];
}

/// One thing to do with a message, as the menus and the touch action sheet show it.
final class MessageAction {
  const MessageAction(
    this.id,
    this.label,
    this.icon,
    this.run, {
    this.destructive = false,
  });

  /// Stable, for keys: `reply`, `copy`, `delete`…
  final String id;
  final String label;
  final IconData icon;
  final VoidCallback run;

  /// It removes something, so it shows in red.
  final bool destructive;
}

/// A chat to forward to: the account's joined chats, with a search field.
class _ForwardDialog extends ConsumerStatefulWidget {
  const _ForwardDialog({required this.account});

  final String account;

  @override
  ConsumerState<_ForwardDialog> createState() => _ForwardDialogState();
}

class _ForwardDialogState extends ConsumerState<_ForwardDialog> {
  var _query = '';

  @override
  Widget build(BuildContext context) {
    final rooms = [
      for (final room
          in ref.watch(roomsProvider(widget.account)).value ?? const <Room>[])
        if (room.membership == Membership.joined &&
            room.name.toLowerCase().contains(_query.toLowerCase()))
          room,
    ];
    return AlertDialog(
      title: const Text('Forward to'),
      contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
      content: SizedBox(
        width: 360,
        height: 420,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                key: const Key('forward.search'),
                autofocus: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded),
                  hintText: 'Search chats',
                ),
                onChanged: (query) => setState(() => _query = query),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  for (final room in rooms)
                    ListTile(
                      key: Key('forward.${room.id}'),
                      leading: MatrixAvatar(
                        account: widget.account,
                        url: room.avatarUrl,
                        name: room.name,
                        seed: room.id,
                        radius: 18,
                      ),
                      title: Text(room.name),
                      onTap: () => Navigator.of(context).pop(room),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

/// The reactions under a message: an emoji each, with a count from two up, quiet grey tags
/// with cut corners; the user's own count is in the text colour, the others' muted. A click
/// gives or takes back the user's, hovering shows who gave it.
class ReactionChips extends StatelessWidget {
  const ReactionChips({
    required this.reactions,
    required this.onToggle,
    super.key,
  });

  final List<Reaction> reactions;
  final void Function(String key) onToggle;

  @override
  Widget build(BuildContext context) {
    final palette = context.oxi;
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 4),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final reaction in reactions)
            Tooltip(
              message: reaction.senders.join('\n'),
              child: Material(
                key: Key('reactionChip.${reaction.key}'),
                color: palette.reaction,
                shape: OxiShapes.cut(5),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => onToggle(reaction.key),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(6, 1, 7, 1),
                    child: _ReactionLabel(reaction: reaction),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Sizes of a reaction's emoji and its count. The count is about 73% of the emoji and muted,
/// so a keycap emoji like 3️⃣ doesn't read as a count (bkv, 2026-10-21).
const reactionEmojiSize = 15.0;
const reactionCountSize = 11.0;

/// A reaction's emoji, and its count when more than one person gave it.
class _ReactionLabel extends StatelessWidget {
  const _ReactionLabel({required this.reaction});

  final Reaction reaction;

  @override
  Widget build(BuildContext context) {
    final count = reaction.senders.length;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          reaction.key,
          key: Key('reactionChip.${reaction.key}.emoji'),
          style: const TextStyle(fontSize: reactionEmojiSize),
        ),
        if (count > 1) ...[
          const SizedBox(width: 4),
          Text(
            '$count',
            key: Key('reactionChip.${reaction.key}.count'),
            style: TextStyle(
              fontSize: reactionCountSize,
              fontWeight: FontWeight.w700,
              // The user's own in the text colour, the others' muted.
              color: reaction.mine
                  ? Theme.of(context).colorScheme.onSurface
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// The message a reply answers, at the top of its bubble.
class ReplyQuoteView extends StatelessWidget {
  const ReplyQuoteView({required this.quote, this.onTap, super.key});

  final ReplyQuote quote;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final name = quote.senderName ?? quote.sender;
    final palette = context.oxi;
    return GestureDetector(
      key: const Key('message.quote'),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(top: 2, bottom: 4),
        padding: const EdgeInsets.fromLTRB(8, 3, 8, 3),
        decoration: BoxDecoration(
          color: palette.quote,
          border: Border(left: BorderSide(color: palette.quoteBar, width: 3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (name != null)
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            Text(
              quote.text ?? 'Loading…',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontStyle: quote.text == null ? FontStyle.italic : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
