import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers_platform_interface/audioplayers_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../../matrix/api/matrix.dart';
import '../../../matrix/rust/rust_matrix.dart';
import '../../../util/log.dart';

/// The core's codec; tests use a fake.
final audioCodecProvider = Provider<AudioCodec>(
  (ref) => const RustAudioCodec(),
);

/// Makes a recorder for each voice message; tests record from a fake.
final voiceRecorderFactoryProvider = Provider<VoiceRecorder Function()>(
  (ref) => MicVoiceRecorder.new,
);

/// The one speaker every audio message and preview plays through.
final audioOutputProvider = Provider<AudioOutput>((ref) {
  final output = Platform.isLinux ? PacatAudioOutput() : PlatformAudioOutput();
  ref.onDispose(() => unawaited(output.dispose()));
  return output;
});

/// What plays now; one sound at a time in the whole app.
final voicePlaybackProvider = Provider<VoicePlayback>((ref) {
  final playback = VoicePlayback(ref.watch(audioOutputProvider));
  ref.onDispose(playback.dispose);
  return playback;
});

/// Recorded sound: interleaved 16-bit samples.
final class RecordedAudio {
  const RecordedAudio(this.pcm, {required this.sampleRate, this.channels = 1});

  final Int16List pcm;
  final int sampleRate;
  final int channels;
}

/// The user or the system doesn't let the app use the microphone (or there is none).
final class MicrophoneUnavailable implements Exception {
  const MicrophoneUnavailable(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The microphone, for one recording.
abstract interface class VoiceRecorder {
  /// Asks for the microphone if need be and starts; throws [MicrophoneUnavailable].
  Future<void> start();

  /// How loud it is now, from 0 to 1, several times a second while recording.
  Stream<double> get levels;

  /// Ends the recording and gives what was recorded.
  Future<RecordedAudio> stop();

  /// Ends the recording and drops it.
  Future<void> cancel();

  Future<void> dispose();
}

/// The `record` plugin's raw samples (48 kHz, mono), on every platform the same; Linux
/// records through `parecord`.
final class MicVoiceRecorder implements VoiceRecorder {
  MicVoiceRecorder();

  static const sampleRate = 48000;

  final _recorder = AudioRecorder();
  final _levels = StreamController<double>.broadcast();
  final _bytes = BytesBuilder(copy: false);
  StreamSubscription<Uint8List>? _subscription;
  Completer<void>? _done;

  @override
  Stream<double> get levels => _levels.stream;

  @override
  Future<void> start() async {
    final allowed = await _recorder.hasPermission().catchError((Object _) {
      return false;
    });
    if (!allowed) {
      throw const MicrophoneUnavailable(
        'OxiTalk may not use the microphone. Allow it in the system settings.',
      );
    }
    final Stream<Uint8List> stream;
    try {
      stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: sampleRate,
          numChannels: 1,
          autoGain: true,
          echoCancel: true,
          noiseSuppress: true,
        ),
      );
    } on Object catch (error) {
      appLog(LogLevel.warn, 'voice', 'Recording didn’t start: $error');
      throw MicrophoneUnavailable(
        Platform.isLinux
            ? 'Can’t record: is parecord installed (pulseaudio-utils)?'
            : 'Can’t record from the microphone.',
      );
    }
    final done = _done = Completer<void>();
    _subscription = stream.listen(
      (chunk) {
        _bytes.add(chunk);
        _levels.add(levelOf(chunk));
      },
      onDone: done.complete,
      onError: (Object error) {
        appLog(LogLevel.warn, 'voice', 'Recording failed: $error');
        if (!done.isCompleted) done.complete();
      },
    );
  }

  @override
  Future<RecordedAudio> stop() async {
    await _recorder.stop();
    // The last samples arrive before the stream ends.
    await _done?.future.timeout(const Duration(seconds: 2), onTimeout: () {});
    await _subscription?.cancel();
    final bytes = _bytes.takeBytes();
    final even = bytes.length - bytes.length % 2;
    return RecordedAudio(
      Uint8List.fromList(bytes.sublist(0, even)).buffer.asInt16List(),
      sampleRate: sampleRate,
    );
  }

  @override
  Future<void> cancel() async {
    await _subscription?.cancel();
    await _recorder.cancel();
    _bytes.clear();
  }

  @override
  Future<void> dispose() async {
    await _subscription?.cancel();
    await _levels.close();
    await _recorder.dispose();
  }
}

/// How loud 16-bit little-endian samples are, from 0 (-50 dBFS or less) to 1 (full scale).
double levelOf(Uint8List chunk) {
  final samples = chunk.lengthInBytes ~/ 2;
  if (samples == 0) return 0;
  final data = ByteData.sublistView(chunk);
  var sum = 0.0;
  for (var i = 0; i < samples; i++) {
    final sample = data.getInt16(i * 2, Endian.little);
    sum += sample * sample;
  }
  final rms = math.sqrt(sum / samples) / 32768;
  if (rms <= 0) return 0;
  final db = 20 * math.log(rms) / math.ln10;
  return ((db + 50) / 50).clamp(0.0, 1.0);
}

/// The audio a file names: the format of a WAV file's samples and where they are.
final class WavInfo {
  const WavInfo({
    required this.sampleRate,
    required this.channels,
    required this.bitsPerSample,
    required this.dataOffset,
    required this.dataLength,
  });

  /// `null` for anything but 16-bit PCM WAV.
  static WavInfo? of(Uint8List bytes) {
    if (bytes.length < 12) return null;
    final data = ByteData.sublistView(bytes);
    String tag(int at) => String.fromCharCodes(bytes.sublist(at, at + 4));
    if (tag(0) != 'RIFF' || tag(8) != 'WAVE') return null;
    int? rate, channels, bits;
    var at = 12;
    while (at + 8 <= bytes.length) {
      final id = tag(at);
      final size = data.getUint32(at + 4, Endian.little);
      final body = at + 8;
      if (id == 'fmt ' && body + 16 <= bytes.length) {
        if (data.getUint16(body, Endian.little) != 1) return null;
        channels = data.getUint16(body + 2, Endian.little);
        rate = data.getUint32(body + 4, Endian.little);
        bits = data.getUint16(body + 14, Endian.little);
      } else if (id == 'data') {
        if (rate == null || channels == null || bits != 16) return null;
        return WavInfo(
          sampleRate: rate,
          channels: channels,
          bitsPerSample: bits!,
          dataOffset: body,
          dataLength: math.min(size, bytes.length - body),
        );
      }
      at = body + size + size % 2;
    }
    return null;
  }

  final int sampleRate;
  final int channels;
  final int bitsPerSample;
  final int dataOffset;
  final int dataLength;

  int get bytesPerSecond => sampleRate * channels * bitsPerSample ~/ 8;

  Duration get duration =>
      Duration(microseconds: dataLength * 1000000 ~/ bytesPerSecond);
}

/// The audio is in a format this platform can't play.
final class UnplayableAudio implements Exception {
  const UnplayableAudio();
}

/// A speaker: one sound at a time.
abstract interface class AudioOutput {
  /// Gets [audio] ready to play: a WAV file from the core, or a file in another format
  /// called [name], which only the platform may know. Throws [UnplayableAudio].
  Future<void> open(Uint8List audio, {required String name});

  /// Plays what was opened from [from].
  Future<void> play(Duration from);

  Future<void> pause();

  /// Where it plays, several times a second while it does.
  Stream<Duration> get positions;

  /// Once the end is reached.
  Stream<void> get completions;

  Future<void> dispose();
}

/// The platform's player through audioplayers' native parts (Android, iOS, macOS, Windows).
final class PlatformAudioOutput implements AudioOutput {
  PlatformAudioOutput();

  static const _id = 'oxitalk.voice';
  final _platform = AudioplayersPlatformInterface.instance;
  final _positions = StreamController<Duration>.broadcast();
  final _completions = StreamController<void>.broadcast();
  Future<void>? _created;
  StreamSubscription<AudioEvent>? _events;
  Timer? _poll;
  Completer<void>? _prepared;

  Future<void> _create() => _created ??= () async {
    await GlobalAudioplayersPlatformInterface.instance.init();
    await _platform.create(_id);
    _events = _platform
        .getEventStream(_id)
        .listen(
          (event) {
            switch (event.eventType) {
              case AudioEventType.complete:
                _poll?.cancel();
                _completions.add(null);
              case AudioEventType.prepared:
                if (event.isPrepared ?? false) _prepared?.complete();
              case _:
            }
          },
          onError: (Object error) {
            appLog(LogLevel.warn, 'voice', 'Audio playback: $error');
            final prepared = _prepared;
            if (prepared != null && !prepared.isCompleted) {
              prepared.completeError(const UnplayableAudio());
            }
          },
        );
  }();

  @override
  Future<void> open(Uint8List audio, {required String name}) async {
    await _create();
    final dir = Directory(
      '${(await getTemporaryDirectory()).path}/oxitalk-audio',
    );
    await dir.create(recursive: true);
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(audio, flush: true);
    final prepared = _prepared = Completer<void>();
    await _platform.setSourceUrl(_id, file.path, isLocal: true);
    await prepared.future.timeout(const Duration(seconds: 10));
  }

  @override
  Future<void> play(Duration from) async {
    await _platform.seek(_id, from);
    await _platform.resume(_id);
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(milliseconds: 100), (_) async {
      final ms = await _platform.getCurrentPosition(_id);
      if (ms != null) _positions.add(Duration(milliseconds: ms));
    });
  }

  @override
  Future<void> pause() async {
    _poll?.cancel();
    await _platform.pause(_id);
  }

  @override
  Stream<Duration> get positions => _positions.stream;

  @override
  Stream<void> get completions => _completions.stream;

  @override
  Future<void> dispose() async {
    _poll?.cancel();
    await _events?.cancel();
    if (_created != null) await _platform.dispose(_id);
  }
}

/// Linux: WAV through `pacat` (pulseaudio-utils, which recording needs anyway), so the app
/// needs no GStreamer development files to build. Other formats aren't played here.
final class PacatAudioOutput implements AudioOutput {
  PacatAudioOutput({this.binary = 'pacat'});

  final String binary;
  final _positions = StreamController<Duration>.broadcast();
  final _completions = StreamController<void>.broadcast();
  Uint8List? _audio;
  WavInfo? _info;
  Process? _process;
  Timer? _tick;

  @override
  Future<void> open(Uint8List audio, {required String name}) async {
    await pause();
    final info = WavInfo.of(audio);
    if (info == null) throw const UnplayableAudio();
    _audio = audio;
    _info = info;
  }

  @override
  Future<void> play(Duration from) async {
    await pause();
    final audio = _audio;
    final info = _info;
    if (audio == null || info == null) return;
    final frame = info.channels * info.bitsPerSample ~/ 8;
    final skip =
        (from.inMicroseconds * info.bytesPerSecond ~/ 1000000) ~/ frame * frame;
    final start = info.dataOffset + math.min<int>(skip, info.dataLength);
    final end = info.dataOffset + info.dataLength;
    // From a file rather than through stdin: pacat reads it at its own pace.
    final dir = Directory('${Directory.systemTemp.path}/oxitalk-audio-$pid');
    await dir.create(recursive: true);
    final samples = File('${dir.path}/playing.raw');
    await samples.writeAsBytes(Uint8List.sublistView(audio, start, end));
    final Process process;
    try {
      process = await Process.start(binary, [
        '--playback',
        '--raw',
        '--format=s16le',
        '--rate=${info.sampleRate}',
        '--channels=${info.channels}',
        '--client-name=OxiTalk',
        '--stream-name=Voice message',
        samples.path,
      ]);
    } on ProcessException catch (error) {
      appLog(LogLevel.warn, 'voice', 'pacat didn’t start: $error');
      throw const UnplayableAudio();
    }
    _process = process;
    unawaited(process.stdout.drain<void>());
    unawaited(process.stderr.drain<void>());
    final clock = Stopwatch()..start();
    final total = info.duration;
    _tick = Timer.periodic(const Duration(milliseconds: 100), (_) {
      final at = from + clock.elapsed;
      _positions.add(at < total ? at : total);
    });
    unawaited(
      process.exitCode.then((_) {
        // Killed by pause() or a new play() otherwise.
        if (identical(_process, process)) {
          _tick?.cancel();
          _process = null;
          _completions.add(null);
        }
      }),
    );
  }

  @override
  Future<void> pause() async {
    _tick?.cancel();
    final process = _process;
    _process = null;
    process?.kill();
  }

  @override
  Stream<Duration> get positions => _positions.stream;

  @override
  Stream<void> get completions => _completions.stream;

  @override
  Future<void> dispose() => pause();
}

/// What the player shows for one sound.
@immutable
final class PlaybackState {
  const PlaybackState({
    this.playing = false,
    this.loading = false,
    this.position = Duration.zero,
    this.duration,
  });

  static const idle = PlaybackState();

  final bool playing;
  final bool loading;
  final Duration position;
  final Duration? duration;

  /// From 0 to 1, `0` while the length isn't known.
  double get progress {
    final total = duration?.inMicroseconds ?? 0;
    if (total <= 0) return 0;
    return (position.inMicroseconds / total).clamp(0.0, 1.0);
  }
}

/// A sound to play: WAV bytes (or another file, called [name]) and how long it is.
final class PlayableAudio {
  const PlayableAudio(this.bytes, {required this.name, this.duration});

  final Uint8List bytes;
  final String name;
  final Duration? duration;
}

/// Plays one sound at a time, named by a key (a message's file, a draft); starting another
/// stops the one before.
final class VoicePlayback extends ChangeNotifier {
  VoicePlayback(this._output) {
    _subscriptions = [
      _output.positions.listen((position) {
        if (_key == null || !_state.playing) return;
        _set(
          PlaybackState(
            playing: true,
            position: position,
            duration: _state.duration,
          ),
        );
      }),
      _output.completions.listen((_) {
        if (_key == null) return;
        // Back to the start, as Element does.
        _set(PlaybackState(duration: _state.duration));
      }),
    ];
  }

  final AudioOutput _output;
  late final List<StreamSubscription<Object?>> _subscriptions;
  String? _key;
  var _state = PlaybackState.idle;

  /// The key of what is playing, paused or loading.
  String? get current => _key;

  PlaybackState stateOf(String key) =>
      key == _key ? _state : PlaybackState.idle;

  void _set(PlaybackState state) {
    _state = state;
    notifyListeners();
  }

  /// Plays the sound [key] or pauses it; [load] fetches it the first time. Throws
  /// [UnplayableAudio] if this platform can't play it.
  Future<void> toggle(String key, Future<PlayableAudio> Function() load) async {
    if (key == _key) {
      if (_state.loading) return;
      if (_state.playing) {
        await _output.pause();
        _set(
          PlaybackState(position: _state.position, duration: _state.duration),
        );
      } else {
        await _play(_state.position);
      }
      return;
    }
    await _open(key, load);
    await _play(Duration.zero);
  }

  /// Jumps within the sound [key] to [fraction] of it, loading it if need be.
  Future<void> seek(
    String key,
    double fraction,
    Future<PlayableAudio> Function() load,
  ) async {
    if (key != _key) await _open(key, load);
    final duration = _state.duration;
    if (duration == null) return;
    final to = duration * fraction.clamp(0.0, 1.0);
    if (_state.playing) {
      _set(PlaybackState(playing: true, position: to, duration: duration));
      await _play(to);
    } else {
      _set(PlaybackState(position: to, duration: duration));
    }
  }

  /// Stops what plays, if it is [key] (or anything, without one).
  Future<void> stop([String? key]) async {
    if (_key == null || (key != null && key != _key)) return;
    await _output.pause();
    _key = null;
    _set(PlaybackState.idle);
  }

  Future<void> _open(String key, Future<PlayableAudio> Function() load) async {
    if (_key != null) await _output.pause();
    _key = key;
    _set(const PlaybackState(loading: true));
    try {
      final audio = await load();
      if (_key != key) return;
      await _output.open(audio.bytes, name: audio.name);
      final duration = WavInfo.of(audio.bytes)?.duration ?? audio.duration;
      if (_key == key) _set(PlaybackState(duration: duration));
    } on Object {
      if (_key == key) {
        _key = null;
        _set(PlaybackState.idle);
      }
      rethrow;
    }
  }

  Future<void> _play(Duration from) async {
    final duration = _state.duration;
    final start = duration != null && from >= duration ? Duration.zero : from;
    _set(PlaybackState(playing: true, position: start, duration: duration));
    await _output.play(start);
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    super.dispose();
  }
}
