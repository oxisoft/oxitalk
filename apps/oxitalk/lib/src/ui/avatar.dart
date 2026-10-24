import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../app/theme.dart';

/// A Matrix picture ([url], `mxc://`) of [account]'s server, its corners cut; [InitialsAvatar]
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

/// The shape of an avatar [radius] across half its side: a square with two cut corners,
/// as the brand's bubble.
ShapeBorder avatarShape(double radius) =>
    OxiShapes.cut(radius < 12 ? 2 : (radius * 0.25).clamp(3, 8));

/// An encoded image in the avatar shape; [fallback] if it can't be decoded.
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
  Widget build(BuildContext context) => ClipPath(
    clipper: ShapeBorderClipper(shape: avatarShape(radius)),
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

/// An avatar with initials on a colour picked from [seed] (a room or user ID).
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
    final color = seed.isEmpty
        ? OxiColors.avatarFallback
        : OxiColors.avatarOf(seed);
    return Container(
      width: radius * 2,
      height: radius * 2,
      alignment: Alignment.center,
      decoration: ShapeDecoration(color: color, shape: avatarShape(radius)),
      child: Text(
        initials(name),
        maxLines: 1,
        style: TextStyle(
          color: Colors.white,
          fontSize: radius * 0.72,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
    );
  }
}

/// An icon in the avatar shape, where a list row has no picture: on the quiet surface, in
/// the text colour, unless [background] and [foreground] say otherwise.
class IconAvatar extends StatelessWidget {
  const IconAvatar({
    required this.icon,
    this.radius = 20,
    this.iconSize,
    this.background,
    this.foreground,
    super.key,
  });

  final IconData? icon;
  final double radius;
  final double? iconSize;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) => Container(
    width: radius * 2,
    height: radius * 2,
    alignment: Alignment.center,
    decoration: ShapeDecoration(
      color: background ?? context.oxi.panel2,
      shape: avatarShape(radius),
    ),
    child: icon == null
        ? null
        : Icon(icon, size: iconSize, color: foreground ?? context.oxi.text),
  );
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
