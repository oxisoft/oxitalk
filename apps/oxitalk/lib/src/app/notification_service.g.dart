// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'notification_service.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Tests override this; the real one talks to the OS.

@ProviderFor(notificationPresenter)
final notificationPresenterProvider = NotificationPresenterProvider._();

/// Tests override this; the real one talks to the OS.

final class NotificationPresenterProvider
    extends
        $FunctionalProvider<
          NotificationPresenter,
          NotificationPresenter,
          NotificationPresenter
        >
    with $Provider<NotificationPresenter> {
  /// Tests override this; the real one talks to the OS.
  NotificationPresenterProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'notificationPresenterProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$notificationPresenterHash();

  @$internal
  @override
  $ProviderElement<NotificationPresenter> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  NotificationPresenter create(Ref ref) {
    return notificationPresenter(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(NotificationPresenter value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<NotificationPresenter>(value),
    );
  }
}

String _$notificationPresenterHash() =>
    r'cae3d80fe2016741078097536b86ec28e09d012e';

/// This device's notification settings.

@ProviderFor(DeviceNotifications)
final deviceNotificationsProvider = DeviceNotificationsProvider._();

/// This device's notification settings.
final class DeviceNotificationsProvider
    extends $NotifierProvider<DeviceNotifications, DeviceNotificationPrefs> {
  /// This device's notification settings.
  DeviceNotificationsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'deviceNotificationsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$deviceNotificationsHash();

  @$internal
  @override
  DeviceNotifications create() => DeviceNotifications();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DeviceNotificationPrefs value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DeviceNotificationPrefs>(value),
    );
  }
}

String _$deviceNotificationsHash() =>
    r'91d80191247794d854c07a8f372ded5be45e4a36';

/// This device's notification settings.

abstract class _$DeviceNotifications
    extends $Notifier<DeviceNotificationPrefs> {
  DeviceNotificationPrefs build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<DeviceNotificationPrefs, DeviceNotificationPrefs>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<DeviceNotificationPrefs, DeviceNotificationPrefs>,
              DeviceNotificationPrefs,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// Whether the app's window has the focus (on phones: the app is in front).

@ProviderFor(WindowFocused)
final windowFocusedProvider = WindowFocusedProvider._();

/// Whether the app's window has the focus (on phones: the app is in front).
final class WindowFocusedProvider
    extends $NotifierProvider<WindowFocused, bool> {
  /// Whether the app's window has the focus (on phones: the app is in front).
  WindowFocusedProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'windowFocusedProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$windowFocusedHash();

  @$internal
  @override
  WindowFocused create() => WindowFocused();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$windowFocusedHash() => r'963b30d0d5be746c68ae9a62b87688869100ab57';

/// Whether the app's window has the focus (on phones: the app is in front).

abstract class _$WindowFocused extends $Notifier<bool> {
  bool build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<bool, bool>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<bool, bool>,
              bool,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// Runs every account's [AccountNotifications] and the app badge; a tap opens the account,
/// room and thread.

@ProviderFor(notificationCoordinator)
final notificationCoordinatorProvider = NotificationCoordinatorProvider._();

/// Runs every account's [AccountNotifications] and the app badge; a tap opens the account,
/// room and thread.

final class NotificationCoordinatorProvider
    extends
        $FunctionalProvider<
          NotificationCoordinator,
          NotificationCoordinator,
          NotificationCoordinator
        >
    with $Provider<NotificationCoordinator> {
  /// Runs every account's [AccountNotifications] and the app badge; a tap opens the account,
  /// room and thread.
  NotificationCoordinatorProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'notificationCoordinatorProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$notificationCoordinatorHash();

  @$internal
  @override
  $ProviderElement<NotificationCoordinator> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  NotificationCoordinator create(Ref ref) {
    return notificationCoordinator(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(NotificationCoordinator value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<NotificationCoordinator>(value),
    );
  }
}

String _$notificationCoordinatorHash() =>
    r'fc6247a169a26041e10a8e2ebe0f58035a6f2949';
