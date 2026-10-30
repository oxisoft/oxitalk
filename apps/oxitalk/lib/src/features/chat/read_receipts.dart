/// Who has read what in a chat: Telegram's ticks with one other member, Element's row of
/// readers' pictures in a group.
library;

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../matrix/api/models.dart';
import '../../ui/avatar.dart';
import '../../ui/format.dart';

/// The position in [entries] of the newest message someone else has read up to: every
/// message at or before it is read. `null` while no one has read any. With one other
/// member this is where the other person has read to.
int? readUpTo(List<TimelineEntry> entries) {
  for (var i = entries.length - 1; i >= 0; i--) {
    if (entryMeta(entries[i])?.readBy.isNotEmpty ?? false) return i;
  }
  return null;
}

/// The pictures of the members who have read up to a message, as Element shows them under
/// it: small, overlapping, the newest reader first, at most [max] and then `+N`. A tap lists
/// them all with when they read it.
class ReadAvatars extends StatelessWidget {
  const ReadAvatars({
    required this.account,
    required this.readers,
    this.max = 10,
    super.key,
  });

  final String account;

  /// Newest first; not empty.
  final List<ReadReceipt> readers;
  final int max;

  /// Half an avatar's side: 14 px pictures.
  static const radius = 7.0;

  /// How much of each picture the next one leaves showing.
  static const step = 10.0;

  @override
  Widget build(BuildContext context) {
    final shown = readers.take(max).toList();
    final more = readers.length - shown.length;
    final palette = context.oxi;
    final names = readers.map((r) => r.name).join(', ');
    // The hint names the first three, one per line; a tap lists everyone.
    final rest = readers.length - 3;
    final hint = [
      'Read by',
      for (final reader in readers.take(3)) reader.name,
      if (rest > 0) 'and $rest more',
    ].join('\n');
    return SelectionContainer.disabled(
      child: Tooltip(
        message: hint,
        child: Semantics(
          button: true,
          label: 'Read by $names',
          // A small tag in the chat's colour across the bubble's bottom edge.
          child: Material(
            color: palette.wallpaper,
            shape: OxiShapes.cut(4),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: const Key('message.readers'),
              onTap: () =>
                  showReaders(context, account: account, readers: readers),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: step * (shown.length - 1) + radius * 2,
                      height: radius * 2,
                      child: Stack(
                        children: [
                          // The newest reader in front, at the right.
                          for (final (i, reader)
                              in shown.indexed.toList().reversed)
                            PositionedDirectional(
                              end: step * i,
                              child: DecoratedBox(
                                key: Key('message.reader.${reader.userId}'),
                                decoration: ShapeDecoration(
                                  shape: avatarShape(radius + 1),
                                  color: palette.wallpaper,
                                ),
                                child: MatrixAvatar(
                                  account: account,
                                  url: reader.avatarUrl,
                                  name: reader.name,
                                  seed: reader.userId,
                                  radius: radius,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (more > 0) ...[
                      const SizedBox(width: 3),
                      Text(
                        '+$more',
                        key: const Key('message.readers.more'),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: palette.muted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Lists everyone who has read up to a message: picture, name, and when.
Future<void> showReaders(
  BuildContext context, {
  required String account,
  required List<ReadReceipt> readers,
}) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    key: const Key('readers.list'),
    title: Text(
      readers.length == 1 ? 'Read by 1 person' : 'Read by ${readers.length}',
    ),
    contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
    content: SizedBox(
      width: 360,
      height: (readers.length * 56.0).clamp(56, 420),
      child: ListView(
        children: [
          for (final reader in readers)
            ListTile(
              key: Key('readers.${reader.userId}'),
              leading: MatrixAvatar(
                account: account,
                url: reader.avatarUrl,
                name: reader.name,
                seed: reader.userId,
                radius: 18,
              ),
              title: Text(
                reader.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: reader.displayName == null
                  ? null
                  : Text(
                      reader.userId,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
              trailing: switch (reader.time) {
                final time? => Text(
                  readTime(time),
                  style: TextStyle(color: context.oxi.muted, fontSize: 12),
                ),
                null => null,
              },
            ),
        ],
      ),
    ),
    actions: [
      OutlinedButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Close'),
      ),
    ],
  ),
);

/// When someone read a message: the time today, else the day and the time.
String readTime(DateTime time, {DateTime? now}) {
  final day = listTime(time, now: now);
  final clock = clockTime(time);
  return day == clock ? clock : '$day $clock';
}
