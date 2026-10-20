import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oxitalk/src/app/linux_desktop_entry.dart';

void main() {
  late Directory root;
  late String executable;
  late String dataHome;

  setUp(() {
    root = Directory.systemTemp.createTempSync('oxitalk-desktop');
    final bundle = Directory('${root.path}/bundle/data')
      ..createSync(recursive: true);
    File('${bundle.path}/app_icon.png').writeAsBytesSync([1, 2, 3]);
    executable = '${root.path}/bundle/oxitalk';
    dataHome = '${root.path}/home/.local/share';
  });
  tearDown(() => root.deleteSync(recursive: true));

  File entry() => File('$dataHome/applications/io.oxisoft.oxitalk.desktop');
  File icon() =>
      File('$dataHome/icons/hicolor/256x256/apps/io.oxisoft.oxitalk.png');

  test(
    'the running app installs its entry and icon, and follows a move',
    () async {
      await registerLinuxDesktopEntry(
        executable: executable,
        dataHome: dataHome,
        dataDirs: ['${root.path}/usr/share'],
      );
      expect(entry().readAsStringSync(), contains('Exec="$executable" %U'));
      expect(entry().readAsStringSync(), contains('Icon=io.oxisoft.oxitalk'));
      expect(
        entry().readAsStringSync(),
        contains('StartupWMClass=io.oxisoft.oxitalk'),
      );
      expect(icon().readAsBytesSync(), [1, 2, 3]);

      final moved = '${root.path}/elsewhere/oxitalk';
      await registerLinuxDesktopEntry(
        executable: moved,
        dataHome: dataHome,
        dataDirs: const [],
      );
      expect(entry().readAsStringSync(), contains('Exec="$moved" %U'));
    },
  );

  test('nothing is written when a package installed the entry, or in a '
      'Flatpak', () async {
    final system = Directory('${root.path}/usr/share/applications')
      ..createSync(recursive: true);
    File('${system.path}/io.oxisoft.oxitalk.desktop').writeAsStringSync('x');
    await registerLinuxDesktopEntry(
      executable: executable,
      dataHome: dataHome,
      dataDirs: ['${root.path}/usr/share'],
    );
    expect(entry().existsSync(), isFalse);

    await registerLinuxDesktopEntry(
      executable: executable,
      dataHome: dataHome,
      dataDirs: const [],
      flatpak: true,
    );
    expect(entry().existsSync(), isFalse);
    expect(icon().existsSync(), isFalse);
  });

  test('the packaged entry says the same, but runs the installed binary', () {
    final packaged = File('linux/io.oxisoft.oxitalk.desktop')
        .readAsStringSync();
    expect(
      packaged,
      desktopEntry('oxitalk').replaceFirst('Exec="oxitalk"', 'Exec=oxitalk'),
    );
  });
}
