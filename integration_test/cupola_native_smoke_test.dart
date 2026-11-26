import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:cupola/features/home/presentation/home_screen.dart';
import 'package:cupola/main.dart' as app;

/// Native smoke gate for macOS, iOS Simulator and Android Emulator.
///
/// This deliberately verifies the real bootstrap path rather than mounting a
/// hand-built ProviderScope. It is not the feature E2E suite: that suite must
/// still exercise the seeded service lab and every service tab. Its job is to
/// catch platform/plugin/bootstrap regressions before those suites waste time.
/// Pumps until the tree is quiet, with a ceiling rather than a fixed sleep.
///
/// `pump(Duration(seconds: 5))` advances one frame and then waits: it does not
/// wait for the bootstrap's async work, so it was both slower than it needed
/// to be on a fast machine and too short on a cold simulator.
/// `pumpAndSettle` can itself time out on a screen with a looping animation,
/// which is why the timeout is caught and the assertions are left to say
/// whether the app actually arrived.
Future<void> _settle(WidgetTester tester) async {
  try {
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 30),
    );
  } on FlutterError {
    // A persistent animation; the tree is as settled as it is going to get.
    await tester.pump(const Duration(seconds: 1));
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const captureScreenshot = bool.fromEnvironment('CUPOLA_NATIVE_SCREENSHOT');

  testWidgets('Stack boots straight to the Home', (tester) async {
    app.main();
    await _settle(tester);

    expect(find.byType(app.CupolaApp), findsOneWidget);

    expect(
      find.byType(HomeScreen),
      findsOneWidget,
      reason: 'the native bootstrap must land on the Home',
    );

    // Keep the evidence artifact for the visual-E2E ledger. The screenshot
    // is intentionally named by target-independent state, so the same test
    // can be compared across macOS, iOS and Android.
    // Some headless Android renderers expose no Flutter screenshot surface and
    // leave `takeScreenshot` pending forever. The boot assertion remains a
    // valid native smoke gate there; visual evidence can be captured with the
    // platform screenshot tool, or this branch can be opted into explicitly
    // on a renderer that supports the integration-test screenshot protocol.
    if (captureScreenshot) {
      await binding.convertFlutterSurfaceToImage();
      await binding.takeScreenshot('cupola-native-boot');
    }
  });
}
