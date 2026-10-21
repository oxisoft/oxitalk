import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:oxitalk/src/features/chats/room_groups.dart';
import 'package:oxitalk/src/matrix/api/matrix.dart';

const _acme = '${SectionTags.customPrefix}acme';
const _globex = '${SectionTags.customPrefix}globex';

void main() {
  const rooms = [
    Room(id: '!invite', name: 'Invite', membership: Membership.invited),
    Room(
      id: '!dm',
      name: 'Bob',
      isDm: true,
      unreadCount: 2,
      unreadNotifications: 2,
    ),
    Room(id: '!fav', name: 'Fav'),
    Room(
      id: '!acme',
      name: 'Acme room',
      unreadCount: 3,
      unreadNotifications: 3,
    ),
    Room(id: '!plain', name: 'Plain'),
    Room(id: '!low', name: 'Low'),
    Room(id: '!gone', name: 'In a deleted section'),
    Room(id: '!favdm', name: 'Fav DM', isDm: true),
  ];
  const sections = Sections(
    custom: [CustomSection(_acme, 'Acme'), CustomSection(_globex, 'Globex')],
    roomTags: {
      '!fav': [SectionTags.favourites],
      '!acme': ['u.other', _acme],
      '!low': [SectionTags.lowPriority],
      '!gone': ['${SectionTags.customPrefix}deleted'],
      '!favdm': [SectionTags.favourites],
      // Tags of an invite don't count.
      '!invite': [SectionTags.favourites],
    },
  );

  test('rooms are grouped in Element’s order, without empty sections', () {
    final groups = groupRooms(rooms, sections);
    expect(
      [
        for (final group in groups)
          '${group.title}: ${[for (final room in group.rooms) room.id].join(' ')}',
      ],
      [
        'Invites: !invite',
        'Favorites: !fav !favdm',
        'People: !dm',
        'Acme: !acme',
        'Rooms: !plain !gone',
        'Low priority: !low',
      ],
    );
    expect(groups[0].unread, 1);
    expect(groups[3].unread, 3);
    expect(groups[3].isCustom, isTrue);
    expect(groups[2].isMovable, isTrue);
    expect(groups[1].isMovable, isFalse);
  });

  test(
    'the stored order is kept; what is missing is added as Element does',
    () {
      expect(movableOrder(const Sections()), [
        SectionTags.people,
        SectionTags.rooms,
      ]);
      expect(
        movableOrder(
          const Sections(
            custom: [
              CustomSection(_acme, 'Acme'),
              CustomSection(_globex, 'Globex'),
            ],
            order: [
              SectionTags.rooms,
              _acme,
              '${SectionTags.customPrefix}deleted',
              _acme,
              'something else',
            ],
          ),
        ),
        [SectionTags.people, _globex, SectionTags.rooms, _acme],
      );
    },
  );

  test('a section moves one place, not past either end', () {
    const order = ['a', 'b', 'c'];
    expect(moved(order, 'b', -1), ['b', 'a', 'c']);
    expect(moved(order, 'b', 1), ['a', 'c', 'b']);
    expect(moved(order, 'a', -1), order);
    expect(moved(order, 'c', 1), order);
    expect(moved(order, 'x', 1), order);
  });

  test('a new section tag is Element’s prefix and a version 4 UUID', () {
    expect(
      newSectionTag(Random(1)),
      matches(
        RegExp(
          r'^element\.io\.section\.[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-'
          r'[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
    expect(newSectionTag(), isNot(newSectionTag()));
  });
}
