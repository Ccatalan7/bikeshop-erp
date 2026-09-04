import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<Map<String, dynamic>> tasks;
  late String prepareHelper;
  late String stateHelper;
  late String macosPublisher;
  late String androidPublisher;
  late String androidWorkflowPublisher;
  late String qualifier;
  late String qualificationVerifier;
  late String pairedNotesBaseResolver;
  late String macosWorkflow;
  late String androidWorkflow;

  setUpAll(() {
    final tasksDocument =
        jsonDecode(File('.vscode/tasks.json').readAsStringSync())
            as Map<String, dynamic>;
    tasks =
        (tasksDocument['tasks'] as List<dynamic>).cast<Map<String, dynamic>>();
    prepareHelper =
        File('scripts/releases/prepare_erp_update.sh').readAsStringSync();
    stateHelper =
        File('scripts/releases/erp_update_state.sh').readAsStringSync();
    macosPublisher = File('scripts/publish_macos_update.sh').readAsStringSync();
    androidPublisher =
        File('scripts/android/publish_direct_release.sh').readAsStringSync();
    androidWorkflowPublisher = File(
      'scripts/releases/publish_android_workflow.mjs',
    ).readAsStringSync();
    qualifier =
        File('scripts/releases/qualify_erp_update.mjs').readAsStringSync();
    qualificationVerifier = File(
      'scripts/releases/verify_integrity_qualification.mjs',
    ).readAsStringSync();
    pairedNotesBaseResolver = File(
      'scripts/releases/resolve_paired_release_notes_base.mjs',
    ).readAsStringSync();
    macosWorkflow =
        File('.github/workflows/macos-release.yml').readAsStringSync();
    androidWorkflow =
        File('.github/workflows/android-release.yml').readAsStringSync();
  });

  Map<String, dynamic> task(String label) => tasks.singleWhere(
        (candidate) => candidate['label'] == label,
      );

  test('one visible ERP task prepares once then starts both platforms', () {
    final topLevel = task('🚀 Publish ERP Update (macOS + Android)');
    final platformGroup = task('🚀 Publish Prepared ERP Platforms');
    final macos = task('🍎 Publish Prepared ERP Update (macOS)');
    final android = task('🤖 Publish Prepared ERP Update (Android)');

    expect(
      (topLevel['osx'] as Map<String, dynamic>)['group'],
      <String, dynamic>{'kind': 'build', 'isDefault': true},
    );
    expect(topLevel['dependsOrder'], 'sequence');
    expect(
      topLevel['dependsOn'],
      <String>[
        '🔒 Prepare ERP Update (shared commit)',
        '✅ Qualify ERP Update (exact SHA)',
        '🚀 Publish Prepared ERP Platforms',
      ],
    );
    final qualification = task('✅ Qualify ERP Update (exact SHA)');
    expect(
      qualification['command'],
      'node scripts/releases/qualify_erp_update.mjs --prepared-state auto --dispatch-only',
    );
    expect(qualification['hide'], isTrue);
    expect(
      (qualification['runOptions'] as Map<String, dynamic>)['instanceLimit'],
      1,
    );
    expect(platformGroup['dependsOrder'], 'parallel');
    expect(
      platformGroup['dependsOn'],
      <String>[
        '🍎 Publish Prepared ERP Update (macOS)',
        '🤖 Publish Prepared ERP Update (Android)',
      ],
    );

    expect(
      macos['command'],
      'bash scripts/publish_macos_update.sh --prepared-state auto',
    );
    expect(
      android['command'],
      'node scripts/releases/publish_android_workflow.mjs '
      '--prepared-state auto',
    );
    expect(macos['hide'], isTrue);
    expect(android['hide'], isTrue);

    final macosPresentation = macos['presentation'] as Map<String, dynamic>;
    final androidPresentation = android['presentation'] as Map<String, dynamic>;
    expect(macosPresentation['panel'], 'dedicated');
    expect(androidPresentation['panel'], 'dedicated');
    expect(macosPresentation['group'], 'erp-update-platforms');
    expect(androidPresentation['group'], 'erp-update-platforms');
  });

  test('shared preparation owns the only commit and push', () {
    final fetch = prepareHelper.indexOf('git fetch --quiet');
    final fastForward = prepareHelper.indexOf('git merge --ff-only');
    final dependencies = prepareHelper.indexOf('flutter pub get');
    final stage = prepareHelper.indexOf('git add -A');
    final commit = prepareHelper.indexOf('git commit -m');
    final notes =
        prepareHelper.indexOf('prepare_shared_release_notes "\$head_sha"');
    final push = prepareHelper.indexOf('git push origin');
    final liveRemoteVerification =
        prepareHelper.indexOf('git ls-remote --heads origin', push);
    final stateWrite = prepareHelper.indexOf('schema_version: 2', push);

    expect(fetch, greaterThanOrEqualTo(0));
    expect(fastForward, greaterThan(fetch));
    expect(dependencies, greaterThan(fastForward));
    expect(stage, greaterThan(dependencies));
    expect(commit, greaterThan(stage));
    expect(notes, greaterThan(commit));
    expect(push, greaterThan(notes));
    expect(liveRemoteVerification, greaterThan(push));
    expect(stateWrite, greaterThan(liveRemoteVerification));
    expect(RegExp(r'git commit -m').allMatches(prepareHelper), hasLength(1));
    expect(RegExp(r'git push origin').allMatches(prepareHelper), hasLength(1));
    expect(prepareHelper, contains('chmod 600'));
    expect(
      prepareHelper,
      contains('VINABIKE_ERP_RELEASE_BRANCH:-smartpegas1.0'),
    );
    expect(
      prepareHelper,
      contains('current_head" != "\$canonical_remote_head'),
    );
    expect(
      prepareHelper,
      contains('git switch "\$CANONICAL_RELEASE_BRANCH"'),
    );
    expect(prepareHelper, contains('--check-release-branch)'));
    expect(
      prepareHelper,
      contains("\$CHECK_RELEASE_BRANCH_ONLY\" == 'YES'"),
    );
    expect(prepareHelper, contains('targets: ["macos", "android"]'));
    expect(prepareHelper, contains('release_notes_from_commit'));
    expect(prepareHelper, contains('release_notes_candidate_b64'));
    expect(prepareHelper, contains('release_notes_candidate_sha256'));
    expect(
      prepareHelper,
      contains('resolve_paired_release_notes_base.mjs'),
    );
    expect(
      pairedNotesBaseResolver,
      contains('vinabike-erp-android-release-evidence'),
    );
    expect(
      pairedNotesBaseResolver,
      contains('chooseCommonReleaseNotesBase'),
    );
    expect(
      prepareHelper,
      contains(
        'Gemini Flash will generate the shared release notes inside protected CI.',
      ),
    );
    expect(prepareHelper, contains("release_notes_candidate_b64=''"));
    expect(prepareHelper, contains("release_notes_candidate_sha256=''"));
    expect(prepareHelper, isNot(contains('--notes-candidate')));
    expect(prepareHelper, isNot(contains('generate_codex_release_notes.mjs')));
    expect(
        prepareHelper.toLowerCase(), isNot(contains('require_command codex')));
    expect(prepareHelper, isNot(contains('SIGNING_PASSWORD')));
    expect(prepareHelper, isNot(contains('SUPABASE_RELEASE_SECRET')));
  });

  test('prepared state is exact-SHA, short-lived, clean, and remote-bound', () {
    expect(stateHelper, contains('ERP_UPDATE_STATE_MAX_AGE_SECONDS=21600'));
    expect(stateHelper, contains('test("^[0-9a-f]{40}\$")'));
    expect(stateHelper, contains('git status --porcelain'));
    expect(stateHelper, contains('git ls-remote'));
    expect(stateHelper, contains('.schema_version == 3'));
    expect(stateHelper, contains('refs/heads/\$ERP_UPDATE_STATE_BRANCH'));
    expect(stateHelper, contains('actual_head'));
    expect(stateHelper, contains('ERP_UPDATE_STATE_HEAD_SHA'));
    expect(
      stateHelper,
      contains('ERP_UPDATE_STATE_RELEASE_NOTES_FROM_COMMIT'),
    );
    expect(stateHelper, contains('failed its SHA256 binding'));
    expect(stateHelper, contains('git merge-base --is-ancestor'));
    expect(stateHelper, contains('must stay inside the current Git directory'));
    expect(stateHelper, contains('.qualification.workflow_id'));
    expect(stateHelper, contains('.qualification.run_id'));
    expect(stateHelper, contains('.qualification.run_attempt'));
    expect(stateHelper, contains('.qualification.head_sha == .head_sha'));
    expect(stateHelper, contains('.qualification.branch == .branch'));
  });

  test('one exact-SHA qualifier reuses, dispatches, and binds live proof', () {
    expect(qualifier, contains('discoveryTimeoutMs = 60_000'));
    expect(qualifier, contains('chooseExactQualificationRun'));
    expect(qualifier, contains('workflowName === "ERP Integrity Gate"'));
    expect(qualifier, contains('expected_commit: prepared.state.head_sha'));
    expect(qualifier, contains('schema_version: 3'));
    expect(qualifier, contains('workflow_path: INTEGRITY_WORKFLOW_PATH'));
    expect(qualifier, contains('workflow_id: liveRun.workflow_id'));
    expect(qualifier, contains('run_attempt: liveRun.run_attempt'));
    expect(qualifier, contains('head_sha: liveRun.head_sha'));
    expect(qualifier, contains('branch: liveRun.head_branch'));
    expect(qualifier, contains('Fix that exact failure before publishing'));
    expect(qualificationVerifier, contains('run.path !== workflowPath'));
    expect(qualificationVerifier, contains('run.head_sha !== headSha'));
    expect(qualificationVerifier, contains('run.head_branch !== branch'));
    expect(qualificationVerifier, contains('run.conclusion !== "success"'));
  });

  test('platform prepared modes retain independent publication paths', () {
    expect(macosPublisher, contains('--check-release-branch'));
    expect(macosPublisher, contains('--prepared-state'));
    expect(
      macosPublisher,
      contains('erp_update_load_state "\$PREPARED_STATE_REQUEST" macos'),
    );
    expect(macosPublisher, contains('erp_update_assert_prepared_source'));
    expect(
      macosPublisher,
      contains('This macOS commit is already published'),
    );
    expect(macosPublisher, contains('gh workflow run'));

    expect(
      androidWorkflowPublisher,
      contains('state.schema_version !== 3'),
    );
    expect(
      androidWorkflowPublisher,
      contains('state.targets.includes("android")'),
    );
    expect(androidWorkflowPublisher, contains('assertPreparedSource(state)'));
    expect(androidWorkflowPublisher, contains('dispatchWorkflow(state, run)'));
    expect(
      androidWorkflowPublisher,
      contains('const WORKFLOW = "macos-release.yml"'),
    );
    expect(androidWorkflowPublisher, contains('release_target: "android"'));
    expect(
      androidWorkflowPublisher,
      contains('integrity_run_id: state.integrityRunId'),
    );
    expect(macosPublisher, contains('integrity_run_id: \$integrity_run_id'));
    expect(
      androidWorkflowPublisher,
      contains('run?.displayTitle === expectedAndroidRunTitle(state)'),
    );
    expect(
      androidWorkflowPublisher,
      contains('vinabike-erp-android-release-evidence'),
    );
    expect(
      androidWorkflowPublisher,
      contains('validateAndroidManifest'),
    );
    expect(
      androidWorkflowPublisher,
      contains('state.releaseNotesFromCommit'),
    );
    expect(
      androidWorkflow,
      contains('if (.release_notes | type) == "object" then'),
      reason: 'a legacy plain-text manifest must fail closed cleanly instead '
          'of crashing jq while resolving a same-commit retry',
    );
    for (final workflow in [macosWorkflow, androidWorkflow]) {
      expect(workflow, contains('actions: read'));
      expect(workflow, contains('integrity_run_id:'));
      expect(workflow, contains('integrity_run_attempt:'));
      expect(workflow, contains('verify_integrity_qualification.mjs'));
      expect(workflow, contains("inputs.integrity_run_id == ''"));
      expect(workflow, contains("inputs.integrity_run_id != ''"));
      expect(workflow, contains('always() && !cancelled()'));
    }
  });

  test('macOS accepts only a shared baseline that covers its own range', () {
    final publishJob = macosWorkflow.indexOf('\n  publish:');
    final androidRoute = macosWorkflow.indexOf('\n  android:', publishJob);
    final protectedPublish = macosWorkflow.substring(publishJob, androidRoute);

    expect(protectedPublish, contains('authoritative_base_commit'));
    expect(
      protectedPublish,
      contains(
        'git merge-base --is-ancestor \\\n'
        '                "\$RELEASE_NOTES_FROM_COMMIT" \\\n'
        '                "\$authoritative_base_commit"',
      ),
    );
    expect(
      protectedPublish,
      contains('base_commit="\$RELEASE_NOTES_FROM_COMMIT"'),
    );
    expect(
      protectedPublish,
      isNot(
        contains(
          '"\$RELEASE_NOTES_FROM_COMMIT" != "\$base_commit"',
        ),
      ),
    );
  });

  test('standalone platform tasks remain selectable', () {
    expect(
      task('🍎 Publish macOS Update (all changes)')['command'],
      'bash scripts/publish_macos_update.sh',
    );
    expect(macosPublisher, contains('git add -A'));
    expect(macosPublisher, contains('git commit -m "\$MESSAGE"'));
    expect(macosPublisher, contains('git push origin "\$branch"'));
    expect(
      androidPublisher,
      contains(
          'expected_confirmation="publish-\${VERSION_NAME}+\${VERSION_CODE}"'),
    );
    expect(androidPublisher, contains('/storage/v1/upload/resumable'));
  });
}
