import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../matrix/api/matrix.dart';
import '../../ui/format.dart';
import '../../ui/rich_text_view.dart';
import 'voice/audio_player_view.dart';

/// Opens a message's file in the system's app for it, downloading it into the cache first.
Future<void> openMedia(
  BuildContext context,
  WidgetRef ref,
  String account,
  MediaInfo media,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final session = ref.read(accountsProvider).value?.byId(account);
  final files = ref.read(fileActionsProvider);
  if (session == null) return;
  try {
    final path = await files.tempPathFor(media.filename);
    await session.saveMedia(media.source, path);
    if (!await files.launch(Uri.file(path))) {
      messenger.showSnackBar(
        SnackBar(content: Text('No app can open ${media.filename}')),
      );
    }
  } on MatrixFailure catch (failure) {
    messenger.showSnackBar(
      SnackBar(content: Text('Can’t open the file: ${failure.kind.name}')),
    );
  }
}

/// Asks where to save a message's file, and saves it there.
Future<void> saveMediaAs(
  BuildContext context,
  WidgetRef ref,
  String account,
  MediaInfo media,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final session = ref.read(accountsProvider).value?.byId(account);
  if (session == null) return;
  final path = await ref.read(fileActionsProvider).askSavePath(media.filename);
  if (path == null) return;
  try {
    await session.saveMedia(media.source, path);
    messenger.showSnackBar(SnackBar(content: Text('Saved to $path')));
  } on MatrixFailure catch (failure) {
    messenger.showSnackBar(
      SnackBar(content: Text('Can’t save the file: ${failure.kind.name}')),
    );
  }
}

/// What a click on a message's file does: images open in the viewer, the rest in the
/// system's app.
void showMedia(
  BuildContext context,
  WidgetRef ref,
  String account,
  MediaInfo media,
) {
  if (media.kind == MediaKind.image) {
    unawaited(
      showDialog<void>(
        context: context,
        builder: (_) => ImageViewer(account: account, media: media),
      ),
    );
  } else {
    unawaited(openMedia(context, ref, account, media));
  }
}

/// A message's file inside its bubble, with the caption under it.
class MediaMessageView extends ConsumerWidget {
  const MediaMessageView({
    required this.account,
    required this.media,
    super.key,
  });

  final String account;
  final MediaInfo media;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caption = media.caption;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        switch (media.kind) {
          MediaKind.image || MediaKind.video => MediaPreview(
            account: account,
            media: media,
            maxSize: 320,
            onTap: () => showMedia(context, ref, account, media),
          ),
          MediaKind.audio => AudioMessageView(account: account, media: media),
          MediaKind.file => FileRow(account: account, media: media),
        },
        if (caption != null && caption.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: switch (media.formattedCaption) {
              final blocks? => RichTextView(
                blocks: blocks,
                onLink: (url) => _openLink(ref, url),
              ),
              null => LinkifiedText(
                text: caption,
                onLink: (url) => _openLink(ref, url),
              ),
            },
          ),
      ],
    );
  }
}

void _openLink(WidgetRef ref, String url) {
  final uri = Uri.tryParse(url);
  if (uri != null) unawaited(ref.read(fileActionsProvider).launch(uri));
}

/// An image or a video's picture, at its shape within [maxSize]; a video gets a ▶ and its
/// length. Loads by itself.
class MediaPreview extends ConsumerWidget {
  const MediaPreview({
    required this.account,
    required this.media,
    required this.maxSize,
    required this.onTap,
    this.square = false,
    super.key,
  });

  final String account;
  final MediaInfo media;
  final double maxSize;
  final VoidCallback onTap;

  /// Cropped to a square, as in a grid.
  final bool square;

  Size get _size {
    if (square) return Size.square(maxSize);
    final width = media.width ?? 4;
    final height = media.height ?? 3;
    final scale = maxSize / (width > height ? width : height);
    // Not narrower than a third of the box, so a tall strip stays tappable.
    return Size(
      (width * scale).clamp(maxSize / 3, maxSize),
      (height * scale).clamp(maxSize / 3, maxSize),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isVideo = media.kind == MediaKind.video;
    // A video without an attached thumbnail has no picture to show.
    final picture = isVideo && media.thumbnail == null
        ? null
        : ref.watch(
            mediaThumbnailProvider(account, media.source, media.thumbnail),
          );
    final size = _size;
    final placeholder = ColoredBox(
      color: Colors.black26,
      child: Center(
        child: switch (picture) {
          AsyncError() => const Icon(Icons.broken_image_outlined),
          AsyncLoading() => const SizedBox.square(
            dimension: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          _ => null,
        },
      ),
    );
    final bytes = picture?.value;
    return Semantics(
      button: true,
      label: media.filename,
      child: GestureDetector(
        key: Key('media.${media.source.hashCode}'),
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(square ? 4 : 10),
          child: SizedBox.fromSize(
            size: size,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (bytes != null)
                  _Picture(bytes: bytes, fallback: placeholder)
                else
                  placeholder,
                if (isVideo) ...[
                  const Center(
                    child: CircleAvatar(
                      backgroundColor: Colors.black54,
                      foregroundColor: Colors.white,
                      child: Icon(Icons.play_arrow_rounded),
                    ),
                  ),
                  if (media.duration case final duration?)
                    Positioned(
                      left: 6,
                      bottom: 6,
                      child: _Chip(text: mediaDuration(duration)),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Picture extends StatelessWidget {
  const _Picture({required this.bytes, required this.fallback});

  final Uint8List bytes;
  final Widget fallback;

  @override
  Widget build(BuildContext context) => Image.memory(
    bytes,
    fit: BoxFit.cover,
    gaplessPlayback: true,
    errorBuilder: (_, _, _) => fallback,
  );
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    ),
  );
}

/// An audio or other file: its icon, name and size; a click opens it, the button saves it.
class FileRow extends ConsumerWidget {
  const FileRow({required this.account, required this.media, super.key});

  final String account;
  final MediaInfo media;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final details = [
      if (media.duration case final duration?) mediaDuration(duration),
      if (media.size case final size?) fileSize(size),
    ].join(' · ');
    return InkWell(
      key: Key('media.${media.source.hashCode}'),
      borderRadius: BorderRadius.circular(8),
      onTap: () => unawaited(openMedia(context, ref, account, media)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: theme.colorScheme.onPrimary,
              child: Icon(
                media.kind == MediaKind.audio
                    ? Icons.play_arrow_rounded
                    : Icons.insert_drive_file_outlined,
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    media.filename,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (details.isNotEmpty)
                    Text(details, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Save as…',
              icon: const Icon(Icons.download_rounded),
              onPressed: () =>
                  unawaited(saveMediaAs(context, ref, account, media)),
            ),
          ],
        ),
      ),
    );
  }
}

/// An image over the whole window, zoomable, with Save as and Open.
class ImageViewer extends ConsumerWidget {
  const ImageViewer({required this.account, required this.media, super.key});

  final String account;
  final MediaInfo media;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final content = ref.watch(mediaContentProvider(account, media.source));
    return Dialog.fullscreen(
      key: const Key('viewer'),
      backgroundColor: Colors.black,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text(media.filename, overflow: TextOverflow.ellipsis),
          leading: const CloseButton(),
          actions: [
            IconButton(
              tooltip: 'Save as…',
              icon: const Icon(Icons.download_rounded),
              onPressed: () =>
                  unawaited(saveMediaAs(context, ref, account, media)),
            ),
            IconButton(
              tooltip: 'Open in default app',
              icon: const Icon(Icons.open_in_new_rounded),
              onPressed: () =>
                  unawaited(openMedia(context, ref, account, media)),
            ),
          ],
        ),
        body: Center(
          child: switch (content) {
            AsyncData(:final value) => InteractiveViewer(
              maxScale: 8,
              child: Image.memory(
                value,
                errorBuilder: (_, _, _) => const _ViewerMessage(
                  'This image can’t be shown here; open it in another app.',
                ),
              ),
            ),
            AsyncError() => const _ViewerMessage('Can’t load the image.'),
            _ => const CircularProgressIndicator(),
          },
        ),
      ),
    );
  }
}

class _ViewerMessage extends StatelessWidget {
  const _ViewerMessage(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: const TextStyle(color: Colors.white70));
}
