import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// A file the user is about to send.
final class PendingFile {
  const PendingFile(this.name, this.mimeType, this.bytes);

  final String name;
  final String mimeType;
  final Uint8List bytes;

  bool get isImage => mimeType.startsWith('image/');
}

const _mimeTypes = {
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'gif': 'image/gif',
  'webp': 'image/webp',
  'mp4': 'video/mp4',
  'webm': 'video/webm',
  'mov': 'video/quicktime',
  'mp3': 'audio/mpeg',
  'ogg': 'audio/ogg',
  'm4a': 'audio/mp4',
  'wav': 'audio/wav',
  'pdf': 'application/pdf',
  'txt': 'text/plain',
  'zip': 'application/zip',
};

/// A file's type from its name's extension.
String mimeTypeOf(String filename) =>
    _mimeTypes[filename.split('.').last.toLowerCase()] ??
    'application/octet-stream';

/// What the app does with files outside itself: where to put one for another app, asking
/// where to save one, picking files to send, the clipboard, and opening files and links in
/// the system's apps.
abstract interface class FileActions {
  /// Asks the user for files to send; empty if they cancel.
  Future<List<PendingFile>> pickFiles();

  /// The files at [paths] (dropped on the window, or copied in a file manager).
  Future<List<PendingFile>> readFiles(List<String> paths);

  /// An image on the clipboard, as a PNG; `null` if there is none.
  Future<Uint8List?> clipboardImage();

  /// Files copied in a file manager, by path.
  Future<List<String>> clipboardFiles();

  /// A fresh path for [filename] in a temporary folder, to hand to another app.
  Future<String> tempPathFor(String filename);

  /// Asks the user where to save [filename]; `null` if they cancel.
  Future<String?> askSavePath(String filename);

  /// Whether [askSavePath] works here: the file picker has no save dialog on Android and
  /// iOS.
  bool get canAskSavePath;

  /// Writes [text] to the file at [path], which the user picked.
  Future<void> writeText(String path, String text);

  /// Opens a file or a link in the system's app for it. Returns `false` if none could.
  Future<bool> launch(Uri uri);
}

final class SystemFileActions implements FileActions {
  const SystemFileActions();

  @override
  Future<List<PendingFile>> pickFiles() async => [
    for (final file in await openFiles())
      PendingFile(
        file.name,
        file.mimeType ?? mimeTypeOf(file.name),
        await file.readAsBytes(),
      ),
  ];

  @override
  Future<List<PendingFile>> readFiles(List<String> paths) async => [
    for (final path in paths)
      if (File(path).statSync().type == FileSystemEntityType.file)
        PendingFile(
          path.split(Platform.pathSeparator).last,
          mimeTypeOf(path),
          await File(path).readAsBytes(),
        ),
  ];

  @override
  Future<Uint8List?> clipboardImage() => Pasteboard.image;

  @override
  Future<List<String>> clipboardFiles() => Pasteboard.files();

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
  bool get canAskSavePath => !(Platform.isAndroid || Platform.isIOS);

  @override
  Future<void> writeText(String path, String text) =>
      File(path).writeAsString(text, flush: true);

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

  /// What [pickFiles] answers.
  List<PendingFile> picked = const [];

  /// What [readFiles] gives for each path.
  final files = <String, PendingFile>{};

  /// What is on the clipboard.
  Uint8List? clipboard;

  @override
  Future<List<PendingFile>> pickFiles() async => picked;

  @override
  Future<List<PendingFile>> readFiles(List<String> paths) async => [
    for (final path in paths) ?files[path],
  ];

  @override
  Future<Uint8List?> clipboardImage() async => clipboard;

  @override
  Future<List<String>> clipboardFiles() async => const [];

  @override
  Future<String> tempPathFor(String filename) async =>
      '/tmp/open/${safeFilename(filename)}';

  @override
  Future<String?> askSavePath(String filename) async => savePath;

  /// What [canAskSavePath] answers.
  var canSave = true;

  @override
  bool get canAskSavePath => canSave;

  /// What [writeText] wrote, by path.
  final written = <String, String>{};

  @override
  Future<void> writeText(String path, String text) async =>
      written[path] = text;

  @override
  Future<bool> launch(Uri uri) async {
    launched.add(uri);
    return true;
  }
}
