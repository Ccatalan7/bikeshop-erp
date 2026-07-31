import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Future<Map<String, dynamic>?> _runGuard(String command) async {
  final process = await Process.start(
    'bash',
    ['.claude/hooks/guard-dangerous-bash.sh'],
  );
  process.stdin.writeln(
    jsonEncode({
      'tool_name': 'Bash',
      'tool_input': {'command': command},
    }),
  );
  await process.stdin.close();
  final stdout = await utf8.decoder.bind(process.stdout).join();
  final stderr = await utf8.decoder.bind(process.stderr).join();
  final exitCode = await process.exitCode;
  expect(exitCode, 0, reason: stderr);
  if (stdout.trim().isEmpty) return null;
  return Map<String, dynamic>.from(
    jsonDecode(stdout) as Map<String, dynamic>,
  );
}

void main() {
  test('Claude project settings load both context and safety hooks', () {
    final settings = jsonDecode(
      File('.claude/settings.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final hooks = settings['hooks'] as Map<String, dynamic>;

    expect(hooks['SessionStart'], isNotEmpty);
    expect(hooks['PreToolUse'], isNotEmpty);
    expect(settings['skipWorkflowUsageWarning'], isFalse);
    expect(
      (settings['env']
          as Map<String, dynamic>)['CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS'],
      '0',
    );
    expect(
      (settings['env'] as Map<String, dynamic>),
      isNot(contains('MAX_THINKING_TOKENS')),
      reason:
          'The primary Claude session may use the reasoning depth required by '
          'the unresolved risk; the project must not impose an artificial cap.',
    );
    final allowed = List<String>.from(
      (settings['permissions'] as Map<String, dynamic>)['allow'] as List,
    );
    expect(
      allowed.where(
        (rule) =>
            rule.contains('query.sh production') ||
            rule.contains('db-query production'),
      ),
      isEmpty,
    );
    final denied = List<String>.from(
      (settings['permissions'] as Map<String, dynamic>)['deny'] as List,
    );
    for (final rule in const [
      'Bash(git checkout *)',
      'Bash(git stash *)',
      'Bash(git rebase *)',
    ]) {
      expect(denied, contains(rule));
    }
    expect(
      File('.claude/hooks/session-context.sh').existsSync(),
      isTrue,
    );
    expect(
      File('.claude/hooks/guard-dangerous-bash.sh').existsSync(),
      isTrue,
    );
    for (final reviewer in const [
      'ui-design-lead',
      'logic-cross-reviewer',
      'ui-cross-reviewer',
    ]) {
      expect(File('.claude/agents/$reviewer.md').existsSync(), isTrue);
    }
    expect(File('.claude/skills/cross-review/SKILL.md').existsSync(), isTrue);
    final collaboration = File(
      'docs/development/CODEX_CLAUDE_COLLABORATION.md',
    ).readAsStringSync();
    expect(collaboration, contains('Dual diagnosis gate'));
    expect(collaboration, contains('budget by'));
    expect(
      collaboration,
      contains('unresolved risk rather than a small fixed tool count'),
    );
  });

  test('ordinary read-only repository commands remain available', () async {
    expect(await _runGuard('git status --short'), isNull);
    expect(await _runGuard('git status push'), isNull);
    expect(await _runGuard('git switch main'), isNull);
    expect(await _runGuard('git switch -c claude/example'), isNull);
    expect(
      await _runGuard('git -C /tmp/example switch main'),
      isNull,
    );
    expect(await _runGuard('rg -n tenant_id lib'), isNull);
  });

  test('external and destructive mutations are denied even in bypass mode',
      () async {
    for (final command in const [
      'git push origin smartpegas1.0',
      'git -C /tmp/example push origin main',
      'git -c user.name=Claude commit -m test',
      '/usr/bin/git restore lib/main.dart',
      'sh -c "git commit -m nested"',
      'git checkout main',
      'git checkout -b claude/example',
      'git checkout .',
      'git checkout lib/main.dart',
      'git checkout HEAD -- lib/',
      'git checkout HEAD lib/main.dart',
      'git checkout -f',
      'git checkout -f main',
      'git checkout -B existing main',
      'git checkout --ours lib/main.dart',
      'git checkout --pathspec-from-file=paths.txt HEAD',
      'git -C /tmp/example checkout HEAD -- lib/',
      'git -C /tmp/example checkout HEAD lib/main.dart',
      '/usr/bin/git --work-tree=/tmp checkout .',
      'sh -c "git checkout HEAD -- lib/"',
      'git switch --discard-changes main',
      'git switch -C existing main',
      'git switch -Cexisting main',
      'git stash',
      'git stash push -u',
      'git stash clear',
      'git rebase main',
      'git rebase -i main',
      'git -C /tmp/example rebase main',
      'bash -c "git stash push -u"',
      'rm -r /tmp/example',
      'rm -R /tmp/example',
      'rm -r -f /tmp/example',
      'find /tmp/example -delete',
      'psql postgres://example',
      '/opt/homebrew/bin/psql postgres://example',
      '/usr/local/bin/supabase db push',
      'bash scripts/db/query.sh production --allow-pii --sql "select 1"',
      'just db-query production --write --sql "select 1"',
      'firebase deploy',
    ]) {
      final output = await _runGuard(command);
      expect(
        output?['hookSpecificOutput']?['permissionDecision'],
        'deny',
        reason: command,
      );
    }
  });
}
