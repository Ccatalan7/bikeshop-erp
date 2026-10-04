#!/usr/bin/env python3
"""Route website work to the site wiki (Claude Code hook; never blocks).

UserPromptSubmit: when the prompt is about vinabike.cl, the site editor, SEO,
the checkout, Merchant or Analytics, remind the agent once per session to use
the `sitio-web` skill and docs/wiki/sitio-web.

PostToolUse (Edit|Write|MultiEdit): when a file of the storefront, the editor,
the store build or a site Edge Function was edited, remind once per session to
update the wiki page in the same task and run its lint.

Owner, 2026-10-03: a «second brain … master schema experto en nuestro sitio web
y editor del sitio». The deterministic guard for Claude and Codex alike is
test/unit/site_wiki_contract_test.dart; this hook makes Claude reach for the
wiki before it gets that far.
"""
import json
from pathlib import Path
import re
import sys
import tempfile

PROMPT = re.compile(
    r'(\bsitio web\b|\bp[aá]gina web\b|\bwebsite\b|\bstorefront\b|vinabike\.cl|\btienda (online|p[uú]blica|web)\b|'
    r'\bseo\b|\beditor (del sitio|web|de website)\b|\bwebsite builder\b|\bcheckout\b|\bcarrito\b|'
    r'\bmerchant\b|search console|\banalytics\b|\bga4\b|pagespeed|\bsitemap\b|robots\.txt|'
    r'portal de clientes|datos estructurados|json-ld|google shopping|firebase hosting|'
    r'pedidos? (online|web)|core web vitals|\blcp\b)',
    re.IGNORECASE)
PATHS = re.compile(
    r'(lib/public_store/|lib/modules/website/|(^|/)web/(index\.html|robots\.txt|app-open\.html)|'
    r'(^|/)firebase\.json$|scripts/(generate_product_seo_snapshots|sync_seo_index|'
    r'check_storefront_bundle_budget|write_storefront_release_evidence)|scripts/storefront_instant_page/|'
    r'cloudflare-worker/|supabase/functions/(google-|mercadopago-|website-|dispatch-storefront|'
    r'send-transactional-order|resend-transactional)|firebase-hosting-store|website-editor-contract|'
    r'storefront-instant-page|website-builder-agent-handoff|ONLINE_ORDER_OPERATIONS)')
SKIP = re.compile(r'docs/wiki/sitio-web/')

PROMPT_NOTE = (
    'Tema del sitio web o su editor: antes de responder o cambiar algo, usa la skill `sitio-web` '
    '(docs/wiki/sitio-web/index.md → páginas del tema → lo vivo: release.json, sitemap, '
    'scripts/db/query.sh, consolas). Lo nuevo que aprendas va a su página y a log.md en la misma tarea.')
EDIT_NOTE = (
    'Editaste {path}, que es parte de la tienda, el editor, el build o una función del sitio. En la '
    'misma tarea: actualiza «En el código y la base» de la página del wiki que corresponde '
    '(docs/wiki/sitio-web/paginas/, y mapa-del-sistema.md si nace una tabla, función, ruta o evento) '
    'y corre `python3 scripts/knowledge/lint_site_wiki.py --db production`. '
    'test/unit/site_wiki_contract_test.dart falla si una ruta pública, un evento de GA4, una página '
    'de administración o una función del sitio no está en el wiki.')


def once(session, kind):
    marker = Path(tempfile.gettempdir()) / 'claude-site-wiki' / f'{session}-{kind}'
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
        if PATHS.search(path) and not SKIP.search(path) and once(session, 'edit'):
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
