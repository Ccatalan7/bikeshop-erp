import 'package:integration_test/integration_test.dart';

import '../test/widget/chat_message_interactions_test.dart' as gestures;

/// Auth-free device smoke for the exact interaction owner used by ChatWindow.
/// Run with: fvm flutter test integration_test/messaging_gestures_device_test.dart
/// -d emulator-5554. It never loads production data or sends messages.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  gestures.main();
}
