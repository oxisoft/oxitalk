import 'package:flutter/material.dart';

import 'src/rust/api.dart';
import 'src/rust/frb_generated.dart';

Future<void> main() async {
  await RustLib.init();
  runApp(const OxiTalkApp());
}

/// Proof-of-concept shell: shows that the Rust core is loaded.
class OxiTalkApp extends StatelessWidget {
  const OxiTalkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OxiTalk',
      home: Scaffold(
        appBar: AppBar(title: const Text('OxiTalk')),
        body: Center(child: Text('Rust core ${coreVersion()}')),
      ),
    );
  }
}
