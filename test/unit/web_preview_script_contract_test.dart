import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Future<int> _unusedLoopbackPort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

Future<String> _processStartStamp(int pid) async {
  final result = await Process.run(
    'ps',
    ['-p', '$pid', '-o', 'lstart='],
  );
  expect(result.exitCode, 0, reason: result.stderr.toString());
  return result.stdout.toString().trim();
}

String _releaseMarker({
  required String root,
  required int port,
  String target = 'store',
  String mode = 'release',
}) =>
    'vinabike-web-preview|root=$root|target=$target|mode=$mode|port=$port';

const _legacyReleaseMarker = 'vinabike-store-release-preview';

String _legacyReleaseBuildDirectory(String root) =>
    '$root/build/web_store_preview';

Future<Process> _startPythonFromStdin({
  required List<String> arguments,
  required String source,
}) async {
  final process = await Process.start('python3', ['-', ...arguments]);
  process.stdin.write(source);
  await process.stdin.close();
  final ready = await process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .first;
  expect(ready, 'ready');
  return process;
}

Future<Process> _startSlowReleaseListener({
  required int port,
  required String marker,
}) async {
  final process = await Process.start(
    'python3',
    [
      '-c',
      r'''
import signal
import socket
import sys
import time

listener = socket.socket()
listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
listener.bind(("127.0.0.1", int(sys.argv[1])))
listener.listen()

def stop(_signum, _frame):
    time.sleep(0.8)
    listener.close()
    raise SystemExit(0)

signal.signal(signal.SIGTERM, stop)
print("ready", flush=True)
while True:
    time.sleep(0.1)
''',
      '$port',
      marker,
    ],
  );
  final ready = await process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .first;
  expect(ready, 'ready');
  return process;
}

Future<Process> _startSlowLegacyReleaseListener({
  required String root,
  required int port,
}) =>
    _startPythonFromStdin(
      arguments: [
        _legacyReleaseBuildDirectory(root),
        '$port',
        _legacyReleaseMarker,
      ],
      source: r'''
import signal
import socket
import sys
import time

listener = socket.socket()
listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
listener.bind(("127.0.0.1", int(sys.argv[2])))
listener.listen()

def stop(_signum, _frame):
    time.sleep(0.8)
    listener.close()
    raise SystemExit(0)

signal.signal(signal.SIGTERM, stop)
print("ready", flush=True)
while True:
    time.sleep(0.1)
''',
    );

Future<Process> _startLegacyDecoy(List<String> arguments) =>
    _startPythonFromStdin(
      arguments: arguments,
      source: r'''
import time

print("ready", flush=True)
while True:
    time.sleep(0.1)
''',
    );

Future<void> _stopIfRunning(Process process) async {
  final alive = await Process.run('kill', ['-0', '${process.pid}']);
  if (alive.exitCode == 0) {
    process.kill();
  }
  await process.exitCode;
}

void main() {
  const scriptPath = 'scripts/dev/web_preview.sh';
  final source = File(scriptPath).readAsStringSync();

  test('preview scripts have valid shell syntax', () async {
    for (final path in [
      scriptPath,
      'scripts/dev/store_release_preview.sh',
    ]) {
      final result = await Process.run('bash', ['-n', path]);
      expect(
        result.exitCode,
        0,
        reason: '$path\n${result.stderr}',
      );
    }
  });

  test('release publication replaces an immutable-version symlink', () {
    expect(source, contains('BUILD_RELEASES_DIR='));
    expect(source, contains('os.replace(sys.argv[1], sys.argv[2])'));
    expect(source, isNot(contains('rm -rf -- "\$BUILD_DIR"')));
  });

  test('a failed rebuild keeps the last good release selected', () async {
    final sandbox = Directory.systemTemp.createTempSync(
      'web-preview-build-contract-',
    );
    final stateDirectory = Directory('${sandbox.path}/state');
    final fakeFlutter = File('${sandbox.path}/flutter');

    Future<ProcessResult> build() => Process.run(
          'bash',
          [scriptPath, 'build', '--store', '--release'],
          environment: {
            ...Platform.environment,
            'FLUTTER_BIN': fakeFlutter.path,
            'WEB_PREVIEW_BUILD_STATE_DIR': stateDirectory.path,
          },
        );

    try {
      fakeFlutter.writeAsStringSync(r'''#!/usr/bin/env bash
set -euo pipefail
output=""
while [ "$#" -gt 0 ]; do
  if [ "$1" = "-o" ]; then
    shift
    output="$1"
  fi
  shift
done
mkdir -p "$output"
printf '<html>good</html>\n' >"$output/index.html"
printf 'good bundle\n' >"$output/main.dart.js"
''');
      await Process.run('chmod', ['+x', fakeFlutter.path]);

      final first = await build();
      expect(first.exitCode, 0, reason: first.stderr.toString());
      final current = Link('${stateDirectory.path}/current');
      expect(current.existsSync(), isTrue);
      final firstTarget = current.resolveSymbolicLinksSync();
      expect(File('$firstTarget/main.dart.js').readAsStringSync(),
          'good bundle\n');

      fakeFlutter.writeAsStringSync('''#!/usr/bin/env bash
exit 42
''');
      final failed = await build();
      expect(failed.exitCode, isNot(0));
      expect(current.resolveSymbolicLinksSync(), firstTarget);
      expect(File('$firstTarget/main.dart.js').readAsStringSync(),
          'good bundle\n');
    } finally {
      sandbox.deleteSync(recursive: true);
    }
  });

  test('ERP release build uses its real entrypoint and isolated bundle',
      () async {
    final sandbox = Directory.systemTemp.createTempSync(
      'erp-web-preview-build-contract-',
    );
    final stateDirectory = Directory('${sandbox.path}/state');
    final fakeFlutter = File('${sandbox.path}/flutter');
    final argumentsFile = File('${sandbox.path}/arguments');

    try {
      fakeFlutter.writeAsStringSync(r'''#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" >"$WEB_PREVIEW_CAPTURE_ARGS"
output=""
while [ "$#" -gt 0 ]; do
  if [ "$1" = "-o" ]; then
    shift
    output="$1"
  fi
  shift
done
mkdir -p "$output"
printf '<html>erp</html>\n' >"$output/index.html"
printf 'erp bundle\n' >"$output/main.dart.js"
''');
      await Process.run('chmod', ['+x', fakeFlutter.path]);

      final result = await Process.run(
        'bash',
        [scriptPath, 'build', '--erp', '--release'],
        environment: {
          ...Platform.environment,
          'FLUTTER_BIN': fakeFlutter.path,
          'WEB_PREVIEW_BUILD_STATE_DIR': stateDirectory.path,
          'WEB_PREVIEW_CAPTURE_ARGS': argumentsFile.path,
        },
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      final arguments = argumentsFile.readAsLinesSync();
      expect(arguments, containsAllInOrder(['-t', 'lib/main.dart']));
      expect(arguments, isNot(contains('lib/main_store.dart')));
      final current = Link('${stateDirectory.path}/current');
      expect(current.existsSync(), isTrue);
      final selected = current.resolveSymbolicLinksSync();
      expect(
        File('$selected/main.dart.js').readAsStringSync(),
        'erp bundle\n',
      );
    } finally {
      sandbox.deleteSync(recursive: true);
    }
  });

  test('debug readiness has no blind client-boot sleep', () {
    expect(source, isNot(contains('BOOT_WAIT')));
    expect(
      source,
      contains('server-side readiness cannot observe that render'),
    );
  });

  test('release marker cleanup is scoped and never uses global pkill',
      () async {
    expect(source, isNot(contains('pkill -f')));
    expect(
      source,
      contains(
        r"'%s|root=%s|target=%s|mode=release|port=%s'",
      ),
    );

    final sandbox = Directory.systemTemp.createTempSync(
      'web-preview-marker-contract-',
    );
    final root = Directory.current.resolveSymbolicLinksSync();
    final port = await _unusedLoopbackPort();
    final decoys = <Process>[];
    try {
      for (final marker in [
        _releaseMarker(root: '$root-other', port: port),
        _releaseMarker(root: root, port: port + 1),
        _releaseMarker(root: root, port: port, mode: 'debug'),
      ]) {
        decoys.add(
          await Process.start(
            'python3',
            ['-c', 'import time; time.sleep(30)', marker],
          ),
        );
      }

      final result = await Process.run(
        'bash',
        [scriptPath, 'stop', '--store'],
        environment: {
          ...Platform.environment,
          'TMPDIR': sandbox.path,
          'STORE_WEB_PORT': '$port',
          'PORT_RELEASE_TIMEOUT': '2',
        },
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      for (final decoy in decoys) {
        final stillAlive = await Process.run('kill', ['-0', '${decoy.pid}']);
        expect(stillAlive.exitCode, 0);
      }
    } finally {
      for (final decoy in decoys) {
        await _stopIfRunning(decoy);
      }
      sandbox.deleteSync(recursive: true);
    }
  });

  test('legacy release cleanup signals only the exact current listener',
      () async {
    final sandbox = Directory.systemTemp.createTempSync(
      'web-preview-legacy-listener-contract-',
    );
    final root = Directory.current.resolveSymbolicLinksSync();
    final port = await _unusedLoopbackPort();
    final oldServer = await _startSlowLegacyReleaseListener(
      root: root,
      port: port,
    );
    try {
      final stopwatch = Stopwatch()..start();
      final result = await Process.run(
        'bash',
        [scriptPath, 'stop', '--store'],
        environment: {
          ...Platform.environment,
          'TMPDIR': sandbox.path,
          'STORE_WEB_PORT': '$port',
          'PORT_RELEASE_TIMEOUT': '5',
        },
      );
      stopwatch.stop();

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(
        stopwatch.elapsedMilliseconds,
        greaterThanOrEqualTo(700),
        reason: 'stop returned before the legacy listener finished TERM',
      );
      expect(result.stdout, contains('store preview port $port released'));
      expect(await oldServer.exitCode, 0);

      final replacement = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        port,
      );
      await replacement.close();
    } finally {
      await _stopIfRunning(oldServer);
      sandbox.deleteSync(recursive: true);
    }
  });

  test('legacy marker decoys are never discovered or signalled globally',
      () async {
    final sandbox = Directory.systemTemp.createTempSync(
      'web-preview-legacy-decoy-contract-',
    );
    final root = Directory.current.resolveSymbolicLinksSync();
    final port = await _unusedLoopbackPort();
    final otherPort = await _unusedLoopbackPort();
    final decoys = <Process>[
      await _startLegacyDecoy([_legacyReleaseMarker]),
      await _startLegacyDecoy([
        _legacyReleaseBuildDirectory('$root-other'),
        '$port',
        _legacyReleaseMarker,
      ]),
      await _startLegacyDecoy([
        _legacyReleaseBuildDirectory(root),
        '$port',
        _legacyReleaseMarker,
      ]),
      await _startSlowLegacyReleaseListener(
        root: root,
        port: otherPort,
      ),
    ];
    try {
      final result = await Process.run(
        'bash',
        [scriptPath, 'stop', '--store'],
        environment: {
          ...Platform.environment,
          'TMPDIR': sandbox.path,
          'STORE_WEB_PORT': '$port',
          'PORT_RELEASE_TIMEOUT': '2',
        },
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      for (final decoy in decoys) {
        final stillAlive = await Process.run('kill', ['-0', '${decoy.pid}']);
        expect(stillAlive.exitCode, 0, reason: 'decoy pid ${decoy.pid}');
      }
    } finally {
      for (final decoy in decoys) {
        await _stopIfRunning(decoy);
      }
      sandbox.deleteSync(recursive: true);
    }
  });

  test('legacy listener from another checkout is refused and left alive',
      () async {
    final sandbox = Directory.systemTemp.createTempSync(
      'web-preview-legacy-foreign-contract-',
    );
    final root = Directory.current.resolveSymbolicLinksSync();
    final port = await _unusedLoopbackPort();
    final foreignServer = await _startSlowLegacyReleaseListener(
      root: '$root-other',
      port: port,
    );
    try {
      final result = await Process.run(
        'bash',
        [scriptPath, 'stop', '--store'],
        environment: {
          ...Platform.environment,
          'TMPDIR': sandbox.path,
          'STORE_WEB_PORT': '$port',
          'PORT_RELEASE_TIMEOUT': '1',
        },
      );

      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('port $port did not become free'));
      final stillAlive = await Process.run(
        'kill',
        ['-0', '${foreignServer.pid}'],
      );
      expect(stillAlive.exitCode, 0);
    } finally {
      await _stopIfRunning(foreignServer);
      sandbox.deleteSync(recursive: true);
    }
  });

  test('stop reports success only after the listener releases the port',
      () async {
    final sandbox = Directory.systemTemp.createTempSync(
      'web-preview-stop-release-contract-',
    );
    final root = Directory.current.resolveSymbolicLinksSync();
    final port = await _unusedLoopbackPort();
    final oldServer = await _startSlowReleaseListener(
      port: port,
      marker: _releaseMarker(root: root, port: port),
    );
    try {
      final stopwatch = Stopwatch()..start();
      final result = await Process.run(
        'bash',
        [scriptPath, 'stop', '--store'],
        environment: {
          ...Platform.environment,
          'TMPDIR': sandbox.path,
          'STORE_WEB_PORT': '$port',
          'PORT_RELEASE_TIMEOUT': '5',
        },
      );
      stopwatch.stop();

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(
        stopwatch.elapsedMilliseconds,
        greaterThanOrEqualTo(700),
        reason: 'stop returned before the listener finished TERM',
      );
      expect(result.stdout, contains('store preview port $port released'));
      expect(await oldServer.exitCode, 0);

      final replacement = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        port,
      );
      await replacement.close();
    } finally {
      await _stopIfRunning(oldServer);
      sandbox.deleteSync(recursive: true);
    }
  });

  test('start waits for a legacy listener to release the port', () async {
    final sandbox = Directory.systemTemp.createTempSync(
      'web-preview-port-release-contract-',
    );
    final root = Directory.current.resolveSymbolicLinksSync();
    final port = await _unusedLoopbackPort();
    final stateDirectory = Directory('${sandbox.path}/state');
    final current = Directory('${stateDirectory.path}/current')
      ..createSync(recursive: true);
    File('${current.path}/index.html').writeAsStringSync('<html>ready</html>');
    File('${current.path}/main.dart.js').writeAsStringSync('new bundle\n');
    final oldServer = await _startSlowLegacyReleaseListener(
      root: root,
      port: port,
    );
    final environment = {
      ...Platform.environment,
      'TMPDIR': sandbox.path,
      'STORE_WEB_PORT': '$port',
      'WEB_PREVIEW_BUILD_STATE_DIR': stateDirectory.path,
      'PORT_RELEASE_TIMEOUT': '5',
      'READY_TIMEOUT': '5',
    };

    try {
      final stopwatch = Stopwatch()..start();
      final result = await Process.run(
        'bash',
        [scriptPath, 'start', '--store', '--release'],
        environment: environment,
      );
      stopwatch.stop();

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(
        stopwatch.elapsedMilliseconds,
        greaterThanOrEqualTo(700),
        reason: 'start returned before the old listener finished TERM',
      );
      expect(result.stdout, contains('server assets ready'));
      expect(await oldServer.exitCode, 0);

      final probe = await Process.run(
        'curl',
        ['-sf', 'http://127.0.0.1:$port/main.dart.js'],
      );
      expect(probe.exitCode, 0, reason: probe.stderr.toString());
      expect(probe.stdout, contains('new bundle'));
    } finally {
      await Process.run(
        'bash',
        [scriptPath, 'stop', '--store'],
        environment: environment,
      );
      await _stopIfRunning(oldServer);
      sandbox.deleteSync(recursive: true);
    }
  });

  test('ERP release start serves a prebuilt app and stops cleanly', () async {
    final sandbox = Directory.systemTemp.createTempSync(
      'erp-web-preview-start-contract-',
    );
    final port = await _unusedLoopbackPort();
    final stateDirectory = Directory('${sandbox.path}/state');
    final current = Directory('${stateDirectory.path}/current')
      ..createSync(recursive: true);
    File('${current.path}/index.html').writeAsStringSync('<html>erp</html>');
    File('${current.path}/main.dart.js').writeAsStringSync('erp bundle\n');
    final environment = {
      ...Platform.environment,
      'TMPDIR': sandbox.path,
      'ERP_WEB_PORT': '$port',
      'WEB_PREVIEW_BUILD_STATE_DIR': stateDirectory.path,
      'READY_TIMEOUT': '5',
      'PORT_RELEASE_TIMEOUT': '5',
    };

    try {
      final result = await Process.run(
        'bash',
        [scriptPath, 'start', '--erp', '--release'],
        environment: environment,
      );
      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(result.stdout, contains('started erp release preview'));

      final assetProbe = await Process.run(
        'curl',
        ['-sf', 'http://127.0.0.1:$port/main.dart.js'],
      );
      expect(assetProbe.exitCode, 0, reason: assetProbe.stderr.toString());
      expect(assetProbe.stdout, contains('erp bundle'));

      final routeProbe = await Process.run(
        'curl',
        ['-sf', 'http://127.0.0.1:$port/hr/payroll'],
      );
      expect(routeProbe.exitCode, 0, reason: routeProbe.stderr.toString());
      expect(routeProbe.stdout, contains('<html>erp</html>'));
    } finally {
      final stop = await Process.run(
        'bash',
        [scriptPath, 'stop', '--erp'],
        environment: environment,
      );
      expect(stop.exitCode, 0, reason: stop.stderr.toString());
      sandbox.deleteSync(recursive: true);
    }
  });

  test('wait readiness rejects assets served by an old process', () async {
    final sandbox = Directory.systemTemp.createTempSync(
      'web-preview-ready-owner-contract-',
    );
    final oldServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    oldServer.listen((request) async {
      request.response.write('old bundle\n');
      await request.response.close();
    });
    final candidate = await Process.start('sleep', ['30']);
    try {
      final runDirectory = Directory('${sandbox.path}/erp-web-preview/erp')
        ..createSync(recursive: true);
      final startStamp = await _processStartStamp(candidate.pid);
      File('${runDirectory.path}/run.pid').writeAsStringSync(
        '${candidate.pid}\n$startStamp\n',
      );

      final result = await Process.run(
        'bash',
        [scriptPath, 'wait', '--erp'],
        environment: {
          ...Platform.environment,
          'TMPDIR': sandbox.path,
          'ERP_WEB_PORT': '${oldServer.port}',
          'READY_TIMEOUT': '1',
        },
      );

      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('preview not ready before the deadline'));
    } finally {
      await oldServer.close(force: true);
      await _stopIfRunning(candidate);
      sandbox.deleteSync(recursive: true);
    }
  });

  test('a stale PID record never kills the process that reused the PID',
      () async {
    final sandbox = Directory.systemTemp.createTempSync(
      'web-preview-pid-contract-',
    );
    final port = await _unusedLoopbackPort();
    final sleeper = await Process.start('sleep', ['30']);
    try {
      final runDirectory = Directory('${sandbox.path}/erp-web-preview/erp')
        ..createSync(
          recursive: true,
        );
      File('${runDirectory.path}/run.pid').writeAsStringSync(
        '${sleeper.pid}\nMon Jan  1 00:00:00 2001\n',
      );

      final result = await Process.run(
        'bash',
        [scriptPath, 'stop', '--erp'],
        environment: {
          ...Platform.environment,
          'TMPDIR': sandbox.path,
          'ERP_WEB_PORT': '$port',
        },
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(
        result.stderr,
        contains('refusing stale PID record'),
      );
      final stillAlive = await Process.run(
        'kill',
        ['-0', sleeper.pid.toString()],
      );
      expect(stillAlive.exitCode, 0);
    } finally {
      sleeper.kill();
      await sleeper.exitCode;
      sandbox.deleteSync(recursive: true);
    }
  });
}
