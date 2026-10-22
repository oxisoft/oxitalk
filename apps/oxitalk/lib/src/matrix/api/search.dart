/// Searching a chat: what the app shows, independent of the bridge.
library;

import 'models.dart';

/// A message that contains the searched text.
final class SearchHit {
  const SearchHit({
    required this.eventId,
    required this.sender,
    required this.time,
    required this.text,
    this.threadRoot,
    this.senderName,
    this.senderAvatarUrl,
    this.filename,
    this.mediaKind,
  });

  final String eventId;

  /// The thread's first event, for a reply in a thread.
  final String? threadRoot;
  final String sender;
  final String? senderName;

  /// An `mxc://` URI.
  final String? senderAvatarUrl;
  final DateTime time;

  /// The text as it is now (after edits), or a file's caption; empty for a file without one.
  final String text;

  /// A file's name.
  final String? filename;
  final MediaKind? mediaKind;
}

/// What a search of one chat found on this device.
final class SearchResults {
  const SearchResults({
    this.hits = const [],
    this.total = 0,
    this.searched = 0,
    this.oldest,
  });

  /// The newest first, up to the limit asked for.
  final List<SearchHit> hits;

  /// All matches, also beyond the limit.
  final int total;

  /// How many messages were searched.
  final int searched;

  /// The oldest message searched.
  final DateTime? oldest;
}
