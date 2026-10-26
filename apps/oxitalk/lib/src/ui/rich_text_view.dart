import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/theme.dart';
import '../matrix/api/models.dart';
import 'touch.dart';

final _url = RegExp(r'https?://[^\s<>"]+');

/// [text] without punctuation that ends the sentence around a link.
String _trimLink(String text) =>
    text.replaceFirst(RegExp(r'[.,;:!?)\]]+$'), '');

/// Formatted message text drawn with the app's own widgets: paragraphs, headings, lists,
/// quotes, code, rules, and the inline styles. Links (also plain URLs in the text) open
/// with [onLink]; spoilers show when clicked; a mention (a user's pill) with [onMention].
class RichTextView extends StatefulWidget {
  const RichTextView({
    required this.blocks,
    required this.onLink,
    this.onMention,
    super.key,
  });

  final List<RichBlock> blocks;
  final void Function(String url) onLink;

  /// A tap on a user's pill: their user ID and the name it shows.
  final void Function(String userId, String name)? onMention;

  @override
  State<RichTextView> createState() => _RichTextViewState();
}

class _RichTextViewState extends State<RichTextView> {
  final _recognizers = <TapGestureRecognizer>[];
  var _spoilersShown = false;

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  TapGestureRecognizer _onTap(VoidCallback action) {
    final recognizer = TapGestureRecognizer()..onTap = action;
    _recognizers.add(recognizer);
    return recognizer;
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    final blocks = widget.blocks;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (index, block) in blocks.indexed)
          Padding(
            padding: EdgeInsets.only(top: index == 0 ? 0 : 4),
            child: _quoted(context, block.quoteDepth, _block(context, block)),
          ),
      ],
    );
  }

  Widget _quoted(BuildContext context, int depth, Widget child) {
    var quoted = child;
    for (var i = 0; i < depth; i++) {
      quoted = Container(
        padding: const EdgeInsets.only(left: 8),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: Theme.of(context).colorScheme.outline,
              width: 3,
            ),
          ),
        ),
        child: quoted,
      );
    }
    return quoted;
  }

  Widget _block(BuildContext context, RichBlock block) {
    final theme = Theme.of(context);
    final text = Text.rich(TextSpan(children: _spans(context, block.spans)));
    return switch (block.kind) {
      ParagraphBlock() => text,
      HeadingBlock(:final level) => DefaultTextStyle.merge(
        style: switch (level) {
          1 => theme.textTheme.titleLarge,
          2 => theme.textTheme.titleMedium,
          _ => theme.textTheme.titleSmall,
        }?.copyWith(fontWeight: FontWeight.w700),
        child: text,
      ),
      ListItemBlock(:final number, :final depth) => Padding(
        padding: EdgeInsets.only(left: 16.0 * (depth - 1)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: number == null ? 16 : 26,
              child: Text(number == null ? '•' : '$number.'),
            ),
            Flexible(child: text),
          ],
        ),
      ),
      CodeBlock() => _CodeBlock(block.spans.map((span) => span.text).join()),
      RuleBlock() => const Divider(height: 12),
    };
  }

  List<InlineSpan> _spans(BuildContext context, List<RichSpan> spans) {
    final scheme = Theme.of(context).colorScheme;
    return [
      for (final span in spans)
        if (span.link == null &&
            span.mention == null &&
            !span.code &&
            !span.spoiler)
          ...linkifiedSpans(
            span.text,
            style: _style(context, span),
            linkColor: scheme.primary,
            onLink: (url) => _onTap(() => widget.onLink(url)),
          )
        else
          TextSpan(
            text: span.text,
            style: _style(context, span),
            recognizer: switch (span) {
              RichSpan(spoiler: true) => _onTap(
                () => setState(() => _spoilersShown = !_spoilersShown),
              ),
              RichSpan(:final link?) => _onTap(() => widget.onLink(link)),
              RichSpan(:final mention?) when widget.onMention != null => _onTap(
                () => widget.onMention!(mention, span.text),
              ),
              _ => null,
            },
          ),
    ];
  }

  TextStyle _style(BuildContext context, RichSpan span) {
    final scheme = Theme.of(context).colorScheme;
    final hidden = span.spoiler && !_spoilersShown;
    return TextStyle(
      fontWeight: span.bold || span.mention != null ? FontWeight.w700 : null,
      fontStyle: span.italic ? FontStyle.italic : null,
      decoration: TextDecoration.combine([
        if (span.strike) TextDecoration.lineThrough,
        if (span.underline || span.link != null) TextDecoration.underline,
      ]),
      fontFamily: span.code ? codeStyle.fontFamily : null,
      fontFamilyFallback: span.code ? codeStyle.fontFamilyFallback : null,
      color: hidden
          ? Colors.transparent
          : span.link != null
          ? context.oxi.threadLink
          : span.mention != null
          ? scheme.onSurface
          : parseCssColor(span.color),
      backgroundColor: hidden
          ? scheme.onSurface.withValues(alpha: 0.35)
          : span.code
          ? scheme.surfaceContainerHighest.withValues(alpha: 0.6)
          : span.mention != null
          ? OxiBrand.yellow.withValues(alpha: context.isDark ? 0.22 : 0.55)
          : null,
    );
  }
}

/// [text] with its URLs as links; each link's tap comes from [onLink].
List<InlineSpan> linkifiedSpans(
  String text, {
  required TextStyle? style,
  required Color linkColor,
  required GestureRecognizer Function(String url) onLink,
}) {
  final spans = <InlineSpan>[];
  var start = 0;
  for (final match in _url.allMatches(text)) {
    final url = _trimLink(match[0]!);
    if (match.start > start) {
      spans.add(
        TextSpan(text: text.substring(start, match.start), style: style),
      );
    }
    spans.add(
      TextSpan(
        text: url,
        style: (style ?? const TextStyle()).copyWith(
          color: linkColor,
          decoration: TextDecoration.underline,
        ),
        recognizer: onLink(url),
      ),
    );
    start = match.start + url.length;
  }
  if (start < text.length) {
    spans.add(TextSpan(text: text.substring(start), style: style));
  }
  return spans;
}

/// Plain message text with its URLs as links.
class LinkifiedText extends StatefulWidget {
  const LinkifiedText({required this.text, required this.onLink, super.key});

  final String text;
  final void Function(String url) onLink;

  @override
  State<LinkifiedText> createState() => _LinkifiedTextState();
}

class _LinkifiedTextState extends State<LinkifiedText> {
  final _recognizers = <TapGestureRecognizer>[];

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    if (!_url.hasMatch(widget.text)) return Text(widget.text);
    return Text.rich(
      TextSpan(
        children: linkifiedSpans(
          widget.text,
          style: null,
          linkColor: Theme.of(context).colorScheme.primary,
          onLink: (url) {
            final recognizer = TapGestureRecognizer()
              ..onTap = () => widget.onLink(url);
            _recognizers.add(recognizer);
            return recognizer;
          },
        ),
      ),
    );
  }
}

/// A CSS colour `#rgb` or `#rrggbb`; `null` for anything else.
Color? parseCssColor(String? css) {
  if (css == null || !css.startsWith('#')) return null;
  var hex = css.substring(1);
  if (hex.length == 3) hex = hex.split('').map((c) => '$c$c').join();
  if (hex.length != 6) return null;
  final value = int.tryParse(hex, radix: 16);
  return value == null ? null : Color(0xFF000000 | value);
}

/// A code block, with a button that copies all of it: shown while the mouse is over the
/// block, and always where there is no mouse to hover.
class _CodeBlock extends StatefulWidget {
  const _CodeBlock(this.code);

  final String code;

  @override
  State<_CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<_CodeBlock> {
  var _hovered = false;
  var _copied = false;
  Timer? _reset;

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(const SnackBar(content: Text('Code copied')));
    setState(() => _copied = true);
    _reset?.cancel();
    _reset = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final touch = isTouchPlatform(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Stack(
        children: [
          Container(
            key: const Key('rich.code'),
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.6,
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Text(widget.code, style: codeStyle.copyWith(fontSize: 13)),
            ),
          ),
          if (touch || _hovered || _copied)
            Positioned(
              top: 2,
              right: 2,
              child: IconButton.filledTonal(
                key: const Key('rich.code.copy'),
                tooltip: 'Copy code',
                iconSize: 16,
                visualDensity: VisualDensity.compact,
                onPressed: () => unawaited(_copy()),
                icon: Icon(_copied ? Icons.check_rounded : Icons.copy_rounded),
              ),
            ),
        ],
      ),
    );
  }
}
