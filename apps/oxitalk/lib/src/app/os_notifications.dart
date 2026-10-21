import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:window_manager/window_manager.dart';

import '../util/log.dart';
import 'linux_desktop_entry.dart';

/// One message line of a room's notification.
final class NotificationLine {
  const NotificationLine({
    required this.sender,
    required this.text,
    required this.time,
  });

  final String sender;
  final String text;
  final DateTime time;
}

/// What an OS notification shows: one per room, updated as messages arrive.
final class ShownNotification {
  const ShownNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.payload,
    required this.group,
    this.lines = const [],
    this.isDm = false,
    this.sound = true,
    this.count = 1,
  });

  /// Stable for the room, so the next message replaces the notification.
  final int id;

  /// The room's name.
  final String title;

  /// The latest message as the platform shows it: `Sender: text`, the text alone in a direct
  /// chat, or "New message" when the text is hidden.
  final String body;

  /// What a tap opens, from [NotificationTarget.encode].
  final String payload;

  /// The account, so its notifications are grouped (Android).
  final String group;

  /// The room's messages so far, oldest first, for Android's conversation style.
  final List<NotificationLine> lines;
  final bool isDm;
  final bool sound;

  /// How many messages the notification stands for.
  final int count;
}

/// The account, room and thread a notification opens.
final class NotificationTarget {
  const NotificationTarget(this.account, this.roomId, {this.thread});

  final String account;
  final String roomId;
  final String? thread;

  String encode() => jsonEncode({
    'account': account,
    'room': roomId,
    if (thread != null) 'thread': thread,
  });

  /// `null` for anything else.
  static NotificationTarget? decode(String? payload) {
    if (payload == null) return null;
    try {
      final json = jsonDecode(payload);
      if (json case {
        'account': final String account,
        'room': final String room,
      }) {
        return NotificationTarget(
          account,
          room,
          thread: json['thread'] as String?,
        );
      }
    } on FormatException {
      // Not ours.
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is NotificationTarget &&
      other.account == account &&
      other.roomId == roomId &&
      other.thread == thread;

  @override
  int get hashCode => Object.hash(account, roomId, thread);
}

/// A room's notification ID: the same on every start (FNV-1a over account and room, kept to
/// 31 bits as Android wants), so a notification left from before is replaced and cancelled.
int notificationId(String account, String roomId) {
  var hash = 0x811c9dc5;
  for (final unit in utf8.encode('$account\n$roomId')) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash & 0x7fffffff;
}

/// Shows and takes away OS notifications and sets the app's badge.
abstract interface class NotificationPresenter {
  /// Sets the platform up; [onTap] gets the payload of a tapped notification, also of the one
  /// that started the app.
  Future<void> start(void Function(String payload) onTap);

  /// Asks the OS for permission where it needs one (Android 13+, Apple); `true` if granted
  /// or not needed.
  Future<bool> requestPermission();

  Future<void> show(ShownNotification notification);

  Future<void> cancel(int id);

  /// The number on the app's icon (macOS dock, iOS); 0 takes it away. Ignored elsewhere.
  Future<void> setBadge(int count);
}

/// Notifications through flutter_local_notifications: Android, iOS, macOS, Linux (D-Bus,
/// libnotify's protocol) and Windows.
final class LocalNotificationsPresenter implements NotificationPresenter {
  LocalNotificationsPresenter([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  /// The macOS and iOS runners answer this with the dock or icon badge.
  static const _badge = MethodChannel('io.oxisoft.oxitalk/badge');

  static const _channel = 'messages';
  static const _quietChannel = 'messages_quiet';

  var _started = false;

  @override
  Future<void> start(void Function(String payload) onTap) async {
    // Permissions are asked when notifications are turned on, not at start.
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    try {
      await _plugin.initialize(
        settings: InitializationSettings(
          android: const AndroidInitializationSettings(
            '@mipmap/ic_launcher_monochrome',
          ),
          iOS: darwin,
          macOS: darwin,
          linux: LinuxInitializationSettings(
            defaultActionName: 'Open',
            defaultIcon: ThemeLinuxIcon(linuxAppId),
          ),
          windows: const WindowsInitializationSettings(
            appName: 'OxiTalk',
            appUserModelId: 'io.oxisoft.oxitalk',
            guid: '6f1d3a4e-2c8b-4f5a-9e7d-0b1c2d3e4f5a',
          ),
        ),
        onDidReceiveNotificationResponse: (response) {
          if (response.payload case final payload?) {
            unawaited(_bringToFront());
            onTap(payload);
          }
        },
      );
      _started = true;
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch != null && launch.didNotificationLaunchApp) {
        if (launch.notificationResponse?.payload case final payload?) {
          onTap(payload);
        }
      }
    } on Object catch (error) {
      // No notification service (a Linux desktop without one): the app runs on without.
      appLog(LogLevel.warn, 'notifications', 'not started: $error');
    }
  }

  /// A click on a desktop notification should show the window, as Element Desktop does.
  Future<void> _bringToFront() async {
    if (!Platform.isLinux) return;
    try {
      await windowManager.show();
      await windowManager.focus();
    } on Object catch (error) {
      appLog(LogLevel.warn, 'notifications', 'window not raised: $error');
    }
  }

  @override
  Future<bool> requestPermission() async {
    try {
      if (Platform.isAndroid) {
        return await _plugin
                .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin
                >()
                ?.requestNotificationsPermission() ??
            false;
      }
      if (Platform.isIOS) {
        return await _plugin
                .resolvePlatformSpecificImplementation<
                  IOSFlutterLocalNotificationsPlugin
                >()
                ?.requestPermissions(alert: true, badge: true, sound: true) ??
            false;
      }
      if (Platform.isMacOS) {
        return await _plugin
                .resolvePlatformSpecificImplementation<
                  MacOSFlutterLocalNotificationsPlugin
                >()
                ?.requestPermissions(alert: true, badge: true, sound: true) ??
            false;
      }
    } on Object catch (error) {
      appLog(LogLevel.warn, 'notifications', 'permission: $error');
      return false;
    }
    // Linux and Windows ask nothing.
    return true;
  }

  @override
  Future<void> show(ShownNotification notification) async {
    if (!_started) return;
    final me = const Person(name: 'You', key: 'me');
    final android = AndroidNotificationDetails(
      notification.sound ? _channel : _quietChannel,
      notification.sound ? 'Messages' : 'Messages without sound',
      channelDescription: 'New messages in your chats',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.message,
      playSound: notification.sound,
      groupKey: 'io.oxisoft.oxitalk.${notification.group}',
      number: notification.count,
      when: notification.lines.lastOrNull?.time.millisecondsSinceEpoch,
      styleInformation: MessagingStyleInformation(
        me,
        conversationTitle: notification.isDm ? null : notification.title,
        groupConversation: !notification.isDm,
        messages: [
          for (final line in notification.lines)
            Message(
              line.text,
              line.time,
              Person(name: line.sender, key: line.sender),
            ),
        ],
      ),
    );
    final darwin = DarwinNotificationDetails(
      presentSound: notification.sound,
      threadIdentifier: notification.payload,
    );
    try {
      await _plugin.show(
        id: notification.id,
        title: notification.title,
        body: notification.body,
        payload: notification.payload,
        notificationDetails: NotificationDetails(
          android: android,
          iOS: darwin,
          macOS: darwin,
          linux: LinuxNotificationDetails(
            category: LinuxNotificationCategory.imReceived,
            suppressSound: !notification.sound,
          ),
          windows: WindowsNotificationDetails(
            audio: notification.sound
                ? null
                : WindowsNotificationAudio.silent(),
          ),
        ),
      );
    } on Object catch (error) {
      appLog(LogLevel.warn, 'notifications', 'not shown: $error');
    }
  }

  @override
  Future<void> cancel(int id) async {
    if (!_started) return;
    try {
      await _plugin.cancel(id: id);
    } on Object catch (error) {
      appLog(LogLevel.warn, 'notifications', 'not cancelled: $error');
    }
  }

  @override
  Future<void> setBadge(int count) async {
    if (kIsWeb || !(Platform.isMacOS || Platform.isIOS)) return;
    try {
      await _badge.invokeMethod<void>('setBadge', count);
    } on Object catch (error) {
      appLog(LogLevel.warn, 'notifications', 'badge not set: $error');
    }
  }
}

/// For tests: keeps what is shown, by ID.
final class FakeNotificationPresenter implements NotificationPresenter {
  /// What is showing now.
  final shown = <int, ShownNotification>{};

  /// Every call, like `show 123`, `cancel 123`, `permission`, `badge 2`.
  final calls = <String>[];

  /// What [requestPermission] answers.
  var grantPermission = true;

  int? badge;

  void Function(String payload)? _onTap;

  /// Taps the notification with [id] as the user would.
  void tap(int id) => _onTap?.call(shown[id]!.payload);

  @override
  Future<void> start(void Function(String payload) onTap) async {
    _onTap = onTap;
    calls.add('start');
  }

  @override
  Future<bool> requestPermission() async {
    calls.add('permission');
    return grantPermission;
  }

  @override
  Future<void> show(ShownNotification notification) async {
    shown[notification.id] = notification;
    calls.add('show ${notification.id}');
  }

  @override
  Future<void> cancel(int id) async {
    shown.remove(id);
    calls.add('cancel $id');
  }

  @override
  Future<void> setBadge(int count) async {
    badge = count;
    calls.add('badge $count');
  }
}
