import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const releaseBundleId = 'com.vinabike.vinabikeErp';
  const debugBundleId = '$releaseBundleId.debug';

  test('macOS Debug owns a different sandbox identity from Release', () {
    final appInfo = _xcconfig('macos/Runner/Configs/AppInfo.xcconfig');
    final debug = _xcconfig('macos/Runner/Configs/Debug.xcconfig');
    final release = _xcconfig('macos/Runner/Configs/Release.xcconfig');

    expect(
      appInfo['PRODUCT_BUNDLE_IDENTIFIER'],
      r'$(VINABIKE_PRODUCT_BUNDLE_IDENTIFIER)',
      reason: 'the target must consume the configuration-specific identity',
    );
    expect(
      debug['VINABIKE_PRODUCT_BUNDLE_IDENTIFIER'],
      debugBundleId,
      reason: 'Debug needs its own macOS container for auth and local caches',
    );
    expect(
      release['VINABIKE_PRODUCT_BUNDLE_IDENTIFIER'],
      releaseBundleId,
      reason: 'the installed app and signed update manifests keep this ID',
    );
    expect(
      debug['VINABIKE_PRODUCT_BUNDLE_IDENTIFIER'],
      isNot(release['VINABIKE_PRODUCT_BUNDLE_IDENTIFIER']),
    );

    final infoPlist = File('macos/Runner/Info.plist').readAsStringSync();
    expect(
      infoPlist,
      contains('<string>\$(PRODUCT_BUNDLE_IDENTIFIER)</string>'),
      reason: 'the built bundle must receive the effective Xcode setting',
    );
  });

  test('canonical native-session launch fails closed before Flutter starts',
      () {
    final script = File('scripts/dev/native_session.sh').readAsStringSync();

    expect(
      script,
      contains("EXPECTED_DEBUG_BUNDLE_ID='$debugBundleId'"),
    );
    expect(
      script,
      contains("EXPECTED_RELEASE_BUNDLE_ID='$releaseBundleId'"),
    );
    expect(script, contains('-showBuildSettings'));
    expect(script, contains('verify_bundle_id_separation || exit 1'));

    final guard = script.indexOf('verify_bundle_id_separation || exit 1');
    final launch = script.indexOf('screen -c "\$SCREENRC" -dmS');
    expect(guard, greaterThanOrEqualTo(0));
    expect(launch, greaterThan(guard));
  });
}

Map<String, String> _xcconfig(String path) {
  final settings = <String, String>{};
  for (final rawLine in File(path).readAsLinesSync()) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('//') || line.startsWith('#')) {
      continue;
    }
    final separator = line.indexOf('=');
    if (separator <= 0) continue;
    settings[line.substring(0, separator).trim()] =
        line.substring(separator + 1).trim();
  }
  return settings;
}
