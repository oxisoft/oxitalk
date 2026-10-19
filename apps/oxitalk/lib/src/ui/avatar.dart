import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../app/theme.dart';

/// A Matrix picture ([url], `mxc://`) of [account]'s server in a circle; [InitialsAvatar]
/// while it loads, when it can't, or when there is none.
class MatrixAvatar extends ConsumerWidget {
  const MatrixAvatar({
    required this.account,
    required this.url,
    required this.name,
    required this.seed,
    this.radius = 24,
    super.key,
  });

  final String account;
  final String? url;
  final String name;
  final String seed;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fallback = InitialsAvatar(name: name, seed: seed, radius: radius);
    final url = this.url;
    if (url == null) return fallback;
    // Sizes the server keeps ready-made thumbnails of.
    final size = radius <= 24 ? 96 : 320;
    final bytes = ref.watch(pictureProvider(account, url, size)).value;
    if (bytes == null) return fallback;
    return PictureAvatar(bytes: bytes, radius: radius, fallback: fallback);
  }
}

/// An encoded image in a circle; [fallback] if it can't be decoded.
class PictureAvatar extends StatelessWidget {
  const PictureAvatar({
    required this.bytes,
    required this.radius,
    required this.fallback,
    super.key,
  });

  final Uint8List bytes;
  final double radius;
  final Widget fallback;

  @override
  Widget build(BuildContext context) => ClipOval(
    child: Image.memory(
      bytes,
      width: radius * 2,
      height: radius * 2,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => fallback,
    ),
  );
}

/// A round avatar with initials on a color picked from [seed] (a room or user ID).
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar({
    required this.name,
    required this.seed,
    this.radius = 24,
    super.key,
  });

  final String name;
  final String seed;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final color =
        OxiColors.avatars[seed.hashCode.abs() % OxiColors.avatars.length];
    return CircleAvatar(
      radius: radius,
      backgroundColor: color,
      child: Text(
        initials(name),
        style: TextStyle(
          color: Colors.white,
          fontSize: radius * 0.8,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Up to two initials: the first letters of the first two words, ignoring a leading `@`/`#`.
String initials(String name) {
  final words = name
      .replaceAll(RegExp('^[@#!]'), '')
      .split(RegExp(r'[\s:._-]+'))
      .where((word) => word.isNotEmpty)
      .take(2);
  final letters = words
      .map((word) => String.fromCharCode(word.runes.first))
      .join();
  return letters.isEmpty ? '?' : letters.toUpperCase();
}
