import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A function the app calls with `kSupabaseFunctionsRegionHeaders` must list
/// `x-region` in its `Access-Control-Allow-Headers`. Without it the web
/// build's preflight succeeds, the browser never sends the POST, and only the
/// web breaks: the native apps ignore CORS. The rule was written down on
/// 2026-09-29 and on 2026-11-09 three functions still lacked it, one of them
/// born on 2026-10-13, after the rule: the web ERP could not reply on
/// Instagram or Messenger, hydrate WhatsApp media or preview the shipment
/// email. So it is a test now.
void main() {
  test('every region-pinned function call allows x-region in CORS', () {
    final calls = <String, Set<String>>{};
    final unnamed = <String>[];
    final dartFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    for (final file in dartFiles) {
      final source = file.readAsStringSync();
      if (source.contains(
          'const Map<String, String> kSupabaseFunctionsRegionHeaders')) {
        continue;
      }
      for (final use in 'kSupabaseFunctionsRegionHeaders'.allMatches(source)) {
        final invoke = source.lastIndexOf('.invoke(', use.start);
        final name = invoke < 0
            ? null
            : RegExp(r"""\.invoke\(\s*['"]([a-z0-9-]+)['"]""")
                .matchAsPrefix(source, invoke)
                ?.group(1);
        final line = '\n'.allMatches(source.substring(0, use.start)).length + 1;
        if (name == null) {
          unnamed.add('${file.path}:$line');
        } else {
          calls.putIfAbsent(name, () => <String>{}).add('${file.path}:$line');
        }
      }
    }

    expect(calls, isNotEmpty, reason: 'No region-pinned function call found.');
    expect(
      unnamed,
      isEmpty,
      reason: 'Name the function with a string literal in the same '
          '`functions.invoke(...)` call that passes kSupabaseFunctionsRegionHeaders.',
    );

    final allowHeaders = RegExp(
      r'''["']Access-Control-Allow-Headers["']\s*:\s*["']([^"']*)["']''',
    );
    final missing = <String>[];
    for (final entry in calls.entries) {
      final path = 'supabase/functions/${entry.key}/index.ts';
      final file = File(path);
      if (!file.existsSync()) {
        missing.add(
            '${entry.key}: $path does not exist (${entry.value.join(', ')})');
        continue;
      }
      final declared = allowHeaders
          .allMatches(file.readAsStringSync())
          .map((match) => match.group(1)!)
          .toList();
      final allowsRegion = declared.isNotEmpty &&
          declared.every((value) => value
              .split(',')
              .map((header) => header.trim().toLowerCase())
              .contains('x-region'));
      if (!allowsRegion) {
        missing.add('${entry.key} (called from ${entry.value.join(', ')})');
      }
    }
    expect(
      missing,
      isEmpty,
      reason: 'Add x-region to Access-Control-Allow-Headers in each of these '
          'functions and deploy it.',
    );
  });
}
