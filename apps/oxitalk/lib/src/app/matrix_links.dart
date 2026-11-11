import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/chat/jump.dart';
import '../features/people/user_profile.dart';
import '../matrix/api/matrix.dart';
import '../util/log.dart';
import 'link_inbox.dart';
import 'matrix_link.dart';
import 'providers.dart';
import 'router.dart';

/// Opens [url] (a matrix.to or `matrix:` link tapped in OxiTalk) as a link from outside
/// would be: in the app, never in the browser.
void openMatrixLinkInApp(WidgetRef ref, String url) =>
    ref.read(pendingLinkProvider.notifier).open(url);

/// Opens the waiting link ([pendingLinkProvider]) once there are accounts to open it in and
/// the active one is verified: a room the accounts are in opens (in the active account if
/// it is among them, else in the one picked), one they aren't in is offered to join, a
/// message link opens its room at it, a person's link their profile.
class MatrixLinks extends ConsumerStatefulWidget {
  const MatrixLinks({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<MatrixLinks> createState() => _MatrixLinksState();
}

class _MatrixLinksState extends ConsumerState<MatrixLinks> {
  bool _busy = false;

  /// How long the room lists may take to arrive before a link is taken as one to join.
  static const _roomsWait = Duration(seconds: 15);

  @override
  void initState() {
    super.initState();
    _router = ref.read(routerProvider)..routerDelegate.addListener(_schedule);
    _schedule();
  }

  late final GoRouter _router;

  @override
  void dispose() {
    _router.routerDelegate.removeListener(_schedule);
    super.dispose();
  }

  bool get _ready {
    final accounts = ref.read(accountsProvider).value;
    if (accounts == null || accounts.sessions.isEmpty) return false;
    if (accounts.active == null) return false;
    if (ref.read(activeVerificationProvider) == VerificationStatus.unverified) {
      return false;
    }
    // Not before the router left the start, sign-in and verification screens: a dialog
    // shown there would go with their page.
    final location = ref.read(routerProvider).state.matchedLocation;
    return location != Routes.starting &&
        location != Routes.login &&
        location != Routes.verify;
  }

  /// Called from listeners, maybe while the tree builds: [_next] runs after.
  void _schedule() => scheduleMicrotask(_next);

  void _next() {
    if (!mounted || _busy || !_ready) return;
    if (ref.read(pendingLinkProvider) == null) return;
    _busy = true;
    final link = ref.read(pendingLinkProvider.notifier).take()!;
    unawaited(
      _open(link)
          .catchError((Object error) {
            appLog(LogLevel.warn, 'links', 'opening a link failed: $error');
          })
          .whenComplete(() {
            _busy = false;
            // Another link may have come meanwhile.
            if (mounted) _schedule();
          }),
    );
  }

  /// A context under the root navigator, for dialogs and sheets.
  BuildContext? get _context => rootNavigatorKey.currentContext;

  void _say(String message) {
    final context = _context;
    if (context == null) return;
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _open(String url) async {
    // The router may have just left the start screen: its page goes with the next frame,
    // and with it a dialog shown on top of it now.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    switch (parseMatrixLink(url)) {
      case null:
        _say('OxiTalk can’t open this link');
      case final UserLink link:
        await _openUser(link);
      case final RoomLink link:
        await _openRoom(link);
    }
  }

  Future<void> _openUser(UserLink link) async {
    final accounts = ref.read(accountsProvider).value!;
    final session = accounts.active!;
    if (link.chat) {
      if (session.dmWith(link.userId) case final room?) {
        _go(session.userId, room);
        return;
      }
    }
    final context = _context;
    if (context == null || !context.mounted) return;
    await showUserProfile(
      context,
      account: session.userId,
      userId: link.userId,
    );
  }

  Future<void> _openRoom(RoomLink link) async {
    final accounts = ref.read(accountsProvider).value!;
    final inRoom = <(String, String)>[];
    for (final session in accounts.sessions) {
      if (await _roomIn(session, link) case final roomId?) {
        inRoom.add((session.userId, roomId));
      }
    }
    if (!mounted) return;
    if (inRoom.isNotEmpty) {
      final (account, roomId) =
          inRoom.where((entry) => entry.$1 == accounts.activeId).firstOrNull ??
          (inRoom.length == 1
              ? inRoom.single
              : await _pick(inRoom) ?? (null, null));
      if (account != null && roomId != null) {
        _go(account, roomId, eventId: link.eventId);
      }
      return;
    }
    final account = await _askToJoin(link, accounts);
    if (account == null || !mounted) return;
    final session = ref.read(accountsProvider).value?.byId(account);
    if (session == null) return;
    try {
      final roomId = await session.joinByAddress(link.address);
      if (!mounted) return;
      _go(account, roomId, eventId: link.eventId);
    } on MatrixFailure catch (error) {
      _say(
        error.kind == FailureKind.invalidId
            ? 'That isn’t a room OxiTalk can join'
            : 'Can’t join ${link.room}: ${error.kind.name}',
      );
    }
  }

  /// The room [link] leads to among [session]'s, if it is in it (or invited): by ID, or by
  /// the main address of one of its rooms.
  Future<String?> _roomIn(MatrixSession session, RoomLink link) async {
    if (link.isAlias) {
      for (final room in session.mentionRooms()) {
        if (room.alias == link.room) return room.roomId;
      }
      return null;
    }
    final rooms = await _firstRooms(session);
    final room = rooms
        ?.where(
          (room) =>
              room.id == link.room &&
              (room.membership == Membership.joined ||
                  room.membership == Membership.invited),
        )
        .firstOrNull;
    return room?.id;
  }

  /// The account's first room list, or `null` if it doesn't come in time. Not with
  /// `Stream.first`: that completes only after the subscription's cancel future.
  Future<List<Room>?> _firstRooms(MatrixSession session) {
    final done = Completer<List<Room>?>();
    StreamSubscription<List<Room>?>? subscription;
    void finish(List<Room>? rooms) {
      if (done.isCompleted) return;
      done.complete(rooms);
      unawaited(subscription?.cancel());
    }

    final timer = Timer(_roomsWait, () => finish(null));
    subscription = session.rooms.listen(
      (rooms) {
        if (rooms != null) finish(rooms);
      },
      onError: (Object _) => finish(null),
      onDone: () => finish(null),
    );
    return done.future.whenComplete(timer.cancel);
  }

  Future<(String, String)?> _pick(List<(String, String)> inRoom) async {
    final context = _context;
    if (context == null || !context.mounted) return null;
    return showDialog<(String, String)>(
      context: context,
      builder: (context) => SimpleDialog(
        key: const Key('link.pickAccount'),
        title: const Text('Open in which account?'),
        children: [
          for (final entry in inRoom)
            SimpleDialogOption(
              key: Key('link.account.${entry.$1}'),
              onPressed: () => Navigator.of(context).pop(entry),
              child: Text(entry.$1),
            ),
        ],
      ),
    );
  }

  /// "Join `room`?", with the account to join with when there are several; that account,
  /// or `null` when cancelled.
  Future<String?> _askToJoin(RoomLink link, AccountsState accounts) async {
    final context = _context;
    if (context == null || !context.mounted) return null;
    var chosen = accounts.activeId!;
    return showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          key: const Key('link.joinDialog'),
          title: Text('Join ${link.room}?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                accounts.sessions.length > 1
                    ? 'None of your accounts is in this room yet. Join with:'
                    : 'You are not in this room yet.',
              ),
              if (accounts.sessions.length > 1)
                for (final session in accounts.sessions)
                  ListTile(
                    key: Key('link.joinAs.${session.userId}'),
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      session.userId == chosen
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_unchecked_rounded,
                    ),
                    title: Text(session.userId),
                    onTap: () => setState(() => chosen = session.userId),
                  ),
            ],
          ),
          actions: [
            OutlinedButton(
              key: const Key('link.joinCancel'),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('link.join'),
              onPressed: () => Navigator.of(context).pop(chosen),
              child: const Text('Join'),
            ),
          ],
        ),
      ),
    );
  }

  /// [account] in front, its room [roomId] open, at [eventId] if given.
  void _go(String account, String roomId, {String? eventId}) {
    ref.read(accountsProvider.notifier).activate(account);
    ref.read(routerProvider).go(Routes.room(roomId));
    if (eventId != null) {
      ref.read(chatJumpProvider((account, roomId)).notifier).show(eventId);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref
      ..listen(pendingLinkProvider, (_, _) => _schedule())
      ..listen(accountsProvider, (_, _) => _schedule())
      ..listen(activeVerificationProvider, (_, _) => _schedule());
    return widget.child;
  }
}
