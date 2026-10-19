import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../features/auth/login_screen.dart';
import '../features/chat/chat_pane.dart';
import '../features/chat_info/chat_info.dart';
import '../features/chats/chats_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/verify/verify_screen.dart';
import '../matrix/api/matrix.dart';
import 'providers.dart';
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
  static const chats = '/';

  static String room(String roomId) => '/room/${Uri.encodeComponent(roomId)}';

  static String roomInfo(String roomId) => '${room(roomId)}/info';
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

@Riverpod(keepAlive: true)
GoRouter router(Ref ref) {
  final refresh = ValueNotifier(0);
  // Each account's open chat, so switching back to it returns there.
  final openRooms = <String, String?>{};
  late final GoRouter router;
  ref
    ..listen(accountsProvider, (_, _) => refresh.value++)
    ..listen(activeVerificationProvider, (_, _) => refresh.value++)
    ..listen(activeAccountProvider, (previous, next) {
      if (previous == next) return;
      if (previous != null) {
        openRooms[previous] = router.state.pathParameters['roomId'];
      }
      final room = next == null ? null : openRooms[next];
      router.go(room == null ? Routes.chats : Routes.room(room));
    })
    ..onDispose(refresh.dispose);
  return router = GoRouter(
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
      if (location == Routes.addAccount || location == Routes.settings) {
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
        return Routes.chats;
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
      GoRoute(path: Routes.settings, builder: (_, _) => const SettingsScreen()),
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
              ),
            ],
          ),
        ],
      ),
    ],
  );
}
