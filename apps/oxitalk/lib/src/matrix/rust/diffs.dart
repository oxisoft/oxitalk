import '../../rust/api/room_list.dart';
import '../../rust/api/timeline.dart';

/// Applies one room-list diff to [list], in place. The diffs of a batch go in order.
void applyRoomListDiff(List<RoomSummary> list, RoomListDiff diff) {
  switch (diff) {
    case RoomListDiff_Append(:final values):
      list.addAll(values);
    case RoomListDiff_Clear():
      list.clear();
    case RoomListDiff_PushFront(:final value):
      list.insert(0, value);
    case RoomListDiff_PushBack(:final value):
      list.add(value);
    case RoomListDiff_PopFront():
      list.removeAt(0);
    case RoomListDiff_PopBack():
      list.removeLast();
    case RoomListDiff_Insert(:final index, :final value):
      list.insert(index, value);
    case RoomListDiff_Set(:final index, :final value):
      list[index] = value;
    case RoomListDiff_Remove(:final index):
      list.removeAt(index);
    case RoomListDiff_Truncate(:final length):
      list.length = length;
    case RoomListDiff_Reset(:final values):
      list
        ..clear()
        ..addAll(values);
  }
}

/// Applies one timeline diff to [list], in place. The diffs of a batch go in order.
void applyTimelineDiff(List<TimelineItem> list, TimelineDiff diff) {
  switch (diff) {
    case TimelineDiff_Append(:final values):
      list.addAll(values);
    case TimelineDiff_Clear():
      list.clear();
    case TimelineDiff_PushFront(:final value):
      list.insert(0, value);
    case TimelineDiff_PushBack(:final value):
      list.add(value);
    case TimelineDiff_PopFront():
      list.removeAt(0);
    case TimelineDiff_PopBack():
      list.removeLast();
    case TimelineDiff_Insert(:final index, :final value):
      list.insert(index, value);
    case TimelineDiff_Set(:final index, :final value):
      list[index] = value;
    case TimelineDiff_Remove(:final index):
      list.removeAt(index);
    case TimelineDiff_Truncate(:final length):
      list.length = length;
    case TimelineDiff_Reset(:final values):
      list
        ..clear()
        ..addAll(values);
  }
}
