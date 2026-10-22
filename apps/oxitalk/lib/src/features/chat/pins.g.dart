// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pins.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The room's pins and pinning; closed when no longer used.

@ProviderFor(pinnedEvents)
final pinnedEventsProvider = PinnedEventsFamily._();

/// The room's pins and pinning; closed when no longer used.

final class PinnedEventsProvider
    extends
        $FunctionalProvider<
          AsyncValue<PinnedEvents>,
          PinnedEvents,
          FutureOr<PinnedEvents>
        >
    with $FutureModifier<PinnedEvents>, $FutureProvider<PinnedEvents> {
  /// The room's pins and pinning; closed when no longer used.
  PinnedEventsProvider._({
    required PinnedEventsFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'pinnedEventsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$pinnedEventsHash();

  @override
  String toString() {
    return r'pinnedEventsProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<PinnedEvents> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<PinnedEvents> create(Ref ref) {
    final argument = this.argument as (String, String);
    return pinnedEvents(ref, argument.$1, argument.$2);
  }

  @override
  bool operator ==(Object other) {
    return other is PinnedEventsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$pinnedEventsHash() => r'2403527bef354a95a2ba0ae3a16594fdd643ce33';

/// The room's pins and pinning; closed when no longer used.

final class PinnedEventsFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<PinnedEvents>, (String, String)> {
  PinnedEventsFamily._()
    : super(
        retry: null,
        name: r'pinnedEventsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The room's pins and pinning; closed when no longer used.

  PinnedEventsProvider call(String account, String roomId) =>
      PinnedEventsProvider._(argument: (account, roomId), from: this);

  @override
  String toString() => r'pinnedEventsProvider';
}

/// Which messages of the room are pinned, and whether the user may pin.

@ProviderFor(roomPins)
final roomPinsProvider = RoomPinsFamily._();

/// Which messages of the room are pinned, and whether the user may pin.

final class RoomPinsProvider
    extends
        $FunctionalProvider<AsyncValue<RoomPins>, RoomPins, Stream<RoomPins>>
    with $FutureModifier<RoomPins>, $StreamProvider<RoomPins> {
  /// Which messages of the room are pinned, and whether the user may pin.
  RoomPinsProvider._({
    required RoomPinsFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'roomPinsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$roomPinsHash();

  @override
  String toString() {
    return r'roomPinsProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $StreamProviderElement<RoomPins> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<RoomPins> create(Ref ref) {
    final argument = this.argument as (String, String);
    return roomPins(ref, argument.$1, argument.$2);
  }

  @override
  bool operator ==(Object other) {
    return other is RoomPinsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$roomPinsHash() => r'936d4460e5f53df5820583ef5bccf663991279be';

/// Which messages of the room are pinned, and whether the user may pin.

final class RoomPinsFamily extends $Family
    with $FunctionalFamilyOverride<Stream<RoomPins>, (String, String)> {
  RoomPinsFamily._()
    : super(
        retry: null,
        name: r'roomPinsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Which messages of the room are pinned, and whether the user may pin.

  RoomPinsProvider call(String account, String roomId) =>
      RoomPinsProvider._(argument: (account, roomId), from: this);

  @override
  String toString() => r'roomPinsProvider';
}

/// The timeline of the room's pinned messages; closed when no longer shown.

@ProviderFor(pinnedTimeline)
final pinnedTimelineProvider = PinnedTimelineFamily._();

/// The timeline of the room's pinned messages; closed when no longer shown.

final class PinnedTimelineProvider
    extends
        $FunctionalProvider<
          AsyncValue<RoomTimeline>,
          RoomTimeline,
          FutureOr<RoomTimeline>
        >
    with $FutureModifier<RoomTimeline>, $FutureProvider<RoomTimeline> {
  /// The timeline of the room's pinned messages; closed when no longer shown.
  PinnedTimelineProvider._({
    required PinnedTimelineFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'pinnedTimelineProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$pinnedTimelineHash();

  @override
  String toString() {
    return r'pinnedTimelineProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<RoomTimeline> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<RoomTimeline> create(Ref ref) {
    final argument = this.argument as (String, String);
    return pinnedTimeline(ref, argument.$1, argument.$2);
  }

  @override
  bool operator ==(Object other) {
    return other is PinnedTimelineProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$pinnedTimelineHash() => r'9f2bd622b3caccc08bc28da04dabc22c34a0bd6b';

/// The timeline of the room's pinned messages; closed when no longer shown.

final class PinnedTimelineFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<RoomTimeline>, (String, String)> {
  PinnedTimelineFamily._()
    : super(
        retry: null,
        name: r'pinnedTimelineProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The timeline of the room's pinned messages; closed when no longer shown.

  PinnedTimelineProvider call(String account, String roomId) =>
      PinnedTimelineProvider._(argument: (account, roomId), from: this);

  @override
  String toString() => r'pinnedTimelineProvider';
}

@ProviderFor(pinnedEntries)
final pinnedEntriesProvider = PinnedEntriesFamily._();

final class PinnedEntriesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<TimelineEntry>>,
          List<TimelineEntry>,
          Stream<List<TimelineEntry>>
        >
    with
        $FutureModifier<List<TimelineEntry>>,
        $StreamProvider<List<TimelineEntry>> {
  PinnedEntriesProvider._({
    required PinnedEntriesFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'pinnedEntriesProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$pinnedEntriesHash();

  @override
  String toString() {
    return r'pinnedEntriesProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $StreamProviderElement<List<TimelineEntry>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<TimelineEntry>> create(Ref ref) {
    final argument = this.argument as (String, String);
    return pinnedEntries(ref, argument.$1, argument.$2);
  }

  @override
  bool operator ==(Object other) {
    return other is PinnedEntriesProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$pinnedEntriesHash() => r'397e5a47e1bd493f78a83d304e2dada01f9a7f27';

final class PinnedEntriesFamily extends $Family
    with
        $FunctionalFamilyOverride<
          Stream<List<TimelineEntry>>,
          (String, String)
        > {
  PinnedEntriesFamily._()
    : super(
        retry: null,
        name: r'pinnedEntriesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  PinnedEntriesProvider call(String account, String roomId) =>
      PinnedEntriesProvider._(argument: (account, roomId), from: this);

  @override
  String toString() => r'pinnedEntriesProvider';
}

/// The room's pinned messages, the last pinned first. The timeline of pinned messages is
/// only opened while there are pins.

@ProviderFor(pinnedMessages)
final pinnedMessagesProvider = PinnedMessagesFamily._();

/// The room's pinned messages, the last pinned first. The timeline of pinned messages is
/// only opened while there are pins.

final class PinnedMessagesProvider
    extends
        $FunctionalProvider<
          List<PinnedMessage>,
          List<PinnedMessage>,
          List<PinnedMessage>
        >
    with $Provider<List<PinnedMessage>> {
  /// The room's pinned messages, the last pinned first. The timeline of pinned messages is
  /// only opened while there are pins.
  PinnedMessagesProvider._({
    required PinnedMessagesFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'pinnedMessagesProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$pinnedMessagesHash();

  @override
  String toString() {
    return r'pinnedMessagesProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $ProviderElement<List<PinnedMessage>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  List<PinnedMessage> create(Ref ref) {
    final argument = this.argument as (String, String);
    return pinnedMessages(ref, argument.$1, argument.$2);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<PinnedMessage> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<PinnedMessage>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is PinnedMessagesProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$pinnedMessagesHash() => r'0e501b01e0e7f4b1ba3be2d19905f0818a7d4685';

/// The room's pinned messages, the last pinned first. The timeline of pinned messages is
/// only opened while there are pins.

final class PinnedMessagesFamily extends $Family
    with $FunctionalFamilyOverride<List<PinnedMessage>, (String, String)> {
  PinnedMessagesFamily._()
    : super(
        retry: null,
        name: r'pinnedMessagesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The room's pinned messages, the last pinned first. The timeline of pinned messages is
  /// only opened while there are pins.

  PinnedMessagesProvider call(String account, String roomId) =>
      PinnedMessagesProvider._(argument: (account, roomId), from: this);

  @override
  String toString() => r'pinnedMessagesProvider';
}
