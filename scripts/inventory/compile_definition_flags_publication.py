#!/usr/bin/env python3
"""Compile the visibility and filter flag publication from its proposal.

Reads definition-flags-proposal-2026-09-16.json (produced read-only by
propose_definition_flags.py) and writes a standalone, rerunnable migration
plus its read-only verifier. The migration updates only is_customer_visible
and is_filterable on the listed global definitions, requires every listed
definition to still carry the recorded preimage flags (or already the
published ones, so an interrupted verification can rerun it), and touches
no template, field, fact or product. Those two columns are outside the
revision trigger, so no contract version moves.
"""
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
RESEARCH = ROOT / 'docs/development/product-specs-research-2026-09-05'
PROPOSAL = RESEARCH / 'definition-flags-proposal-2026-09-16.json'
VERSION = '20260916150000'
SLUG = 'definition_visibility_flags'
MIGRATION = ROOT / f'supabase/migrations/{VERSION}_{SLUG}.sql'
VERIFIER = ROOT / f'supabase/manual_checks/verification/{VERSION}_{SLUG}.sql'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rows(proposal):
    return [{'id': p['definition_id'], 'key': p['key'],
             'visible_before': p['current']['is_customer_visible'],
             'filterable_before': p['current']['is_filterable'],
             'visible_after': p['proposed']['is_customer_visible'],
             'filterable_after': p['proposed']['is_filterable']}
            for p in proposal['proposals']]


def literal(value):
    encoded = json.dumps(value, ensure_ascii=False, separators=(',', ':'))
    if '$flags$' in encoded:
        raise SystemExit('dollar tag collision')
    return encoded


RECORDSET = ("jsonb_to_recordset($flags$%s$flags$::jsonb) as r(id uuid, key text, visible_before boolean, "
             "filterable_before boolean, visible_after boolean, filterable_after boolean)")
AFTER_COUNT = """(select count(*) from public.spec_definitions d join nd_flag_changes c on c.id=d.id
   where d.tenant_id is null and d.key=c.key and d.is_customer_visible=c.visible_after and d.is_filterable=c.filterable_after)"""
BEFORE_COUNT = """(select count(*) from public.spec_definitions d join nd_flag_changes c on c.id=d.id
   where d.tenant_id is null and d.key=c.key and d.is_customer_visible=c.visible_before and d.is_filterable=c.filterable_before)"""


def migration_text(proposal, changes):
    n = len(changes)
    return f"""-- Customer visibility and filter flags for {n} global definitions that were
-- born invisible and unfilterable: the public store shows a value only when
-- is_customer_visible is true and the assistant, supply needs and supplier
-- portal can use a field only when is_filterable is true. Rule and list in
-- docs/development/product-specs-research-2026-09-05/definition-flags-proposal-2026-09-16.md
-- (proposal sha256 {digest(PROPOSAL)}). No flag is switched off. Only the two
-- flag columns change; they are outside product_spec_definition_revision, so
-- no template contract version moves. No template, field, fact, product or
-- assignment changes. Rerunnable: with every flag already published it exits.
begin;
set local lock_timeout='5s';
set local statement_timeout='120s';
create temp table nd_flag_changes on commit drop as select * from {RECORDSET % literal(changes)};
do $guard$ begin
 if (select count(*) from nd_flag_changes) <> {n} then
  raise exception 'Flag change list drifted';
 end if;
 if {AFTER_COUNT} = {n} then
  return;
 end if;
 if {BEFORE_COUNT} <> {n} then
  raise exception 'Definition flag preimage drifted; recompute the proposal before publishing';
 end if;
 update public.spec_definitions d set is_customer_visible=c.visible_after, is_filterable=c.filterable_after
  from nd_flag_changes c where d.id=c.id and d.tenant_id is null;
 if {AFTER_COUNT} <> {n} then
  raise exception 'Flag publication did not reach every listed definition';
 end if;
end $guard$;
commit;
"""


def verifier_text(changes):
    n = len(changes)
    return f"""-- Read-only flag read-back. Fails before publication (division by zero) and
-- passes only when every listed definition carries its published flags.
with nd_flag_changes as (select * from {RECORDSET % literal(changes)})
select 1/(case when {AFTER_COUNT} = {n} then 1 else 0 end) as flags_published;
select (select count(*) from public.spec_definitions where tenant_id is null and is_customer_visible) as visible_definitions,
 (select count(*) from public.spec_definitions where tenant_id is null and is_filterable) as filterable_definitions,
 (select count(distinct t.id) from public.spec_templates t join public.spec_template_fields f on f.template_id=t.id
   join public.spec_definitions d on d.id=f.spec_definition_id
   where t.is_active and d.is_customer_visible and coalesce(t.form_contract->'roles'->>d.key,'') <> 'legacy') as templates_with_a_visible_active_field,
 (select count(*) from public.spec_templates where is_active) as active_templates;
"""


def main():
    proposal = json.loads(PROPOSAL.read_text())
    if proposal.get('publication_authorized') is not False or proposal.get('writes') != 0:
        raise SystemExit('unexpected proposal shape')
    changes = rows(proposal)
    if any(c['visible_before'] and not c['visible_after'] or c['filterable_before'] and not c['filterable_after']
           for c in changes):
        raise SystemExit('a downgrade slipped into the proposal')
    MIGRATION.write_text(migration_text(proposal, changes))
    VERIFIER.write_text(verifier_text(changes))
    print(json.dumps({'definitions': len(changes), 'migration': str(MIGRATION.relative_to(ROOT)),
                      'migration_sha256': digest(MIGRATION), 'verifier': str(VERIFIER.relative_to(ROOT)),
                      'verifier_sha256': digest(VERIFIER)}))


if __name__ == '__main__':
    main()
