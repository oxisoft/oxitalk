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
import '../../ui/format.dart';

/// A chat as a page of its own (narrow windows).
class ChatScreen extends StatelessWidget {
  const ChatScreen({required this.roomId, super.key});

  final String roomId;

  @override
  Widget build(BuildContext context) =>
      ChatPane(roomId: roomId, showBack: true);
}

class ChatPane extends ConsumerWidget {
  const ChatPane({required this.roomId, required this.showBack, super.key});

  final String roomId;
  final bool showBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final room = ref
        .watch(roomsProvider)
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
        title: Row(
          children: [
            InitialsAvatar(name: name, seed: roomId, radius: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
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
      body: ColoredBox(
        color: context.isDark
            ? OxiColors.wallpaperDark
            : OxiColors.wallpaperLight,
        child: Column(
          children: [
            Expanded(
              child: TimelineView(
                roomId: roomId,
                showSenders: !(room?.isDm ?? false),
              ),
            ),
            Composer(roomId: roomId),
          ],
        ),
      ),
    );
  }
}

class TimelineView extends ConsumerStatefulWidget {
  const TimelineView({
    required this.roomId,
    required this.showSenders,
    super.key,
  });

  final String roomId;

  /// Names above other people's messages; off in direct chats.
  final bool showSenders;

  @override
  ConsumerState<TimelineView> createState() => _TimelineViewState();
}

class _TimelineViewState extends ConsumerState<TimelineView> {
  var _loadingOlder = false;
  var _reachedStart = false;

  /// Loads older messages when the list is short or scrolled near its top.
  Future<void> _loadOlder() async {
    if (_loadingOlder || _reachedStart) return;
    final timeline = ref.read(roomTimelineProvider(widget.roomId)).value;
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
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final entries = ref.watch(timelineEntriesProvider(widget.roomId));
    return switch (entries) {
      AsyncData(value: final entries) => _list(entries),
      AsyncError(:final error) => Center(
        child: Text('Can’t open this chat: $error'),
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }

  Widget _list(List<TimelineEntry> entries) {
    if (entries.length < 20) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => unawaited(_loadOlder()),
      );
    }
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
          return switch (entry) {
            DayDivider(:final day) => _DayChip(label: dayLabel(day)),
            MessageEntry() => MessageBubble(
              key: ValueKey(entry.id),
              isOwn: entry.isOwn,
              sender: _senderLabel(
                entry.sender,
                entry.senderName,
                entry.isOwn,
                previous,
              ),
              time: entry.time,
              sendState: entry.sendState,
              child: Text(entry.body),
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

  /// The sender's name above the first of their consecutive messages, in group chats.
  String? _senderLabel(
    String sender,
    String? name,
    bool isOwn,
    TimelineEntry? previous,
  ) {
    if (!widget.showSenders || isOwn) return null;
    final sameSender = switch (previous) {
      MessageEntry(sender: final s) ||
      UndecryptableEntry(sender: final s) => s == sender,
      _ => false,
    };
    return sameSender ? null : name ?? sender;
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
    this.sendState,
    super.key,
  });

  final bool isOwn;
  final String? sender;
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
    return Align(
      alignment: isOwn ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
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
                Text(
                  sender,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color:
                        OxiColors.avatars[sender.hashCode.abs() %
                            OxiColors.avatars.length],
                  ),
                ),
              Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.end,
                spacing: 8,
                children: [
                  child,
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(clockTime(time), style: meta),
                      if (isOwn && sendState != null) ...[
                        const SizedBox(width: 3),
                        _SendStateIcon(state: sendState!),
                      ],
                    ],
                  ),
                ],
              ),
            ],
          ),
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

class Composer extends ConsumerStatefulWidget {
  const Composer({required this.roomId, super.key});

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
    final timeline = ref.read(roomTimelineProvider(widget.roomId)).value;
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
