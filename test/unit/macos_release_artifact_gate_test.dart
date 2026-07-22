import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String workflow;
  late String integrityWorkflow;
  late String installer;
  late String updaterService;
  late String publishHelper;
  late String flutterTestGate;
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
    flutterTestGate =
        File('scripts/run_flutter_test_gate.sh').readAsStringSync();
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

  test('all clean builds generate the packaged spreadsheet engine', () {
    final npmBuild = integrityWorkflow.indexOf(
      'npm run build:spreadsheet-engine',
    );
    final flutterBuild = integrityWorkflow.indexOf('flutter build web');
    expect(npmBuild, greaterThanOrEqualTo(0));
    expect(flutterBuild, greaterThan(npmBuild));
    expect(workflow, contains('npm run build:spreadsheet-engine'));
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
    expect(publishHelper, contains('-f publish_release=true'));
    expect(publishHelper, contains('git branch --show-current'));
    expect(publishHelper, contains('git push origin "\$branch"'));
    expect(publishHelper, isNot(contains('git checkout')));
    expect(publishHelper, isNot(contains('git switch')));
    expect(runbook, contains('smartpegas1.0'));
  });

  test('developer helper verifies the exact local snapshot before publication',
      () {
    final stage = publishHelper.indexOf('git add -A');
    final writeSnapshot = publishHelper.indexOf(
      'snapshot_tree="\$(git write-tree)"',
      stage,
    );
    final createTemporaryDirectory = publishHelper.indexOf(
      'snapshot_root="\$(mktemp -d',
      writeSnapshot,
    );
    final exportSnapshot = publishHelper.indexOf(
      'git archive "\$snapshot_tree" | tar -x -C "\$snapshot_root"',
      createTemporaryDirectory,
    );
    final npmInstall = publishHelper.indexOf('npm ci', exportSnapshot);
    final spreadsheetBuild = publishHelper.indexOf(
      'npm run build:spreadsheet-engine',
      npmInstall,
    );
    final flutterDependencies = publishHelper.indexOf(
      '"\$flutter_bin" pub get',
      spreadsheetBuild,
    );
    final analyzer = publishHelper.indexOf(
      '"\$flutter_bin" analyze --no-fatal-infos --no-fatal-warnings lib test',
      flutterDependencies,
    );
    final tests = publishHelper.indexOf(
      'bash scripts/run_flutter_test_gate.sh "\$flutter_bin"',
      analyzer,
    );
    final webBuild = publishHelper.indexOf(
      '"\$flutter_bin" build web --release --no-wasm-dry-run',
      tests,
    );
    final readCurrentIndex = publishHelper.indexOf(
      'current_index_tree="\$(git write-tree)"',
      webBuild,
    );
    final snapshotGuard = publishHelper.indexOf(
      'if [[ "\$current_index_tree" != "\$snapshot_tree" ]]',
      readCurrentIndex,
    );
    final cleanup = publishHelper.indexOf('cleanup_snapshot', snapshotGuard);
    final commit = publishHelper.indexOf('git commit -m', cleanup);
    final push = publishHelper.indexOf('git push origin', commit);
    final dispatch = publishHelper.indexOf('gh workflow run', push);

    expect(stage, greaterThanOrEqualTo(0));
    expect(writeSnapshot, greaterThan(stage));
    expect(createTemporaryDirectory, greaterThan(writeSnapshot));
    expect(exportSnapshot, greaterThan(createTemporaryDirectory));
    expect(npmInstall, greaterThan(exportSnapshot));
    expect(spreadsheetBuild, greaterThan(npmInstall));
    expect(flutterDependencies, greaterThan(spreadsheetBuild));
    expect(analyzer, greaterThan(flutterDependencies));
    expect(tests, greaterThan(analyzer));
    expect(webBuild, greaterThan(tests));
    expect(readCurrentIndex, greaterThan(webBuild));
    expect(snapshotGuard, greaterThan(readCurrentIndex));
    expect(cleanup, greaterThan(snapshotGuard));
    expect(commit, greaterThan(snapshotGuard));
    expect(push, greaterThan(commit));
    expect(dispatch, greaterThan(push));
    expect(publishHelper, isNot(contains('if ! git diff --quiet')));
    expect(
      publishHelper,
      isNot(contains('git ls-files --others --exclude-standard')),
    );
    expect(
      publishHelper,
      contains('"\$repo_root/.fvm/flutter_sdk/bin/flutter"'),
    );
  });

  test('Flutter gate reports the exact failed test without noisy source dumps',
      () {
    expect(flutterTestGate, contains('test --machine'));
    expect(flutterTestGate, contains('Flutter tests failed. Exact failure'));
    expect(flutterTestGate, contains('FAILED:'));
    expect(flutterTestGate, contains('split("\\n  Actual:")[0]'));
    expect(flutterTestGate, contains('Nothing was published.'));
    expect(integrityWorkflow,
        contains('bash scripts/run_flutter_test_gate.sh flutter'));
    expect(publishHelper, contains('--preflight-only'));
  });
}
