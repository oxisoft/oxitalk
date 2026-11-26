// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'about_screen.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The app's version as the platform's bundle has it (Info.plist, the APK, the Windows
/// resources, Linux's version.json), and the core's.

@ProviderFor(appVersion)
final appVersionProvider = AppVersionProvider._();

/// The app's version as the platform's bundle has it (Info.plist, the APK, the Windows
/// resources, Linux's version.json), and the core's.

final class AppVersionProvider
    extends
        $FunctionalProvider<
          AsyncValue<AppVersion>,
          AppVersion,
          FutureOr<AppVersion>
        >
    with $FutureModifier<AppVersion>, $FutureProvider<AppVersion> {
  /// The app's version as the platform's bundle has it (Info.plist, the APK, the Windows
  /// resources, Linux's version.json), and the core's.
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
  $FutureProviderElement<AppVersion> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<AppVersion> create(Ref ref) {
    return appVersion(ref);
  }
}

String _$appVersionHash() => r'f75aa47a78cf420bf35908910db8d5367cbfd713';
