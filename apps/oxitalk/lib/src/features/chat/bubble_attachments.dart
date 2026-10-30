/// What hangs on a message bubble's bottom edge: its reactions and who has read up to it.
library;

import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A message bubble with its reactions at its bottom start corner and the readers' pictures
/// at its bottom end corner, each across the bubble's edge: half on the bubble, half under
/// it, so they read as part of the message (bkv, 2026-10-30).
///
/// The bubble sits at the start, or at the end when [alignEnd] (the user's own messages).
/// When the reactions and readers are wider than the bubble, the whole is as wide as they
/// are and they keep to its corners.
class BubbleAttachments extends MultiChildRenderObjectWidget {
  BubbleAttachments({
    required Widget bubble,
    required this.alignEnd,
    this.overlap = true,
    Widget? start,
    Widget? end,
    super.key,
  }) : super(
         children: [
           bubble,
           start ?? const SizedBox.shrink(),
           end ?? const SizedBox.shrink(),
         ],
       );

  final bool alignEnd;

  /// Across the bubble's edge; when `false` (big emojis without a bubble), under it.
  final bool overlap;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderBubbleAttachments(alignEnd: alignEnd, overlap: overlap);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderBubbleAttachments renderObject,
  ) => renderObject
    ..alignEnd = alignEnd
    ..overlap = overlap;
}

class _AttachmentParentData extends ContainerBoxParentData<RenderBox> {}

/// The render object of [BubbleAttachments]; its children are the bubble, the start
/// attachment and the end attachment, in that order (an empty box for a missing one).
class RenderBubbleAttachments extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _AttachmentParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _AttachmentParentData> {
  RenderBubbleAttachments({required this._alignEnd, required bool overlap})
    : _overlapping = overlap;

  /// From the bubble's side edge to an attachment: clear of the bubble's cut corner.
  static const inset = 12.0;

  /// Between the reactions and the readers when both show.
  static const gap = 8.0;

  /// At most this much of an attachment lies on the bubble: half of one row of reactions.
  static const maxOverlap = 11.0;

  bool get alignEnd => _alignEnd;
  bool _alignEnd;
  set alignEnd(bool value) {
    if (value == _alignEnd) return;
    _alignEnd = value;
    markNeedsLayout();
  }

  bool get overlap => _overlapping;
  bool _overlapping;
  set overlap(bool value) {
    if (value == _overlapping) return;
    _overlapping = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _AttachmentParentData) {
      child.parentData = _AttachmentParentData();
    }
  }

  RenderBox get _bubble => firstChild!;
  RenderBox get _start => childAfter(_bubble)!;
  RenderBox get _end => childAfter(_start)!;

  double _overlap(Size size) =>
      !_overlapping || size.isEmpty ? 0 : math.min(size.height / 2, maxOverlap);

  /// The size, and with [place] the children's offsets, for [constraints]; [measure] lays
  /// a child out (or measures it dry) and gives its size.
  Size _layout(
    BoxConstraints constraints,
    Size Function(RenderBox child, BoxConstraints constraints) measure, {
    bool place = false,
  }) {
    final maxWidth = constraints.maxWidth;
    final bubble = measure(_bubble, BoxConstraints(maxWidth: maxWidth));
    final attachments = BoxConstraints(
      maxWidth: math.max(0, maxWidth - 2 * inset),
    );
    final start = measure(_start, attachments);
    final end = measure(_end, attachments);
    final both = !start.isEmpty && !end.isEmpty;
    final needed = start.isEmpty && end.isEmpty
        ? 0.0
        : inset + start.width + (both ? gap : 0) + end.width + inset;
    final width = math.max(bubble.width, needed);
    final below = math.max(
      0.0,
      math.max(start.height - _overlap(start), end.height - _overlap(end)),
    );
    final size = constraints.constrain(Size(width, bubble.height + below));
    if (place) {
      final bubbleLeft = alignEnd ? size.width - bubble.width : 0.0;
      final wide = needed > bubble.width;
      final left = wide ? 0.0 : bubbleLeft;
      final right = wide ? size.width : bubbleLeft + bubble.width;
      _offset(_bubble, Offset(bubbleLeft, 0));
      _offset(_start, Offset(left + inset, bubble.height - _overlap(start)));
      _offset(
        _end,
        Offset(right - inset - end.width, bubble.height - _overlap(end)),
      );
    }
    return size;
  }

  static void _offset(RenderBox child, Offset offset) =>
      (child.parentData! as _AttachmentParentData).offset = offset;

  @override
  void performLayout() {
    size = _layout(constraints, (child, constraints) {
      child.layout(constraints, parentUsesSize: true);
      return child.size;
    }, place: true);
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) => _layout(
    constraints,
    (child, constraints) => child.getDryLayout(constraints),
  );

  double _attachmentsWidth(double Function(RenderBox child) width) {
    final start = width(_start);
    final end = width(_end);
    if (start == 0 && end == 0) return 0;
    return inset + start + (start > 0 && end > 0 ? gap : 0) + end + inset;
  }

  @override
  double computeMinIntrinsicWidth(double height) => math.max(
    _bubble.getMinIntrinsicWidth(height),
    _attachmentsWidth((child) => child.getMinIntrinsicWidth(double.infinity)),
  );

  @override
  double computeMaxIntrinsicWidth(double height) => math.max(
    _bubble.getMaxIntrinsicWidth(height),
    _attachmentsWidth((child) => child.getMaxIntrinsicWidth(double.infinity)),
  );

  double _below(double Function(RenderBox child) height) {
    double hanging(RenderBox child) {
      final h = height(child);
      if (h <= 0) return 0;
      return _overlapping ? h - math.min(h / 2, maxOverlap) : h;
    }

    return math.max(hanging(_start), hanging(_end));
  }

  @override
  double computeMinIntrinsicHeight(double width) =>
      _bubble.getMinIntrinsicHeight(width) +
      _below((child) => child.getMinIntrinsicHeight(width));

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _bubble.getMaxIntrinsicHeight(width) +
      _below((child) => child.getMaxIntrinsicHeight(width));

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      defaultComputeDistanceToFirstActualBaseline(baseline);

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
