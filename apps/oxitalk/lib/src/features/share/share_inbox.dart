import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../util/log.dart';

/// What another app shared into OxiTalk (the system's share sheet, Open with, a file dropped
/// on the Dock icon, a file named on the command line): files, by path in a folder of the
/// app's own, and text or a link.
@immutable
final class SharedItems {
  const SharedItems({this.paths = const [], this.text = ''});

  /// From the platform channel: `{paths: [...], text: '...'}`.
  factory SharedItems.fromMap(Map<Object?, Object?> map) => SharedItems(
    paths: [
      for (final path in (map['paths'] as List<Object?>?) ?? const [])
        if (path is String && path.isNotEmpty) path,
    ],
    text: ((map['text'] as String?) ?? '').trim(),
  );

  final List<String> paths;
  final String text;

  bool get isEmpty => paths.isEmpty && text.isEmpty;

  /// The file names, for showing.
  List<String> get names => [
    for (final path in paths) path.split(RegExp(r'[/\\]')).last,
  ];

  /// Both, as when a second share arrives before the first went anywhere.
  SharedItems merge(SharedItems other) => SharedItems(
    paths: [
      ...paths,
      for (final path in other.paths)
        if (!paths.contains(path)) path,
    ],
    text: [
      if (text.isNotEmpty) text,
      if (other.text.isNotEmpty && other.text != text) other.text,
    ].join('\n'),
  );

  @override
  bool operator ==(Object other) =>
      other is SharedItems &&
      listEquals(other.paths, paths) &&
      other.text == text;

  @override
  int get hashCode => Object.hash(Object.hashAll(paths), text);

  @override
  String toString() =>
      'SharedItems(${paths.length} files, ${text.length} chars)';
}

/// The files and links named on the command line, as Linux's and Windows' Open with pass
/// them (`oxitalk %U`): existing files by path or `file://` URI, web links as text; options
/// and anything else are left out.
SharedItems sharedFromArgs(
  List<String> args, {
  bool Function(String path)? isFile,
}) {
  final exists = isFile ?? (path) => File(path).existsSync();
  final paths = <String>[];
  final links = <String>[];
  for (final arg in args) {
    if (arg.isEmpty || arg.startsWith('-')) continue;
    if (arg.startsWith('http://') || arg.startsWith('https://')) {
      links.add(arg);
      continue;
    }
    String path;
    if (arg.startsWith('file:')) {
      try {
        path = Uri.parse(arg).toFilePath();
      } on Object {
        continue;
      }
    } else {
      path = arg;
    }
    if (exists(path) && !paths.contains(path)) paths.add(path);
  }
  return SharedItems(paths: paths, text: links.join('\n'));
}

/// Where shared things come from.
abstract interface class ShareSource {
  /// What was shared since the last call, once; `null` for nothing.
  Future<SharedItems?> take();

  /// Fires when something new was shared while the app runs; [take] then gets it.
  Stream<void> get arrivals;
}

/// The platform's share hand-off: Android's share sheet (MainActivity copies the shared
/// content into the app's cache), the iOS Share Extension (it leaves the files and a manifest
/// in the App Group's container), macOS Open with and the Dock icon. On Linux and Windows
/// only the command line ([args]).
final class PlatformShareSource implements ShareSource {
  PlatformShareSource({List<String> args = const []})
    : _fromArgs = args.isEmpty ? null : sharedFromArgs(args);

  static const _channel = MethodChannel('io.oxisoft.oxitalk/share');

  SharedItems? _fromArgs;
  StreamController<void>? _arrivals;

  static bool get _hasChannel =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);

  @override
  Stream<void> get arrivals {
    final controller = _arrivals ??= StreamController<void>.broadcast();
    if (_hasChannel) {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'sharedArrived') controller.add(null);
      });
    }
    return controller.stream;
  }

  @override
  Future<SharedItems?> take() async {
    var items = _fromArgs;
    _fromArgs = null;
    if (_hasChannel) {
      try {
        final map = await _channel.invokeMapMethod<Object?, Object?>(
          'takeShared',
        );
        if (map != null) {
          final shared = SharedItems.fromMap(map);
          items = items == null ? shared : items.merge(shared);
        }
      } on MissingPluginException {
        // An embedder without the channel.
      } on PlatformException catch (error) {
        appLog(LogLevel.warn, 'share', 'takeShared failed: ${error.code}');
      }
    }
    return items == null || items.isEmpty ? null : items;
  }
}

/// For tests: what [share] was given, handed out by [take].
final class FakeShareSource implements ShareSource {
  final _queue = <SharedItems>[];
  final _arrivals = StreamController<void>.broadcast();

  /// Shares [items], as another app does while OxiTalk runs.
  void share(SharedItems items) {
    _queue.add(items);
    _arrivals.add(null);
  }

  /// Something shared before the app started (a cold start from the share sheet).
  void sharedBeforeStart(SharedItems items) => _queue.add(items);

  @override
  Stream<void> get arrivals => _arrivals.stream;

  @override
  Future<SharedItems?> take() async {
    if (_queue.isEmpty) return null;
    final items = _queue.reduce((a, b) => a.merge(b));
    _queue.clear();
    return items;
  }
}

/// Overridden in main with the command line's arguments.
final shareSourceProvider = Provider<ShareSource>(
  (ref) => PlatformShareSource(),
);

/// What was shared and waits for the user to pick a chat ("Send to…"); `null` for nothing.
/// Asked of the platform at the start, whenever the app comes back to the front, and when
/// the platform says something arrived.
final pendingShareProvider = NotifierProvider<PendingShare, SharedItems?>(
  PendingShare.new,
);

class PendingShare extends Notifier<SharedItems?> {
  @override
  SharedItems? build() {
    final source = ref.watch(shareSourceProvider);
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

  /// Takes what the platform has, added to what waits already.
  Future<void> collect() async {
    final items = await ref.read(shareSourceProvider).take();
    if (!ref.mounted || items == null || items.isEmpty) return;
    appLog(LogLevel.info, 'share', 'received $items');
    state = state?.merge(items) ?? items;
  }

  void clear() => state = null;
}

/// The chat the user picked for shared things, until its message box takes them.
@immutable
final class ShareDelivery {
  const ShareDelivery(this.account, this.roomId, this.items);

  final String account;
  final String roomId;
  final SharedItems items;
}

final shareDeliveryProvider = NotifierProvider<ShareDeliveries, ShareDelivery?>(
  ShareDeliveries.new,
);

class ShareDeliveries extends Notifier<ShareDelivery?> {
  @override
  ShareDelivery? build() => null;

  void deliver(ShareDelivery delivery) => state = delivery;

  /// The delivery for the message box of [roomId] in [account], taken out; `null` if the
  /// waiting one (if any) is for another chat.
  ShareDelivery? takeFor(String account, String roomId) {
    final delivery = state;
    if (delivery == null ||
        delivery.account != account ||
        delivery.roomId != roomId) {
      return null;
    }
    state = null;
    return delivery;
  }
}
