// `scripts/dev/web_preview.sh --local` (2026-09-30): the ERP compiled against
// the local Supabase stack. lib/main.dart falls back to PRODUCTION without
// defines, so the profile must refuse a remote URL, a missing or non-public
// key, and any bundle that was not stamped for the local stack. These cases
// run the real script with a fake `supabase status` and a fake Flutter.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _script = 'scripts/dev/web_preview.sh';

String _jwt(Map<String, Object> claims) {
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg': 'HS256', 'typ': 'JWT'})}.${part(claims)}.firma';
}

final _anonKey = _jwt({'iss': 'supabase-demo', 'role': 'anon'});
final _serviceKey = _jwt({'iss': 'supabase-demo', 'role': 'service_role'});
const _publishableKey = 'sb_publishable_localdemo';

class _Sandbox {
  _Sandbox() : root = Directory.systemTemp.createTempSync('web-preview-local-');

  final Directory root;

  String get state => '${root.path}/state';
  String get argvFile => '${root.path}/flutter-argv.txt';
  String get definesModeFile => '${root.path}/defines-mode.txt';

  /// A `supabase status -o env` that prints [lines].
  void stack(List<String> lines) {
    final status = File('${root.path}/status.env')
      ..writeAsStringSync('${lines.join('\n')}\n');
    File('${root.path}/supabase').writeAsStringSync('#!/usr/bin/env bash\n'
        '[ "\$1 \$2 \$3" = "status -o env" ] || exit 64\n'
        'cat "${status.path}"\n');
  }

  /// A `flutter build web` that records its argv and compiles the define's
  /// URL into main.dart.js (or leaves it out when [compileUrl] is false).
  void flutter({bool compileUrl = true}) {
    File('${root.path}/flutter').writeAsStringSync('''#!/usr/bin/env bash
set -euo pipefail
printf '%s\\n' "\$@" >"$argvFile"
output=""
defines=""
while [ "\$#" -gt 0 ]; do
  case "\$1" in
    -o) shift; output="\$1" ;;
    --dart-define-from-file=*) defines="\${1#--dart-define-from-file=}" ;;
  esac
  shift
done
mkdir -p "\$output"
printf '<html>local</html>\\n' >"\$output/index.html"
url=""
if [ -n "\$defines" ]; then
  # `stat -f %Lp` is BSD-only; CI runs this on Linux (2026-10-01).
  python3 -c 'import os,sys; print(format(os.stat(sys.argv[1]).st_mode & 0o777, "o"))' "\$defines" >"$definesModeFile"
  url="\$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["SUPABASE_URL"])' "\$defines")"
fi
${compileUrl ? r'printf "var u=\"%s/rest/v1\";\n" "$url"' : r'printf "var u=null;\n"'} >"\$output/main.dart.js"
''');
  }

  Future<ProcessResult> run(List<String> arguments,
      {Map<String, String> extra = const {}}) async {
    for (final tool in ['supabase', 'flutter']) {
      final file = File('${root.path}/$tool');
      if (file.existsSync()) await Process.run('chmod', ['+x', file.path]);
    }
    return Process.run('bash', [
      _script,
      ...arguments
    ], environment: {
      ...Platform.environment,
      'TMPDIR': root.path,
      'FLUTTER_BIN': '${root.path}/flutter',
      'WEB_PREVIEW_SUPABASE_CLI': '${root.path}/supabase',
      'WEB_PREVIEW_LOCAL_BUILD_STATE_DIR': state,
      ...extra,
    });
  }

  void dispose() => root.deleteSync(recursive: true);
}

void main() {
  late _Sandbox sandbox;

  setUp(() => sandbox = _Sandbox());
  tearDown(() => sandbox.dispose());

  test('a remote API URL is refused before anything compiles', () async {
    sandbox
      ..stack([
        'API_URL="https://xzdvtzdqjeyqxnkqprtf.supabase.co"',
        'ANON_KEY="$_anonKey"',
      ])
      ..flutter();

    final result = await sandbox.run(['build', '--local']);

    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('non-local API URL'));
    expect(File(sandbox.argvFile).existsSync(), isFalse);
    expect(Directory('${sandbox.state}/releases').existsSync(), isFalse);
  });

  test('a URL that only starts like a local one is refused', () async {
    sandbox
      ..stack([
        'API_URL="http://127.0.0.1:54321@xzdvtzdqjeyqxnkqprtf.supabase.co"',
        'ANON_KEY="$_anonKey"',
      ])
      ..flutter();

    final result = await sandbox.run(['build', '--local']);

    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('non-local API URL'));
    expect(File(sandbox.argvFile).existsSync(), isFalse);
  });

  test('a missing or service-role key is refused and never printed', () async {
    for (final keyLine in [
      '',
      'ANON_KEY="$_serviceKey"',
      'ANON_KEY="sb_secret_x"'
    ]) {
      sandbox
        ..stack([
          'API_URL="http://127.0.0.1:54321"',
          if (keyLine.isNotEmpty) keyLine
        ])
        ..flutter();

      final result = await sandbox.run(['build', '--local']);

      expect(result.exitCode, isNot(0), reason: keyLine);
      expect(result.stderr, contains('non-public anon key'), reason: keyLine);
      expect('${result.stdout}${result.stderr}', isNot(contains(_serviceKey)));
      expect(File(sandbox.argvFile).existsSync(), isFalse, reason: keyLine);
    }
  });

  test('a local stack builds through a private defines file and a stamp',
      () async {
    sandbox
      ..stack([
        'API_URL="http://127.0.0.1:54321"',
        'ANON_KEY="$_anonKey"',
        'PUBLISHABLE_KEY="$_publishableKey"',
        'SERVICE_ROLE_KEY="$_serviceKey"',
        'DB_URL="postgresql://postgres:postgres@127.0.0.1:54322/postgres"',
      ])
      ..flutter();

    final result = await sandbox.run(['build', '--local']);

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    final argv = File(sandbox.argvFile).readAsStringSync();
    expect(argv, contains('lib/main.dart'));
    expect(argv, contains('--dart-define-from-file='));
    expect(argv, isNot(contains('--dart-define=')));
    expect(argv, isNot(contains(_anonKey)));
    expect(File(sandbox.definesModeFile).readAsStringSync().trim(), '600');
    // The defines and the stack's status never outlive the build.
    final leftovers = sandbox.root
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) =>
            file.path.endsWith('defines.json') ||
            (file.path.endsWith('status.env') &&
                file.path != '${sandbox.root.path}/status.env'));
    expect(leftovers, isEmpty);
    final output = '${result.stdout}${result.stderr}';
    for (final secret in [
      _anonKey,
      _serviceKey,
      _publishableKey,
      'postgres:postgres'
    ]) {
      expect(output, isNot(contains(secret)));
    }
    final stamp = File('${sandbox.state}/current/.vinabike-local-profile')
        .readAsStringSync();
    expect(stamp, contains('api_url=http://127.0.0.1:54321'));
    expect(stamp, matches(RegExp(r'keys_sha256_16=[0-9a-f]{16}')));
    expect(stamp, isNot(contains(_anonKey)));
  });

  test('a bundle without the local URL is refused, not published', () async {
    sandbox
      ..stack(['API_URL="http://127.0.0.1:54321"', 'ANON_KEY="$_anonKey"'])
      ..flutter(compileUrl: false);

    final result = await sandbox.run(['build', '--local']);

    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('does not carry the local API URL'));
    expect(Link('${sandbox.state}/current').existsSync(), isFalse);
  });

  test('the customer portal uses the real store entrypoint with local Auth',
      () async {
    sandbox
      ..stack(['API_URL="http://127.0.0.1:54321"', 'ANON_KEY="$_anonKey"'])
      ..flutter();
    final result = await sandbox.run([
      'build',
      '--store',
      '--local'
    ], extra: {
      'VINABIKE_STORE_TENANT_ID': 'b5380d4f-dfb4-492e-b592-6420308be916',
      'VINABIKE_STORE_SUBDOMAIN': 'c3-privado',
    });
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    final argv = File(sandbox.argvFile).readAsStringSync();
    expect(argv, contains('lib/main_store.dart'));
    expect(argv, contains('--dart-define-from-file='));
    expect(
        argv,
        contains(
            'PUBLIC_STORE_TENANT_ID=b5380d4f-dfb4-492e-b592-6420308be916'));
    expect(argv, isNot(contains(_anonKey)));
    final stamp = File('${sandbox.state}/current/.vinabike-local-profile')
        .readAsStringSync();
    expect(stamp, contains('api_url=http://127.0.0.1:54321'));
    expect(stamp,
        contains('store_tenant_id=b5380d4f-dfb4-492e-b592-6420308be916'));
    expect(stamp, contains('store_subdomain=c3-privado'));
  });

  test('the local server refuses an unstamped (production) bundle', () async {
    final production = Directory('${sandbox.state}/releases/prod')
      ..createSync(recursive: true);
    File('${production.path}/index.html').writeAsStringSync('<html></html>');
    File('${production.path}/main.dart.js').writeAsStringSync('var u=1;');
    Link('${sandbox.state}/current').createSync('releases/prod');

    final result = await sandbox.run(['serve-release', '--local']);

    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('without the local-profile stamp'));
  });

  test('the production preview refuses a local bundle', () async {
    final local = Directory('${sandbox.root.path}/erp-state/releases/local')
      ..createSync(recursive: true);
    File('${local.path}/index.html').writeAsStringSync('<html></html>');
    File('${local.path}/.vinabike-local-profile')
        .writeAsStringSync('api_url=http://127.0.0.1:54321\n');
    Link('${sandbox.root.path}/erp-state/current').createSync('releases/local');

    final result = await sandbox.run([
      'serve-release',
      '--erp'
    ], extra: {
      'WEB_PREVIEW_BUILD_STATE_DIR': '${sandbox.root.path}/erp-state',
    });

    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('local-profile bundle on the erp preview'));
  });

  test('the local profile never shares a production preview origin', () async {
    for (final port in ['54330', '54331']) {
      final result = await sandbox
          .run(['url', '--local'], extra: {'ERP_LOCAL_WEB_PORT': port});
      expect(result.exitCode, 2, reason: port);
      expect(result.stderr, contains('needs its own origin'));
      final store = await sandbox.run(['url', '--store', '--local'],
          extra: {'STORE_LOCAL_WEB_PORT': port});
      expect(store.exitCode, 2, reason: port);
      expect(store.stderr, contains('needs its own origin'));
    }
    final ok = await sandbox.run(['url', '--local']);
    expect(ok.stdout, startsWith('http://localhost:54334/'));
  });

  test('--local refuses an ambiguous all-app target', () async {
    final result = await sandbox.run(['build', '--all', '--local']);
    expect(result.exitCode, 2);
    expect(result.stderr, contains('needs --erp or --store'));
  });
}
