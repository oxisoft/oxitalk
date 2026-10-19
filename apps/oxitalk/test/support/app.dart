import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oxitalk/src/app/account_pictures.dart';
import 'package:oxitalk/src/app/app.dart';
import 'package:oxitalk/src/app/collapsed_sections.dart';
import 'package:oxitalk/src/app/diagnostics.dart';
import 'package:oxitalk/src/app/file_actions.dart';
import 'package:oxitalk/src/app/media_prefs.dart';
import 'package:oxitalk/src/app/pick_image.dart';
import 'package:oxitalk/src/app/window_controls.dart';
import 'package:oxitalk/src/app/providers.dart';
import 'package:oxitalk/src/matrix/fakes/fakes.dart';

/// Phone-sized by default; pass a wider [size] for the desktop layout.
Future<void> pumpApp(
  WidgetTester tester,
  FakeMatrixClientFactory factory, {
  Size size = const Size(400, 800),
  MemoryDiagnostics? diagnostics,
  MemoryAccountPictures? pictures,
  PickImage? pickImage,
  MemoryCollapsedSections? collapsed,
  WindowControls? window,
  MemoryMediaPrefs? mediaPrefs,
  FakeFileActions? files,
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        clientFactoryProvider.overrideWithValue(factory),
        secretStoreProvider.overrideWithValue(MemorySecretStore()),
        diagnosticsProvider.overrideWithValue(
          diagnostics ?? MemoryDiagnostics(),
        ),
        accountPicturesProvider.overrideWithValue(
          pictures ?? MemoryAccountPictures(),
        ),
        pickImageProvider.overrideWithValue(pickImage ?? () async => null),
        if (window != null) windowControlsProvider.overrideWithValue(window),
        mediaPrefsProvider.overrideWithValue(mediaPrefs ?? MemoryMediaPrefs()),
        fileActionsProvider.overrideWithValue(files ?? FakeFileActions()),
        collapsedSectionsStoreProvider.overrideWithValue(
          collapsed ?? MemoryCollapsedSections(),
        ),
      ],
      child: const OxiTalkApp(),
    ),
  );
  await tester.pumpAndSettle();
}
