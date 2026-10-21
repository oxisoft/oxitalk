import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:oxitalk/src/matrix/api/matrix.dart'
    show FailureKind, MessageEntry, SyncStatus, UndecryptableEntry;
import 'package:oxitalk/src/matrix/rust/diffs.dart';
import 'package:oxitalk/src/matrix/rust/mapping.dart';
import 'package:oxitalk/src/matrix/rust/sync_supervisor.dart';
import 'package:oxitalk/src/rust/api/error.dart';
import 'package:oxitalk/src/rust/api/notifications.dart';
import 'package:oxitalk/src/rust/api/room_list.dart';
import 'package:oxitalk/src/rust/api/sync.dart';
import 'package:oxitalk/src/rust/api/timeline.dart';

// The bridge's plain data classes need no Rust library, so these run without it.

RoomSummary _room(String id, {bool isOneToOne = false}) => RoomSummary(
  roomId: id,
  name: id,
  membership: Membership.joined,
  unreadCount: 0,
  unreadNotifications: 0,
  unreadMentions: 0,
  markedUnread: false,
  defaultNotificationMode: RoomNotificationMode.allMessages,
  isOneToOne: isOneToOne,
  isDm: false,
  isEncrypted: false,
);

EventInfo _event({bool isOwn = false}) => EventInfo(
  sender: '@bob:example.org',
  timestampMs: 1760000000000,
  isOwn: isOwn,
  sendState: SendState.sent,
  reactions: const [],
  isEdited: false,
  isEditable: false,
);

void main() {
  test('a room says whether its default is the direct chat one', () {
    expect(roomOf(_room('a', isOneToOne: true)).isOneToOne, isTrue);
    expect(roomOf(_room('b')).isOneToOne, isFalse);
  });

  test('room list diffs apply in order', () {
    final list = <RoomSummary>[];
    for (final diff in [
      RoomListDiff.reset(values: [_room('a'), _room('b')]),
      RoomListDiff.pushFront(value: _room('z')),
      RoomListDiff.pushBack(value: _room('c')),
      RoomListDiff.insert(index: 1, value: _room('y')),
      RoomListDiff.set_(index: 2, value: _room('A')),
      RoomListDiff.remove(index: 0),
      RoomListDiff.append(values: [_room('d'), _room('e')]),
      const RoomListDiff.popFront(),
      const RoomListDiff.popBack(),
      const RoomListDiff.truncate(length: 3),
    ]) {
      applyRoomListDiff(list, diff);
    }
    expect(list.map((room) => room.roomId), ['A', 'b', 'c']);

    applyRoomListDiff(list, const RoomListDiff.clear());
    expect(list, isEmpty);
  });

  test('timeline diffs apply in order, and hidden items are left out', () {
    final items = <TimelineItem>[];
    for (final diff in [
      TimelineDiff.reset(
        values: [
          const TimelineItem(
            id: 's',
            content: TimelineItemContent.timelineStart(),
          ),
          const TimelineItem(
            id: 'd',
            content: TimelineItemContent.dateDivider(
              timestampMs: 1760000000000,
            ),
          ),
        ],
      ),
      TimelineDiff.pushBack(
        value: TimelineItem(
          id: 'm',
          content: TimelineItemContent.message(event: _event(), body: 'hi'),
        ),
      ),
      TimelineDiff.pushBack(
        value: TimelineItem(
          id: 'o',
          content: TimelineItemContent.otherEvent(event: _event()),
        ),
      ),
      TimelineDiff.pushBack(
        value: TimelineItem(
          id: 'u',
          content: TimelineItemContent.unableToDecrypt(
            event: _event(isOwn: true),
          ),
        ),
      ),
    ]) {
      applyTimelineDiff(items, diff);
    }
    expect(items, hasLength(5));

    final entries = entriesOf(items);
    expect(entries.map((entry) => entry.id), ['d', 'm', 'u']);
    expect((entries[1] as MessageEntry).body, 'hi');
    expect((entries[2] as UndecryptableEntry).isOwn, isTrue);
  });

  test('core errors map to failure kinds', () {
    expect(
      failure(const CoreError.forbidden(message: 'no')).kind,
      FailureKind.forbidden,
    );
    expect(
      failure(const CoreError.sessionExpired()).kind,
      FailureKind.sessionExpired,
    );
    expect(failure(const CoreError.invalidId(id: 'x')).message, 'x');
  });

  group('sync supervisor', () {
    late StreamController<SyncState> states;
    late int starts;
    late SyncSupervisor supervisor;

    setUp(() {
      states = StreamController();
      starts = 0;
      supervisor = SyncSupervisor(
        states: states.stream,
        start: () async => starts++,
        firstDelay: const Duration(milliseconds: 10),
        maxDelay: const Duration(milliseconds: 20),
      );
    });

    tearDown(() async {
      await supervisor.close();
      await states.close();
    });

    Future<void> settle([Duration wait = Duration.zero]) =>
        Future<void>.delayed(wait);

    test('maps the SDK states to the status', () async {
      final statuses = <SyncStatus>[];
      final subscription = supervisor.status.stream.listen(statuses.add);
      states
        ..add(const SyncState.running())
        ..add(const SyncState.offline())
        ..add(const SyncState.running());
      await settle();
      expect(statuses, [
        SyncStatus.connecting,
        SyncStatus.online,
        SyncStatus.offline,
        SyncStatus.online,
      ]);
      await subscription.cancel();
    });

    test('restarts after an error, with a growing delay', () async {
      const error = SyncState.error(error: CoreError.network(message: 'down'));
      states.add(error);
      await settle();
      expect(supervisor.status.value, SyncStatus.connecting);
      expect(starts, 0);
      await settle(const Duration(milliseconds: 15));
      expect(starts, 1);

      // The second error waits the doubled delay.
      states.add(error);
      await settle(const Duration(milliseconds: 15));
      expect(starts, 1);
      await settle(const Duration(milliseconds: 15));
      expect(starts, 2);

      // Running again resets the delay.
      states
        ..add(const SyncState.running())
        ..add(error);
      await settle(const Duration(milliseconds: 15));
      expect(starts, 3);
    });
  });
}
