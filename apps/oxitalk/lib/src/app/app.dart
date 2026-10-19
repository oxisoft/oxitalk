import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/verify/incoming_verifications.dart';
import 'router.dart';
import 'theme.dart';

class OxiTalkApp extends ConsumerWidget {
  const OxiTalkApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
    title: 'OxiTalk',
    debugShowCheckedModeBanner: false,
    theme: oxiTheme(Brightness.light),
    darkTheme: oxiTheme(Brightness.dark),
    routerConfig: ref.watch(routerProvider),
    builder: (_, child) => IncomingVerifications(child: child!),
  );
}
