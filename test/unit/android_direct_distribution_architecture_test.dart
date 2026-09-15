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
    expect(
      publisher,
      contains('--dart-define=AI_AGENT_GATEWAY_ENABLED=true'),
    );
    expect(
      publisher,
      contains(
        '--dart-define=SUPABASE_PUBLISHABLE_KEY="\$SUPABASE_PUBLISHABLE_KEY"',
      ),
    );
    expect(
      publisher,
      contains('Vinabike ERP Supabase publishable key'),
    );
    expect(publisher, contains('app-arm64-v8a-release.apk'));
    expect(publisher, contains('ANDROID_ARM64_VERSION_CODE_OFFSET=2000'));
    expect(publisher, contains(r'"$AAPT" dump badging "$APK_PATH"'));
    expect(
      normalized(publisher),
      contains(r'APK_VERSION_CODE != EXPECTED_APK_VERSION_CODE'),
    );
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
    expect(workflow, contains('integrity_run_id:'));
    expect(workflow, contains('integrity_run_attempt:'));
    expect(
      workflow,
      contains(
        "notes \${{ inputs.release_notes_candidate_sha256 || 'gemini' }}",
      ),
    );
    expect(workflow, contains('environment: Production'));
    expect(workflow, contains('cancel-in-progress: false'));
    expect(workflow, contains('always() && !cancelled()'));
    expect(workflow, contains("inputs.integrity_run_id == ''"));
    expect(workflow, contains("inputs.integrity_run_id != ''"));
    expect(workflow, contains('needs.integrity.result'));
    // La exigencia del gate NO puede vivir en `needs` de este job: `needs` es
    // una espera, y nombrar ahí a `qualification` hacía que la compilación
    // arrancara recién cuando el gate terminaba (medido el 2026-08-07: 18 min
    // 29 s contra los 13 min 58 s de macOS en la misma publicación). Vive en
    // una fase propia del publicador que espera al run en vuelo después del
    // build local y justo antes de la primera escritura remota.
    final publishJob = workflow.indexOf('\n  publish:');
    final publishNeeds = workflow.indexOf('needs:', publishJob);
    final publishSteps = workflow.indexOf('steps:', publishJob);
    expect(
      workflow.substring(publishJob, publishSteps),
      isNot(contains('- qualification')),
    );
    expect(
      workflow.substring(publishJob, publishNeeds),
      isNot(contains('needs.qualification.result')),
    );
    final signedUpload = workflow.indexOf(
      'Build, sign, qualify, upload, and verify the Android release',
      publishSteps,
    );
    expect(signedUpload, greaterThan(publishSteps));
    expect(workflow, contains("--wait-seconds '2400'"));
    expect(workflow, contains('verify_integrity_qualification.mjs'));
    expect(workflow, contains('VINABIKE_ANDROID_INTEGRITY_RUN_ID:'));
    expect(workflow, contains('VINABIKE_ANDROID_INTEGRITY_RUN_ATTEMPT:'));
    expect(workflow, contains('VINABIKE_ANDROID_INTEGRITY_RESULT:'));
    expect(workflow, contains('actions: read'));
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
      r'${{ secrets.SUPABASE_PUBLISHABLE_KEY }}',
    ]) {
      expect(workflow.indexOf(secret), greaterThan(productionBoundary));
    }
    expect(workflow, contains('generate_release_notes.mjs'));
    expect(
      compactWorkflow,
      contains(
        r'git merge-base --is-ancestor "$notes_base" "$android_commit"',
      ),
    );
    expect(
      workflow,
      contains('VINABIKE_ANDROID_RELEASE_NOTES_FROM_COMMIT:'),
    );
    expect(
      workflow,
      contains(
        r'GEMINI_RELEASE_API_KEY: ${{ secrets.GEMINI_RELEASE_API_KEY }}',
      ),
    );
    expect(
      workflow,
      contains(
        r"GEMINI_RELEASE_NOTES_MODEL: ${{ vars.GEMINI_RELEASE_NOTES_MODEL || 'gemini-3.1-flash-lite' }}",
      ),
    );
    expect(workflow, isNot(contains('CODEX_RELEASE_NOTES_CANDIDATE_B64')));
    expect(workflow, isNot(contains('OPENAI_API_KEY')));
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
    expect(publisher, contains('VINABIKE_ANDROID_RELEASE_NOTES_FROM_COMMIT'));
    expect(
      publisher,
      contains('.release_notes.from_commit == \$expected_from_commit'),
    );
    expect(publisher, isNot(contains('--prepared-state')));
    expect(
      compactPublisher,
      contains(r'"$(git rev-parse HEAD)" != "$CI_EXACT_SHA"'),
    );
    expect(
      publisher,
      contains('VERSION_CODE=\$((LATEST_ANDROID_BUILD_NUMBER + 1))'),
    );
    expect(
      publisher,
      contains(r'(.build_number // .version_code) | floor'),
    );
    expect(
      normalized(publisher),
      contains(
        r'if has("build_number") then .version_code else (.version_code + 2000) end | floor',
      ),
    );
    expect(
      publisher,
      contains(r'and .version_code == (.build_number + 2000)'),
    );
    final build = publisher.indexOf(r'"${FLUTTER_COMMAND[@]}" build apk');
    final integrityGate = publisher.lastIndexOf(
      'require_integrity_qualification_before_publication',
    );
    final firstRemoteMutation = publisher.indexOf(
      r'for part_array_index in "${!APK_PART_FILES[@]}"',
    );
    expect(build, greaterThanOrEqualTo(0));
    expect(integrityGate, greaterThan(build));
    expect(firstRemoteMutation, greaterThan(integrityGate));
    expect(
      publisher.substring(build, integrityGate),
      contains('APKSIGNER_OUTPUT'),
      reason: 'The signed APK must be verified before waiting on integrity.',
    );
    expect(
      publisher.substring(integrityGate, firstRemoteMutation),
      isNot(contains('upload_object ')),
      reason: 'No storage mutation may occur before the exact-SHA gate.',
    );
    expect(publisher, contains('--argjson build_number "\$VERSION_CODE"'));
    expect(publisher, contains('--argjson version_code "\$APK_VERSION_CODE"'));
    expect(publisher, contains('.build_number == \$build_number'));
    expect(publisher, contains('.version_code == \$version_code'));
    expect(publisher, contains('download_latest_android_manifest'));
    expect(publisher, contains('/storage/v1/object/sign/\${BUCKET}/'));
    expect(
      publisher,
      contains(r"""jq -er '.signedURL | select(type == "string")'"""),
    );
    expect(
      publisher,
      contains(r'signed_url="${SUPABASE_URL}/storage/v1${signed_path}"'),
    );
    expect(
      publisher,
      contains("Cache-Control: no-cache, no-store, max-age=0"),
    );
    expect(publisher, contains('for readback_delay in 0 1 2 4 8 12'));
    expect(
      publisher,
      contains(
        'The mutable Android manifest did not converge to the published release.',
      ),
    );
    expect(
      compactPublisher,
      contains(
        r'APK_VERSION_CODE <= LATEST_ANDROID_INSTALLED_VERSION_CODE',
      ),
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
    expect(publisher, contains(r'local cache_control="${5:-3600}"'));
    expect(
      publisher,
      contains(r'-H "Cache-Control: ${cache_control}"'),
    );
    expect(
      publisher,
      contains(
        r'''upload_object \
  "$LATEST_MANIFEST_PATH" \
  "$MANIFEST_PATH" \
  "application/json" \
  "true" \
  "0"''',
      ),
    );
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
