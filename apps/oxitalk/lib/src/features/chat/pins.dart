import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
import '../../matrix/api/matrix.dart';
import '../../ui/avatar.dart';
import '../../ui/format.dart';
import 'jump.dart';
import 'message_actions.dart';

part 'pins.g.dart';

MatrixSession? _session(Ref ref, String account) => ref.watch(
  accountsProvider.select((accounts) => accounts.value?.byId(account)),
);

/// The room's pins and pinning; closed when no longer used.
@riverpod
Future<PinnedEvents> pinnedEvents(
  Ref ref,
  String account,
  String roomId,
) async {
  final session = _session(ref, account);
  if (session == null) throw const MatrixFailure(FailureKind.sessionExpired);
  PinnedEvents? pins;
  var disposed = false;
  ref.onDispose(() {
    disposed = true;
    pins?.close();
  });
  pins = await session.openPins(roomId);
  if (disposed) pins.close();
  return pins;
}

/// Which messages of the room are pinned, and whether the user may pin.
@riverpod
Stream<RoomPins> roomPins(Ref ref, String account, String roomId) =>
    switch (ref.watch(pinnedEventsProvider(account, roomId))) {
      AsyncData(:final value) => value.pins,
      AsyncError(:final error, :final stackTrace) => Stream.error(
        error,
        stackTrace,
      ),
      _ => const Stream.empty(),
    };

/// The timeline of the room's pinned messages; closed when no longer shown.
@riverpod
Future<RoomTimeline> pinnedTimeline(
  Ref ref,
  String account,
  String roomId,
) async {
  final session = _session(ref, account);
  if (session == null) throw const MatrixFailure(FailureKind.sessionExpired);
  RoomTimeline? timeline;
  var disposed = false;
  ref.onDispose(() {
    disposed = true;
    timeline?.close();
  });
  timeline = await session.openPinnedTimeline(roomId);
  if (disposed) timeline.close();
  return timeline;
}

@riverpod
Stream<List<TimelineEntry>> pinnedEntries(
  Ref ref,
  String account,
  String roomId,
) => switch (ref.watch(pinnedTimelineProvider(account, roomId))) {
  AsyncData(:final value) => value.entries,
  AsyncError(:final error, :final stackTrace) => Stream.error(
    error,
    stackTrace,
  ),
  _ => const Stream.empty(),
};

/// A pinned message: its event ID, and its entry once loaded.
typedef PinnedMessage = ({String eventId, TimelineEntry? entry});

/// The room's pinned messages, the last pinned first. The timeline of pinned messages is
/// only opened while there are pins.
@riverpod
List<PinnedMessage> pinnedMessages(Ref ref, String account, String roomId) {
  final ids = ref.watch(roomPinsProvider(account, roomId)).value?.eventIds;
  if (ids == null || ids.isEmpty) return const [];
  final entries =
      ref.watch(pinnedEntriesProvider(account, roomId)).value ??
      const <TimelineEntry>[];
  final byId = {
    for (final entry in entries) ?eventFields(entry)?.meta.eventId: entry,
  };
  return [for (final id in ids.reversed) (eventId: id, entry: byId[id])];
}

/// Whether the user may pin in the room; `false` until known.
bool canPin(WidgetRef ref, String account, String roomId) =>
    ref.read(roomPinsProvider(account, roomId)).value?.canPin ?? false;

/// Whether the message [eventId] is pinned.
bool isPinned(WidgetRef ref, String account, String roomId, String eventId) =>
    ref
        .read(roomPinsProvider(account, roomId))
        .value
        ?.eventIds
        .contains(eventId) ??
    false;

/// Pins or unpins the message [eventId]; a failure shows as a snack bar.
Future<void> setPinned(
  BuildContext context,
  WidgetRef ref, {
  required String account,
  required String roomId,
  required String eventId,
  required bool pinned,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final pins = await ref.read(pinnedEventsProvider(account, roomId).future);
    pinned ? await pins.pin(eventId) : await pins.unpin(eventId);
  } on MatrixFailure catch (failure) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '${pinned ? 'Can’t pin' : 'Can’t unpin'}: ${failure.kind.name}',
        ),
      ),
    );
  }
}

/// A line of text for a pinned message: its text, or a file's caption or name.
String pinPreview(TimelineEntry? entry) => switch (entry) {
  null => 'Loading…',
  MessageEntry(:final body) => body,
  MediaEntry(:final media) => media.caption ?? media.filename,
  UndecryptableEntry() => 'Waiting for this message…',
  RedactedEntry() => 'Message deleted',
  DayDivider() => '',
};

IconData? _mediaIcon(TimelineEntry? entry) => switch (entry) {
  MediaEntry(:final media) => switch (media.kind) {
    MediaKind.image => Icons.image_outlined,
    MediaKind.video => Icons.videocam_outlined,
    MediaKind.audio => Icons.audiotrack_outlined,
    MediaKind.file => Icons.insert_drive_file_outlined,
  },
  _ => null,
};

/// Above the chat while it has pins, as in Element X: the pin the banner is at; a tap
/// shows that message and moves the banner to the pin before it. The list button opens all.
class PinnedBanner extends ConsumerStatefulWidget {
  const PinnedBanner({required this.account, required this.roomId, super.key});

  final String account;
  final String roomId;

  @override
  ConsumerState<PinnedBanner> createState() => _PinnedBannerState();
}

class _PinnedBannerState extends ConsumerState<PinnedBanner> {
  /// Which pin shows, counted from the last pinned.
  var _index = 0;

  /// The pins when [_index] was set; a pin added or taken away starts over at the last.
  int? _count;

  @override
  Widget build(BuildContext context) {
    final pins = ref.watch(
      pinnedMessagesProvider(widget.account, widget.roomId),
    );
    if (pins.isEmpty) return const SizedBox.shrink();
    if (_count != pins.length) {
      _count = pins.length;
      _index = 0;
    }
    final index = _index % pins.length;
    final pin = pins[index];
    final theme = Theme.of(context);
    final icon = _mediaIcon(pin.entry);
    return Material(
      key: const Key('pins.banner'),
      color: theme.colorScheme.surfaceContainerLow,
      child: InkWell(
        onTap: () {
          ref
              .read(chatJumpProvider((widget.account, widget.roomId)).notifier)
              .show(pin.eventId);
          setState(() => _index = (index + 1) % pins.length);
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
          child: Row(
            children: [
              _PinIndicator(count: pins.length, index: index),
              const SizedBox(width: 10),
              const Icon(
                Icons.push_pin_outlined,
                size: 18,
                color: OxiColors.accent,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      pins.length == 1
                          ? 'Pinned message'
                          : 'Pinned message ${index + 1} of ${pins.length}',
                      key: const Key('pins.banner.label'),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: OxiColors.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Row(
                      children: [
                        if (icon != null) ...[
                          Icon(icon, size: 16),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Text(
                            pinPreview(pin.entry),
                            key: const Key('pins.banner.text'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                key: const Key('pins.viewAll'),
                tooltip: 'All pinned messages',
                icon: const Icon(Icons.format_list_bulleted_rounded),
                onPressed: () => unawaited(
                  showPinnedMessages(
                    context,
                    account: widget.account,
                    roomId: widget.roomId,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A bar per pin, the shown one highlighted, like Element X's (up to five shown).
class _PinIndicator extends StatelessWidget {
  const _PinIndicator({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    if (count < 2) return const SizedBox(width: 3, height: 32);
    final shown = count.clamp(1, 5);
    // The window of bars that contains the current pin.
    final first = (index ~/ shown) * shown;
    return SizedBox(
      width: 3,
      height: 32,
      child: Column(
        children: [
          for (var i = 0; i < shown; i++) ...[
            if (i > 0) const SizedBox(height: 2),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: first + i == index
                      ? OxiColors.accent
                      : OxiColors.accent.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Opens the list of all the room's pinned messages. With [openChat] (from the chat's
/// info), a tap on one opens the chat to show it.
Future<void> showPinnedMessages(
  BuildContext context, {
  required String account,
  required String roomId,
  bool openChat = false,
}) => showDialog<void>(
  context: context,
  builder: (_) => PinnedMessagesDialog(
    account: account,
    roomId: roomId,
    openChat: openChat,
  ),
);

/// Every pinned message, the last pinned first: sender, text or file, time. A tap shows it
/// in the chat; Unpin when the user may.
class PinnedMessagesDialog extends ConsumerWidget {
  const PinnedMessagesDialog({
    required this.account,
    required this.roomId,
    this.openChat = false,
    super.key,
  });

  final String account;
  final String roomId;
  final bool openChat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pins = ref.watch(pinnedMessagesProvider(account, roomId));
    final mayPin =
        ref.watch(roomPinsProvider(account, roomId)).value?.canPin ?? false;
    return AlertDialog(
      key: const Key('pins.list'),
      title: Text(
        pins.isEmpty ? 'Pinned messages' : 'Pinned messages (${pins.length})',
      ),
      contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
      content: SizedBox(
        width: 440,
        height: 480,
        child: pins.isEmpty
            ? const Center(child: Text('No pinned messages'))
            : ListView(
                children: [
                  for (final pin in pins)
                    _PinnedTile(
                      account: account,
                      roomId: roomId,
                      pin: pin,
                      mayUnpin: mayPin,
                      openChat: openChat,
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _PinnedTile extends ConsumerWidget {
  const _PinnedTile({
    required this.account,
    required this.roomId,
    required this.pin,
    required this.mayUnpin,
    required this.openChat,
  });

  final String account;
  final String roomId;
  final PinnedMessage pin;
  final bool mayUnpin;
  final bool openChat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entry = pin.entry;
    final fields = entry == null ? null : eventFields(entry);
    final name = fields?.senderName ?? fields?.sender;
    final icon = _mediaIcon(entry);
    return ListTile(
      key: Key('pins.item.${pin.eventId}'),
      leading: fields == null
          ? const CircleAvatar(radius: 18, child: Icon(Icons.push_pin_outlined))
          : MatrixAvatar(
              account: account,
              url: fields.senderAvatarUrl,
              name: name ?? '',
              seed: fields.sender,
              radius: 18,
            ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              name ?? '…',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          if (fields != null)
            Text(
              listTime(fields.time),
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
      subtitle: Row(
        children: [
          if (icon != null) ...[Icon(icon, size: 16), const SizedBox(width: 4)],
          Expanded(
            child: Text(
              pinPreview(entry),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      trailing: mayUnpin
          ? IconButton(
              key: Key('pins.unpin.${pin.eventId}'),
              tooltip: 'Unpin',
              icon: const Icon(Icons.push_pin_rounded),
              onPressed: () => unawaited(
                setPinned(
                  context,
                  ref,
                  account: account,
                  roomId: roomId,
                  eventId: pin.eventId,
                  pinned: false,
                ),
              ),
            )
          : null,
      onTap: () {
        final router = GoRouter.of(context);
        Navigator.of(context).pop();
        if (openChat) router.go(Routes.room(roomId));
        ref
            .read(chatJumpProvider((account, roomId)).notifier)
            .show(pin.eventId);
      },
    );
  }
}

/// In the chat's info: how many messages are pinned; opens the list.
class PinnedMessagesRow extends ConsumerWidget {
  const PinnedMessagesRow({
    required this.account,
    required this.roomId,
    super.key,
  });

  final String account;
  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count =
        ref.watch(roomPinsProvider(account, roomId)).value?.eventIds.length ??
        0;
    return ListTile(
      key: const Key('info.pins'),
      leading: const Icon(Icons.push_pin_outlined),
      title: const Text('Pinned messages'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$count', style: Theme.of(context).textTheme.bodyLarge),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
      onTap: () => unawaited(
        showPinnedMessages(
          context,
          account: account,
          roomId: roomId,
          openChat: true,
        ),
      ),
    );
  }
}
