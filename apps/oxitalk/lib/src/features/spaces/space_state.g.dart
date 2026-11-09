// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'space_state.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// [account]'s top-level joined spaces, in Element's order; `null` until first read.

@ProviderFor(spaces)
final spacesProvider = SpacesFamily._();

/// [account]'s top-level joined spaces, in Element's order; `null` until first read.

final class SpacesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Space>?>,
          List<Space>?,
          Stream<List<Space>?>
        >
    with $FutureModifier<List<Space>?>, $StreamProvider<List<Space>?> {
  /// [account]'s top-level joined spaces, in Element's order; `null` until first read.
  SpacesProvider._({
    required SpacesFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'spacesProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$spacesHash();

  @override
  String toString() {
    return r'spacesProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<List<Space>?> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<Space>?> create(Ref ref) {
    final argument = this.argument as String;
    return spaces(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is SpacesProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$spacesHash() => r'8484663989bb5fc457dbb93799dc06cadb32b8ca';

/// [account]'s top-level joined spaces, in Element's order; `null` until first read.

final class SpacesFamily extends $Family
    with $FunctionalFamilyOverride<Stream<List<Space>?>, String> {
  SpacesFamily._()
    : super(
        retry: null,
        name: r'spacesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// [account]'s top-level joined spaces, in Element's order; `null` until first read.

  SpacesProvider call(String account) =>
      SpacesProvider._(argument: account, from: this);

  @override
  String toString() => r'spacesProvider';
}

/// The space [account]'s chat list shows (its ID), or `null` for all chats. Kept per
/// account on this device. A space the user leaves, or is removed from, falls back to all
/// chats.

@ProviderFor(SelectedSpace)
final selectedSpaceProvider = SelectedSpaceFamily._();

/// The space [account]'s chat list shows (its ID), or `null` for all chats. Kept per
/// account on this device. A space the user leaves, or is removed from, falls back to all
/// chats.
final class SelectedSpaceProvider
    extends $NotifierProvider<SelectedSpace, String?> {
  /// The space [account]'s chat list shows (its ID), or `null` for all chats. Kept per
  /// account on this device. A space the user leaves, or is removed from, falls back to all
  /// chats.
  SelectedSpaceProvider._({
    required SelectedSpaceFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'selectedSpaceProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$selectedSpaceHash();

  @override
  String toString() {
    return r'selectedSpaceProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  SelectedSpace create() => SelectedSpace();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SelectedSpaceProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$selectedSpaceHash() => r'45eacd42ae542127db65b46b6b32c5c78142b0fb';

/// The space [account]'s chat list shows (its ID), or `null` for all chats. Kept per
/// account on this device. A space the user leaves, or is removed from, falls back to all
/// chats.

final class SelectedSpaceFamily extends $Family
    with
        $ClassFamilyOverride<SelectedSpace, String?, String?, String?, String> {
  SelectedSpaceFamily._()
    : super(
        retry: null,
        name: r'selectedSpaceProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// The space [account]'s chat list shows (its ID), or `null` for all chats. Kept per
  /// account on this device. A space the user leaves, or is removed from, falls back to all
  /// chats.

  SelectedSpaceProvider call(String account) =>
      SelectedSpaceProvider._(argument: account, from: this);

  @override
  String toString() => r'selectedSpaceProvider';
}

/// The space [account]'s chat list shows (its ID), or `null` for all chats. Kept per
/// account on this device. A space the user leaves, or is removed from, falls back to all
/// chats.

abstract class _$SelectedSpace extends $Notifier<String?> {
  late final _$args = ref.$arg as String;
  String get account => _$args;

  String? build(String account);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<String?, String?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<String?, String?>,
              String?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// The space [account]'s list shows, once it is among the account's spaces; `null` for all
/// chats.

@ProviderFor(currentSpace)
final currentSpaceProvider = CurrentSpaceFamily._();

/// The space [account]'s list shows, once it is among the account's spaces; `null` for all
/// chats.

final class CurrentSpaceProvider
    extends $FunctionalProvider<Space?, Space?, Space?>
    with $Provider<Space?> {
  /// The space [account]'s list shows, once it is among the account's spaces; `null` for all
  /// chats.
  CurrentSpaceProvider._({
    required CurrentSpaceFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'currentSpaceProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$currentSpaceHash();

  @override
  String toString() {
    return r'currentSpaceProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<Space?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  Space? create(Ref ref) {
    final argument = this.argument as String;
    return currentSpace(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Space? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Space?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is CurrentSpaceProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$currentSpaceHash() => r'f20695100e2593993a3c810d641379cd631cb425';

/// The space [account]'s list shows, once it is among the account's spaces; `null` for all
/// chats.

final class CurrentSpaceFamily extends $Family
    with $FunctionalFamilyOverride<Space?, String> {
  CurrentSpaceFamily._()
    : super(
        retry: null,
        name: r'currentSpaceProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The space [account]'s list shows, once it is among the account's spaces; `null` for all
  /// chats.

  CurrentSpaceProvider call(String account) =>
      CurrentSpaceProvider._(argument: account, from: this);

  @override
  String toString() => r'currentSpaceProvider';
}

/// The chats [account]'s list shows: those of the current space, or all of them; `null`
/// until the room list is read.

@ProviderFor(visibleRooms)
final visibleRoomsProvider = VisibleRoomsFamily._();

/// The chats [account]'s list shows: those of the current space, or all of them; `null`
/// until the room list is read.

final class VisibleRoomsProvider
    extends $FunctionalProvider<List<Room>?, List<Room>?, List<Room>?>
    with $Provider<List<Room>?> {
  /// The chats [account]'s list shows: those of the current space, or all of them; `null`
  /// until the room list is read.
  VisibleRoomsProvider._({
    required VisibleRoomsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'visibleRoomsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$visibleRoomsHash();

  @override
  String toString() {
    return r'visibleRoomsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<List<Room>?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  List<Room>? create(Ref ref) {
    final argument = this.argument as String;
    return visibleRooms(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<Room>? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<Room>?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is VisibleRoomsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$visibleRoomsHash() => r'642946cfa41be27e44143a3db43b67f116ee4487';

/// The chats [account]'s list shows: those of the current space, or all of them; `null`
/// until the room list is read.

final class VisibleRoomsFamily extends $Family
    with $FunctionalFamilyOverride<List<Room>?, String> {
  VisibleRoomsFamily._()
    : super(
        retry: null,
        name: r'visibleRoomsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The chats [account]'s list shows: those of the current space, or all of them; `null`
  /// until the room list is read.

  VisibleRoomsProvider call(String account) =>
      VisibleRoomsProvider._(argument: account, from: this);

  @override
  String toString() => r'visibleRoomsProvider';
}

/// What a space's badge shows: its chats' notifying unread messages.

@ProviderFor(spaceBadge)
final spaceBadgeProvider = SpaceBadgeFamily._();

/// What a space's badge shows: its chats' notifying unread messages.

final class SpaceBadgeProvider
    extends $FunctionalProvider<RoomBadge, RoomBadge, RoomBadge>
    with $Provider<RoomBadge> {
  /// What a space's badge shows: its chats' notifying unread messages.
  SpaceBadgeProvider._({
    required SpaceBadgeFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'spaceBadgeProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$spaceBadgeHash();

  @override
  String toString() {
    return r'spaceBadgeProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $ProviderElement<RoomBadge> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  RoomBadge create(Ref ref) {
    final argument = this.argument as (String, String);
    return spaceBadge(ref, argument.$1, argument.$2);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RoomBadge value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RoomBadge>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SpaceBadgeProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$spaceBadgeHash() => r'65685a3a6a7399c2d80ab7f2bf8217a32cbe2f16';

/// What a space's badge shows: its chats' notifying unread messages.

final class SpaceBadgeFamily extends $Family
    with $FunctionalFamilyOverride<RoomBadge, (String, String)> {
  SpaceBadgeFamily._()
    : super(
        retry: null,
        name: r'spaceBadgeProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// What a space's badge shows: its chats' notifying unread messages.

  SpaceBadgeProvider call(String account, String spaceId) =>
      SpaceBadgeProvider._(argument: (account, spaceId), from: this);

  @override
  String toString() => r'spaceBadgeProvider';
}

/// Whether chats outside the current space have notifying unread messages (or invites):
/// the space selector shows a red dot then.

@ProviderFor(unreadOutsideSpace)
final unreadOutsideSpaceProvider = UnreadOutsideSpaceFamily._();

/// Whether chats outside the current space have notifying unread messages (or invites):
/// the space selector shows a red dot then.

final class UnreadOutsideSpaceProvider
    extends $FunctionalProvider<bool, bool, bool>
    with $Provider<bool> {
  /// Whether chats outside the current space have notifying unread messages (or invites):
  /// the space selector shows a red dot then.
  UnreadOutsideSpaceProvider._({
    required UnreadOutsideSpaceFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'unreadOutsideSpaceProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$unreadOutsideSpaceHash();

  @override
  String toString() {
    return r'unreadOutsideSpaceProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  bool create(Ref ref) {
    final argument = this.argument as String;
    return unreadOutsideSpace(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is UnreadOutsideSpaceProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$unreadOutsideSpaceHash() =>
    r'7b0e50d2013d3eb653283b2cd10a28e996fa9794';

/// Whether chats outside the current space have notifying unread messages (or invites):
/// the space selector shows a red dot then.

final class UnreadOutsideSpaceFamily extends $Family
    with $FunctionalFamilyOverride<bool, String> {
  UnreadOutsideSpaceFamily._()
    : super(
        retry: null,
        name: r'unreadOutsideSpaceProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Whether chats outside the current space have notifying unread messages (or invites):
  /// the space selector shows a red dot then.

  UnreadOutsideSpaceProvider call(String account) =>
      UnreadOutsideSpaceProvider._(argument: account, from: this);

  @override
  String toString() => r'unreadOutsideSpaceProvider';
}
