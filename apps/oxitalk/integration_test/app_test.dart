import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:oxitalk/main.dart';
import 'package:oxitalk/src/rust/frb_generated.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(RustLib.init);

  testWidgets('the app starts and shows the core version', (tester) async {
    await tester.pumpWidget(const OxiTalkApp());
    expect(find.text('Rust core 0.1.1'), findsOneWidget);
  });
}
