import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oxitalk/src/app/collapsed_sections.dart';
import 'package:oxitalk/src/matrix/api/matrix.dart';
import 'package:oxitalk/src/matrix/fakes/fakes.dart';

import 'support/app.dart';

const _wide = Size(1200, 800);
const _me = '@me:acme.com';
const _acme = '${SectionTags.customPrefix}acme';

FakeSession _session({Sections sections = const Sections()}) => FakeSession(
  userId: _me,
  sections: sections,
  rooms: const [
    Room(
      id: '!bob',
      name: 'Bob',
      isDm: true,
      unreadCount: 2,
      unreadNotifications: 2,
    ),
    Room(id: '!team', name: 'Team'),
    Room(id: '!news', name: 'News', unreadCount: 4, unreadNotifications: 4),
  ],
);

/// The section headers, top to bottom.
List<String> _headers(WidgetTester tester) => [
  for (final element in find.byType(InkWell).evaluate())
    if (element.widget.key case ValueKey<String>(:final value)
        when value.startsWith('section.'))
      value.substring('section.'.length),
];

Future<void> _rightClick(WidgetTester tester, String room) async {
  await tester.tap(find.text(room), buttons: kSecondaryMouseButton);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('only rooms: a plain list, without headers', (tester) async {
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
    );
    expect(find.text('Team'), findsOneWidget);
    expect(_headers(tester), isEmpty);
  });

  testWidgets('sections in Element’s order; one folds, showing its unread', (
    tester,
  ) async {
    final collapsed = MemoryCollapsedSections();
    await pumpApp(
      tester,
      FakeMatrixClientFactory(
        saved: [
          _session(
            sections: const Sections(
              custom: [CustomSection(_acme, 'Acme')],
              order: [_acme, SectionTags.people, SectionTags.rooms],
              roomTags: {
                '!team': [SectionTags.favourites],
                '!news': [_acme],
              },
            ),
          ),
        ],
      ),
      collapsed: collapsed,
    );
    expect(_headers(tester), [
      SectionTags.favourites,
      _acme,
      SectionTags.people,
    ]);
    expect(find.text('Acme'), findsOneWidget);
    expect(find.text('News'), findsOneWidget);

    await tester.tap(find.byKey(const Key('section.$_acme')));
    await tester.pumpAndSettle();
    expect(find.text('News'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('section.$_acme')),
        matching: find.text('4'),
      ),
      findsOneWidget,
    );
    expect(collapsed.values[_me], {_acme});

    await tester.tap(find.byKey(const Key('section.$_acme')));
    await tester.pumpAndSettle();
    expect(find.text('News'), findsOneWidget);
    expect(collapsed.values[_me], isEmpty);
  });

  testWidgets('folded sections stay folded after a restart', (tester) async {
    await pumpApp(
      tester,
      FakeMatrixClientFactory(saved: [_session()]),
      collapsed: MemoryCollapsedSections()..values[_me] = {SectionTags.people},
    );
    expect(find.text('Bob'), findsNothing);
    expect(find.text('Team'), findsOneWidget);
  });

  testWidgets('a right-click makes a room a favorite and takes it back', (
    tester,
  ) async {
    final session = _session();
    await pumpApp(
      tester,
      FakeMatrixClientFactory(saved: [session]),
      size: _wide,
    );
    await _rightClick(tester, 'Team');
    await tester.tap(find.text('Add to favorites'));
    await tester.pumpAndSettle();
    expect(session.sectionState.value.roomTags['!team'], [
      SectionTags.favourites,
    ]);
    expect(_headers(tester).first, SectionTags.favourites);

    await _rightClick(tester, 'Team');
    await tester.tap(find.text('Low priority'));
    await tester.pumpAndSettle();
    expect(session.sectionState.value.roomTags['!team'], [
      SectionTags.lowPriority,
    ]);
    expect(_headers(tester).last, SectionTags.lowPriority);

    await _rightClick(tester, 'Team');
    await tester.tap(find.text('Remove from low priority'));
    await tester.pumpAndSettle();
    expect(session.sectionState.value.roomTags['!team'], isEmpty);
  });

  testWidgets('a long-press opens the same menu on a phone', (tester) async {
    await pumpApp(tester, FakeMatrixClientFactory(saved: [_session()]));
    await tester.longPress(find.text('Team'));
    await tester.pumpAndSettle();
    expect(find.text('Move to section…'), findsOneWidget);
  });

  testWidgets('a new section is made with a room, renamed, moved and deleted', (
    tester,
  ) async {
    final session = _session();
    await pumpApp(
      tester,
      FakeMatrixClientFactory(saved: [session]),
      size: _wide,
    );
    await _rightClick(tester, 'News');
    await tester.tap(find.text('New section…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('section.name')), 'Clients');
    await tester.tap(find.byKey(const Key('section.save')));
    await tester.pumpAndSettle();

    final sections = session.sectionState.value;
    final tag = sections.custom.single.tag;
    expect(sections.custom.single.name, 'Clients');
    expect(sections.order, [SectionTags.people, tag, SectionTags.rooms]);
    expect(sections.roomTags['!news'], [tag]);
    expect(_headers(tester), [SectionTags.people, tag, SectionTags.rooms]);

    await tester.tap(find.byKey(Key('sectionMenu.$tag')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('section.name')), 'Customers');
    await tester.tap(find.byKey(const Key('section.save')));
    await tester.pumpAndSettle();
    expect(find.text('Customers'), findsOneWidget);

    await tester.tap(find.byKey(Key('sectionMenu.$tag')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move up'));
    await tester.pumpAndSettle();
    expect(_headers(tester), [tag, SectionTags.people, SectionTags.rooms]);

    // The top one can't move up.
    await tester.tap(find.byKey(Key('sectionMenu.$tag')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<PopupMenuItem<VoidCallback>>(
            find.widgetWithText(PopupMenuItem<VoidCallback>, 'Move up'),
          )
          .enabled,
      isFalse,
    );
    await tester.tap(find.text('Delete…'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('section.delete')));
    await tester.pumpAndSettle();
    expect(session.sectionState.value.custom, isEmpty);
    expect(session.sectionState.value.order, [
      SectionTags.people,
      SectionTags.rooms,
    ]);
    expect(_headers(tester), [SectionTags.people, SectionTags.rooms]);
    expect(find.text('News'), findsOneWidget);
  });

  testWidgets('a room moves to an existing section from the dialog', (
    tester,
  ) async {
    final session = _session(
      sections: const Sections(custom: [CustomSection(_acme, 'Acme')]),
    );
    await pumpApp(
      tester,
      FakeMatrixClientFactory(saved: [session]),
      size: _wide,
    );
    await _rightClick(tester, 'Bob');
    await tester.tap(find.text('Move to section…'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('moveTo.Acme')));
    await tester.pumpAndSettle();
    expect(session.sectionState.value.roomTags['!bob'], [_acme]);

    await _rightClick(tester, 'Bob');
    await tester.tap(find.text('Move to section…'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('moveTo.People')));
    await tester.pumpAndSettle();
    expect(session.sectionState.value.roomTags['!bob'], isEmpty);
  });

  testWidgets('an invite has no section menu', (tester) async {
    await pumpApp(
      tester,
      FakeMatrixClientFactory(
        saved: [
          FakeSession(
            userId: _me,
            rooms: const [
              Room(id: '!inv', name: 'Invite', membership: Membership.invited),
            ],
          ),
        ],
      ),
      size: _wide,
    );
    expect(_headers(tester), [SectionTags.invites]);
    await _rightClick(tester, 'Invite');
    expect(find.text('Move to section…'), findsNothing);
  });

  testWidgets('accepting an invite opens the chat, though it changes section', (
    tester,
  ) async {
    await pumpApp(
      tester,
      FakeMatrixClientFactory(
        saved: [
          FakeSession(
            userId: _me,
            rooms: const [
              Room(
                id: '!inv',
                name: 'Carol',
                isDm: true,
                membership: Membership.invited,
              ),
              Room(id: '!team', name: 'Team'),
            ],
          ),
        ],
      ),
      size: _wide,
    );
    await tester.tap(find.text('Invitation — tap to see it'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('invite.accept')));
    await tester.pumpAndSettle();
    expect(_headers(tester), [SectionTags.people, SectionTags.rooms]);
    expect(find.byKey(const Key('composer.text')), findsOneWidget);
  });
}
