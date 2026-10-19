import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../features/auth/login_screen.dart';
import '../features/chat/chat_pane.dart';
import '../features/chats/chats_screen.dart';
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
  static const chats = '/';

  static String room(String roomId) => '/room/${Uri.encodeComponent(roomId)}';
}

@Riverpod(keepAlive: true)
GoRouter router(Ref ref) {
  final authChanged = ValueNotifier(0);
  ref
    ..listen(authProvider, (_, _) => authChanged.value++)
    ..listen(verificationStatusProvider, (_, _) => authChanged.value++)
    ..onDispose(authChanged.dispose);
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: Routes.chats,
    refreshListenable: authChanged,
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      final location = state.matchedLocation;
      if (auth.isLoading && !auth.hasValue) return Routes.starting;
      final loggedIn = auth.value != null;
      if (!loggedIn) return location == Routes.login ? null : Routes.login;
      // An unverified device sees nothing else until it is verified (or logged out).
      final unverified =
          ref.read(verificationStatusProvider).value ==
          VerificationStatus.unverified;
      if (unverified) return location == Routes.verify ? null : Routes.verify;
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
          ),
        ],
      ),
    ],
  );
}
