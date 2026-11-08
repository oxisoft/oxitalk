import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'src/app/account_pictures.dart';
import 'src/app/app.dart';
import 'src/app/collapsed_sections.dart';
import 'src/app/diagnostics.dart';
import 'src/app/linux_desktop_entry.dart';
import 'src/app/media_prefs.dart';
import 'src/app/providers.dart';
import 'src/app/ui_prefs.dart';
import 'src/app/window_controls.dart';
import 'src/features/share/share_inbox.dart';
import 'src/rust/frb_generated.dart';
import 'src/util/log.dart';

/// [args]: files and links named on the command line, as Open with passes them on Linux and
/// Windows; they go to "Send to…".
Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  // GNOME and other Wayland desktops show the name and icon of an installed entry only.
  if (Platform.isLinux) unawaited(registerThisLinuxApp());
  // The bundled fonts' licences, in About → View licenses.
  LicenseRegistry.addLicense(() async* {
    for (final (name, file) in [
      ('Open Sans', 'OpenSans'),
      ('Noto Color Emoji', 'NotoColorEmoji'),
    ]) {
      yield LicenseEntryWithLineBreaks([
        name,
      ], await rootBundle.loadString('assets/fonts/$file-LICENSE.txt'));
    }
  });
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
        shareSourceProvider.overrideWithValue(PlatformShareSource(args: args)),
        accountPicturesProvider.overrideWithValue(FileAccountPictures(dataDir)),
        collapsedSectionsStoreProvider.overrideWithValue(
          FileCollapsedSections(dataDir),
        ),
      ],
      child: const OxiTalkApp(),
    ),
  );
}
