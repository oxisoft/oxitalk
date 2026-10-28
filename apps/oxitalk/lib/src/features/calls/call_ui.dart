import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../matrix/api/matrix.dart';
import '../../ui/avatar.dart';
import 'call_controller.dart';
import 'call_media.dart';

/// The room's call as Matrix says, for the chat header and banner.
final roomCallProvider = StreamProvider.autoDispose
    .family<RoomCall, (String, String)>((ref, key) {
      final (account, roomId) = key;
      final session = ref.watch(
        accountsProvider.select((accounts) => accounts.value?.byId(account)),
      );
      if (session == null) return const Stream.empty();
      return session.roomCall(roomId);
    });

Room? _roomOf(WidgetRef ref, String account, String roomId) => ref
    .watch(roomsProvider(account))
    .value
    ?.where((room) => room.id == roomId)
    .firstOrNull;

/// Starts or joins the room's call: a direct chat rings, a group is notified; a call already
/// going on is joined without either.
Future<void> startCall(
  WidgetRef ref, {
  required String account,
  required String roomId,
  required CallIntent intent,
}) {
  final going =
      ref.read(roomCallProvider((account, roomId))).value?.isActive ?? false;
  final dm =
      ref
          .read(roomsProvider(account))
          .value
          ?.where((room) => room.id == roomId)
          .firstOrNull
          ?.isDm ??
      false;
  return ref
      .read(callControllerProvider.notifier)
      .join(
        account,
        roomId,
        intent: intent,
        notify: going
            ? CallNotify.none
            : dm
            ? CallNotify.ring
            : CallNotify.notify,
      );
}

/// The voice and video call buttons of a chat's header.
class CallButtons extends ConsumerWidget {
  const CallButtons({required this.account, required this.roomId, super.key});

  final String account;
  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(callControllerProvider);
    final here = active?.roomId == roomId && active?.account == account;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          key: const Key('chat.voiceCall'),
          tooltip: here ? 'In this call' : 'Voice call',
          icon: const Icon(Icons.call_outlined),
          onPressed: here
              ? null
              : () => unawaited(
                  startCall(
                    ref,
                    account: account,
                    roomId: roomId,
                    intent: CallIntent.audio,
                  ),
                ),
        ),
        IconButton(
          key: const Key('chat.videoCall'),
          tooltip: here ? 'In this call' : 'Video call',
          icon: const Icon(Icons.videocam_outlined),
          onPressed: here
              ? null
              : () => unawaited(
                  startCall(
                    ref,
                    account: account,
                    roomId: roomId,
                    intent: CallIntent.video,
                  ),
                ),
        ),
      ],
    );
  }
}

/// "Call in progress" over a chat whose call the user isn't in, with Join.
class CallBanner extends ConsumerWidget {
  const CallBanner({required this.account, required this.roomId, super.key});

  final String account;
  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final call = ref.watch(roomCallProvider((account, roomId))).value;
    final active = ref.watch(callControllerProvider);
    final here = active?.roomId == roomId && active?.account == account;
    if (call == null || !call.isActive || here) return const SizedBox.shrink();
    final oxi = context.oxi;
    final names = {for (final p in call.participants) p.name}.toList();
    final who = switch (names) {
      [final one] => one,
      [final one, final two] => '$one and $two',
      _ => '${names.first} and ${names.length - 1} others',
    };
    final video = call.intent == CallIntent.video;
    return Material(
      key: const Key('call.banner'),
      color: oxi.panel,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            left: const BorderSide(color: OxiBrand.yellow, width: 3),
            bottom: BorderSide(color: oxi.line),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(14, 8, 12, 8),
        child: Row(
          children: [
            Icon(
              video ? Icons.videocam_rounded : Icons.call_rounded,
              size: 20,
              color: oxi.text,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Call in progress',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    who,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: oxi.muted, fontSize: 12.5),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              key: const Key('call.join'),
              onPressed: () => unawaited(
                startCall(
                  ref,
                  account: account,
                  roomId: roomId,
                  intent: video ? CallIntent.video : CallIntent.audio,
                ),
              ),
              icon: Icon(video ? Icons.videocam_rounded : Icons.call_rounded),
              label: const Text('Join'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Over the whole app: the call screen, or the bar of an ongoing call while browsing, and the
/// incoming call.
class CallOverlay extends StatefulWidget {
  const CallOverlay({required this.child, super.key});

  final Widget child;

  @override
  State<CallOverlay> createState() => _CallOverlayState();
}

/// Above the app's navigator, so it has an [Overlay] of its own for tooltips and menus.
class _CallOverlayState extends State<CallOverlay> {
  late final OverlayEntry _entry = OverlayEntry(
    builder: (_) => _CallLayer(child: widget.child),
  );

  @override
  void didUpdateWidget(CallOverlay old) {
    super.didUpdateWidget(old);
    if (old.child != widget.child) _entry.markNeedsBuild();
  }

  @override
  Widget build(BuildContext context) => Overlay(initialEntries: [_entry]);
}

class _CallLayer extends ConsumerWidget {
  const _CallLayer({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final call = ref.watch(callControllerProvider);
    final ringing = ref.watch(
      incomingCallsProvider.select((state) => state.ringing.firstOrNull),
    );
    return Stack(
      children: [
        Positioned.fill(
          child: Column(
            children: [
              if (call != null && call.minimized) OngoingCallBar(call: call),
              Expanded(child: child),
            ],
          ),
        ),
        if (call != null && !call.minimized)
          Positioned.fill(child: CallScreen(call: call)),
        if (ringing != null)
          Positioned.fill(child: IncomingCallCard(ringing: ringing)),
      ],
    );
  }
}

String _duration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

/// A tick a second while a call shows its length; tests send one.
final callTickerProvider = StreamProvider.autoDispose<DateTime>(
  (ref) => Stream.periodic(const Duration(seconds: 1), (_) => DateTime.now()),
);

/// The time since [since], ticking.
class _Elapsed extends ConsumerWidget {
  const _Elapsed({required this.since, this.style});

  final DateTime since;
  final TextStyle? style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(callTickerProvider).value ?? DateTime.now();
    final elapsed = now.difference(since);
    return Text(
      _duration(elapsed.isNegative ? Duration.zero : elapsed),
      style: style,
    );
  }
}

/// A thin bar over the app while a call runs in the background.
class OngoingCallBar extends ConsumerWidget {
  const OngoingCallBar({required this.call, super.key});

  final ActiveCallState call;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final room = _roomOf(ref, call.account, call.roomId);
    final controller = ref.read(callControllerProvider.notifier);
    return Material(
      key: const Key('call.bar'),
      color: OxiBrand.ink,
      child: InkWell(
        onTap: () => controller.setMinimized(false),
        child: Container(
          height: 40,
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: OxiBrand.yellow, width: 2),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              const Icon(Icons.call_rounded, size: 18, color: OxiBrand.yellow),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  room?.name ?? 'Call',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _Elapsed(
                since: call.startedAt,
                style: const TextStyle(color: Color(0xFFA8A8B8)),
              ),
              const Spacer(),
              IconButton(
                key: const Key('call.bar.mic'),
                tooltip: call.media.micOn ? 'Mute' : 'Unmute',
                color: Colors.white,
                iconSize: 20,
                icon: Icon(
                  call.media.micOn ? Icons.mic_rounded : Icons.mic_off_rounded,
                ),
                onPressed: () => unawaited(controller.toggleMicrophone()),
              ),
              IconButton(
                key: const Key('call.bar.open'),
                tooltip: 'Back to the call',
                color: Colors.white,
                iconSize: 20,
                icon: const Icon(Icons.open_in_full_rounded),
                onPressed: () => controller.setMinimized(false),
              ),
              IconButton(
                key: const Key('call.bar.hangUp'),
                tooltip: 'Hang up',
                color: OxiBrand.red,
                iconSize: 20,
                icon: const Icon(Icons.call_end_rounded),
                onPressed: () => unawaited(controller.hangUp()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The call: everybody's video or picture, and the buttons.
class CallScreen extends ConsumerWidget {
  const CallScreen({required this.call, super.key});

  final ActiveCallState call;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(callControllerProvider.notifier);
    final room = _roomOf(ref, call.account, call.roomId);
    final media = controller.media;
    final status = switch ((call.phase, call.media.connection)) {
      (CallPhase.failed, _) => call.error ?? 'The call failed',
      (CallPhase.joining, _) => 'Joining…',
      (_, CallConnection.idle || CallConnection.connecting) => 'Connecting…',
      (_, CallConnection.reconnecting) => 'Reconnecting…',
      (_, CallConnection.disconnected) => 'Disconnected',
      _ when call.media.tiles.length < 2 =>
        (room?.isDm ?? false) ? 'Ringing…' : 'Waiting for others…',
      _ => null,
    };
    return Material(
      key: const Key('call.screen'),
      color: OxiBrand.ink,
      child: SafeArea(
        child: Column(
          children: [
            _CallHeader(call: call, room: room),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: _Tiles(call: call, media: media),
                  ),
                  if (status != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 16,
                      child: Center(
                        child: Container(
                          key: const Key('call.status'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 6,
                          ),
                          decoration: ShapeDecoration(
                            color: const Color(0xCC12121B),
                            shape: OxiShapes.small,
                          ),
                          child: Text(
                            status,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (call.phase == CallPhase.failed)
              Padding(
                padding: const EdgeInsets.all(16),
                child: OutlinedButton(
                  key: const Key('call.close'),
                  onPressed: controller.dismiss,
                  child: const Text('Close'),
                ),
              )
            else
              _Controls(call: call, media: media),
          ],
        ),
      ),
    );
  }
}

class _CallHeader extends ConsumerWidget {
  const _CallHeader({required this.call, required this.room});

  final ActiveCallState call;
  final Room? room;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
    child: Row(
      children: [
        IconButton(
          key: const Key('call.minimize'),
          tooltip: 'Back to the chats',
          color: Colors.white,
          icon: const Icon(Icons.close_fullscreen_rounded),
          onPressed: call.phase == CallPhase.failed
              ? null
              : () => ref
                    .read(callControllerProvider.notifier)
                    .setMinimized(true),
        ),
        const SizedBox(width: 4),
        if (room != null)
          MatrixAvatar(
            account: call.account,
            url: room!.avatarUrl,
            name: room!.name,
            seed: room!.id,
            radius: 16,
          ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                room?.name ?? call.roomId,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              Row(
                children: [
                  _Elapsed(
                    since: call.startedAt,
                    style: const TextStyle(
                      color: Color(0xFFA8A8B8),
                      fontSize: 12.5,
                    ),
                  ),
                  if (call.media.encrypted) ...[
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.lock_rounded,
                      key: Key('call.encrypted'),
                      size: 13,
                      color: OxiBrand.yellow,
                    ),
                    const SizedBox(width: 3),
                    const Text(
                      'End-to-end encrypted',
                      style: TextStyle(
                        color: Color(0xFFA8A8B8),
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// One person's tile: their video, or their picture and name.
class _Tile extends ConsumerWidget {
  const _Tile({
    required this.call,
    required this.tile,
    required this.media,
    this.small = false,
  });

  final ActiveCallState call;
  final CallTile tile;
  final CallMedia? media;
  final bool small;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final participant = call.roomCall?.participants
        .where((p) => p.identity == tile.identity)
        .firstOrNull;
    final name = tile.isLocal ? 'You' : (participant?.name ?? tile.userId);
    final border = tile.speaking
        ? const BorderSide(color: OxiBrand.yellow, width: 2)
        : const BorderSide(color: Color(0xFF262634));
    return Container(
      key: Key('call.tile.${tile.identity}'),
      clipBehavior: Clip.antiAlias,
      decoration: ShapeDecoration(
        color: const Color(0xFF1A1A26),
        shape: OxiShapes.all(small ? 6 : 10, side: border),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: tile.hasVideo && media != null
                ? media!.videoView(tile)
                : Center(
                    child: MatrixAvatar(
                      account: call.account,
                      url: participant?.avatarUrl,
                      name: participant?.name ?? tile.userId,
                      seed: tile.userId,
                      radius: small ? 20 : 44,
                    ),
                  ),
          ),
          if (!small)
            Positioned(
              left: 8,
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: ShapeDecoration(
                  color: const Color(0xB30B0B12),
                  shape: OxiShapes.small,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!tile.micOn) ...[
                      const Icon(
                        Icons.mic_off_rounded,
                        size: 14,
                        color: OxiBrand.red,
                      ),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Tiles extends StatelessWidget {
  const _Tiles({required this.call, required this.media});

  final ActiveCallState call;
  final CallMedia? media;

  @override
  Widget build(BuildContext context) {
    var tiles = call.media.tiles;
    if (tiles.isEmpty) {
      // Before the media connects: this device alone.
      tiles = const [CallTile(identity: '', isLocal: true)];
    }
    final local = tiles.where((t) => t.isLocal).firstOrNull;
    final others = tiles.where((t) => !t.isLocal).toList();
    // One other: theirs big, ours small in a corner.
    if (others.length == 1 && local != null) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final width = math.min(180.0, constraints.maxWidth * 0.3);
          return Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: _Tile(call: call, tile: others.first, media: media),
                ),
              ),
              Positioned(
                right: 20,
                top: 20,
                width: width,
                height: width * 3 / 4,
                child: _Tile(
                  call: call,
                  tile: local,
                  media: media,
                  small: true,
                ),
              ),
            ],
          );
        },
      );
    }
    // Everybody in a grid.
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = tiles.length;
        final columns = count <= 1
            ? 1
            : count <= 4
            ? 2
            : 3;
        final rows = (count / columns).ceil();
        final width = constraints.maxWidth / columns;
        final height = constraints.maxHeight / rows;
        return Wrap(
          children: [
            for (final tile in tiles)
              SizedBox(
                width: width,
                height: height,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: _Tile(call: call, tile: tile, media: media),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// A round-ish call button: the cut shape, a label below.
class _CallButton extends StatelessWidget {
  const _CallButton({
    required this.keyName,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.active = false,
    this.danger = false,
  });

  final String keyName;
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  /// Highlighted (yellow): an option that is off, like a muted microphone.
  final bool active;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final background = danger
        ? OxiBrand.red
        : active
        ? OxiBrand.yellow
        : const Color(0xFF262634);
    final foreground = danger
        ? Colors.white
        : active
        ? OxiBrand.ink
        : Colors.white;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: label,
            child: Material(
              color: background,
              shape: OxiShapes.all(12),
              child: InkWell(
                key: Key(keyName),
                customBorder: OxiShapes.all(12),
                onTap: onPressed,
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: Icon(icon, color: foreground, size: 26),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(color: Color(0xFFA8A8B8), fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _Controls extends ConsumerStatefulWidget {
  const _Controls({required this.call, required this.media});

  final ActiveCallState call;
  final CallMedia? media;

  @override
  ConsumerState<_Controls> createState() => _ControlsState();
}

class _ControlsState extends ConsumerState<_Controls> {
  bool _canSwitch = false;

  @override
  void initState() {
    super.initState();
    unawaited(_check());
  }

  @override
  void didUpdateWidget(_Controls old) {
    super.didUpdateWidget(old);
    if (old.media != widget.media) unawaited(_check());
  }

  Future<void> _check() async {
    final can = await widget.media?.canSwitchCamera().catchError((_) => false);
    if (mounted) setState(() => _canSwitch = can ?? false);
  }

  /// The outputs to choose from while the list is open.
  (List<AudioRoute>, AudioRoute?)? _outputs;

  Future<void> _toggleOutputs() async {
    if (_outputs != null) {
      setState(() => _outputs = null);
      return;
    }
    final routes = await widget.media?.audioRoutes();
    if (mounted) setState(() => _outputs = routes);
  }

  Future<void> _choose(AudioRoute route) async {
    setState(() => _outputs = null);
    await widget.media?.setAudioRoute(route);
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(callControllerProvider.notifier);
    final call = widget.call;
    final ready = widget.media != null;
    final outputs = _outputs;
    final buttons = Wrap(
      alignment: WrapAlignment.center,
      children: [
        _CallButton(
          keyName: 'call.mic',
          icon: call.media.micOn ? Icons.mic_rounded : Icons.mic_off_rounded,
          label: call.media.micOn ? 'Mute' : 'Unmute',
          active: !call.media.micOn,
          onPressed: ready
              ? () => unawaited(controller.toggleMicrophone())
              : null,
        ),
        _CallButton(
          keyName: 'call.camera',
          icon: call.media.cameraOn
              ? Icons.videocam_rounded
              : Icons.videocam_off_rounded,
          label: call.media.cameraOn ? 'Camera off' : 'Camera on',
          active: !call.media.cameraOn,
          onPressed: ready ? () => unawaited(controller.toggleCamera()) : null,
        ),
        if (_canSwitch && call.media.cameraOn)
          _CallButton(
            keyName: 'call.switchCamera',
            icon: Icons.cameraswitch_rounded,
            label: 'Switch',
            onPressed: () => unawaited(controller.switchCamera()),
          ),
        _CallButton(
          keyName: 'call.output',
          icon: Icons.volume_up_rounded,
          label: 'Sound',
          active: _outputs != null,
          onPressed: ready ? () => unawaited(_toggleOutputs()) : null,
        ),
        _CallButton(
          keyName: 'call.hangUp',
          icon: Icons.call_end_rounded,
          label: 'Hang up',
          danger: true,
          onPressed: () => unawaited(controller.hangUp()),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (outputs != null)
            Container(
              key: const Key('call.outputs'),
              margin: const EdgeInsets.only(bottom: 12),
              constraints: const BoxConstraints(maxWidth: 360),
              child: Material(
                color: const Color(0xFF1A1A26),
                shape: OxiShapes.medium,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (outputs.$1.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text(
                          'No other outputs',
                          style: TextStyle(color: Color(0xFFA8A8B8)),
                        ),
                      ),
                    for (final route in outputs.$1)
                      ListTile(
                        dense: true,
                        textColor: Colors.white,
                        iconColor: OxiBrand.yellow,
                        leading: route == outputs.$2
                            ? const Icon(Icons.check_rounded)
                            : const SizedBox(width: 24),
                        title: Text(
                          route.label.isEmpty ? route.id : route.label,
                        ),
                        onTap: () => unawaited(_choose(route)),
                      ),
                  ],
                ),
              ),
            ),
          buttons,
        ],
      ),
    );
  }
}

/// The incoming call: who calls, Decline, Voice and Video.
class IncomingCallCard extends ConsumerWidget {
  const IncomingCallCard({required this.ringing, super.key});

  final Ringing ringing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final call = ringing.call;
    final room = _roomOf(ref, ringing.account, call.roomId);
    final calls = ref.read(incomingCallsProvider.notifier);
    final video = call.intent == CallIntent.video;
    final what = !call.ring
        ? 'started a call in ${room?.name ?? 'a group'}'
        : video
        ? 'is video calling you'
        : 'is calling you';
    final accounts = ref.watch(accountsProvider).value?.sessions.length ?? 1;
    return ColoredBox(
      color: const Color(0x990B0B12),
      child: Center(
        child: Material(
          key: const Key('call.incoming'),
          color: OxiBrand.ink,
          shape: OxiShapes.all(
            14,
            side: const BorderSide(color: OxiBrand.yellow, width: 1.5),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 28, 28, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  MatrixAvatar(
                    account: ringing.account,
                    url: call.senderAvatarUrl,
                    name: call.callerName,
                    seed: call.senderId,
                    radius: 40,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    call.callerName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    what,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFA8A8B8)),
                  ),
                  if (accounts > 1) ...[
                    const SizedBox(height: 4),
                    Text(
                      'to ${ringing.account}',
                      style: const TextStyle(
                        color: Color(0xFFA8A8B8),
                        fontSize: 12,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _CallButton(
                        keyName: 'call.decline',
                        icon: Icons.call_end_rounded,
                        label: 'Decline',
                        danger: true,
                        onPressed: () => unawaited(calls.decline(ringing)),
                      ),
                      _CallButton(
                        keyName: 'call.acceptVoice',
                        icon: Icons.call_rounded,
                        label: 'Voice',
                        onPressed: () =>
                            unawaited(calls.accept(ringing, CallIntent.audio)),
                      ),
                      _CallButton(
                        keyName: 'call.acceptVideo',
                        icon: Icons.videocam_rounded,
                        label: 'Video',
                        active: true,
                        onPressed: () =>
                            unawaited(calls.accept(ringing, CallIntent.video)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
