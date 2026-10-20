import 'dart:io';

/// The app's ID: the window's Wayland app ID and X11 class, set by the Linux runner.
const linuxAppId = 'io.oxisoft.oxitalk';

/// What the desktop entry says, for the binary at [executable].
String desktopEntry(String executable) =>
    '''
[Desktop Entry]
Type=Application
Name=OxiTalk
GenericName=Matrix chat
Comment=Chat on Matrix, end-to-end encrypted
Exec="${executable.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}" %U
Icon=$linuxAppId
Terminal=false
Categories=Network;InstantMessaging;Chat;
Keywords=Matrix;Chat;Messenger;E2EE;
StartupWMClass=$linuxAppId
StartupNotify=true
''';

/// Makes the desktop show OxiTalk's name and icon for its window, as GNOME and other
/// Wayland desktops take them only from an installed desktop entry named after the app ID.
/// Writes `<data home>/applications/io.oxisoft.oxitalk.desktop`, running [executable], and
/// the icon from the bundle beside it into the user's icon theme; again when the binary
/// moved or the icon changed. Not in a Flatpak or when a package installed the entry
/// ([dataDirs]); failures are ignored, the app runs on with the default icon.
Future<void> registerLinuxDesktopEntry({
  required String executable,
  required String dataHome,
  required List<String> dataDirs,
  bool flatpak = false,
}) async {
  if (flatpak) return;
  for (final dir in dataDirs) {
    if (File('$dir/applications/$linuxAppId.desktop').existsSync()) return;
  }
  try {
    final bundleIcon = File(
      '${File(executable).parent.path}/data/app_icon.png',
    );
    if (bundleIcon.existsSync()) {
      final icon = File('$dataHome/icons/hicolor/256x256/apps/$linuxAppId.png');
      final bytes = await bundleIcon.readAsBytes();
      if (!icon.existsSync() || !_same(await icon.readAsBytes(), bytes)) {
        await icon.parent.create(recursive: true);
        await icon.writeAsBytes(bytes, flush: true);
      }
    }
    final entry = File('$dataHome/applications/$linuxAppId.desktop');
    final text = desktopEntry(executable);
    if (!entry.existsSync() || await entry.readAsString() != text) {
      await entry.parent.create(recursive: true);
      await entry.writeAsString(text, flush: true);
    }
  } on FileSystemException {
    // A read-only home and the like: the default icon it is.
  }
}

/// Registers the running app, with the XDG directories of this session.
Future<void> registerThisLinuxApp() {
  final env = Platform.environment;
  final home = env['HOME'] ?? '';
  final dataHome = env['XDG_DATA_HOME'] ?? '';
  return registerLinuxDesktopEntry(
    executable: Platform.resolvedExecutable,
    dataHome: dataHome.isEmpty ? '$home/.local/share' : dataHome,
    dataDirs: (env['XDG_DATA_DIRS'] ?? '').isEmpty
        ? const ['/usr/local/share', '/usr/share']
        : env['XDG_DATA_DIRS']!.split(':'),
    flatpak: env.containsKey('FLATPAK_ID'),
  );
}

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
