/// One of the account's top-level joined spaces, in the order Element shows them.
final class Space {
  const Space({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.alias,
    this.roomIds = const {},
  });

  final String id;
  final String name;

  /// An `mxc://` URI.
  final String? avatarUrl;

  /// The space's main address, like `#team:example.org`.
  final String? alias;

  /// The joined rooms in the space or in any space below it. Direct chats are only there if
  /// someone added them, which Matrix rarely does.
  final Set<String> roomIds;

  /// A link to the space that any Matrix app opens.
  String get link => 'https://matrix.to/#/${alias ?? id}';
}

/// A room or subspace directly in a space, as the server lists it: joined or not.
final class SpaceChild {
  const SpaceChild({
    required this.id,
    required this.name,
    this.topic,
    this.avatarUrl,
    this.alias,
    this.joinedMembers = 0,
    this.isSpace = false,
    this.joined = false,
    this.via = const [],
    this.suggested = false,
  });

  final String id;
  final String name;
  final String? topic;

  /// An `mxc://` URI.
  final String? avatarUrl;
  final String? alias;
  final int joinedMembers;
  final bool isSpace;

  /// The user is in it.
  final bool joined;

  /// The servers to join it through.
  final List<String> via;

  /// The space's admins suggest it.
  final bool suggested;

  /// What [MatrixSession.joinByAddress] joins it by: a link with the servers to go through.
  String get joinAddress => [
    'https://matrix.to/#/$id',
    if (via.isNotEmpty)
      '?${[for (final server in via) 'via=$server'].join('&')}',
  ].join();
}

/// A joined room inside a space that leaving the space can leave too.
final class SpaceLeaveRoom {
  const SpaceLeaveRoom({
    required this.id,
    required this.name,
    this.isSpace = false,
    this.lastAdmin = false,
  });

  final String id;
  final String name;
  final bool isSpace;

  /// The user is its last admin: nobody could manage it after.
  final bool lastAdmin;
}
