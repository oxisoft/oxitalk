import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    show NotifierProvider, Notifier, ProviderListenableSelect;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../matrix/api/matrix.dart';

part 'jump.g.dart';

/// Account and room ID.
typedef ChatKey = (String, String);

/// Where a chat's timeline should go: a message to bring into view, the message drawn
/// highlighted, and whether the timeline shows the room around an older message instead of
/// its newest end (as Element X does for a pin or a search hit that isn't loaded).
@immutable
final class ChatJump {
  const ChatJump({
    this.target,
    this.around,
    this.highlight,
    this.keepHighlight = false,
    this.serial = 0,
  });

  /// The event to bring into view; `null` once it is shown.
  final String? target;

  /// With an event ID, the timeline is the one opened around that event.
  final String? around;

  /// The event whose message is drawn highlighted.
  final String? highlight;

  /// Whether the highlight stays (a search hit) rather than fading after a moment (a pin).
  final bool keepHighlight;

  /// Counts the requests, so a second jump to the same message still scrolls.
  final int serial;
}

/// Where each open chat's timeline should go. Kept while the app runs, so a jump asked for
/// from another screen (the chat's info) waits for the chat to show.
final chatJumpProvider =
    NotifierProvider.family<ChatJumpNotifier, ChatJump, ChatKey>(
      ChatJumpNotifier.new,
    );

final class ChatJumpNotifier extends Notifier<ChatJump> {
  ChatJumpNotifier(this.chat);

  final ChatKey chat;

  @override
  ChatJump build() => const ChatJump();

  /// Brings the message [eventId] into view and highlights it, for a moment or with
  /// [keepHighlight] until another jump; from the loaded messages, or else around it.
  void show(String eventId, {bool keepHighlight = false}) => state = ChatJump(
    target: eventId,
    around: state.around,
    highlight: eventId,
    keepHighlight: keepHighlight,
    serial: state.serial + 1,
  );

  /// Shows the room around [eventId], to bring that message into view.
  void openAround(String eventId) => state = ChatJump(
    target: state.target,
    around: eventId,
    highlight: state.highlight,
    keepHighlight: state.keepHighlight,
    serial: state.serial,
  );

  /// The target message is in view (or can't be shown).
  void shown() => state = ChatJump(
    around: state.around,
    highlight: state.highlight,
    keepHighlight: state.keepHighlight,
    serial: state.serial,
  );

  /// Takes the highlight away; with [serial], only if it is still that jump's.
  void clearHighlight([int? serial]) {
    if ((serial != null && state.serial != serial) || state.highlight == null) {
      return;
    }
    state = ChatJump(
      target: state.target,
      around: state.around,
      serial: state.serial,
    );
  }

  /// Back to the newest messages, with nothing highlighted.
  void toLatest() => state = ChatJump(serial: state.serial + 1);
}

MatrixSession? _session(Ref ref, String account) => ref.watch(
  accountsProvider.select((accounts) => accounts.value?.byId(account)),
);

/// A room's timeline around the message [eventId]; closed when no longer shown.
@riverpod
Future<RoomTimeline> timelineAt(
  Ref ref,
  String account,
  String roomId,
  String eventId,
) async {
  final session = _session(ref, account);
  if (session == null) throw const MatrixFailure(FailureKind.sessionExpired);
  RoomTimeline? timeline;
  var disposed = false;
  ref.onDispose(() {
    disposed = true;
    timeline?.close();
  });
  timeline = await session.openTimelineAt(roomId, eventId);
  if (disposed) timeline.close();
  return timeline;
}

/// As [timelineEntries], for [timelineAt].
@riverpod
Stream<List<TimelineEntry>> timelineAtEntries(
  Ref ref,
  String account,
  String roomId,
  String eventId,
) => switch (ref.watch(timelineAtProvider(account, roomId, eventId))) {
  AsyncData(:final value) => value.entries,
  AsyncError(:final error, :final stackTrace) => Stream.error(
    error,
    stackTrace,
  ),
  _ => const Stream.empty(),
};

/// Scrolls the list of [controller] until the widget of [key] is built, then brings it to
/// the middle. The list is reversed (newest at the bottom); [index] is the item's position
/// in the list's entries, oldest first, and [builtIndexes] tells which are built now.
/// Returns whether it got there.
Future<bool> scrollToItem({
  required ScrollController controller,
  required GlobalKey key,
  required int index,
  required Iterable<int> Function() builtIndexes,
  required bool Function() mounted,
}) async {
  for (var step = 0; step < 200; step++) {
    if (!mounted() || !controller.hasClients) return false;
    final context = key.currentContext;
    if (context != null && context.mounted) {
      await Scrollable.ensureVisible(
        context,
        alignment: 0.5,
        duration: const Duration(milliseconds: 250),
      );
      return true;
    }
    final built = builtIndexes().toList();
    final position = controller.position;
    if (built.isEmpty) {
      await SchedulerBinding.instance.endOfFrame;
      continue;
    }
    // Reversed: an older item (a lower index) is further up, at a larger offset.
    final older = index < built.reduce((a, b) => a < b ? a : b);
    final distance = position.viewportDimension * 0.8;
    final to = (position.pixels + (older ? distance : -distance)).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (to == position.pixels) {
      // At an end: wait for older messages to load, if they do.
      await SchedulerBinding.instance.endOfFrame;
      if (step > 20 && built.isNotEmpty) return false;
      continue;
    }
    controller.jumpTo(to);
    await SchedulerBinding.instance.endOfFrame;
  }
  return false;
}

/// The message a jump went to, drawn with an accent outline and tint.
class JumpHighlight extends StatelessWidget {
  const JumpHighlight({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    key: const Key('message.highlight'),
    decoration: ShapeDecoration(
      color: OxiBrand.yellow.withValues(alpha: 0.18),
      shape: OxiShapes.cut(
        10,
        side: BorderSide(
          color: Theme.of(context).colorScheme.primary,
          width: 2,
        ),
      ),
    ),
    child: Padding(padding: const EdgeInsets.all(2), child: child),
  );
}

/// Over the timeline while it shows older messages: back to the newest ones.
class JumpToLatestButton extends StatelessWidget {
  const JumpToLatestButton({required this.onPressed, super.key});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => FloatingActionButton.small(
    key: const Key('chat.toLatest'),
    heroTag: null,
    tooltip: 'Jump to the latest messages',
    // Quiet: yellow is for sending and starting chats.
    backgroundColor: context.oxi.panel,
    foregroundColor: context.oxi.text,
    shape: OxiShapes.cut(8, side: BorderSide(color: context.oxi.line)),
    onPressed: onPressed,
    child: const Icon(Icons.keyboard_double_arrow_down_rounded),
  );
}
