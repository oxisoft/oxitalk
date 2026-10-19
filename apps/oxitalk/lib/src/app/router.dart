import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../features/auth/login_screen.dart';
import '../features/chat/chat_pane.dart';
import '../features/chats/chats_screen.dart';
import 'providers.dart';
import 'theme.dart';

part 'router.g.dart';

abstract final class Routes {
  static const starting = '/starting';
  static const login = '/login';
  static const chats = '/';

  static String room(String roomId) => '/room/${Uri.encodeComponent(roomId)}';
}

@Riverpod(keepAlive: true)
GoRouter router(Ref ref) {
  final authChanged = ValueNotifier(0);
  ref
    ..listen(authProvider, (_, _) => authChanged.value++)
    ..onDispose(authChanged.dispose);
  return GoRouter(
    initialLocation: Routes.chats,
    refreshListenable: authChanged,
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      final location = state.matchedLocation;
      if (auth.isLoading && !auth.hasValue) return Routes.starting;
      final loggedIn = auth.value != null;
      if (!loggedIn) return location == Routes.login ? null : Routes.login;
      if (location == Routes.login || location == Routes.starting) {
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
