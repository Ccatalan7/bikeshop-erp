#!/usr/bin/env python3
"""Route compatibility work to the wiki (Claude Code hook; never blocks).

UserPromptSubmit: when the prompt is about part compatibility, spec sheets or
the compatibility engine, remind the agent once per session to use the
`compatibilidad` skill and docs/wiki/compatibilidad.

PostToolUse (Edit|Write|MultiEdit): when a file of the engine, the bike sheet,
the spec sheets or the Master Schema was edited, remind once per session to
update the wiki page in the same task and run its lint.

Owner, 2026-10-02: the wiki must not become «una carpeta paralela que será
olvidada». The deterministic guard for Claude and Codex alike is
test/unit/compatibility_wiki_contract_test.dart; this hook makes Claude reach
for the wiki before it gets that far.
"""
import json
from pathlib import Path
import re
import sys
import tempfile

PROMPT = re.compile(
    r'\b(calza\w*|compatib\w*|repuesto\w*|ficha t[eé]cnica|fichas t[eé]cnicas|ficha de la bici|'
    r'master schema|n[uú]cleo\w*|cassette\w*|pi[ñn][oó]n\w*|pedalier\w*|biela\w*|rotor\w*|'
    r'horquilla\w*|amortiguador\w*|tija\w*|neum[aá]tico\w*|llanta\w*|maza\w*|desviador\w*|'
    r'cambio trasero|bsd|etrto|boost|freehub|shis|bottom bracket|headset|derailleur|'
    r'motor de compatibilidad|spec_definitions|spec_templates)\b',
    re.IGNORECASE)
PATHS = re.compile(
    r'(bike_product_compatibility_service|wheel_service_facts|bike_form_dialog|bikeshop_models|'
    r'service_question_contract|product_compatibility|public_spec_display|BIKE_WORKSHOP_MASTER_SCHEMA|'
    r'product-technical-specifications-contract|bicycle-compatibility-knowledge|'
    r'supabase/migrations/[^/]*spec|scripts/inventory/[^/]*spec)')

PROMPT_NOTE = (
    'Tema de compatibilidad o fichas técnicas: antes de responder o cambiar algo, usa la skill '
    '`compatibilidad` (docs/wiki/compatibilidad/index.md → páginas del tema → datos vivos con '
    'scripts/db/query.sh). Lo nuevo que aprendas va a su página y a log.md en la misma tarea.')
EDIT_NOTE = (
    'Editaste {path}, que es parte del motor, las fichas o el Master Schema. En la misma tarea: '
    'actualiza la sección «En Vinabike» de la página del wiki que corresponde (y '
    'docs/wiki/compatibilidad/paginas/modelo-vinabike.md si cambió una clave de la bici o una '
    'familia) y corre `python3 scripts/knowledge/lint_compat_wiki.py --db production`. '
    'test/unit/compatibility_wiki_contract_test.dart falla si el motor juzga una familia o lee un '
    'campo de la bici que el wiki no nombra.')


def once(session, kind):
    marker = Path(tempfile.gettempdir()) / 'claude-compat-wiki' / f'{session}-{kind}'
    if marker.exists():
        return False
    marker.parent.mkdir(parents=True, exist_ok=True)
    marker.touch()
    return True


def main():
    payload = json.load(sys.stdin)
    event = payload.get('hook_event_name', '')
    session = re.sub(r'[^A-Za-z0-9_-]', '', str(payload.get('session_id', 'none')))[:80] or 'none'
    note = None
    if event == 'UserPromptSubmit':
        if PROMPT.search(payload.get('prompt') or '') and once(session, 'prompt'):
            note = PROMPT_NOTE
    elif event == 'PostToolUse':
        tool_input = payload.get('tool_input') or {}
        path = str(tool_input.get('file_path') or tool_input.get('path') or '')
        if PATHS.search(path) and once(session, 'edit'):
            note = EDIT_NOTE.format(path=path)
    if note:
        print(json.dumps({'hookSpecificOutput': {'hookEventName': event, 'additionalContext': note}},
                         ensure_ascii=False))


if __name__ == '__main__':
    try:
        main()
    except Exception:
        pass
    sys.exit(0)
