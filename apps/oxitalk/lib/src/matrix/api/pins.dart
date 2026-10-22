/// A room's pinned messages: what the app shows, independent of the bridge.
library;

/// Which events of a room are pinned, and whether the user may change that.
final class RoomPins {
  const RoomPins({this.eventIds = const [], this.canPin = false});

  /// In the order they were pinned: the last one was pinned last.
  final List<String> eventIds;

  /// Whether the user's power level allows pinning and unpinning.
  final bool canPin;
}

/// A room's pins, followed until [close].
abstract interface class PinnedEvents {
  /// The current pins (none until they are read), then every change.
  Stream<RoomPins> get pins;

  /// Pins the message [eventId] as the last pin; `false` if it was pinned already.
  Future<bool> pin(String eventId);

  /// `false` if it wasn't pinned.
  Future<bool> unpin(String eventId);

  void close();
}
