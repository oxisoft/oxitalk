import 'package:flutter/services.dart';

/// Plain-text emoticons and the emoji they become.
const emoticons = {
  ':)': '🙂',
  ':-)': '🙂',
  '(:': '🙂',
  ':(': '🙁',
  ':-(': '🙁',
  ':D': '😃',
  ':-D': '😃',
  'xD': '😆',
  'XD': '😆',
  ';)': '😉',
  ';-)': '😉',
  ':P': '😛',
  ':-P': '😛',
  ':p': '😛',
  ':-p': '😛',
  ';P': '😜',
  ';p': '😜',
  ':O': '😮',
  ':-O': '😮',
  ':o': '😮',
  ':-o': '😮',
  ':|': '😐',
  ':-|': '😐',
  ':/': '😕',
  ':-/': '😕',
  ":'(": '😢',
  ':*': '😘',
  ':-*': '😘',
  'B)': '😎',
  'B-)': '😎',
  '8)': '😎',
  '>:(': '😠',
  'O:)': '😇',
  ':\$': '😳',
  '<3': '❤️',
  '</3': '💔',
};

/// Characters that end an emoticon as it is typed.
const _ends = ' \n.,!?';

/// The emoji for the emoticon that ends [text] at [end], and where that emoticon starts;
/// `null` if there is none. An emoticon stands alone, after a space or at the start, and
/// never inside `code`.
({int start, String emoji})? _emoticonBefore(String text, int end) {
  final start = text.lastIndexOf(RegExp(r'\s'), end - 1) + 1;
  final emoji = emoticons[text.substring(start, end)];
  if (emoji == null) return null;
  // An odd number of backticks before it: inside code.
  if ('`'.allMatches(text.substring(0, start)).length.isOdd) return null;
  return (start: start, emoji: emoji);
}

/// Replaces an emoticon with its emoji the moment a space or punctuation follows it, while
/// [enabled] says so.
class EmoticonFormatter extends TextInputFormatter {
  EmoticonFormatter({required this.enabled});

  final bool Function() enabled;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final cursor = newValue.selection.baseOffset;
    // Only one character typed, at the cursor.
    if (!enabled() ||
        !newValue.selection.isCollapsed ||
        newValue.text.length != oldValue.text.length + 1 ||
        cursor < 2 ||
        !_ends.contains(newValue.text[cursor - 1])) {
      return newValue;
    }
    final found = _emoticonBefore(newValue.text, cursor - 1);
    if (found == null) return newValue;
    final text = newValue.text.replaceRange(
      found.start,
      cursor - 1,
      found.emoji,
    );
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(
        offset: cursor + text.length - newValue.text.length,
      ),
    );
  }
}

/// [text] with an emoticon at its very end replaced too, for sending: nothing followed it
/// to replace it as it was typed.
String withTrailingEmoticon(String text) {
  final end = text.trimRight().length;
  if (end == 0) return text;
  final found = _emoticonBefore(text, end);
  return found == null
      ? text
      : text.replaceRange(found.start, end, found.emoji);
}
