import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../util/log.dart';

/// Pictures that tell the accounts apart and aren't on the Matrix server: one the user picked
/// for an account on this device only, and the website icon of each account's server.
abstract interface class AccountPictures {
  /// The picture picked for [userId] on this device, if any.
  Future<Uint8List?> local(String userId);

  Future<void> setLocal(String userId, Uint8List data);

  Future<void> clearLocal(String userId);

  /// The website icon of [server] (a server name, like `matrix.org`), if it has one that
  /// can be shown.
  Future<Uint8List?> serverIcon(String server);
}

/// The server name part of a Matrix user ID: `@me:acme.com` → `acme.com`.
String serverOf(String userId) => userId.substring(userId.indexOf(':') + 1);

/// Keeps the pictures as files under `<dataDir>/pictures/`. A server icon is fetched from the
/// server's website once a week; a server without one is asked again after a day.
final class FileAccountPictures implements AccountPictures {
  FileAccountPictures(
    Directory dataDir, {
    @visibleForTesting Uri Function(String host)? homePage,
  }) : _accounts = Directory('${dataDir.path}/pictures/accounts'),
       _servers = Directory('${dataDir.path}/pictures/servers'),
       _homePage = homePage ?? ((host) => Uri.https(host, '/'));

  static const _iconMaxAge = Duration(days: 7);
  static const _noIconMaxAge = Duration(days: 1);
  static const _maxDownload = 512 * 1024;

  final Directory _accounts;
  final Directory _servers;
  final Uri Function(String host) _homePage;

  File _localFile(String userId) =>
      File('${_accounts.path}/${base64Url.encode(utf8.encode(userId))}');

  @override
  Future<Uint8List?> local(String userId) async {
    final file = _localFile(userId);
    return file.existsSync() ? file.readAsBytes() : null;
  }

  @override
  Future<void> setLocal(String userId, Uint8List data) async {
    await _accounts.create(recursive: true);
    await _localFile(userId).writeAsBytes(data, flush: true);
  }

  @override
  Future<void> clearLocal(String userId) async {
    final file = _localFile(userId);
    if (file.existsSync()) await file.delete();
  }

  @override
  Future<Uint8List?> serverIcon(String server) async {
    final host = server.split(':').first.toLowerCase();
    // An empty file means the server had no icon.
    final file = File('${_servers.path}/$host');
    if (file.existsSync()) {
      final bytes = await file.readAsBytes();
      final age = DateTime.now().difference(file.lastModifiedSync());
      if (age < (bytes.isEmpty ? _noIconMaxAge : _iconMaxAge)) {
        return bytes.isEmpty ? null : bytes;
      }
    }
    final Uint8List? icon;
    try {
      icon = await _download(host);
    } on Object catch (error) {
      // Offline: whatever was there before.
      appLog(LogLevel.debug, 'pictures', 'no icon for $host: $error');
      return file.existsSync() ? _nonEmpty(await file.readAsBytes()) : null;
    }
    await _servers.create(recursive: true);
    await file.writeAsBytes(icon ?? const [], flush: true);
    return icon;
  }

  /// The icons the home page declares, then `/favicon.ico`; the first one Flutter can show.
  Future<Uint8List?> _download(String host) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..userAgent = 'OxiTalk';
    try {
      final home = _homePage(host);
      // A connection failure ends it (offline); a page the site refuses doesn't.
      Future<Uint8List?> page(Uri url) async {
        try {
          return await _get(client, url);
        } on HttpException {
          return null;
        }
      }

      final html = await page(home);
      final candidates = [
        if (html != null)
          ...iconLinks(utf8.decode(html, allowMalformed: true))
              .map(home.resolve),
        home.resolve('/favicon.ico'),
      ];
      for (final url in candidates) {
        final bytes = await page(url);
        if (bytes != null && isShowableImage(bytes)) return bytes;
      }
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static Future<Uint8List> _get(HttpClient client, Uri url) async {
    final request = await client.getUrl(url);
    final response = await request.close().timeout(const Duration(seconds: 10));
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw HttpException('${response.statusCode}', uri: url);
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.timeout(const Duration(seconds: 10))) {
      bytes.add(chunk);
      if (bytes.length > _maxDownload) {
        throw HttpException('too large', uri: url);
      }
    }
    return bytes.takeBytes();
  }

  static Uint8List? _nonEmpty(Uint8List bytes) => bytes.isEmpty ? null : bytes;
}

/// The `href`s of the `<link rel="…icon…">` tags in [html], in order.
List<String> iconLinks(String html) => [
  for (final tag in RegExp(
    r'<link\b[^>]*>',
    caseSensitive: false,
  ).allMatches(html))
    if (_attribute(tag[0]!, 'rel')?.toLowerCase().contains('icon') ?? false)
      ?_attribute(tag[0]!, 'href'),
];

String? _attribute(String tag, String name) {
  final match = RegExp(
    '\\b$name\\s*=\\s*(?:"([^"]*)"|\'([^\']*)\'|([^\\s>]+))',
    caseSensitive: false,
  ).firstMatch(tag);
  return match == null ? null : match[1] ?? match[2] ?? match[3];
}

/// PNG, JPEG, GIF, WebP or ICO, which Flutter decodes on every platform; not SVG.
bool isShowableImage(List<int> bytes) {
  bool startsWith(List<int> magic, [int offset = 0]) =>
      bytes.length >= offset + magic.length &&
      [for (var i = 0; i < magic.length; i++) bytes[offset + i] == magic[i]]
          .every((same) => same);
  return startsWith(const [0x89, 0x50, 0x4E, 0x47]) ||
      startsWith(const [0xFF, 0xD8, 0xFF]) ||
      startsWith(ascii.encode('GIF8')) ||
      (startsWith(ascii.encode('RIFF')) &&
          startsWith(ascii.encode('WEBP'), 8)) ||
      startsWith(const [0x00, 0x00, 0x01, 0x00]);
}

/// For tests: keeps everything in memory and fetches nothing.
final class MemoryAccountPictures implements AccountPictures {
  final locals = <String, Uint8List>{};

  /// What [serverIcon] returns, by server name.
  final serverIcons = <String, Uint8List>{};

  @override
  Future<Uint8List?> local(String userId) async => locals[userId];

  @override
  Future<void> setLocal(String userId, Uint8List data) async =>
      locals[userId] = data;

  @override
  Future<void> clearLocal(String userId) async => locals.remove(userId);

  @override
  Future<Uint8List?> serverIcon(String server) async => serverIcons[server];
}
