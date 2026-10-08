import 'package:flutter_rust_bridge_hooks/flutter_rust_bridge_hooks.dart';

/// Builds the Rust core and bundles it as a native code asset.
void main(List<String> args) async {
  await build(args, (input, output) async {
    await const FlutterRustBridgeNativeAssetsBuilder(
      cratePath: '../../rust/oxitalk_core',
    ).run(input: input, output: output);
  });
}
