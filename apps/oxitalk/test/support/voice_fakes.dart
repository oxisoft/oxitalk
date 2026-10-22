import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:oxitalk/src/features/chat/video/video_message.dart';
import 'package:oxitalk/src/features/chat/voice/audio_io.dart';

/// A microphone that hears what the test says: [levels] to show, then [pcm] on stop.
final class FakeVoiceRecorder implements VoiceRecorder {
  FakeVoiceRecorder({this.denied = false, Int16List? pcm})
    : pcm = pcm ?? Int16List.fromList(List.filled(48000 * 2, 8000));

  /// Whether the user said no to the microphone.
  final bool denied;

  /// Two seconds at 48 kHz unless the test says otherwise.
  final Int16List pcm;

  final _levels = StreamController<double>.broadcast();
  var started = false;
  var stopped = false;
  var cancelled = false;
  var disposed = false;

  void hear(double level) => _levels.add(level);

  @override
  Stream<double> get levels => _levels.stream;

  @override
  Future<void> start() async {
    if (denied) {
      throw const MicrophoneUnavailable('OxiTalk may not use the microphone.');
    }
    started = true;
  }

  @override
  Future<RecordedAudio> stop() async {
    stopped = true;
    return RecordedAudio(pcm, sampleRate: 48000);
  }

  @override
  Future<void> cancel() async => cancelled = true;

  @override
  Future<void> dispose() async {
    disposed = true;
    await _levels.close();
  }
}

/// A speaker the test drives: it says where it plays when told, and ends when told.
final class FakeAudioOutput implements AudioOutput {
  final _positions = StreamController<Duration>.broadcast();
  final _completions = StreamController<void>.broadcast();

  /// What was opened, by name.
  final opened = <String>[];

  /// Every `play <ms>` and `pause`, in order.
  final calls = <String>[];

  /// Throws [UnplayableAudio] on open, as Linux does for an mp3.
  var unplayable = false;

  void playAt(Duration position) => _positions.add(position);

  void finish() => _completions.add(null);

  @override
  Future<void> open(Uint8List audio, {required String name}) async {
    if (unplayable) throw const UnplayableAudio();
    opened.add(name);
  }

  @override
  Future<void> play(Duration from) async =>
      calls.add('play ${from.inMilliseconds}');

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Stream<Duration> get positions => _positions.stream;

  @override
  Stream<void> get completions => _completions.stream;

  @override
  Future<void> dispose() async {}
}

/// A camera that records [video] when stopped.
final class FakeVideoRecorder implements VideoRecorder {
  FakeVideoRecorder({this.unavailable});

  final String? unavailable;
  var recording = false;
  var disposed = false;

  static final video = RecordedVideo(
    data: Uint8List.fromList([0, 0, 0, 24, 102, 116, 121, 112]),
    filename: 'Video.mp4',
    mimeType: 'video/mp4',
    duration: const Duration(seconds: 3),
    photo: Uint8List.fromList([1, 2, 3]),
    width: 720,
    height: 1280,
  );

  @override
  Future<void> open() async {
    if (unavailable case final message?) throw CameraUnavailable(message);
  }

  @override
  Widget preview() => const ColoredBox(
    key: Key('fake.camera'),
    color: Colors.blueGrey,
    child: SizedBox.square(dimension: 200),
  );

  @override
  bool get canSwitch => false;

  @override
  Future<void> switchCamera() async {}

  @override
  Future<void> start() async => recording = true;

  @override
  Future<RecordedVideo> stop() async {
    recording = false;
    return video;
  }

  @override
  Widget? playback(RecordedVideo video) =>
      const SizedBox(key: Key('fake.playback'), width: 200, height: 200);

  @override
  Future<void> dispose() async => disposed = true;
}
