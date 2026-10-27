import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../matrix/api/matrix.dart';
import '../../ui/format.dart';
import 'settings_heading.dart';

/// The homeserver [account] uses, in Settings › Account: its address, software, Matrix
/// version, federation, sign-in methods and upload limit at once; room versions,
/// capabilities, unstable features, `.well-known` and the connection under More details.
/// Asked of the server when the section opens and on Refresh; Copy server details puts a
/// plain-text summary on the clipboard, for support.
class AccountServerSettings extends ConsumerWidget {
  const AccountServerSettings({required this.account, super.key});

  final String account;

  Future<void> _copy(BuildContext context, ServerInfo info) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: serverDetailsText(info)));
    messenger.showSnackBar(
      const SnackBar(content: Text('Server details copied')),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final server = ref.watch(serverInfoProvider(account));
    void refresh() => ref.invalidate(serverInfoProvider(account));
    final info = server.value;
    return Column(
      key: const Key('settings.server'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SettingsHeading(
          'Server',
          subtitle: 'The homeserver this account uses.',
        ),
        if (info != null) ...[
          _ServerLines(info: info),
          if (server.hasError && !server.isLoading)
            _ErrorLine(
              text: 'Can’t refresh the server details.',
              onRetry: refresh,
            ),
          _MoreDetails(info: info),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  key: const Key('server.refresh'),
                  onPressed: server.isLoading ? null : refresh,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Refresh'),
                ),
                OutlinedButton.icon(
                  key: const Key('server.copy'),
                  onPressed: () => unawaited(_copy(context, info)),
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text('Copy server details'),
                ),
                if (server.isLoading)
                  const SizedBox.square(
                    key: Key('server.refreshing'),
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),
        ] else if (server.hasError && !server.isLoading)
          _ErrorLine(text: 'Can’t load the server details.', onRetry: refresh)
        else
          const Padding(
            key: Key('server.loading'),
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }
}

class _ErrorLine extends StatelessWidget {
  const _ErrorLine({required this.text, required this.onRetry});

  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => ListTile(
    key: const Key('server.error'),
    title: Text(text),
    trailing: OutlinedButton(
      key: const Key('server.retry'),
      onPressed: onRetry,
      child: const Text('Try again'),
    ),
  );
}

/// The key lines, shown at once.
class _ServerLines extends StatelessWidget {
  const _ServerLines({required this.info});

  final ServerInfo info;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _InfoLine(
        'Address',
        serverAddress(info),
        key: const Key('server.address'),
      ),
      _InfoLine(
        'Software',
        info.software?.label ?? 'Unknown',
        key: const Key('server.software'),
      ),
      _InfoLine(
        'Matrix version',
        info.newestSpecVersion ?? 'Unknown',
        key: const Key('server.matrixVersion'),
      ),
      _InfoLine(
        'Federation',
        federationLabel(info.federation),
        key: const Key('server.federation'),
      ),
      _InfoLine(
        'Sign-in methods',
        signInLabel(info),
        key: const Key('server.signIn'),
      ),
      _InfoLine('Upload limit', switch (info.uploadLimitBytes) {
        final bytes? => fileSize(bytes),
        null => 'Unknown',
      }, key: const Key('server.uploadLimit')),
    ],
  );
}

/// One label and its value: side by side on a wide pane, the label above on a narrow one.
class _InfoLine extends StatelessWidget {
  const _InfoLine(this.label, this.value, {super.key});

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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: LayoutBuilder(
        builder: (context, constraints) => constraints.maxWidth < 420
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [labelText, const SizedBox(height: 1), valueText],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 170, child: labelText),
                  Expanded(child: valueText),
                ],
              ),
      ),
    );
  }
}

/// A sub-heading inside More details.
class _Group extends StatelessWidget {
  const _Group(this.title, this.children);

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            title,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        ...children,
      ],
    );
  }
}

/// Room versions, capabilities, unstable features, `.well-known` and the connection.
class _MoreDetails extends StatelessWidget {
  const _MoreDetails({required this.info});

  final ServerInfo info;

  @override
  Widget build(BuildContext context) {
    final caps = info.capabilities;
    final conn = info.connection;
    final named = [
      for (final feature in info.unstableFeatures)
        if (feature.label != null) feature,
    ];
    return Theme(
      // No lines above and below the opened part.
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: const Key('server.more'),
        title: const Text('More details'),
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        shape: const Border(),
        collapsedShape: const Border(),
        children: [
          _Group('Discovery', [
            _InfoLine('Server name', info.serverName),
            _InfoLine(
              'Client well-known',
              wellKnownLabel(info.wellKnownClient, info.wellKnownBaseUrl),
            ),
            _InfoLine(
              'Server well-known',
              wellKnownLabel(info.wellKnownServer, info.serverDelegation),
            ),
            if (info.software case final software?)
              _InfoLine('Software found at', software.source),
          ]),
          _Group('Connection', [
            _InfoLine(
              'IP addresses',
              conn.addresses.isEmpty ? 'Unknown' : conn.addresses.join(', '),
            ),
            _InfoLine('Round trip', roundTripLabel(conn.roundTrip)),
            _InfoLine('Encrypted (TLS)', connectionLabel(conn)),
          ]),
          _Group('Sign-in', [
            _InfoLine('Login types', switch (info.login) {
              final login? when login.flows.isNotEmpty => login.flows.join(
                ', ',
              ),
              _ => 'Unknown',
            }),
            _InfoLine('OAuth / OIDC', oauthLabel(info)),
          ]),
          _Group('What accounts may change', [
            if (caps == null)
              const _InfoLine('Capabilities', 'Unknown')
            else ...[
              _InfoLine('Password', _yesNo(caps.changePassword)),
              _InfoLine('Display name', _yesNo(caps.setDisplayName)),
              _InfoLine('Picture', _yesNo(caps.setAvatar)),
              _InfoLine('Email and phone', _yesNo(caps.change3pids)),
              _InfoLine('Sign in other devices', _yesNo(caps.getLoginToken)),
            ],
          ]),
          _Group('Room versions', [
            _InfoLine('Default', caps?.defaultRoomVersion ?? 'Unknown'),
            _InfoLine('Stable', roomVersionsLabel(caps, stable: true)),
            _InfoLine('Unstable', roomVersionsLabel(caps, stable: false)),
          ]),
          _Group('Matrix versions', [
            _InfoLine(
              'Supported',
              info.specVersions.isEmpty
                  ? 'Unknown'
                  : info.specVersions.join(', '),
            ),
          ]),
          _Group('Features', [
            if (named.isEmpty)
              const _InfoLine('Named features', 'None')
            else
              for (final feature in named)
                _InfoLine(
                  feature.label!,
                  [
                    feature.enabled ? 'On' : 'Off',
                    if (feature.usedByApp) 'used by OxiTalk',
                  ].join(' · '),
                ),
            if (info.unstableFeatures.isNotEmpty)
              ExpansionTile(
                key: const Key('server.rawFeatures'),
                title: Text(
                  'All unstable features (${info.unstableFeatures.length})',
                ),
                tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
                shape: const Border(),
                collapsedShape: const Border(),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: SelectableText(
                      [
                        for (final f in info.unstableFeatures)
                          '${f.id}: ${f.enabled ? 'on' : 'off'}',
                      ].join('\n'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
          ]),
          _Group('Support', [
            ...supportLines(info).map((line) => _InfoLine(line.$1, line.$2)),
          ]),
        ],
      ),
    );
  }
}

String _yesNo(bool value) => value ? 'Allowed' : 'Not allowed';

/// The base URL without its trailing `/`.
String serverAddress(ServerInfo info) => info.homeserverUrl.endsWith('/')
    ? info.homeserverUrl.substring(0, info.homeserverUrl.length - 1)
    : info.homeserverUrl;

String federationLabel(Federation federation) => switch (federation) {
  Federation.enabled => 'On',
  Federation.disabled => 'Off',
  Federation.unknown => 'Unknown',
};

/// The ways a person signs in, in words; login types only bridges use are left out.
String signInLabel(ServerInfo info) {
  final login = info.login;
  final methods = <String>[
    if (login != null)
      for (final flow in login.flows)
        ?switch (flow) {
          'm.login.password' => 'Password',
          'm.login.sso' =>
            login.ssoProviders.isEmpty
                ? 'Single sign-on'
                : 'Single sign-on (${login.ssoProviders.join(', ')})',
          'm.login.token' => 'Login token',
          'm.login.application_service' => null,
          _ => flow,
        },
    if (info.oauth == Availability.yes) 'OAuth',
  ];
  if (methods.isEmpty) return login == null ? 'Unknown' : 'None';
  return methods.join(', ');
}

String wellKnownLabel(Probe probe, String? value) => switch (probe) {
  Probe.found => value ?? 'Found, but empty',
  Probe.notFound => 'Not published',
  Probe.noAnswer => 'No answer',
};

String roundTripLabel(Duration? roundTrip) => switch (roundTrip) {
  final time? when time.inMilliseconds < 1 => 'Under 1 ms',
  final time? => '${time.inMilliseconds} ms',
  null => 'Unknown',
};

String connectionLabel(ConnectionInfo conn) =>
    [if (conn.tls) 'Yes' else 'No', ?conn.httpVersion].join(' · ');

String oauthLabel(ServerInfo info) => switch (info.oauth) {
  Availability.yes => switch (info.oauthIssuer) {
    final issuer? => 'Yes · $issuer',
    null => 'Yes',
  },
  Availability.no => 'Not offered',
  Availability.unknown => 'Unknown',
};

String roomVersionsLabel(ServerCapabilities? caps, {required bool stable}) {
  if (caps == null) return 'Unknown';
  final versions = [
    for (final room in caps.roomVersions)
      if (room.stable == stable) room.version,
  ];
  return versions.isEmpty ? 'None' : versions.join(', ');
}

/// The support document as label and value lines.
List<(String, String)> supportLines(ServerInfo info) {
  final support = info.support;
  if (info.wellKnownSupport != Probe.found || support == null) {
    return [('Contacts', wellKnownLabel(info.wellKnownSupport, null))];
  }
  return [
    for (final contact in support.contacts)
      (
        switch (contact.role) {
          'm.role.admin' => 'Admin',
          'm.role.security' => 'Security',
          final role => role,
        },
        [?contact.matrixId, ?contact.email].join(', '),
      ),
    if (support.page case final page?) ('Support page', page),
    if (support.contacts.isEmpty && support.page == null)
      ('Contacts', 'None listed'),
  ];
}

/// Everything shown, as plain text for a support request. The account's own ID is left
/// out; the server's name and address are in.
String serverDetailsText(ServerInfo info) {
  final caps = info.capabilities;
  final conn = info.connection;
  final lines = <String>[
    'Server details (OxiTalk)',
    'Address: ${serverAddress(info)}',
    'Server name: ${info.serverName}',
    'Software: ${info.software?.label ?? 'Unknown'}'
        '${info.software == null ? '' : ' (from ${info.software!.source})'}',
    'Matrix version: ${info.newestSpecVersion ?? 'Unknown'}',
    'Federation: ${federationLabel(info.federation)}',
    'Sign-in methods: ${signInLabel(info)}',
    'Login types: ${info.login?.flows.join(', ') ?? 'Unknown'}',
    'OAuth / OIDC: ${oauthLabel(info)}',
    'Upload limit: ${switch (info.uploadLimitBytes) {
      final bytes? => fileSize(bytes),
      null => 'Unknown',
    }}',
    'Client well-known: '
        '${wellKnownLabel(info.wellKnownClient, info.wellKnownBaseUrl)}',
    'Server well-known: '
        '${wellKnownLabel(info.wellKnownServer, info.serverDelegation)}',
    for (final (label, value) in supportLines(info)) 'Support $label: $value',
    'IP addresses: '
        '${conn.addresses.isEmpty ? 'Unknown' : conn.addresses.join(', ')}',
    'Round trip: ${roundTripLabel(conn.roundTrip)}',
    'TLS: ${connectionLabel(conn)}',
    if (caps == null)
      'Capabilities: Unknown'
    else ...[
      'Change password: ${_yesNo(caps.changePassword)}',
      'Change display name: ${_yesNo(caps.setDisplayName)}',
      'Change picture: ${_yesNo(caps.setAvatar)}',
      'Change email and phone: ${_yesNo(caps.change3pids)}',
      'Sign in other devices: ${_yesNo(caps.getLoginToken)}',
      'Default room version: ${caps.defaultRoomVersion ?? 'Unknown'}',
      'Stable room versions: ${roomVersionsLabel(caps, stable: true)}',
      'Unstable room versions: ${roomVersionsLabel(caps, stable: false)}',
    ],
    'Matrix versions: '
        '${info.specVersions.isEmpty ? 'Unknown' : info.specVersions.join(', ')}',
    'Unstable features: '
        '${info.unstableFeatures.isEmpty ? 'None' : [for (final f in info.unstableFeatures) '${f.id}${f.enabled ? '' : ' (off)'}'].join(', ')}',
  ];
  return lines.join('\n');
}
