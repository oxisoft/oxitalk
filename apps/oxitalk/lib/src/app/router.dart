import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../features/about/about_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/chat/chat_pane.dart';
import '../features/chat/threads.dart';
import '../features/chat_info/chat_info.dart';
import '../features/chat_info/room_notifications.dart';
import '../features/chats/chats_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/verify/verify_screen.dart';
import '../matrix/api/matrix.dart';
import 'providers.dart';
import 'ui_prefs.dart';
import 'theme.dart';

part 'router.g.dart';

/// The root navigator, for dialogs shown from outside a route (an incoming verification).
final rootNavigatorKey = GlobalKey<NavigatorState>();

abstract final class Routes {
  static const starting = '/starting';
  static const login = '/login';
  static const verify = '/verify';
  static const addAccount = '/add-account';
  static const settings = '/settings';

  /// Where Settings › Notifications used to be; it leads to [accountNotifications].
  static const oldNotificationSettings = '/settings/notifications';

  /// One section of Settings: beside the menu on a wide window, a page of its own on a
  /// narrow one.
  static String settingsSection(SettingsSection section) =>
      '$settings/${section.slug}';

  /// The Account section about [userId], whichever account is in front.
  static String settingsAccount(String userId) => Uri(
    path: settingsSection(SettingsSection.account),
    queryParameters: {'user': userId},
  ).toString();

  /// The Account section scrolled to the notifications of [userId] (the active account's
  /// without one).
  static String accountNotifications([String? userId]) => Uri(
    path: settingsSection(SettingsSection.account),
    queryParameters: {'user': ?userId, 'show': 'notifications'},
  ).toString();

  static const about = '/about';
  static const chats = '/';

  static String room(String roomId) => '/room/${Uri.encodeComponent(roomId)}';

  static String roomInfo(String roomId) => '${room(roomId)}/info';

  /// The chat's notification settings, under its info.
  static String roomNotifications(String roomId) =>
      '${roomInfo(roomId)}/notifications';

  /// The thread that starts at [rootEventId].
  static String thread(String roomId, String rootEventId) =>
      '${room(roomId)}/thread/${Uri.encodeComponent(rootEventId)}';

  /// The room's thread list.
  static String threads(String roomId) => '${room(roomId)}/threads';
}

/// The active account's verification status, which decides whether it sees its chats.
@Riverpod(keepAlive: true)
VerificationStatus activeVerification(Ref ref) =>
    switch (ref.watch(activeAccountProvider)) {
      final account? =>
        ref.watch(verificationStatusProvider(account)).value ??
            VerificationStatus.unknown,
      null => VerificationStatus.unknown,
    };

/// Where [account] comes back to: its last open chat, else the chat list.
String homeLocation(UiPrefs prefs, String? account) => switch (account) {
  final account? => switch (prefs.lastRoom(account)) {
    final room? => Routes.room(room),
    null => Routes.chats,
  },
  null => Routes.chats,
};

@Riverpod(keepAlive: true)
GoRouter router(Ref ref) {
  final refresh = ValueNotifier(0);
  // Each account's open chat, kept across starts, so the app and each account come back to it.
  final prefs = ref.read(uiPrefsProvider);
  String home(String? account) => homeLocation(prefs, account);
  late final GoRouter router;
  ref
    ..listen(accountsProvider, (_, _) => refresh.value++)
    ..listen(activeVerificationProvider, (_, _) => refresh.value++)
    ..listen(activeAccountProvider, (previous, next) {
      if (previous != next) router.go(home(next));
    })
    ..onDispose(refresh.dispose);
  router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: Routes.chats,
    refreshListenable: refresh,
    redirect: (context, state) {
      final accounts = ref.read(accountsProvider);
      final location = state.matchedLocation;
      if (accounts.isLoading && !accounts.hasValue) return Routes.starting;
      if (accounts.value?.sessions.isEmpty ?? true) {
        return location == Routes.login ? null : Routes.login;
      }
      if (location == Routes.addAccount ||
          location == Routes.about ||
          location == Routes.settings ||
          location.startsWith('${Routes.settings}/')) {
        return null;
      }
      // An unverified account sees nothing else until it is verified (or logged out).
      if (ref.read(activeVerificationProvider) ==
          VerificationStatus.unverified) {
        return location == Routes.verify ? null : Routes.verify;
      }
      if (location == Routes.login ||
          location == Routes.starting ||
          location == Routes.verify) {
        return home(ref.read(activeAccountProvider));
      }
      return null;
    },
    routes: [
      GoRoute(
        path: Routes.starting,
        builder: (_, _) =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
      GoRoute(path: Routes.login, builder: (_, _) => const LoginScreen()),
      GoRoute(
        path: Routes.settings,
        builder: (_, _) => const SettingsScreen(),
        routes: [
          GoRoute(
            path: ':section',
            // Notifications moved into Account; an unknown section is the menu.
            redirect: (_, state) => switch (state.pathParameters['section']) {
              'notifications' => Routes.accountNotifications(
                state.uri.queryParameters['user'],
              ),
              final slug when SettingsSection.bySlug(slug) == null =>
                Routes.settings,
              _ => null,
            },
            pageBuilder: (context, state) {
              final section = SettingsSection.bySlug(
                state.pathParameters['section'],
              )!;
              // Which account the Account section is about; see editedAccount.
              final user = state.uri.queryParameters['user'];
              // Account scrolled to its notifications (from an old link).
              final showNotifications =
                  state.uri.queryParameters['show'] == 'notifications';
              // Wide: beside the menu. Narrow: a page of its own over it.
              return MediaQuery.sizeOf(context).width >= wideLayoutBreakpoint
                  ? NoTransitionPage(
                      key: state.pageKey,
                      child: SettingsScreen(
                        section: section,
                        user: user,
                        showNotifications: showNotifications,
                      ),
                    )
                  : MaterialPage(
                      key: state.pageKey,
                      child: SettingsSectionScreen(
                        section: section,
                        user: user,
                        showNotifications: showNotifications,
                      ),
                    );
            },
          ),
        ],
      ),
      GoRoute(path: Routes.about, builder: (_, _) => const AboutScreen()),
      GoRoute(
        path: Routes.addAccount,
        builder: (_, _) => const LoginScreen(adding: true),
      ),
      GoRoute(path: Routes.verify, builder: (_, _) => const VerifyScreen()),
      GoRoute(
        path: Routes.chats,
        pageBuilder: (_, _) => const NoTransitionPage(child: ChatsScreen()),
        routes: [
          GoRoute(
            path: 'room/:roomId',
            pageBuilder: (context, state) {
              final roomId = state.pathParameters['roomId']!;
              // Wide: the list stays and the chat opens next to it. Narrow: the chat is a
              // page of its own on top of the list.
              return MediaQuery.sizeOf(context).width >= wideLayoutBreakpoint
                  ? NoTransitionPage(
                      key: state.pageKey,
                      child: ChatsScreen(roomId: roomId),
                    )
                  : MaterialPage(
                      key: state.pageKey,
                      child: ChatScreen(roomId: roomId),
                    );
            },
            routes: [
              GoRoute(
                path: 'info',
                pageBuilder: (context, state) {
                  final roomId = state.pathParameters['roomId']!;
                  // Wide: next to the chat. Narrow: a page of its own over it.
                  return MediaQuery.sizeOf(context).width >=
                          wideLayoutBreakpoint
                      ? NoTransitionPage(
                          key: state.pageKey,
                          child: ChatsScreen(roomId: roomId, showInfo: true),
                        )
                      : MaterialPage(
                          key: state.pageKey,
                          child: ChatInfoScreen(roomId: roomId),
                        );
                },
                routes: [
                  GoRoute(
                    path: 'notifications',
                    pageBuilder: (context, state) {
                      final roomId = state.pathParameters['roomId']!;
                      // Wide: in the info's place. Narrow: a page of its own over it.
                      return MediaQuery.sizeOf(context).width >=
                              wideLayoutBreakpoint
                          ? NoTransitionPage(
                              key: state.pageKey,
                              child: ChatsScreen(
                                roomId: roomId,
                                showNotifications: true,
                              ),
                            )
                          : MaterialPage(
                              key: state.pageKey,
                              child: RoomNotificationsScreen(roomId: roomId),
                            );
                    },
                  ),
                ],
              ),
              GoRoute(
                path: 'thread/:rootId',
                pageBuilder: (context, state) {
                  final roomId = state.pathParameters['roomId']!;
                  final rootId = state.pathParameters['rootId']!;
                  // Wide: beside the chat. Narrow: a page of its own over it.
                  return MediaQuery.sizeOf(context).width >=
                          wideLayoutBreakpoint
                      ? NoTransitionPage(
                          key: state.pageKey,
                          child: ChatsScreen(roomId: roomId, thread: rootId),
                        )
                      : MaterialPage(
                          key: state.pageKey,
                          child: ThreadScreen(
                            roomId: roomId,
                            rootEventId: rootId,
                          ),
                        );
                },
              ),
              GoRoute(
                path: 'threads',
                pageBuilder: (context, state) {
                  final roomId = state.pathParameters['roomId']!;
                  return MediaQuery.sizeOf(context).width >=
                          wideLayoutBreakpoint
                      ? NoTransitionPage(
                          key: state.pageKey,
                          child: ChatsScreen(roomId: roomId, showThreads: true),
                        )
                      : MaterialPage(
                          key: state.pageKey,
                          child: ThreadListScreen(roomId: roomId),
                        );
                },
              ),
            ],
          ),
        ],
      ),
    ],
  );
  // Remembers the open chat as it changes; the list alone means none.
  void remember() {
    final account = ref.read(activeAccountProvider);
    final state = router.state;
    final location = state.matchedLocation;
    if (account == null) return;
    if (location == Routes.chats) {
      unawaited(prefs.setLastRoom(account, null));
    } else if (state.pathParameters['roomId'] case final room?) {
      unawaited(prefs.setLastRoom(account, room));
    }
  }

  router.routerDelegate.addListener(remember);
  ref.onDispose(() => router.routerDelegate.removeListener(remember));
  return router;
}
