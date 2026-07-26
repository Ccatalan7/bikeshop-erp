import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String normalized(String value) => value.replaceAll(RegExp(r'\s+'), ' ');

  Future<({int exitCode, String stdout, String stderr})> parseSignerDigest(
      String apksignerOutput) async {
    final process = await Process.start(
      'bash',
      ['scripts/android/extract_apksigner_cert_sha256.sh'],
    );
    process.stdin.write(apksignerOutput);
    await process.stdin.close();
    final output =
        await process.stdout.transform(systemEncoding.decoder).join();
    final error = await process.stderr.transform(systemEncoding.decoder).join();
    final exitCode = await process.exitCode;
    return (
      exitCode: exitCode,
      stdout: output.trim(),
      stderr: error.trim(),
    );
  }

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
      contains('extract_apksigner_cert_sha256.sh'),
    );
    expect(
      publisher,
      contains(
        '7e651eb2989b22a9d9262f91f0657e3a512134ac7675715fed144273ad2a897c',
      ),
    );
    expect(
      normalized(publisher),
      contains(
        r'if [[ "$SIGNER_CERT_SHA256" != "$EXPECTED_SIGNER_CERT_SHA256" ]]',
      ),
    );
  });

  test('Android signer parser supports legacy and Build Tools 37 output',
      () async {
    const digest =
        '7e651eb2989b22a9d9262f91f0657e3a512134ac7675715fed144273ad2a897c';
    final legacy = await parseSignerDigest(
      'Signer #1 certificate SHA-256 digest: $digest\n',
    );
    final buildTools37 = await parseSignerDigest(
      'V2 Signer: certificate SHA-256 digest: ${digest.toUpperCase()}\n',
    );

    expect(legacy.exitCode, 0, reason: legacy.stderr);
    expect(legacy.stdout, digest);
    expect(buildTools37.exitCode, 0, reason: buildTools37.stderr);
    expect(buildTools37.stdout, digest);
  });

  test('Android signer parser fails closed for ambiguous certificates',
      () async {
    const expected =
        '7e651eb2989b22a9d9262f91f0657e3a512134ac7675715fed144273ad2a897c';
    const unexpected =
        '8e651eb2989b22a9d9262f91f0657e3a512134ac7675715fed144273ad2a897c';
    final ambiguous = await parseSignerDigest(
      'V2 Signer: certificate SHA-256 digest: $expected\n'
      'V3 Signer: certificate SHA-256 digest: $unexpected\n',
    );

    expect(ambiguous.exitCode, isNot(0));
    expect(ambiguous.stdout, isEmpty);
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

  test('protected Android workflow binds one exact source and shared notes',
      () {
    final workflow = File(
      '.github/workflows/android-release.yml',
    ).readAsStringSync();
    final compactWorkflow = normalized(workflow);
    final productionBoundary = workflow.indexOf('environment: Production');

    expect(workflow, contains('publish_release:'));
    expect(workflow, contains('workflow_call:'));
    expect(workflow, contains('expected_commit:'));
    expect(workflow, contains('release_notes_from_commit:'));
    expect(workflow, contains('release_notes_candidate_b64:'));
    expect(workflow, contains('release_notes_candidate_sha256:'));
    expect(
      workflow,
      contains(
        "notes \${{ inputs.release_notes_candidate_sha256 || 'fallback' }}",
      ),
    );
    expect(workflow, contains('environment: Production'));
    expect(workflow, contains('cancel-in-progress: false'));
    expect(workflow, contains(r'if: ${{ inputs.publish_release == true }}'));
    expect(workflow, contains('contents: read'));
    expect(workflow, isNot(contains('contents: write')));
    expect(
        workflow, contains('uses: ./.github/workflows/erp-integrity-gate.yml'));
    expect(workflow, contains('ANDROID_RELEASE_KEYSTORE_BASE64'));
    expect(workflow, contains('ANDROID_RELEASE_STORE_PASSWORD'));
    expect(workflow, contains('ANDROID_RELEASE_KEY_PASSWORD'));
    expect(workflow, contains('ANDROID_RELEASE_KEY_ALIAS'));
    expect(workflow, contains('SUPABASE_RELEASE_SECRET'));
    for (final secret in <String>[
      r'${{ secrets.ANDROID_RELEASE_KEYSTORE_BASE64 }}',
      r'${{ secrets.ANDROID_RELEASE_STORE_PASSWORD }}',
      r'${{ secrets.ANDROID_RELEASE_KEY_PASSWORD }}',
      r'${{ secrets.ANDROID_RELEASE_KEY_ALIAS }}',
      r'${{ secrets.SUPABASE_RELEASE_SECRET }}',
    ]) {
      expect(workflow.indexOf(secret), greaterThan(productionBoundary));
    }
    expect(workflow, contains('generate_release_notes.mjs'));
    expect(workflow, contains('CODEX_RELEASE_NOTES_CANDIDATE_B64='));
    expect(workflow, contains("CODEX_CANDIDATE_B64=''"));
    expect(
      workflow.indexOf("CODEX_CANDIDATE_B64=''"),
      lessThan(workflow.indexOf('generate_release_notes.mjs')),
    );
    expect(
      compactWorkflow,
      contains(r'if [[ "$EXPECTED_COMMIT" != "$GITHUB_SHA" ]]'),
    );
    expect(
      workflow,
      contains('name: vinabike-erp-android-release-evidence'),
    );
    expect(workflow, contains('/android-release-manifest.json'));
    expect(workflow, contains('retention-days: 30'));
  });

  test('Linux CI Android publisher is monotonic retry-safe and exact', () {
    final publisher = File(
      'scripts/android/publish_direct_release.sh',
    ).readAsStringSync();
    final compactPublisher = normalized(publisher);

    expect(publisher, contains('--ci-exact-sha'));
    expect(publisher, isNot(contains('--prepared-state')));
    expect(
      compactPublisher,
      contains(r'"$(git rev-parse HEAD)" != "$CI_EXACT_SHA"'),
    );
    expect(
      publisher,
      contains('VERSION_CODE=\$((LATEST_ANDROID_VERSION_CODE + 1))'),
    );
    expect(publisher, contains('prepare_ci_version'));
    expect(publisher, contains('validate_complete_release_manifest'));
    expect(publisher, contains('write_release_evidence'));
    expect(publisher, contains('--argjson release_notes'));
    expect(
        publisher, contains('.release_notes.to_commit == \$expected_commit'));
    expect(publisher, contains('remote_object_matches_file'));
    expect(
      compactPublisher,
      contains(
        r'''(.statusCode | tostring) == "404" and .error == "not_found"''',
      ),
    );
    expect(
      publisher,
      contains('Reusing the verified immutable Android version manifest.'),
    );
    expect(publisher, contains('.release_notes == \$release_notes'));
    expect(publisher, contains('.apk_parts == \$apk_parts'));
    expect(
      compactPublisher,
      isNot(
        contains(
          'for required in awk base64 cat curl date dd find git head jq keytool mktemp perl rm security',
        ),
      ),
    );
  });
}
