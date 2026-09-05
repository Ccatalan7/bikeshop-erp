import 'dart:io';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() =>
    integrationDriver(onScreenshot: (name, bytes, [args]) async {
      final output = Directory('.tmp/messaging-ui-device');
      await output.create(recursive: true);
      await File('${output.path}/$name.png').writeAsBytes(bytes);
      return true;
    });
