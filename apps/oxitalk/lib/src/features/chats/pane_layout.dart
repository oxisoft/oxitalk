import 'dart:math';

/// How wide the chat list and the thread pane are on a wide window, from the widths they
/// were dragged to and the window's width: the chat between them takes the rest, and keeps
/// at least [chatMin] while the side panes can give way.
final class PaneLayout {
  PaneLayout._({
    required this.list,
    required this.thread,
    required this.listMax,
    required this.threadMax,
  });

  /// Fits the panes into a [window] this wide, of which the account rail and its line take
  /// [rail]. [list] and [thread] are the dragged widths, null for the defaults; a [narrow]
  /// list keeps [narrowList]. Without a [hasThread] pane there is no thread width.
  factory PaneLayout.fit({
    required double window,
    required double rail,
    required double? list,
    required bool narrow,
    required double? thread,
    required bool hasThread,
  }) {
    final listCap = max(listMin, min(listMaxCap, window * listMaxShare));
    final threadCap = max(threadMin, window * threadMaxShare);
    var listWidth = narrow
        ? narrowList
        : (list ?? listDefault).clamp(listMin, listCap);
    var threadWidth = hasThread
        ? (thread ?? threadDefault).clamp(threadMin, threadCap)
        : 0.0;
    // What the side panes may take between them, the chat keeping its minimum.
    final sides = window - rail - (hasThread ? 2 : 1) - chatMin;
    var excess = listWidth + threadWidth - sides;
    // A smaller window shrinks the thread first, then the list; down to their minimums,
    // then to what they can't do without, and only then does the chat get less.
    double give(double width, double floor) {
      final cut = min(max(excess, 0), max(width - floor, 0)).toDouble();
      excess -= cut;
      return width - cut;
    }

    if (hasThread) threadWidth = give(threadWidth, threadMin);
    if (!narrow) listWidth = give(listWidth, listMin);
    if (hasThread) threadWidth = give(threadWidth, threadFloor);
    if (!narrow) listWidth = give(listWidth, listFloor);
    return PaneLayout._(
      list: listWidth,
      thread: hasThread ? threadWidth : null,
      listMax: max(listMin, min(listCap, sides - threadWidth)),
      threadMax: max(threadMin, min(threadCap, sides - listWidth)),
    );
  }

  static const listDefault = 360.0;
  static const listMin = 260.0;

  /// The list is never wider than this, nor than [listMaxShare] of the window.
  static const listMaxCap = 560.0;
  static const listMaxShare = 0.45;

  /// Below its minimum on a small window, the list stops here before the chat gives way.
  static const listFloor = 200.0;

  /// The list narrowed to pictures and short names.
  static const narrowList = 96.0;

  static const threadDefault = 400.0;
  static const threadMin = 300.0;
  static const threadMaxShare = 0.5;

  /// Below its minimum on a small window, the thread pane stops here before the chat gives
  /// way.
  static const threadFloor = 240.0;

  static const chatMin = 360.0;

  /// The list's width, the account rail and its line not counted.
  final double list;

  /// The thread pane's width, if one is open.
  final double? thread;

  /// How wide the list can be dragged with the thread pane as it is.
  final double listMax;

  /// How wide the thread pane can be dragged with the list as it is.
  final double threadMax;

  /// [width] for the list, within its limits.
  double clampList(double width) => width.clamp(listMin, listMax);

  /// [width] for the thread pane, within its limits.
  double clampThread(double width) => width.clamp(threadMin, threadMax);
}
