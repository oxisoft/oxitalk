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
import '../../app/ui_prefs.dart';
import '../../matrix/api/matrix.dart';
import '../../rust/api.dart';
import '../../ui/format.dart';
import '../settings/server_settings.dart';

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

/// About OxiTalk, full screen: the icon in an ink hero, the version, what it is, and where
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
                      if (ref.watch(activeAccountProvider)
                          case final account?) ...[
                        const SizedBox(height: 12),
                        _ServerCard(
                          key: ValueKey('about.server.$account'),
                          account: account,
                          version: version,
                        ),
                      ],
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

/// The ink band at the top, in the icon's brand: the icon, the name and the version, a
/// cut corner bottom right and a yellow and red signal stripe.
class _Hero extends StatelessWidget {
  const _Hero({required this.version});

  final AppVersion version;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top + kToolbarHeight;
    return Container(
      key: const Key('about.hero'),
      decoration: const ShapeDecoration(
        color: OxiBrand.ink,
        shape: BeveledRectangleBorder(
          borderRadius: BorderRadius.only(bottomRight: Radius.circular(40)),
        ),
      ),
      child: Stack(
        children: [
          const Positioned(left: 24, bottom: 18, child: _SignalStripe()),
          Padding(
            padding: EdgeInsets.fromLTRB(16, top + 8, 16, 40),
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
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
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
                      decoration: const ShapeDecoration(
                        color: OxiBrand.yellow,
                        shape: BeveledRectangleBorder(
                          borderRadius: BorderRadius.all(Radius.circular(6)),
                        ),
                      ),
                      child: Text(
                        version.label,
                        key: const Key('about.version'),
                        style: const TextStyle(
                          color: OxiBrand.ink,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
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

/// A short yellow bar and a red one, like a signal level.
class _SignalStripe extends StatelessWidget {
  const _SignalStripe();

  @override
  Widget build(BuildContext context) => const IgnorePointer(
    child: Row(
      children: [
        SizedBox(
          width: 56,
          height: 4,
          child: ColoredBox(color: OxiBrand.yellow),
        ),
        SizedBox(width: 6),
        SizedBox(width: 16, height: 4, child: ColoredBox(color: OxiBrand.red)),
      ],
    ),
  );
}

/// The app's icon as a rounded tile with a thin yellow edge and a soft shadow.
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
          color: OxiBrand.yellow.withValues(alpha: 0.35),
          width: 1.5,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
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
      shape: BeveledRectangleBorder(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(10),
          bottomRight: Radius.circular(10),
        ),
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
      decoration: const ShapeDecoration(
        color: OxiBrand.ink,
        shape: BeveledRectangleBorder(
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(8),
            bottomRight: Radius.circular(8),
          ),
        ),
      ),
      child: Icon(icon, size: 20, color: OxiBrand.yellow),
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

/// The server the app runs against (the active account's): the homeserver, its software
/// and Matrix version, and whether it offers voice and video calls, through which call
/// service and media server. More is in Settings › Account › Server; Copy puts it all
/// on the clipboard for a support request.
class _ServerCard extends ConsumerWidget {
  const _ServerCard({required this.account, required this.version, super.key});

  final String account;
  final AppVersion version;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final server = ref.watch(serverInfoProvider(account));
    final services = ref.watch(callServicesProvider(account));
    final seen = ref.watch(uiPrefsProvider).callServer(account);
    final info = server.value;
    final loading = server.isLoading || services.isLoading;
    void refresh() {
      ref
        ..invalidate(serverInfoProvider(account))
        ..invalidate(callServicesProvider(account));
    }

    final lines = aboutServerLines(
      info: info,
      serverFailed: server.hasError && info == null,
      services: services.value,
      servicesFailed: services.hasError && services.value == null,
      seen: seen,
    );
    return _LinkGroup(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.dns_rounded, color: theme.colorScheme.primary),
                  const SizedBox(width: 24),
                  Expanded(
                    child: Text(
                      'Server',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (loading)
                    const SizedBox.square(
                      key: Key('about.server.loading'),
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              for (final (label, value, key) in lines)
                _ServerLine(label, value, key: Key('about.server.$key')),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    key: const Key('about.server.refresh'),
                    onPressed: loading ? null : refresh,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Refresh'),
                  ),
                  OutlinedButton.icon(
                    key: const Key('about.server.copy'),
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      await Clipboard.setData(
                        ClipboardData(
                          text: aboutDetailsText(
                            version: version,
                            lines: lines,
                            info: info,
                          ),
                        ),
                      );
                      messenger.showSnackBar(
                        const SnackBar(content: Text('Details copied')),
                      );
                    },
                    icon: const Icon(Icons.copy_rounded),
                    label: const Text('Copy details'),
                  ),
                  OutlinedButton.icon(
                    key: const Key('about.server.more'),
                    onPressed: () => unawaited(
                      context.push(Routes.settingsAccount(account)),
                    ),
                    icon: const Icon(Icons.tune_rounded),
                    label: const Text('All server details'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A label above its value on a narrow card, side by side on a wide one.
class _ServerLine extends StatelessWidget {
  const _ServerLine(this.label, this.value, {super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelText = Text(
      label,
      style: theme.textTheme.bodyMedium?.copyWith(color: context.oxi.muted),
    );
    final valueText = SelectableText(value, style: theme.textTheme.bodyMedium);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: LayoutBuilder(
        builder: (context, constraints) => constraints.maxWidth < 400
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [labelText, const SizedBox(height: 1), valueText],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 150, child: labelText),
                  Expanded(child: valueText),
                ],
              ),
      ),
    );
  }
}

const _slidingSync = 'org.matrix.simplified_msc3575';
const _delayedEvents = 'org.matrix.msc4140';

bool? _feature(ServerInfo? info, String id) {
  if (info == null || !info.versionsKnown) return null;
  for (final feature in info.unstableFeatures) {
    if (feature.id == id) return feature.enabled;
  }
  return false;
}

/// The lines of About's server card as (label, value, key): the homeserver, then calls.
/// [services] are the call services the homeserver offers; [seen] the media server the
/// last call connected to (only a join tells its version).
List<(String, String, String)> aboutServerLines({
  required ServerInfo? info,
  required bool serverFailed,
  required List<String>? services,
  required bool servicesFailed,
  required CallServerSeen? seen,
  DateTime? now,
}) {
  final unknown = serverFailed ? 'Can’t load' : 'Checking…';
  final slidingSync = _feature(info, _slidingSync);
  final delayed = _feature(info, _delayedEvents);
  final lines = <(String, String, String)>[
    ('Homeserver', info == null ? unknown : serverAddress(info), 'address'),
    (
      'Software',
      info == null ? unknown : info.software?.label ?? 'Not published',
      'software',
    ),
    (
      'Matrix version',
      info == null ? unknown : info.newestSpecVersion ?? 'Unknown',
      'matrixVersion',
    ),
    (
      'Sliding sync',
      switch (slidingSync) {
        null => info == null ? unknown : 'Unknown',
        true => 'Supported',
        false => 'Not advertised (OxiTalk needs it)',
      },
      'slidingSync',
    ),
    (
      'Federation',
      info == null ? unknown : federationLabel(info.federation),
      'federation',
    ),
    if (info?.uploadLimitBytes case final bytes?)
      ('Upload limit', fileSize(bytes), 'uploadLimit'),
  ];
  lines.add((
    'Voice and video calls',
    switch (services) {
      null => servicesFailed ? 'Can’t check' : 'Checking…',
      [] => 'Not offered by this server',
      _ => 'Supported, end-to-end encrypted',
    },
    'calls',
  ));
  if (services != null && services.isNotEmpty) {
    lines.add((
      services.length == 1 ? 'Call service' : 'Call services',
      [for (final url in services) '$url (lk-jwt-service)'].join('\n'),
      'callService',
    ));
  }
  if (services == null || services.isNotEmpty) {
    lines.add((
      'Media server',
      switch (seen) {
        null => 'Shown after the first call',
        final seen => [
          'LiveKit ${seen.version ?? '(version not told)'}'
              '${seen.region == null || seen.region!.isEmpty ? '' : ', region ${seen.region}'}',
          seen.url,
          'Seen in a call ${_when(seen.seenAt.toLocal(), now)}',
        ].join('\n'),
      },
      'mediaServer',
    ));
    if (delayed != null) {
      lines.add((
        'Call clean-up',
        delayed
            ? 'By the server (delayed events)'
            : 'By the app only (no delayed events)',
        'callCleanup',
      ));
    }
  }
  return lines;
}

String _when(DateTime time, DateTime? now) {
  final day = dayLabel(time, now: now);
  return '${day == 'Today' || day == 'Yesterday' ? day.toLowerCase() : 'on $day'}'
      ' at ${clockTime(time)}';
}

/// About's details as plain text, for a support request: the app, then the server lines,
/// then the full server details when they are known.
String aboutDetailsText({
  required AppVersion version,
  required List<(String, String, String)> lines,
  required ServerInfo? info,
}) => [
  'OxiTalk ${version.label.replaceFirst('Version ', '')}',
  for (final (label, value, _) in lines)
    '$label: ${value.replaceAll('\n', ' · ')}',
  if (info != null) ...['', serverDetailsText(info)],
].join('\n');
