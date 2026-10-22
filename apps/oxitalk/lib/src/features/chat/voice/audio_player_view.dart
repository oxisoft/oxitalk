import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../matrix/api/matrix.dart';
import '../../../ui/format.dart';
import '../media_views.dart';
import 'audio_io.dart';

/// A waveform as bars, the part played in [activeColor]; a tap or drag seeks. Without
/// [points] (an audio message sent without one) the bars are flat.
class WaveformBars extends StatelessWidget {
  const WaveformBars({
    required this.points,
    required this.progress,
    required this.color,
    required this.activeColor,
    this.onSeek,
    this.height = 32,
    super.key,
  });

  /// From 0 to [VoiceClip.waveformMax].
  final List<int>? points;

  /// From 0 to 1.
  final double progress;
  final Color color;
  final Color activeColor;
  final ValueChanged<double>? onSeek;
  final double height;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      void seek(Offset at) =>
          onSeek?.call((at.dx / constraints.maxWidth).clamp(0.0, 1.0));
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: onSeek == null ? null : (d) => seek(d.localPosition),
        onHorizontalDragUpdate: onSeek == null
            ? null
            : (d) => seek(d.localPosition),
        child: CustomPaint(
          size: Size(constraints.maxWidth, height),
          painter: _WaveformPainter(
            levels: levelsOf(points),
            progress: progress,
            color: color,
            activeColor: activeColor,
          ),
        ),
      );
    },
  );

  /// The points from 0 to 1; none for a flat line.
  static List<double> levelsOf(List<int>? points) => [
    for (final point in points ?? const <int>[])
      (point / VoiceClip.waveformMax).clamp(0.0, 1.0),
  ];
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.levels,
    required this.progress,
    required this.color,
    required this.activeColor,
  });

  final List<double> levels;
  final double progress;
  final Color color;
  final Color activeColor;

  static const _bar = 3.0;
  static const _gap = 2.0;

  @override
  void paint(Canvas canvas, Size size) {
    final count = math.max(1, ((size.width + _gap) / (_bar + _gap)).floor());
    final paint = Paint()..strokeCap = StrokeCap.round;
    for (var i = 0; i < count; i++) {
      final level = levels.isEmpty
          ? 0.0
          : levels[(i * levels.length / count).floor()];
      final height = math.max(_bar, level * size.height);
      final x = i * (_bar + _gap);
      paint.color = (i + 0.5) / count <= progress ? activeColor : color;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, (size.height - height) / 2, _bar, height),
          const Radius.circular(_bar / 2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.progress != progress ||
      old.levels != levels ||
      old.color != color ||
      old.activeColor != activeColor;
}

/// Play/pause, the waveform and the time of one sound; [load] fetches it the first time.
class AudioPlayerRow extends ConsumerWidget {
  const AudioPlayerRow({
    required this.playKey,
    required this.load,
    required this.waveform,
    this.duration,
    this.title,
    this.trailing,
    this.onUnplayable,
    super.key,
  });

  /// Names the sound in [VoicePlayback].
  final String playKey;
  final Future<PlayableAudio> Function() load;
  final List<int>? waveform;

  /// As the message says, until the file is loaded.
  final Duration? duration;
  final String? title;
  final Widget? trailing;

  /// When this platform can't play the file.
  final VoidCallback? onUnplayable;

  Future<void> _guard(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
    } on UnplayableAudio {
      onUnplayable?.call();
    } on Object {
      messenger.showSnackBar(
        const SnackBar(content: Text('Can’t play this audio.')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = ref.watch(voicePlaybackProvider);
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: playback,
      builder: (context, _) {
        final state = playback.stateOf(playKey);
        final total = state.duration ?? duration;
        final active = playback.current == playKey;
        final time = active && (state.playing || state.position > Duration.zero)
            ? '${mediaDuration(state.position)} / ${mediaDuration(total ?? Duration.zero)}'
            : mediaDuration(total ?? Duration.zero);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: 40,
              child: IconButton.filled(
                key: Key('audio.play.$playKey'),
                tooltip: state.playing ? 'Pause' : 'Play',
                padding: EdgeInsets.zero,
                onPressed: () => unawaited(
                  _guard(context, () => playback.toggle(playKey, load)),
                ),
                icon: state.loading
                    ? SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.colorScheme.onPrimary,
                        ),
                      )
                    : Icon(
                        state.playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: SizedBox(
                width: 220,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (title case final title?)
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    WaveformBars(
                      key: Key('audio.waveform.$playKey'),
                      points: waveform,
                      progress: active ? state.progress : 0,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                      activeColor: theme.colorScheme.primary,
                      onSeek: (fraction) => unawaited(
                        _guard(
                          context,
                          () => playback.seek(playKey, fraction, load),
                        ),
                      ),
                    ),
                    Text(
                      time,
                      key: Key('audio.time.$playKey'),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            ?trailing,
          ],
        );
      },
    );
  }
}

/// An audio message in its bubble, played right there: a voice message with its waveform,
/// another sound file with its name too.
class AudioMessageView extends ConsumerWidget {
  const AudioMessageView({
    required this.account,
    required this.media,
    super.key,
  });

  final String account;
  final MediaInfo media;

  @override
  Widget build(BuildContext context, WidgetRef ref) => AudioPlayerRow(
    key: Key('media.${media.source.hashCode}'),
    playKey: media.source,
    waveform: media.waveform,
    duration: media.duration,
    title: media.isVoice ? null : media.filename,
    load: () => loadMessageAudio(ref, account, media),
    onUnplayable: () => unawaited(openMedia(context, ref, account, media)),
    trailing: IconButton(
      tooltip: 'Save as…',
      icon: const Icon(Icons.download_rounded),
      onPressed: () => unawaited(saveMediaAs(context, ref, account, media)),
    ),
  );
}

/// An audio message's file, made playable: a voice message is decoded to WAV by the core.
Future<PlayableAudio> loadMessageAudio(
  WidgetRef ref,
  String account,
  MediaInfo media,
) async {
  final session = ref.read(accountsProvider).value?.byId(account);
  if (session == null) throw StateError('no session');
  final codec = ref.read(audioCodecProvider);
  final data = await session.mediaContent(media.source);
  final name = 'audio-${media.source.hashCode.toUnsigned(32)}';
  final wav = await codec.playableWav(data);
  if (wav != null) {
    return PlayableAudio(wav, name: '$name.wav', duration: media.duration);
  }
  final dot = media.filename.lastIndexOf('.');
  final extension = dot < 0 ? '' : media.filename.substring(dot);
  return PlayableAudio(data, name: '$name$extension', duration: media.duration);
}
