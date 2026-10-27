/// What the app found out about an account's homeserver; see [ServerInfo].
library;

/// Whether a document the server may publish (`.well-known`) is there.
enum Probe {
  found,

  /// The server answered that there is none.
  notFound,

  /// No answer: the host can't be reached, or it took too long.
  noAnswer,
}

/// Whether the server talks to other Matrix servers.
enum Federation { enabled, disabled, unknown }

/// Whether the server offers something; [unknown] when it didn't answer.
enum Availability { yes, no, unknown }

/// The software the homeserver runs, and where that was read.
final class ServerSoftware {
  const ServerSoftware({this.name, this.version, this.source = ''});

  final String? name;
  final String? version;

  /// The endpoint or header that told it.
  final String source;

  /// "Tuwunel 1.9.4", or whichever half is known.
  String get label => [?name, ?version].join(' ');

  @override
  bool operator ==(Object other) =>
      other is ServerSoftware &&
      other.name == name &&
      other.version == version &&
      other.source == source;

  @override
  int get hashCode => Object.hash(name, version, source);
}

/// One entry of the server's unstable features.
final class UnstableFeature {
  const UnstableFeature({
    required this.id,
    this.enabled = true,
    this.label,
    this.usedByApp = false,
  });

  final String id;
  final bool enabled;

  /// What it is, for the features worth naming.
  final String? label;

  /// The app uses it when the server has it.
  final bool usedByApp;
}

/// How one can sign in to the server.
final class LoginInfo {
  const LoginInfo({
    this.flows = const [],
    this.getLoginToken = false,
    this.ssoProviders = const [],
  });

  /// The login types, e.g. `m.login.password`, in the server's order.
  final List<String> flows;

  /// A signed-in device may sign in another one.
  final bool getLoginToken;

  /// The names of the single sign-on providers.
  final List<String> ssoProviders;
}

/// One room version the server can create rooms with.
final class RoomVersion {
  const RoomVersion(this.version, {this.stable = true});

  final String version;
  final bool stable;
}

/// What an account may do on the server.
final class ServerCapabilities {
  const ServerCapabilities({
    this.changePassword = true,
    this.setDisplayName = true,
    this.setAvatar = true,
    this.change3pids = true,
    this.getLoginToken = false,
    this.defaultRoomVersion,
    this.roomVersions = const [],
  });

  final bool changePassword;
  final bool setDisplayName;
  final bool setAvatar;
  final bool change3pids;
  final bool getLoginToken;
  final String? defaultRoomVersion;
  final List<RoomVersion> roomVersions;
}

/// One contact of the server's support document.
final class SupportContact {
  const SupportContact({required this.role, this.matrixId, this.email});

  /// `m.role.admin`, `m.role.security`, or another.
  final String role;
  final String? matrixId;
  final String? email;
}

/// The server's support document.
final class SupportInfo {
  const SupportInfo({this.contacts = const [], this.page});

  final List<SupportContact> contacts;
  final String? page;
}

/// How the app reaches the server.
final class ConnectionInfo {
  const ConnectionInfo({
    this.host = '',
    this.port,
    this.addresses = const [],
    this.roundTrip,
    this.tls = false,
    this.httpVersion,
  });

  final String host;
  final int? port;

  /// What the system's resolver gives for [host].
  final List<String> addresses;

  /// How long one `/versions` request took.
  final Duration? roundTrip;
  final bool tls;

  /// E.g. "HTTP/2.0".
  final String? httpVersion;
}

/// Everything found out about an account's homeserver. A part the server didn't answer is
/// `null`, empty or unknown.
final class ServerInfo {
  const ServerInfo({
    required this.userId,
    required this.homeserverUrl,
    required this.serverName,
    this.wellKnownClient = Probe.noAnswer,
    this.wellKnownBaseUrl,
    this.wellKnownServer = Probe.noAnswer,
    this.serverDelegation,
    this.software,
    this.federation = Federation.unknown,
    this.versionsKnown = false,
    this.specVersions = const [],
    this.newestSpecVersion,
    this.unstableFeatures = const [],
    this.login,
    this.oauth = Availability.unknown,
    this.oauthIssuer,
    this.capabilities,
    this.uploadLimitBytes,
    this.wellKnownSupport = Probe.noAnswer,
    this.support,
    this.connection = const ConnectionInfo(),
  });

  /// The account it is about.
  final String userId;

  /// The base URL the account uses.
  final String homeserverUrl;

  /// The domain of the user ID.
  final String serverName;
  final Probe wellKnownClient;
  final String? wellKnownBaseUrl;
  final Probe wellKnownServer;

  /// Where other servers reach this one (`m.server`).
  final String? serverDelegation;
  final ServerSoftware? software;
  final Federation federation;

  /// Whether the server listed its Matrix versions.
  final bool versionsKnown;

  /// Oldest first.
  final List<String> specVersions;
  final String? newestSpecVersion;

  /// The named ones first.
  final List<UnstableFeature> unstableFeatures;
  final LoginInfo? login;

  /// Sign-in through OAuth 2.0 / OIDC (e.g. Matrix Authentication Service).
  final Availability oauth;
  final String? oauthIssuer;
  final ServerCapabilities? capabilities;
  final int? uploadLimitBytes;
  final Probe wellKnownSupport;
  final SupportInfo? support;
  final ConnectionInfo connection;
}
