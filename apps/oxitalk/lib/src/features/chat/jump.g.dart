// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'jump.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// A room's timeline around the message [eventId]; closed when no longer shown.

@ProviderFor(timelineAt)
final timelineAtProvider = TimelineAtFamily._();

/// A room's timeline around the message [eventId]; closed when no longer shown.

final class TimelineAtProvider
    extends
        $FunctionalProvider<
          AsyncValue<RoomTimeline>,
          RoomTimeline,
          FutureOr<RoomTimeline>
        >
    with $FutureModifier<RoomTimeline>, $FutureProvider<RoomTimeline> {
  /// A room's timeline around the message [eventId]; closed when no longer shown.
  TimelineAtProvider._({
    required TimelineAtFamily super.from,
    required (String, String, String) super.argument,
  }) : super(
         retry: null,
         name: r'timelineAtProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$timelineAtHash();

  @override
  String toString() {
    return r'timelineAtProvider'
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
    final argument = this.argument as (String, String, String);
    return timelineAt(ref, argument.$1, argument.$2, argument.$3);
  }

  @override
  bool operator ==(Object other) {
    return other is TimelineAtProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$timelineAtHash() => r'edd37e4b2eb75816ee992a211cc828d18c2b237e';

/// A room's timeline around the message [eventId]; closed when no longer shown.

final class TimelineAtFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<RoomTimeline>,
          (String, String, String)
        > {
  TimelineAtFamily._()
    : super(
        retry: null,
        name: r'timelineAtProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// A room's timeline around the message [eventId]; closed when no longer shown.

  TimelineAtProvider call(String account, String roomId, String eventId) =>
      TimelineAtProvider._(argument: (account, roomId, eventId), from: this);

  @override
  String toString() => r'timelineAtProvider';
}

/// As [timelineEntries], for [timelineAt].

@ProviderFor(timelineAtEntries)
final timelineAtEntriesProvider = TimelineAtEntriesFamily._();

/// As [timelineEntries], for [timelineAt].

final class TimelineAtEntriesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<TimelineEntry>>,
          List<TimelineEntry>,
          Stream<List<TimelineEntry>>
        >
    with
        $FutureModifier<List<TimelineEntry>>,
        $StreamProvider<List<TimelineEntry>> {
  /// As [timelineEntries], for [timelineAt].
  TimelineAtEntriesProvider._({
    required TimelineAtEntriesFamily super.from,
    required (String, String, String) super.argument,
  }) : super(
         retry: null,
         name: r'timelineAtEntriesProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$timelineAtEntriesHash();

  @override
  String toString() {
    return r'timelineAtEntriesProvider'
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
    final argument = this.argument as (String, String, String);
    return timelineAtEntries(ref, argument.$1, argument.$2, argument.$3);
  }

  @override
  bool operator ==(Object other) {
    return other is TimelineAtEntriesProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$timelineAtEntriesHash() => r'd253bafdeea9f120d13369599e38b3d02043cbc8';

/// As [timelineEntries], for [timelineAt].

final class TimelineAtEntriesFamily extends $Family
    with
        $FunctionalFamilyOverride<
          Stream<List<TimelineEntry>>,
          (String, String, String)
        > {
  TimelineAtEntriesFamily._()
    : super(
        retry: null,
        name: r'timelineAtEntriesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// As [timelineEntries], for [timelineAt].

  TimelineAtEntriesProvider call(
    String account,
    String roomId,
    String eventId,
  ) => TimelineAtEntriesProvider._(
    argument: (account, roomId, eventId),
    from: this,
  );

  @override
  String toString() => r'timelineAtEntriesProvider';
}
