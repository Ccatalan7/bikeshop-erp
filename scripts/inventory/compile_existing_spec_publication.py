#!/usr/bin/env python3
"""Prepare reviewed forward metadata updates without changing observations.

Existing templates and field identities are preserved. Shared definitions are
immutable inputs. Execution requires a separately reviewed migration, fresh
preimage, population audit and backup; this module never executes SQL.
"""
from copy import deepcopy
import hashlib
import json

from compile_non_drivetrain_publication import (
    TABLES, TENANT, assertion_sql, generate_migration as new_metadata_migration,
    generate_verifier, metadata_records, sql_json)
from compile_product_spec_catalog import validate_contract

EDITABLE_FIELD = tuple(k for k in TABLES['spec_template_fields'] if k not in
                       ('id', 'tenant_id', 'template_id', 'spec_definition_id'))


def load_pinned(path, expected):
    if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
        raise ValueError('Reviewed input changed: ' + str(path))
    return json.loads(path.read_text())


def preimage_query(catalog, families):
    """Capture actual IDs, definitions and effective bindings, never just FKs."""
    families = set(families)
    selected = [t for t in catalog['templates'] if t['key'] in families]
    if len(selected) != len(families) or not families:
        raise ValueError('Preimage requires an exact nonempty family set')
    keys = {f['key'] for t in selected for f in t['fields']}
    quoted = lambda values: ','.join("'" + str(v).replace("'", "''") + "'"
                                     for v in sorted(values))
    return f"""with selected as (
 select t.* from public.spec_templates t
 where (t.tenant_id is null or t.tenant_id='{TENANT}')
 and t.key=any(array[{quoted(families)}]::text[])),
fields as (select f.* from public.spec_template_fields f
 where f.template_id in (select id from selected)),
definitions as (select d.* from public.spec_definitions d
 where (d.tenant_id is null or d.tenant_id='{TENANT}')
 and (d.key=any(array[{quoted(keys)}]::text[])
 or d.id in (select spec_definition_id from fields)))
select jsonb_build_object('tenant_id','{TENANT}',
 'captured_at',transaction_timestamp(),
 'templates',(select coalesce(jsonb_agg(to_jsonb(t) order by t.key,t.id),'[]') from selected t),
 'fields',(select coalesce(jsonb_agg(to_jsonb(f) order by f.id),'[]') from fields f),
 'existing_definitions',(select coalesce(jsonb_agg(to_jsonb(d)||jsonb_build_object('options',
   (select coalesce(jsonb_agg(to_jsonb(v) order by v.id),'[]')
    from public.spec_definition_values v where v.spec_definition_id=d.id)) order by d.key,d.id),'[]')
    from definitions d),
 'effective_bindings',(select coalesce(jsonb_object_agg(key,n),'{{}}') from (
   select t.key,count(b.product_id) n from selected t
   left join public.product_spec_bindings_internal_v1 b on b.template_id=t.id
   and b.tenant_id='{TENANT}' group by t.key) x),
 'explicit_bindings',(select coalesce(jsonb_object_agg(key,n),'{{}}') from (
   select t.key,count(p.id) n from selected t left join public.products p
   on p.spec_template_id=t.id and p.tenant_id='{TENANT}' group by t.key) x)
) as metadata;
"""


def compile_packet(*, catalog, cases, before, families, hashes, adjudication):
    """Keep full preimages and compute the exact monotonic contract revision.

    The caller owns source/domain adjudication. A green compiler cannot supply
    that review or turn historical ``origin`` labels into current DB state.
    """
    templates, definitions = catalog['templates'], catalog['definitions']
    used_keys = {f['key'] for t in templates for f in t['fields']}
    if set(definitions) != used_keys:
        raise ValueError('Only definitions used by the reviewed templates belong here')
    if (before['tenant_id'] != TENANT or not families or
            {t['key'] for t in templates} != set(families) or
            len(templates) != len(families)):
        raise ValueError('Explicit existing-template scope required')
    old_templates = {t['key']: t for t in before['templates']}
    if (len(old_templates) != len(before['templates']) or
            set(old_templates) != set(families)):
        raise ValueError('Missing or ambiguous existing template preimage')
    ids = {t['id'] for t in before['templates']}
    old_fields = {(f['template_id'], f['spec_definition_id']): f
                  for f in before['fields']}
    if (len(old_fields) != len(before['fields']) or
            any(f['template_id'] not in ids or f['tenant_id'] is not None
                for f in before['fields'])):
        raise ValueError('Unexpected existing field scope')
    reused = {d['key']: d for d in before['existing_definitions']}
    if (len(reused) != len(before['existing_definitions']) or
            not set(reused) <= set(definitions)):
        raise ValueError('Ambiguous or out-of-scope shared definition')
    if not {k for k, d in definitions.items() if d['origin'] == 'existing'} <= set(reused):
        raise ValueError('Existing definitions require a live preimage')
    definition_ids = {d['id'] for d in reused.values()}
    if any(f['spec_definition_id'] not in definition_ids for f in before['fields']):
        raise ValueError('Existing observations cannot lose their field definition')
    for key, actual in reused.items():
        if actual['tenant_id'] is not None or any(actual[c] != definitions[key][c]
                for c in ('id', 'key', 'label', 'data_type', 'unit',
                          'allowed_values', 'validation_rules')):
            raise ValueError('Shared definition must remain unchanged: ' + key)
        if any(v['tenant_id'] is not None or not v['is_active']
               for v in actual['options']):
            raise ValueError('Shared option scope or state changed')
    for t in templates:
        old = old_templates[t['key']]
        if (old['tenant_id'] is not None or not old['is_active'] or
                (t['id'], t['technical_family']) !=
                (old['id'], old['technical_family'])):
            raise ValueError('Template identity, family and activation are immutable here')
        # This publisher owns the contract and field uses. A proposed rename
        # or activation must never disappear silently during packet assembly.
        # Missing optional attributes mean preserve; explicit changes fail.
        for attribute in ('name', 'description', 'default_tags', 'is_active',
                          'tenant_id', 'created_at', 'updated_at', 'contract_version'):
            if attribute in t and json.dumps(t[attribute], sort_keys=True) != json.dumps(
                    old[attribute], sort_keys=True):
                raise ValueError('Unsupported template metadata change: ' + attribute)
        validate_contract(t['key'], t['form_contract'], definitions,
                          {f['key'] for f in t['fields']})
    if cases['catalogue_sha256'] != hashes['catalog_sha256'] or any(
            c['template'] not in families for c in cases['cases']):
        raise ValueError('Cases must belong to the exact reviewed catalogue')
    if not adjudication:
        raise ValueError('Domain adjudication must be explicit')
    records = metadata_records(templates, definitions, set(reused))
    generated_pairs = {(f['template_id'], f['spec_definition_id'])
                       for f in records['spec_template_fields']}
    if not set(old_fields) <= generated_pairs:
        raise ValueError('Retire existing fields explicitly; never remove observations')
    patches, field_revisions, desired_fields = [], {}, []
    for wanted in records['spec_template_fields']:
        pair = (wanted['template_id'], wanted['spec_definition_id'])
        old = old_fields.get(pair)
        if old is None:
            field_revisions[pair[0]] = field_revisions.get(pair[0], 0) + 1
            desired_fields.append(wanted)
            continue
        after = {**deepcopy(old), **{k: wanted[k] for k in EDITABLE_FIELD}}
        after.pop('updated_at', None)
        if any(old[k] != after[k] for k in EDITABLE_FIELD):
            patches.append({'table': 'spec_template_fields',
                            'before': deepcopy(old), 'after': after})
            field_revisions[pair[0]] = field_revisions.get(pair[0], 0) + 1
        desired_fields.append(after)
    desired_templates = []
    for t in templates:
        old = old_templates[t['key']]
        after = {**deepcopy(old), 'form_contract': deepcopy(t['form_contract'])}
        after.pop('updated_at', None)
        changed = old['form_contract'] != after['form_contract']
        after['contract_version'] = (old['contract_version'] + int(changed) +
                                     field_revisions.get(t['id'], 0))
        desired_templates.append(after)
        if changed:
            patches.append({'table': 'spec_templates',
                            'before': deepcopy(old), 'after': after})
    records['spec_templates'] = desired_templates
    records['spec_template_fields'] = desired_fields
    return {
        'schema_version': 2, 'scope': 'existing_global_metadata_forward_only',
        'audited_tenant_id': TENANT, **hashes, 'families': list(families),
        'reused_definitions': list(reused.values()), 'records': records,
        'before': {'spec_templates': before['templates'],
                   'spec_template_fields': before['fields']},
        'patches': patches, 'adjudication': adjudication,
        'product_writes': False, 'fill_allowed': False,
        'mechanical_approval': False,
    }


def before_assertion_sql():
    checks = []
    for table in ('spec_templates', 'spec_template_fields'):
        checks.append(f"""not exists (
 select 1 from jsonb_array_elements(doc->'before'->'{table}') wanted
 left join public.{table} actual on actual.id=(wanted->>'id')::uuid
 where actual.id is null or to_jsonb(actual) is distinct from wanted)""")
    checks.append("""not exists (select 1 from public.spec_template_fields actual
 where actual.template_id in (select (t->>'id')::uuid
 from jsonb_array_elements(doc->'before'->'spec_templates') t)
 and actual.id not in (select (f->>'id')::uuid
 from jsonb_array_elements(doc->'before'->'spec_template_fields') f))""")
    checks.append("""not exists (select 1
 from jsonb_array_elements(doc->'records'->'spec_template_fields') wanted
 join public.spec_template_fields actual on actual.id=(wanted->>'id')::uuid
 where wanted->>'id' not in (select f->>'id'
 from jsonb_array_elements(doc->'before'->'spec_template_fields') f))""")
    return ' and\n'.join('(' + c + ')' for c in checks)


def generate_migration(packet, *, source_sha):
    if packet.get('scope') != 'existing_global_metadata_forward_only':
        raise ValueError('Wrong publisher for this scope')
    # Reuse the proven locks, business fingerprint and exact postconditions.
    # Fail loudly if the owner's framing changes; never guess SQL boundaries.
    framed = new_metadata_migration(packet, source_sha=source_sha)
    if framed.count('do $publish$') != 1 or framed.count('end $publish$;') != 1:
        raise ValueError('New-metadata publisher framing changed')
    prefix, rest = framed.split('do $publish$', 1)
    _, suffix = rest.split('end $publish$;', 1)
    prefix = prefix[prefix.index('begin isolation level repeatable read;'):]
    inserts = []
    for table in ('spec_definitions', 'spec_definition_values'):
        columns = ','.join(TABLES[table])
        inserts.append(f"""
 for v_wanted in select value from jsonb_array_elements(doc->'records'->'{table}') loop
   select to_jsonb(t) into v_actual from public.{table} t where id=(v_wanted->>'id')::uuid;
   if found then
     raise exception 'Forward publication new-record collision in {table}: %',v_wanted->>'id';
   end if;
   insert into public.{table}({columns})
   select {columns} from jsonb_populate_record(null::public.{table},v_wanted);
 end loop;""")
    field_columns = ','.join(TABLES['spec_template_fields'])
    patch_columns = ','.join(EDITABLE_FIELD)
    return f"""-- Reviewed existing-template metadata update; identity and observations preserved.
-- Source SHA-256: {source_sha}
-- Exact preimage or exact replay only; no schema/fact/assignment repair here.
-- Recovery needs a new reviewed forward packet against the then-current state.
{prefix}
do $publish$
declare doc jsonb; v_wanted jsonb; v_actual jsonb; patch jsonb;
begin
 select d.doc into doc from nd_publication_document d;
 if md5(pg_get_functiondef(to_regprocedure(
   'public.spec_validate_draft_internal_v1(uuid,jsonb,text,text,text,text)')))
   is distinct from 'ac0738d5c2039412b603dc71adc41721' then
   raise exception 'Unreviewed specification validator';
 end if;
 if exists(select 1 from jsonb_array_elements(doc->'records'->'spec_templates') w
    join public.spec_templates t on t.key=w->>'key'
    and (t.tenant_id is null or t.tenant_id=(doc->>'audited_tenant_id')::uuid)
    where t.id<>(w->>'id')::uuid)
 or exists(select 1 from jsonb_array_elements(doc->'records'->'spec_definitions') w
    join public.spec_definitions d on d.key=w->>'key'
    and (d.tenant_id is null or d.tenant_id=(doc->>'audited_tenant_id')::uuid)
    where d.id<>(w->>'id')::uuid) then
   raise exception 'Publication key collision';
 end if;
 if exists(select 1 from jsonb_array_elements(doc->'reused_definitions') wanted
   left join public.spec_definitions actual on actual.id=(wanted->>'id')::uuid
   where actual.id is null or to_jsonb(actual) is distinct from wanted-'options'
   or (select coalesce(jsonb_agg(to_jsonb(v) order by v.id),'[]')
       from public.spec_definition_values v where v.spec_definition_id=actual.id)
      is distinct from wanted->'options') then
   raise exception 'Forward publication shared-definition drift';
 end if;
 if ({assertion_sql(packet)}) then
   return; -- Exact replay must not increment any revision.
 end if;
 if not ({before_assertion_sql()}) then
   raise exception 'Forward publication preimage drift';
 end if;
 {''.join(inserts)}
 -- Template first, then changed/new fields. Each real edit bumps the native
 -- revision once; unchanged fields never receive an UPDATE.
 for patch in select value from jsonb_array_elements(doc->'patches')
     where value->>'table'='spec_templates' loop
   update public.spec_templates set form_contract=patch->'after'->'form_contract'
   where id=(patch->'before'->>'id')::uuid;
 end loop;
 for patch in select value from jsonb_array_elements(doc->'patches')
     where value->>'table'='spec_template_fields' loop
   update public.spec_template_fields set ({patch_columns})=(
     select {patch_columns} from jsonb_populate_record(
       null::public.spec_template_fields,patch->'after'))
   where id=(patch->'before'->>'id')::uuid;
 end loop;
 for v_wanted in select value from jsonb_array_elements(doc->'records'->'spec_template_fields')
     where value->>'id' not in (select f->>'id'
       from jsonb_array_elements(doc->'before'->'spec_template_fields') f) loop
   insert into public.spec_template_fields({field_columns})
   select {field_columns} from jsonb_populate_record(null::public.spec_template_fields,v_wanted);
 end loop;
end $publish$;
{suffix}"""
