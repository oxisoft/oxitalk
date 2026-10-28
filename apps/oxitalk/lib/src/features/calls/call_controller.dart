import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../matrix/api/matrix.dart';
import '../../util/log.dart';
import '../chat/voice/audio_io.dart';
import 'call_media.dart';

/// Where a call of this device is.
enum CallPhase {
  /// Asking for the token and joining.
  joining,

  /// Joined; the media connects or is connected ([ActiveCallState.media]).
  inCall,

  /// It couldn't start; [ActiveCallState.error] says why.
  failed,
}

/// The call this device is in (one at a time).
final class ActiveCallState {
  const ActiveCallState({
    required this.account,
    required this.roomId,
    required this.intent,
    required this.phase,
    required this.startedAt,
    this.media = const CallMediaState(),
    this.minimized = false,
    this.error,
    this.roomCall,
  });

  final String account;
  final String roomId;
  final CallIntent intent;
  final CallPhase phase;
  final DateTime startedAt;
  final CallMediaState media;

  /// Shown as a bar over the chats instead of the whole window.
  final bool minimized;
  final String? error;

  /// The room's call as Matrix says (who joined, by device).
  final RoomCall? roomCall;

  ActiveCallState copyWith({
    CallPhase? phase,
    CallMediaState? media,
    bool? minimized,
    String? error,
    RoomCall? roomCall,
  }) => ActiveCallState(
    account: account,
    roomId: roomId,
    intent: intent,
    phase: phase ?? this.phase,
    startedAt: startedAt,
    media: media ?? this.media,
    minimized: minimized ?? this.minimized,
    error: error ?? this.error,
    roomCall: roomCall ?? this.roomCall,
  );
}

/// The call of this device: starting, joining, the media and the buttons.
final callControllerProvider =
    NotifierProvider<CallController, ActiveCallState?>(CallController.new);

final class CallController extends Notifier<ActiveCallState?> {
  JoinedCall? _joined;
  CallMedia? _media;
  final _subscriptions = <StreamSubscription<Object?>>[];

  /// Someone else was in the call at some point (to end a two-person call when they leave).
  bool _hadOthers = false;

  @override
  ActiveCallState? build() {
    ref.onDispose(() => unawaited(_teardown()));
    return null;
  }

  /// Joins the call of [roomId] as [account] (starting it if nobody is in it), with the camera
  /// on for [CallIntent.video]. A call this device is in elsewhere is left first.
  Future<void> join(
    String account,
    String roomId, {
    required CallIntent intent,
    CallNotify notify = CallNotify.none,
  }) async {
    final current = state;
    if (current != null) {
      if (current.roomId == roomId && current.account == account) {
        state = current.copyWith(minimized: false);
        return;
      }
      await hangUp();
    }
    final session = ref.read(accountsProvider).value?.byId(account);
    if (session == null) return;
    state = ActiveCallState(
      account: account,
      roomId: roomId,
      intent: intent,
      phase: CallPhase.joining,
      startedAt: DateTime.now(),
      media: CallMediaState(cameraOn: intent == CallIntent.video),
    );
    final JoinedCall joined;
    try {
      joined = await session.joinCall(roomId, intent: intent, notify: notify);
    } on MatrixFailure catch (failure) {
      appLog(LogLevel.warn, 'calls', 'join failed: $failure');
      if (state?.roomId == roomId) {
        state = state?.copyWith(
          phase: CallPhase.failed,
          error: switch (failure.kind) {
            FailureKind.forbidden =>
              'You can’t join calls in this chat, or the call service refused.',
            FailureKind.network => 'The call service can’t be reached.',
            _ => 'This server has no call service, or it failed.',
          },
        );
      }
      return;
    }
    // Hung up while joining.
    if (state?.roomId != roomId || state?.account != account) {
      unawaited(joined.leave());
      return;
    }
    _joined = joined;
    final media = ref.read(callMediaFactoryProvider)();
    _media = media;
    _hadOthers = false;
    _subscriptions
      ..add(joined.mediaKeys.listen((key) => unawaited(media.setKey(key))))
      ..add(
        media.states.listen((media) {
          if (state case final current?) state = current.copyWith(media: media);
        }),
      )
      ..add(
        session.roomCall(roomId).listen((call) {
          final current = state;
          if (current == null) return;
          state = current.copyWith(roomCall: call);
          final others = call.participants.any((p) => !p.isThisDevice);
          if (others) _hadOthers = true;
          // A call of two ends when the other leaves, as Element's 1:1 calls do.
          final dm =
              ref
                  .read(roomsProvider(account))
                  .value
                  ?.where((room) => room.id == roomId)
                  .firstOrNull
                  ?.isDm ??
              false;
          if (dm && _hadOthers && !others) unawaited(hangUp());
        }, onError: (Object _) {}),
      );
    state = state?.copyWith(phase: CallPhase.inCall);
    try {
      await media.connect(
        url: joined.livekitUrl,
        token: joined.livekitToken,
        camera: intent == CallIntent.video,
      );
    } on Object catch (error) {
      appLog(LogLevel.warn, 'calls', 'media failed: $error');
      state = state?.copyWith(error: 'The call’s media couldn’t connect.');
    }
  }

  /// Leaves the call.
  Future<void> hangUp() async {
    state = null;
    await _teardown();
  }

  Future<void> _teardown() async {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    final joined = _joined;
    final media = _media;
    _joined = null;
    _media = null;
    await Future.wait([
      if (media != null) media.close().catchError((Object _) {}),
      if (joined != null)
        joined.leave().catchError((Object error) {
          appLog(LogLevel.warn, 'calls', 'leave failed: $error');
        }),
    ]);
  }

  /// Takes back a failed call's screen.
  void dismiss() {
    if (state?.phase == CallPhase.failed) state = null;
  }

  CallMedia? get media => _media;

  Future<void> toggleMicrophone() async {
    final current = state;
    final media = _media;
    if (current == null || media == null) return;
    await media.setMicrophone(!current.media.micOn);
  }

  Future<void> toggleCamera() async {
    final current = state;
    final media = _media;
    if (current == null || media == null) return;
    await media.setCamera(!current.media.cameraOn);
  }

  Future<void> switchCamera() async => _media?.switchCamera();

  void setMinimized(bool minimized) {
    if (state case final current?) {
      state = current.copyWith(minimized: minimized);
    }
  }
}

/// A ring shown now, of one of the accounts.
final class Ringing {
  const Ringing(this.account, this.call);

  final String account;
  final IncomingCall call;
}

/// Rings addressed to any of the accounts, while the app runs, and the rings it missed.
final class IncomingCallsState {
  const IncomingCallsState({this.ringing = const [], this.missed = const {}});

  /// Oldest first; the app shows the first.
  final List<Ringing> ringing;

  /// The rings that stopped here unanswered, by their notification event ID.
  final Set<String> missed;
}

final incomingCallsProvider =
    NotifierProvider<IncomingCalls, IncomingCallsState>(IncomingCalls.new);

final class IncomingCalls extends Notifier<IncomingCallsState> {
  final _subscriptions = <String, StreamSubscription<IncomingCallUpdate>>{};

  late Ringer _ringer;

  @override
  IncomingCallsState build() {
    final ringer = _ringer = ref.watch(ringerProvider);
    ref
      ..listen(
        accountsProvider,
        (_, next) => _follow(next.value?.sessions ?? const []),
        fireImmediately: true,
      )
      ..onDispose(() {
        for (final subscription in _subscriptions.values) {
          unawaited(subscription.cancel());
        }
        _subscriptions.clear();
        unawaited(ringer.stop());
      });
    return const IncomingCallsState();
  }

  void _follow(List<MatrixSession> sessions) {
    final ids = {for (final s in sessions) s.userId};
    for (final gone
        in _subscriptions.keys.where((id) => !ids.contains(id)).toList()) {
      unawaited(_subscriptions.remove(gone)?.cancel());
    }
    for (final session in sessions) {
      _subscriptions.putIfAbsent(
        session.userId,
        () => session.incomingCalls.listen(
          (update) => _on(session.userId, update),
          onError: (Object _) {},
        ),
      );
    }
  }

  void _on(String account, IncomingCallUpdate update) {
    switch (update) {
      case CallRinging(:final call):
        // Already in that call here (answered on this device as it rang).
        final active = ref.read(callControllerProvider);
        if (active?.roomId == call.roomId && active?.account == account) return;
        appLog(
          LogLevel.info,
          'calls',
          'ringing: ${call.roomId} from ${call.senderId}',
        );
        state = IncomingCallsState(
          ringing: [...state.ringing, Ringing(account, call)],
          missed: state.missed,
        );
      case CallRingEnded(:final notificationEventId, :final reason):
        final wasShown = state.ringing.any(
          (r) => r.call.notificationEventId == notificationEventId,
        );
        state = IncomingCallsState(
          ringing: [
            for (final r in state.ringing)
              if (r.call.notificationEventId != notificationEventId) r,
          ],
          missed:
              wasShown &&
                  (reason == IncomingCallEnd.expired ||
                      reason == IncomingCallEnd.callEnded)
              ? {...state.missed, notificationEventId}
              : state.missed,
        );
    }
    _ring();
  }

  void _ring() {
    if (state.ringing.any((r) => r.call.ring)) {
      unawaited(_ringer.start());
    } else {
      unawaited(_ringer.stop());
    }
  }

  void _drop(Ringing ringing) {
    state = IncomingCallsState(
      ringing: [
        for (final r in state.ringing)
          if (r.call.notificationEventId != ringing.call.notificationEventId) r,
      ],
      missed: state.missed,
    );
    _ring();
  }

  /// Answers with the camera on ([CallIntent.video]) or off.
  Future<void> accept(Ringing ringing, CallIntent intent) async {
    _drop(ringing);
    ref.read(accountsProvider.notifier).activate(ringing.account);
    await ref
        .read(callControllerProvider.notifier)
        .join(ringing.account, ringing.call.roomId, intent: intent);
  }

  Future<void> decline(Ringing ringing) async {
    _drop(ringing);
    final session = ref.read(accountsProvider).value?.byId(ringing.account);
    try {
      await session?.declineCall(
        ringing.call.roomId,
        ringing.call.notificationEventId,
      );
    } on MatrixFailure catch (failure) {
      appLog(LogLevel.warn, 'calls', 'decline failed: $failure');
    }
  }
}

/// The ring tone while a call rings; tests use a silent one.
abstract interface class Ringer {
  Future<void> start();

  Future<void> stop();
}

final ringerProvider = Provider<Ringer>((ref) {
  final ringer = ToneRinger();
  ref.onDispose(() => unawaited(ringer.dispose()));
  return ringer;
});

/// A ring tone made here (no sound file): two short bursts of a 440 + 480 Hz chord, then quiet,
/// played again until stopped. Through the speaker the voice messages use (pacat on Linux).
final class ToneRinger implements Ringer {
  ToneRinger();

  AudioOutput? _output;
  StreamSubscription<void>? _again;
  bool _ringing = false;

  @override
  Future<void> start() async {
    if (_ringing) return;
    _ringing = true;
    try {
      final output = _output ??= Platform.isLinux
          ? PacatAudioOutput()
          : PlatformAudioOutput();
      await output.open(ringTone(), name: 'oxitalk-ring.wav');
      _again ??= output.completions.listen((_) {
        if (_ringing) unawaited(output.play(Duration.zero));
      });
      if (_ringing) await output.play(Duration.zero);
    } on Object catch (error) {
      appLog(LogLevel.warn, 'calls', 'ring tone: $error');
    }
  }

  @override
  Future<void> stop() async {
    if (!_ringing) return;
    _ringing = false;
    await _output?.pause();
  }

  Future<void> dispose() async {
    _ringing = false;
    await _again?.cancel();
    await _output?.dispose();
  }
}

/// The ring tone as a 16-bit mono WAV: 0.4 s chord, 0.2 s quiet, 0.4 s chord, 2 s quiet.
Uint8List ringTone({int rate = 16000}) {
  const parts = [(0.4, true), (0.2, false), (0.4, true), (2.0, false)];
  final samples = <int>[];
  var n = 0;
  for (final (seconds, on) in parts) {
    final count = (seconds * rate).round();
    for (var i = 0; i < count; i++, n++) {
      if (!on) {
        samples.add(0);
        continue;
      }
      // A short fade at both ends, so it doesn't click.
      final fade = math.min(1.0, math.min(i, count - i) / (0.01 * rate));
      final t = n / rate;
      final value =
          (math.sin(2 * math.pi * 440 * t) + math.sin(2 * math.pi * 480 * t)) *
          0.25 *
          fade;
      samples.add((value * 32767).round());
    }
  }
  final data = ByteData(44 + samples.length * 2);
  void ascii(int at, String text) {
    for (var i = 0; i < text.length; i++) {
      data.setUint8(at + i, text.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  data.setUint32(4, 36 + samples.length * 2, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  data
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little)
    ..setUint16(22, 1, Endian.little)
    ..setUint32(24, rate, Endian.little)
    ..setUint32(28, rate * 2, Endian.little)
    ..setUint16(32, 2, Endian.little)
    ..setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  data.setUint32(40, samples.length * 2, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    data.setInt16(44 + i * 2, samples[i], Endian.little);
  }
  return data.buffer.asUint8List();
}
