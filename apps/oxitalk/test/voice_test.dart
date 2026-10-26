import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oxitalk/src/app/file_actions.dart';
import 'package:oxitalk/src/features/chat/voice/audio_io.dart';
import 'package:oxitalk/src/features/chat/voice/voice_composer.dart';
import 'package:oxitalk/src/matrix/api/matrix.dart';
import 'package:oxitalk/src/matrix/fakes/fakes.dart';

import 'support/app.dart';
import 'support/voice_fakes.dart';

const _wide = Size(1400, 900);
const _me = '@me:acme.com';
const _bob = '@bob:acme.com';
const _room = '!team:acme.com';

const _voice = MediaInfo(
  kind: MediaKind.audio,
  source: 'voice',
  filename: 'Voice message.ogg',
  duration: Duration(seconds: 4),
  isVoice: true,
  waveform: [0, 200, 1024, 600, 100],
);
const _song = MediaInfo(
  kind: MediaKind.audio,
  source: 'song',
  filename: 'song.mp3',
  duration: Duration(minutes: 3),
);

final _hello = MessageEntry(
  id: 'hello',
  sender: _bob,
  senderName: 'Bob',
  time: DateTime(2026, 10, 22, 12),
  body: 'Hello there',
  meta: const EventMeta(eventId: r'$hello'),
);

MediaEntry _media(String id, MediaInfo media) => MediaEntry(
  id: id,
  sender: _bob,
  senderName: 'Bob',
  time: DateTime(2026, 10, 22, 12, 1),
  media: media,
);

typedef _Chat = ({
  FakeTimeline timeline,
  FakeAudioOutput audio,
  FakeFileActions files,
  List<FakeVoiceRecorder> recorders,
});

Future<_Chat> _open(
  WidgetTester tester, {
  List<TimelineEntry>? entries,
  bool denied = false,
  bool video = false,
  Size size = _wide,
}) async {
  final timeline = FakeTimeline(ownUserId: _me, entries: entries ?? [_hello]);
  final session = FakeSession(
    userId: _me,
    rooms: const [Room(id: _room, name: 'Team')],
  );
  session.timelines[_room] = timeline;
  session.pictures.addAll({
    // A WAV-ish file the fake codec passes on, and an mp3 it can't.
    'voice': Uint8List.fromList('RIFF....WAVE'.codeUnits),
    'voice2': Uint8List.fromList('RIFF....WAVE'.codeUnits),
    'song': Uint8List.fromList('ID3 an mp3'.codeUnits),
  });
  final audio = FakeAudioOutput();
  final files = FakeFileActions();
  final recorders = <FakeVoiceRecorder>[];
  await pumpApp(
    tester,
    FakeMatrixClientFactory(saved: [session]),
    size: size,
    files: files,
    audio: audio,
    video: video,
    recorder: () {
      final recorder = FakeVoiceRecorder(denied: denied);
      recorders.add(recorder);
      return recorder;
    },
  );
  await tester.tap(find.text('Team'));
  await tester.pumpAndSettle();
  return (timeline: timeline, audio: audio, files: files, recorders: recorders);
}

Finder _key(String key) => find.byKey(Key(key));

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(_key(key)).data!;

void main() {
  group('composer', () {
    testWidgets('shows the microphone while empty, Send once there is text', (
      tester,
    ) async {
      await _open(tester);
      expect(_key('composer.mic'), findsOneWidget);
      expect(_key('composer.send'), findsNothing);
      // No video where the platform can't record it.
      expect(_key('composer.video'), findsNothing);

      await tester.enterText(_key('composer.text'), 'Hi');
      await tester.pump();
      expect(_key('composer.mic'), findsNothing);
      expect(_key('composer.send'), findsOneWidget);
    });

    testWidgets('a click records with the time and loudness, Stop shows it to '
        'play, Send sends it', (tester) async {
      final chat = await _open(tester);
      await tester.tap(_key('composer.mic'));
      await tester.pump();
      expect(_key('voice.recording'), findsOneWidget);
      expect(_key('composer.text'), findsNothing);
      expect(_text(tester, 'voice.elapsed'), '0:00');
      chat.recorders.single.hear(0.9);
      await tester.pump(const Duration(milliseconds: 1200));
      expect(_text(tester, 'voice.elapsed'), '0:01');
      expect(_key('voice.levels'), findsOneWidget);

      await tester.tap(_key('voice.stop'));
      await tester.pump();
      await tester.pump();
      expect(chat.recorders.single.stopped, isTrue);
      expect(_key('voice.preview'), findsOneWidget);
      const draft = 'draft:$_room:null';
      // The fake recorder heard two seconds.
      expect(_text(tester, 'audio.time.$draft'), '0:02');

      await tester.tap(_key('audio.play.$draft'));
      await tester.pump();
      expect(chat.audio.opened, ['draft.wav']);
      expect(chat.audio.calls, ['play 0']);
      chat.audio.playAt(const Duration(seconds: 1));
      await tester.pump();
      expect(_text(tester, 'audio.time.$draft'), '0:01 / 0:02');

      await tester.tap(_key('voice.send'));
      await tester.pumpAndSettle();
      final (clip, replyTo) = chat.timeline.voices.single;
      expect(clip.duration, const Duration(seconds: 2));
      expect(clip.waveform, hasLength(100));
      expect(replyTo, isNull);
      expect(_key('voice.preview'), findsNothing);
      expect(_key('composer.mic'), findsOneWidget);
      expect(chat.audio.calls.last, 'pause');
    });

    testWidgets('the bin drops a recording, also while listening', (
      tester,
    ) async {
      final chat = await _open(tester);
      await tester.tap(_key('composer.mic'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(_key('voice.cancel'));
      await tester.pumpAndSettle();
      expect(chat.recorders.single.cancelled, isTrue);
      expect(_key('composer.text'), findsOneWidget);

      await tester.tap(_key('composer.mic'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(_key('voice.stop'));
      await tester.pumpAndSettle();
      await tester.tap(_key('voice.discard'));
      await tester.pumpAndSettle();
      expect(chat.timeline.voices, isEmpty);
      expect(_key('composer.mic'), findsOneWidget);
    });

    testWidgets('holding records and letting go sends, as a reply when '
        'replying', (tester) async {
      final chat = await _open(tester);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.text('Hello there')));
      await tester.pumpAndSettle();
      await tester.tap(_key('hover.reply').hitTestable().first);
      await tester.pumpAndSettle();
      expect(_key('composer.mode'), findsOneWidget);

      final hold = await tester.startGesture(
        tester.getCenter(_key('composer.mic')),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await tester.pump();
      expect(_key('voice.slideHint'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await hold.up();
      await tester.pumpAndSettle();
      expect(chat.timeline.voices.single.$2, r'$hello');
      expect(_key('composer.mode'), findsNothing);
    }, variant: desktop);

    testWidgets('sliding left cancels; sliding up keeps recording', (
      tester,
    ) async {
      final chat = await _open(tester);
      var hold = await tester.startGesture(
        tester.getCenter(_key('composer.mic')),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 700));
      await hold.moveBy(const Offset(-60, 0));
      await tester.pump();
      await hold.moveBy(const Offset(-80, 0));
      await tester.pump();
      await hold.up();
      await tester.pumpAndSettle();
      expect(chat.recorders.first.cancelled, isTrue);
      expect(chat.timeline.voices, isEmpty);
      expect(_key('composer.text'), findsOneWidget);

      hold = await tester.startGesture(tester.getCenter(_key('composer.mic')));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 700));
      await hold.moveBy(const Offset(0, -40));
      await tester.pump();
      await hold.moveBy(const Offset(0, -50));
      await tester.pump();
      await hold.up();
      await tester.pump(const Duration(milliseconds: 200));
      // Still recording, now with Stop and Send.
      expect(chat.recorders.last.cancelled, isFalse);
      expect(_key('voice.stop'), findsOneWidget);
      await tester.tap(_key('voice.send'));
      await tester.pumpAndSettle();
      expect(chat.timeline.voices, hasLength(1));
    });

    testWidgets('a quick hold is dropped with a hint', (tester) async {
      final chat = await _open(tester);
      final hold = await tester.startGesture(
        tester.getCenter(_key('composer.mic')),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 100));
      await hold.up();
      await tester.pumpAndSettle();
      expect(chat.timeline.voices, isEmpty);
      expect(find.text('Hold to record, let go to send.'), findsOneWidget);
    });

    testWidgets('a refused microphone says so', (tester) async {
      final chat = await _open(tester, denied: true);
      await tester.tap(_key('composer.mic'));
      await tester.pumpAndSettle();
      expect(find.text('OxiTalk may not use the microphone.'), findsOneWidget);
      expect(_key('voice.recording'), findsNothing);
      expect(chat.recorders.single.started, isFalse);
    });

    testWidgets('records a video where the platform can, and sends it', (
      tester,
    ) async {
      final chat = await _open(tester, video: true);
      await tester.tap(_key('composer.video'));
      await tester.pumpAndSettle();
      expect(_key('fake.camera'), findsOneWidget);
      await tester.tap(_key('video.record'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(_key('video.record'));
      await tester.pumpAndSettle();
      expect(_key('fake.playback'), findsOneWidget);
      expect(find.text('Video message · 0:03'), findsOneWidget);
      await tester.tap(_key('video.send'));
      await tester.pumpAndSettle();
      final (duration, photo, replyTo) = chat.timeline.videos['Video.mp4']!;
      expect(duration, const Duration(seconds: 3));
      expect(photo, isNotNull);
      expect(replyTo, isNull);
      expect(_key('video.recorder'), findsNothing);
    });
  });

  group('audio messages', () {
    testWidgets('play inline with their waveform and time, one at a time', (
      tester,
    ) async {
      const other = MediaInfo(
        kind: MediaKind.audio,
        source: 'voice2',
        filename: 'Voice message.ogg',
        duration: Duration(seconds: 9),
        isVoice: true,
      );
      final chat = await _open(
        tester,
        entries: [_media('voice', _voice), _media('voice2', other)],
      );
      expect(_key('audio.waveform.voice'), findsOneWidget);
      // No waveform sent: the bars are flat.
      expect(_key('audio.waveform.voice2'), findsOneWidget);
      expect(_text(tester, 'audio.time.voice'), '0:04');

      await tester.tap(_key('audio.play.voice'));
      await tester.pump();
      expect(chat.audio.opened.single, endsWith('.wav'));
      expect(chat.audio.calls, ['play 0']);
      expect(find.byTooltip('Pause'), findsOneWidget);
      chat.audio.playAt(const Duration(seconds: 2));
      await tester.pump();
      expect(_text(tester, 'audio.time.voice'), '0:02 / 0:04');

      // The other stops this one.
      await tester.tap(_key('audio.play.voice2'));
      await tester.pumpAndSettle();
      expect(chat.audio.calls, ['play 0', 'pause', 'play 0']);
      expect(_text(tester, 'audio.time.voice'), '0:04');
      expect(find.byTooltip('Pause'), findsOneWidget);

      // Paused, then on from there.
      chat.audio.playAt(const Duration(seconds: 3));
      await tester.pump();
      await tester.tap(_key('audio.play.voice2'));
      await tester.pump();
      expect(find.byTooltip('Pause'), findsNothing);
      await tester.tap(_key('audio.play.voice2'));
      await tester.pump();
      expect(chat.audio.calls.last, 'play 3000');

      // At the end it goes back to the start.
      chat.audio.finish();
      await tester.pump();
      expect(find.byTooltip('Pause'), findsNothing);
      expect(_text(tester, 'audio.time.voice2'), '0:09');
    });

    testWidgets('a tap on the waveform jumps there', (tester) async {
      final chat = await _open(tester, entries: [_media('voice', _voice)]);
      await tester.tap(_key('audio.play.voice'));
      await tester.pump();
      final bars = tester.getRect(_key('audio.waveform.voice'));
      await tester.tapAt(bars.centerLeft + Offset(bars.width * 0.75, 0));
      await tester.pump();
      expect(chat.audio.calls.last, 'play 3000');
    });

    testWidgets('a file this platform can’t play opens in another app', (
      tester,
    ) async {
      final chat = await _open(tester, entries: [_media('song', _song)]);
      expect(find.text('song.mp3'), findsOneWidget);
      chat.audio.unplayable = true;
      await tester.tap(_key('audio.play.song'));
      await tester.pumpAndSettle();
      expect(chat.files.launched.single.path, endsWith('song.mp3'));
    });
  });

  testWidgets(
    'the recording time is real time, even when the redraws come late',
    (tester) async {
      var now = DateTime(2026, 10, 22, 12);
      final draft = VoiceDraft(
        recorder: FakeVoiceRecorder.new,
        codec: const FakeAudioCodec(),
        playback: VoicePlayback(FakeAudioOutput()),
        send: (_) async {},
        onError: (_) {},
        clock: Clock(() => now),
      );
      addTearDown(draft.dispose);
      await draft.start(locked: true);
      expect((draft.state as VoiceRecording).elapsed, Duration.zero);
      // A stalled event loop: seven seconds pass, one redraw arrives.
      now = now.add(const Duration(seconds: 7));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        (draft.state as VoiceRecording).elapsed,
        const Duration(seconds: 7),
      );
      // Redraws without time passing don't add time.
      await tester.pump(const Duration(seconds: 1));
      expect(
        (draft.state as VoiceRecording).elapsed,
        const Duration(seconds: 7),
      );
      await draft.cancel();
      expect(draft.state, isA<VoiceIdle>());
    },
  );

  test('a WAV file tells its format and length', () {
    final header = ByteData(44)
      ..setUint32(4, 36 + 96000, Endian.little)
      ..setUint32(16, 16, Endian.little)
      ..setUint16(20, 1, Endian.little)
      ..setUint16(22, 1, Endian.little)
      ..setUint32(24, 48000, Endian.little)
      ..setUint32(28, 96000, Endian.little)
      ..setUint16(32, 2, Endian.little)
      ..setUint16(34, 16, Endian.little)
      ..setUint32(40, 96000, Endian.little);
    final bytes = Uint8List(44 + 96000)..setAll(0, header.buffer.asUint8List());
    bytes.setAll(0, 'RIFF'.codeUnits);
    bytes.setAll(8, 'WAVEfmt '.codeUnits);
    bytes.setAll(36, 'data'.codeUnits);
    final info = WavInfo.of(bytes)!;
    expect(info.sampleRate, 48000);
    expect(info.channels, 1);
    expect(info.dataOffset, 44);
    expect(info.duration, const Duration(seconds: 1));
    expect(WavInfo.of(Uint8List.fromList('ID3 an mp3'.codeUnits)), isNull);
    expect(levelOf(Uint8List(960)), 0);
    final loud = ByteData(4)
      ..setInt16(0, 32767, Endian.little)
      ..setInt16(2, -32767, Endian.little);
    expect(levelOf(loud.buffer.asUint8List()), closeTo(1, 0.01));
  });
}
