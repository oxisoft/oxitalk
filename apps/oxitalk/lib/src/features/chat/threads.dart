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
import 'chat_pane.dart';

/// A thread as a page of its own (narrow windows).
class ThreadScreen extends ConsumerWidget {
  const ThreadScreen({
    required this.roomId,
    required this.rootEventId,
    super.key,
  });

  final String roomId;
  final String rootEventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(activeAccountProvider);
    if (account == null) return const SizedBox.shrink();
    return ThreadPane(
      key: ValueKey((account, roomId, rootEventId)),
      account: account,
      roomId: roomId,
      rootEventId: rootEventId,
      showBack: true,
    );
  }
}

/// The room's thread list as a page of its own (narrow windows).
class ThreadListScreen extends ConsumerWidget {
  const ThreadListScreen({required this.roomId, super.key});

  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(activeAccountProvider);
    if (account == null) return const SizedBox.shrink();
    return ThreadListPane(
      key: ValueKey((account, roomId, 'threads')),
      account: account,
      roomId: roomId,
      showBack: true,
    );
  }
}

/// Esc goes back to the chat, unless a dialog is over the pane.
mixin _EscapeToChat<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  String get roomId;

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
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape ||
        !(ModalRoute.of(context)?.isCurrent ?? false)) {
      return false;
    }
    backToChat();
    return true;
  }

  void backToChat() => context.go(Routes.room(roomId));

  /// Back on a page of its own, ✕ beside the chat.
  Widget leading({required bool showBack, required Key key}) => showBack
      ? BackButton(key: key, onPressed: backToChat)
      : IconButton(
          key: key,
          tooltip: 'Close',
          icon: const Icon(Icons.close_rounded),
          onPressed: backToChat,
        );
}

/// A thread: its first message, the replies, and a message box that answers in the thread.
/// Beside the chat on a wide window; Esc, ✕ or Back returns to the chat alone.
class ThreadPane extends ConsumerStatefulWidget {
  const ThreadPane({
    required this.account,
    required this.roomId,
    required this.rootEventId,
    required this.showBack,
    super.key,
  });

  final String account;
  final String roomId;
  final String rootEventId;
  final bool showBack;

  @override
  ConsumerState<ThreadPane> createState() => _ThreadPaneState();
}

class _ThreadPaneState extends ConsumerState<ThreadPane>
    with _EscapeToChat<ThreadPane> {
  @override
  String get roomId => widget.roomId;

  @override
  Widget build(BuildContext context) {
    final room = ref
        .watch(roomsProvider(widget.account))
        .value
        ?.where((room) => room.id == roomId)
        .firstOrNull;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: leading(
          showBack: widget.showBack,
          key: const Key('thread.close'),
        ),
        titleSpacing: 0,
        flexibleSpace: const WindowDragArea(),
        actions: const [WindowButtons.right()],
        title: _Title(title: 'Thread', subtitle: room?.name),
      ),
      body: ColoredBox(
        color: context.isDark
            ? OxiColors.wallpaperDark
            : OxiColors.wallpaperLight,
        child: Column(
          children: [
            Expanded(
              child: TimelineView(
                account: widget.account,
                roomId: roomId,
                thread: widget.rootEventId,
                showSenders: !(room?.isDm ?? false),
              ),
            ),
            Composer(
              account: widget.account,
              roomId: roomId,
              thread: widget.rootEventId,
            ),
          ],
        ),
      ),
    );
  }
}

/// The room's threads, the most recently active first; one opens in the thread pane.
class ThreadListPane extends ConsumerStatefulWidget {
  const ThreadListPane({
    required this.account,
    required this.roomId,
    required this.showBack,
    super.key,
  });

  final String account;
  final String roomId;
  final bool showBack;

  @override
  ConsumerState<ThreadListPane> createState() => _ThreadListPaneState();
}

class _ThreadListPaneState extends ConsumerState<ThreadListPane>
    with _EscapeToChat<ThreadListPane> {
  var _loading = false;
  var _reachedEnd = false;

  @override
  String get roomId => widget.roomId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_loadMore()));
  }

  Future<void> _loadMore() async {
    if (_loading || _reachedEnd) return;
    _loading = true;
    try {
      final list = await ref.read(
        threadListProvider(widget.account, roomId).future,
      );
      final end = await list.loadMore();
      if (mounted) setState(() => _reachedEnd = end);
    } on MatrixFailure {
      // Tried again on the next scroll.
    } finally {
      _loading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final room = ref
        .watch(roomsProvider(widget.account))
        .value
        ?.where((room) => room.id == roomId)
        .firstOrNull;
    final threads = ref.watch(roomThreadsProvider(widget.account, roomId));
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: leading(
          showBack: widget.showBack,
          key: const Key('threads.close'),
        ),
        titleSpacing: 0,
        flexibleSpace: const WindowDragArea(),
        actions: const [WindowButtons.right()],
        title: _Title(title: 'Threads', subtitle: room?.name),
      ),
      body: switch (threads) {
        AsyncData(value: final threads) when threads.isEmpty => Center(
          child: _reachedEnd
              ? const Text(
                  'No threads yet.\nReply in a thread from a message’s menu.',
                  key: Key('threads.empty'),
                  textAlign: TextAlign.center,
                )
              : const CircularProgressIndicator(),
        ),
        AsyncData(value: final threads) => _list(threads),
        AsyncError(:final error) => Center(
          child: Text('Can’t load the threads: $error'),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Widget _list(List<RoomThread> threads) =>
      NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.metrics.extentAfter < 400) unawaited(_loadMore());
          return false;
        },
        child: ListView.separated(
          itemCount: threads.length,
          separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
          itemBuilder: (context, index) => _ThreadTile(
            account: widget.account,
            thread: threads[index],
            onTap: () =>
                context.go(Routes.thread(roomId, threads[index].rootEventId)),
          ),
        ),
      );
}

class _ThreadTile extends StatelessWidget {
  const _ThreadTile({
    required this.account,
    required this.thread,
    required this.onTap,
  });

  final String account;
  final RoomThread thread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final root = thread.root;
    final latest = thread.latest;
    final name = root.senderName ?? root.sender;
    final latestName = latest == null
        ? null
        : latest.senderName ?? latest.sender;
    return ListTile(
      key: Key('threads.thread.${thread.rootEventId}'),
      onTap: onTap,
      leading: MatrixAvatar(
        account: account,
        url: root.senderAvatarUrl,
        name: name,
        seed: root.sender,
        radius: 20,
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
          Text(
            listTime((latest ?? root).time),
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(root.text ?? '', maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(
            [
              replyCountLabel(thread.replyCount),
              if (latest != null) '$latestName: ${latest.text ?? ''}',
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: OxiColors.accent),
          ),
        ],
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(title),
      if (subtitle case final subtitle?)
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall,
        ),
    ],
  );
}
