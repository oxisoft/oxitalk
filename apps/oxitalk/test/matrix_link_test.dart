import 'package:flutter_test/flutter_test.dart';
import 'package:oxitalk/src/app/matrix_link.dart';

void main() {
  group('matrix.to links', () {
    test('a room ID, percent-encoded, with via (Alex\'s link)', () {
      expect(
        parseMatrixLink(
          'https://matrix.to/#/%21NkkzZ-3Bsp9IDhpB8Vggbwc63cOcvYZbxTEMfMEjCUU'
          '?via=chat.oxisoft.net',
        ),
        const RoomLink(
          '!NkkzZ-3Bsp9IDhpB8Vggbwc63cOcvYZbxTEMfMEjCUU',
          via: ['chat.oxisoft.net'],
        ),
      );
    });

    test('raw and encoded aliases, room IDs and users', () {
      expect(
        parseMatrixLink('https://matrix.to/#/#oxitalk:oxisoft.net'),
        const RoomLink('#oxitalk:oxisoft.net'),
      );
      expect(
        parseMatrixLink('https://matrix.to/#/%23oxitalk%3Aoxisoft.net'),
        const RoomLink('#oxitalk:oxisoft.net'),
      );
      expect(
        parseMatrixLink('https://matrix.to/#/!abc:s.org?via=s.org&via=t.org'),
        const RoomLink('!abc:s.org', via: ['s.org', 't.org']),
      );
      expect(
        parseMatrixLink('https://matrix.to/#/@bob:acme.com'),
        const UserLink('@bob:acme.com'),
      );
      expect(
        parseMatrixLink('  http://matrix.to/#/%40bob%3Aacme.com '),
        const UserLink('@bob:acme.com'),
      );
    });

    test('a message in a room, raw or encoded', () {
      expect(
        parseMatrixLink(r'https://matrix.to/#/!abc:s.org/$evt1?via=s.org'),
        const RoomLink('!abc:s.org', via: ['s.org'], eventId: r'$evt1'),
      );
      expect(
        parseMatrixLink(
          'https://matrix.to/#/%23room%3As.org/%24evt%2B1%3Ds.org',
        ),
        const RoomLink('#room:s.org', eventId: r'$evt+1=s.org'),
      );
    });

    test('anything else is not a link OxiTalk opens', () {
      for (final url in [
        'https://matrix.to/',
        'https://matrix.to/#/',
        'https://matrix.to/#/+group:s.org',
        'https://matrix.to/#/#alias-without-server',
        'https://matrix.to/#/@nobody',
        'https://matrix.to/#/!abc:s.org/not-an-event',
        'https://matrix.to/#/%E0%A4%A',
        'https://example.org/#/!abc:s.org',
        'oxitalk.com',
        '',
      ]) {
        expect(parseMatrixLink(url), isNull, reason: url);
      }
    });
  });

  group('matrix: URIs', () {
    test('as in the spec', () {
      expect(
        parseMatrixLink('matrix:r/oxitalk:oxisoft.net'),
        const RoomLink('#oxitalk:oxisoft.net'),
      );
      expect(
        parseMatrixLink('matrix:roomid/abc:s.org/e/evt1?via=s.org'),
        const RoomLink('!abc:s.org', via: ['s.org'], eventId: r'$evt1'),
      );
      expect(
        parseMatrixLink('matrix:u/bob:acme.com'),
        const UserLink('@bob:acme.com'),
      );
      expect(
        parseMatrixLink('MATRIX:r/oxitalk:oxisoft.net?action=join'),
        const RoomLink('#oxitalk:oxisoft.net', join: true),
      );
      expect(
        parseMatrixLink('matrix://host.example/r/oxitalk:oxisoft.net'),
        const RoomLink('#oxitalk:oxisoft.net'),
      );
    });

    test("as matrix.to's page hands them over: encoded, without the sigil", () {
      expect(
        parseMatrixLink(
          'matrix:roomid/NkkzZ-3Bsp9IDhpB8Vggbwc63cOcvYZbxTEMfMEjCUU'
          '%3Achat.oxisoft.net?action=join&via=chat.oxisoft.net',
        ),
        const RoomLink(
          '!NkkzZ-3Bsp9IDhpB8Vggbwc63cOcvYZbxTEMfMEjCUU:chat.oxisoft.net',
          via: ['chat.oxisoft.net'],
          join: true,
        ),
      );
      expect(
        parseMatrixLink(
          'matrix:r/oxitalk%3Aoxisoft.net?action=join&via=a.org&via=b.org',
        ),
        const RoomLink(
          '#oxitalk:oxisoft.net',
          via: ['a.org', 'b.org'],
          join: true,
        ),
      );
      expect(
        parseMatrixLink(
          'matrix:roomid/abc%3As.org/e/evt123?action=join&via=s.org',
        ),
        const RoomLink(
          '!abc:s.org',
          via: ['s.org'],
          eventId: r'$evt123',
          join: true,
        ),
      );
      expect(
        parseMatrixLink('matrix:u/bob%3Aacme.com?action=chat'),
        const UserLink('@bob:acme.com', chat: true),
      );
    });

    test('a sigil already there is not doubled', () {
      expect(
        parseMatrixLink('matrix:r/%23oxitalk%3Aoxisoft.net'),
        const RoomLink('#oxitalk:oxisoft.net'),
      );
      expect(
        parseMatrixLink('matrix:roomid/!abc:s.org/e/%24evt'),
        const RoomLink('!abc:s.org', eventId: r'$evt'),
      );
    });

    test('broken ones are nothing', () {
      for (final url in [
        'matrix:',
        'matrix:r',
        'matrix:r/',
        'matrix:x/abc:s.org',
        'matrix:r/no-server',
        'matrix:u/bob',
        'matrix:roomid/abc:s.org/e',
        'matrix:roomid/abc:s.org/x/evt',
        'matrix:roomid/abc:s.org/e/evt/e/again',
        'matrix:r/%ZZ',
      ]) {
        expect(parseMatrixLink(url), isNull, reason: url);
      }
    });
  });

  test('which links OxiTalk opens itself', () {
    expect(isMatrixLink('https://matrix.to/#/#a:b.c'), isTrue);
    expect(isMatrixLink('https://www.matrix.to/#/#a:b.c'), isTrue);
    expect(isMatrixLink('matrix:u/bob:acme.com'), isTrue);
    expect(isMatrixLink('https://matrix.top/#/#a:b.c'), isFalse);
    expect(isMatrixLink('https://example.org/?u=https://matrix.to/'), isFalse);
  });

  test('the join address carries the via servers', () {
    expect(const RoomLink('#a:b.c').address, '#a:b.c');
    expect(
      const RoomLink('!abc', via: ['s.org', 't.org']).address,
      'https://matrix.to/#/!abc?via=s.org&via=t.org',
    );
    // The round trip gives the same room.
    const real = RoomLink('#ab:c.d', via: ['s.org']);
    expect(parseMatrixLink(real.address), real);
  });

  test('the command line names the link among other arguments', () {
    expect(
      linkFromArgs(['--x', '/home/me/a.png', 'matrix:r/a:b.c']),
      'matrix:r/a:b.c',
    );
    expect(linkFromArgs(['https://oxitalk.com']), isNull);
    expect(linkFromArgs(const []), isNull);
  });
}
