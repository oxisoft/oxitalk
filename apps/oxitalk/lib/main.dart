import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'src/app/app.dart';
import 'src/app/diagnostics.dart';
import 'src/app/providers.dart';
import 'src/rust/frb_generated.dart';
import 'src/util/log.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  final diagnostics = await RustDiagnostics.start(
    await getApplicationSupportDirectory(),
  );
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    appLog(LogLevel.error, 'flutter', details.toString());
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    appLog(LogLevel.error, 'dart', '$error\n$stack');
    return false;
  };
  runApp(
    ProviderScope(
      overrides: [diagnosticsProvider.overrideWithValue(diagnostics)],
      child: const OxiTalkApp(),
    ),
  );
}
