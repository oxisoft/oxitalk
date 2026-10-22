// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'about_screen.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The core's version, which is the app's, with the build number once it is read.

@ProviderFor(appVersion)
final appVersionProvider = AppVersionProvider._();

/// The core's version, which is the app's, with the build number once it is read.

final class AppVersionProvider
    extends $FunctionalProvider<AppVersion, AppVersion, AppVersion>
    with $Provider<AppVersion> {
  /// The core's version, which is the app's, with the build number once it is read.
  AppVersionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appVersionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appVersionHash();

  @$internal
  @override
  $ProviderElement<AppVersion> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  AppVersion create(Ref ref) {
    return appVersion(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AppVersion value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AppVersion>(value),
    );
  }
}

String _$appVersionHash() => r'56fd761ca9bdabe31471592fcecf8a731483c868';

/// The build number, where the build bundles it: Linux and web builds have it in
/// `version.json` (the other platforms would need a plugin); `null` elsewhere.

@ProviderFor(appBuild)
final appBuildProvider = AppBuildProvider._();

/// The build number, where the build bundles it: Linux and web builds have it in
/// `version.json` (the other platforms would need a plugin); `null` elsewhere.

final class AppBuildProvider
    extends $FunctionalProvider<AsyncValue<String?>, String?, FutureOr<String?>>
    with $FutureModifier<String?>, $FutureProvider<String?> {
  /// The build number, where the build bundles it: Linux and web builds have it in
  /// `version.json` (the other platforms would need a plugin); `null` elsewhere.
  AppBuildProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appBuildProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appBuildHash();

  @$internal
  @override
  $FutureProviderElement<String?> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<String?> create(Ref ref) {
    return appBuild(ref);
  }
}

String _$appBuildHash() => r'61236fe629ece4a418eb3d302ea69a3ddbdd5ae6';
