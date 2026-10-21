import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/accounts/account_switcher.dart';
import '../features/verify/incoming_verifications.dart';
import 'providers.dart';
import 'router.dart';
import 'theme.dart';
import 'title_bar.dart';

class OxiTalkApp extends ConsumerWidget {
  const OxiTalkApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
    title: 'OxiTalk',
    debugShowCheckedModeBanner: false,
    theme: oxiTheme(Brightness.light),
    darkTheme: oxiTheme(Brightness.dark),
    themeMode: ref.watch(appThemeProvider),
    routerConfig: ref.watch(routerProvider),
    builder: (_, child) => WithTitleBar(
      child: IncomingVerifications(child: AccountHotkeys(child: child!)),
    ),
  );
}
