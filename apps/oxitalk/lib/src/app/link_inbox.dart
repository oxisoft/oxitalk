import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../util/log.dart';
import 'matrix_link.dart';

/// Where links that open OxiTalk come from: a matrix.to or `matrix:` link clicked in
/// another app or the browser.
abstract interface class LinkSource {
  /// The link that came since the last call, once; `null` for none.
  Future<String?> take();

  /// Fires when a link came while the app runs; [take] then gets it.
  Stream<void> get arrivals;
}

/// The platform's link hand-off on the `io.oxisoft.oxitalk/links` channel: Android's VIEW
/// intents, iOS and macOS URL opens, and on Linux and Windows a second launch's command
/// line, which the running app gets. The first launch's command line is [args].
final class PlatformLinkSource implements LinkSource {
  PlatformLinkSource({List<String> args = const []})
    : _fromArgs = linkFromArgs(args);

  static const channel = MethodChannel('io.oxisoft.oxitalk/links');

  String? _fromArgs;
  StreamController<void>? _arrivals;

  static bool get _hasChannel => !kIsWeb;

  @override
  Stream<void> get arrivals {
    final controller = _arrivals ??= StreamController<void>.broadcast();
    if (_hasChannel) {
      channel.setMethodCallHandler((call) async {
        if (call.method == 'linkArrived') controller.add(null);
      });
    }
    return controller.stream;
  }

  @override
  Future<String?> take() async {
    var link = _fromArgs;
    _fromArgs = null;
    if (_hasChannel) {
      try {
        final arrived = await channel.invokeMethod<String>('takeLink');
        if (arrived != null && arrived.trim().isNotEmpty) link = arrived.trim();
      } on MissingPluginException {
        // An embedder without the channel.
      } on PlatformException catch (error) {
        appLog(LogLevel.warn, 'links', 'takeLink failed: ${error.code}');
      }
    }
    return link;
  }
}

/// For tests: links handed out by [take], the newest.
final class FakeLinkSource implements LinkSource {
  String? _link;
  final _arrivals = StreamController<void>.broadcast();

  /// A link clicked while OxiTalk runs.
  void open(String link) {
    _link = link;
    _arrivals.add(null);
  }

  /// The link the app was started with.
  void openedBeforeStart(String link) => _link = link;

  @override
  Stream<void> get arrivals => _arrivals.stream;

  @override
  Future<String?> take() async {
    final link = _link;
    _link = null;
    return link;
  }
}

/// Overridden in main with the command line's arguments.
final linkSourceProvider = Provider<LinkSource>((ref) => PlatformLinkSource());

/// The link waiting to be opened, raw; `null` for none. From the platform (asked at the
/// start, when the app comes back to the front and when the platform says one came) and
/// from links tapped in OxiTalk itself ([open]). `MatrixLinks` opens it once the accounts
/// can.
final pendingLinkProvider = NotifierProvider<PendingLink, String?>(
  PendingLink.new,
);

class PendingLink extends Notifier<String?> {
  @override
  String? build() {
    final source = ref.watch(linkSourceProvider);
    final arrivals = source.arrivals.listen((_) => unawaited(collect()));
    final lifecycle = AppLifecycleListener(
      onResume: () => unawaited(collect()),
    );
    ref.onDispose(() {
      unawaited(arrivals.cancel());
      lifecycle.dispose();
    });
    unawaited(Future(collect));
    return null;
  }

  /// Takes the platform's link; a newer one replaces one still waiting.
  Future<void> collect() async {
    final link = await ref.read(linkSourceProvider).take();
    if (!ref.mounted || link == null || link.isEmpty) return;
    appLog(LogLevel.info, 'links', 'received a link');
    state = link;
  }

  /// A link tapped in OxiTalk.
  void open(String link) => state = link;

  /// The waiting link, taken out.
  String? take() {
    final link = state;
    state = null;
    return link;
  }
}

/// Android only: whether matrix.to links open in OxiTalk, which only the user can turn on
/// (Settings › Apps › OxiTalk › Open by default), since only matrix.to's owner can verify
/// an app for them.
abstract interface class LinkSettings {
  /// `null` where there is no such setting (other platforms, no channel).
  Future<bool?> opensMatrixTo();

  /// Opens the system screen to turn it on or off.
  Future<void> openSystemSettings();
}

final class PlatformLinkSettings implements LinkSettings {
  const PlatformLinkSettings();

  @override
  Future<bool?> opensMatrixTo() async {
    if (kIsWeb || !Platform.isAndroid) return null;
    try {
      return await PlatformLinkSource.channel.invokeMethod<bool>(
        'opensMatrixTo',
      );
    } on MissingPluginException {
      return null;
    } on PlatformException catch (error) {
      appLog(LogLevel.warn, 'links', 'opensMatrixTo failed: ${error.code}');
      return null;
    }
  }

  @override
  Future<void> openSystemSettings() async {
    try {
      await PlatformLinkSource.channel.invokeMethod<void>('openLinkSettings');
    } on MissingPluginException {
      // Nothing to open.
    } on PlatformException catch (error) {
      appLog(LogLevel.warn, 'links', 'openLinkSettings failed: ${error.code}');
    }
  }
}

/// For tests: the setting as [opens] says; [openSystemSettings] counts.
final class FakeLinkSettings implements LinkSettings {
  FakeLinkSettings({this.opens});

  bool? opens;
  int opened = 0;

  @override
  Future<bool?> opensMatrixTo() async => opens;

  @override
  Future<void> openSystemSettings() async => opened++;
}

final linkSettingsProvider = Provider<LinkSettings>(
  (ref) => const PlatformLinkSettings(),
);

/// [LinkSettings.opensMatrixTo], asked again when the app comes back to the front (the
/// user may have changed it in the system's settings).
final opensMatrixToProvider = FutureProvider.autoDispose<bool?>((ref) {
  final lifecycle = AppLifecycleListener(onResume: ref.invalidateSelf);
  ref.onDispose(lifecycle.dispose);
  return ref.watch(linkSettingsProvider).opensMatrixTo();
});
