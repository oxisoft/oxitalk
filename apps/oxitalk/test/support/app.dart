import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oxitalk/src/app/app.dart';
import 'package:oxitalk/src/app/providers.dart';
import 'package:oxitalk/src/matrix/fakes/fakes.dart';

/// Phone-sized by default; pass a wider [size] for the desktop layout.
Future<void> pumpApp(
  WidgetTester tester,
  FakeMatrixClientFactory factory, {
  Size size = const Size(400, 800),
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
      ],
      child: const OxiTalkApp(),
    ),
  );
  await tester.pumpAndSettle();
}
