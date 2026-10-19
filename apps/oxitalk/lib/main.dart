import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'src/app/account_pictures.dart';
import 'src/app/app.dart';
import 'src/app/collapsed_sections.dart';
import 'src/app/diagnostics.dart';
import 'src/app/media_prefs.dart';
import 'src/app/providers.dart';
import 'src/app/ui_prefs.dart';
import 'src/app/window_controls.dart';
import 'src/rust/frb_generated.dart';
import 'src/util/log.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  final window = await DrawnWindowControls.start();
  final dataDir = await getApplicationSupportDirectory();
  final diagnostics = await RustDiagnostics.start(dataDir);
  final mediaPrefs = await FileMediaPrefs.load(dataDir);
  final uiPrefs = await FileUiPrefs.load(dataDir);
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
      overrides: [
        diagnosticsProvider.overrideWithValue(diagnostics),
        windowControlsProvider.overrideWithValue(window),
        mediaPrefsProvider.overrideWithValue(mediaPrefs),
        uiPrefsProvider.overrideWithValue(uiPrefs),
        accountPicturesProvider.overrideWithValue(FileAccountPictures(dataDir)),
        collapsedSectionsStoreProvider.overrideWithValue(
          FileCollapsedSections(dataDir),
        ),
      ],
      child: const OxiTalkApp(),
    ),
  );
}
