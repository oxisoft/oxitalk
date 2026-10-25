import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/theme.dart';

/// The grip of the line between two panes: a strip wider than the line, laid over it, that
/// drags it left or right with the resize cursor, and lights the line up while hovered,
/// dragged or focused. A double click puts the pane back to its default width; the arrow
/// keys move it while it has the focus.
///
/// It resizes a pane [width] wide: on its left ([growsRight], as the chat list) or on its
/// right (as the thread pane), so a drag to the right makes it wider or narrower.
class PaneDivider extends StatefulWidget {
  const PaneDivider({
    required this.label,
    required this.width,
    required this.growsRight,
    required this.onResize,
    required this.onResizeEnd,
    required this.onReset,
    super.key,
  });

  /// The grip's width: the line sits in its middle.
  static const gripWidth = 10.0;

  /// How far an arrow key, or a screen reader's increase, moves the line.
  static const keyStep = 16.0;

  /// What a screen reader says, as `Resize chat list`.
  final String label;

  /// The pane's width now.
  final double width;
  final bool growsRight;

  /// The width the user drags the pane to; whoever gets it keeps it within its limits.
  final ValueChanged<double> onResize;

  /// The drag or key press is over: time to save.
  final VoidCallback onResizeEnd;
  final VoidCallback onReset;

  @override
  State<PaneDivider> createState() => _PaneDividerState();
}

class _PaneDividerState extends State<PaneDivider> {
  var _hovered = false;
  var _focused = false;
  var _dragging = false;
  double _startWidth = 0;
  double _dragged = 0;

  double get _sign => widget.growsRight ? 1 : -1;

  void _step(double by) {
    widget.onResize(widget.width + by);
    widget.onResizeEnd();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final step = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowLeft => -PaneDivider.keyStep,
      LogicalKeyboardKey.arrowRight => PaneDivider.keyStep,
      _ => null,
    };
    if (step == null) return KeyEventResult.ignored;
    _step(step * _sign);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final lit = _hovered || _dragging || _focused;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      container: true,
      label: widget.label,
      value: '${widget.width.round()} pixels',
      increasedValue: '${(widget.width + PaneDivider.keyStep).round()} pixels',
      decreasedValue: '${(widget.width - PaneDivider.keyStep).round()} pixels',
      onIncrease: () => _step(PaneDivider.keyStep),
      onDecrease: () => _step(-PaneDivider.keyStep),
      child: Focus(
        onKeyEvent: _onKey,
        onFocusChange: (focused) => setState(() => _focused = focused),
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeColumn,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            dragStartBehavior: DragStartBehavior.down,
            onHorizontalDragStart: (_) => setState(() {
              _dragging = true;
              _startWidth = widget.width;
              _dragged = 0;
            }),
            onHorizontalDragUpdate: (details) {
              _dragged += details.delta.dx;
              widget.onResize(_startWidth + _dragged * _sign);
            },
            onHorizontalDragEnd: (_) {
              setState(() => _dragging = false);
              widget.onResizeEnd();
            },
            onHorizontalDragCancel: () => setState(() => _dragging = false),
            onDoubleTap: widget.onReset,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: 2,
                // Yellow lights up a dark window; on a light one a thin yellow line is
                // hard to see, so ink.
                color: lit
                    ? (dark ? OxiBrand.yellow : OxiBrand.ink)
                    : Colors.transparent,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
