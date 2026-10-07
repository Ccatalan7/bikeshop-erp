import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The ERP on the web runs without Flutter's offline service worker: it
/// cached parts of two builds together and the published ERP stopped at
/// start until its caches were cleared by hand (2026-10-07). Every build of
/// the ERP web leaves the worker out and puts the retiring one in its place,
/// so a browser that still has the old worker lets it go.
void main() {
  const retirement = 'scripts/erp_web/flutter_service_worker.js';
  const install =
      'cp scripts/erp_web/flutter_service_worker.js build/web_erp/flutter_service_worker.js';

  /// What publishes the ERP web: the live site, its previews, the manual
  /// deploy and `just build-erp`.
  const published = [
    '.github/workflows/firebase-hosting-merge.yml',
    '.github/workflows/firebase-hosting-preview.yml',
    'scripts/deploy.sh',
    'Justfile',
  ];

  /// Where the ERP web is built: the workflows, the scripts and the Justfile.
  List<File> buildSources() => [
        ...Directory('.github/workflows')
            .listSync()
            .whereType<File>()
            .where((file) => file.path.endsWith('.yml')),
        ...Directory('scripts')
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.sh')),
        File('Justfile'),
      ];

  /// Each `flutter build web` command in [source], with its continuation
  /// lines joined.
  Iterable<String> buildCommands(String source) sync* {
    final lines = source.split('\n');
    for (var i = 0; i < lines.length; i++) {
      if (!lines[i].contains('build web')) continue;
      final command = StringBuffer(lines[i]);
      while (lines[i].trimRight().endsWith(r'\') && i + 1 < lines.length) {
        i++;
        command.write(' ${lines[i].trim()}');
      }
      yield command.toString();
    }
  }

  test('every ERP web build leaves the offline worker out', () {
    final builds = <String>{};
    for (final file in buildSources()) {
      for (final command in buildCommands(file.readAsStringSync())) {
        if (!RegExp(r'-o\s+build/web_erp(\s|$)').hasMatch(command)) continue;
        builds.add(file.path);
        expect(
          command,
          contains('--pwa-strategy=none'),
          reason: '${file.path} builds the ERP web with the offline worker',
        );
      }
    }
    expect(builds, containsAll(published));
  });

  test('every published ERP web build puts the retiring worker in place', () {
    for (final path in published) {
      expect(
        File(path).readAsStringSync(),
        contains(install),
        reason: '$path publishes the ERP web without the retiring worker',
      );
    }
  });

  test('the retiring worker only empties Flutter caches and lets itself go',
      () {
    final worker = File(retirement).readAsStringSync();
    expect(worker, contains('self.skipWaiting()'));
    expect(worker, contains("name.startsWith('flutter-')"));
    expect(worker, contains('self.registration.unregister()'));
    // Without a fetch handler every request goes to the network; nothing
    // reloads the open page under the operator.
    expect(worker, isNot(contains("addEventListener('fetch'")));
    expect(worker, isNot(contains('.navigate(')));
    expect(worker, isNot(contains('location.reload')));
  });

  test('a page the old worker served retires it before the app starts', () {
    final index = File('web/index.html').readAsStringSync();
    final start =
        index.indexOf("var flutterWorker = '/flutter_service_worker.js'");
    expect(start, greaterThan(0), reason: 'web/index.html lost the retirement');
    // Before Flutter's bootstrap, and only for Flutter's worker: the
    // Firebase Messaging worker lives at its own scope and stays.
    expect(start, lessThan(index.indexOf('{{flutter_bootstrap_js}}')));
    final script = index.substring(start, index.indexOf('</script>', start));
    expect(script, contains('controller.scriptURL.indexOf(flutterWorker) < 0'));
    expect(script, contains('worker.scriptURL.indexOf(flutterWorker) >= 0'));
    expect(script, contains("name.indexOf('flutter-') === 0"));
    // Once per tab, so a worker that will not leave cannot loop the page.
    expect(script,
        contains("sessionStorage.getItem('vb-flutter-worker-retired')"));
  });
}
