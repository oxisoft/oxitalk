import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../matrix/api/models.dart';

/// The character that stands for a pill in the composer's text: one character, so the cursor
/// can't go inside a pill and backspace deletes it whole.
const pillChar = '\uFFFC';

/// The composer's text with pills: each pill is a [pillChar] in the text, drawn as a chip,
/// and its [MessagePart] is kept in [pills] in the order the pills appear. Editing keeps the
/// two in step: a pill deleted from the text is dropped, and a [pillChar] that comes from
/// elsewhere (pasted) is taken out.
class ComposerController extends TextEditingController {
  ComposerController();

  final _pills = <MessagePart>[];

  /// The pills, in the order they appear in the text.
  List<MessagePart> get pills => List.unmodifiable(_pills);

  @override
  set value(TextEditingValue newValue) {
    final old = super.value;
    if (_pills.isEmpty && !newValue.text.contains(pillChar)) {
      super.value = newValue;
      return;
    }
    super.value = _sync(old, newValue);
  }

  /// [next] with the pills deleted from [old] dropped from [pills], and any new [pillChar]
  /// taken out of the text.
  TextEditingValue _sync(TextEditingValue old, TextEditingValue next) {
    final before = old.text;
    final after = next.text;
    // The changed stretch: after the common start and before the common end. The cursor
    // tells which of two equal pills next to each other went.
    var start = 0;
    final shorter = before.length < after.length ? before.length : after.length;
    while (start < shorter && before[start] == after[start]) {
      start++;
    }
    final cursor = next.selection.isValid ? next.selection.start : start;
    if (cursor < start && after.length < before.length) start = cursor;
    var end = 0;
    while (end < shorter - start &&
        before[before.length - 1 - end] == after[after.length - 1 - end]) {
      end++;
    }
    final removedFrom = start;
    final removedTo = before.length - end;
    final pillsBefore = _count(before, 0, removedFrom);
    final removedPills = _count(before, removedFrom, removedTo);
    _pills.removeRange(pillsBefore, pillsBefore + removedPills);
    final inserted = after.substring(start, after.length - end);
    if (!inserted.contains(pillChar)) return next;
    // A pill character from outside (a paste): there is no pill for it.
    final cleaned = inserted.replaceAll(pillChar, '');
    final text = after.replaceRange(start, after.length - end, cleaned);
    final offset = start + cleaned.length;
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: offset),
    );
  }

  static int _count(String text, int from, int to) {
    var count = 0;
    for (var i = from; i < to; i++) {
      if (text[i] == pillChar) count++;
    }
    return count;
  }

  /// Replaces the text from [start] to [end] (the typed `@name`) with a pill for [pill] and a
  /// space after it, the cursor after the space.
  void insertPill(int start, int end, MessagePart pill) {
    final old = super.value;
    final index = _count(old.text, 0, start);
    final removed = _count(old.text, start, end);
    _pills
      ..removeRange(index, index + removed)
      ..insert(index, pill);
    final text = old.text.replaceRange(start, end, '$pillChar ');
    super.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: start + 2),
    );
  }

  /// Sets the text and its pills: each [pillChar] in [text] stands for the next of [pills].
  void setContent(String text, List<MessagePart> pills) {
    _pills
      ..clear()
      ..addAll(pills);
    super.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  @override
  void clear() {
    _pills.clear();
    super.clear();
  }

  /// What was written, as parts: the text between the pills, and the pills. Spaces at the
  /// start and the end are left out.
  List<MessagePart> parts() {
    final text = this.text;
    final parts = <MessagePart>[];
    var pill = 0;
    final buffer = StringBuffer();
    for (final char in text.split('')) {
      if (char == pillChar && pill < _pills.length) {
        if (buffer.isNotEmpty) parts.add(TextPart(buffer.toString()));
        buffer.clear();
        parts.add(_pills[pill++]);
      } else {
        buffer.write(char);
      }
    }
    if (buffer.isNotEmpty) parts.add(TextPart(buffer.toString()));
    // Trim the whole message, not each piece.
    if (parts.firstOrNull case TextPart(:final text)) {
      final trimmed = text.trimLeft();
      trimmed.isEmpty ? parts.removeAt(0) : parts[0] = TextPart(trimmed);
    }
    if (parts.lastOrNull case TextPart(:final text)) {
      final trimmed = text.trimRight();
      trimmed.isEmpty
          ? parts.removeLast()
          : parts[parts.length - 1] = TextPart(trimmed);
    }
    return parts;
  }

  /// Whether there are pills in the text.
  bool get hasPills => _pills.isNotEmpty;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (_pills.isEmpty || !text.contains(pillChar)) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    final children = <InlineSpan>[];
    final buffer = StringBuffer();
    var pill = 0;
    for (final char in text.split('')) {
      if (char == pillChar && pill < _pills.length) {
        if (buffer.isNotEmpty) children.add(TextSpan(text: buffer.toString()));
        buffer.clear();
        children.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: MentionPill(part: _pills[pill++], style: style),
          ),
        );
      } else {
        buffer.write(char);
      }
    }
    if (buffer.isNotEmpty) children.add(TextSpan(text: buffer.toString()));
    return TextSpan(style: style, children: children);
  }
}

/// A pill as the composer draws it: the name on a quiet yellow tag with cut corners, the
/// mention colour of the brand.
class MentionPill extends StatelessWidget {
  const MentionPill({required this.part, this.style, super.key});

  final MessagePart part;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final label = switch (part) {
      UserPill(:final name, :final userId) => name.isEmpty ? userId : name,
      RoomPill(:final alias, :final name) => alias ?? name,
      AtRoomPill() => '@room',
      TextPart(:final text) => text,
    };
    return Container(
      key: Key('composer.pill.$label'),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: ShapeDecoration(
        color: OxiBrand.yellow.withValues(alpha: context.isDark ? 0.22 : 0.55),
        shape: OxiShapes.cut(4),
      ),
      child: Text(
        label,
        style: (style ?? const TextStyle()).copyWith(
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }
}

/// [body] of a message with the pills its [formatted] text shows put back, for editing it:
/// each mention (a user) or room link found in the formatted text, in order, becomes a pill
/// where its text is next found in the body.
(String, List<MessagePart>) pillsFromMessage(
  String body,
  List<RichBlock>? formatted,
) {
  if (formatted == null) return (body, const []);
  final found = <(String, MessagePart)>[];
  for (final block in formatted) {
    for (final span in block.spans) {
      if (span.mention case final userId?) {
        found.add((span.text, UserPill(userId, span.text)));
      } else if (span.link case final link?) {
        if (roomOfLink(link) case final room?) {
          found.add((
            span.text,
            RoomPill(
              roomId: room,
              name: span.text,
              alias: room.startsWith('#') ? room : null,
            ),
          ));
        }
      }
    }
  }
  if (found.isEmpty) return (body, const []);
  final text = StringBuffer();
  final pills = <MessagePart>[];
  var from = 0;
  for (final (label, pill) in found) {
    if (label.isEmpty) continue;
    final at = body.indexOf(label, from);
    if (at < 0) continue;
    text
      ..write(body.substring(from, at))
      ..write(pillChar);
    pills.add(pill);
    from = at + label.length;
  }
  text.write(body.substring(from));
  return (text.toString(), pills);
}

/// The room (an `!id` or `#alias`) a `matrix.to` link points to, if it points to one.
String? roomOfLink(String link) {
  const prefix = 'https://matrix.to/#/';
  if (!link.startsWith(prefix)) return null;
  final target = Uri.decodeComponent(
    link.substring(prefix.length).split('?').first,
  );
  return target.startsWith('#') || target.startsWith('!')
      ? target.split('/').first
      : null;
}
