import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oxitalk/src/app/ui_prefs.dart';
import 'package:oxitalk/src/features/chat/emoticons.dart';
import 'package:oxitalk/src/matrix/api/matrix.dart';
import 'package:oxitalk/src/matrix/fakes/fakes.dart';

import 'support/app.dart';

const _me = '@me:acme.com';
const _room = '!team:acme.com';

/// [before] with [typed] typed at its end, through the formatter.
String _type(String before, String typed, {bool enabled = true}) {
  final formatter = EmoticonFormatter(enabled: () => enabled);
  var value = TextEditingValue(
    text: before,
    selection: TextSelection.collapsed(offset: before.length),
  );
  for (final char in typed.split('')) {
    final text = value.text + char;
    value = formatter.formatEditUpdate(
      value,
      TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      ),
    );
  }
  return value.text;
}

void main() {
  test('an emoticon becomes an emoji once a space or punctuation follows', () {
    expect(_type('', ':) '), '🙂 ');
    expect(_type('hi', ' ;)!'), 'hi 😉!');
    expect(_type('', '<3\n'), '❤️\n');
    expect(_type('', ':D, :P.'), '😃, 😛.');
    expect(_type('', ':)'), ':)');
  });

  test('only a standalone emoticon, outside code, and while turned on', () {
    expect(_type('', 'a:) '), 'a:) ');
    expect(_type('', 'see http://x.io/ '), 'see http://x.io/ ');
    expect(_type('', '`:) '), '`:) ');
    expect(_type('', '`x` :) '), '`x` 🙂 ');
    expect(_type('', ':) ', enabled: false), ':) ');
  });

  test('a trailing emoticon is replaced on sending', () {
    expect(
      withTrailingEmoticon('so, the bug in oxitalk :)'),
      'so, the bug in oxitalk 🙂',
    );
    expect(withTrailingEmoticon('ok :D  '), 'ok 😃  ');
    expect(withTrailingEmoticon('no:)'), 'no:)');
    expect(withTrailingEmoticon(''), '');
  });

  testWidgets(
    'the composer replaces emoticons, unless turned off in Settings',
    (tester) async {
      final ui = MemoryUiPrefs();
      final timeline = FakeTimeline(ownUserId: _me);
      final session = FakeSession(
        userId: _me,
        rooms: const [Room(id: _room, name: 'Team')],
      );
      session.timelines[_room] = timeline;
      await pumpApp(
        tester,
        FakeMatrixClientFactory(saved: [session]),
        size: const Size(1400, 900),
        ui: ui,
      );
      await tester.tap(find.text('Team'));
      await tester.pumpAndSettle();
      final composer = find.byKey(const Key('composer.text'));
      String typed() => tester.widget<TextField>(composer).controller!.text;
      String lastSent() => (timeline.entryList.last as MessageEntry).body;

      await tester.enterText(composer, 'hi :)');
      await tester.enterText(composer, 'hi :) ');
      expect(typed(), 'hi 🙂 ');
      await tester.enterText(composer, 'hi 🙂 and ;)');
      await tester.tap(find.byKey(const Key('composer.send')));
      await tester.pumpAndSettle();
      expect(lastSent(), 'hi 🙂 and 😉');

      await tester.tap(find.byKey(const Key('rail.settings')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings.replaceEmoticons')));
      await tester.pumpAndSettle();
      expect(ui.replaceEmoticons, isFalse);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.enterText(composer, ':)');
      await tester.enterText(composer, ':) ');
      expect(typed(), ':) ');
      await tester.tap(find.byKey(const Key('composer.send')));
      await tester.pumpAndSettle();
      expect(lastSent(), ':)');
    },
  );
}
