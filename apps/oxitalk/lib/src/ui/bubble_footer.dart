import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A bubble's [content] with a [footer] row under it that spans the bubble's full width:
/// as wide as the content, or as the footer needs (up to the room there is), whichever is
/// wider. The content keeps its own size, so the bubble doesn't grow to the maximum.
///
/// Only the footer is measured by its intrinsic width; the content may hold scroll views
/// or other widgets that can't be.
class BubbleWithFooter extends MultiChildRenderObjectWidget {
  BubbleWithFooter({required Widget content, required Widget footer, super.key})
    : super(children: [content, footer]);

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderBubbleWithFooter();
}

class _FooterParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderBubbleWithFooter extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _FooterParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _FooterParentData> {
  RenderBox get _content => firstChild!;
  RenderBox get _footer => childAfter(firstChild!)!;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _FooterParentData) {
      child.parentData = _FooterParentData();
    }
  }

  double _width(BoxConstraints constraints, double contentWidth) {
    final footerWidth = _footer.getMaxIntrinsicWidth(double.infinity);
    return constraints.constrainWidth(math.max(contentWidth, footerWidth));
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final content = _content.getDryLayout(constraints.loosen());
    final width = _width(constraints, content.width);
    final footer = _footer.getDryLayout(BoxConstraints.tightFor(width: width));
    return constraints.constrain(Size(width, content.height + footer.height));
  }

  @override
  void performLayout() {
    final content = _content
      ..layout(constraints.loosen(), parentUsesSize: true);
    final width = _width(constraints, content.size.width);
    final footer = _footer
      ..layout(BoxConstraints.tightFor(width: width), parentUsesSize: true);
    (content.parentData! as _FooterParentData).offset = Offset.zero;
    (footer.parentData! as _FooterParentData).offset = Offset(
      0,
      content.size.height,
    );
    size = constraints.constrain(
      Size(width, content.size.height + footer.size.height),
    );
  }

  @override
  double computeMinIntrinsicWidth(double height) => math.max(
    _content.getMinIntrinsicWidth(height),
    _footer.getMinIntrinsicWidth(height),
  );

  @override
  double computeMaxIntrinsicWidth(double height) => math.max(
    _content.getMaxIntrinsicWidth(height),
    _footer.getMaxIntrinsicWidth(height),
  );

  @override
  double computeMinIntrinsicHeight(double width) =>
      _content.getMinIntrinsicHeight(width) +
      _footer.getMinIntrinsicHeight(width);

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _content.getMaxIntrinsicHeight(width) +
      _footer.getMaxIntrinsicHeight(width);

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
