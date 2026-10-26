import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oxitalk/src/app/file_actions.dart';
import 'package:oxitalk/src/app/ui_prefs.dart';
import 'package:oxitalk/src/app/window_controls.dart';
import 'package:oxitalk/src/features/about/about_screen.dart';
import 'package:oxitalk/src/matrix/api/matrix.dart';
import 'package:oxitalk/src/matrix/fakes/fakes.dart';

import 'support/app.dart';
import 'support/rust_core.dart';

const _me = '@me:acme.com';

/// A window whose title bar the app draws, as on Linux.
final class _DrawnWindow implements WindowControls {
  @override
  bool get drawsTitleBar => true;

  @override
  List<WindowButton> get leftButtons => const [];

  @override
  List<WindowButton> get rightButtons => const [WindowButton.close];

  @override
  Future<void> startDragging() async {}

  @override
  Future<void> doubleClick() async {}

  @override
  Future<void> showMenu() async {}

  @override
  Future<void> press(WindowButton button) async {}
}

/// The app with one account, About opened from the rail (wide) or the account menu
/// (narrow, where the rail is hidden).
Future<FakeFileActions> _openAbout(
  WidgetTester tester, {
  Size size = const Size(1200, 800),
  String theme = 'light',
  WindowControls? window,
}) async {
  final files = FakeFileActions();
  await pumpApp(
    tester,
    FakeMatrixClientFactory(
      saved: [
        FakeSession(
          userId: _me,
          rooms: const [Room(id: '!team', name: 'Team')],
        ),
      ],
    ),
    size: size,
    files: files,
    window: window,
    ui: MemoryUiPrefs(theme: theme),
  );
  if (find.byKey(const Key('rail.about')).evaluate().isNotEmpty) {
    await tester.tap(find.byKey(const Key('rail.about')));
  } else {
    await pickFromAccountMenu(tester, 'accountMenu.about');
  }
  await tester.pumpAndSettle();
  return files;
}

void main() {
  setUpAll(initRustCore);

  testWidgets('About is a full-screen page: icon, name, version, what it is '
      'and its links', (tester) async {
    final files = await _openAbout(tester);
    final about = find.byKey(const Key('about'));
    expect(about, findsOneWidget);
    // Full screen: as big as the window, not a dialog over the chats.
    expect(tester.getSize(about), const Size(1200, 800));
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Team'), findsNothing);

    expect(find.byKey(const Key('about.hero')), findsOneWidget);
    expect(find.bySemanticsLabel('OxiTalk icon'), findsWidgets);
    expect(find.text('OxiTalk'), findsWidgets);
    expect(find.text('Version 0.1.27'), findsOneWidget);
    expect(
      find.text(
        'An open-source Matrix client, privacy first, built with Flutter on '
        'matrix-rust-sdk.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('MIT License'), findsOneWidget);

    for (final (key, uri) in [
      ('about.website', 'https://oxitalk.com'),
      ('about.source', 'https://github.com/oxisoft/oxitalk'),
      ('about.oxisoft', 'https://oxisoft.io'),
    ]) {
      await tester.ensureVisible(find.byKey(Key(key)));
      await tester.tap(find.byKey(Key(key)));
      await tester.pumpAndSettle();
      expect(files.launched.last, Uri.parse(uri));
    }
    expect(find.text('Made by OxiSoft'), findsOneWidget);
  });

  testWidgets('Licenses opens Flutter’s license page, full screen too; Back '
      'returns to About, and Back again to the chats', (tester) async {
    await _openAbout(tester);
    await tester.ensureVisible(find.byKey(const Key('about.licenses')));
    await tester.tap(find.byKey(const Key('about.licenses')));
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsOneWidget);
    expect(tester.getSize(find.byType(LicensePage)), const Size(1200, 800));

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsNothing);
    expect(find.byKey(const Key('about')), findsOneWidget);

    await tester.tap(find.byKey(const Key('about.back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('about')), findsNothing);
    expect(find.text('Team'), findsOneWidget);
  });

  testWidgets('Esc and the system back close it', (tester) async {
    await _openAbout(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('about')), findsNothing);
    expect(find.text('Team'), findsOneWidget);

    await tester.tap(find.byKey(const Key('rail.about')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('about')), findsOneWidget);
    // Android's back button.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('about')), findsNothing);
  });

  testWidgets('on a phone, in the dark, it fits without overflow', (
    tester,
  ) async {
    await _openAbout(tester, size: const Size(360, 640), theme: 'dark');
    expect(tester.takeException(), isNull);
    final about = find.byKey(const Key('about'));
    expect(tester.getSize(about), const Size(360, 640));
    expect(Theme.of(tester.element(about)).brightness, Brightness.dark);
    await tester.scrollUntilVisible(
      find.byKey(const Key('about.license')),
      200,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('under the Linux title bar it sits below the bar, with its own '
      'back button', (tester) async {
    await _openAbout(tester, window: _DrawnWindow());
    final bar = tester.getRect(find.byKey(const Key('titleBar')));
    final about = tester.getRect(find.byKey(const Key('about')));
    expect(about.top, greaterThanOrEqualTo(bar.bottom));
    expect(
      tester.getRect(find.byKey(const Key('about.back'))).top,
      greaterThanOrEqualTo(bar.bottom),
    );
  });

  test('the version shows its build number when the build says it', () {
    expect(const AppVersion('0.1.26', '27').label, 'Version 0.1.26 (27)');
    expect(const AppVersion('0.1.26').label, 'Version 0.1.26');
  });
}
