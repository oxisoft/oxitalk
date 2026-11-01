import 'package:flutter_rust_bridge_hooks/flutter_rust_bridge_hooks.dart';

/// Builds the Rust core and bundles it as a native code asset.
///
/// The builder always runs `cargo build --release`. Flutter enables linking only for profile and
/// release builds, so a debug build or `flutter test` turns off the release profile's LTO, single
/// codegen unit and stripping (rust/Cargo.toml): those are for the store builds and make every
/// build of the core minutes longer.
void main(List<String> args) async {
  await build(args, (input, output) async {
    await FlutterRustBridgeNativeAssetsBuilder(
      cratePath: '../../rust/oxitalk_core',
      extraCargoBuildArgs: input.config.linkingEnabled
          ? const []
          : const [
              '--config',
              'profile.release.lto=false',
              '--config',
              'profile.release.codegen-units=16',
              '--config',
              'profile.release.opt-level=3',
              '--config',
              'profile.release.strip="none"',
            ],
    ).run(input: input, output: output);
  });
}
