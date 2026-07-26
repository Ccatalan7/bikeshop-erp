import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<Map<String, dynamic>> tasks;
  late String preparation;
  late String windowsPublisher;
  late String runbook;

  setUpAll(() {
    final tasksDocument =
        jsonDecode(File('.vscode/tasks.json').readAsStringSync())
            as Map<String, dynamic>;
    tasks =
        (tasksDocument['tasks'] as List<dynamic>).cast<Map<String, dynamic>>();
    preparation = File(
      'scripts/releases/prepare_windows_android_update.ps1',
    ).readAsStringSync();
    windowsPublisher =
        File('scripts/publish_windows_update.ps1').readAsStringSync();
    runbook = File('docs/WINDOWS_DESKTOP_DISTRIBUTION.md').readAsStringSync();
  });

  Map<String, dynamic> task(String label) => tasks.singleWhere(
        (candidate) => candidate['label'] == label,
      );

  test('Windows exposes one preparation followed by parallel publishers', () {
    final topLevel = task('🚀 Publish ERP Update (Windows + Android)');
    final platformGroup =
        task('🚀 Publish Prepared Windows + Android Platforms');
    final windows = task('🪟 Publish Prepared ERP Update (Windows)');
    final android = task('🤖 Publish Prepared ERP Update (Android CI)');

    expect(topLevel['dependsOrder'], 'sequence');
    expect(
      topLevel['dependsOn'],
      <String>[
        '🔒 Prepare Windows + Android ERP Update',
        '🚀 Publish Prepared Windows + Android Platforms',
      ],
    );
    expect(platformGroup['dependsOrder'], 'parallel');
    expect(
      platformGroup['dependsOn'],
      <String>[
        '🪟 Publish Prepared ERP Update (Windows)',
        '🤖 Publish Prepared ERP Update (Android CI)',
      ],
    );
    expect(
      windows['command'],
      contains(
        'scripts/publish_windows_update.ps1 -PreparedState '
        '.git/vinabike-windows-android-publish-state.json',
      ),
    );
    expect(
      android['command'],
      'node scripts/releases/publish_android_workflow.mjs '
      '--prepared-state '
      '.git/vinabike-windows-android-publish-state.json',
    );

    final windowsPresentation = windows['presentation'] as Map<String, dynamic>;
    final androidPresentation = android['presentation'] as Map<String, dynamic>;
    expect(windowsPresentation['panel'], 'dedicated');
    expect(androidPresentation['panel'], 'dedicated');
    expect(windowsPresentation['group'], 'erp-update-windows-android');
    expect(androidPresentation['group'], 'erp-update-windows-android');
  });

  test('Windows preparation owns one exact source commit and push', () {
    final branchCheck = preparation.indexOf('-CheckReleaseBranch');
    final fetch = preparation.indexOf('git fetch');
    final fastForward = preparation.indexOf('git merge --ff-only');
    final dependencies = preparation.indexOf(
      'Invoke-FlutterDependencyNormalization -RepositoryRoot',
      fastForward,
    );
    final stage = preparation.indexOf('git add -A');
    final commit = preparation.indexOf('git commit -m');
    final codex = preparation.indexOf('Get-LocalCodexCandidate', commit);
    final push = preparation.indexOf('git push origin');
    final remoteReadback = preparation.indexOf('git ls-remote', push);
    final stateWrite = preparation.indexOf('schema_version = 2', push);

    expect(branchCheck, greaterThanOrEqualTo(0));
    expect(fetch, greaterThan(branchCheck));
    expect(fastForward, greaterThan(fetch));
    expect(dependencies, greaterThan(fastForward));
    expect(stage, greaterThan(dependencies));
    expect(commit, greaterThan(stage));
    expect(codex, greaterThan(commit));
    expect(push, greaterThan(codex));
    expect(remoteReadback, greaterThan(push));
    expect(stateWrite, greaterThan(remoteReadback));
    expect(RegExp(r'git commit -m').allMatches(preparation), hasLength(1));
    expect(RegExp(r'git push origin').allMatches(preparation), hasLength(1));
    expect(
      preparation,
      contains('git push origin "\${headSha}:refs/heads/\$branch"'),
    );
    expect(preparation, contains("targets = @('windows', 'android')"));
    expect(preparation, contains('candidate_sha256 = \$candidateSha256'));
    expect(preparation, contains('Get-ReusableCodexCandidate'));
    expect(
      preparation,
      contains('Reusing the exact Codex candidate already bound'),
    );
    expect(preparation, contains('--git-bin \$git.Source |'));
    expect(preparation, contains('Out-Host'));
    expect(preparation, contains('Protect-PrivateStateFile'));
    expect(preparation, contains('SetAccessRuleProtection(\$true, \$false)'));
    expect(preparation, isNot(contains('ANDROID_SIGNING')));
    expect(preparation, isNot(contains('SUPABASE_SERVICE_ROLE')));
  });

  test('prepared Windows publisher revalidates the bounded handoff', () {
    expect(windowsPublisher, contains('[string]\$PreparedState'));
    expect(windowsPublisher, contains('[switch]\$CheckReleaseBranch'));
    expect(windowsPublisher, contains('\$schemaVersion -ne 2'));
    expect(windowsPublisher, contains("\$targets -notcontains 'windows'"));
    expect(windowsPublisher, contains('\$stateAge -gt 21600'));
    expect(
      windowsPublisher,
      contains('must stay inside the current Git directory'),
    );
    expect(windowsPublisher, contains('FileAttributes]::ReparsePoint'));
    expect(windowsPublisher, contains('Get-Sha256Hex -Bytes \$candidateBytes'));
    expect(windowsPublisher, contains('git status --porcelain'));
    expect(windowsPublisher, contains('git merge-base --is-ancestor'));
    expect(windowsPublisher, contains('git ls-remote'));
    expect(
      RegExp('Assert-PreparedErpUpdateSource')
          .allMatches(windowsPublisher)
          .length,
      greaterThanOrEqualTo(3),
    );
    expect(
      windowsPublisher,
      contains(
        'Git staging, commit, and push are owned by the shared preparation step.',
      ),
    );
  });

  test('Windows dispatch carries exact source and shared Codex metadata', () {
    expect(
      windowsPublisher,
      contains('expected_commit = \$headSha'),
    );
    expect(
      windowsPublisher,
      contains('release_notes_from_commit = \$releaseNotesFromCommit'),
    );
    expect(
      windowsPublisher,
      contains(
        'release_notes_candidate_b64 = \$releaseNotesCandidateBase64',
      ),
    );
    expect(
      windowsPublisher,
      contains(
        'release_notes_candidate_sha256 = '
        '\$releaseNotesCandidateSha256',
      ),
    );
    expect(windowsPublisher, contains('publish_release = \$true'));
    expect(windowsPublisher, contains('ConvertTo-Json -Compress'));
    expect(windowsPublisher, contains('--json'));
    expect(
      preparation,
      allOf(
        contains('generate_codex_release_notes.mjs'),
        contains('--git-bin \$git.Source'),
        contains('--codex-bin \$codex.Source'),
      ),
    );
  });

  test('exact published Windows commit is an idempotent success', () {
    final exactReleaseLookup =
        windowsPublisher.indexOf('Find-PublishedWindowsReleaseForCommit');
    final dispatch = windowsPublisher.indexOf('gh workflow run');
    final finalVerification = windowsPublisher.lastIndexOf(
      'Find-PublishedWindowsReleaseForCommit',
    );

    expect(exactReleaseLookup, greaterThanOrEqualTo(0));
    expect(windowsPublisher, contains('windows-release-manifest.json'));
    expect(
      windowsPublisher,
      contains("(Get-ObjectProperty \$manifest 'commit') -ne \$HeadSha"),
    );
    expect(windowsPublisher, contains("'publish_requested') -ne \$true"));
    expect(
      windowsPublisher,
      contains('Windows release is already published'),
    );
    expect(windowsPublisher, contains('for (\$page = 1; \$page -le 20;'));
    expect(windowsPublisher, isNot(contains("'target_commitish') -eq")));
    expect(windowsPublisher, contains('\$zipAsset'));
    expect(windowsPublisher, contains('\$checksumAsset'));
    expect(windowsPublisher, contains('\$installerAsset'));
    expect(windowsPublisher, contains('\$expectedChecksum'));
    expect(dispatch, greaterThan(exactReleaseLookup));
    expect(finalVerification, greaterThan(dispatch));
  });

  test('GitHub policy and run lookup failures stop publication', () {
    expect(
      windowsPublisher,
      contains('Could not verify the GitHub Production environment policy.'),
    );
    expect(
      windowsPublisher,
      contains('Could not verify the Production custom branch policies.'),
    );
    expect(
      windowsPublisher,
      contains('The workflow-run API request failed.'),
    );
    expect(
      windowsPublisher,
      contains(
        'exact run could not be correlated within five minutes.',
      ),
    );
    expect(
      windowsPublisher,
      contains('\$candidateTitle -ne \$ExpectedTitle'),
    );
    expect(
      windowsPublisher,
      contains(
        '"Windows publish · \$headSha · notes \$notesTitleIdentity"',
      ),
    );
  });

  test('standalone Windows task remains available', () {
    expect(
      task('🚀 Publish Windows Update (all changes)')['command'],
      'powershell -NoProfile -ExecutionPolicy Bypass '
      '-File scripts/publish_windows_update.ps1',
    );
    expect(windowsPublisher,
        contains("Write-Step 'Staging all Source Control changes'"));
    expect(windowsPublisher, contains('git commit -m \$Message'));
    expect(windowsPublisher, contains('git push origin \$branch'));
  });

  test('runbook explains shared notes and separate safety boundaries', () {
    expect(
      runbook,
      contains('Publish ERP Update (Windows + Android)'),
    );
    expect(runbook, contains('at most one new commit'));
    expect(runbook, contains('Codex CLI once'));
    expect(runbook, contains('same validated Codex candidate'));
    expect(runbook, contains('separate GitHub Actions workflows'));
    expect(runbook, contains('first paired Android release'));
    expect(runbook, contains('deterministic fallback'));
  });
}
