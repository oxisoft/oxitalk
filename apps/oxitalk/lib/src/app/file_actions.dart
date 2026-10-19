import 'dart:io';
import 'dart:math';

import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// What the app does with files outside itself: where to put one for another app, asking
/// where to save one, and opening files and links in the system's apps.
abstract interface class FileActions {
  /// A fresh path for [filename] in a temporary folder, to hand to another app.
  Future<String> tempPathFor(String filename);

  /// Asks the user where to save [filename]; `null` if they cancel.
  Future<String?> askSavePath(String filename);

  /// Opens a file or a link in the system's app for it. Returns `false` if none could.
  Future<bool> launch(Uri uri);
}

final class SystemFileActions implements FileActions {
  const SystemFileActions();

  @override
  Future<String> tempPathFor(String filename) async {
    final id = Random.secure().nextInt(1 << 32).toRadixString(16);
    final dir = Directory(
      '${(await getTemporaryDirectory()).path}/oxitalk-open/$id',
    );
    await dir.create(recursive: true);
    return '${dir.path}/${safeFilename(filename)}';
  }

  @override
  Future<String?> askSavePath(String filename) async =>
      (await getSaveLocation(suggestedName: safeFilename(filename)))?.path;

  @override
  Future<bool> launch(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// [name] without path separators or other characters a file system may refuse.
String safeFilename(String name) {
  final safe = name.replaceAll(RegExp(r'[/\\:*?"<>|\x00-\x1f]'), '_').trim();
  return safe.isEmpty || safe == '.' || safe == '..' ? 'file' : safe;
}

/// For tests: remembers what was asked.
final class FakeFileActions implements FileActions {
  /// What [askSavePath] answers.
  String? savePath = '/saved/file';
  final launched = <Uri>[];

  @override
  Future<String> tempPathFor(String filename) async =>
      '/tmp/open/${safeFilename(filename)}';

  @override
  Future<String?> askSavePath(String filename) async => savePath;

  @override
  Future<bool> launch(Uri uri) async {
    launched.add(uri);
    return true;
  }
}
