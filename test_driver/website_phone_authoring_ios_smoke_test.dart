import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  await integrationDriver(
    onScreenshot: (name, bytes, [args]) async {
      final output = File('/private/tmp/$name.png');
      await output.writeAsBytes(bytes, flush: true);
      stdout.writeln('IOS_SMOKE_SCREENSHOT=${output.path}');
      return true;
    },
  );
}
