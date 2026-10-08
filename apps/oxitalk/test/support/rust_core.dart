import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:oxitalk/src/rust/frb_generated.dart';

/// Loads the Rust core in `flutter test`.
///
/// The build hook puts the library under `build/native_assets/<os>/`, which the bridge's
/// default loader doesn't look at outside a bundled app.
Future<void> initRustCore() => RustLib.init(
  externalLibrary: ExternalLibrary.open(switch (Platform.operatingSystem) {
    'linux' => 'build/native_assets/linux/liboxitalk_core.so',
    'macos' => 'build/native_assets/macos/oxitalk_core.framework/oxitalk_core',
    'windows' => r'build\native_assets\windows\oxitalk_core.dll',
    final os => throw UnsupportedError('No Rust core for $os'),
  }),
);
