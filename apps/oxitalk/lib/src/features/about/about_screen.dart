import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
import '../../rust/api.dart';

part 'about_screen.g.dart';

/// The app's version, and its build number where the build says it.
final class AppVersion {
  const AppVersion(this.version, [this.build]);

  final String version;
  final String? build;

  String get label =>
      build == null ? 'Version $version' : 'Version $version ($build)';
}

/// The core's version, which is the app's, with the build number once it is read.
@Riverpod(keepAlive: true)
AppVersion appVersion(Ref ref) =>
    AppVersion(coreVersion(), ref.watch(appBuildProvider).value);

/// The build number, where the build bundles it: Linux and web builds have it in
/// `version.json` (the other platforms would need a plugin); `null` elsewhere.
@Riverpod(keepAlive: true)
Future<String?> appBuild(Ref ref) async {
  try {
    final json = jsonDecode(await rootBundle.loadString('version.json'));
    if (json case {'version': final String version, 'build_number': final build}
        when version == coreVersion()) {
      return '$build';
    }
  } on Object {
    // Not bundled on this platform.
  }
  return null;
}

abstract final class AboutLinks {
  static final website = Uri.parse('https://oxitalk.com');
  static final source = Uri.parse('https://github.com/oxisoft/oxitalk');
  static final oxisoft = Uri.parse('https://oxisoft.io');
}

/// Opens the About screen over whatever is open.
void showOxiTalkAbout(BuildContext context) =>
    unawaited(context.push(Routes.about));

/// About OxiTalk, full screen: the icon in a blue hero, the version, what it is, and where
/// it lives. Back, Esc or the system's back closes it.
class AboutScreen extends ConsumerStatefulWidget {
  const AboutScreen({super.key});

  @override
  ConsumerState<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends ConsumerState<AboutScreen> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape ||
        !(ModalRoute.of(context)?.isCurrent ?? false)) {
      return false;
    }
    _close();
    return true;
  }

  void _close() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(
        homeLocation(
          ref.read(uiPrefsProvider),
          ref.read(activeAccountProvider),
        ),
      );
    }
  }

  void _open(Uri uri) => unawaited(ref.read(fileActionsProvider).launch(uri));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final version = ref.watch(appVersionProvider);
    return Scaffold(
      key: const Key('about'),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: BackButton(key: const Key('about.back'), onPressed: _close),
        title: const Text('About'),
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          _Hero(version: version),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: _Appear(
                delay: 150,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'An open-source Matrix client, privacy first, built '
                        'with Flutter on matrix-rust-sdk.',
                        key: const Key('about.tagline'),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _LinkGroup(
                        children: [
                          _LinkTile(
                            key: const Key('about.website'),
                            icon: Icons.language_rounded,
                            title: 'Website',
                            subtitle: 'oxitalk.com',
                            onTap: () => _open(AboutLinks.website),
                          ),
                          _LinkTile(
                            key: const Key('about.source'),
                            icon: Icons.code_rounded,
                            title: 'Source code',
                            subtitle: 'github.com/oxisoft/oxitalk',
                            onTap: () => _open(AboutLinks.source),
                          ),
                          _LinkTile(
                            key: const Key('about.licenses'),
                            icon: Icons.description_outlined,
                            title: 'Open-source licenses',
                            subtitle: 'The packages and fonts OxiTalk uses',
                            external: false,
                            onTap: () => showLicensePage(
                              context: context,
                              applicationName: 'OxiTalk',
                              applicationVersion: version.label,
                              applicationIcon: const Padding(
                                padding: EdgeInsets.all(8),
                                child: _AppIcon(size: 64),
                              ),
                              applicationLegalese: 'MIT License, © OxiSoft',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _LinkGroup(
                        children: [
                          _LinkTile(
                            key: const Key('about.oxisoft'),
                            icon: Icons.favorite_rounded,
                            title: 'Made by OxiSoft',
                            subtitle: 'oxisoft.io',
                            onTap: () => _open(AboutLinks.oxisoft),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Free software under the MIT License.\n'
                        'Copyright © 2026 OxiSoft.',
                        key: const Key('about.license'),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The blue band at the top: the icon, the name and the version.
class _Hero extends StatelessWidget {
  const _Hero({required this.version});

  final AppVersion version;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final top = MediaQuery.paddingOf(context).top + kToolbarHeight;
    return Container(
      key: const Key('about.hero'),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? const [Color(0xFF1A5C8A), Color(0xFF17436B), Color(0xFF0E2A45)]
              : const [Color(0xFF3FBCF5), OxiColors.accent, Color(0xFF1C82C4)],
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Stack(
        children: [
          // Two soft light circles, for depth.
          Positioned(
            top: -60,
            right: -40,
            child: _Glow(size: 220, alpha: dark ? 0.06 : 0.12),
          ),
          Positioned(
            bottom: -70,
            left: -50,
            child: _Glow(size: 200, alpha: dark ? 0.05 : 0.10),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16, top + 8, 16, 32),
            child: Center(
              child: Column(
                children: [
                  const _Appear(scale: true, child: _AppIcon(size: 112)),
                  const SizedBox(height: 18),
                  _Appear(
                    delay: 80,
                    child: Text(
                      'OxiTalk',
                      style: Theme.of(context).textTheme.headlineLarge
                          ?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                          ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _Appear(
                    delay: 120,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.28),
                        ),
                      ),
                      child: Text(
                        version.label,
                        key: const Key('about.version'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.size, required this.alpha});

  final double size;
  final double alpha;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            Colors.white.withValues(alpha: alpha),
            Colors.white.withValues(alpha: 0),
          ],
        ),
      ),
    ),
  );
}

/// The app's icon as a rounded tile with a soft shadow.
class _AppIcon extends StatelessWidget {
  const _AppIcon({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.24);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.7),
          width: 2,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x40000000),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Image.asset(
          'assets/branding/oxitalk-icon-256.png',
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          semanticLabel: 'OxiTalk icon',
        ),
      ),
    );
  }
}

/// A card of link rows.
class _LinkGroup extends StatelessWidget {
  const _LinkGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: scheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          for (final (index, child) in children.indexed) ...[
            if (index > 0) const Divider(height: 1, indent: 64),
            child,
          ],
        ],
      ),
    );
  }
}

class _LinkTile extends StatelessWidget {
  const _LinkTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.external = true,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// Opens in the browser, rather than in the app.
  final bool external;

  @override
  Widget build(BuildContext context) => ListTile(
    onTap: onTap,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
    leading: Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: OxiColors.accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 20, color: OxiColors.accent),
    ),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
    subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
    trailing: Icon(
      external ? Icons.open_in_new_rounded : Icons.chevron_right_rounded,
      size: 18,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}

/// Fades and slides [child] in once, [delay] ms after the screen opens; with [scale], it
/// grows in a little instead.
class _Appear extends StatelessWidget {
  const _Appear({required this.child, this.delay = 0, this.scale = false});

  final Widget child;
  final int delay;
  final bool scale;

  @override
  Widget build(BuildContext context) {
    const duration = 450;
    final start = delay / (duration + delay);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: duration + delay),
      curve: Interval(start, 1, curve: Curves.easeOutCubic),
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: scale
            ? Transform.scale(scale: 0.85 + 0.15 * t, child: child)
            : Transform.translate(
                offset: Offset(0, 12 * (1 - t)),
                child: child,
              ),
      ),
    );
  }
}
