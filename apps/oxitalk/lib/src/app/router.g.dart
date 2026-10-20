// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'router.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The active account's verification status, which decides whether it sees its chats.

@ProviderFor(activeVerification)
final activeVerificationProvider = ActiveVerificationProvider._();

/// The active account's verification status, which decides whether it sees its chats.

final class ActiveVerificationProvider
    extends
        $FunctionalProvider<
          VerificationStatus,
          VerificationStatus,
          VerificationStatus
        >
    with $Provider<VerificationStatus> {
  /// The active account's verification status, which decides whether it sees its chats.
  ActiveVerificationProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'activeVerificationProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$activeVerificationHash();

  @$internal
  @override
  $ProviderElement<VerificationStatus> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  VerificationStatus create(Ref ref) {
    return activeVerification(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(VerificationStatus value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<VerificationStatus>(value),
    );
  }
}

String _$activeVerificationHash() =>
    r'fb90bcb01c4fec320b60b101719c12143933adc9';

@ProviderFor(router)
final routerProvider = RouterProvider._();

final class RouterProvider
    extends $FunctionalProvider<GoRouter, GoRouter, GoRouter>
    with $Provider<GoRouter> {
  RouterProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'routerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$routerHash();

  @$internal
  @override
  $ProviderElement<GoRouter> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  GoRouter create(Ref ref) {
    return router(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(GoRouter value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<GoRouter>(value),
    );
  }
}

String _$routerHash() => r'77420fa3d837f2449dcf6ac7f314f999d658a136';
