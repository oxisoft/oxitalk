import 'dart:async';

// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../matrix/api/matrix.dart';
import '../../ui/format.dart';
import 'jump.dart';
import 'message_actions.dart';

/// The day of the topmost message in view of each open chat; `null` while there is none.
final chatTopDayProvider = NotifierProvider.autoDispose
    .family<ChatTopDay, DateTime?, ChatKey>(ChatTopDay.new);

final class ChatTopDay extends Notifier<DateTime?> {
  ChatTopDay(this.chat);

  final ChatKey chat;

  @override
  DateTime? build() => null;

  /// The day (any time in it) of the topmost message in view.
  void set(DateTime? time) {
    final day = time == null ? null : dayOf(time);
    if (day != state) state = day;
  }
}

/// Midnight (local time) of [time]'s day.
DateTime dayOf(DateTime time) => DateTime(time.year, time.month, time.day);

/// When [entry] happened, for a message or a notice; `null` for a day divider.
DateTime? entryTime(TimelineEntry entry) => switch (entry) {
  NoticeEntry(:final time) => time,
  DayDivider() => null,
  _ => eventFields(entry)?.time,
};

/// What the loaded messages tell about the first message of a day.
sealed class LoadedDayStart {
  const LoadedDayStart();
}

/// The day's first message (or, without one that day, the next day's) is loaded.
final class LoadedFound extends LoadedDayStart {
  const LoadedFound(this.eventId, this.time);

  final String eventId;
  final DateTime time;
}

/// All messages since the day are loaded, and there are none.
final class LoadedNoneAfter extends LoadedDayStart {
  const LoadedNoneAfter();
}

/// The loaded messages start after the day began: the first ones may not be loaded.
final class NotLoaded extends LoadedDayStart {
  const NotLoaded();
}

/// Looks for the first message at or after [start] in [entries] (oldest first). They tell
/// for sure only if they reach back before [start] (or [reachedStart], the room's first
/// message is among them); that there is none after [start] only if they also reach the
/// newest message ([reachedEnd]).
LoadedDayStart loadedDayStart(
  List<TimelineEntry> entries,
  DateTime start, {
  required bool reachedStart,
  required bool reachedEnd,
}) {
  final messages = [
    for (final entry in entries)
      if (eventFields(entry) case final fields?
          when fields.meta.eventId != null)
        (fields.meta.eventId!, fields.time),
  ];
  final covered =
      reachedStart ||
      (messages.isNotEmpty && messages.first.$2.isBefore(start));
  if (!covered) return const NotLoaded();
  for (final (eventId, time) in messages) {
    if (!time.isBefore(start)) return LoadedFound(eventId, time);
  }
  return reachedEnd ? const LoadedNoneAfter() : const NotLoaded();
}

/// The narrow row under the chat's header with the day of the topmost message in view; a
/// click opens a calendar to go to another day. Hidden while no message is in view.
class ChatDateRow extends ConsumerWidget {
  const ChatDateRow({required this.account, required this.roomId, super.key});

  final String account;
  final String roomId;

  static const height = 26.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final day = ref.watch(chatTopDayProvider((account, roomId)));
    if (day == null) return const SizedBox.shrink();
    final muted = context.oxi.muted;
    return Material(
      color: context.oxi.panel,
      child: Tooltip(
        message: 'Jump to a date',
        waitDuration: const Duration(milliseconds: 600),
        child: InkWell(
          key: const Key('chat.dateRow'),
          onTap: () => unawaited(_pick(context, ref, day)),
          child: Container(
            height: height,
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: context.oxi.line)),
            ),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.calendar_today_outlined, size: 13, color: muted),
                const SizedBox(width: 6),
                Text(
                  dayLabel(day),
                  key: const Key('chat.dateRow.label'),
                  style: TextStyle(
                    color: muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pick(BuildContext context, WidgetRef ref, DateTime day) async {
    final session = ref.read(accountsProvider).value?.byId(account);
    DateTime? created;
    try {
      created = await session?.roomCreatedAt(roomId);
    } on MatrixFailure {
      // The calendar starts at the earliest day then.
    }
    if (!context.mounted) return;
    final today = dayOf(DateTime.now());
    final first = dayOf(created ?? earliestDay);
    final picked = await showDialog<DateTime>(
      context: context,
      builder: (_) => JumpToDateDialog(
        initial: day,
        first: first.isAfter(day) ? day : first,
        last: today.isBefore(day) ? day : today,
      ),
    );
    if (picked != null) {
      ref.read(chatJumpProvider((account, roomId)).notifier).toDay(picked);
    }
  }

  /// The calendar's first day when the room's creation isn't known: Matrix began in 2014.
  static final earliestDay = DateTime(2014);
}

/// A small calendar to pick a day of the chat: picking only selects it, [Scroll to date]
/// goes there (the dialog returns the day), Cancel doesn't.
class JumpToDateDialog extends StatefulWidget {
  const JumpToDateDialog({
    required this.initial,
    required this.first,
    required this.last,
    super.key,
  });

  final DateTime initial;
  final DateTime first;
  final DateTime last;

  @override
  State<JumpToDateDialog> createState() => _JumpToDateDialogState();
}

class _JumpToDateDialogState extends State<JumpToDateDialog> {
  late DateTime _picked = widget.initial;

  @override
  Widget build(BuildContext context) => Dialog(
    key: const Key('dateJump.dialog'),
    insetPadding: const EdgeInsets.all(24),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 340),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 16, 8, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Jump to date',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            Theme(
              data: calendarTheme(context),
              child: CalendarDatePicker(
                key: const Key('dateJump.calendar'),
                initialDate: widget.initial,
                firstDate: widget.first,
                lastDate: widget.last,
                onDateChanged: (day) => setState(() => _picked = day),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: OverflowBar(
                alignment: MainAxisAlignment.end,
                spacing: 8,
                overflowSpacing: 8,
                overflowAlignment: OverflowBarAlignment.end,
                children: [
                  OutlinedButton(
                    key: const Key('dateJump.cancel'),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    key: const Key('dateJump.go'),
                    onPressed: () => Navigator.of(context).pop(_picked),
                    child: const Text('Scroll to date'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// The calendar in OxiTalk's colours: flat, bevelled days, the picked one yellow under
/// ink (in light and dark), today only outlined.
ThemeData calendarTheme(BuildContext context) {
  final theme = Theme.of(context);
  final oxi = context.oxi;
  final cut = WidgetStatePropertyAll<OutlinedBorder>(OxiShapes.cut(6));
  final fill = WidgetStateProperty.resolveWith<Color?>(
    (states) => states.contains(WidgetState.selected) ? OxiBrand.yellow : null,
  );
  final text = WidgetStateProperty.resolveWith<Color?>((states) {
    if (states.contains(WidgetState.selected)) return OxiBrand.ink;
    if (states.contains(WidgetState.disabled)) {
      return oxi.muted.withValues(alpha: 0.45);
    }
    return oxi.text;
  });
  final overlay = WidgetStateProperty.resolveWith<Color?>(
    (states) =>
        states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.focused) ||
            states.contains(WidgetState.pressed)
        ? OxiBrand.yellow.withValues(alpha: 0.16)
        : null,
  );
  return theme.copyWith(
    datePickerTheme: theme.datePickerTheme.copyWith(
      backgroundColor: oxi.panel,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      dayShape: cut,
      dayBackgroundColor: fill,
      dayForegroundColor: text,
      dayOverlayColor: overlay,
      todayBackgroundColor: fill,
      todayForegroundColor: text,
      todayBorder: BorderSide(color: oxi.muted),
      yearShape: cut,
      yearBackgroundColor: fill,
      yearForegroundColor: text,
      yearOverlayColor: overlay,
      weekdayStyle: TextStyle(color: oxi.muted, fontWeight: FontWeight.w700),
    ),
  );
}
