import 'package:flutter/foundation.dart';

/// Where a `https://matrix.to/#/…` or `matrix:` link leads: a room (at one of its
/// messages) or a person.
@immutable
sealed class MatrixLink {
  const MatrixLink();
}

/// A room by its ID (`!opaque` or `!opaque:server`) or address (`#alias:server`), the
/// servers to join it through, and a message in it to show.
final class RoomLink extends MatrixLink {
  const RoomLink(
    this.room, {
    this.via = const [],
    this.eventId,
    this.join = false,
  });

  final String room;
  final List<String> via;
  final String? eventId;

  /// The link asks to join (`action=join` in a `matrix:` link).
  final bool join;

  bool get isAlias => room.startsWith('#');

  /// What `MatrixSession.joinByAddress` takes: the room with its [via] servers.
  String get address => via.isEmpty
      ? room
      : 'https://matrix.to/#/${Uri.encodeComponent(room)}'
            '?${via.map((server) => 'via=${Uri.encodeQueryComponent(server)}').join('&')}';

  @override
  bool operator ==(Object other) =>
      other is RoomLink &&
      other.room == room &&
      listEquals(other.via, via) &&
      other.eventId == eventId &&
      other.join == join;

  @override
  int get hashCode => Object.hash(room, Object.hashAll(via), eventId, join);

  @override
  String toString() => 'RoomLink($room, via: $via, event: $eventId)';
}

/// A person, by user ID; [chat] when the link asks for a direct chat (`action=chat`).
final class UserLink extends MatrixLink {
  const UserLink(this.userId, {this.chat = false});

  final String userId;
  final bool chat;

  @override
  bool operator ==(Object other) =>
      other is UserLink && other.userId == userId && other.chat == chat;

  @override
  int get hashCode => Object.hash(userId, chat);

  @override
  String toString() => 'UserLink($userId, chat: $chat)';
}

final _roomId = RegExp(r'^![^\s:/]+(?::[^\s/]+)?$');
final _alias = RegExp(r'^#[^\s:/]+:[^\s/]+$');
final _userId = RegExp(r'^@[^\s:/]+:[^\s/]+$');
final _eventId = RegExp(r'^\$[^\s/]+$');

const _matrixToHosts = ['matrix.to', 'www.matrix.to'];

/// Whether [url] is a matrix.to or `matrix:` link, which OxiTalk opens itself rather than
/// in the browser (even when [parseMatrixLink] then finds nothing it can open in it).
bool isMatrixLink(String url) {
  final text = url.trim().toLowerCase();
  if (text.startsWith('matrix:')) return true;
  for (final scheme in const ['https://', 'http://']) {
    for (final host in _matrixToHosts) {
      if (text.startsWith('$scheme$host/') || text == '$scheme$host') {
        return true;
      }
    }
  }
  return false;
}

/// The room or person [url] leads to: `https://matrix.to/#/<id>[/<event>][?via=…]` with
/// the ID raw or percent-encoded, or a `matrix:` URI (MSC2312: `matrix:r/alias:server`,
/// `matrix:roomid/id:server[/e/event]`, `matrix:u/user:server`, `?via=…&action=join|chat`),
/// also as matrix.to's page makes them, encoded and without the sigil. `null` for anything
/// else.
MatrixLink? parseMatrixLink(String url) {
  final text = url.trim();
  try {
    if (text.toLowerCase().startsWith('matrix:')) {
      return _parseMatrixUri(text.substring('matrix:'.length));
    }
    if (!isMatrixLink(text)) return null;
    final hash = text.indexOf('#');
    if (hash < 0 || !text.startsWith('#/', hash)) return null;
    final (path, query) = _splitQuery(text.substring(hash + 2));
    final segments = [
      for (final segment in path.split('/'))
        if (segment.isNotEmpty) Uri.decodeComponent(segment),
    ];
    if (segments.isEmpty) return null;
    return _link(
      segments.first,
      event: segments.length > 1 ? segments[1] : null,
      query: query,
    );
  } on FormatException {
    return null;
  } on ArgumentError {
    return null;
  }
}

/// The first matrix.to or `matrix:` link among the command line's arguments, as Linux and
/// Windows pass a clicked link (`oxitalk %U`, `oxitalk.exe "%1"`).
String? linkFromArgs(List<String> args) {
  for (final arg in args) {
    if (isMatrixLink(arg)) return arg.trim();
  }
  return null;
}

MatrixLink? _parseMatrixUri(String rest) {
  var path = rest;
  // matrix://authority/…: the authority says nothing about where the link leads.
  if (path.startsWith('//')) {
    final slash = path.indexOf('/', 2);
    if (slash < 0) return null;
    path = path.substring(slash + 1);
  }
  final (body, query) = _splitQuery(path);
  final segments = body.split('/');
  if (segments.length < 2 || segments.length.isOdd) return null;
  String? id;
  String? event;
  for (var i = 0; i < segments.length; i += 2) {
    final kind = segments[i].toLowerCase();
    final value = Uri.decodeComponent(segments[i + 1]);
    if (value.isEmpty) return null;
    if (i == 0) {
      final sigil = switch (kind) {
        'r' || 'room' => '#',
        'roomid' => '!',
        'u' || 'user' => '@',
        _ => null,
      };
      if (sigil == null) return null;
      id = value.startsWith(sigil) ? value : '$sigil$value';
    } else if (i == 2 && (kind == 'e' || kind == 'event')) {
      event = value.startsWith(r'$') ? value : '\$$value';
    } else {
      return null;
    }
  }
  return _link(id!, event: event, query: query);
}

MatrixLink? _link(
  String id, {
  required String? event,
  required List<(String, String)> query,
}) {
  final via = [
    for (final (key, value) in query)
      if (key == 'via' && value.isNotEmpty) value,
  ];
  final action = query
      .where((pair) => pair.$1 == 'action')
      .map((pair) => pair.$2)
      .lastOrNull;
  if (_userId.hasMatch(id)) return UserLink(id, chat: action == 'chat');
  if (!_roomId.hasMatch(id) && !_alias.hasMatch(id)) return null;
  if (event != null && !_eventId.hasMatch(event)) return null;
  return RoomLink(id, via: via, eventId: event, join: action == 'join');
}

(String, List<(String, String)>) _splitQuery(String text) {
  final mark = text.indexOf('?');
  if (mark < 0) return (text, const []);
  final pairs = <(String, String)>[];
  for (final part in text.substring(mark + 1).split('&')) {
    if (part.isEmpty) continue;
    final equals = part.indexOf('=');
    final key = equals < 0 ? part : part.substring(0, equals);
    final value = equals < 0 ? '' : part.substring(equals + 1);
    pairs.add((Uri.decodeQueryComponent(key), Uri.decodeQueryComponent(value)));
  }
  return (text.substring(0, mark), pairs);
}
