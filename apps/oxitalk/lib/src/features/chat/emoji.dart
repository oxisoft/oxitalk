import 'dart:async';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';

/// The reactions offered first, as Element offers them.
const quickReactions = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

final _pictographic = RegExp(
  // The analyzer checks patterns without Unicode mode, where `\p{…}` is invalid.
  // ignore: valid_regexps
  r'^(?:\p{Extended_Pictographic}|[\u{1F1E6}-\u{1F1FF}\u{1F3FB}-\u{1F3FF}\u{FE0F}\u{200D}\u{20E3}#*0-9])+$',
  unicode: true,
);

/// Whether [text] is only 1–3 emojis (and spaces), which show big without a bubble.
bool isEmojiOnly(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty || !_pictographic.hasMatch(trimmed.replaceAll(' ', ''))) {
    return false;
  }
  // A digit or # alone is not an emoji; a keycap (with U+20E3) is.
  if (RegExp(r'^[#*0-9 ]+$').hasMatch(trimmed)) return false;
  final emojis = trimmed.characters.where((c) => c.trim().isNotEmpty);
  return emojis.length <= 3;
}

/// The picker as both places use it: categories, search and skin tones; recent ones are the
/// account's, shown separately.
Widget emojiPicker({required void Function(String emoji) onSelected}) =>
    EmojiPicker(
      onEmojiSelected: (_, emoji) => onSelected(emoji.emoji),
      config: const Config(
        height: 300,
        // Desktop fonts have them all; asking the platform needs a plugin call.
        checkPlatformCompatibility: false,
        categoryViewConfig: CategoryViewConfig(
          recentTabBehavior: RecentTabBehavior.NONE,
        ),
        bottomActionBarConfig: BottomActionBarConfig(
          showBackspaceButton: false,
        ),
      ),
    );

/// Asks for a reaction: the quick ones and the user's recent ones in a row, and the full
/// picker under ＋. Returns the emoji, or `null` if the user closes it.
Future<String?> pickReaction(BuildContext context, String account) =>
    showDialog<String>(
      context: context,
      builder: (_) => _ReactionDialog(account: account),
    );

class _ReactionDialog extends ConsumerStatefulWidget {
  const _ReactionDialog({required this.account});

  final String account;

  @override
  ConsumerState<_ReactionDialog> createState() => _ReactionDialogState();
}

class _ReactionDialogState extends ConsumerState<_ReactionDialog> {
  var _full = false;

  @override
  Widget build(BuildContext context) {
    final recent =
        ref.watch(recentEmojisProvider(widget.account)).value ?? const [];
    final row = [
      ...quickReactions,
      for (final emoji in recent.take(6))
        if (!quickReactions.contains(emoji)) emoji,
    ];
    return Dialog(
      key: const Key('reactionPicker'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                alignment: WrapAlignment.center,
                children: [
                  for (final emoji in row)
                    IconButton(
                      key: Key('reaction.$emoji'),
                      onPressed: () => Navigator.of(context).pop(emoji),
                      icon: Text(emoji, style: const TextStyle(fontSize: 24)),
                    ),
                  IconButton(
                    key: const Key('reaction.more'),
                    tooltip: 'More emojis',
                    onPressed: () => setState(() => _full = !_full),
                    icon: Icon(
                      _full ? Icons.expand_less_rounded : Icons.add_rounded,
                    ),
                  ),
                ],
              ),
              if (_full)
                emojiPicker(
                  onSelected: (emoji) => Navigator.of(context).pop(emoji),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Counts a use of [emoji] in the account's recent ones, and refreshes them.
void rememberEmoji(WidgetRef ref, String account, String emoji) {
  final session = ref.read(accountsProvider).value?.byId(account);
  if (session == null) return;
  unawaited(
    session
        .addRecentEmoji(emoji)
        .then((_) => ref.invalidate(recentEmojisProvider(account)))
        .catchError((Object _) {
          // Not counted; the emoji was used all the same.
        }),
  );
}
