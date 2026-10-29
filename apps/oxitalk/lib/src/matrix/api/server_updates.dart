/// Whether the account administers its server, and the latest releases of the server
/// software, which the app asks the release pages for only for such admins.
library;

/// How the installed version compares with the latest release.
enum ReleaseStatus {
  /// The latest release (or newer).
  upToDate,

  /// A newer release is out.
  outdated,

  /// The installed version isn't known or can't be compared.
  unknown,

  /// The project stopped; no newer release will come.
  discontinued,
}

/// The latest release of a server project and how the installed version compares.
final class ReleaseCheck {
  const ReleaseCheck({
    required this.project,
    required this.latest,
    this.url = '',
    this.status = ReleaseStatus.unknown,
    this.note,
  });

  /// "Synapse", "LiveKit", …
  final String project;

  /// The latest release's version, without a leading `v`.
  final String latest;
  final String url;
  final ReleaseStatus status;

  /// Something to know about the project (maintenance mode, discontinued).
  final String? note;
}
