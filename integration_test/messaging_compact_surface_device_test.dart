import 'package:integration_test/integration_test.dart';
import '../test/widget/messaging_compact_surface_test.dart' as surface;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  surface.runMessagingCompactSurfaceTests(
      device: true,
      capture: (name, tester) async {
        if (name.endsWith('-keyboard')) {
          await binding.convertFlutterSurfaceToImage();
        }
        await tester.pump();
        await binding.takeScreenshot(name);
      });
}
