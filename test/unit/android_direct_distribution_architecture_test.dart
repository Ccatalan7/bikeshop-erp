import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android release builds never fall back to the debug signing key', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final publisher = File(
      'scripts/android/publish_direct_release.sh',
    ).readAsStringSync();

    expect(gradle, contains('VINABIKE_ANDROID_KEYSTORE_PATH'));
    expect(gradle, contains('VINABIKE_ANDROID_STORE_PASSWORD'));
    expect(gradle, contains('signingConfigs.findByName("release")'));
    expect(gradle, isNot(contains('signingConfigs.getByName("debug")')));
    expect(publisher, contains('EXPECTED_SIGNER_CERT_SHA256'));
    expect(publisher, contains('/storage/v1/upload/resumable'));
    expect(publisher, contains('chunk_size=6291456'));
    expect(publisher, contains('Tus-Resumable: 1.0.0'));
    expect(publisher, contains('--split-per-abi'));
    expect(publisher, contains('app-arm64-v8a-release.apk'));
    expect(publisher, contains('APK_PART_BYTES=41943040'));
    expect(
      publisher,
      contains(
        '7e651eb2989b22a9d9262f91f0657e3a512134ac7675715fed144273ad2a897c',
      ),
    );
  });

  test('Android installer handoff is package-scoped and cache-scoped', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final activity = File(
      'android/app/src/main/kotlin/com/vinabike/erp/MainActivity.kt',
    ).readAsStringSync();
    final paths = File(
      'android/app/src/main/res/xml/update_file_paths.xml',
    ).readAsStringSync();

    expect(manifest, contains('android.permission.REQUEST_INSTALL_PACKAGES'));
    expect(manifest, contains(r'${applicationId}.fileprovider'));
    expect(activity, contains(r'"$packageName.fileprovider"'));
    expect(activity, contains('packageManager.canRequestPackageInstalls()'));
    expect(activity, contains('apk.path.startsWith'));
    expect(paths, contains('path="android-updates/"'));
  });

  test('private route and in-app prompt share one release repository', () {
    final page = File(
      'lib/public_store/pages/android_app_download_page.dart',
    ).readAsStringSync();
    final service = File(
      'lib/shared/services/android_update_service_io.dart',
    ).readAsStringSync();
    final router = File(
      'lib/public_store/routes/public_store_router.dart',
    ).readAsStringSync();
    final firebase = File('firebase.json').readAsStringSync();

    expect(page, contains('MobileReleaseRepository'));
    expect(service, contains('MobileReleaseRepository'));
    expect(service, contains("sha256.bind(apk.openRead())"));
    expect(router, contains('/cuenta/descargas/android'));
    expect(firebase, contains('X-Robots-Tag'));
    expect(firebase, contains('noindex, nofollow, noarchive'));
  });
}
