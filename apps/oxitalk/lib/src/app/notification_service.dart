import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../matrix/api/matrix.dart';
import 'os_notifications.dart';
import 'providers.dart';
import 'router.dart';

part 'notification_service.g.dart';

/// How notifications show on this device, for every account (Settings › Account).
final class DeviceNotificationPrefs {
  const DeviceNotificationPrefs({
    this.enabled = true,
    this.showText = true,
    this.sound = true,
  });

  /// Show OS notifications at all.
  final bool enabled;

  /// Show the message's text; off shows "New message" (for privacy, e.g. on a shared
  /// screen).
  final bool showText;

  /// Play a sound where the push rules ask for one.
  final bool sound;
}

/// How many messages of a room a notification keeps for Android's conversation style.
const notificationLinesKept = 5;

/// What a notification says when its text is hidden or there is none.
const hiddenNotificationText = 'New message';

/// One account's OS notifications, as Element X decides them: one notification per room,
/// updated as messages arrive; none for the room the user is looking at; taken away when the
/// room's notifying count drops to zero (read here or on another device), when the user
/// opens the room, or when it is muted.
final class AccountNotifications {
  AccountNotifications({
    required this.account,
    required this.presenter,
    required this.prefs,
    required this.isLookingAt,
  });

  /// The account's user ID.
  final String account;
  final NotificationPresenter presenter;
  final DeviceNotificationPrefs Function() prefs;

  /// Whether the window is focused with this account's room open.
  final bool Function(String roomId) isLookingAt;

  final _rooms = <String, _RoomNotification>{};

  /// The account's notifying total, as the account rail counts it.
  int get total => _total;
  var _total = 0;

  /// The rooms with a notification showing.
  Iterable<String> get shownRooms => _rooms.keys;

  /// A message the core says should notify.
  void onMessage(MessageNotification message) {
    final prefs = this.prefs();
    if (!prefs.enabled ||
        message.senderId == account ||
        isLookingAt(message.roomId)) {
      return;
    }
    final room = _rooms.putIfAbsent(message.roomId, _RoomNotification.new);
    final text = switch (message) {
      _ when !prefs.showText => hiddenNotificationText,
      MessageNotification(isInvite: true) => 'Invited you',
      MessageNotification(:final text?) => text,
      _ => hiddenNotificationText,
    };
    room.lines.add(
      NotificationLine(
        sender: message.senderName,
        text: text,
        time: message.time,
      ),
    );
    if (room.lines.length > notificationLinesKept) room.lines.removeAt(0);
    room.count++;
    // The count isn't up yet when the message arrives; cancelling waits until it is.
    room.sawCount = false;
    final body = message.isDm || message.isInvite || !prefs.showText
        ? text
        : '${message.senderName}: $text';
    unawaited(
      presenter.show(
        ShownNotification(
          id: notificationId(account, message.roomId),
          title: message.roomName,
          body: body,
          payload: NotificationTarget(
            account,
            message.roomId,
            thread: message.threadRoot,
          ).encode(),
          group: account,
          lines: List.of(room.lines),
          isDm: message.isDm,
          sound: prefs.sound && message.sound,
          count: room.count,
        ),
      ),
    );
  }

  /// The account's room list changed.
  void onRooms(List<Room> rooms) {
    var total = 0;
    final byId = <String, Room>{};
    for (final room in rooms) {
      byId[room.id] = room;
      total += room.notifyingCount;
    }
    _total = total;
    for (final id in List.of(_rooms.keys)) {
      final room = byId[id];
      final shown = _rooms[id]!;
      if (room == null || room.isMuted) {
        _cancel(id);
      } else if (room.notifyingCount > 0) {
        shown.sawCount = true;
      } else if (shown.sawCount) {
        // It counted, now it doesn't: read here or on another device.
        _cancel(id);
      }
    }
  }

  /// The user is looking at [roomId] now.
  void onLookingAt(String roomId) {
    if (_rooms.containsKey(roomId)) _cancel(roomId);
  }

  /// Takes every notification of the account away (turned off, logged out).
  void cancelAll() => List.of(_rooms.keys).forEach(_cancel);

  void _cancel(String roomId) {
    _rooms.remove(roomId);
    unawaited(presenter.cancel(notificationId(account, roomId)));
  }
}

final class _RoomNotification {
  final lines = <NotificationLine>[];
  var count = 0;

  /// The room list has counted the room's messages since the last one arrived.
  var sawCount = false;
}

/// Tests override this; the real one talks to the OS.
@Riverpod(keepAlive: true)
NotificationPresenter notificationPresenter(Ref ref) =>
    LocalNotificationsPresenter();

/// This device's notification settings.
@Riverpod(keepAlive: true)
class DeviceNotifications extends _$DeviceNotifications {
  @override
  DeviceNotificationPrefs build() {
    final prefs = ref.watch(uiPrefsProvider);
    return DeviceNotificationPrefs(
      enabled: prefs.notificationsEnabled,
      showText: prefs.notificationText,
      sound: prefs.notificationSound,
    );
  }

  /// Turning them on asks the OS for permission where it needs one; without it they stay
  /// off. Returns whether they are on.
  Future<bool> setEnabled({required bool on}) async {
    final granted =
        !on ||
        await ref.read(notificationPresenterProvider).requestPermission();
    final enabled = on && granted;
    state = DeviceNotificationPrefs(
      enabled: enabled,
      showText: state.showText,
      sound: state.sound,
    );
    await ref.read(uiPrefsProvider).setNotificationsEnabled(on: enabled);
    return enabled;
  }

  void setShowText({required bool on}) {
    state = DeviceNotificationPrefs(
      enabled: state.enabled,
      showText: on,
      sound: state.sound,
    );
    unawaited(ref.read(uiPrefsProvider).setNotificationText(on: on));
  }

  void setSound({required bool on}) {
    state = DeviceNotificationPrefs(
      enabled: state.enabled,
      showText: state.showText,
      sound: on,
    );
    unawaited(ref.read(uiPrefsProvider).setNotificationSound(on: on));
  }
}

/// Whether the app's window has the focus (on phones: the app is in front).
@Riverpod(keepAlive: true)
class WindowFocused extends _$WindowFocused {
  @override
  bool build() => true;

  void set({required bool focused}) => state = focused;
}

/// Runs every account's [AccountNotifications] and the app badge; a tap opens the account,
/// room and thread.
@Riverpod(keepAlive: true)
NotificationCoordinator notificationCoordinator(Ref ref) {
  final coordinator = NotificationCoordinator._(ref);
  ref.onDispose(coordinator._dispose);
  return coordinator;
}

final class NotificationCoordinator {
  NotificationCoordinator._(this._ref) {
    final presenter = _ref.read(notificationPresenterProvider);
    unawaited(presenter.start(_open));
    if (_ref.read(deviceNotificationsProvider).enabled) {
      // Asked once on the first start; the OS answers from then on without asking.
      unawaited(presenter.requestPermission());
    }
    _ref
      ..listen(accountsProvider, (_, next) {
        _sync(next.value?.sessions ?? const []);
      }, fireImmediately: true)
      ..listen(deviceNotificationsProvider, (previous, next) {
        if (!next.enabled) {
          for (final account in _accounts.values) {
            account.notifications.cancelAll();
          }
        }
        _updateBadge();
      })
      ..listen(windowFocusedProvider, (_, _) => _lookingChanged())
      ..listen(activeAccountProvider, (_, _) => _lookingChanged());
    final router = _ref.read(routerProvider);
    router.routerDelegate.addListener(_lookingChanged);
    _removeRouterListener = () =>
        router.routerDelegate.removeListener(_lookingChanged);
  }

  final Ref _ref;
  final _accounts = <String, _Account>{};
  late final void Function() _removeRouterListener;
  int? _badge;

  /// The room the user is looking at: open in the focused window, of the account in front.
  (String, String)? get lookingAt {
    if (!_ref.read(windowFocusedProvider)) return null;
    final account = _ref.read(activeAccountProvider);
    if (account == null) return null;
    final GoRouterState state;
    try {
      state = _ref.read(routerProvider).state;
    } on Object {
      // No route yet.
      return null;
    }
    return switch (state.pathParameters['roomId']) {
      final room? => (account, room),
      null => null,
    };
  }

  /// The notifications of [account], for tests.
  @visibleForTesting
  AccountNotifications? notificationsOf(String account) =>
      _accounts[account]?.notifications;

  void _sync(List<MatrixSession> sessions) {
    final ids = {for (final session in sessions) session.userId};
    for (final id in List.of(_accounts.keys)) {
      if (!ids.contains(id)) _accounts.remove(id)!.close();
    }
    for (final session in sessions) {
      if (_accounts.containsKey(session.userId)) continue;
      final notifications = AccountNotifications(
        account: session.userId,
        presenter: _ref.read(notificationPresenterProvider),
        prefs: () => _ref.read(deviceNotificationsProvider),
        isLookingAt: (room) => lookingAt == (session.userId, room),
      );
      _accounts[session.userId] = _Account(notifications, [
        session.notifications.listen(notifications.onMessage),
        session.rooms.listen((rooms) {
          notifications.onRooms(rooms ?? const []);
          _updateBadge();
        }),
      ]);
    }
    _updateBadge();
  }

  void _lookingChanged() {
    if (lookingAt case (final account, final room)) {
      _accounts[account]?.notifications.onLookingAt(room);
    }
  }

  void _updateBadge() {
    final total = _ref.read(deviceNotificationsProvider).enabled
        ? _accounts.values.fold(
            0,
            (sum, account) => sum + account.notifications.total,
          )
        : 0;
    if (total == _badge) return;
    _badge = total;
    unawaited(_ref.read(notificationPresenterProvider).setBadge(total));
  }

  /// A tapped notification: its account in front, then its room (and thread).
  void _open(String payload) {
    final target = NotificationTarget.decode(payload);
    if (target == null) return;
    final accounts = _ref.read(accountsProvider).value;
    if (accounts?.byId(target.account) == null) return;
    _ref.read(accountsProvider.notifier).activate(target.account);
    _ref.read(routerProvider).go(switch (target.thread) {
      final thread? => Routes.thread(target.roomId, thread),
      null => Routes.room(target.roomId),
    });
  }

  void _dispose() {
    _removeRouterListener();
    for (final account in _accounts.values) {
      account.close();
    }
    _accounts.clear();
  }
}

final class _Account {
  _Account(this.notifications, this.subscriptions);

  final AccountNotifications notifications;
  final List<StreamSubscription<Object?>> subscriptions;

  void close() {
    for (final subscription in subscriptions) {
      unawaited(subscription.cancel());
    }
    notifications.cancelAll();
  }
}

/// Starts the notifications with the app and tells them when the window gains or loses the
/// focus.
class OsNotifications extends ConsumerStatefulWidget {
  const OsNotifications({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<OsNotifications> createState() => _OsNotificationsState();
}

class _OsNotificationsState extends ConsumerState<OsNotifications> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) => ref
          .read(windowFocusedProvider.notifier)
          .set(focused: state == AppLifecycleState.resumed),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(notificationCoordinatorProvider);
    return widget.child;
  }
}
