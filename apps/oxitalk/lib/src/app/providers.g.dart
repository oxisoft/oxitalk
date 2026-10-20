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

/// Set by `main` (and by tests): it is started before the app.

@ProviderFor(diagnostics)
final diagnosticsProvider = DiagnosticsProvider._();

/// Set by `main` (and by tests): it is started before the app.

final class DiagnosticsProvider
    extends $FunctionalProvider<Diagnostics, Diagnostics, Diagnostics>
    with $Provider<Diagnostics> {
  /// Set by `main` (and by tests): it is started before the app.
  DiagnosticsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'diagnosticsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$diagnosticsHash();

  @$internal
  @override
  $ProviderElement<Diagnostics> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  Diagnostics create(Ref ref) {
    return diagnostics(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Diagnostics value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Diagnostics>(value),
    );
  }
}

String _$diagnosticsHash() => r'748c8d8e39bccb5f5a046f3816c861999580ef47';

/// Set by `main` (and by tests), next to the app's other data.

@ProviderFor(accountPictures)
final accountPicturesProvider = AccountPicturesProvider._();

/// Set by `main` (and by tests), next to the app's other data.

final class AccountPicturesProvider
    extends
        $FunctionalProvider<AccountPictures, AccountPictures, AccountPictures>
    with $Provider<AccountPictures> {
  /// Set by `main` (and by tests), next to the app's other data.
  AccountPicturesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'accountPicturesProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$accountPicturesHash();

  @$internal
  @override
  $ProviderElement<AccountPictures> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  AccountPictures create(Ref ref) {
    return accountPictures(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AccountPictures value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AccountPictures>(value),
    );
  }
}

String _$accountPicturesHash() => r'dabfd006d018417ea32ec566486eb4b70dec098e';

/// Set by `main` (and by tests), next to the app's other data.

@ProviderFor(collapsedSectionsStore)
final collapsedSectionsStoreProvider = CollapsedSectionsStoreProvider._();

/// Set by `main` (and by tests), next to the app's other data.

final class CollapsedSectionsStoreProvider
    extends
        $FunctionalProvider<
          CollapsedSections,
          CollapsedSections,
          CollapsedSections
        >
    with $Provider<CollapsedSections> {
  /// Set by `main` (and by tests), next to the app's other data.
  CollapsedSectionsStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'collapsedSectionsStoreProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$collapsedSectionsStoreHash();

  @$internal
  @override
  $ProviderElement<CollapsedSections> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  CollapsedSections create(Ref ref) {
    return collapsedSectionsStore(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CollapsedSections value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CollapsedSections>(value),
    );
  }
}

String _$collapsedSectionsStoreHash() =>
    r'0dfdf980ba74e5b8a7587e9092e8d69bc6a05120';

/// Tests override this; there is no file dialog in a test.

@ProviderFor(pickImage)
final pickImageProvider = PickImageProvider._();

/// Tests override this; there is no file dialog in a test.

final class PickImageProvider
    extends $FunctionalProvider<PickImage, PickImage, PickImage>
    with $Provider<PickImage> {
  /// Tests override this; there is no file dialog in a test.
  PickImageProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'pickImageProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$pickImageHash();

  @$internal
  @override
  $ProviderElement<PickImage> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  PickImage create(Ref ref) {
    return pickImage(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PickImage value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PickImage>(value),
    );
  }
}

String _$pickImageHash() => r'd8c8d529428e93da90f3903ecdcc1306cc3492fe';

/// Set by `main` (and by tests), next to the app's other data.

@ProviderFor(uiPrefs)
final uiPrefsProvider = UiPrefsProvider._();

/// Set by `main` (and by tests), next to the app's other data.

final class UiPrefsProvider
    extends $FunctionalProvider<UiPrefs, UiPrefs, UiPrefs>
    with $Provider<UiPrefs> {
  /// Set by `main` (and by tests), next to the app's other data.
  UiPrefsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'uiPrefsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$uiPrefsHash();

  @$internal
  @override
  $ProviderElement<UiPrefs> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  UiPrefs create(Ref ref) {
    return uiPrefs(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(UiPrefs value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<UiPrefs>(value),
    );
  }
}

String _$uiPrefsHash() => r'e6b1ef2897799025e1ddca5fa35cfee69d3eb77c';

/// Whether the chat list is narrowed to pictures and short names.

@ProviderFor(NarrowList)
final narrowListProvider = NarrowListProvider._();

/// Whether the chat list is narrowed to pictures and short names.
final class NarrowListProvider extends $NotifierProvider<NarrowList, bool> {
  /// Whether the chat list is narrowed to pictures and short names.
  NarrowListProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'narrowListProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$narrowListHash();

  @$internal
  @override
  NarrowList create() => NarrowList();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$narrowListHash() => r'a845f7a9f19625e5fe2bb3a4eab8832838cd736c';

/// Whether the chat list is narrowed to pictures and short names.

abstract class _$NarrowList extends $Notifier<bool> {
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

/// Whether the account rail is hidden.

@ProviderFor(RailHidden)
final railHiddenProvider = RailHiddenProvider._();

/// Whether the account rail is hidden.
final class RailHiddenProvider extends $NotifierProvider<RailHidden, bool> {
  /// Whether the account rail is hidden.
  RailHiddenProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'railHiddenProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$railHiddenHash();

  @$internal
  @override
  RailHidden create() => RailHidden();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$railHiddenHash() => r'afde9cef7393203d2a851e7379701218314a6223';

/// Whether the account rail is hidden.

abstract class _$RailHidden extends $Notifier<bool> {
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

/// Whether messages are sent formatted from their markdown, as Element sends them.

@ProviderFor(UseMarkdown)
final useMarkdownProvider = UseMarkdownProvider._();

/// Whether messages are sent formatted from their markdown, as Element sends them.
final class UseMarkdownProvider extends $NotifierProvider<UseMarkdown, bool> {
  /// Whether messages are sent formatted from their markdown, as Element sends them.
  UseMarkdownProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'useMarkdownProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$useMarkdownHash();

  @$internal
  @override
  UseMarkdown create() => UseMarkdown();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$useMarkdownHash() => r'4ba820f57ca3b191e9f1394b28d67d500c5e3b59';

/// Whether messages are sent formatted from their markdown, as Element sends them.

abstract class _$UseMarkdown extends $Notifier<bool> {
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

/// `main` sets the real window; tests and phones have none of the app's own.

@ProviderFor(windowControls)
final windowControlsProvider = WindowControlsProvider._();

/// `main` sets the real window; tests and phones have none of the app's own.

final class WindowControlsProvider
    extends $FunctionalProvider<WindowControls, WindowControls, WindowControls>
    with $Provider<WindowControls> {
  /// `main` sets the real window; tests and phones have none of the app's own.
  WindowControlsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'windowControlsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$windowControlsHash();

  @$internal
  @override
  $ProviderElement<WindowControls> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  WindowControls create(Ref ref) {
    return windowControls(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(WindowControls value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<WindowControls>(value),
    );
  }
}

String _$windowControlsHash() => r'246db448059665fbaf7cde179475521ceecc96bb';

/// Set by `main` (and by tests), next to the app's other data.

@ProviderFor(mediaPrefs)
final mediaPrefsProvider = MediaPrefsProvider._();

/// Set by `main` (and by tests), next to the app's other data.

final class MediaPrefsProvider
    extends $FunctionalProvider<MediaPrefs, MediaPrefs, MediaPrefs>
    with $Provider<MediaPrefs> {
  /// Set by `main` (and by tests), next to the app's other data.
  MediaPrefsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'mediaPrefsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$mediaPrefsHash();

  @$internal
  @override
  $ProviderElement<MediaPrefs> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  MediaPrefs create(Ref ref) {
    return mediaPrefs(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MediaPrefs value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MediaPrefs>(value),
    );
  }
}

String _$mediaPrefsHash() => r'65d023d886efd66c1f355c76e7dd14f74cb273cc';

/// Tests override this: no file dialogs or other apps in a test.

@ProviderFor(fileActions)
final fileActionsProvider = FileActionsProvider._();

/// Tests override this: no file dialogs or other apps in a test.

final class FileActionsProvider
    extends $FunctionalProvider<FileActions, FileActions, FileActions>
    with $Provider<FileActions> {
  /// Tests override this: no file dialogs or other apps in a test.
  FileActionsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'fileActionsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$fileActionsHash();

  @$internal
  @override
  $ProviderElement<FileActions> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  FileActions create(Ref ref) {
    return fileActions(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(FileActions value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<FileActions>(value),
    );
  }
}

String _$fileActionsHash() => r'c270e8ecbb8d9ba4aa491959a66157880cb73109';

/// How long cached media is kept, in days (`null`: forever); applied to every account.

@ProviderFor(MediaRetention)
final mediaRetentionProvider = MediaRetentionProvider._();

/// How long cached media is kept, in days (`null`: forever); applied to every account.
final class MediaRetentionProvider
    extends $NotifierProvider<MediaRetention, int?> {
  /// How long cached media is kept, in days (`null`: forever); applied to every account.
  MediaRetentionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'mediaRetentionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$mediaRetentionHash();

  @$internal
  @override
  MediaRetention create() => MediaRetention();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<int?>(value),
    );
  }
}

String _$mediaRetentionHash() => r'a6e1416f61816c9faa032399e51df718c3c199c8';

/// How long cached media is kept, in days (`null`: forever); applied to every account.

abstract class _$MediaRetention extends $Notifier<int?> {
  int? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<int?, int?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<int?, int?>,
              int?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

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

String _$accountsHash() => r'4a28d736c01abe339e9d1bafaedf8314202903e6';

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

@ProviderFor(profile)
final profileProvider = ProfileFamily._();

final class ProfileProvider
    extends $FunctionalProvider<AsyncValue<Profile>, Profile, Stream<Profile>>
    with $FutureModifier<Profile>, $StreamProvider<Profile> {
  ProfileProvider._({
    required ProfileFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'profileProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$profileHash();

  @override
  String toString() {
    return r'profileProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<Profile> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<Profile> create(Ref ref) {
    final argument = this.argument as String;
    return profile(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ProfileProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$profileHash() => r'3103e9a1c0d9000b8338136774ca4f6c7c5c7600';

final class ProfileFamily extends $Family
    with $FunctionalFamilyOverride<Stream<Profile>, String> {
  ProfileFamily._()
    : super(
        retry: null,
        name: r'profileProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  ProfileProvider call(String account) =>
      ProfileProvider._(argument: account, from: this);

  @override
  String toString() => r'profileProvider';
}

/// The picture at [mxcUrl] (`mxc://`), as a thumbnail about [size] pixels wide. Kept once
/// loaded; a failed load is tried again the next time it is shown.

@ProviderFor(picture)
final pictureProvider = PictureFamily._();

/// The picture at [mxcUrl] (`mxc://`), as a thumbnail about [size] pixels wide. Kept once
/// loaded; a failed load is tried again the next time it is shown.

final class PictureProvider
    extends
        $FunctionalProvider<
          AsyncValue<Uint8List>,
          Uint8List,
          FutureOr<Uint8List>
        >
    with $FutureModifier<Uint8List>, $FutureProvider<Uint8List> {
  /// The picture at [mxcUrl] (`mxc://`), as a thumbnail about [size] pixels wide. Kept once
  /// loaded; a failed load is tried again the next time it is shown.
  PictureProvider._({
    required PictureFamily super.from,
    required (String, String, int) super.argument,
  }) : super(
         retry: null,
         name: r'pictureProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$pictureHash();

  @override
  String toString() {
    return r'pictureProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<Uint8List> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<Uint8List> create(Ref ref) {
    final argument = this.argument as (String, String, int);
    return picture(ref, argument.$1, argument.$2, argument.$3);
  }

  @override
  bool operator ==(Object other) {
    return other is PictureProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$pictureHash() => r'47d597f712858f678c0fa90437dae8a09a138e54';

/// The picture at [mxcUrl] (`mxc://`), as a thumbnail about [size] pixels wide. Kept once
/// loaded; a failed load is tried again the next time it is shown.

final class PictureFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<Uint8List>, (String, String, int)> {
  PictureFamily._()
    : super(
        retry: null,
        name: r'pictureProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The picture at [mxcUrl] (`mxc://`), as a thumbnail about [size] pixels wide. Kept once
  /// loaded; a failed load is tried again the next time it is shown.

  PictureProvider call(String account, String mxcUrl, int size) =>
      PictureProvider._(argument: (account, mxcUrl, size), from: this);

  @override
  String toString() => r'pictureProvider';
}

/// The picture the user picked for [account] on this device, if any.

@ProviderFor(localPicture)
final localPictureProvider = LocalPictureFamily._();

/// The picture the user picked for [account] on this device, if any.

final class LocalPictureProvider
    extends
        $FunctionalProvider<
          AsyncValue<Uint8List?>,
          Uint8List?,
          FutureOr<Uint8List?>
        >
    with $FutureModifier<Uint8List?>, $FutureProvider<Uint8List?> {
  /// The picture the user picked for [account] on this device, if any.
  LocalPictureProvider._({
    required LocalPictureFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'localPictureProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$localPictureHash();

  @override
  String toString() {
    return r'localPictureProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<Uint8List?> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<Uint8List?> create(Ref ref) {
    final argument = this.argument as String;
    return localPicture(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is LocalPictureProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$localPictureHash() => r'c4b9aaf0551ec5958739e4a8d9f478cec284942b';

/// The picture the user picked for [account] on this device, if any.

final class LocalPictureFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<Uint8List?>, String> {
  LocalPictureFamily._()
    : super(
        retry: null,
        name: r'localPictureProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The picture the user picked for [account] on this device, if any.

  LocalPictureProvider call(String account) =>
      LocalPictureProvider._(argument: account, from: this);

  @override
  String toString() => r'localPictureProvider';
}

/// The website icon of [server], if it has one.

@ProviderFor(serverIcon)
final serverIconProvider = ServerIconFamily._();

/// The website icon of [server], if it has one.

final class ServerIconProvider
    extends
        $FunctionalProvider<
          AsyncValue<Uint8List?>,
          Uint8List?,
          FutureOr<Uint8List?>
        >
    with $FutureModifier<Uint8List?>, $FutureProvider<Uint8List?> {
  /// The website icon of [server], if it has one.
  ServerIconProvider._({
    required ServerIconFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'serverIconProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$serverIconHash();

  @override
  String toString() {
    return r'serverIconProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<Uint8List?> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<Uint8List?> create(Ref ref) {
    final argument = this.argument as String;
    return serverIcon(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ServerIconProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$serverIconHash() => r'f788efeed269d86f2d6d64b07092f8d7667466af';

/// The website icon of [server], if it has one.

final class ServerIconFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<Uint8List?>, String> {
  ServerIconFamily._()
    : super(
        retry: null,
        name: r'serverIconProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// The website icon of [server], if it has one.

  ServerIconProvider call(String server) =>
      ServerIconProvider._(argument: server, from: this);

  @override
  String toString() => r'serverIconProvider';
}

@ProviderFor(sections)
final sectionsProvider = SectionsFamily._();

final class SectionsProvider
    extends
        $FunctionalProvider<AsyncValue<Sections>, Sections, Stream<Sections>>
    with $FutureModifier<Sections>, $StreamProvider<Sections> {
  SectionsProvider._({
    required SectionsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'sectionsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$sectionsHash();

  @override
  String toString() {
    return r'sectionsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<Sections> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<Sections> create(Ref ref) {
    final argument = this.argument as String;
    return sections(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is SectionsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$sectionsHash() => r'9fbcef995ac8f1bd167874ec1d216904218e3aaf';

final class SectionsFamily extends $Family
    with $FunctionalFamilyOverride<Stream<Sections>, String> {
  SectionsFamily._()
    : super(
        retry: null,
        name: r'sectionsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  SectionsProvider call(String account) =>
      SectionsProvider._(argument: account, from: this);

  @override
  String toString() => r'sectionsProvider';
}

/// The sections of [account]'s room list that the user folded.

@ProviderFor(CollapsedSectionTags)
final collapsedSectionTagsProvider = CollapsedSectionTagsFamily._();

/// The sections of [account]'s room list that the user folded.
final class CollapsedSectionTagsProvider
    extends $AsyncNotifierProvider<CollapsedSectionTags, Set<String>> {
  /// The sections of [account]'s room list that the user folded.
  CollapsedSectionTagsProvider._({
    required CollapsedSectionTagsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'collapsedSectionTagsProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$collapsedSectionTagsHash();

  @override
  String toString() {
    return r'collapsedSectionTagsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  CollapsedSectionTags create() => CollapsedSectionTags();

  @override
  bool operator ==(Object other) {
    return other is CollapsedSectionTagsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$collapsedSectionTagsHash() =>
    r'0b98b18d84c068fdfde1aea95a3d0023a3aa797d';

/// The sections of [account]'s room list that the user folded.

final class CollapsedSectionTagsFamily extends $Family
    with
        $ClassFamilyOverride<
          CollapsedSectionTags,
          AsyncValue<Set<String>>,
          Set<String>,
          FutureOr<Set<String>>,
          String
        > {
  CollapsedSectionTagsFamily._()
    : super(
        retry: null,
        name: r'collapsedSectionTagsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// The sections of [account]'s room list that the user folded.

  CollapsedSectionTagsProvider call(String account) =>
      CollapsedSectionTagsProvider._(argument: account, from: this);

  @override
  String toString() => r'collapsedSectionTagsProvider';
}

/// The sections of [account]'s room list that the user folded.

abstract class _$CollapsedSectionTags extends $AsyncNotifier<Set<String>> {
  late final _$args = ref.$arg as String;
  String get account => _$args;

  FutureOr<Set<String>> build(String account);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<Set<String>>, Set<String>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<Set<String>>, Set<String>>,
              AsyncValue<Set<String>>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// A picture of a message's file for showing it in the chat. Kept once loaded.

@ProviderFor(mediaThumbnail)
final mediaThumbnailProvider = MediaThumbnailFamily._();

/// A picture of a message's file for showing it in the chat. Kept once loaded.

final class MediaThumbnailProvider
    extends
        $FunctionalProvider<
          AsyncValue<Uint8List>,
          Uint8List,
          FutureOr<Uint8List>
        >
    with $FutureModifier<Uint8List>, $FutureProvider<Uint8List> {
  /// A picture of a message's file for showing it in the chat. Kept once loaded.
  MediaThumbnailProvider._({
    required MediaThumbnailFamily super.from,
    required (String, String, String?) super.argument,
  }) : super(
         retry: null,
         name: r'mediaThumbnailProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mediaThumbnailHash();

  @override
  String toString() {
    return r'mediaThumbnailProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<Uint8List> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<Uint8List> create(Ref ref) {
    final argument = this.argument as (String, String, String?);
    return mediaThumbnail(ref, argument.$1, argument.$2, argument.$3);
  }

  @override
  bool operator ==(Object other) {
    return other is MediaThumbnailProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mediaThumbnailHash() => r'2e9d6294823e2a510b12d40081523f5d80f8df45';

/// A picture of a message's file for showing it in the chat. Kept once loaded.

final class MediaThumbnailFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<Uint8List>,
          (String, String, String?)
        > {
  MediaThumbnailFamily._()
    : super(
        retry: null,
        name: r'mediaThumbnailProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// A picture of a message's file for showing it in the chat. Kept once loaded.

  MediaThumbnailProvider call(
    String account,
    String source,
    String? thumbnail,
  ) => MediaThumbnailProvider._(
    argument: (account, source, thumbnail),
    from: this,
  );

  @override
  String toString() => r'mediaThumbnailProvider';
}

/// A message's whole file, while something shows it.

@ProviderFor(mediaContent)
final mediaContentProvider = MediaContentFamily._();

/// A message's whole file, while something shows it.

final class MediaContentProvider
    extends
        $FunctionalProvider<
          AsyncValue<Uint8List>,
          Uint8List,
          FutureOr<Uint8List>
        >
    with $FutureModifier<Uint8List>, $FutureProvider<Uint8List> {
  /// A message's whole file, while something shows it.
  MediaContentProvider._({
    required MediaContentFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'mediaContentProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mediaContentHash();

  @override
  String toString() {
    return r'mediaContentProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<Uint8List> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<Uint8List> create(Ref ref) {
    final argument = this.argument as (String, String);
    return mediaContent(ref, argument.$1, argument.$2);
  }

  @override
  bool operator ==(Object other) {
    return other is MediaContentProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mediaContentHash() => r'a4afda7364212dea22c8a7f325fe96a3fad00901';

/// A message's whole file, while something shows it.

final class MediaContentFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<Uint8List>, (String, String)> {
  MediaContentFamily._()
    : super(
        retry: null,
        name: r'mediaContentProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// A message's whole file, while something shows it.

  MediaContentProvider call(String account, String source) =>
      MediaContentProvider._(argument: (account, source), from: this);

  @override
  String toString() => r'mediaContentProvider';
}

@ProviderFor(roomDetails)
final roomDetailsProvider = RoomDetailsFamily._();

final class RoomDetailsProvider
    extends
        $FunctionalProvider<
          AsyncValue<RoomDetails>,
          RoomDetails,
          FutureOr<RoomDetails>
        >
    with $FutureModifier<RoomDetails>, $FutureProvider<RoomDetails> {
  RoomDetailsProvider._({
    required RoomDetailsFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'roomDetailsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$roomDetailsHash();

  @override
  String toString() {
    return r'roomDetailsProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<RoomDetails> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<RoomDetails> create(Ref ref) {
    final argument = this.argument as (String, String);
    return roomDetails(ref, argument.$1, argument.$2);
  }

  @override
  bool operator ==(Object other) {
    return other is RoomDetailsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$roomDetailsHash() => r'95b145362bd09fcf759bc3865efa699e58df6a86';

final class RoomDetailsFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<RoomDetails>, (String, String)> {
  RoomDetailsFamily._()
    : super(
        retry: null,
        name: r'roomDetailsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  RoomDetailsProvider call(String account, String roomId) =>
      RoomDetailsProvider._(argument: (account, roomId), from: this);

  @override
  String toString() => r'roomDetailsProvider';
}

@ProviderFor(roomMembers)
final roomMembersProvider = RoomMembersFamily._();

final class RoomMembersProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<RoomMember>>,
          List<RoomMember>,
          FutureOr<List<RoomMember>>
        >
    with $FutureModifier<List<RoomMember>>, $FutureProvider<List<RoomMember>> {
  RoomMembersProvider._({
    required RoomMembersFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'roomMembersProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$roomMembersHash();

  @override
  String toString() {
    return r'roomMembersProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<List<RoomMember>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<RoomMember>> create(Ref ref) {
    final argument = this.argument as (String, String);
    return roomMembers(ref, argument.$1, argument.$2);
  }

  @override
  bool operator ==(Object other) {
    return other is RoomMembersProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$roomMembersHash() => r'822502e9721ea0928a1023118958c3309bdc6ac6';

final class RoomMembersFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<List<RoomMember>>,
          (String, String)
        > {
  RoomMembersFamily._()
    : super(
        retry: null,
        name: r'roomMembersProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  RoomMembersProvider call(String account, String roomId) =>
      RoomMembersProvider._(argument: (account, roomId), from: this);

  @override
  String toString() => r'roomMembersProvider';
}

/// The room's files and links, for its info screen; closed when no longer shown.

@ProviderFor(mediaTimeline)
final mediaTimelineProvider = MediaTimelineFamily._();

/// The room's files and links, for its info screen; closed when no longer shown.

final class MediaTimelineProvider
    extends
        $FunctionalProvider<
          AsyncValue<RoomTimeline>,
          RoomTimeline,
          FutureOr<RoomTimeline>
        >
    with $FutureModifier<RoomTimeline>, $FutureProvider<RoomTimeline> {
  /// The room's files and links, for its info screen; closed when no longer shown.
  MediaTimelineProvider._({
    required MediaTimelineFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'mediaTimelineProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mediaTimelineHash();

  @override
  String toString() {
    return r'mediaTimelineProvider'
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
    return mediaTimeline(ref, argument.$1, argument.$2);
  }

  @override
  bool operator ==(Object other) {
    return other is MediaTimelineProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mediaTimelineHash() => r'13caf66f2b7e3dad83e167f005ff11ff94b952b9';

/// The room's files and links, for its info screen; closed when no longer shown.

final class MediaTimelineFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<RoomTimeline>, (String, String)> {
  MediaTimelineFamily._()
    : super(
        retry: null,
        name: r'mediaTimelineProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The room's files and links, for its info screen; closed when no longer shown.

  MediaTimelineProvider call(String account, String roomId) =>
      MediaTimelineProvider._(argument: (account, roomId), from: this);

  @override
  String toString() => r'mediaTimelineProvider';
}

/// As [timelineEntries], for [mediaTimeline].

@ProviderFor(mediaTimelineEntries)
final mediaTimelineEntriesProvider = MediaTimelineEntriesFamily._();

/// As [timelineEntries], for [mediaTimeline].

final class MediaTimelineEntriesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<TimelineEntry>>,
          List<TimelineEntry>,
          Stream<List<TimelineEntry>>
        >
    with
        $FutureModifier<List<TimelineEntry>>,
        $StreamProvider<List<TimelineEntry>> {
  /// As [timelineEntries], for [mediaTimeline].
  MediaTimelineEntriesProvider._({
    required MediaTimelineEntriesFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'mediaTimelineEntriesProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mediaTimelineEntriesHash();

  @override
  String toString() {
    return r'mediaTimelineEntriesProvider'
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
    return mediaTimelineEntries(ref, argument.$1, argument.$2);
  }

  @override
  bool operator ==(Object other) {
    return other is MediaTimelineEntriesProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mediaTimelineEntriesHash() =>
    r'a0f7968fe974dca9de82311e6d0203ae26d7e3db';

/// As [timelineEntries], for [mediaTimeline].

final class MediaTimelineEntriesFamily extends $Family
    with
        $FunctionalFamilyOverride<
          Stream<List<TimelineEntry>>,
          (String, String)
        > {
  MediaTimelineEntriesFamily._()
    : super(
        retry: null,
        name: r'mediaTimelineEntriesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// As [timelineEntries], for [mediaTimeline].

  MediaTimelineEntriesProvider call(String account, String roomId) =>
      MediaTimelineEntriesProvider._(argument: (account, roomId), from: this);

  @override
  String toString() => r'mediaTimelineEntriesProvider';
}

/// The emojis the user used lately, the last first.

@ProviderFor(recentEmojis)
final recentEmojisProvider = RecentEmojisFamily._();

/// The emojis the user used lately, the last first.

final class RecentEmojisProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<String>>,
          List<String>,
          FutureOr<List<String>>
        >
    with $FutureModifier<List<String>>, $FutureProvider<List<String>> {
  /// The emojis the user used lately, the last first.
  RecentEmojisProvider._({
    required RecentEmojisFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'recentEmojisProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$recentEmojisHash();

  @override
  String toString() {
    return r'recentEmojisProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<List<String>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<String>> create(Ref ref) {
    final argument = this.argument as String;
    return recentEmojis(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is RecentEmojisProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$recentEmojisHash() => r'ce98fdbe05862de6c4d8f14e375ed057fd980128';

/// The emojis the user used lately, the last first.

final class RecentEmojisFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<List<String>>, String> {
  RecentEmojisFamily._()
    : super(
        retry: null,
        name: r'recentEmojisProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The emojis the user used lately, the last first.

  RecentEmojisProvider call(String account) =>
      RecentEmojisProvider._(argument: account, from: this);

  @override
  String toString() => r'recentEmojisProvider';
}

/// Whether the user may delete other people's messages in the room.

@ProviderFor(canRedactOthers)
final canRedactOthersProvider = CanRedactOthersFamily._();

/// Whether the user may delete other people's messages in the room.

final class CanRedactOthersProvider
    extends $FunctionalProvider<AsyncValue<bool>, bool, FutureOr<bool>>
    with $FutureModifier<bool>, $FutureProvider<bool> {
  /// Whether the user may delete other people's messages in the room.
  CanRedactOthersProvider._({
    required CanRedactOthersFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'canRedactOthersProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$canRedactOthersHash();

  @override
  String toString() {
    return r'canRedactOthersProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<bool> create(Ref ref) {
    final argument = this.argument as (String, String);
    return canRedactOthers(ref, argument.$1, argument.$2);
  }

  @override
  bool operator ==(Object other) {
    return other is CanRedactOthersProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$canRedactOthersHash() => r'ca991f0671acb55003feb6f741dcf1fa20fbbceb';

/// Whether the user may delete other people's messages in the room.

final class CanRedactOthersFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<bool>, (String, String)> {
  CanRedactOthersFamily._()
    : super(
        retry: null,
        name: r'canRedactOthersProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Whether the user may delete other people's messages in the room.

  CanRedactOthersProvider call(String account, String roomId) =>
      CanRedactOthersProvider._(argument: (account, roomId), from: this);

  @override
  String toString() => r'canRedactOthersProvider';
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
