import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
import '../../app/window_controls.dart';
import '../../matrix/api/matrix.dart';
import '../../ui/avatar.dart';
import '../../ui/format.dart';
import 'media_views.dart';

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
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: showBack
            ? BackButton(onPressed: () => context.go(Routes.chats))
            : null,
        titleSpacing: showBack ? 0 : null,
        // The rest of the header is the window's title bar.
        flexibleSpace: const WindowDragArea(),
        actions: const [WindowButtons.right()],
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
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (room?.isEncrypted ?? false)
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
      body: ColoredBox(
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
    );
  }
}

class TimelineView extends ConsumerStatefulWidget {
  const TimelineView({
    required this.account,
    required this.roomId,
    required this.showSenders,
    super.key,
  });

  final String account;
  final String roomId;

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

  /// The message bubbles, to find the one a context menu was opened on.
  final _bubbleKeys = <String, GlobalKey>{};

  /// The newest entry when the room was last marked read.
  String? _readUpTo;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: () => unawaited(_markRead()));
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
        .read(timelineEntriesProvider(widget.account, widget.roomId))
        .value
        ?.lastOrNull
        ?.id;
    final timeline = ref
        .read(roomTimelineProvider(widget.account, widget.roomId))
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
        .read(roomTimelineProvider(widget.account, widget.roomId))
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
      timelineEntriesProvider(widget.account, widget.roomId),
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
    // Message text can be selected, across messages too, and copied; the context menu also
    // copies the whole message it was opened on.
    return SelectionArea(
      contextMenuBuilder: (context, region) {
        final entry = _entryAt(
          region.contextMenuAnchors.primaryAnchor,
          entries,
        );
        final text = switch (entry) {
          MessageEntry(:final body) => body,
          MediaEntry(:final media) => media.caption,
          _ => null,
        };
        return AdaptiveTextSelectionToolbar.buttonItems(
          anchors: region.contextMenuAnchors,
          buttonItems: [
            ...region.contextMenuButtonItems,
            if (text != null && text.isNotEmpty)
              ContextMenuButtonItem(
                label: 'Copy message',
                onPressed: () {
                  region.hideToolbar();
                  unawaited(Clipboard.setData(ClipboardData(text: text)));
                },
              ),
            if (entry case MediaEntry(:final media))
              ContextMenuButtonItem(
                label: 'Save as…',
                onPressed: () {
                  region.hideToolbar();
                  unawaited(saveMediaAs(context, ref, widget.account, media));
                },
              ),
          ],
        );
      },
      child: _scrollable(entries),
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

  Widget _scrollable(List<TimelineEntry> entries) {
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: ListView.builder(
        reverse: true,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        itemCount: entries.length,
        itemBuilder: (context, index) {
          final position = entries.length - 1 - index;
          final entry = entries[position];
          final previous = position > 0 ? entries[position - 1] : null;
          final next = position < entries.length - 1
              ? entries[position + 1]
              : null;
          return switch (entry) {
            DayDivider(:final day) => SelectionContainer.disabled(
              child: _DayChip(label: dayLabel(day)),
            ),
            MessageEntry() => MessageBubble(
              key: _bubbleKeys.putIfAbsent(entry.id, GlobalKey.new),
              isOwn: entry.isOwn,
              sender: _senderLabel(
                entry.sender,
                entry.senderName,
                entry.isOwn,
                previous,
              ),
              avatar: _senderAvatar(
                entry.id,
                entry.sender,
                entry.senderName,
                entry.senderAvatarUrl,
                entry.isOwn,
                next,
              ),
              time: entry.time,
              sendState: entry.sendState,
              child: Text(entry.body),
            ),
            MediaEntry() => MessageBubble(
              key: _bubbleKeys.putIfAbsent(entry.id, GlobalKey.new),
              isOwn: entry.isOwn,
              sender: _senderLabel(
                entry.sender,
                entry.senderName,
                entry.isOwn,
                previous,
              ),
              avatar: _senderAvatar(
                entry.id,
                entry.sender,
                entry.senderName,
                entry.senderAvatarUrl,
                entry.isOwn,
                next,
              ),
              time: entry.time,
              sendState: entry.sendState,
              child: MediaMessageView(
                account: widget.account,
                media: entry.media,
              ),
            ),
            UndecryptableEntry() => MessageBubble(
              key: ValueKey(entry.id),
              isOwn: entry.isOwn,
              sender: _senderLabel(
                entry.sender,
                entry.senderName,
                entry.isOwn,
                previous,
              ),
              avatar: _senderAvatar(
                entry.id,
                entry.sender,
                entry.senderName,
                entry.senderAvatarUrl,
                entry.isOwn,
                next,
              ),
              time: entry.time,
              child: const Text(
                'Waiting for this message…',
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
            ),
          };
        },
      ),
    );
  }

  /// In group chats, the sender's picture beside the last of their consecutive messages and
  /// an empty space of the same width beside the others; `null` in direct chats and for the
  /// user's own messages.
  Widget? _senderAvatar(
    String id,
    String sender,
    String? name,
    String? url,
    bool isOwn,
    TimelineEntry? next,
  ) {
    if (!widget.showSenders || isOwn) return null;
    if (_sameSender(next, sender)) {
      return const SizedBox(width: _senderAvatarRadius * 2);
    }
    return MatrixAvatar(
      key: Key('senderAvatar.$id'),
      account: widget.account,
      url: url,
      name: name ?? sender,
      seed: sender,
      radius: _senderAvatarRadius,
    );
  }

  static const _senderAvatarRadius = 16.0;

  static bool _sameSender(TimelineEntry? entry, String sender) =>
      switch (entry) {
        MessageEntry(sender: final s) ||
        MediaEntry(sender: final s) ||
        UndecryptableEntry(sender: final s) => s == sender,
        _ => false,
      };

  /// The sender's name above the first of their consecutive messages, in group chats.
  String? _senderLabel(
    String sender,
    String? name,
    bool isOwn,
    TimelineEntry? previous,
  ) {
    if (!widget.showSenders || isOwn) return null;
    return _sameSender(previous, sender) ? null : name ?? sender;
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

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    required this.isOwn,
    required this.time,
    required this.child,
    this.sender,
    this.avatar,
    this.sendState,
    super.key,
  });

  final bool isOwn;
  final String? sender;

  /// Beside the bubble, on its left.
  final Widget? avatar;
  final DateTime time;
  final SendState? sendState;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    final color = isOwn
        ? (dark ? OxiColors.ownBubbleDark : OxiColors.ownBubbleLight)
        : (dark ? OxiColors.bubbleDark : OxiColors.bubbleLight);
    final meta = Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11);
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
            if (sender case final sender?)
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
            Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: 8,
              children: [
                child,
                SelectionContainer.disabled(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(clockTime(time), style: meta),
                      if (isOwn && sendState != null) ...[
                        const SizedBox(width: 3),
                        _SendStateIcon(state: sendState!),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    final avatar = this.avatar;
    return Align(
      alignment: isOwn ? Alignment.centerRight : Alignment.centerLeft,
      child: avatar == null
          ? bubble
          : Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 2, right: 6),
                  child: avatar,
                ),
                Flexible(child: bubble),
              ],
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

class Composer extends ConsumerStatefulWidget {
  const Composer({required this.account, required this.roomId, super.key});

  final String account;
  final String roomId;

  @override
  ConsumerState<Composer> createState() => _ComposerState();
}

class _ComposerState extends ConsumerState<Composer> {
  final _text = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _text.text.trim();
    final timeline = ref
        .read(roomTimelineProvider(widget.account, widget.roomId))
        .value;
    if (text.isEmpty || timeline == null) return;
    _text.clear();
    _focus.requestFocus();
    try {
      await timeline.send(text);
    } on MatrixFailure catch (failure) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Not sent: ${failure.kind.name}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: CallbackShortcuts(
                // Enter sends; Shift+Enter makes a new line.
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.enter): () =>
                      unawaited(_send()),
                },
                child: TextField(
                  key: const Key('composer.text'),
                  controller: _text,
                  focusNode: _focus,
                  minLines: 1,
                  maxLines: 6,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'Message',
                    border: InputBorder.none,
                  ),
                ),
              ),
            ),
            IconButton(
              key: const Key('composer.send'),
              tooltip: 'Send',
              color: OxiColors.accent,
              icon: const Icon(Icons.send_rounded),
              onPressed: () => unawaited(_send()),
            ),
          ],
        ),
      ),
    ),
  );
}
