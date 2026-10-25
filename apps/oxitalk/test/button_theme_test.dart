import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oxitalk/src/app/theme.dart';

/// The visible box of [button]: its [Material], inside the tap target.
Size _box(WidgetTester tester, Finder button) => tester.getSize(
  find.descendant(of: button, matching: find.byType(Material)).first,
);

ShapeBorder _shape(WidgetTester tester, Finder button) => tester
    .widget<Material>(
      find.descendant(of: button, matching: find.byType(Material)).first,
    )
    .shape!;

Future<void> _pump(WidgetTester tester, Brightness brightness) =>
    tester.pumpWidget(
      MaterialApp(
        theme: oxiTheme(brightness),
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                FilledButton(
                  key: const Key('primary'),
                  onPressed: () {},
                  child: const Text('Save'),
                ),
                OutlinedButton(
                  key: const Key('secondary'),
                  onPressed: () {},
                  child: const Text('Change'),
                ),
                OutlinedButton.icon(
                  key: const Key('destructive'),
                  style: OxiButtons.destructive(context),
                  onPressed: () {},
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Log out'),
                ),
                FilledButton(
                  key: const Key('destructiveFilled'),
                  style: OxiButtons.destructiveFilled(context),
                  onPressed: () {},
                  child: const Text('Delete'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

Color? _label(WidgetTester tester, String key, String text) => tester
    .widget<RichText>(
      find.descendant(
        of: find.byKey(Key(key)),
        matching: find.byWidgetPredicate(
          (w) => w is RichText && w.text.toPlainText() == text,
        ),
      ),
    )
    .text
    .style
    ?.color;

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('every button kind has one size and shape ($brightness)', (
      tester,
    ) async {
      await _pump(tester, brightness);
      for (final key in [
        'primary',
        'secondary',
        'destructive',
        'destructiveFilled',
      ]) {
        final button = find.byKey(Key(key));
        expect(_box(tester, button).height, OxiButtons.height, reason: key);
        final shape = _shape(tester, button);
        expect(shape, isA<BeveledRectangleBorder>(), reason: key);
      }
    });
  }

  testWidgets('primary is yellow under ink in dark, ink under white in light', (
    tester,
  ) async {
    await _pump(tester, Brightness.dark);
    expect(_label(tester, 'primary', 'Save'), OxiBrand.ink);
    await _pump(tester, Brightness.light);
    await tester.pumpAndSettle();
    expect(_label(tester, 'primary', 'Save'), Colors.white);
  });

  testWidgets('secondary and destructive are outlined; destructive is red', (
    tester,
  ) async {
    await _pump(tester, Brightness.dark);
    final secondary = _shape(tester, find.byKey(const Key('secondary')));
    final destructive = _shape(tester, find.byKey(const Key('destructive')));
    expect(
      (secondary as BeveledRectangleBorder).side.color,
      OxiButtons.outline(OxiPalette.dark),
    );
    expect((destructive as BeveledRectangleBorder).side.color, OxiBrand.red);
    expect(_label(tester, 'destructive', 'Log out'), OxiBrand.red);
    expect(_label(tester, 'secondary', 'Change'), OxiPalette.dark.text);

    await _pump(tester, Brightness.light);
    await tester.pumpAndSettle();
    expect(_label(tester, 'destructive', 'Log out'), OxiButtons.dangerOnLight);
  });

  test('the app shows no borderless text buttons', () {
    // Every button the app draws is filled or outlined, so none reads as plain text.
    // TextButton is left to the framework's own text actions (snack bars, text menus).
    final offenders = [
      for (final file in Directory('lib').listSync(recursive: true))
        if (file is File &&
            file.path.endsWith('.dart') &&
            RegExp(r'\bTextButton(\.icon)?\(')
                .hasMatch(file.readAsStringSync()))
          file.path,
    ];
    expect(offenders, isEmpty);
  });
}
