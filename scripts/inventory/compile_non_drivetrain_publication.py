#!/usr/bin/env python3
"""Compile the reviewed twelve-family metadata publication; never run SQL.

Only new global metadata is inserted, as required by immutable OEM references.
The one existing shared definition is
checked byte-for-byte as JSONB and never updated. Product facts, assignments,
references and category defaults are outside this publication.
"""
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import uuid

from compile_product_spec_catalog import RESEARCH, ROOT, validate_contract

CATALOG = RESEARCH / 'all-family-port-cardinality-integrated-2026-09-07.json'
CATALOG_SHA = '16459826fee4c589cce37243afe4e159317212ddf1d47d6d6f1d76f9b3fadf15'
CASES = RESEARCH / 'all-family-port-cardinality-cases-integrated-2026-09-07.json'
CASES_SHA = '329ad3e5543048121775fd7fc3d5c5b4acd90d7446cd3deacc999b4dce3716d7'
PREIMAGE = RESEARCH / 'non-drivetrain-publication-preimage-2026-09-07.json'
PREIMAGE_SHA = 'dcd23323fa221cab3cc073c4cc64eabeced3d12da8b56ff37adec18f6a503292'
TENANT = '5443b130-cc28-45af-a420-cd500b288890'
FAMILIES = ('bottle', 'bottle_cage', 'lock', 'audible_signal', 'reflector',
            'souvenir', 'food_beverage', 'rider_apparel', 'rider_glove',
            'rider_protection', 'helmet', 'workshop_chemical')
VERSION = '20260907222000'
TABLES = {
    'spec_definitions': ('id', 'tenant_id', 'key', 'label', 'data_type', 'unit',
                        'allowed_values', 'validation_rules',
                        'is_customer_visible', 'is_compatibility_relevant',
                        'description', 'is_filterable', 'is_required_by_default',
                        'is_mechanic_visible', 'group_name', 'sort_order'),
    'spec_definition_values': ('id', 'tenant_id', 'spec_definition_id', 'code',
                               'label', 'sort_order', 'is_active'),
    'spec_templates': ('id', 'tenant_id', 'key', 'name', 'technical_family',
                      'form_contract', 'is_active', 'description', 'default_tags'),
    'spec_template_fields': ('id', 'tenant_id', 'template_id',
                            'spec_definition_id', 'section_key', 'sort_order',
                            'is_required', 'visibility_rules', 'option_rules',
                            'constraint_rules', 'default_value_json', 'helper_text'),
}


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')


def sql_json(value):
    encoded = json.dumps(value, ensure_ascii=False, separators=(',', ':'))
    if '$nd_catalog$' in encoded:
        raise ValueError('SQL document delimiter collision')
    return '$nd_catalog$' + encoded + '$nd_catalog$::jsonb'


def compile_packet():
    if hashlib.sha256(CATALOG.read_bytes()).hexdigest() != CATALOG_SHA:
        raise ValueError('Frozen catalogue changed')
    if hashlib.sha256(CASES.read_bytes()).hexdigest() != CASES_SHA:
        raise ValueError('Frozen cases changed')
    if hashlib.sha256(PREIMAGE.read_bytes()).hexdigest() != PREIMAGE_SHA:
        raise ValueError('Frozen metadata preimage changed')
    catalog = json.loads(CATALOG.read_text())
    preimage = json.loads(PREIMAGE.read_text())[0]['metadata']
    if preimage['tenant_id'] != TENANT or preimage['template_collisions']:
        raise ValueError('Target scope or new template preimage changed')
    templates = [deepcopy(t) for t in catalog['templates'] if t['key'] in FAMILIES]
    if len(templates) != len(FAMILIES) or any(t['origin'] != 'new' for t in templates):
        raise ValueError('This publication cannot replace existing templates')
    keys = {f['key'] for t in templates for f in t['fields']}
    definitions = {k: deepcopy(catalog['definitions'][k]) for k in sorted(keys)}
    reused = {d['key']: d for d in preimage['existing_definitions']}
    if set(reused) != {k for k, d in definitions.items() if d['origin'] == 'existing'}:
        raise ValueError('Definition collision or missing preimage')
    for key, before in reused.items():
        if any(before[c] != definitions[key][c] for c in
               ('id', 'key', 'label', 'data_type', 'unit', 'allowed_values', 'validation_rules')):
            raise ValueError('Reused definition drift: ' + key)
    for template in templates:
        if template['key'] in ('lock', 'rider_protection'):
            template['form_contract']['helpers']['kit_members'] = (
                'Describe el contenido incluido. La marca y el modelo son los '
                'declarados para cada pieza; sus medidas y certificaciones '
                'deben conservar su propio alcance.')
        validate_contract(template['key'], template['form_contract'], definitions,
                          {f['key'] for f in template['fields']})
    records = metadata_records(templates, definitions, set(reused))
    packet = {
        'schema_version': 1, 'scope': 'new_global_metadata_only',
        'audited_tenant_id': TENANT, 'catalog_sha256': CATALOG_SHA,
        'preimage_sha256': hashlib.sha256(PREIMAGE.read_bytes()).hexdigest(),
        'families': list(FAMILIES), 'reused_definitions': list(reused.values()),
        'records': records, 'product_writes': False, 'fill_allowed': False,
        'mechanical_approval': False,
        'adjudication': {'PUB-D01': 'rejected_and_withdrawn_by_reviewer',
                         'KIT-R01': 'content_scope_helper_added',
                         'KIT-R02': 'unknown_family_remains_nonblocking_pending'},
    }
    subset = {**catalog, 'templates': templates, 'definitions': definitions}
    cases = json.loads(CASES.read_text())
    cases['cases'] = [c for c in cases['cases'] if c['template'] in FAMILIES]
    for family in ('lock', 'rider_protection'):
        for known in (True, False):
            values = {'member_role': 'otro', 'quantity': '1',
                      'position': 'Sin posición'}
            if known:
                values['family'] = 'light'
            case = {'id': 'nd_kit_' + family + ('_light' if known else '_unknown'),
                    'template': family,
                    'values': {'kit_members': {'schema_version': 1, 'rows': [
                        {'id': 'included-member', 'values': values, 'sources': []}]}},
                    'expected_blocking': [], 'facts_verified_for_product': False,
                    'automatic_fill_authorized': False}
            if not known:
                case['expected_issue_subset'] = [
                    {'code': 'row_incomplete', 'field': 'kit_members', 'blocking': False}]
            cases['cases'].append(case)
    return packet, subset, cases


def metadata_records(templates, definitions, reused_keys):
    """Build new records while retaining all explicitly reused definitions.

    ``origin`` in a historical proposal is not live publication state: a
    definition marked new there may already be shared by a preceding batch.
    """
    records = {table: [] for table in TABLES}
    for key, definition in definitions.items():
        if key in reused_keys:
            continue
        record = {k: definition[k] for k in TABLES['spec_definitions']
                  if k in definition}
        record.update(tenant_id=None, is_customer_visible=False,
                      is_compatibility_relevant=False, description=None,
                      is_filterable=False, is_required_by_default=False,
                      is_mechanic_visible=True, group_name=None, sort_order=0)
        records['spec_definitions'].append(record)
        for order, option in enumerate(definition['allowed_values']):
            records['spec_definition_values'].append({
                'id': str(uuid.uuid5(uuid.NAMESPACE_URL,
                                    'vinabike:spec-option:' + definition['id'] + ':' + option)),
                'tenant_id': None, 'spec_definition_id': definition['id'],
                'code': 'catalog_' + hashlib.md5(option.encode()).hexdigest(),
                'label': option, 'sort_order': order, 'is_active': True})
    for template in templates:
        records['spec_templates'].append({
            **{k: template[k] for k in TABLES['spec_templates'] if k in template},
            'tenant_id': None, 'is_active': True, 'description': None,
            'default_tags': []})
        for field in template['fields']:
            definition_id = definitions[field['key']]['id']
            records['spec_template_fields'].append({
                **{k: field[k] for k in TABLES['spec_template_fields'] if k in field},
                'id': str(uuid.uuid5(uuid.NAMESPACE_URL,
                                    'vinabike:spec-field:' + template['id'] + ':' + definition_id)),
                'tenant_id': None, 'template_id': template['id'],
                'spec_definition_id': definition_id,
                'default_value_json': deepcopy(field.get('default_value_json')),
                'helper_text': field.get('helper_text')})
    return records


def assertion_sql(packet):
    checks = []
    for table in TABLES:
        checks.append(f"""not exists (
 select 1 from jsonb_array_elements(doc->'records'->'{table}') wanted
 left join public.{table} actual on actual.id=(wanted->>'id')::uuid
 where actual.id is null or (select jsonb_object_agg(k,to_jsonb(actual)->k)
 from jsonb_object_keys(wanted) k) is distinct from wanted)""")
    # An extra field/option would expand this reviewed representation.
    checks.append("""not exists (select 1 from public.spec_template_fields f
 where f.template_id in (select (t->>'id')::uuid from jsonb_array_elements(doc->'records'->'spec_templates') t)
 and f.id not in (select (f->>'id')::uuid from jsonb_array_elements(doc->'records'->'spec_template_fields') f))""")
    checks.append("""not exists (select 1 from public.spec_definition_values v
 where v.spec_definition_id in (select (d->>'id')::uuid from jsonb_array_elements(doc->'records'->'spec_definitions') d)
 and v.id not in (select (v->>'id')::uuid from jsonb_array_elements(doc->'records'->'spec_definition_values') v))""")
    checks.append("""not exists (select 1 from jsonb_array_elements(doc->'reused_definitions') wanted
 left join public.spec_definitions d on d.id=(wanted->>'id')::uuid
 where d.id is null or to_jsonb(d) is distinct from wanted-'options'
 or (select coalesce(jsonb_agg(to_jsonb(v) order by v.id),'[]')
     from public.spec_definition_values v where v.spec_definition_id=d.id) is distinct from wanted->'options')""")
    return " and\n".join('(' + check + ')' for check in checks)


def generate_migration(packet, *, source_sha=CATALOG_SHA):
    blocks = []
    for table, columns in TABLES.items():
        names = ','.join(columns)
        blocks.append(f"""
 for wanted in select value from jsonb_array_elements(doc->'records'->'{table}') loop
   select to_jsonb(t) into actual from public.{table} t where id=(wanted->>'id')::uuid;
   if found then
     if (select jsonb_object_agg(k,actual->k) from jsonb_object_keys(wanted) k)
       is distinct from wanted then raise exception 'Publication drift in {table}: %',wanted->>'id'; end if;
   else
     insert into public.{table}({names})
     select {names} from jsonb_populate_record(null::public.{table},wanted);
   end if;
 end loop;""")
    sizes = {key: len(value) for key, value in packet['records'].items()}
    return f"""-- Reviewed new metadata only: {sizes['spec_templates']} templates, {sizes['spec_definitions']} definitions, {sizes['spec_template_fields']} fields.
-- Source catalogue SHA-256: {source_sha}
-- No product, category default, fact, reference or compatibility approval write.
-- Recovery: deactivate only these new templates with the normal binding guard;
-- retain their definitions and observations. Never erase later product edits.
begin isolation level repeatable read;
set local lock_timeout='5s';
set local statement_timeout='120s';
lock table public.spec_definitions,public.spec_definition_values,
 public.spec_templates,public.spec_template_fields in share row exclusive mode;
create temporary table nd_publication_document(doc jsonb) on commit drop;
insert into nd_publication_document values ({sql_json(packet)});
create temporary table nd_publication_before on commit drop as select
 (select md5(coalesce(jsonb_agg(to_jsonb(f) order by f.id),'[]')::text) from public.spec_facts f) facts,
 (select md5(coalesce(jsonb_agg(jsonb_build_array(p.id,p.spec_revision,p.spec_template_id,p.spec_reference_id) order by p.id),'[]')::text) from public.products p) products,
 (select md5(coalesce(jsonb_agg(to_jsonb(r) order by r.id),'[]')::text) from public.product_spec_references r) references,
 (select md5(coalesce(jsonb_agg(to_jsonb(m) order by m.id),'[]')::text) from public.category_tech_mappings m) category_defaults;
do $publish$
declare doc jsonb; wanted jsonb; actual jsonb;
begin
 select d.doc into doc from nd_publication_document d;
 if md5(pg_get_functiondef(to_regprocedure(
   'public.spec_validate_draft_internal_v1(uuid,jsonb,text,text,text,text)')))
   is distinct from 'ac0738d5c2039412b603dc71adc41721' then
   raise exception 'Unreviewed specification validator';
 end if;
 -- Reject homonymous visible metadata instead of silently shadowing it.
 if exists(select 1 from jsonb_array_elements(doc->'records'->'spec_templates') w
    join public.spec_templates t on t.key=w->>'key' and (t.tenant_id is null or t.tenant_id=(doc->>'audited_tenant_id')::uuid)
    where t.id<>(w->>'id')::uuid)
 or exists(select 1 from jsonb_array_elements(doc->'records'->'spec_definitions') w
    join public.spec_definitions d on d.key=w->>'key' and (d.tenant_id is null or d.tenant_id=(doc->>'audited_tenant_id')::uuid)
    where d.id<>(w->>'id')::uuid) then
   raise exception 'Publication key collision';
 end if;
 {''.join(blocks)}
end $publish$;
set constraints all immediate;
select 1/(case when {assertion_sql(packet)} then 1 else 0 end) as exact_metadata
from nd_publication_document;
select 1/(case when b.facts=(select md5(coalesce(jsonb_agg(to_jsonb(f) order by f.id),'[]')::text) from public.spec_facts f)
 and b.products=(select md5(coalesce(jsonb_agg(jsonb_build_array(p.id,p.spec_revision,p.spec_template_id,p.spec_reference_id) order by p.id),'[]')::text) from public.products p)
 and b.references=(select md5(coalesce(jsonb_agg(to_jsonb(r) order by r.id),'[]')::text) from public.product_spec_references r)
 and b.category_defaults=(select md5(coalesce(jsonb_agg(to_jsonb(m) order by m.id),'[]')::text) from public.category_tech_mappings m)
 then 1 else 0 end) as product_observations_and_identity_unchanged from nd_publication_before b;
commit;
"""


def generate_verifier(packet, cases):
    template_ids = {t['key']: t['id'] for t in packet['records']['spec_templates']}
    executable = [{**c, 'template_id': template_ids[c['template']]}
                  for c in cases['cases']]
    return f"""-- Read-only exact metadata verification; must fail before publication.
with publication(doc) as (values ({sql_json(packet)}))
select 1/(case when {assertion_sql(packet)} then 1 else 0 end) as exact_metadata
from publication;
-- Exercise the deployed validator on synthetic drafts and the real templates.
-- This reads metadata only; it neither creates nor changes a product.
with cases as (select value as c from jsonb_array_elements({sql_json(executable)})),
results as materialized (select c,public.spec_validate_draft_internal_v1(
 (c->>'template_id')::uuid,c->'values') as issues from cases),
checks as (select c->>'id' as id,
 (select coalesce(jsonb_agg(jsonb_build_object('code',i->>'code','field',i->>'field')
  order by i->>'code',i->>'field'),'[]') from jsonb_array_elements(issues) i
  where coalesce((i->>'blocking')::boolean,true)) =
  coalesce(c->'expected_sql_blocking',c->'expected_blocking')
 and (select coalesce(jsonb_agg(jsonb_build_object('code',i->>'code','field',i->>'field',
  'blocking',coalesce((i->>'blocking')::boolean,true))),'[]') from jsonb_array_elements(issues) i)
  @> coalesce(c->'expected_sql_issue_subset',c->'expected_issue_subset','[]')
 and not exists(select 1 from jsonb_array_elements(issues) i
  where i->>'field' in (select jsonb_array_elements_text(coalesce(c->'forbidden_issue_fields','[]')))) as passed
 from results)
select count(*) as representation_cases,1/(case when bool_and(passed) then 1 else 0 end)
 as deployed_behavior_matches from checks;
"""


if __name__ == '__main__':
    packet, subset, cases = compile_packet()
    write_json(RESEARCH / 'non-drivetrain-publication-packet-2026-09-07.json', packet)
    write_json(RESEARCH / 'non-drivetrain-publication-catalog-2026-09-07.json', subset)
    write_json(RESEARCH / 'non-drivetrain-publication-cases-2026-09-07.json', cases)
    (ROOT / f'supabase/migrations/{VERSION}_non_drivetrain_spec_templates.sql').write_text(generate_migration(packet))
    verification = ROOT / 'supabase/manual_checks/verification'
    verification.mkdir(parents=True, exist_ok=True)
    (verification / f'{VERSION}_non_drivetrain_spec_templates.sql').write_text(generate_verifier(packet, cases))
    print(json.dumps({'families': len(packet['families']),
                      'records': {k: len(v) for k, v in packet['records'].items()},
                      'cases': len(cases['cases']), 'product_writes': False}))
