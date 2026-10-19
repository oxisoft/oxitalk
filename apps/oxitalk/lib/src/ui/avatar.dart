import 'package:flutter/material.dart';

import '../app/theme.dart';

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
