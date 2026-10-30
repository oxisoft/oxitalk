import 'package:flutter_test/flutter_test.dart';
import 'package:oxitalk/src/rust/api.dart';

import 'support/rust_core.dart';

void main() {
  setUpAll(initRustCore);

  test('the Rust core answers through the bridge', () {
    expect(coreVersion(), '0.1.35');
  });
}
