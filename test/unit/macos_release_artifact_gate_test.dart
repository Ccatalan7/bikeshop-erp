import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String workflow;
  late String integrityWorkflow;
  late String installer;
  late String updaterService;
  late String publishHelper;
  late String codexReleaseNotesHelper;
  late String releaseNotesGenerator;
  late String flutterTestGate;
  late String releaseBaseResolver;
  late String runbook;
  late String infoPlist;
  late String releaseEntitlements;

  setUpAll(() {
    workflow = File('.github/workflows/macos-release.yml').readAsStringSync();
    integrityWorkflow =
        File('.github/workflows/erp-integrity-gate.yml').readAsStringSync();
    installer =
        File('scripts/install_vinabike_erp_macos.sh').readAsStringSync();
    updaterService = File(
      'lib/shared/services/desktop_update_service_io.dart',
    ).readAsStringSync();
    publishHelper = File('scripts/publish_macos_update.sh').readAsStringSync();
    codexReleaseNotesHelper = File(
      'scripts/releases/generate_codex_release_notes.mjs',
    ).readAsStringSync();
    releaseNotesGenerator = File(
      'scripts/releases/generate_release_notes.mjs',
    ).readAsStringSync();
    flutterTestGate =
        File('scripts/run_flutter_test_gate.sh').readAsStringSync();
    releaseBaseResolver = File(
      'scripts/releases/resolve_previous_release_commit.sh',
    ).readAsStringSync();
    runbook = File('docs/MACOS_DESKTOP_DISTRIBUTION.md').readAsStringSync();
    infoPlist = File('macos/Runner/Info.plist').readAsStringSync();
    releaseEntitlements =
        File('macos/Runner/Release.entitlements').readAsStringSync();
  });

  test('manual macOS dispatch fails safe as artifact-only by default', () {
    expect(
      workflow,
      contains(RegExp(
        r'publish_release:\s*\n'
        r'\s+description:.*\n'
        r'\s+required: true\s*\n'
        r'\s+type: boolean\s*\n'
        r'\s+default: false',
      )),
    );
    for (final inputName in const [
      'expected_commit',
      'release_notes_candidate_b64',
    ]) {
      expect(
        workflow,
        contains(
          RegExp(
            '$inputName:\\s*\\n'
            '\\s+description:.*\\n'
            '\\s+required: false\\s*\\n'
            '\\s+type: string\\s*\\n'
            '\\s+default: (?:\'\'|"")',
          ),
        ),
        reason: '$inputName must remain an optional empty dispatch input.',
      );
    }
    expect(
        workflow, contains('permissions:\n  actions: read\n  contents: read'));
    expect(
      workflow,
      contains(
        "if: \${{ always() && !cancelled() && "
        "needs.build.result == 'success' && "
        "github.event_name == 'workflow_dispatch' && "
        "inputs.release_target != 'android' && "
        "inputs.publish_release == true }}",
      ),
    );

    final publishJob = workflow.indexOf('\n  publish:');
    final artifactUpload = workflow.indexOf('actions/upload-artifact@v4');
    final releaseMutation = workflow.indexOf('gh release create');
    final signingSecret = workflow.indexOf('MACOS_UPDATE_SIGNING_KEY');
    final signingCommand = workflow.indexOf('ssh-keygen -Y sign');
    expect(publishJob, greaterThan(artifactUpload));
    expect(releaseMutation, greaterThan(publishJob));
    expect(signingSecret, greaterThan(publishJob));
    expect(signingCommand, greaterThan(publishJob));
    expect(workflow.substring(0, publishJob), isNot(contains('gh release ')));
    expect(RegExp(r'environment: Production').allMatches(workflow).length, 1);
    expect(RegExp(r'contents: write').allMatches(workflow).length, 1);
  });

  test('macOS artifact is bound to exact source and signed metadata', () {
    expect(workflow, contains('ref: \${{ github.sha }}'));
    expect(workflow, contains('--dart-define=VINABIKE_BUILD_TAG'));
    expect(workflow, contains('ssh-keygen -Y sign'));
    expect(workflow, contains('ssh-keygen -Y verify'));
    expect(workflow, contains('MACOS_UPDATE_SIGNING_KEY'));
    expect(workflow, contains('archive_sha256'));
    expect(workflow, contains('--target "\$GITHUB_SHA"'));
    expect(workflow, contains('macos-latest'));
    expect(
      workflow,
      contains(
        'com.apple.security.temporary-exception.files.home-relative-path.read-write:0',
      ),
    );
  });

  test('protected publish binds release notes before signing the manifest', () {
    final publishJob = workflow.indexOf('\n  publish:');
    final geminiReleaseNotesSecret = workflow.indexOf(
      r'GEMINI_RELEASE_API_KEY: ${{ secrets.GEMINI_RELEASE_API_KEY }}',
    );
    final openAiReleaseNotesSecret = workflow.indexOf(
      r'OPENAI_API_KEY: ${{ secrets.OPENAI_API_KEY }}',
    );
    final sourceGuardJob = workflow.indexOf('\n  source-guard:');
    final expectedCommitInput = workflow.indexOf(
      r'${{ inputs.expected_commit }}',
      sourceGuardJob,
    );
    final codexCandidateInput = workflow.indexOf(
      r'${{ inputs.release_notes_candidate_b64 }}',
      publishJob,
    );
    final baseResolution = workflow.indexOf(
      'resolve_previous_release_commit.sh',
      publishJob,
    );
    final generation = workflow.indexOf(
      'generate_release_notes.mjs',
      baseResolution,
    );
    final merge = workflow.indexOf(
      "jq -s '.[0] * .[1]'",
      generation,
    );
    final signing = workflow.indexOf('ssh-keygen -Y sign', merge);

    expect(publishJob, greaterThanOrEqualTo(0));
    expect(sourceGuardJob, greaterThanOrEqualTo(0));
    expect(expectedCommitInput, greaterThan(sourceGuardJob));
    expect(expectedCommitInput, lessThan(publishJob));
    expect(codexCandidateInput, greaterThan(publishJob));
    expect(
      workflow.substring(sourceGuardJob, publishJob),
      allOf(
        contains('EXPECTED_COMMIT'),
        contains('GITHUB_SHA'),
      ),
      reason:
          'The workflow must bind an explicit publish request to its exact source SHA.',
    );
    expect(
      workflow.substring(publishJob, baseResolution),
      contains('CODEX_RELEASE_NOTES_CANDIDATE_B64'),
      reason:
          'Only protected publication may receive the optional local notes.',
    );
    expect(
      workflow.substring(0, publishJob),
      isNot(contains('CODEX_RELEASE_NOTES_CANDIDATE_B64')),
      reason:
          'The local Codex payload must only enter the protected publish job.',
    );
    expect(geminiReleaseNotesSecret, greaterThan(publishJob));
    expect(openAiReleaseNotesSecret, greaterThan(geminiReleaseNotesSecret));
    expect(
      workflow,
      contains(
        r"GEMINI_RELEASE_NOTES_MODEL: ${{ vars.GEMINI_RELEASE_NOTES_MODEL || 'gemini-3.1-flash-lite' }}",
      ),
    );
    expect(
      RegExp(r'secrets\.GEMINI_RELEASE_API_KEY').allMatches(workflow).length,
      1,
      reason:
          'The Gemini key must only be exposed inside protected publication.',
    );
    expect(
      RegExp(r'secrets\.OPENAI_API_KEY').allMatches(workflow).length,
      1,
      reason:
          'The compatibility OpenAI key must stay inside protected publication.',
    );
    expect(baseResolution, greaterThan(publishJob));
    expect(generation, greaterThan(baseResolution));
    expect(
      releaseNotesGenerator,
      contains('CODEX_RELEASE_NOTES_CANDIDATE_B64'),
      reason:
          'The generator must consume and revalidate the transported candidate.',
    );
    final codexCandidateDecode = releaseNotesGenerator.indexOf(
      'decodeCodexReleaseEnvelopeBase64(',
    );
    final generationFunction = releaseNotesGenerator.indexOf(
      'export async function generateReleaseNotes',
    );
    final codexCandidateValidation = releaseNotesGenerator.indexOf(
      'acceptCodexReleaseEnvelope(',
      generationFunction,
    );
    final remoteProviderSelection = releaseNotesGenerator.indexOf(
      'const provider =',
      generationFunction,
    );
    expect(codexCandidateDecode, greaterThanOrEqualTo(0));
    expect(generationFunction, greaterThanOrEqualTo(0));
    expect(codexCandidateValidation, greaterThan(generationFunction));
    expect(remoteProviderSelection, greaterThan(codexCandidateValidation));
    expect(
      workflow.substring(generation, merge),
      allOf(
        contains('--from-commit "\$base_commit"'),
        contains('--to-commit "\$GITHUB_SHA"'),
        contains('--output dist/release-notes.json'),
      ),
    );
    expect(merge, greaterThan(generation));
    expect(signing, greaterThan(merge));
    expect(
      workflow,
      contains('.release_notes.to_commit == \$head'),
    );
    expect(workflow, contains("jq -r '.release_notes.summary'"));
    final normalizedWorkflow = workflow.replaceAll(RegExp(r'\s+'), ' ');
    expect(
      normalizedWorkflow,
      contains(
        'gh release edit "\$RELEASE_TAG" \\ --repo "\$GH_REPO" '
        '\\ --target "\$GITHUB_SHA"',
      ),
      reason: 'A retry must refresh both assets and their release notes.',
    );
    expect(runbook, contains('GEMINI_RELEASE_API_KEY'));
    expect(runbook, contains('gemini-3.1-flash-lite'));
    expect(runbook, contains('OPENAI_API_KEY'));
    expect(runbook, contains('deterministic fallback'));
    expect(runbook, contains('human reviewers'));
    final normalizedRunbook = runbook.replaceAll(RegExp(r'\s+'), ' ');
    expect(
      normalizedRunbook,
      matches(
        RegExp(
          r'Codex.*Gemini.*deterministic fallback',
          caseSensitive: false,
        ),
      ),
      reason:
          'The documented provider order must remain Codex, Gemini, then fallback.',
    );
    expect(
      normalizedRunbook,
      allOf(
        contains('source-inspection boundary'),
        contains('source and diffs'),
        contains('OpenAI'),
        contains('sanitized'),
      ),
      reason:
          'The runbook must explain the distinct local-Codex and sanitized-CI privacy boundaries.',
    );
  });

  test('release-note baseline skips same-SHA retries and stays ancestral', () {
    expect(
      releaseBaseResolver,
      contains(r'[[ "$candidate_commit" == "$HEAD_COMMIT" ]]'),
    );
    expect(
      releaseBaseResolver,
      contains(r'[[ "$candidate_commit" != "$release_target" ]]'),
    );
    expect(
      releaseBaseResolver,
      contains(
        'git merge-base --is-ancestor "\$candidate_commit" "\$HEAD_COMMIT"',
      ),
    );
    expect(
      releaseBaseResolver,
      contains(r'fallback_commit="$(git rev-parse "${HEAD_COMMIT}^"'),
    );
  });

  test('CI owns the complete release integrity gate', () {
    final npmBuild = integrityWorkflow.indexOf(
      'npm run build:spreadsheet-engine',
    );
    final flutterBuild = integrityWorkflow.indexOf('flutter build web');
    expect(npmBuild, greaterThanOrEqualTo(0));
    expect(flutterBuild, greaterThan(npmBuild));
    expect(
      integrityWorkflow,
      contains('Verify packaged spreadsheet assets are committed'),
    );
    expect(integrityWorkflow, contains('git diff --exit-code --'));
    expect(
      integrityWorkflow,
      contains('bash scripts/run_flutter_test_gate.sh flutter'),
    );
    expect(
      integrityWorkflow,
      contains(
        'workflow_call:\n'
        '    inputs:\n'
        '      expected_commit:\n'
        '        required: false',
      ),
    );
    expect(
      integrityWorkflow,
      contains("if: \${{ inputs.expected_commit != '' }}"),
    );
    expect(
      integrityWorkflow,
      isNot(contains("github.event_name == 'workflow_dispatch'")),
    );
    expect(workflow, contains('npm run build:spreadsheet-engine'));

    final integrityJob = workflow.indexOf('\n  integrity:');
    final sourceGuardJob = workflow.indexOf('\n  source-guard:');
    final qualificationJob = workflow.indexOf('\n  qualification:');
    final buildJob = workflow.indexOf('\n  build:');
    final buildNeedsSourceGuard = workflow.indexOf(
      '- source-guard',
      buildJob,
    );
    final buildNeedsIntegrity = workflow.indexOf(
      '- integrity',
      buildJob,
    );
    final buildNeedsQualification = workflow.indexOf(
      '- qualification',
      buildJob,
    );
    final publishJob = workflow.indexOf('\n  publish:');
    final publishNeedsBuild = workflow.indexOf('needs: build', publishJob);
    expect(sourceGuardJob, greaterThanOrEqualTo(0));
    expect(integrityJob, greaterThanOrEqualTo(0));
    expect(qualificationJob, greaterThan(integrityJob));
    expect(buildJob, greaterThan(qualificationJob));
    expect(buildNeedsSourceGuard, greaterThan(buildJob));
    expect(buildNeedsIntegrity, greaterThan(buildJob));
    expect(buildNeedsQualification, greaterThan(buildNeedsIntegrity));
    expect(
      workflow.substring(buildJob, buildNeedsSourceGuard),
      allOf(
        contains('always()'),
        contains('!cancelled()'),
        contains("inputs.integrity_run_id == ''"),
        contains("inputs.integrity_run_id != ''"),
      ),
    );
    expect(publishJob, greaterThan(buildNeedsIntegrity));
    expect(publishNeedsBuild, greaterThan(publishJob));
  });

  test('installer keeps Gatekeeper enabled and verifies a narrow target', () {
    expect(installer, contains('ssh-keygen -Y verify'));
    expect(installer, contains('/usr/bin/shasum -a 256'));
    expect(installer, contains('codesign --verify --deep --strict'));
    expect(
        installer, contains("EXPECTED_BUNDLE_ID='com.vinabike.vinabikeErp'"));
    expect(
        installer, contains('xattr -dr com.apple.quarantine "\$prepared_app"'));
    expect(installer, isNot(contains('spctl --master-disable')));
    expect(installer, isNot(contains('sudo')));
    expect(installer, isNot(contains('xattr -cr /')));
    expect(installer, contains('Vinabike ERP.previous.app'));
    expect(installer, contains('reject_downgrade'));
    expect(installer, contains('prune_stale_prepared_releases'));
    expect(installer, contains("prune_stale_prepared_releases ''"));
    expect(installer, contains('rotate_log_if_large'));
    expect(installer, contains("APPLY_ATTEMPTED='YES'"));
    expect(
      installer,
      contains(r'rm -f "$PREPARE_REQUEST" "$APPLY_REQUEST"'),
    );
    expect(
      installer.indexOf(r'write_release_state "$CURRENT_STATE" "$TAG_NAME"'),
      lessThan(installer.indexOf('if ! launch_installed_app; then')),
    );
    expect(
      installer,
      contains(
        r'write_release_state "$CURRENT_STATE" "$previous_current_tag"',
      ),
    );
  });

  test('installer atomically persists only signature-verified manifests', () {
    expect(
      installer,
      contains(
        'PREPARED_MANIFEST="\${COORDINATION_ROOT}/prepared-manifest.json"',
      ),
    );
    expect(
      installer,
      contains(
        'CURRENT_MANIFEST="\${COORDINATION_ROOT}/current-manifest.json"',
      ),
    );

    final signatureVerification = installer.indexOf('ssh-keygen -Y verify');
    final prepareFunction = installer.indexOf('prepare_latest_release()');
    final preparedManifest = installer.indexOf(
      'persist_verified_manifest "\$PREPARED_MANIFEST"',
      prepareFunction,
    );
    final preparedState = installer.indexOf(
      'write_release_state "\$PREPARED_STATE" "\$TAG_NAME"',
      preparedManifest,
    );
    expect(signatureVerification, greaterThanOrEqualTo(0));
    expect(preparedManifest, greaterThan(prepareFunction));
    expect(preparedManifest, greaterThan(signatureVerification));
    expect(preparedState, greaterThan(preparedManifest));

    final atomicCopy = installer.indexOf('write_file_atomically()');
    final atomicMove = installer.indexOf(
      'mv -f "\$temporary" "\$destination"',
      atomicCopy,
    );
    expect(atomicCopy, greaterThanOrEqualTo(0));
    expect(atomicMove, greaterThan(atomicCopy));
    expect(
      installer,
      contains(
        'write_file_atomically "\$previous_current_manifest" "\$CURRENT_MANIFEST"',
      ),
      reason: 'A failed launch must restore the prior trusted manifest.',
    );
  });

  test('macOS app coordinates with a per-user background updater', () {
    expect(
      updaterService,
      contains('(Platform.isWindows || Platform.isMacOS)'),
    );
    expect(updaterService, contains('prepare-request.json'));
    expect(updaterService, contains('apply-request.json'));
    expect(updaterService, contains('prepared-release.json'));
    expect(
      updaterService,
      contains('_clearMacosPreparationFailureForRetry'),
    );
    expect(updaterService, contains("errorTag != 'unknown'"));
    expect(updaterService, contains("'VinabikeERP'"));
    expect(updaterService, contains("'coordination'"));
    final macosFetchStart =
        updaterService.indexOf('_fetchLatestMacosRelease() async');
    final macosFetchEnd = updaterService.indexOf(
      '_readInstalledReleaseTag() async',
      macosFetchStart,
    );
    final macosFetchSource =
        updaterService.substring(macosFetchStart, macosFetchEnd);
    expect(
      updaterService,
      contains('releases/download/macos-latest/'),
    );
    expect(macosFetchSource, contains('_macosLatestManifestUrl'));
    expect(macosFetchSource, isNot(contains('api.github.com')));
    expect(macosFetchSource, contains('archive_sha256'));
    expect(macosFetchSource, contains('installer_sha256'));
    expect(installer, contains('<key>WatchPaths</key>'));
    expect(installer, contains(r'${USER_HOME}/Applications'));
    expect(installer, contains(r'${SUPPORT_ROOT}/coordination'));
    expect(
      releaseEntitlements,
      contains(
        'com.apple.security.temporary-exception.files.home-relative-path.read-write',
      ),
    );
    expect(
      releaseEntitlements,
      contains('/Library/Application Support/VinabikeERP/'),
    );
    expect(infoPlist, contains('<string>Viñabike ERP</string>'));
  });

  test('developer helper publishes current authorized branch without switching',
      () {
    expect(publishHelper, contains('release_target: "macos"'));
    expect(publishHelper, contains('publish_release: "true"'));
    expect(publishHelper, contains('--json'));
    expect(publishHelper, contains('git branch --show-current'));
    expect(publishHelper, contains('git push origin "\$branch"'));
    expect(
      publishHelper,
      contains('Existing macOS release build found for current commit'),
    );
    expect(publishHelper, contains('\$expected_run_title'));
    expect(
      publishHelper,
      contains('(.display_title // "") == \$expected_title'),
      reason:
          'The helper must bind to the exact source and note inputs, not any run.',
    );
    expect(publishHelper, isNot(contains('git checkout')));
    expect(publishHelper, isNot(contains('git switch')));
    expect(runbook, contains('smartpegas1.0'));
    final normalizedRunbook = runbook.replaceAll(RegExp(r'\s+'), ' ');
    expect(
      normalizedRunbook,
      contains('same low-friction operating model as the Windows publisher'),
    );
    expect(runbook, isNot(contains('--preflight-only')));
    expect(runbook, isNot(contains('intentionally stricter than the Windows')));
  });

  test('registered macOS entrypoint routes Android without sharing publishers',
      () {
    expect(
      workflow,
      contains(
        "if: \${{ github.event_name == 'workflow_dispatch' && "
        "inputs.release_target == 'android' }}",
      ),
    );
    expect(workflow, contains('uses: ./.github/workflows/android-release.yml'));
    expect(workflow, contains('secrets: inherit'));
    expect(
      workflow,
      contains(
        "if: \${{ inputs.release_target != 'android' }}\n"
        '    name: Verify requested source commit',
      ),
    );
  });

  test('developer helper follows the Windows-like CI publication sequence', () {
    final stage = publishHelper.indexOf('git add -A');
    final commit = publishHelper.indexOf('git commit -m', stage);
    final codexCandidate = publishHelper.indexOf(
      'prepare_local_codex_release_notes "\$head_sha"',
      commit,
    );
    final push = publishHelper.indexOf('git push origin', commit);
    final activeRunLookup = publishHelper.indexOf('active_run="\$(', push);
    final dispatch = publishHelper.indexOf('gh workflow run', activeRunLookup);
    final wait = publishHelper.indexOf('gh run view "\$run_id"', dispatch);
    final diagnostics = publishHelper.indexOf(
      'show_workflow_failure_diagnostics "\$run_id"',
      wait,
    );
    final releaseVerification = publishHelper.indexOf(
      'verify_published_release "\$head_sha" "\$run_id"',
      diagnostics,
    );

    expect(stage, greaterThanOrEqualTo(0));
    expect(commit, greaterThan(stage));
    expect(codexCandidate, greaterThan(commit));
    expect(codexCandidate, lessThan(push));
    expect(push, greaterThan(commit));
    expect(activeRunLookup, greaterThan(push));
    expect(dispatch, greaterThan(activeRunLookup));
    expect(wait, greaterThan(dispatch));
    expect(diagnostics, greaterThan(wait));
    expect(releaseVerification, greaterThan(diagnostics));
    expect(
      publishHelper,
      contains('scripts/releases/generate_codex_release_notes.mjs'),
    );
    expect(
      publishHelper.substring(activeRunLookup, dispatch),
      allOf(
        contains('expected_commit'),
        contains('release_notes_candidate_b64'),
      ),
      reason:
          'The dispatch payload must carry both exact-head and optional-note bindings.',
    );
    expect(
      publishHelper.substring(dispatch),
      contains('--json'),
      reason:
          'The bounded candidate must be dispatched as JSON on stdin, not shell flags.',
    );

    expect(publishHelper, contains('require_command git'));
    expect(publishHelper, contains('require_command gh'));
    expect(publishHelper, contains('require_command jq'));
    expect(publishHelper, isNot(contains('require_command volta')));
    expect(publishHelper, isNot(contains('require_command node')));
    expect(publishHelper, isNot(contains('require_command codex')));
    expect(publishHelper, isNot(contains('require_command gitleaks')));
    expect(publishHelper, isNot(contains('require_command npm')));
    expect(publishHelper, isNot(contains('npm ci')));
    expect(publishHelper, isNot(contains('flutter analyze')));
    expect(publishHelper, isNot(contains('run_flutter_test_gate.sh')));
    expect(publishHelper, isNot(contains('flutter build')));
    expect(publishHelper, isNot(contains('git archive')));
    expect(publishHelper, isNot(contains('--preflight-only')));
  });

  test('local Codex release-note attempt is read-only and optional', () {
    expect(codexReleaseNotesHelper, contains('--ephemeral'));
    expect(codexReleaseNotesHelper, contains('read-only'));
    expect(codexReleaseNotesHelper, contains('--output-schema'));
    expect(
      codexReleaseNotesHelper,
      anyOf(contains('--output-last-message'), contains('"-o"')),
    );
    expect(
      codexReleaseNotesHelper,
      isNot(contains('--dangerously-bypass-approvals-and-sandbox')),
    );
    expect(
      publishHelper,
      anyOf(
        contains('Codex release notes unavailable'),
        contains('Local Codex notes unavailable'),
        contains('Continuing without local Codex release notes'),
        contains('continuing without local Codex release notes'),
      ),
      reason:
          'Codex authentication, quota, or output failure must not block publication.',
    );
  });

  test('developer helper verifies exact run and release evidence', () {
    expect(
      publishHelper,
      contains('repos/\${REPO}/releases/tags/macos-latest'),
    );
    expect(publishHelper, contains('.commit == \$sha'));
    expect(
      publishHelper,
      contains('(.run_id | tostring) == \$run_id'),
    );
    expect(publishHelper, contains('.archive_name == \$archive'));
    expect(publishHelper, contains('.target_commitish'));
    expect(publishHelper, contains('"\${archive_name}.sha256"'));
    expect(publishHelper, contains('macos-latest is missing'));
    expect(
      publishHelper,
      contains('macos-latest does not identify the completed workflow'),
    );
  });

  test('Flutter gate reports the exact failed test without noisy source dumps',
      () {
    expect(flutterTestGate, contains('test --machine'));
    expect(flutterTestGate, contains('Flutter tests failed. Exact failure'));
    expect(flutterTestGate, contains('FAILED:'));
    expect(flutterTestGate, contains('.type == "print"'));
    expect(
      flutterTestGate,
      contains('EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK'),
    );
    expect(flutterTestGate, contains('.testID | tostring'));
    expect(flutterTestGate, contains('.[0:1200]'));
    expect(flutterTestGate, contains('Nothing was published.'));
    expect(
      integrityWorkflow,
      contains('bash scripts/run_flutter_test_gate.sh flutter'),
    );
    expect(publishHelper, contains('Failed job:'));
    expect(publishHelper, contains('Failed step:'));
    expect(publishHelper, contains('--log-failed'));
    expect(publishHelper, contains('tail -n 300'));
    expect(publishHelper, contains('[line truncated]'));
    expect(
      publishHelper,
      contains(r'/actions/runs/${run_id}/jobs'),
    );
    expect(
      publishHelper,
      contains('[flutter-test-gate\\] Flutter tests failed'),
    );
    expect(
      publishHelper,
      contains('[flutter-test-gate\\] Nothing was published'),
    );
    final jobsApiFallback = publishHelper.indexOf(
      'Could not load job/annotation diagnostics',
    );
    final failedLogFallback = publishHelper.indexOf(
      'Failed step log:',
      jobsApiFallback,
    );
    expect(jobsApiFallback, greaterThanOrEqualTo(0));
    expect(failedLogFallback, greaterThan(jobsApiFallback));
    expect(
      publishHelper.indexOf('Failure summary:', failedLogFallback),
      greaterThan(failedLogFallback),
    );
    expect(
      publishHelper,
      contains('Source commit \$head_sha remains pushed'),
    );
  });
}
