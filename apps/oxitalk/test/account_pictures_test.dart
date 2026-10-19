import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:oxitalk/src/app/account_pictures.dart';

import 'support/png.dart';

// Plain tests: a widget test's binding answers every HTTP request with 400.
void main() {
  group('server icons', () {
    late Directory dataDir;
    late HttpServer site;
    var requests = <String>[];
    var pages = <String, List<int>>{};

    setUp(() async {
      dataDir = Directory.systemTemp.createTempSync('oxitalk_pictures');
      requests = [];
      pages = {};
      site = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      site.listen((request) async {
        requests.add(request.uri.path);
        final page = pages[request.uri.path];
        request.response.statusCode = page == null ? 404 : 200;
        if (page != null) request.response.add(page);
        await request.response.close();
      });
    });

    tearDown(() async {
      await site.close(force: true);
      dataDir.deleteSync(recursive: true);
    });

    FileAccountPictures pictures() => FileAccountPictures(
      dataDir,
      homePage: (_) => Uri.http('127.0.0.1:${site.port}', '/'),
    );

    test('the home page’s icon first, skipping what can’t be shown', () async {
      pages['/'] =
          '<html><head>'
                  '<link rel="icon" type="image/svg+xml" href="/icon.svg">'
                  "<link href='icons/apple.png' rel='apple-touch-icon'>"
                  '</head></html>'
              .codeUnits;
      pages['/icon.svg'] = '<svg/>'.codeUnits;
      pages['/icons/apple.png'] = png;
      expect(await pictures().serverIcon('acme.com'), png);

      // Then from the file, without asking the site.
      requests.clear();
      expect(await pictures().serverIcon('acme.com'), png);
      expect(requests, isEmpty);
    });

    test('/favicon.ico when the home page declares none', () async {
      final ico = Uint8List.fromList([0, 0, 1, 0, ...png]);
      pages['/'] = '<html></html>'.codeUnits;
      pages['/favicon.ico'] = ico;
      expect(await pictures().serverIcon('acme.com:8448'), ico);
    });

    test('a site without an icon is remembered as such', () async {
      expect(await pictures().serverIcon('acme.com'), isNull);
      requests.clear();
      expect(await pictures().serverIcon('acme.com'), isNull);
      expect(requests, isEmpty);
    });

    test('the picture on this device is kept per account', () async {
      final store = pictures();
      await store.setLocal('@me:acme.com', png);
      expect(await store.local('@me:acme.com'), png);
      expect(await store.local('@other:acme.com'), isNull);
      await store.clearLocal('@me:acme.com');
      expect(await store.local('@me:acme.com'), isNull);
    });
  });

  test('icon links are read from any attribute order and quoting', () {
    expect(
      iconLinks(
        '<LINK REL="shortcut icon" HREF="/a.ico">'
        '<link rel=stylesheet href=/s.css>'
        '<link href=/b.png rel=icon>',
      ),
      ['/a.ico', '/b.png'],
    );
  });
}
