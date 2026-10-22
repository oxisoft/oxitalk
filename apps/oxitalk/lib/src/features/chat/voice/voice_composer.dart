import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../matrix/api/matrix.dart';
import '../../../ui/format.dart';
import 'audio_io.dart';
import 'audio_player_view.dart';

/// Where a voice message in the composer is.
sealed class VoiceDraftState {
  const VoiceDraftState();
}

final class VoiceIdle extends VoiceDraftState {
  const VoiceIdle();
}

/// The microphone is being opened.
final class VoiceStarting extends VoiceDraftState {
  const VoiceStarting({required this.locked});

  final bool locked;
}

final class VoiceRecording extends VoiceDraftState {
  const VoiceRecording({
    required this.elapsed,
    required this.levels,
    required this.locked,
    this.slide = Offset.zero,
  });

  final Duration elapsed;

  /// The latest loudness readings, oldest first, each from 0 to 1.
  final List<double> levels;

  /// Recording on without the button held: by a click or tap, or after sliding up.
  final bool locked;

  /// How far the held button was moved.
  final Offset slide;
}

/// The recording is being encoded.
final class VoiceEncoding extends VoiceDraftState {
  const VoiceEncoding();
}

/// Recorded: it can be played, sent or dropped.
final class VoicePreview extends VoiceDraftState {
  const VoicePreview(this.clip);

  final VoiceClip clip;
}

/// The voice message the composer records: click or tap to record (then stop to listen, or
/// send), or hold to record and let go to send; sliding left while holding cancels, sliding
/// up keeps it recording without the button.
final class VoiceDraft extends ChangeNotifier {
  VoiceDraft({
    required VoiceRecorder Function() recorder,
    required this._codec,
    required this._playback,
    required this.send,
    required this.onError,
    this.playKey = 'draft',
    Clock? clock,
  }) : _newRecorder = recorder,
       _fixedClock = clock;

  /// How long a recording may be; it stops there and waits to be sent.
  static const maxLength = Duration(minutes: 10);

  /// Sliding the held button this far left cancels, this far up locks.
  static const cancelDistance = 120.0;
  static const lockDistance = 70.0;

  /// A held recording shorter than this is taken for a tap gone wrong and dropped.
  static const minLength = Duration(milliseconds: 600);

  static const _levelsShown = 48;

  final VoiceRecorder Function() _newRecorder;
  final AudioCodec _codec;
  final VoicePlayback _playback;

  /// Tells the time; tests give a fake one, otherwise the zone's (which fake async fakes).
  final Clock? _fixedClock;

  /// Sends a finished voice message.
  final Future<void> Function(VoiceClip clip) send;

  /// Tells the user why it didn't work.
  final void Function(String message) onError;

  /// Names the preview in [VoicePlayback].
  final String playKey;

  VoiceDraftState _state = const VoiceIdle();
  VoiceRecorder? _recorder;
  StreamSubscription<double>? _levels;

  /// Redraws the elapsed time and levels while recording, whether or not frames come.
  Timer? _tick;

  /// When recording started, by [_now]; the elapsed time is real time, not counted ticks.
  DateTime? _startedAt;
  var _disposed = false;

  DateTime _now() => (_fixedClock ?? clock).now();

  Duration get _elapsed {
    final started = _startedAt;
    return started == null ? Duration.zero : _now().difference(started);
  }

  VoiceDraftState get state => _state;

  /// Whether the composer shows the voice message instead of the text.
  bool get isActive => _state is! VoiceIdle;

  void _set(VoiceDraftState state) {
    if (_disposed) return;
    _state = state;
    notifyListeners();
  }

  /// Starts recording; [locked] for a click or tap, not for a held button.
  Future<void> start({required bool locked}) async {
    if (_state is! VoiceIdle) return;
    await _playback.stop();
    _set(VoiceStarting(locked: locked));
    final recorder = _recorder = _newRecorder();
    try {
      await recorder.start();
    } on MicrophoneUnavailable catch (error) {
      _recorder = null;
      unawaited(recorder.dispose());
      _set(const VoiceIdle());
      onError(error.message);
      return;
    }
    // Let go (or cancelled) while the microphone was opening.
    final starting = _state;
    if (starting is! VoiceStarting || _disposed) {
      await recorder.cancel();
      await recorder.dispose();
      if (identical(_recorder, recorder)) _recorder = null;
      return;
    }
    _startedAt = _now();
    final levels = <double>[];
    _levels = recorder.levels.listen((level) {
      levels.add(level);
      if (levels.length > _levelsShown) levels.removeAt(0);
    });
    _set(
      VoiceRecording(
        elapsed: Duration.zero,
        levels: const [],
        locked: starting.locked,
      ),
    );
    _tick = Timer.periodic(const Duration(milliseconds: 100), (_) {
      final recording = _state;
      if (recording is! VoiceRecording) return;
      if (_elapsed >= maxLength) {
        unawaited(stop());
        return;
      }
      _set(
        VoiceRecording(
          elapsed: _elapsed,
          levels: List.unmodifiable(levels),
          locked: recording.locked,
          slide: recording.slide,
        ),
      );
    });
  }

  /// The held button moved by [offset] from where it was pressed.
  void slide(Offset offset) {
    final recording = _state;
    if (recording is VoiceStarting) {
      if (offset.dx <= -cancelDistance) unawaited(cancel());
      return;
    }
    if (recording is! VoiceRecording || recording.locked) return;
    if (offset.dx <= -cancelDistance) {
      unawaited(cancel());
    } else if (offset.dy <= -lockDistance) {
      _set(
        VoiceRecording(
          elapsed: recording.elapsed,
          levels: recording.levels,
          locked: true,
        ),
      );
    } else {
      _set(
        VoiceRecording(
          elapsed: recording.elapsed,
          levels: recording.levels,
          locked: false,
          slide: offset,
        ),
      );
    }
  }

  /// The held button was let go: a held recording is sent, a very short one dropped.
  Future<void> release() async {
    final state = _state;
    if (state is VoiceStarting && !state.locked) {
      _set(const VoiceIdle());
      return;
    }
    if (state is! VoiceRecording || state.locked) return;
    if (_elapsed < minLength) {
      await cancel();
      onError('Hold to record, let go to send.');
      return;
    }
    final clip = await _finish();
    if (clip != null) await _send(clip);
  }

  /// Ends the recording and shows it to listen to before sending.
  Future<void> stop() async {
    final clip = await _finish();
    if (clip != null) _set(VoicePreview(clip));
  }

  /// Sends the recording, or the one listened to.
  Future<void> sendNow() async {
    final state = _state;
    final clip = switch (state) {
      VoicePreview(:final clip) => clip,
      VoiceRecording() => await _finish(),
      _ => null,
    };
    if (clip != null) await _send(clip);
  }

  /// Drops the recording or the one listened to.
  Future<void> cancel() async {
    _stopClock();
    final recorder = _recorder;
    _recorder = null;
    await _playback.stop(playKey);
    _set(const VoiceIdle());
    if (recorder != null) {
      await recorder.cancel();
      await recorder.dispose();
    }
  }

  Future<VoiceClip?> _finish() async {
    final recorder = _recorder;
    if (recorder == null || _state is! VoiceRecording) return null;
    _recorder = null;
    _stopClock();
    _set(const VoiceEncoding());
    try {
      final audio = await recorder.stop();
      final clip = await _codec.encodeVoice(
        audio.pcm,
        sampleRate: audio.sampleRate,
        channels: audio.channels,
      );
      if (clip.duration == Duration.zero) {
        _set(const VoiceIdle());
        onError('Nothing was recorded.');
        return null;
      }
      return clip;
    } on Object catch (error) {
      _set(const VoiceIdle());
      onError('Can’t record: $error');
      return null;
    } finally {
      unawaited(recorder.dispose());
    }
  }

  Future<void> _send(VoiceClip clip) async {
    await _playback.stop(playKey);
    _set(const VoiceIdle());
    await send(clip);
  }

  void _stopClock() {
    _tick?.cancel();
    _tick = null;
    unawaited(_levels?.cancel());
    _levels = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _stopClock();
    final recorder = _recorder;
    _recorder = null;
    if (recorder != null) {
      unawaited(recorder.cancel().whenComplete(recorder.dispose));
    }
    unawaited(_playback.stop(playKey));
    super.dispose();
  }
}

/// The microphone button: a click or tap records until stopped; holding records until let
/// go, which sends.
class MicButton extends StatelessWidget {
  const MicButton({required this.draft, super.key});

  final VoiceDraft draft;

  @override
  Widget build(BuildContext context) {
    final holding = switch (draft.state) {
      VoiceStarting(locked: false) => true,
      VoiceRecording(locked: false) => true,
      _ => false,
    };
    final theme = Theme.of(context);
    return Tooltip(
      message: 'Record a voice message (or hold to talk)',
      child: GestureDetector(
        key: const Key('composer.mic'),
        onTap: () => unawaited(draft.start(locked: true)),
        onLongPressStart: (_) => unawaited(draft.start(locked: false)),
        onLongPressMoveUpdate: (details) =>
            draft.slide(details.offsetFromOrigin),
        onLongPressEnd: (_) => unawaited(draft.release()),
        onLongPressCancel: () => unawaited(draft.release()),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: holding ? 56 : 48,
          height: holding ? 56 : 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: holding ? theme.colorScheme.error : Colors.transparent,
          ),
          child: Icon(
            Icons.mic_rounded,
            color: holding
                ? theme.colorScheme.onError
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// Instead of the text while recording or listening: the time and loudness, or the
/// recording to play.
class VoiceDraftBar extends ConsumerWidget {
  const VoiceDraftBar({required this.draft, super.key});

  final VoiceDraft draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return switch (draft.state) {
      VoiceIdle() => const SizedBox.shrink(),
      VoiceStarting() || VoiceEncoding() => const SizedBox(
        height: 48,
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      VoiceRecording(
        :final elapsed,
        :final levels,
        :final locked,
        :final slide,
      ) =>
        Row(
          key: const Key('voice.recording'),
          children: [
            if (locked)
              IconButton(
                key: const Key('voice.cancel'),
                tooltip: 'Delete recording',
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: () => unawaited(draft.cancel()),
              )
            else
              const SizedBox(width: 12),
            // Blinks every half second.
            AnimatedOpacity(
              opacity: elapsed.inMilliseconds ~/ 500 % 2 == 0 ? 1 : 0.25,
              duration: const Duration(milliseconds: 200),
              child: Icon(
                Icons.circle,
                size: 12,
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              mediaDuration(elapsed),
              key: const Key('voice.elapsed'),
              style: theme.textTheme.bodyLarge?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: locked
                  ? WaveformBars(
                      key: const Key('voice.levels'),
                      points: [
                        for (final level in levels)
                          (level * VoiceClip.waveformMax).round(),
                      ],
                      progress: 1,
                      color: theme.colorScheme.onSurfaceVariant,
                      activeColor: theme.colorScheme.error,
                      height: 28,
                    )
                  : Opacity(
                      opacity: (1 + slide.dx / VoiceDraft.cancelDistance).clamp(
                        0.2,
                        1.0,
                      ),
                      child: Text(
                        '‹ Slide to cancel, up to lock',
                        key: const Key('voice.slideHint'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      VoicePreview(:final clip) => Row(
        key: const Key('voice.preview'),
        children: [
          IconButton(
            key: const Key('voice.discard'),
            tooltip: 'Delete recording',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () => unawaited(draft.cancel()),
          ),
          Expanded(
            child: AudioPlayerRow(
              playKey: draft.playKey,
              waveform: clip.waveform,
              duration: clip.duration,
              load: () async {
                final codec = ref.read(audioCodecProvider);
                final wav = await codec.playableWav(clip.data);
                if (wav == null) throw const UnplayableAudio();
                return PlayableAudio(
                  wav,
                  name: 'draft.wav',
                  duration: clip.duration,
                );
              },
            ),
          ),
        ],
      ),
    };
  }
}

/// The buttons at the end of the composer while recording without holding, or listening:
/// stop to listen, and send.
class VoiceDraftActions extends StatelessWidget {
  const VoiceDraftActions({required this.draft, super.key});

  final VoiceDraft draft;

  @override
  Widget build(BuildContext context) {
    final state = draft.state;
    final recording = state is VoiceRecording && state.locked;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (recording)
          IconButton(
            key: const Key('voice.stop'),
            tooltip: 'Stop and listen',
            icon: const Icon(Icons.stop_circle_outlined),
            onPressed: () => unawaited(draft.stop()),
          ),
        IconButton(
          key: const Key('voice.send'),
          tooltip: 'Send voice message',
          color: Theme.of(context).colorScheme.primary,
          icon: const Icon(Icons.send_rounded),
          onPressed: recording || state is VoicePreview
              ? () => unawaited(draft.sendNow())
              : null,
        ),
      ],
    );
  }
}
