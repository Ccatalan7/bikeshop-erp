import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String workflow;
  late String integrityWorkflow;
  late String publishHelper;
  late String releaseBaseResolver;
  late String distributionRunbook;

  setUpAll(() {
    workflow = File('.github/workflows/windows-release.yml').readAsStringSync();
    integrityWorkflow =
        File('.github/workflows/erp-integrity-gate.yml').readAsStringSync();
    publishHelper =
        File('scripts/publish_windows_update.ps1').readAsStringSync();
    releaseBaseResolver = File(
      'scripts/releases/resolve_previous_release_commit.sh',
    ).readAsStringSync();
    distributionRunbook =
        File('docs/WINDOWS_DESKTOP_DISTRIBUTION.md').readAsStringSync();
  });

  test('manual Windows dispatch fails safe as artifact-only by default', () {
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
    expect(workflow, contains('permissions:\n  contents: read'));
    expect(
      workflow,
      contains(
        "if: \${{ github.event_name == 'workflow_dispatch' && inputs.publish_release == true }}",
      ),
    );

    final publishJob = workflow.indexOf('\n  publish:');
    final artifactUpload = workflow.indexOf('actions/upload-artifact@v4');
    final releaseMutation = workflow.indexOf('gh release create');
    final releaseUpload = workflow.indexOf('gh release upload');
    expect(publishJob, greaterThan(artifactUpload));
    expect(releaseMutation, greaterThan(publishJob));
    expect(releaseUpload, greaterThan(publishJob));
    expect(
      workflow.substring(0, publishJob),
      isNot(contains('gh release ')),
    );
    expect(RegExp(r'environment: Production').allMatches(workflow).length, 1);
    expect(RegExp(r'contents: write').allMatches(workflow).length, 1);
  });

  test('Windows artifacts are built from and identify the exact run SHA', () {
    expect(workflow, contains('ref: \${{ github.sha }}'));
    expect(integrityWorkflow, contains('ref: \${{ github.sha }}'));
    expect(workflow, contains('windows-release-manifest.json'));
    expect(workflow, contains('commit = \$env:GITHUB_SHA'));
    expect(workflow, contains('sha256sum --check'));
    expect(workflow, contains('--target "\$GITHUB_SHA"'));
    expect(workflow, contains('npm run build:spreadsheet-engine'));
    expect(
      workflow,
      contains(
        r'data\flutter_assets\web\spreadsheet_engine\univer.bundle.js',
      ),
    );
    expect(workflow, contains('tag_name = \$env:RELEASE_TAG'));
    expect(workflow, contains('installer_sha256 = \$installerHash'));
  });

  test('protected publish binds release notes to the selected Windows release',
      () {
    final publishJob = workflow.indexOf('\n  publish:');
    final checkout = workflow.indexOf(
      'Check out release verification material',
      publishJob,
    );
    final geminiReleaseNotesSecret = workflow.indexOf(
      r'GEMINI_RELEASE_API_KEY: ${{ secrets.GEMINI_RELEASE_API_KEY }}',
    );
    final openAiReleaseNotesSecret = workflow.indexOf(
      r'OPENAI_API_KEY: ${{ secrets.OPENAI_API_KEY }}',
    );
    final baseResolution = workflow.indexOf(
      'resolve_previous_release_commit.sh',
      checkout,
    );
    final generation = workflow.indexOf(
      'generate_release_notes.mjs',
      baseResolution,
    );
    final merge = workflow.indexOf(
      "jq -s '.[0] * .[1]'",
      generation,
    );
    final releaseUpload = workflow.indexOf('gh release upload', merge);

    expect(publishJob, greaterThanOrEqualTo(0));
    expect(checkout, greaterThan(publishJob));
    expect(
      workflow.substring(checkout, baseResolution),
      allOf(
        contains(r'ref: ${{ github.sha }}'),
        contains('fetch-depth: 0'),
      ),
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
    );
    expect(RegExp(r'secrets\.OPENAI_API_KEY').allMatches(workflow).length, 1);
    expect(generation, greaterThan(baseResolution));
    expect(
      workflow.substring(generation, merge),
      allOf(
        contains('--from-commit "\$base_commit"'),
        contains('--to-commit "\$GITHUB_SHA"'),
        contains('--output dist/release-notes.json'),
      ),
    );
    expect(merge, greaterThan(generation));
    expect(releaseUpload, greaterThan(merge));
    expect(workflow, contains('.release_notes.to_commit == \$head'));
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
    expect(distributionRunbook, contains('GEMINI_RELEASE_API_KEY'));
    expect(distributionRunbook, contains('gemini-3.1-flash-lite'));
    expect(distributionRunbook, contains('OPENAI_API_KEY'));
    expect(distributionRunbook, contains('deterministic fallback'));
    expect(distributionRunbook, contains('human reviewers'));
  });

  test('release-note baseline ignores a current-SHA retry', () {
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
  });

  test('release publication binds GitHub CLI to the repository explicitly', () {
    expect(workflow, contains('GH_REPO: \${{ github.repository }}'));
    expect(
      workflow,
      contains('gh release view "\$RELEASE_TAG" --repo "\$GH_REPO"'),
    );
    expect(
      RegExp(r'--repo "\$GH_REPO"').allMatches(workflow).length,
      greaterThanOrEqualTo(3),
    );
  });

  test('developer publish helper opts into the guarded publish run', () {
    expect(publishHelper, contains('publish_release = \$true'));
    expect(publishHelper, contains('ConvertTo-Json -Compress'));
    expect(publishHelper, contains('--json'));
    expect(publishHelper, contains('\$expectedRunTitle'));
    expect(publishHelper, contains('\$candidateTitle -ne \$ExpectedTitle'));
  });

  test('CI validates the Windows bundle without contacting production', () {
    expect(
      workflow,
      contains('Validate Windows runtime bundle without launching it'),
    );
    expect(workflow, contains("'vinabike_erp.exe'"));
    expect(workflow, contains("'flutter_windows.dll'"));
    expect(workflow.toLowerCase(), isNot(contains('start-process')));
    expect(
      distributionRunbook,
      contains('initializes the production Supabase fallback'),
    );
  });
}
