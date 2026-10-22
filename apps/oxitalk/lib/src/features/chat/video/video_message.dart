import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../../ui/format.dart';

/// Whether this platform can record a video message: the camera plugins record video on
/// Android and iOS (camera) and Windows (camera_windows); on macOS and Linux only a
/// third-party plugin could, and its Linux part needs GStreamer development files to build.
final videoMessagesSupportedProvider = Provider<bool>(
  (ref) =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isWindows),
);

/// Makes the camera for each video; tests use a fake.
final videoRecorderFactoryProvider = Provider<VideoRecorder Function()>(
  (ref) => CameraVideoRecorder.new,
);

/// A recorded video, ready to send.
final class RecordedVideo {
  const RecordedVideo({
    required this.data,
    required this.filename,
    required this.mimeType,
    required this.duration,
    this.path,
    this.photo,
    this.width,
    this.height,
  });

  final Uint8List data;
  final String filename;
  final String mimeType;
  final Duration duration;

  /// Where the file is, to play it before sending.
  final String? path;

  /// A picture the camera took as it started, for the thumbnail.
  final Uint8List? photo;
  final int? width;
  final int? height;
}

/// The camera, for one video.
abstract interface class VideoRecorder {
  /// Opens the camera, the front one first; throws a [CameraUnavailable].
  Future<void> open();

  /// What the camera sees.
  Widget preview();

  /// Whether there is another camera to switch to.
  bool get canSwitch;

  Future<void> switchCamera();

  Future<void> start();

  Future<RecordedVideo> stop();

  /// A player for [video] before it is sent, if this platform has one.
  Widget? playback(RecordedVideo video);

  Future<void> dispose();
}

final class CameraUnavailable implements Exception {
  const CameraUnavailable(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The camera plugin's video, with a photo taken just before for the thumbnail.
final class CameraVideoRecorder implements VideoRecorder {
  CameraVideoRecorder();

  List<CameraDescription> _cameras = const [];
  CameraController? _controller;
  var _index = 0;
  Uint8List? _photo;
  final _clock = clock.stopwatch();

  @override
  Future<void> open() async {
    try {
      _cameras = await availableCameras();
    } on CameraException catch (error) {
      throw CameraUnavailable(_messageOf(error));
    }
    if (_cameras.isEmpty) throw const CameraUnavailable('No camera found.');
    final front = _cameras.indexWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
    );
    _index = front < 0 ? 0 : front;
    await _openCamera();
  }

  Future<void> _openCamera() async {
    await _controller?.dispose();
    final controller = _controller = CameraController(
      _cameras[_index],
      ResolutionPreset.high,
      videoBitrate: 2500000,
      audioBitrate: 96000,
    );
    try {
      await controller.initialize();
    } on CameraException catch (error) {
      throw CameraUnavailable(_messageOf(error));
    }
  }

  static String _messageOf(CameraException error) => switch (error.code) {
    'CameraAccessDenied' ||
    'CameraAccessDeniedWithoutPrompt' ||
    'CameraAccessRestricted' ||
    'AudioAccessDenied' ||
    'AudioAccessDeniedWithoutPrompt' ||
    'AudioAccessRestricted' =>
      'OxiTalk may not use the camera or microphone. '
          'Allow them in the system settings.',
    _ => 'Can’t open the camera: ${error.description ?? error.code}',
  };

  @override
  Widget preview() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox.shrink();
    }
    return CameraPreview(controller);
  }

  @override
  bool get canSwitch => _cameras.length > 1;

  @override
  Future<void> switchCamera() async {
    if (!canSwitch) return;
    _index = (_index + 1) % _cameras.length;
    await _openCamera();
  }

  @override
  Future<void> start() async {
    final controller = _controller;
    if (controller == null) return;
    try {
      _photo = await (await controller.takePicture()).readAsBytes();
    } on CameraException {
      // The video goes without a thumbnail.
      _photo = null;
    }
    await controller.startVideoRecording();
    _clock
      ..reset()
      ..start();
  }

  @override
  Future<RecordedVideo> stop() async {
    final controller = _controller;
    if (controller == null) throw const CameraUnavailable('The camera closed.');
    final file = await controller.stopVideoRecording();
    _clock.stop();
    final size = controller.value.previewSize;
    // The preview size is the sensor's, landscape; a phone held upright records portrait.
    final upright =
        (Platform.isAndroid || Platform.isIOS) &&
        controller.value.deviceOrientation.name.startsWith('portrait');
    final name = file.name.isEmpty ? 'video.mp4' : file.name;
    final mov = name.toLowerCase().endsWith('.mov');
    return RecordedVideo(
      data: await file.readAsBytes(),
      filename: mov ? 'Video.mov' : 'Video.mp4',
      mimeType: mov ? 'video/quicktime' : 'video/mp4',
      duration: _clock.elapsed,
      path: file.path,
      photo: _photo,
      width: size == null ? null : (upright ? size.height : size.width).round(),
      height: size == null
          ? null
          : (upright ? size.width : size.height).round(),
    );
  }

  @override
  Widget? playback(RecordedVideo video) =>
      (Platform.isAndroid || Platform.isIOS) && video.path != null
      ? _VideoFilePlayer(path: video.path!)
      : null;

  @override
  Future<void> dispose() async {
    final controller = _controller;
    _controller = null;
    await controller?.dispose();
  }
}

class _VideoFilePlayer extends StatefulWidget {
  const _VideoFilePlayer({required this.path});

  final String path;

  @override
  State<_VideoFilePlayer> createState() => _VideoFilePlayerState();
}

class _VideoFilePlayerState extends State<_VideoFilePlayer> {
  late final _controller = VideoPlayerController.file(File(widget.path));

  @override
  void initState() {
    super.initState();
    unawaited(
      _controller.initialize().then((_) async {
        await _controller.setLooping(true);
        await _controller.play();
        if (mounted) setState(() {});
      }),
    );
  }

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _controller.value.isInitialized
      ? AspectRatio(
          aspectRatio: _controller.value.aspectRatio,
          child: VideoPlayer(_controller),
        )
      : const Center(child: CircularProgressIndicator());
}

/// Records a video message over the whole window: the camera, a button to start and stop
/// (at most [maxLength]), then the video to watch with Retake and Send. Returns it on Send.
Future<RecordedVideo?> recordVideoMessage(BuildContext context) =>
    showDialog<RecordedVideo>(
      context: context,
      builder: (_) => const VideoRecordScreen(),
    );

/// How long a video message may be.
const maxVideoLength = Duration(minutes: 1);

class VideoRecordScreen extends ConsumerStatefulWidget {
  const VideoRecordScreen({super.key});

  @override
  ConsumerState<VideoRecordScreen> createState() => _VideoRecordScreenState();
}

class _VideoRecordScreenState extends ConsumerState<VideoRecordScreen> {
  late final VideoRecorder _camera = ref.read(videoRecorderFactoryProvider)();
  var _opened = false;
  String? _error;
  var _recording = false;
  var _busy = false;
  RecordedVideo? _video;
  Timer? _tick;
  final _clock = clock.stopwatch();

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  Future<void> _open() async {
    try {
      await _camera.open();
      if (mounted) setState(() => _opened = true);
    } on CameraUnavailable catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  Future<void> _start() async {
    setState(() => _busy = true);
    try {
      await _camera.start();
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Can’t record: $error';
        });
      }
      return;
    }
    _clock
      ..reset()
      ..start();
    _tick = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (_clock.elapsed >= maxVideoLength) unawaited(_stop());
      if (mounted) setState(() {});
    });
    if (mounted) {
      setState(() {
        _busy = false;
        _recording = true;
      });
    }
  }

  Future<void> _stop() async {
    if (!_recording) return;
    _tick?.cancel();
    _clock.stop();
    setState(() {
      _recording = false;
      _busy = true;
    });
    try {
      final video = await _camera.stop();
      if (mounted) setState(() => _video = video);
    } on Object catch (error) {
      if (mounted) setState(() => _error = 'Can’t record: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _retake() async {
    setState(() => _video = null);
  }

  @override
  void dispose() {
    _tick?.cancel();
    unawaited(_camera.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final video = _video;
    final error = _error;
    const white = TextStyle(color: Colors.white);
    final Widget body;
    if (error != null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(error, style: white, textAlign: TextAlign.center),
        ),
      );
    } else if (video != null) {
      body = Center(
        child:
            _camera.playback(video) ??
            (video.photo == null
                ? const Icon(Icons.videocam, color: Colors.white54, size: 96)
                : Image.memory(video.photo!, fit: BoxFit.contain)),
      );
    } else if (!_opened) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      body = Center(child: _camera.preview());
    }
    return Dialog.fullscreen(
      key: const Key('video.recorder'),
      backgroundColor: Colors.black,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          leading: const CloseButton(),
          title: Text(
            video != null
                ? 'Video message · ${mediaDuration(video.duration)}'
                : _recording
                ? mediaDuration(_clock.elapsed)
                : 'Video message',
            key: const Key('video.title'),
          ),
          actions: [
            if (video == null && !_recording && _opened && _camera.canSwitch)
              IconButton(
                tooltip: 'Switch camera',
                icon: const Icon(Icons.cameraswitch_rounded),
                onPressed: _busy
                    ? null
                    : () => unawaited(
                        _camera.switchCamera().then((_) {
                          if (mounted) setState(() {});
                        }),
                      ),
              ),
          ],
        ),
        body: body,
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: video != null
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      TextButton.icon(
                        key: const Key('video.retake'),
                        onPressed: () => unawaited(_retake()),
                        icon: const Icon(Icons.replay_rounded),
                        label: const Text('Retake'),
                      ),
                      FilledButton.icon(
                        key: const Key('video.send'),
                        onPressed: () => Navigator.of(context).pop(video),
                        icon: const Icon(Icons.send_rounded),
                        label: const Text('Send'),
                      ),
                    ],
                  )
                : Center(
                    child: IconButton(
                      key: const Key('video.record'),
                      iconSize: 64,
                      tooltip: _recording ? 'Stop' : 'Record',
                      color: Colors.red,
                      onPressed: !_opened || _busy || error != null
                          ? null
                          : () => unawaited(_recording ? _stop() : _start()),
                      icon: Icon(
                        _recording
                            ? Icons.stop_circle_rounded
                            : Icons.fiber_manual_record_rounded,
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
