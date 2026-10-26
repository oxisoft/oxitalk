import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../matrix/api/matrix.dart';
import 'emoji.dart';
import 'message_actions.dart';

/// On a touch screen, what a tap on a message opens, as other phone messengers do: a sheet
/// from the bottom with the message, a row of reactions (the user's recent ones first,
/// then the quick ones, and ＋ for every emoji), and what can be done with it. The sheet
/// closes before the chosen action runs.
Future<void> showMessageSheet(
  BuildContext context, {
  required String account,
  required TimelineEntry entry,
  required List<MessageAction> actions,
  required void Function(String emoji) onReact,
}) async {
  unawaited(HapticFeedback.selectionClick());
  final chosen = await showModalBottomSheet<VoidCallback>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => MessageSheet(
      account: account,
      entry: entry,
      actions: actions,
      onReact: onReact,
    ),
  );
  chosen?.call();
}

/// The sheet [showMessageSheet] shows. It pops with the action to run.
class MessageSheet extends ConsumerStatefulWidget {
  const MessageSheet({
    required this.account,
    required this.entry,
    required this.actions,
    required this.onReact,
    super.key,
  });

  final String account;
  final TimelineEntry entry;
  final List<MessageAction> actions;
  final void Function(String emoji) onReact;

  /// How many emojis the row offers before ＋.
  static const reactionCount = 6;

  @override
  ConsumerState<MessageSheet> createState() => _MessageSheetState();
}

class _MessageSheetState extends ConsumerState<MessageSheet> {
  /// The full picker is open under the row.
  var _full = false;

  void _choose(VoidCallback action) => Navigator.of(context).pop(action);

  void _react(String emoji) => _choose(() => widget.onReact(emoji));

  @override
  Widget build(BuildContext context) {
    final fields = eventFields(widget.entry);
    // The row stands for React…; the rest is listed in the menus' order.
    final canReact = widget.actions.any((action) => action.id == 'react');
    final actions = [
      for (final action in widget.actions)
        if (action.id != 'react') action,
    ];
    final recent =
        ref.watch(recentEmojisProvider(widget.account)).value ?? const [];
    final emojis = {
      ...recent,
      ...quickReactions,
    }.take(MessageSheet.reactionCount).toList();
    final mine = {
      for (final reaction in fields?.meta.reactions ?? const <Reaction>[])
        if (reaction.mine) reaction.key,
    };
    return SafeArea(
      top: false,
      child: Column(
        key: const Key('messageSheet'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (fields != null) _Preview(entry: widget.entry, fields: fields),
          if (canReact)
            Padding(
              padding: const EdgeInsets.fromLTRB(13, 8, 13, 4),
              // Shared out evenly, so it fits the narrowest phone.
              child: Row(
                key: const Key('messageSheet.reactions'),
                children: [
                  for (final emoji in emojis)
                    _ReactionButton(
                      key: Key('messageSheet.react.$emoji'),
                      selected: mine.contains(emoji),
                      onTap: () => _react(emoji),
                      child: Text(emoji, style: const TextStyle(fontSize: 26)),
                    ),
                  _ReactionButton(
                    key: const Key('messageSheet.react.more'),
                    tooltip: _full ? 'Fewer emojis' : 'More emojis',
                    onTap: () => setState(() => _full = !_full),
                    child: Icon(
                      _full ? Icons.expand_less_rounded : Icons.add_rounded,
                      size: 26,
                    ),
                  ),
                ],
              ),
            ),
          if (_full) emojiPicker(onSelected: _react),
          if (canReact || fields != null)
            Divider(height: 9, color: context.oxi.line),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final action in actions) _ActionRow(action, _choose),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Who wrote the message and its first lines, at the top of the sheet.
class _Preview extends StatelessWidget {
  const _Preview({required this.entry, required this.fields});

  final TimelineEntry entry;
  final EventFields fields;

  @override
  Widget build(BuildContext context) {
    final palette = context.oxi;
    final text = switch (entry) {
      UndecryptableEntry() => 'Waiting for this message…',
      final entry => messageText(entry),
    };
    return Padding(
      key: const Key('messageSheet.preview'),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
        decoration: BoxDecoration(
          color: palette.quote,
          border: Border(left: BorderSide(color: palette.quoteBar, width: 3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              fields.isOwn ? 'You' : fields.senderName ?? fields.sender,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: palette.muted,
              ),
            ),
            if (text.isNotEmpty)
              Text(
                text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, color: palette.text),
              ),
          ],
        ),
      ),
    );
  }
}

/// One emoji of the sheet's row, or its ＋: an equal share of the row with cut corners,
/// outlined when the user already gave that reaction.
class _ReactionButton extends StatelessWidget {
  const _ReactionButton({
    required this.onTap,
    required this.child,
    this.selected = false,
    this.tooltip,
    super.key,
  });

  final VoidCallback onTap;
  final Widget child;
  final bool selected;
  final String? tooltip;

  static const height = 46.0;

  @override
  Widget build(BuildContext context) {
    final palette = context.oxi;
    final button = Material(
      color: selected ? palette.reaction : palette.panel2,
      shape: OxiShapes.cut(
        8,
        side: selected
            ? BorderSide(color: palette.quoteBar, width: 1.5)
            : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: height,
          child: Center(child: FittedBox(child: child)),
        ),
      ),
    );
    final tooltip = this.tooltip;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: tooltip == null
            ? button
            : Tooltip(message: tooltip, child: button),
      ),
    );
  }
}

/// One action of the sheet: its icon and label, in red when it removes something.
class _ActionRow extends StatelessWidget {
  const _ActionRow(this.action, this.choose);

  final MessageAction action;
  final void Function(VoidCallback action) choose;

  @override
  Widget build(BuildContext context) {
    final color = action.destructive
        ? OxiButtons.danger(Theme.of(context).brightness)
        : context.oxi.text;
    return ListTile(
      key: Key('messageSheet.${action.id}'),
      leading: Icon(action.icon, color: color),
      title: Text(
        action.label,
        style: TextStyle(
          color: color,
          fontWeight: action.destructive ? FontWeight.w700 : FontWeight.w600,
        ),
      ),
      shape: OxiShapes.small,
      visualDensity: VisualDensity.standard,
      onTap: () => choose(action.run),
    );
  }
}
