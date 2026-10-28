import 'dart:async';
import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
import '../../matrix/api/matrix.dart';
import '../../ui/avatar.dart';
import '../../ui/bubble_footer.dart';
import '../../ui/format.dart';
import '../../ui/rich_text_view.dart';
import '../../ui/touch.dart';
import '../../app/file_actions.dart';
import '../calls/call_controller.dart';
import '../calls/call_ui.dart';
import '../chats/badges.dart';
import 'chat_search.dart';
import 'drafts.dart';
import 'emoji.dart';
import 'emoticons.dart';
import 'invite_pane.dart';
import 'jump.dart';
import '../people/people_providers.dart';
import '../people/user_profile.dart';
import 'mentions/composer_controller.dart';
import 'mentions/mention_suggestions.dart';
import 'media_views.dart';
import 'message_actions.dart';
import 'message_sheet.dart';
import 'notice_line.dart';
import 'pins.dart';
import 'send_files.dart';
import 'video/video_message.dart';
import 'voice/audio_io.dart';
import 'voice/voice_composer.dart';

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
    // An invitation shows what it is about, to accept or decline, instead of the chat.
    if (room != null && room.membership == Membership.invited) {
      return InvitePane(account: account, room: room, showBack: showBack);
    }
    final name = room?.name ?? roomId;
    final typing = typingLabel(
      ref.watch(typingProvider(account)).value?[roomId],
      direct: room?.isDm ?? false,
    );
    final searching = ref.watch(
      chatSearchProvider((account, roomId)).select((search) => search.open),
    );
    void toggleSearch() {
      final search = ref.read(chatSearchProvider((account, roomId)).notifier);
      searching ? search.close() : search.open();
    }

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: showBack
            ? BackButton(onPressed: () => context.go(Routes.chats))
            : null,
        titleSpacing: showBack ? 0 : null,
        actions: [
          CallButtons(account: account, roomId: roomId),
          IconButton(
            key: const Key('chat.search'),
            tooltip: 'Search this chat (Ctrl+F)',
            isSelected: searching,
            icon: const Icon(Icons.search_rounded),
            onPressed: toggleSearch,
          ),
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
              customBorder: OxiShapes.small,
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
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                  ),
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
                                  ?.copyWith(color: context.oxi.muted),
                            )
                          else if (room?.isEncrypted ?? false)
                            Text(
                              'end-to-end encrypted',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: context.oxi.muted),
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
          color: context.oxi.wallpaper,
          child: Column(
            children: [
              if (searching)
                ChatSearchBar(account: account, roomId: roomId)
              else
                SearchShortcut(account: account, roomId: roomId),
              PinnedBanner(account: account, roomId: roomId),
              CallBanner(account: account, roomId: roomId),
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

  final _scroll = ScrollController();

  /// Where a jump (to a pin or a search hit) wants the chat; none in a thread.
  ChatJump _jump = const ChatJump();

  /// The jump being brought into view, by its serial.
  int? _jumping;

  /// Whether a timeline opened around an older message has all the newer ones.
  var _reachedEnd = false;
  var _loadingNewer = false;

  /// Takes a pin's highlight away after a moment.
  Timer? _highlightTimer;

  /// The folded runs of membership notices the user opened, by their first entry's ID.
  final _openRuns = <String>{};

  ChatKey get _chat => (widget.account, widget.roomId);

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
      // A chat opens at its newest messages, unless it opens to show one.
      final jump = ref.read(chatJumpProvider(_chat));
      if (jump.target == null && (jump.around ?? jump.highlight) != null) {
        Future.microtask(
          () => ref.read(chatJumpProvider(_chat).notifier).toLatest(),
        );
      }
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
    _scroll.dispose();
    _highlightTimer?.cancel();
    super.dispose();
  }

  /// The timeline shown: the live one, or the one around an older message.
  RoomTimeline? get _shownTimeline => switch (_jump.around) {
    final around? =>
      ref.read(timelineAtProvider(widget.account, widget.roomId, around)).value,
    null =>
      ref
          .read(
            roomTimelineProvider(
              widget.account,
              widget.roomId,
              thread: widget.thread,
            ),
          )
          .value,
  };

  /// Marks the room read while the user can see its newest message: the chat is open, the
  /// window in front and the timeline at the bottom.
  Future<void> _markRead() async {
    final state = WidgetsBinding.instance.lifecycleState;
    if (!mounted || !_atBottom || _jump.around != null) return;
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
    final timeline = _shownTimeline;
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

  /// Loads newer messages into a timeline around an older message; at the newest, back to
  /// the live timeline once the user is at the bottom.
  Future<void> _loadNewer({required bool atBottom}) async {
    if (_jump.around == null) return;
    if (_reachedEnd) {
      if (atBottom) ref.read(chatJumpProvider(_chat).notifier).toLatest();
      return;
    }
    final timeline = _shownTimeline;
    if (_loadingNewer || timeline == null) return;
    _loadingNewer = true;
    try {
      _reachedEnd = await timeline.loadNewer();
    } on MatrixFailure {
      // Tried again on the next scroll.
    } finally {
      _loadingNewer = false;
    }
  }

  bool _onScroll(ScrollNotification notification) {
    // The list is reversed: its end is the oldest message.
    if (notification.metrics.extentAfter < 400) unawaited(_loadOlder());
    if (notification.metrics.extentBefore < 400) {
      unawaited(_loadNewer(atBottom: notification.metrics.extentBefore < 48));
    }
    final atBottom = notification.metrics.extentBefore < 48;
    if (atBottom != _atBottom) {
      _atBottom = atBottom;
      if (atBottom) unawaited(_markRead());
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final jump = widget.thread == null
        ? ref.watch(chatJumpProvider(_chat))
        : const ChatJump();
    if (jump.around != _jump.around) {
      _reachedStart = false;
      _reachedEnd = false;
      _jumping = null;
      if (jump.around == null) {
        // Back at the newest messages, which are at the bottom.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) _scroll.jumpTo(0);
        });
      }
    }
    _jump = jump;
    // The menus offer Pin and Unpin by them.
    ref.watch(roomPinsProvider(widget.account, widget.roomId));
    final live = ref.watch(
      timelineEntriesProvider(
        widget.account,
        widget.roomId,
        thread: widget.thread,
      ),
    );
    final shown = switch (jump.around) {
      final around? => ref.watch(
        timelineAtEntriesProvider(widget.account, widget.roomId, around),
      ),
      null => live,
    };
    final entries = ref.watch(showMembershipEventsProvider)
        ? shown
        : shown.whenData(
            (entries) => [
              for (final entry in entries)
                if (!isMembershipNotice(entry)) entry,
            ],
          );
    return switch (entries) {
      AsyncData(value: final entries) when jump.around == null => _list(
        entries,
      ),
      AsyncData(value: final entries) => Stack(
        children: [
          _list(entries),
          PositionedDirectional(
            end: 16,
            bottom: 16,
            child: JumpToLatestButton(
              onPressed: () =>
                  ref.read(chatJumpProvider(_chat).notifier).toLatest(),
            ),
          ),
        ],
      ),
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
    if (_jump.target case final target? when _jumping != _jump.serial) {
      _jumping = _jump.serial;
      final jump = _jump;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => unawaited(_reveal(target, jump, entries)),
      );
    }
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

  /// Brings the message [target] of [jump] into view: in [entries] if it is there, else in
  /// a timeline opened around it.
  Future<void> _reveal(
    String target,
    ChatJump jump,
    List<TimelineEntry> entries,
  ) async {
    if (!mounted) return;
    final notifier = ref.read(chatJumpProvider(_chat).notifier);
    final index = entries.indexWhere(
      (entry) => eventFields(entry)?.meta.eventId == target,
    );
    if (index < 0) {
      if (jump.around != target) {
        _jumping = null;
        notifier.openAround(target);
      } else if (entries.isEmpty) {
        // The timeline around it is still loading.
        _jumping = null;
      } else {
        notifier.shown();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Can’t show that message here')),
        );
      }
      return;
    }
    await scrollToItem(
      controller: _scroll,
      key: _bubbleKeys.putIfAbsent(entries[index].id, GlobalKey.new),
      index: index,
      builtIndexes: () => [
        for (final (i, entry) in entries.indexed)
          if (_bubbleKeys[entry.id]?.currentContext != null) i,
      ],
      mounted: () => mounted,
    );
    if (!mounted) return;
    notifier.shown();
    _highlightTimer?.cancel();
    if (!jump.keepHighlight) {
      _highlightTimer = Timer(
        const Duration(seconds: 3),
        () => notifier.clearHighlight(jump.serial),
      );
    }
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
    final runStarts = noticeRunStarts(entries);
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: ListView.builder(
        controller: _scroll,
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
          if (entry is NoticeEntry) {
            return SelectionContainer.disabled(
              child: _notice(entry, position, entries, runStarts),
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

  /// A notice's line; in a run of membership notices, the first shows the run folded (and
  /// the rest nothing) until opened.
  Widget _notice(
    NoticeEntry entry,
    int position,
    List<TimelineEntry> entries,
    List<int?> runStarts,
  ) {
    final line = NoticeLine(
      key: _bubbleKeys.putIfAbsent(entry.id, GlobalKey.new),
      text: noticeText(
        entry,
        ownUserId: widget.account,
        missedCalls: ref.watch(
          incomingCallsProvider.select((calls) => calls.missed),
        ),
      ),
    );
    final start = runStarts[position];
    if (start == null) return line;
    final runId = entries[start].id;
    final open = _openRuns.contains(runId);
    if (position != start) return open ? line : const SizedBox.shrink();
    final run = [
      for (var p = start; p < entries.length && runStarts[p] == start; p++)
        entries[p] as NoticeEntry,
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        NoticeRunLine(
          key: Key('notice.run.$runId'),
          summary: noticeRunSummary(run),
          expanded: open,
          onToggle: () => setState(
            () => open ? _openRuns.remove(runId) : _openRuns.add(runId),
          ),
        ),
        if (open) line,
      ],
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
        onMention: (userId, name) => _openProfile(userId, name: name),
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
    final hasActions = canAct && entry is! UndecryptableEntry;
    final touch = isTouchPlatform(context);
    // In the chat, a thread shows under its first message; in the thread, it is all around.
    final thread = widget.thread == null ? meta.thread : null;
    final bubble = MessageBubble(
      key: _bubbleKeys.putIfAbsent(entry.id, GlobalKey.new),
      isOwn: fields.isOwn,
      plain: entry is MessageEntry && isEmojiOnly(entry.body),
      sender: _senderLabel(fields, previous),
      onSender: () => _openProfile(
        fields.sender,
        name: fields.senderName,
        avatarUrl: fields.senderAvatarUrl,
      ),
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
              compact: entry is MessageEntry && isEmojiOnly(entry.body),
              onTap: () => _actions.openThread(entry),
            ),
      // On a touch screen a tap opens the action sheet instead, and the message keeps the
      // whole width: there is no mouse to hover with.
      onTap: hasActions && touch
          ? () => _openSheet(entry, canRedactOthers: canRedactOthers)
          : null,
      hoverActions: hasActions && !touch
          ? _HoverActions(
              tooltipsLeft: fields.isOwn,
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
    return meta.eventId != null && meta.eventId == _jump.highlight
        ? JumpHighlight(child: bubble)
        : bubble;
  }

  /// The touch screen's sheet of what can be done with [entry].
  void _openSheet(TimelineEntry entry, {required bool canRedactOthers}) {
    final actions = _actions;
    unawaited(
      showMessageSheet(
        context,
        account: widget.account,
        entry: entry,
        actions: actions.actions(entry, canRedactOthers: canRedactOthers),
        onReact: (emoji) => unawaited(actions.toggleReaction(entry, emoji)),
      ),
    );
  }

  /// Someone's profile, from their name, picture or a pill.
  void _openProfile(String userId, {String? name, String? avatarUrl}) =>
      unawaited(
        showUserProfile(
          context,
          account: widget.account,
          userId: userId,
          roomId: widget.roomId,
          name: name,
          avatarUrl: avatarUrl,
        ),
      );

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
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _openProfile(
          fields.sender,
          name: fields.senderName,
          avatarUrl: fields.senderAvatarUrl,
        ),
        child: MatrixAvatar(
          key: Key('senderAvatar.$id'),
          account: widget.account,
          url: fields.senderAvatarUrl,
          name: fields.senderName ?? fields.sender,
          seed: fields.sender,
          radius: _senderAvatarRadius,
        ),
      ),
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
      decoration: ShapeDecoration(
        color: context.oxi.panel,
        shape: OxiShapes.cut(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: context.oxi.muted,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
        ),
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
      spacing: 8,
      children: [
        OutlinedButton(
          key: const Key('message.retry'),
          onPressed: onRetry,
          child: const Text('Retry'),
        ),
        OutlinedButton(
          key: const Key('message.remove'),
          style: OxiButtons.destructive(context),
          onPressed: onRemove,
          child: const Text('Remove'),
        ),
      ],
    ),
  );
}

/// The small toolbar beside a message under the mouse: react, reply, reply in a thread (in
/// the chat), and the rest. One narrow column of buttons, so the message keeps its width;
/// tooltips show beside the buttons, away from the message ([tooltipsLeft] for the user's
/// own, where the toolbar is on the message's left).
class _HoverActions extends StatelessWidget {
  const _HoverActions({
    required this.onReact,
    required this.onReply,
    required this.menu,
    this.onThread,
    this.tooltipsLeft = false,
  });

  final VoidCallback onReact;
  final VoidCallback onReply;
  final VoidCallback? onThread;
  final bool tooltipsLeft;

  /// The message menu's items, made when it opens.
  final List<ContextMenuButtonItem> Function() menu;

  /// The toolbar's width, and the room kept for it beside the message.
  static const width = 40.0;

  @override
  Widget build(BuildContext context) => Material(
    color: context.oxi.panel,
    shape: OxiShapes.cut(8, side: BorderSide(color: context.oxi.line)),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
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
    ),
  );

  Widget _toolbarButton(
    Key key,
    String tooltip,
    IconData icon,
    VoidCallback onPressed,
  ) => Tooltip(
    message: tooltip,
    positionDelegate: _besideButton,
    child: IconButton(
      key: key,
      iconSize: 18,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: width, height: 36),
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      icon: Icon(icon, semanticLabel: tooltip),
    ),
  );

  /// Beside the button, vertically centred on it, inside the window.
  Offset _besideButton(TooltipPositionContext context) {
    const gap = 8.0;
    final half = context.targetSize.width / 2 + gap;
    final tooltip = context.tooltipSize;
    final left = tooltipsLeft
        ? context.target.dx - half - tooltip.width
        : context.target.dx + half;
    final top = context.target.dy - tooltip.height / 2;
    return Offset(
      left.clamp(0, math.max(0, context.overlaySize.width - tooltip.width)),
      top.clamp(0, math.max(0, context.overlaySize.height - tooltip.height)),
    );
  }

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
    this.onTap,
    this.onSender,
    super.key,
  });

  final bool isOwn;
  final String? sender;

  /// A tap on [sender]: opens their profile.
  final VoidCallback? onSender;

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

  /// The thread that starts at this message: the bubble's last row, or under big emojis.
  final Widget? thread;

  /// Shown beside the bubble while the mouse is over the message.
  final Widget? hoverActions;

  /// A tap on the message, or its reactions, where nothing in it takes the tap itself
  /// (links, media, reactions, the quote and the thread keep theirs).
  final VoidCallback? onTap;

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  var _hovered = false;

  /// The mouse is over the toolbar, which floats above the chat, off the message.
  var _overToolbar = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.oxi;
    final isOwn = widget.isOwn;
    final color = widget.plain
        ? Colors.transparent
        : isOwn
        ? palette.ownBubble
        : palette.bubble;
    final meta = Theme.of(context).textTheme.bodySmall?.copyWith(
      fontSize: 11,
      color: isOwn && !widget.plain ? palette.ownMeta : palette.muted,
    );
    final sender = widget.sender;
    final thread = widget.thread;
    // Square, but for one cut corner where the tail would be: bottom left for others,
    // bottom right for the user's own.
    final shape = BeveledRectangleBorder(
      borderRadius: isOwn
          ? const BorderRadius.only(bottomRight: Radius.circular(10))
          : const BorderRadius.only(bottomLeft: Radius.circular(10)),
    );
    final strip = isOwn && !widget.plain ? palette.ownStrip : null;
    final inner = switch (thread) {
      // The thread's row is the bubble's last, across its full width; under big emojis
      // it is a small chip of its own.
      final thread? when !widget.plain => BubbleWithFooter(
        content: _content(sender, meta),
        footer: Material(type: MaterialType.transparency, child: thread),
      ),
      final thread? => Column(
        crossAxisAlignment: isOwn
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [_content(sender, meta), thread],
      ),
      null => _content(sender, meta),
    };
    final bubble = ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.75,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: DecoratedBox(
          decoration: ShapeDecoration(color: color, shape: shape),
          child: ClipPath(
            clipper: ShapeBorderClipper(shape: shape),
            clipBehavior: widget.plain ? Clip.none : Clip.antiAlias,
            child: DefaultTextStyle.merge(
              style: TextStyle(color: isOwn ? palette.ownText : palette.text),
              child: strip == null
                  ? inner
                  // A thin yellow strip inside the right edge, in dark.
                  : Container(
                      foregroundDecoration: BoxDecoration(
                        border: Border(
                          right: BorderSide(color: strip, width: 3),
                        ),
                      ),
                      child: inner,
                    ),
            ),
          ),
        ),
      ),
    );
    final reactions = widget.reactions;
    final column = Column(
      crossAxisAlignment: isOwn
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [bubble, ?reactions],
    );
    final onTap = widget.onTap;
    final content = onTap == null
        ? column
        : GestureDetector(
            key: const Key('message.tap'),
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: column,
          );
    final hoverActions = widget.hoverActions;
    // A narrow room kept beside the message, so it doesn't move when the toolbar shows.
    // The toolbar floats above the chat from there, so a short message doesn't grow to
    // its height.
    final toolbar = hoverActions == null
        ? null
        : _ToolbarSlot(
            visible: _hovered || _overToolbar,
            onHover: (over) {
              if (mounted && over != _overToolbar) {
                setState(() => _overToolbar = over);
              }
            },
            child: hoverActions,
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

  /// The sender's name, the quote, the message with its time, and the footer.
  Widget _content(String? sender, TextStyle? meta) {
    final isOwn = widget.isOwn;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (sender != null)
            SelectionContainer.disabled(
              child: MouseRegion(
                cursor: widget.onSender == null
                    ? MouseCursor.defer
                    : SystemMouseCursors.click,
                child: GestureDetector(
                  key: const Key('message.sender'),
                  onTap: widget.onSender,
                  child: Text(
                    sender,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: context.oxi.muted,
                    ),
                  ),
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
                      _SendStateIcon(
                        state: widget.sendState!,
                        color: meta?.color,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          ...widget.footer,
        ],
      ),
    );
  }
}

/// The room beside a message where its toolbar shows: as wide as the toolbar, no height.
/// The toolbar floats in the overlay, its bottom at the message's bottom, moved down or up
/// as needed to stay inside the chat's visible part (never under its header or the
/// message box).
class _ToolbarSlot extends StatefulWidget {
  const _ToolbarSlot({
    required this.visible,
    required this.onHover,
    required this.child,
  });

  final bool visible;
  final ValueChanged<bool> onHover;
  final Widget child;

  @override
  State<_ToolbarSlot> createState() => _ToolbarSlotState();
}

class _ToolbarSlotState extends State<_ToolbarSlot> {
  final _portal = OverlayPortalController();
  ScrollPosition? _scroll;

  @override
  void initState() {
    super.initState();
    if (widget.visible) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Follows the message while the chat scrolls under the mouse.
    final scroll = Scrollable.maybeOf(context)?.position;
    if (scroll != _scroll) {
      _scroll?.removeListener(_moved);
      _scroll = scroll?..addListener(_moved);
    }
  }

  @override
  void didUpdateWidget(_ToolbarSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Not during the build that changed it: right after.
    if (widget.visible != oldWidget.visible) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
    }
  }

  void _sync() {
    if (!mounted || widget.visible == _portal.isShowing) return;
    widget.visible ? _portal.show() : _portal.hide();
  }

  @override
  void dispose() {
    _scroll?.removeListener(_moved);
    super.dispose();
  }

  void _moved() {
    if (!_portal.isShowing) return;
    // A scroll may be corrected during layout, when a rebuild can't be asked for.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  /// The chat's visible part, in this slot's coordinates.
  Rect? _viewportInSlot() {
    final slot = context.findRenderObject();
    final viewport = Scrollable.maybeOf(context)?.context.findRenderObject();
    if (slot is! RenderBox || viewport is! RenderBox || !viewport.hasSize) {
      return null;
    }
    final toViewport = slot.getTransformTo(viewport);
    if (toViewport.invert() == 0) return null;
    return MatrixUtils.transformRect(toViewport, Offset.zero & viewport.size);
  }

  @override
  Widget build(BuildContext context) => OverlayPortal.overlayChildLayoutBuilder(
    controller: _portal,
    overlayChildBuilder: (context, info) {
      final slot = MatrixUtils.transformRect(
        info.childPaintTransform,
        Offset.zero & info.childSize,
      );
      final viewport = switch (_viewportInSlot()) {
        final rect? => MatrixUtils.transformRect(
          info.childPaintTransform,
          rect,
        ),
        null => Offset.zero & info.overlaySize,
      };
      return Positioned.fill(
        child: CustomSingleChildLayout(
          delegate: _ToolbarPosition(slot: slot, bounds: viewport),
          child: MouseRegion(
            onEnter: (_) => widget.onHover(true),
            onExit: (_) => widget.onHover(false),
            child: widget.child,
          ),
        ),
      );
    },
    child: const SizedBox(width: _HoverActions.width),
  );
}

class _ToolbarPosition extends SingleChildLayoutDelegate {
  const _ToolbarPosition({required this.slot, required this.bounds});

  /// Where the slot is: the toolbar's bottom goes to its bottom.
  final Rect slot;

  /// What the toolbar stays inside.
  final Rect bounds;

  static const _margin = 4.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final lowest = bounds.bottom - _margin - childSize.height;
    final highest = bounds.top + _margin;
    final top = math.max(
      highest,
      math.min(slot.bottom - childSize.height, lowest),
    );
    return Offset(slot.center.dx - childSize.width / 2, top);
  }

  @override
  bool shouldRelayout(_ToolbarPosition oldDelegate) =>
      slot != oldDelegate.slot || bounds != oldDelegate.bounds;
}

class _SendStateIcon extends StatelessWidget {
  const _SendStateIcon({required this.state, this.color});

  final SendState state;

  /// The message time's colour.
  final Color? color;

  @override
  Widget build(BuildContext context) => switch (state) {
    SendState.sending => Icon(
      Icons.schedule_rounded,
      size: 14,
      color: color,
      semanticLabel: 'Sending',
    ),
    SendState.sent => Icon(
      Icons.done_rounded,
      size: 14,
      color: color,
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
/// message menu started one (Esc cancels). With [thread], it writes into that thread. While
/// it is empty, the microphone records a voice message, and the camera a video where the
/// platform can.
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
  final _text = ComposerController();
  late final _emoticons = EmoticonFormatter(
    enabled: () => ref.read(replaceEmoticonsProvider),
  );
  final _focus = FocusNode();

  /// Ends the user's typing after a pause.
  Timer? _typingPause;
  var _typing = false;

  /// Where the last notice went; `ref` can't be used once the composer is gone.
  RoomTimeline? _typingIn;

  late final _voice = VoiceDraft(
    recorder: ref.read(voiceRecorderFactoryProvider),
    codec: ref.read(audioCodecProvider),
    playback: ref.read(voicePlaybackProvider),
    send: _sendVoice,
    onError: _showError,
    playKey: 'draft:${widget.roomId}:${widget.thread}',
  );

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

  /// The `@…` or `#…` being typed, for the suggestions; `null` for none.
  MentionQuery? _query;

  /// The suggestion lit for Enter or Tab.
  var _selected = 0;

  /// Esc closed the suggestions; they come back with the next letter.
  var _dismissed = false;

  /// The suggestions shown, as last built.
  var _suggestions = const <MentionSuggestion>[];
  final _popupLink = LayerLink();
  final _popup = OverlayPortalController();

  /// This account's drafts; kept, as `ref` can't be used once the composer is gone.
  late final Drafts _drafts;

  /// Saves the draft a moment after the last change.
  Timer? _draftSave;

  /// The mode as last built, for the draft.
  ComposerMode? _mode;

  /// A reply or edit given back by a draft: its text is the draft's, not the message's.
  ComposerMode? _restoredMode;

  /// Whether the text or mode changed since the composer opened, so leaving saves.
  var _changed = false;

  /// While a draft's text is put back: not the user typing.
  var _restoring = false;

  /// What was last saved, to skip saves when only the cursor moved.
  (String, ComposerMode?)? _saved;

  late final AppLifecycleListener _lifecycle;

  static const _draftDelay = Duration(milliseconds: 500);

  @override
  void initState() {
    super.initState();
    _drafts = ref.read(draftsProvider(widget.account).notifier);
    final live = _drafts.live(widget.roomId, widget.thread);
    if (live != null) {
      _text.setContent(live.text, live.pills);
      _saved = (live.text, live.mode);
      if (live.mode case final mode?) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _restoreMode(mode));
      }
    } else {
      unawaited(_restoreStored());
    }
    _text
      ..addListener(_onText)
      ..addListener(_onQuery)
      ..addListener(_onDraftChange);
    // Leaving the app saves at once: a phone may stop it in the background.
    _lifecycle = AppLifecycleListener(
      onHide: () => _saveDraft(leaving: false),
      onPause: () => _saveDraft(leaving: false),
    );
    _popup.show();
  }

  /// Puts back the draft kept in the account's store, unless the user typed already.
  Future<void> _restoreStored() async {
    final draft = await _drafts.stored(widget.roomId, widget.thread);
    if (draft == null || !mounted || _text.text.isNotEmpty) return;
    final (text, pills) = composerContent(draft.parts);
    _restoring = true;
    _text.setContent(text, pills);
    _restoring = false;
    _saved = (text, null);
    final mode = await _draftMode(draft);
    if (mode != null && mounted) _restoreMode(mode);
  }

  /// The reply or edit of [draft], if its message can still be loaded.
  Future<ComposerMode?> _draftMode(ComposerDraft draft) async {
    final eventId = draft.eventId;
    if (eventId == null || draft.type == DraftType.newMessage) return null;
    try {
      final timeline = await ref.read(
        roomTimelineProvider(
          widget.account,
          widget.roomId,
          thread: widget.thread,
        ).future,
      );
      if (!mounted) return null;
      final reply = draft.type == DraftType.reply;
      final entry = await timeline.draftTarget(eventId, reply: reply);
      if (entry == null) return null;
      return reply ? Replying(entry) : Editing(entry);
    } on MatrixFailure {
      return null;
    }
  }

  void _restoreMode(ComposerMode mode) {
    if (!mounted || ref.read(composerModeProvider(_chat)) != null) return;
    _restoredMode = mode;
    _setMode(mode);
  }

  /// Saves the draft [_draftDelay] after the text or mode last changed.
  void _onDraftChange() {
    if (_restoring) return;
    final now = (_text.text, _mode);
    if (_saved case (final text, final mode)
        when text == now.$1 && identical(mode, now.$2)) {
      return;
    }
    _changed = true;
    _draftSave?.cancel();
    _draftSave = Timer(_draftDelay, () => _saveDraft(leaving: false));
  }

  /// Keeps the draft now; [leaving] also updates the chat list's line.
  void _saveDraft({required bool leaving}) {
    _draftSave?.cancel();
    if (!_changed) return;
    _saved = (_text.text, _mode);
    _drafts.keep(
      widget.roomId,
      widget.thread,
      LiveDraft(text: _text.text, pills: _text.pills, mode: _mode),
      leaving: leaving,
    );
  }

  /// Follows what is typed before the cursor for the suggestions.
  void _onQuery() {
    final query = mentionQueryAt(_text.value);
    if (query == _query) return;
    setState(() {
      if (query?.text != _query?.text || query?.trigger != _query?.trigger) {
        _selected = 0;
        _dismissed = false;
      }
      _query = query;
    });
  }

  /// What the popup offers for [query]: members (and @room) for `@`, rooms for `#`.
  List<MentionSuggestion> _suggestionsFor(MentionQuery? query) {
    if (query == null || _dismissed) return const [];
    if (query.trigger == '#') {
      final session = ref.read(accountsProvider).value?.byId(widget.account);
      return roomSuggestions(query.text, session?.mentionRooms() ?? const []);
    }
    final members =
        ref.watch(roomMembersProvider(widget.account, widget.roomId)).value ??
        const <RoomMember>[];
    final canMentionRoom =
        ref
            .watch(canMentionRoomProvider((widget.account, widget.roomId)))
            .value ??
        false;
    return memberSuggestions(
      query.text,
      members,
      own: widget.account,
      canMentionRoom: canMentionRoom,
    );
  }

  /// Puts [suggestion] as a pill where its `@…` is.
  void _pick(MentionSuggestion suggestion) {
    final query = _query;
    if (query == null) return;
    _text.insertPill(query.start, query.end, suggestion.part);
    _focus.requestFocus();
  }

  void _moveSelection(int by) {
    if (_suggestions.isEmpty) return;
    setState(() => _selected = (_selected + by) % _suggestions.length);
  }

  @override
  void dispose() {
    _saveDraft(leaving: true);
    _lifecycle.dispose();
    _typingPause?.cancel();
    if (_typing) {
      unawaited(_typingIn?.setTyping(false).catchError((Object _) {}));
    }
    _text.dispose();
    _focus.dispose();
    _voice.dispose();
    super.dispose();
  }

  /// Tells the room the user types while there is text and keys are pressed, and stops
  /// after [_typingTimeout] without a change, or when the text is gone.
  void _onText() {
    if (_restoring || !ref.read(sendTypingProvider)) return;
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
    final parts = _text.parts();
    // The emoticon at the very end, which the formatter only replaces after a space.
    if (ref.read(replaceEmoticonsProvider) && parts.lastOrNull is TextPart) {
      final last = parts.removeLast() as TextPart;
      parts.add(TextPart(withTrailingEmoticon(last.text)));
    }
    final mode = ref.read(composerModeProvider(_chat));
    final timeline = _timeline;
    // An empty edit of a caption removes it; empty text sends nothing.
    final editingCaption = mode is Editing && mode.entry is MediaEntry;
    if ((parts.isEmpty && !editingCaption) || timeline == null) return;
    _text.clear();
    _setMode(null);
    _draftSave?.cancel();
    _saved = ('', null);
    _drafts.clear(widget.roomId, widget.thread);
    _focus.requestFocus();
    final markdown = ref.read(useMarkdownProvider);
    try {
      switch (mode) {
        case null:
          await timeline.sendMessage(parts, markdown: markdown);
        case Replying(:final entry):
          await timeline.sendMessage(
            parts,
            replyTo: eventFields(entry)?.meta.eventId,
            markdown: markdown,
          );
        case Editing(:final entry):
          final ref = eventFields(entry)?.meta.ref;
          if (ref != null) {
            await timeline.editMessage(
              ref,
              parts,
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

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  /// The event a voice message or video answers, when the composer is replying.
  String? _replyTo() {
    final mode = ref.read(composerModeProvider(_chat));
    return mode is Replying ? eventFields(mode.entry)?.meta.eventId : null;
  }

  Future<void> _sendVoice(VoiceClip clip) async {
    final timeline = _timeline;
    if (timeline == null) return;
    final replyTo = _replyTo();
    _setMode(null);
    try {
      await timeline.sendVoice(clip, inReplyTo: replyTo);
    } on MatrixFailure catch (failure) {
      _showError('Not sent: ${failure.kind.name}');
    }
  }

  Future<void> _recordVideo() async {
    final video = await recordVideoMessage(context);
    final timeline = _timeline;
    if (video == null || timeline == null) return;
    final replyTo = _replyTo();
    _setMode(null);
    try {
      await timeline.sendVideo(
        video.data,
        filename: video.filename,
        mimeType: video.mimeType,
        duration: video.duration,
        photo: video.photo,
        width: video.width,
        height: video.height,
        inReplyTo: replyTo,
      );
    } on MatrixFailure catch (failure) {
      _showError('Not sent: ${failure.kind.name}');
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
          // The user's recent ones in a line under the picker.
          child: Consumer(
            builder: (context, ref, _) => emojiPicker(
              recent:
                  ref.watch(recentEmojisProvider(widget.account)).value ??
                  const [],
              onSelected: (emoji) => Navigator.of(context).pop(emoji),
            ),
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
    final mode = _mode = ref.watch(composerModeProvider(_chat));
    ref.listen(composerModeProvider(_chat), (previous, next) {
      _mode = next;
      final restored = identical(next, _restoredMode);
      _restoredMode = null;
      if (restored) {
        // The draft's text stays.
      } else if (next is Editing) {
        switch (next.entry) {
          case MessageEntry(:final body, :final formatted):
            final (text, pills) = pillsFromMessage(body, formatted);
            _text.setContent(text, pills);
          case MediaEntry(:final media):
            _text.setContent(media.caption ?? '', const []);
          default:
            _text.setContent(messageText(next.entry), const []);
        }
      } else if (previous is Editing) {
        _text.clear();
      }
      if (next != null) _focus.requestFocus();
      _onDraftChange();
    });
    final palette = context.oxi;
    final suggestions = _suggestions = _suggestionsFor(_query);
    final selected = suggestions.isEmpty
        ? 0
        : _selected.clamp(0, suggestions.length - 1);
    return CompositedTransformTarget(
      link: _popupLink,
      child: OverlayPortal(
        controller: _popup,
        overlayChildBuilder: (context) => suggestions.isEmpty
            ? const SizedBox.shrink()
            : Align(
                alignment: Alignment.topLeft,
                child: CompositedTransformFollower(
                  link: _popupLink,
                  showWhenUnlinked: false,
                  targetAnchor: Alignment.topLeft,
                  followerAnchor: Alignment.bottomLeft,
                  offset: const Offset(8, -4),
                  child: SizedBox(
                    width: math.min(420, MediaQuery.sizeOf(context).width - 16),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 340),
                      child: MentionSuggestionList(
                        account: widget.account,
                        suggestions: suggestions,
                        selected: selected,
                        onPick: _pick,
                      ),
                    ),
                  ),
                ),
              ),
        child: _composer(context, mode, palette, suggestions, selected),
      ),
    );
  }

  Widget _composer(
    BuildContext context,
    ComposerMode? mode,
    OxiPalette palette,
    List<MentionSuggestion> suggestions,
    int selected,
  ) {
    return Material(
      color: palette.panel,
      shape: Border(top: BorderSide(color: palette.line)),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (mode != null)
              _ModeBar(mode: mode, onCancel: () => _setMode(null)),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
              child: ListenableBuilder(
                listenable: Listenable.merge([_voice, _text]),
                builder: (context, _) => Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (_voice.isActive)
                      Expanded(child: VoiceDraftBar(draft: _voice))
                    else ...[
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
                            const SingleActivator(
                              LogicalKeyboardKey.enter,
                            ): () => suggestions.isEmpty
                                ? unawaited(_send())
                                : _pick(suggestions[selected]),
                            if (suggestions.isNotEmpty) ...{
                              const SingleActivator(
                                LogicalKeyboardKey.tab,
                              ): () =>
                                  _pick(suggestions[selected]),
                              const SingleActivator(
                                LogicalKeyboardKey.arrowDown,
                              ): () =>
                                  _moveSelection(1),
                              const SingleActivator(
                                LogicalKeyboardKey.arrowUp,
                              ): () =>
                                  _moveSelection(-1),
                              const SingleActivator(
                                LogicalKeyboardKey.escape,
                              ): () =>
                                  setState(() => _dismissed = true),
                            },
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
                            if (mode != null && suggestions.isEmpty)
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
                              isDense: true,
                              // Quiet while typing, as the mockup: no outline.
                              focusedBorder: const OxiInputBorder(cut: 6),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 11,
                              ),
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
                    ],
                    if (_voice.state
                        case VoiceRecording(locked: true) || VoicePreview())
                      VoiceDraftActions(draft: _voice)
                    else if (_voice.isActive ||
                        (_text.text.trim().isEmpty && mode is! Editing)) ...[
                      if (!_voice.isActive &&
                          ref.watch(videoMessagesSupportedProvider))
                        IconButton(
                          key: const Key('composer.video'),
                          tooltip: 'Record a video message',
                          icon: const Icon(Icons.videocam_outlined),
                          onPressed: () => unawaited(_recordVideo()),
                        ),
                      MicButton(
                        key: const ValueKey('composer.micButton'),
                        draft: _voice,
                      ),
                    ] else
                      IconButton(
                        key: const Key('composer.send'),
                        tooltip: mode is Editing ? 'Save' : 'Send',
                        // Yellow under ink, in both themes.
                        style: IconButton.styleFrom(
                          backgroundColor: OxiBrand.yellow,
                          foregroundColor: OxiBrand.ink,
                          hoverColor: OxiBrand.ink.withValues(alpha: 0.08),
                          shape: OxiShapes.small,
                          fixedSize: const Size(44, 40),
                        ),
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
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  mode is Editing ? 'Editing' : 'Replying to $name',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w700,
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

/// A thread at its first message: how many replies, who wrote the latest and when; opens
/// the thread. Inside the bubble it is the bubble's last row, under a thin line; [compact],
/// it is a small chip under big emojis, which have no bubble.
class ThreadBar extends StatelessWidget {
  const ThreadBar({
    required this.account,
    required this.thread,
    required this.onTap,
    this.compact = false,
    super.key,
  });

  final String account;
  final ThreadSummary thread;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final latest = thread.latest;
    final link = context.oxi.threadLink;
    final muted = theme.textTheme.bodySmall?.copyWith(
      fontSize: 11,
      color: context.oxi.muted,
    );
    final row = Row(
      children: [
        Icon(Icons.forum_outlined, size: 16, color: link),
        const SizedBox(width: 6),
        if (latest != null) ...[
          SizedBox.square(
            dimension: 18,
            child: MatrixAvatar(
              account: account,
              url: latest.senderAvatarUrl,
              name: latest.senderName ?? latest.sender,
              seed: latest.sender,
              radius: 9,
            ),
          ),
          const SizedBox(width: 6),
        ],
        // The one flexible part: narrow bubbles shorten it rather than overflow.
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: replyCountLabel(thread.replyCount),
                  style: TextStyle(
                    color: link,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
                if (latest != null)
                  TextSpan(text: '  ${listTime(latest.time)}', style: muted),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
          ),
        ),
        const SizedBox(width: 4),
        Icon(Icons.chevron_right_rounded, size: 18, color: link),
      ],
    );
    if (compact) {
      return SelectionContainer.disabled(
        child: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Material(
            color: context.oxi.panel2,
            shape: OxiShapes.cut(5),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
                // As wide as it needs, up to the room there is.
                child: IntrinsicWidth(child: row),
              ),
            ),
          ),
        ),
      );
    }
    return SelectionContainer.disabled(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Divider(
            height: 1,
            thickness: 1,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.10),
          ),
          InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
              child: row,
            ),
          ),
        ],
      ),
    );
  }
}
