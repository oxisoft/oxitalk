import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/pick_image.dart';
import '../../app/providers.dart';
import '../../app/router.dart';
import '../../matrix/api/matrix.dart';
import 'finders.dart';

/// The part of a room address made from its name: `Team Alpha!` → `team-alpha`.
String aliasFrom(String name) => name
    .toLowerCase()
    .replaceAll(RegExp('[^a-z0-9._=-]+'), '-')
    .replaceAll(RegExp('-+'), '-')
    .replaceAll(RegExp(r'^-|-$'), '');

/// What the New room dialog gives back.
typedef NewRoomForm = ({
  String name,
  String? topic,
  bool public,
  String? alias,
  bool encrypted,
  PickedImage? picture,
});

/// Asks for a new room's details, creates it, and opens it.
Future<void> createRoom(
  BuildContext context,
  WidgetRef ref,
  String account,
) async {
  final router = GoRouter.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final form = await showDialog<NewRoomForm>(
    context: context,
    builder: (_) => NewRoomDialog(server: account.split(':').skip(1).join(':')),
  );
  final session = ref.read(accountsProvider).value?.byId(account);
  if (form == null || session == null) return;
  try {
    final roomId = await session.createRoom(
      name: form.name,
      topic: form.topic,
      public: form.public,
      alias: form.alias,
      encrypted: form.encrypted,
      avatar: form.picture?.bytes,
      avatarMimeType: form.picture?.mimeType,
    );
    router.go(Routes.room(roomId));
  } on MatrixFailure catch (failure) {
    messenger.showSnackBar(
      SnackBar(content: Text('Can’t create the room: ${failure.kind.name}')),
    );
  }
}

/// Lets the user pick a public room or give an address or link, joins it, and opens it; a
/// room they are in already just opens.
Future<void> joinRoom(
  BuildContext context,
  WidgetRef ref,
  String account,
) async {
  final router = GoRouter.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final session = ref.read(accountsProvider).value?.byId(account);
  if (session == null) return;
  final choice = await showDialog<JoinChoice>(
    context: context,
    builder: (_) => JoinRoomDialog(account: account, session: session),
  );
  if (choice == null) return;
  if (choice.joined) {
    router.go(Routes.room(choice.target));
    return;
  }
  try {
    router.go(Routes.room(await session.joinByAddress(choice.target)));
  } on MatrixFailure catch (failure) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          failure.kind == FailureKind.invalidId
              ? 'That isn’t a room address or link'
              : 'Can’t join: ${failure.kind.name}',
        ),
      ),
    );
  }
}

class NewRoomDialog extends ConsumerStatefulWidget {
  const NewRoomDialog({required this.server, super.key});

  /// The account's server, for the address of a public room.
  final String server;

  @override
  ConsumerState<NewRoomDialog> createState() => _NewRoomDialogState();
}

class _NewRoomDialogState extends ConsumerState<NewRoomDialog> {
  final _name = TextEditingController();
  final _topic = TextEditingController();
  final _alias = TextEditingController();

  /// Whether the user changed the address; until then it follows the name.
  var _aliasEdited = false;
  var _public = false;
  var _encrypted = true;
  PickedImage? _picture;

  @override
  void initState() {
    super.initState();
    _name.addListener(() {
      if (!_aliasEdited) _alias.text = aliasFrom(_name.text);
      setState(() {});
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _topic.dispose();
    _alias.dispose();
    super.dispose();
  }

  Future<void> _pickPicture() async {
    final picture = await ref.read(pickImageProvider)();
    if (picture != null && mounted) setState(() => _picture = picture);
  }

  void _create() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final topic = _topic.text.trim();
    final alias = _alias.text.trim();
    Navigator.of(context).pop((
      name: name,
      topic: topic.isEmpty ? null : topic,
      public: _public,
      alias: _public && alias.isNotEmpty ? alias : null,
      encrypted: _encrypted || !_public,
      picture: _picture,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final picture = _picture;
    return AlertDialog(
      key: const Key('newRoom'),
      title: const Text('New room'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: InkWell(
                  key: const Key('newRoom.picture'),
                  customBorder: const CircleBorder(),
                  onTap: () => unawaited(_pickPicture()),
                  child: CircleAvatar(
                    radius: 36,
                    backgroundImage: picture == null
                        ? null
                        : MemoryImage(picture.bytes),
                    child: picture == null
                        ? const Icon(Icons.add_a_photo_outlined)
                        : null,
                  ),
                ),
              ),
              TextField(
                key: const Key('newRoom.name'),
                controller: _name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              TextField(
                key: const Key('newRoom.topic'),
                controller: _topic,
                decoration: const InputDecoration(
                  labelText: 'Topic (optional)',
                ),
              ),
              const SizedBox(height: 16),
              SegmentedButton<bool>(
                key: const Key('newRoom.access'),
                segments: const [
                  ButtonSegment(
                    value: false,
                    icon: Icon(Icons.lock_outline_rounded),
                    label: Text('Private'),
                  ),
                  ButtonSegment(
                    value: true,
                    icon: Icon(Icons.public_rounded),
                    label: Text('Public'),
                  ),
                ],
                selected: {_public},
                onSelectionChanged: (choice) =>
                    setState(() => _public = choice.single),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _public
                      ? 'Listed in your server’s room directory; anyone can join.'
                      : 'Only people you invite can join. Always encrypted.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              if (_public) ...[
                TextField(
                  key: const Key('newRoom.alias'),
                  controller: _alias,
                  onChanged: (_) => _aliasEdited = true,
                  decoration: InputDecoration(
                    labelText: 'Address',
                    prefixText: '#',
                    suffixText: ':${widget.server}',
                  ),
                ),
                SwitchListTile(
                  key: const Key('newRoom.encrypted'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('End-to-end encrypted'),
                  subtitle: const Text('Can’t be turned off later.'),
                  value: _encrypted,
                  onChanged: (on) => setState(() => _encrypted = on),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('newRoom.create'),
          onPressed: _name.text.trim().isEmpty ? null : _create,
          child: const Text('Create'),
        ),
      ],
    );
  }
}

/// Lets the user pick people, invites each to the room, and says how it went in a snack bar.
Future<void> inviteToRoom(
  BuildContext context,
  WidgetRef ref,
  String account,
  String roomId,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final session = ref.read(accountsProvider).value?.byId(account);
  if (session == null) return;
  List<RoomMember> members;
  try {
    members = await ref.read(roomMembersProvider(account, roomId).future);
  } on MatrixFailure {
    members = const [];
  }
  if (!context.mounted) return;
  final userIds = await showDialog<List<String>>(
    context: context,
    builder: (_) => inviteDialog(
      account: account,
      session: session,
      members: {
        for (final member in members)
          member.userId: member.invited ? 'Invited' : 'In the room',
      },
    ),
  );
  if (userIds == null || userIds.isEmpty) return;
  final failed = <String>[];
  for (final userId in userIds) {
    try {
      await session.invite(roomId, userId);
    } on MatrixFailure catch (failure) {
      failed.add(
        failure.kind == FailureKind.invalidId
            ? '$userId (not a user ID)'
            : '$userId (${failure.kind.name})',
      );
    }
  }
  ref.invalidate(roomMembersProvider(account, roomId));
  final invited = userIds.length - failed.length;
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        failed.isEmpty
            ? (invited == 1
                  ? 'Invited ${userIds.single}'
                  : 'Invited $invited people')
            : 'Can’t invite ${failed.join(', ')}',
      ),
    ),
  );
}
