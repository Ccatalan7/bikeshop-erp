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
    // 2026-08-19 · decisión del dueño: «asegúrate de que correr querys por
    // agentes de IA sea muy fácil y no tengan ningún problema». Esta aserción
    // exigía lo contrario —que producción NO estuviera pre-aprobada—, y
    // contradecía al propio AGENT_DATABASE_CONTRACT.md, que promete que las
    // lecturas guiadas «never interrupt the user». El resultado real fue un
    // prompt por consulta que los agentes reportaban como bloqueo. La
    // deliberación de una escritura la conserva VINABIKE_DB_WRITE_CONFIRM y el
    // journal de query.sh, no un segundo permiso interactivo.
    expect(
      allowed,
      contains('Bash(bash scripts/db/query.sh production *)'),
      reason: 'Las lecturas alojadas son autónomas y no deben interrumpir.',
    );
    expect(
      allowed,
      contains(
        'Bash(VINABIKE_DB_WRITE_CONFIRM=production '
        'bash scripts/db/query.sh production *)',
      ),
      reason:
          'La forma canónica de la escritura guiada lleva el marcador de '
          'entorno como prefijo; sin esta regla ninguna otra la cubre.',
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

  // 2026-07-31 · decisión del dueño: commit, push y deshacer una edición
  // propia pasan al agente. Lo externo —deploy, publicación y escrituras en
  // producción— sigue siendo suyo, y eso se sigue exigiendo más abajo.
  test('el agente puede guardar y publicar su propio trabajo en la rama',
      () async {
    expect(await _runGuard('git add -A'), isNull);
    expect(await _runGuard('git commit -m "fix: algo"'), isNull);
    expect(await _runGuard('git push origin smartpegas1.0'), isNull);
    expect(await _runGuard('git restore -- lib/main.dart'), isNull);
    expect(await _runGuard('git restore -- lib/a.dart lib/b.dart'), isNull);
  });

  // Tres falsos positivos que costaron tiempo real y no protegían nada.
  test('el guard no muerde donde no hay peligro', () async {
    // Un guion DENTRO de un nombre de archivo no es el flag -r.
    expect(await _runGuard('rm -f frames/5c-parcial.png'), isNull);
    expect(await _runGuard('rm -f a-recursivo.txt b-raro.png'), isNull);
    // Buscar si hay una publicación corriendo es leer, no publicar — y es
    // justamente lo que hay que hacer ANTES de escribir en el árbol.
    expect(await _runGuard('pgrep -fl "firebase deploy|gradlew"'), isNull);
  });

  // 2026-08-01 · publicar la actualización del ERP pasa al agente. La tarea
  // macOS+Android es UNA, y el guard trataba sus dos mitades distinto —Android
  // pasaba, macOS no—, que fue lo que llevó a cancelar el run equivocado.
  test('el agente publica la actualización, pero no toca la infraestructura',
      () async {
    expect(
      await _runGuard('bash scripts/publish_macos_update.sh --prepared-state auto'),
      isNull,
    );
    expect(
      await _runGuard(
        'node scripts/releases/publish_android_workflow.mjs --prepared-state auto',
      ),
      isNull,
    );
    expect(
      await _runGuard('bash scripts/releases/prepare_erp_update.sh'),
      isNull,
    );

    // Mencionar la ruta dentro de un documento no es ejecutarla: el guard la
    // reconoce en posición de comando, no como texto suelto.
    expect(
      await _runGuard('grep -rn scripts/deploy.sh docs/'),
      isNull,
    );
    expect(
      await _runGuard('cat notas.md >> docs/development/plan.md'),
      isNull,
    );

    // 2026-08-19 · decisión del dueño: desplegar una Edge Function pasa al
    // agente. La regla anterior era asimétrica sin querer — el hook sólo corre
    // en Claude Code, así que Codex desplegaba el mismo comando sin fricción y
    // a Claude se le denegaba: no era política, era dónde estaba enganchado el
    // freno. La protección real la conserva `scripts/supabase_cli.sh`, que
    // exige un `--project-ref` aprobado: importa el destino, no quién escribe.
    expect(
      await _runGuard(
        'scripts/supabase_cli.sh functions deploy whatsapp-webhook '
        '--project-ref xzdvtzdqjeyqxnkqprtf',
      ),
      isNull,
    );

    // Lo que NO es el ciclo de release sigue siendo del dueño. Publicar el
    // sitio y correr la release son alcance distinto al de una función
    // revisada, y siguen denegados.
    for (final command in const [
      'firebase deploy',
      'bash scripts/deploy.sh',
      'sh ./scripts/deploy.sh --prod',
      './scripts/deploy.sh',
    ]) {
      expect(
        (await _runGuard(command))?['hookSpecificOutput']
            ?['permissionDecision'],
        'deny',
        reason: command,
      );
    }
  });

  test('external and destructive mutations are denied even in bypass mode',
      () async {
    for (final command in const [
      // Barrer el árbol entero no es recuperar una edición propia: descarta
      // el trabajo sin commitear de quien comparta el checkout.
      'git restore .',
      'git restore --staged lib/main.dart',
      'git restore --source=HEAD~1 lib/main.dart',
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
      'firebase deploy',
    ]) {
      final output = await _runGuard(command);
      expect(
        output?['hookSpecificOutput']?['permissionDecision'],
        'deny',
        reason: command,
      );
    }

    // 2026-08-05 · decisión del dueño: «los agentes deben correr los querys
    // siempre, sin pedir confirmación». La escritura guiada a producción por
    // el camino canónico deja de denegarse — VINABIKE_DB_WRITE_CONFIRM y el
    // journal de scripts/db/query.sh conservan la deliberación y la
    // auditoría. El costo de la regla anterior fue real: un admin recién
    // invitado quedó bloqueado por metadatos corruptos, el arreglo era un
    // UPDATE de una fila, y el guard lo devolvía a un Codex sin cupo. Los
    // caminos NO guiados (psql directo, supabase db, --allow-pii) siguen
    // denegados arriba: la política abrió el camino auditado, no la puerta.
    // 2026-08-19 · Regresión del defecto de posición de comando. Las reglas de
    // PII y de refresh comparaban subcadenas contra el comando entero, así que
    // *mencionar* la regla —documentarla, commitearla, greparla— se denegaba
    // sin que hubiera consulta. Es el mismo defecto que el bloque de deploy ya
    // había pagado; aquí era silencioso y el agente lo reportaba como bloqueo
    // mecánico. El entorno se lee del primer argumento posicional, de modo que
    // un `production` dentro del SQL tampoco dispara la regla.
    for (final command in const [
      'bash scripts/db/query.sh production --write --sql "select 1"',
      'just db-query production --write --sql "select 1"',
      'bash scripts/db/query.sh production --sql "select id from customers"',
      'grep -rn -- "--allow-pii" docs/',
      'git commit -m "docs: --allow-pii en scripts/db/query.sh production"',
      'bash scripts/db/query.sh local --allow-pii --sql "select * from users"',
      'bash scripts/db/query.sh local --sql "select * from production_lines"',
      'rg "scripts/db/production_validation.sh refresh" docs/',
    ]) {
      expect(await _runGuard(command), isNull, reason: command);
    }

    // El override sigue denegado en uso real, incluso con prefijo de entorno.
    for (final command in const [
      'VINABIKE_DB_WRITE_CONFIRM=production bash scripts/db/query.sh '
          'production --allow-pii --sql "select 1"',
      'bash scripts/db/query.sh staging --allow-pii --sql "select 1"',
      'bash scripts/db/production_validation.sh refresh',
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
