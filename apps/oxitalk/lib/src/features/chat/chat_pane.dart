import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
import '../../matrix/api/matrix.dart';
import '../../ui/avatar.dart';
import '../../ui/format.dart';
import '../../ui/rich_text_view.dart';
import '../../app/file_actions.dart';
import '../chats/badges.dart';
import 'emoji.dart';
import 'emoticons.dart';
import 'media_views.dart';
import 'message_actions.dart';
import 'send_files.dart';

/// A chat of the active account as a page of its own (narrow windows).
class ChatScreen extends ConsumerWidget {
  const ChatScreen({required this.roomId, super.key});

  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(activeAccountProvider);
    if (account == null) return const SizedBox.shrink();
    return ChatPane(
      key: ValueKey((account, roomId)),
      account: account,
      roomId: roomId,
      showBack: true,
    );
  }
}

class ChatPane extends ConsumerWidget {
  const ChatPane({
    required this.account,
    required this.roomId,
    required this.showBack,
    super.key,
  });

  /// The user ID of the account the chat belongs to.
  final String account;
  final String roomId;
  final bool showBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final room = ref
        .watch(roomsProvider(account))
        .value
        ?.where((room) => room.id == roomId)
        .firstOrNull;
    final name = room?.name ?? roomId;
    final typing = typingLabel(
      ref.watch(typingProvider(account)).value?[roomId],
      direct: room?.isDm ?? false,
    );
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: showBack
            ? BackButton(onPressed: () => context.go(Routes.chats))
            : null,
        titleSpacing: showBack ? 0 : null,
        actions: [
          IconButton(
            key: const Key('chat.threads'),
            tooltip: 'Threads',
            icon: const Icon(Icons.forum_outlined),
            onPressed: () => context.go(Routes.threads(roomId)),
          ),
        ],
        // The picture and name, and only they, open the chat's info.
        title: Align(
          alignment: AlignmentDirectional.centerStart,
          child: Tooltip(
            message: 'Chat info',
            child: InkWell(
              key: const Key('chat.title'),
              borderRadius: BorderRadius.circular(8),
              onTap: () => context.go(Routes.roomInfo(roomId)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MatrixAvatar(
                      account: account,
                      url: room?.avatarUrl,
                      name: name,
                      seed: roomId,
                      radius: 18,
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (room?.isMuted ?? false) ...[
                                const SizedBox(width: 6),
                                const MutedIcon(
                                  key: Key('chat.muted'),
                                  size: 16,
                                ),
                              ],
                            ],
                          ),
                          if (typing != null)
                            Text(
                              typing,
                              key: const Key('chat.typing'),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: OxiColors.accent),
                            )
                          else if (room?.isEncrypted ?? false)
                            Text(
                              'end-to-end encrypted',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      // Files dropped anywhere on the chat go to the send dialog.
      body: DropTarget(
        onDragDone: (details) => unawaited(
          _sendDropped(context, ref, [for (final f in details.files) f.path]),
        ),
        child: ColoredBox(
          color: context.isDark
              ? OxiColors.wallpaperDark
              : OxiColors.wallpaperLight,
          child: Column(
            children: [
              Expanded(
                child: TimelineView(
                  account: account,
                  roomId: roomId,
                  showSenders: !(room?.isDm ?? false),
                ),
              ),
              Composer(account: account, roomId: roomId),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _sendDropped(
    BuildContext context,
    WidgetRef ref,
    List<String> paths,
  ) async {
    final files = await ref.read(fileActionsProvider).readFiles(paths);
    if (!context.mounted) return;
    await confirmAndSendFiles(
      context,
      ref,
      account: account,
      roomId: roomId,
      files: files,
    );
  }
}

class TimelineView extends ConsumerStatefulWidget {
  const TimelineView({
    required this.account,
    required this.roomId,
    required this.showSenders,
    this.thread,
    super.key,
  });

  final String account;
  final String roomId;

  /// The thread's first event ID, to show that thread instead of the chat.
  final String? thread;

  /// Names above other people's messages; off in direct chats.
  final bool showSenders;

  @override
  ConsumerState<TimelineView> createState() => _TimelineViewState();
}

class _TimelineViewState extends ConsumerState<TimelineView> {
  var _loadingOlder = false;
  var _reachedStart = false;

  /// Whether the newest message is in view; the list is reversed, so its start is the bottom.
  var _atBottom = true;

  /// The message bubbles, to find the one a context menu was opened on, or a quote's original.
  final _bubbleKeys = <String, GlobalKey>{};

  /// The newest entry when the room was last marked read.
  String? _readUpTo;
  late final AppLifecycleListener _lifecycle;

  MessageActions get _actions => MessageActions(
    context,
    ref,
    widget.account,
    widget.roomId,
    thread: widget.thread,
  );

  /// Whether the room's unread mark was taken away since it was opened; once only, so
  /// marking it unread while it is open sticks.
  var _unmarked = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: () => unawaited(_markRead()));
    if (widget.thread == null) {
      ref.listenManual(
        roomsProvider(widget.account),
        (_, rooms) => _clearUnreadMark(rooms.value),
        fireImmediately: true,
      );
    }
  }

  /// Opening a room takes away its unread mark, as Element does.
  void _clearUnreadMark(List<Room>? rooms) {
    final room = rooms?.where((room) => room.id == widget.roomId).firstOrNull;
    if (_unmarked || room == null || !room.markedUnread) return;
    _unmarked = true;
    final session = ref.read(accountsProvider).value?.byId(widget.account);
    unawaited(
      session?.setMarkedUnread(widget.roomId, false).catchError((Object _) {
        // Tried again when the room list changes.
        _unmarked = false;
      }),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  /// Marks the room read while the user can see its newest message: the chat is open, the
  /// window in front and the timeline at the bottom.
  Future<void> _markRead() async {
    final state = WidgetsBinding.instance.lifecycleState;
    if (!mounted || !_atBottom) return;
    if (state != null && state != AppLifecycleState.resumed) return;
    final newest = ref
        .read(
          timelineEntriesProvider(
            widget.account,
            widget.roomId,
            thread: widget.thread,
          ),
        )
        .value
        ?.lastOrNull
        ?.id;
    final timeline = ref
        .read(
          roomTimelineProvider(
            widget.account,
            widget.roomId,
            thread: widget.thread,
          ),
        )
        .value;
    if (newest == null || newest == _readUpTo || timeline == null) return;
    _readUpTo = newest;
    try {
      await timeline.markAsRead();
    } on MatrixFailure {
      // Tried again with the next message.
      _readUpTo = null;
    }
  }

  /// Loads older messages when the list is short or scrolled near its top.
  Future<void> _loadOlder() async {
    if (_loadingOlder || _reachedStart) return;
    final timeline = ref
        .read(
          roomTimelineProvider(
            widget.account,
            widget.roomId,
            thread: widget.thread,
          ),
        )
        .value;
    if (timeline == null) return;
    _loadingOlder = true;
    try {
      _reachedStart = await timeline.loadOlder();
    } on MatrixFailure {
      // Tried again on the next scroll.
    } finally {
      _loadingOlder = false;
    }
  }

  bool _onScroll(ScrollNotification notification) {
    // The list is reversed: its end is the oldest message.
    if (notification.metrics.extentAfter < 400) unawaited(_loadOlder());
    final atBottom = notification.metrics.extentBefore < 48;
    if (atBottom != _atBottom) {
      _atBottom = atBottom;
      if (atBottom) unawaited(_markRead());
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final entries = ref.watch(
      timelineEntriesProvider(
        widget.account,
        widget.roomId,
        thread: widget.thread,
      ),
    );
    return switch (entries) {
      AsyncData(value: final entries) => _list(entries),
      AsyncError(:final error) => Center(
        child: Text('Can’t open this chat: $error'),
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }

  Widget _list(List<TimelineEntry> entries) {
    if (entries.lastOrNull?.id != _readUpTo) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => unawaited(_markRead()),
      );
    }
    if (entries.length < 20) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => unawaited(_loadOlder()),
      );
    }
    _bubbleKeys.removeWhere((id, _) => !entries.any((entry) => entry.id == id));
    final canRedactOthers =
        ref
            .watch(canRedactOthersProvider(widget.account, widget.roomId))
            .value ??
        false;
    // Message text can be selected, across messages too, and copied; the context menu has
    // what can be done with the message it was opened on.
    return SelectionArea(
      contextMenuBuilder: (context, region) {
        final entry = _entryAt(
          region.contextMenuAnchors.primaryAnchor,
          entries,
        );
        return AdaptiveTextSelectionToolbar.buttonItems(
          anchors: region.contextMenuAnchors,
          buttonItems: [
            ...region.contextMenuButtonItems,
            if (entry != null)
              ..._actions.menuItems(
                entry,
                canRedactOthers: canRedactOthers,
                close: region.hideToolbar,
              ),
          ],
        );
      },
      child: _scrollable(entries, canRedactOthers: canRedactOthers),
    );
  }

  /// The message whose bubble is at [position] on screen.
  TimelineEntry? _entryAt(Offset position, List<TimelineEntry> entries) {
    for (final entry in entries) {
      final box = _bubbleKeys[entry.id]?.currentContext?.findRenderObject();
      if (box is RenderBox &&
          box.attached &&
          (box.localToGlobal(Offset.zero) & box.size).contains(position)) {
        return entry;
      }
    }
    return null;
  }

  /// Scrolls to the message [eventId] if it is loaded and built; else says where it is.
  void _showOriginal(String eventId, List<TimelineEntry> entries) {
    final entry = entries
        .where((entry) => eventFields(entry)?.meta.eventId == eventId)
        .firstOrNull;
    final context = entry == null
        ? null
        : _bubbleKeys[entry.id]?.currentContext;
    if (context != null) {
      unawaited(
        Scrollable.ensureVisible(
          context,
          alignment: 0.5,
          duration: const Duration(milliseconds: 300),
        ),
      );
    } else {
      ScaffoldMessenger.of(this.context).showSnackBar(
        const SnackBar(content: Text('Scroll up to see that message')),
      );
    }
  }

  Widget _scrollable(
    List<TimelineEntry> entries, {
    required bool canRedactOthers,
  }) {
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: ListView.builder(
        reverse: true,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        itemCount: entries.length,
        itemBuilder: (context, index) {
          final position = entries.length - 1 - index;
          final entry = entries[position];
          if (entry case DayDivider(:final day)) {
            return SelectionContainer.disabled(
              child: _DayChip(label: dayLabel(day)),
            );
          }
          final previous = position > 0 ? entries[position - 1] : null;
          final next = position < entries.length - 1
              ? entries[position + 1]
              : null;
          return _bubble(entry, previous, next, entries, canRedactOthers);
        },
      ),
    );
  }

  Widget _bubble(
    TimelineEntry entry,
    TimelineEntry? previous,
    TimelineEntry? next,
    List<TimelineEntry> entries,
    bool canRedactOthers,
  ) {
    final fields = eventFields(entry)!;
    final meta = fields.meta;
    final quote = meta.inReplyTo;
    final body = switch (entry) {
      MessageEntry(:final body) when isEmojiOnly(body) => Text(
        body,
        style: const TextStyle(fontSize: 40, height: 1.2),
      ),
      MessageEntry(:final formatted?) => RichTextView(
        blocks: formatted,
        onLink: _openLink,
      ),
      MessageEntry(:final body) => LinkifiedText(text: body, onLink: _openLink),
      MediaEntry(:final media) => MediaMessageView(
        account: widget.account,
        media: media,
      ),
      UndecryptableEntry() => const Text(
        'Waiting for this message…',
        style: TextStyle(fontStyle: FontStyle.italic),
      ),
      _ => const Text(
        'Message deleted',
        style: TextStyle(fontStyle: FontStyle.italic),
      ),
    };
    final canAct = meta.eventId != null && entry is! RedactedEntry;
    // In the chat, a thread shows under its first message; in the thread, it is all around.
    final thread = widget.thread == null ? meta.thread : null;
    return MessageBubble(
      key: _bubbleKeys.putIfAbsent(entry.id, GlobalKey.new),
      isOwn: fields.isOwn,
      plain: entry is MessageEntry && isEmojiOnly(entry.body),
      sender: _senderLabel(fields, previous),
      avatar: _senderAvatar(entry.id, fields, next),
      time: fields.time,
      sendState: fields.sendState,
      edited: meta.isEdited,
      quote: quote == null
          ? null
          : ReplyQuoteView(
              quote: quote,
              onTap: () => _showOriginal(quote.eventId, entries),
            ),
      footer: [
        if (meta.uploadPercent case final percent?)
          LinearProgressIndicator(
            key: const Key('message.upload'),
            value: percent / 100,
          ),
        if (fields.isOwn && fields.sendState == SendState.failed)
          _FailedActions(
            onRetry: () => unawaited(_actions.retry(entry)),
            onRemove: () => unawaited(_actions.delete(entry)),
          ),
      ],
      reactions: meta.reactions.isEmpty
          ? null
          : ReactionChips(
              reactions: meta.reactions,
              onToggle: (key) => unawaited(_actions.toggleReaction(entry, key)),
            ),
      thread: thread == null || meta.eventId == null
          ? null
          : ThreadBar(
              key: Key('thread.bar.${meta.eventId}'),
              account: widget.account,
              thread: thread,
              onTap: () => _actions.openThread(entry),
            ),
      hoverActions: canAct && entry is! UndecryptableEntry
          ? _HoverActions(
              onReact: () => unawaited(_actions.react(entry)),
              onReply: () => _actions.reply(entry),
              onThread: widget.thread == null
                  ? () => _actions.openThread(entry)
                  : null,
              menu: () => _actions.menuItems(
                entry,
                canRedactOthers: canRedactOthers,
                close: () {},
              ),
            )
          : null,
      child: body,
    );
  }

  void _openLink(String url) {
    final uri = Uri.tryParse(url);
    if (uri != null) unawaited(ref.read(fileActionsProvider).launch(uri));
  }

  /// In group chats, the sender's picture beside the last of their consecutive messages and
  /// an empty space of the same width beside the others; `null` in direct chats and for the
  /// user's own messages.
  Widget? _senderAvatar(String id, EventFields fields, TimelineEntry? next) {
    if (!widget.showSenders || fields.isOwn) return null;
    if (_sameSender(next, fields.sender)) {
      return const SizedBox(width: _senderAvatarRadius * 2);
    }
    return MatrixAvatar(
      key: Key('senderAvatar.$id'),
      account: widget.account,
      url: fields.senderAvatarUrl,
      name: fields.senderName ?? fields.sender,
      seed: fields.sender,
      radius: _senderAvatarRadius,
    );
  }

  static const _senderAvatarRadius = 16.0;

  static bool _sameSender(TimelineEntry? entry, String sender) =>
      switch (entry) {
        null => false,
        final entry => eventFields(entry)?.sender == sender,
      };

  /// The sender's name above the first of their consecutive messages, in group chats.
  String? _senderLabel(EventFields fields, TimelineEntry? previous) {
    if (!widget.showSenders || fields.isOwn) return null;
    return _sameSender(previous, fields.sender)
        ? null
        : fields.senderName ?? fields.sender;
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 13),
      ),
    ),
  );
}

/// A failed message of the user's: send it again, or drop it.
class _FailedActions extends StatelessWidget {
  const _FailedActions({required this.onRetry, required this.onRemove});

  final VoidCallback onRetry;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => SelectionContainer.disabled(
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(
          key: const Key('message.retry'),
          onPressed: onRetry,
          child: const Text('Retry'),
        ),
        TextButton(
          key: const Key('message.remove'),
          onPressed: onRemove,
          child: const Text('Remove'),
        ),
      ],
    ),
  );
}

/// The small toolbar beside a message under the mouse: react, reply, reply in a thread (in
/// the chat), and the rest.
class _HoverActions extends StatelessWidget {
  const _HoverActions({
    required this.onReact,
    required this.onReply,
    required this.menu,
    this.onThread,
  });

  final VoidCallback onReact;
  final VoidCallback onReply;
  final VoidCallback? onThread;

  /// The message menu's items, made when it opens.
  final List<ContextMenuButtonItem> Function() menu;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerHigh,
    elevation: 1,
    borderRadius: BorderRadius.circular(16),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _toolbarButton(
          const Key('hover.react'),
          'React',
          Icons.add_reaction_outlined,
          onReact,
        ),
        _toolbarButton(
          const Key('hover.reply'),
          'Reply',
          Icons.reply_rounded,
          onReply,
        ),
        if (onThread case final onThread?)
          _toolbarButton(
            const Key('hover.thread'),
            'Reply in thread',
            Icons.forum_outlined,
            onThread,
          ),
        Builder(
          builder: (context) => _toolbarButton(
            const Key('hover.more'),
            'More',
            Icons.more_horiz_rounded,
            () => unawaited(_openMenu(context)),
          ),
        ),
      ],
    ),
  );

  static Widget _toolbarButton(
    Key key,
    String tooltip,
    IconData icon,
    VoidCallback onPressed,
  ) => IconButton(
    key: key,
    tooltip: tooltip,
    iconSize: 18,
    visualDensity: VisualDensity.compact,
    onPressed: onPressed,
    icon: Icon(icon),
  );

  Future<void> _openMenu(BuildContext context) async {
    final box = context.findRenderObject()! as RenderBox;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final items = menu();
    final chosen = await showMenu<int>(
      context: context,
      position: RelativeRect.fromRect(
        box.localToGlobal(Offset.zero, ancestor: overlay) & box.size,
        Offset.zero & overlay.size,
      ),
      items: [
        for (final (index, item) in items.indexed)
          PopupMenuItem(value: index, child: Text(item.label ?? '')),
      ],
    );
    if (chosen != null) items[chosen].onPressed?.call();
  }
}

class MessageBubble extends StatefulWidget {
  const MessageBubble({
    required this.isOwn,
    required this.time,
    required this.child,
    this.sender,
    this.avatar,
    this.sendState,
    this.edited = false,
    this.plain = false,
    this.quote,
    this.footer = const [],
    this.reactions,
    this.thread,
    this.hoverActions,
    super.key,
  });

  final bool isOwn;
  final String? sender;

  /// Beside the bubble, on its left.
  final Widget? avatar;
  final DateTime time;
  final SendState? sendState;
  final Widget child;
  final bool edited;

  /// Without the bubble: a message of big emojis.
  final bool plain;

  /// The message this one answers, above the content.
  final Widget? quote;

  /// Under the content: upload progress, or what to do with a failed message.
  final List<Widget> footer;

  /// Under the bubble.
  final Widget? reactions;

  /// Under the reactions: the thread that starts at this message.
  final Widget? thread;

  /// Shown beside the bubble while the mouse is over the message.
  final Widget? hoverActions;

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    final isOwn = widget.isOwn;
    final color = widget.plain
        ? Colors.transparent
        : isOwn
        ? (dark ? OxiColors.ownBubbleDark : OxiColors.ownBubbleLight)
        : (dark ? OxiColors.bubbleDark : OxiColors.bubbleLight);
    final meta = Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11);
    final sender = widget.sender;
    final bubble = ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.75,
      ),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(isOwn ? 14 : 4),
            bottomRight: Radius.circular(isOwn ? 4 : 14),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (sender != null)
              SelectionContainer.disabled(
                child: Text(
                  sender,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color:
                        OxiColors.avatars[sender.hashCode.abs() %
                            OxiColors.avatars.length],
                  ),
                ),
              ),
            ?widget.quote,
            Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: 8,
              children: [
                widget.child,
                SelectionContainer.disabled(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.edited) Text('edited', style: meta),
                      if (widget.edited) const SizedBox(width: 4),
                      Text(clockTime(widget.time), style: meta),
                      if (isOwn && widget.sendState != null) ...[
                        const SizedBox(width: 3),
                        _SendStateIcon(state: widget.sendState!),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            ...widget.footer,
          ],
        ),
      ),
    );
    final reactions = widget.reactions;
    final content = Column(
      crossAxisAlignment: isOwn
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [bubble, ?reactions, ?widget.thread],
    );
    final hoverActions = widget.hoverActions;
    // Room kept for the toolbar, so the message doesn't move when it shows.
    final toolbar = hoverActions == null
        ? null
        : SelectionContainer.disabled(
            child: Visibility(
              visible: _hovered,
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
              child: hoverActions,
            ),
          );
    final avatar = widget.avatar;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Align(
        alignment: isOwn ? Alignment.centerRight : Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (isOwn && toolbar != null) ...[
              toolbar,
              const SizedBox(width: 4),
            ],
            if (avatar != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 2, right: 6),
                child: avatar,
              ),
            Flexible(child: content),
            if (!isOwn && toolbar != null) ...[
              const SizedBox(width: 4),
              toolbar,
            ],
          ],
        ),
      ),
    );
  }
}

class _SendStateIcon extends StatelessWidget {
  const _SendStateIcon({required this.state});

  final SendState state;

  @override
  Widget build(BuildContext context) => switch (state) {
    SendState.sending => const Icon(
      Icons.schedule_rounded,
      size: 14,
      semanticLabel: 'Sending',
    ),
    SendState.sent => const Icon(
      Icons.done_rounded,
      size: 14,
      color: OxiColors.accent,
      semanticLabel: 'Sent',
    ),
    SendState.failed => Icon(
      Icons.error_outline_rounded,
      size: 14,
      color: Theme.of(context).colorScheme.error,
      semanticLabel: 'Not sent',
    ),
  };
}

/// The message box: text with emojis, files by 📎, paste or drop; a reply or an edit when the
/// message menu started one (Esc cancels). With [thread], it writes into that thread.
class Composer extends ConsumerStatefulWidget {
  const Composer({
    required this.account,
    required this.roomId,
    this.thread,
    super.key,
  });

  final String account;
  final String roomId;

  /// The thread's first event ID.
  final String? thread;

  @override
  ConsumerState<Composer> createState() => _ComposerState();
}

class _ComposerState extends ConsumerState<Composer> {
  final _text = TextEditingController();
  late final _emoticons = EmoticonFormatter(
    enabled: () => ref.read(replaceEmoticonsProvider),
  );
  final _focus = FocusNode();

  /// Ends the user's typing after a pause.
  Timer? _typingPause;
  var _typing = false;

  /// Where the last notice went; `ref` can't be used once the composer is gone.
  RoomTimeline? _typingIn;

  ComposerKey get _chat => (widget.account, widget.roomId, widget.thread);

  RoomTimeline? get _timeline => ref
      .read(
        roomTimelineProvider(
          widget.account,
          widget.roomId,
          thread: widget.thread,
        ),
      )
      .value;

  @override
  void initState() {
    super.initState();
    _text.addListener(_onText);
  }

  @override
  void dispose() {
    _typingPause?.cancel();
    if (_typing) {
      unawaited(_typingIn?.setTyping(false).catchError((Object _) {}));
    }
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Tells the room the user types while there is text and keys are pressed, and stops
  /// after [_typingTimeout] without a change, or when the text is gone.
  void _onText() {
    if (!ref.read(sendTypingProvider)) return;
    _typingPause?.cancel();
    if (_text.text.trim().isEmpty) {
      if (_typing) _sendTyping(false);
      return;
    }
    _sendTyping(true);
    _typingPause = Timer(_typingTimeout, () => _sendTyping(false));
  }

  static const _typingTimeout = Duration(seconds: 5);

  void _sendTyping(bool typing) {
    _typing = typing;
    final timeline = _timeline;
    _typingIn = timeline;
    unawaited(
      timeline?.setTyping(typing).catchError((Object _) {
        // Only the others' view of the user's typing; nothing to tell the user.
      }),
    );
  }

  void _setMode(ComposerMode? mode) =>
      ref.read(composerModeProvider(_chat).notifier).set(mode);

  Future<void> _send() async {
    final typed = _text.text.trim();
    final text = ref.read(replaceEmoticonsProvider)
        ? withTrailingEmoticon(typed)
        : typed;
    final mode = ref.read(composerModeProvider(_chat));
    final timeline = _timeline;
    // An empty edit of a caption removes it; empty text sends nothing.
    final editingCaption = mode is Editing && mode.entry is MediaEntry;
    if ((text.isEmpty && !editingCaption) || timeline == null) return;
    _text.clear();
    _setMode(null);
    _focus.requestFocus();
    final markdown = ref.read(useMarkdownProvider);
    try {
      switch (mode) {
        case null:
          await timeline.send(text, markdown: markdown);
        case Replying(:final entry):
          final eventId = eventFields(entry)?.meta.eventId;
          eventId == null
              ? await timeline.send(text, markdown: markdown)
              : await timeline.sendReply(text, eventId, markdown: markdown);
        case Editing(:final entry):
          final ref = eventFields(entry)?.meta.ref;
          if (ref != null) {
            await timeline.edit(
              ref,
              text,
              caption: entry is MediaEntry,
              markdown: markdown,
            );
          }
      }
    } on MatrixFailure catch (failure) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Not sent: ${failure.kind.name}')),
        );
      }
    }
  }

  Future<void> _attach() async {
    final files = await ref.read(fileActionsProvider).pickFiles();
    if (!mounted) return;
    await confirmAndSendFiles(
      context,
      ref,
      account: widget.account,
      roomId: widget.roomId,
      files: files,
      thread: widget.thread,
    );
  }

  /// Ctrl+V: an image or copied files go to the send dialog; text is pasted as usual.
  Future<void> _paste() async {
    final files = ref.read(fileActionsProvider);
    final image = await files.clipboardImage();
    final copied = image == null
        ? await files.clipboardFiles()
        : const <String>[];
    if (image != null || copied.isNotEmpty) {
      final pending = image != null
          ? [PendingFile('pasted.png', 'image/png', image)]
          : await files.readFiles(copied);
      if (!mounted) return;
      await confirmAndSendFiles(
        context,
        ref,
        account: widget.account,
        roomId: widget.roomId,
        files: pending,
        thread: widget.thread,
      );
      return;
    }
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    if (text != null && mounted) _insert(text);
  }

  /// Puts [text] where the cursor is, replacing a selection.
  void _insert(String text) {
    final value = _text.value;
    final selection = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: value.text.length);
    _text.value = value.copyWith(
      text: value.text.replaceRange(selection.start, selection.end, text),
      selection: TextSelection.collapsed(offset: selection.start + text.length),
    );
  }

  Future<void> _pickEmoji() async {
    final emoji = await showDialog<String>(
      context: context,
      builder: (context) => Dialog(
        key: const Key('composer.emojiPicker'),
        child: SizedBox(
          width: 380,
          child: emojiPicker(
            onSelected: (emoji) => Navigator.of(context).pop(emoji),
          ),
        ),
      ),
    );
    if (emoji == null || !mounted) return;
    _insert(emoji);
    rememberEmoji(ref, widget.account, emoji);
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(composerModeProvider(_chat));
    ref.listen(composerModeProvider(_chat), (previous, next) {
      if (next is Editing) {
        _text.text = messageText(next.entry);
        if (next.entry case MediaEntry(:final media)) {
          _text.text = media.caption ?? '';
        }
      } else if (previous is Editing) {
        _text.clear();
      }
      if (next != null) _focus.requestFocus();
    });
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (mode != null)
              _ModeBar(mode: mode, onCancel: () => _setMode(null)),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    key: const Key('composer.attach'),
                    tooltip: 'Attach files',
                    icon: const Icon(Icons.attach_file_rounded),
                    onPressed: () => unawaited(_attach()),
                  ),
                  Expanded(
                    child: CallbackShortcuts(
                      // Enter sends; Shift+Enter makes a new line; Esc drops a reply or
                      // an edit.
                      bindings: {
                        const SingleActivator(LogicalKeyboardKey.enter): () =>
                            unawaited(_send()),
                        const SingleActivator(
                          LogicalKeyboardKey.keyV,
                          control: true,
                        ): () =>
                            unawaited(_paste()),
                        const SingleActivator(
                          LogicalKeyboardKey.keyV,
                          meta: true,
                        ): () =>
                            unawaited(_paste()),
                        if (mode != null)
                          const SingleActivator(
                            LogicalKeyboardKey.escape,
                          ): () =>
                              _setMode(null),
                      },
                      child: TextField(
                        key: const Key('composer.text'),
                        controller: _text,
                        focusNode: _focus,
                        minLines: 1,
                        maxLines: 6,
                        textCapitalization: TextCapitalization.sentences,
                        inputFormatters: [_emoticons],
                        decoration: InputDecoration(
                          hintText: widget.thread == null
                              ? 'Message'
                              : 'Reply in thread',
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    key: const Key('composer.emoji'),
                    tooltip: 'Emoji',
                    icon: const Icon(Icons.emoji_emotions_outlined),
                    onPressed: () => unawaited(_pickEmoji()),
                  ),
                  IconButton(
                    key: const Key('composer.send'),
                    tooltip: mode is Editing ? 'Save' : 'Send',
                    color: OxiColors.accent,
                    icon: Icon(
                      mode is Editing
                          ? Icons.check_rounded
                          : Icons.send_rounded,
                    ),
                    onPressed: () => unawaited(_send()),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Above the message box: which message the user answers or edits, with ✕ to stop.
class _ModeBar extends StatelessWidget {
  const _ModeBar({required this.mode, required this.onCancel});

  final ComposerMode mode;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final fields = eventFields(mode.entry);
    final name = fields?.senderName ?? fields?.sender ?? '';
    return Padding(
      key: const Key('composer.mode'),
      padding: const EdgeInsets.fromLTRB(16, 6, 4, 0),
      child: Row(
        children: [
          Icon(
            mode is Editing ? Icons.edit_rounded : Icons.reply_rounded,
            size: 18,
            color: OxiColors.accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  mode is Editing ? 'Editing' : 'Replying to $name',
                  style: const TextStyle(
                    color: OxiColors.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  messageText(mode.entry),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            key: const Key('composer.cancelMode'),
            tooltip: 'Cancel',
            icon: const Icon(Icons.close_rounded),
            onPressed: onCancel,
          ),
        ],
      ),
    );
  }
}

/// Under a thread's first message: how many replies, who wrote the latest and when; opens
/// the thread.
class ThreadBar extends StatelessWidget {
  const ThreadBar({
    required this.account,
    required this.thread,
    required this.onTap,
    super.key,
  });

  final String account;
  final ThreadSummary thread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final latest = thread.latest;
    final small = Theme.of(context).textTheme.bodySmall;
    return SelectionContainer.disabled(
      child: Padding(
        padding: const EdgeInsets.only(top: 2, bottom: 4),
        child: Material(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 12, 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (latest != null) ...[
                    MatrixAvatar(
                      account: account,
                      url: latest.senderAvatarUrl,
                      name: latest.senderName ?? latest.sender,
                      seed: latest.sender,
                      radius: 10,
                    ),
                    const SizedBox(width: 6),
                  ] else ...[
                    const Icon(
                      Icons.forum_outlined,
                      size: 16,
                      color: OxiColors.accent,
                    ),
                    const SizedBox(width: 6),
                  ],
                  // Narrow bubbles shorten the texts rather than overflow.
                  Flexible(
                    child: Text(
                      replyCountLabel(thread.replyCount),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: OxiColors.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (latest != null) ...[
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        listTime(latest.time),
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        style: small,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
