// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Tests override this (no keyring in CI).

@ProviderFor(secretStore)
final secretStoreProvider = SecretStoreProvider._();

/// Tests override this (no keyring in CI).

final class SecretStoreProvider
    extends $FunctionalProvider<SecretStore, SecretStore, SecretStore>
    with $Provider<SecretStore> {
  /// Tests override this (no keyring in CI).
  SecretStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'secretStoreProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$secretStoreHash();

  @$internal
  @override
  $ProviderElement<SecretStore> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  SecretStore create(Ref ref) {
    return secretStore(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SecretStore value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SecretStore>(value),
    );
  }
}

String _$secretStoreHash() => r'f6ba1ced2e985c77ee9b83ea18f3bf60168186cd';

/// Tests override this with fakes.

@ProviderFor(clientFactory)
final clientFactoryProvider = ClientFactoryProvider._();

/// Tests override this with fakes.

final class ClientFactoryProvider
    extends
        $FunctionalProvider<
          MatrixClientFactory,
          MatrixClientFactory,
          MatrixClientFactory
        >
    with $Provider<MatrixClientFactory> {
  /// Tests override this with fakes.
  ClientFactoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'clientFactoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$clientFactoryHash();

  @$internal
  @override
  $ProviderElement<MatrixClientFactory> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  MatrixClientFactory create(Ref ref) {
    return clientFactory(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MatrixClientFactory value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MatrixClientFactory>(value),
    );
  }
}

String _$clientFactoryHash() => r'faa6039222f420e578c1d1d8b6803a0a4ac54181';

/// What the login form suggests.

@ProviderFor(defaultServer)
final defaultServerProvider = DefaultServerProvider._();

/// What the login form suggests.

final class DefaultServerProvider
    extends $FunctionalProvider<String, String, String>
    with $Provider<String> {
  /// What the login form suggests.
  DefaultServerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'defaultServerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$defaultServerHash();

  @$internal
  @override
  $ProviderElement<String> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  String create(Ref ref) {
    return defaultServer(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String>(value),
    );
  }
}

String _$defaultServerHash() => r'87c06ddbf7a0996cbee9c7cdafaf646fde203c47';

/// The logged-in session, or `null` when logged out. Starts by restoring a saved session.

@ProviderFor(Auth)
final authProvider = AuthProvider._();

/// The logged-in session, or `null` when logged out. Starts by restoring a saved session.
final class AuthProvider extends $AsyncNotifierProvider<Auth, MatrixSession?> {
  /// The logged-in session, or `null` when logged out. Starts by restoring a saved session.
  AuthProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'authProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$authHash();

  @$internal
  @override
  Auth create() => Auth();
}

String _$authHash() => r'95eedfd341dd36f158ed2e1bdb090dc13fc886d6';

/// The logged-in session, or `null` when logged out. Starts by restoring a saved session.

abstract class _$Auth extends $AsyncNotifier<MatrixSession?> {
  FutureOr<MatrixSession?> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<MatrixSession?>, MatrixSession?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<MatrixSession?>, MatrixSession?>,
              AsyncValue<MatrixSession?>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(syncStatus)
final syncStatusProvider = SyncStatusProvider._();

final class SyncStatusProvider
    extends
        $FunctionalProvider<
          AsyncValue<SyncStatus>,
          SyncStatus,
          Stream<SyncStatus>
        >
    with $FutureModifier<SyncStatus>, $StreamProvider<SyncStatus> {
  SyncStatusProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'syncStatusProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$syncStatusHash();

  @$internal
  @override
  $StreamProviderElement<SyncStatus> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<SyncStatus> create(Ref ref) {
    return syncStatus(ref);
  }
}

String _$syncStatusHash() => r'68729a0c736199ae1176dca42681965bae9795a3';

/// This device's verification status; [VerificationStatus.unknown] while logged out.

@ProviderFor(verificationStatus)
final verificationStatusProvider = VerificationStatusProvider._();

/// This device's verification status; [VerificationStatus.unknown] while logged out.

final class VerificationStatusProvider
    extends
        $FunctionalProvider<
          AsyncValue<VerificationStatus>,
          VerificationStatus,
          Stream<VerificationStatus>
        >
    with
        $FutureModifier<VerificationStatus>,
        $StreamProvider<VerificationStatus> {
  /// This device's verification status; [VerificationStatus.unknown] while logged out.
  VerificationStatusProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'verificationStatusProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$verificationStatusHash();

  @$internal
  @override
  $StreamProviderElement<VerificationStatus> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<VerificationStatus> create(Ref ref) {
    return verificationStatus(ref);
  }
}

String _$verificationStatusHash() =>
    r'6c4d4db979323984e4fcd85d6a5359700dc9a7f0';

@ProviderFor(verificationRequests)
final verificationRequestsProvider = VerificationRequestsProvider._();

final class VerificationRequestsProvider
    extends
        $FunctionalProvider<
          AsyncValue<VerificationRequest>,
          VerificationRequest,
          Stream<VerificationRequest>
        >
    with
        $FutureModifier<VerificationRequest>,
        $StreamProvider<VerificationRequest> {
  VerificationRequestsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'verificationRequestsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$verificationRequestsHash();

  @$internal
  @override
  $StreamProviderElement<VerificationRequest> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<VerificationRequest> create(Ref ref) {
    return verificationRequests(ref);
  }
}

String _$verificationRequestsHash() =>
    r'0c6cc48cfe941fd3c419e7f433d03c61de8e8014';

/// `null` until the first room list has arrived.

@ProviderFor(rooms)
final roomsProvider = RoomsProvider._();

/// `null` until the first room list has arrived.

final class RoomsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Room>?>,
          List<Room>?,
          Stream<List<Room>?>
        >
    with $FutureModifier<List<Room>?>, $StreamProvider<List<Room>?> {
  /// `null` until the first room list has arrived.
  RoomsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'roomsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$roomsHash();

  @$internal
  @override
  $StreamProviderElement<List<Room>?> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<Room>?> create(Ref ref) {
    return rooms(ref);
  }
}

String _$roomsHash() => r'48867a01740bdf5d0a6761e6169052bf0e00408d';

@ProviderFor(roomTimeline)
final roomTimelineProvider = RoomTimelineFamily._();

final class RoomTimelineProvider
    extends
        $FunctionalProvider<
          AsyncValue<RoomTimeline>,
          RoomTimeline,
          FutureOr<RoomTimeline>
        >
    with $FutureModifier<RoomTimeline>, $FutureProvider<RoomTimeline> {
  RoomTimelineProvider._({
    required RoomTimelineFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'roomTimelineProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$roomTimelineHash();

  @override
  String toString() {
    return r'roomTimelineProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<RoomTimeline> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<RoomTimeline> create(Ref ref) {
    final argument = this.argument as String;
    return roomTimeline(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is RoomTimelineProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$roomTimelineHash() => r'1102e04b5d312e12fc10cc28d1b36e12d1ae755a';

final class RoomTimelineFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<RoomTimeline>, String> {
  RoomTimelineFamily._()
    : super(
        retry: null,
        name: r'roomTimelineProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  RoomTimelineProvider call(String roomId) =>
      RoomTimelineProvider._(argument: roomId, from: this);

  @override
  String toString() => r'roomTimelineProvider';
}

/// Follows the timeline's state rather than awaiting its `future`: a logout disposes both
/// while the timeline may still be opening, and an awaited `future` then fails unhandled.

@ProviderFor(timelineEntries)
final timelineEntriesProvider = TimelineEntriesFamily._();

/// Follows the timeline's state rather than awaiting its `future`: a logout disposes both
/// while the timeline may still be opening, and an awaited `future` then fails unhandled.

final class TimelineEntriesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<TimelineEntry>>,
          List<TimelineEntry>,
          Stream<List<TimelineEntry>>
        >
    with
        $FutureModifier<List<TimelineEntry>>,
        $StreamProvider<List<TimelineEntry>> {
  /// Follows the timeline's state rather than awaiting its `future`: a logout disposes both
  /// while the timeline may still be opening, and an awaited `future` then fails unhandled.
  TimelineEntriesProvider._({
    required TimelineEntriesFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'timelineEntriesProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$timelineEntriesHash();

  @override
  String toString() {
    return r'timelineEntriesProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<List<TimelineEntry>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<TimelineEntry>> create(Ref ref) {
    final argument = this.argument as String;
    return timelineEntries(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is TimelineEntriesProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$timelineEntriesHash() => r'9a6acb081525cdedbff53521af8e3495ad62d347';

/// Follows the timeline's state rather than awaiting its `future`: a logout disposes both
/// while the timeline may still be opening, and an awaited `future` then fails unhandled.

final class TimelineEntriesFamily extends $Family
    with $FunctionalFamilyOverride<Stream<List<TimelineEntry>>, String> {
  TimelineEntriesFamily._()
    : super(
        retry: null,
        name: r'timelineEntriesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Follows the timeline's state rather than awaiting its `future`: a logout disposes both
  /// while the timeline may still be opening, and an awaited `future` then fails unhandled.

  TimelineEntriesProvider call(String roomId) =>
      TimelineEntriesProvider._(argument: roomId, from: this);

  @override
  String toString() => r'timelineEntriesProvider';
}
