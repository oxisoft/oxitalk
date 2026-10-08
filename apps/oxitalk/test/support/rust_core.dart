import 'dart:convert';
import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:oxitalk/src/rust/frb_generated.dart';

/// Loads the Rust core in `flutter test`.
///
/// The bridge's default loader only finds the library inside a bundled app. `flutter test`
/// runs the build hook and records the library's absolute path in
/// `build/native_assets/<os>/native_assets.json`, so it is opened from there.
Future<void> initRustCore() {
  final manifest = File(
    'build/native_assets/${Platform.operatingSystem}/native_assets.json',
  );
  final json = jsonDecode(manifest.readAsStringSync()) as Map<String, Object?>;
  final targets = json['native-assets']! as Map<String, Object?>;
  final assets = targets.values.single! as Map<String, Object?>;
  final location = assets.values.single! as List<Object?>;
  return RustLib.init(
    externalLibrary: ExternalLibrary.open(location.last! as String),
  );
}
