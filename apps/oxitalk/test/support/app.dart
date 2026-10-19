import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oxitalk/src/app/account_pictures.dart';
import 'package:oxitalk/src/app/app.dart';
import 'package:oxitalk/src/app/collapsed_sections.dart';
import 'package:oxitalk/src/app/diagnostics.dart';
import 'package:oxitalk/src/app/pick_image.dart';
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
        collapsedSectionsStoreProvider.overrideWithValue(
          collapsed ?? MemoryCollapsedSections(),
        ),
      ],
      child: const OxiTalkApp(),
    ),
  );
  await tester.pumpAndSettle();
}
