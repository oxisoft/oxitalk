import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../matrix/api/matrix.dart';
import '../../ui/avatar.dart';
import '../../ui/format.dart';
import '../chat/media_views.dart';
import '../chat/pins.dart';
import '../chats/new_room.dart';
import '../chats/notification_actions.dart';
import 'member_actions.dart';
import 'room_settings.dart';

/// A chat's info of the active account as a page of its own (narrow windows).
class ChatInfoScreen extends ConsumerWidget {
  const ChatInfoScreen({required this.roomId, super.key});

  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(activeAccountProvider);
    if (account == null) return const SizedBox.shrink();
    return ChatInfoPane(
      key: ValueKey((account, roomId)),
      account: account,
      roomId: roomId,
    );
  }
}

/// A chat's picture, name, address, topic, members and encryption, and its members, media,
/// files and links in tabs. In the chat's place; Back or Esc returns to the chat.
class ChatInfoPane extends ConsumerStatefulWidget {
  const ChatInfoPane({required this.account, required this.roomId, super.key});

  final String account;
  final String roomId;

  @override
  ConsumerState<ChatInfoPane> createState() => _ChatInfoPaneState();
}

class _ChatInfoPaneState extends ConsumerState<ChatInfoPane> {
  String get account => widget.account;
  String get roomId => widget.roomId;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  /// Esc returns to the chat, unless a dialog (like the image viewer) is over the info.
  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape ||
        !(ModalRoute.of(context)?.isCurrent ?? false)) {
      return false;
    }
    _back();
    return true;
  }

  void _back() => context.go(Routes.room(roomId));

  @override
  Widget build(BuildContext context) {
    final details = ref.watch(roomDetailsProvider(account, roomId));
    final settings = ref.watch(roomSettingsProvider(account, roomId)).value;
    // A change to the room's state, here or elsewhere, shows in the header too.
    ref.listen(roomSettingsProvider(account, roomId), (previous, next) {
      final before = previous?.value;
      if (before != null && next.value != before) {
        ref.invalidate(roomDetailsProvider(account, roomId));
      }
    });
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: BackButton(key: const Key('info.back'), onPressed: _back),
          title: const Text('Chat info'),
          actions: [
            // Only when the power level allows changing the name, topic or picture.
            if (settings case final settings?
                when settings.permissions.details && details.hasValue)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: OutlinedButton.icon(
                  key: const Key('info.edit'),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit'),
                  onPressed: () => unawaited(
                    editRoomDetails(
                      context,
                      account: account,
                      settings: settings,
                      shownName: details.requireValue.name,
                    ),
                  ),
                ),
              ),
          ],
        ),
        body: NestedScrollView(
          headerSliverBuilder: (context, _) => [
            SliverToBoxAdapter(
              child: switch (details) {
                // Kept while it is fetched again after a change.
                AsyncValue(:final value?) => _Header(
                  account: account,
                  details: value,
                ),
                AsyncError() => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Can’t load this chat’s details.'),
                ),
                _ => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              },
            ),
            SliverToBoxAdapter(
              child: _NotificationsRow(account: account, roomId: roomId),
            ),
            if (settings != null)
              SliverToBoxAdapter(
                child: ListTile(
                  key: const Key('info.security'),
                  leading: const Icon(Icons.shield_outlined),
                  title: const Text('Security & privacy'),
                  subtitle: Text(securitySummary(settings)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.go(Routes.roomSecurity(roomId)),
                ),
              ),
            SliverToBoxAdapter(
              child: PinnedMessagesRow(account: account, roomId: roomId),
            ),
            const SliverToBoxAdapter(
              child: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(text: 'Members'),
                  Tab(text: 'Photos & videos'),
                  Tab(text: 'Audio'),
                  Tab(text: 'Documents'),
                  Tab(text: 'Links'),
                ],
              ),
            ),
          ],
          body: TabBarView(
            children: [
              _Members(account: account, roomId: roomId),
              _MediaTab(
                account: account,
                roomId: roomId,
                kinds: const {MediaKind.image, MediaKind.video},
                empty: 'No photos or videos',
                grid: true,
              ),
              _MediaTab(
                account: account,
                roomId: roomId,
                kinds: const {MediaKind.audio},
                empty: 'No audio',
              ),
              _MediaTab(
                account: account,
                roomId: roomId,
                kinds: const {MediaKind.file},
                empty: 'No documents',
              ),
              _Links(account: account, roomId: roomId),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.account, required this.details});

  final String account;
  final RoomDetails details;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dmUser = details.dmUserId;
    final topic = details.topic;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        children: [
          MatrixAvatar(
            account: account,
            url: details.avatarUrl,
            name: details.name,
            seed: details.roomId,
            radius: 44,
          ),
          const SizedBox(height: 12),
          Text(
            details.name,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge,
          ),
          SelectableText(
            dmUser ?? details.alias ?? details.roomId,
            key: const Key('info.id'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
          if (topic != null && topic.isNotEmpty) ...[
            const SizedBox(height: 8),
            SelectableText(topic, textAlign: TextAlign.center),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            alignment: WrapAlignment.center,
            children: [
              if (dmUser == null)
                Chip(
                  avatar: const Icon(Icons.group_outlined, size: 18),
                  label: Text(
                    details.joinedMembers == 1
                        ? '1 member'
                        : '${details.joinedMembers} members',
                  ),
                ),
              Chip(
                avatar: Icon(
                  details.isEncrypted
                      ? Icons.lock_rounded
                      : Icons.lock_open_rounded,
                  size: 18,
                ),
                label: Text(
                  details.isEncrypted
                      ? 'End-to-end encrypted'
                      : 'Not encrypted',
                ),
              ),
              if (details.dmUserVerified case final verified?)
                Chip(
                  avatar: Icon(
                    verified
                        ? Icons.verified_user_rounded
                        : Icons.gpp_maybe_outlined,
                    size: 18,
                  ),
                  label: Text(verified ? 'Verified' : 'Not verified'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The chat's notification mode; opens its notification settings.
class _NotificationsRow extends ConsumerWidget {
  const _NotificationsRow({required this.account, required this.roomId});

  final String account;
  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final room = ref
        .watch(roomsProvider(account))
        .value
        ?.where((room) => room.id == roomId)
        .firstOrNull;
    final mode = room?.notificationMode;
    return ListTile(
      key: const Key('info.notifications'),
      leading: Icon(
        room?.isMuted ?? false
            ? Icons.notifications_off_outlined
            : Icons.notifications_outlined,
      ),
      title: const Text('Notifications'),
      subtitle: room == null
          ? null
          : Text(
              mode == null
                  ? 'Default (${notificationModeLabel(room.defaultNotificationMode)})'
                  : notificationModeLabel(mode),
            ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => context.go(Routes.roomNotifications(roomId)),
    );
  }
}

class _Members extends ConsumerWidget {
  const _Members({required this.account, required this.roomId});

  final String account;
  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => switch (ref.watch(
    roomMembersProvider(account, roomId),
  )) {
    AsyncData(:final value) => ListView.builder(
      // The first row invites someone.
      itemCount: value.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return ListTile(
            key: const Key('info.invite'),
            leading: const IconAvatar(icon: Icons.person_add_alt_rounded),
            title: const Text('Invite people'),
            onTap: () => unawaited(inviteToRoom(context, ref, account, roomId)),
          );
        }
        final member = value[index - 1];
        final name = member.displayName ?? member.userId;
        final level = member.powerLevel;
        final role = switch (level) {
          null => 'Creator',
          adminLevel || moderatorLevel || memberLevel => switch (member.role) {
            MemberRole.admin => 'Admin',
            MemberRole.moderator => 'Moderator',
            MemberRole.member => null,
          },
          _ => roleName(level),
        };
        final label = [
          if (member.banned) 'Banned' else ?role,
          if (member.invited) 'Invited',
        ].join(' · ');
        return ListTile(
          key: Key('member.${member.userId}'),
          leading: MatrixAvatar(
            account: account,
            url: member.avatarUrl,
            name: name,
            seed: member.userId,
            radius: 20,
          ),
          title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            member.userId,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (label.isNotEmpty) Text(label),
              MemberMenu(account: account, roomId: roomId, member: member),
            ],
          ),
        );
      },
    ),
    AsyncError() => const Center(child: Text('Can’t load the members.')),
    _ => const Center(child: CircularProgressIndicator()),
  };
}

/// Pages back through the chat's files and links while a tab shows them: at first, and
/// whenever its list is scrolled near the end.
mixin _LoadsOlder<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  String get account;
  String get roomId;

  var _loading = false;
  var _reachedStart = false;

  bool get reachedStart => _reachedStart;

  Future<void> loadOlder() async {
    if (_loading || _reachedStart) return;
    final timeline = ref.read(mediaTimelineProvider(account, roomId)).value;
    if (timeline == null) return;
    _loading = true;
    try {
      final reached = await timeline.loadOlder();
      if (mounted) setState(() => _reachedStart = reached);
    } on MatrixFailure {
      // Tried again on the next scroll.
    } finally {
      _loading = false;
    }
  }

  /// Loads more when there are few items yet or the list is near its end.
  void loadIfShort(int count) {
    if (count < 30) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => unawaited(loadOlder()),
      );
    }
  }

  bool onScroll(ScrollNotification notification) {
    if (notification.metrics.extentAfter < 400) unawaited(loadOlder());
    return false;
  }

  /// The list's state when it has nothing: still looking, or nothing there.
  Widget emptyOr(String empty) => Center(
    child: _reachedStart ? Text(empty) : const CircularProgressIndicator(),
  );
}

class _MediaTab extends ConsumerStatefulWidget {
  const _MediaTab({
    required this.account,
    required this.roomId,
    required this.kinds,
    required this.empty,
    this.grid = false,
  });

  final String account;
  final String roomId;
  final Set<MediaKind> kinds;
  final String empty;
  final bool grid;

  @override
  ConsumerState<_MediaTab> createState() => _MediaTabState();
}

class _MediaTabState extends ConsumerState<_MediaTab>
    with _LoadsOlder<_MediaTab> {
  @override
  String get account => widget.account;

  @override
  String get roomId => widget.roomId;

  @override
  Widget build(BuildContext context) {
    final entries =
        ref.watch(mediaTimelineEntriesProvider(account, roomId)).value ??
        const <TimelineEntry>[];
    // Newest first.
    final items = [
      for (final entry in entries.reversed)
        if (entry is MediaEntry && widget.kinds.contains(entry.media.kind))
          entry,
    ];
    loadIfShort(items.length);
    if (items.isEmpty) return emptyOr(widget.empty);
    return NotificationListener<ScrollNotification>(
      onNotification: onScroll,
      child: widget.grid
          ? GridView.builder(
              padding: const EdgeInsets.all(4),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 120,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
              ),
              itemCount: items.length,
              itemBuilder: (context, index) => LayoutBuilder(
                builder: (context, constraints) => MediaPreview(
                  account: account,
                  media: items[index].media,
                  maxSize: constraints.maxWidth,
                  square: true,
                  onTap: () =>
                      showMedia(context, ref, account, items[index].media),
                ),
              ),
            )
          : ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, index) => Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 2,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FileRow(account: account, media: items[index].media),
                    Text(
                      '${items[index].senderName ?? items[index].sender} · '
                      '${dayLabel(items[index].time)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// A link someone posted, with who and when.
final class _Link {
  const _Link(this.url, this.entry);

  final String url;
  final MessageEntry entry;
}

final _url = RegExp(r'https?://[^\s<>"]+');

/// The links in [text], without punctuation that ends the sentence around them.
List<String> linksIn(String text) => [
  for (final match in _url.allMatches(text))
    match[0]!.replaceFirst(RegExp(r'[.,;:!?)\]]+$'), ''),
];

class _Links extends ConsumerStatefulWidget {
  const _Links({required this.account, required this.roomId});

  final String account;
  final String roomId;

  @override
  ConsumerState<_Links> createState() => _LinksState();
}

class _LinksState extends ConsumerState<_Links> with _LoadsOlder<_Links> {
  @override
  String get account => widget.account;

  @override
  String get roomId => widget.roomId;

  @override
  Widget build(BuildContext context) {
    final entries =
        ref.watch(mediaTimelineEntriesProvider(account, roomId)).value ??
        const <TimelineEntry>[];
    final links = [
      for (final entry in entries.reversed)
        if (entry is MessageEntry)
          for (final url in linksIn(entry.body)) _Link(url, entry),
    ];
    loadIfShort(links.length);
    if (links.isEmpty) return emptyOr('No links');
    final theme = Theme.of(context);
    return NotificationListener<ScrollNotification>(
      onNotification: onScroll,
      child: ListView.builder(
        itemCount: links.length,
        itemBuilder: (context, index) {
          final link = links[index];
          return ListTile(
            leading: const Icon(Icons.link_rounded),
            title: Text(
              link.url,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: theme.colorScheme.primary),
            ),
            subtitle: Text(
              '${link.entry.senderName ?? link.entry.sender} · '
              '${dayLabel(link.entry.time)}',
            ),
            onTap: () => unawaited(
              ref.read(fileActionsProvider).launch(Uri.parse(link.url)),
            ),
          );
        },
      ),
    );
  }
}
