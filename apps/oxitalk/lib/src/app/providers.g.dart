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

/// The accounts. Starts by restoring the saved ones; all of them sync all the time.

@ProviderFor(Accounts)
final accountsProvider = AccountsProvider._();

/// The accounts. Starts by restoring the saved ones; all of them sync all the time.
final class AccountsProvider
    extends $AsyncNotifierProvider<Accounts, AccountsState> {
  /// The accounts. Starts by restoring the saved ones; all of them sync all the time.
  AccountsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'accountsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$accountsHash();

  @$internal
  @override
  Accounts create() => Accounts();
}

String _$accountsHash() => r'88e7bc18e8f3b110f2097d4dd7a2a3eb56fdb4a9';

/// The accounts. Starts by restoring the saved ones; all of them sync all the time.

abstract class _$Accounts extends $AsyncNotifier<AccountsState> {
  FutureOr<AccountsState> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<AccountsState>, AccountsState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<AccountsState>, AccountsState>,
              AsyncValue<AccountsState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// The user ID of the account in front, or `null` when there are none.

@ProviderFor(activeAccount)
final activeAccountProvider = ActiveAccountProvider._();

/// The user ID of the account in front, or `null` when there are none.

final class ActiveAccountProvider
    extends $FunctionalProvider<String?, String?, String?>
    with $Provider<String?> {
  /// The user ID of the account in front, or `null` when there are none.
  ActiveAccountProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'activeAccountProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$activeAccountHash();

  @$internal
  @override
  $ProviderElement<String?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  String? create(Ref ref) {
    return activeAccount(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String?>(value),
    );
  }
}

String _$activeAccountHash() => r'6e1641153bbe8c536d7a9a8bf88892b9add5de52';

@ProviderFor(syncStatus)
final syncStatusProvider = SyncStatusFamily._();

final class SyncStatusProvider
    extends
        $FunctionalProvider<
          AsyncValue<SyncStatus>,
          SyncStatus,
          Stream<SyncStatus>
        >
    with $FutureModifier<SyncStatus>, $StreamProvider<SyncStatus> {
  SyncStatusProvider._({
    required SyncStatusFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'syncStatusProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$syncStatusHash();

  @override
  String toString() {
    return r'syncStatusProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<SyncStatus> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<SyncStatus> create(Ref ref) {
    final argument = this.argument as String;
    return syncStatus(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is SyncStatusProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$syncStatusHash() => r'987fdbdba3f33203be123d96e148e4e68e12a7fd';

final class SyncStatusFamily extends $Family
    with $FunctionalFamilyOverride<Stream<SyncStatus>, String> {
  SyncStatusFamily._()
    : super(
        retry: null,
        name: r'syncStatusProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  SyncStatusProvider call(String account) =>
      SyncStatusProvider._(argument: account, from: this);

  @override
  String toString() => r'syncStatusProvider';
}

/// The account's verification status; [VerificationStatus.unknown] once it is gone.

@ProviderFor(verificationStatus)
final verificationStatusProvider = VerificationStatusFamily._();

/// The account's verification status; [VerificationStatus.unknown] once it is gone.

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
  /// The account's verification status; [VerificationStatus.unknown] once it is gone.
  VerificationStatusProvider._({
    required VerificationStatusFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'verificationStatusProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$verificationStatusHash();

  @override
  String toString() {
    return r'verificationStatusProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<VerificationStatus> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<VerificationStatus> create(Ref ref) {
    final argument = this.argument as String;
    return verificationStatus(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is VerificationStatusProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$verificationStatusHash() =>
    r'8dbe39669d1f5f03329730a604c1143114ee8b42';

/// The account's verification status; [VerificationStatus.unknown] once it is gone.

final class VerificationStatusFamily extends $Family
    with $FunctionalFamilyOverride<Stream<VerificationStatus>, String> {
  VerificationStatusFamily._()
    : super(
        retry: null,
        name: r'verificationStatusProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The account's verification status; [VerificationStatus.unknown] once it is gone.

  VerificationStatusProvider call(String account) =>
      VerificationStatusProvider._(argument: account, from: this);

  @override
  String toString() => r'verificationStatusProvider';
}

@ProviderFor(verificationRequests)
final verificationRequestsProvider = VerificationRequestsFamily._();

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
  VerificationRequestsProvider._({
    required VerificationRequestsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'verificationRequestsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$verificationRequestsHash();

  @override
  String toString() {
    return r'verificationRequestsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<VerificationRequest> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<VerificationRequest> create(Ref ref) {
    final argument = this.argument as String;
    return verificationRequests(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is VerificationRequestsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$verificationRequestsHash() =>
    r'267a100b872cf1f50537d3675b2b3d1ebf4fd9b5';

final class VerificationRequestsFamily extends $Family
    with $FunctionalFamilyOverride<Stream<VerificationRequest>, String> {
  VerificationRequestsFamily._()
    : super(
        retry: null,
        name: r'verificationRequestsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  VerificationRequestsProvider call(String account) =>
      VerificationRequestsProvider._(argument: account, from: this);

  @override
  String toString() => r'verificationRequestsProvider';
}

/// `null` until the first room list has arrived.

@ProviderFor(rooms)
final roomsProvider = RoomsFamily._();

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
  RoomsProvider._({
    required RoomsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'roomsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$roomsHash();

  @override
  String toString() {
    return r'roomsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<List<Room>?> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<Room>?> create(Ref ref) {
    final argument = this.argument as String;
    return rooms(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is RoomsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$roomsHash() => r'479c67cde191bbbd4c6eaa4512f17ca53ddf0471';

/// `null` until the first room list has arrived.

final class RoomsFamily extends $Family
    with $FunctionalFamilyOverride<Stream<List<Room>?>, String> {
  RoomsFamily._()
    : super(
        retry: null,
        name: r'roomsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// `null` until the first room list has arrived.

  RoomsProvider call(String account) =>
      RoomsProvider._(argument: account, from: this);

  @override
  String toString() => r'roomsProvider';
}

/// What the account switcher shows: unread messages plus invites.

@ProviderFor(unreadCount)
final unreadCountProvider = UnreadCountFamily._();

/// What the account switcher shows: unread messages plus invites.

final class UnreadCountProvider extends $FunctionalProvider<int, int, int>
    with $Provider<int> {
  /// What the account switcher shows: unread messages plus invites.
  UnreadCountProvider._({
    required UnreadCountFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'unreadCountProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$unreadCountHash();

  @override
  String toString() {
    return r'unreadCountProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<int> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  int create(Ref ref) {
    final argument = this.argument as String;
    return unreadCount(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<int>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is UnreadCountProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$unreadCountHash() => r'cd69ef890e31b24c72de8cf1dbe614c5a74b865e';

/// What the account switcher shows: unread messages plus invites.

final class UnreadCountFamily extends $Family
    with $FunctionalFamilyOverride<int, String> {
  UnreadCountFamily._()
    : super(
        retry: null,
        name: r'unreadCountProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// What the account switcher shows: unread messages plus invites.

  UnreadCountProvider call(String account) =>
      UnreadCountProvider._(argument: account, from: this);

  @override
  String toString() => r'unreadCountProvider';
}

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
    required (String, String) super.argument,
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
    return roomTimeline(ref, argument.$1, argument.$2);
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

String _$roomTimelineHash() => r'4a7425da15aba5d756162c8189ecd6edf2b1d9ed';

final class RoomTimelineFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<RoomTimeline>, (String, String)> {
  RoomTimelineFamily._()
    : super(
        retry: null,
        name: r'roomTimelineProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  RoomTimelineProvider call(String account, String roomId) =>
      RoomTimelineProvider._(argument: (account, roomId), from: this);

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
    required (String, String) super.argument,
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
    return timelineEntries(ref, argument.$1, argument.$2);
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

String _$timelineEntriesHash() => r'0e3e705846fbf510e05fdc3450105e0924e33af3';

/// Follows the timeline's state rather than awaiting its `future`: a logout disposes both
/// while the timeline may still be opening, and an awaited `future` then fails unhandled.

final class TimelineEntriesFamily extends $Family
    with
        $FunctionalFamilyOverride<
          Stream<List<TimelineEntry>>,
          (String, String)
        > {
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

  TimelineEntriesProvider call(String account, String roomId) =>
      TimelineEntriesProvider._(argument: (account, roomId), from: this);

  @override
  String toString() => r'timelineEntriesProvider';
}
