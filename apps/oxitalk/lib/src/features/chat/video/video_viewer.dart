import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../matrix/api/matrix.dart';
import '../../../ui/format.dart';

/// The player a received video plays in, inside the app, given the downloaded file; `null`
/// where there is none and videos open in the system's app. video_player plays on Android,
/// iOS and macOS; on Windows and Linux it has no player without a third-party plugin
/// (GStreamer development files on Linux). Tests put in a fake.
final inlineVideoPlayerProvider = Provider<Widget Function(String path)?>(
  (ref) => !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS)
      ? (path) => VideoFileView(path: path)
      : null,
);

/// A received video over the whole window: downloaded into the cache, then played with
/// play/pause and a bar to move through it; Save as… and Open in default app as the image
/// viewer has them.
class VideoViewer extends ConsumerStatefulWidget {
  const VideoViewer({
    required this.account,
    required this.media,
    required this.player,
    required this.onSave,
    required this.onOpenElsewhere,
    super.key,
  });

  final String account;
  final MediaInfo media;
  final Widget Function(String path) player;
  final VoidCallback onSave;
  final VoidCallback onOpenElsewhere;

  @override
  ConsumerState<VideoViewer> createState() => _VideoViewerState();
}

class _VideoViewerState extends ConsumerState<VideoViewer> {
  late final Future<String> _file = _download();

  Future<String> _download() async {
    final session = ref.read(accountsProvider).value?.byId(widget.account);
    if (session == null) throw StateError('signed out');
    final files = ref.read(fileActionsProvider);
    final path = await files.tempPathFor(widget.media.filename);
    await session.saveMedia(widget.media.source, path);
    return path;
  }

  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
    key: const Key('videoViewer'),
    backgroundColor: Colors.black,
    child: Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.media.filename, overflow: TextOverflow.ellipsis),
        leading: const CloseButton(),
        actions: [
          IconButton(
            tooltip: 'Save as…',
            icon: const Icon(Icons.download_rounded),
            onPressed: widget.onSave,
          ),
          IconButton(
            tooltip: 'Open in default app',
            icon: const Icon(Icons.open_in_new_rounded),
            onPressed: widget.onOpenElsewhere,
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<String>(
          future: _file,
          builder: (context, snapshot) => switch (snapshot) {
            AsyncSnapshot(:final String data) => widget.player(data),
            AsyncSnapshot(hasError: true) => const _Message(
              'Can’t download the video.',
            ),
            _ => const Center(child: CircularProgressIndicator()),
          },
        ),
      ),
    ),
  );
}

/// Plays the video file at [path] at once: a tap on the picture or the button pauses and
/// plays, the bar under it moves through it, with the time and the length beside it.
class VideoFileView extends StatefulWidget {
  const VideoFileView({required this.path, super.key});

  final String path;

  @override
  State<VideoFileView> createState() => _VideoFileViewState();
}

class _VideoFileViewState extends State<VideoFileView> {
  late final _controller = VideoPlayerController.file(File(widget.path));
  var _failed = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_changed);
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      await _controller.initialize();
      await _controller.play();
    } on Object {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _toggle() {
    final value = _controller.value;
    if (value.isPlaying) {
      unawaited(_controller.pause());
      return;
    }
    // At the end: from the start again.
    if (value.duration > Duration.zero && value.position >= value.duration) {
      unawaited(_controller.seekTo(Duration.zero));
    }
    unawaited(_controller.play());
  }

  @override
  void dispose() {
    _controller.removeListener(_changed);
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = _controller.value;
    if (_failed || value.hasError) {
      return const _Message(
        'This video can’t be played here. Open it in the default app.',
      );
    }
    if (!value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: _toggle,
            child: Center(
              child: AspectRatio(
                aspectRatio: value.aspectRatio,
                child: VideoPlayer(_controller),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 16, 12),
          child: Row(
            children: [
              IconButton(
                key: const Key('videoViewer.play'),
                color: Colors.white,
                tooltip: value.isPlaying ? 'Pause' : 'Play',
                icon: Icon(
                  value.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                ),
                onPressed: _toggle,
              ),
              Expanded(
                child: VideoProgressIndicator(
                  _controller,
                  allowScrubbing: true,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  colors: const VideoProgressColors(
                    playedColor: OxiBrand.yellow,
                    bufferedColor: Colors.white24,
                    backgroundColor: Colors.white12,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${mediaDuration(value.position)} / '
                '${mediaDuration(value.duration)}',
                style: const TextStyle(
                  color: Colors.white70,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white70),
      ),
    ),
  );
}
