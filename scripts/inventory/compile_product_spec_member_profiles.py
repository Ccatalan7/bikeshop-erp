#!/usr/bin/env python3
"""Generate the scoped-observation extension from reviewed live predecessors.

No catalog activation or product filling. Root and members share the existing
typed writer, exact reader, draft validator and atomic save implementation.
"""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SQL = ROOT / 'scripts/inventory/sql'
TARGET = SQL / 'product_spec_member_profiles_candidate.sql'
EXPECTED = {
    'get_product_spec_editor_context_v2': 'ffc95bc18f46105a9b7dc3a702e485a6',
    'save_product_with_specs_v1': '007ed3a67a009527c24ed54ee3380b99',
    'spec_product_payload_internal_v1': 'a353807af49f812d0b349fbc6f112c4c',
    'spec_template_product_payload_internal_v1': 'a56ef26e739ff4b3687d9f07f9065cb0',
    'spec_validate_product_internal_v1': '6f8f676f03241a5f68a10b3d9b152272',
    'spec_write_payload_internal_v2': '4000850abcb96fe223f1df53584eadfb',
}


def once(body, old, new):
    if body.count(old) != 1:
        raise ValueError('Member profile predecessor changed: ' + old[:100])
    return body.replace(old, new)


def wrapper(signature, returns, expression, *, stable=False, definer=False):
    return (f'create or replace function public.{signature}\nreturns {returns} '
            f'language sql {"stable " if stable else ""}'
            f'{"security definer " if definer else ""}'
            f'set search_path=pg_catalog,public,pg_temp as $$\n select {expression}\n$$;\n')


def compile_sql():
    source = json.loads((SQL / 'product_spec_member_profile_predecessors.json').read_text())
    bodies = {}
    for item in source['functions']:
        actual = hashlib.md5(item['body'].encode()).hexdigest()
        if item['name'] not in EXPECTED or actual != EXPECTED[item['name']] or actual != item['md5']:
            raise ValueError('Unreviewed predecessor: ' + item['name'])
        bodies[item['name']] = item['body']
    if bodies.keys() != EXPECTED.keys():
        raise ValueError('Missing predecessor')

    payload = bodies['spec_product_payload_internal_v1']
    payload = once(payload, 'spec_product_payload_internal_v1(p_product_id uuid)',
                   'spec_product_scope_payload_internal_v1(p_product_id uuid, p_scope text)')
    payload = once(payload, 'f.subject_scope is null', 'f.subject_scope is not distinct from p_scope')

    template_payload = bodies['spec_template_product_payload_internal_v1']
    template_payload = once(template_payload,
        'spec_template_product_payload_internal_v1(p_product_id uuid, p_template_id uuid, p_include_legacy boolean)',
        'spec_template_product_scope_payload_internal_v1(p_product_id uuid, p_template_id uuid, p_include_legacy boolean, p_scope text)')
    template_payload = once(template_payload, 'public.spec_product_payload_internal_v1(p_product_id)',
                            'public.spec_product_scope_payload_internal_v1(p_product_id,p_scope)')

    writer = bodies['spec_write_payload_internal_v2']
    writer = once(writer, 'spec_write_payload_internal_v2(p_product_id uuid, p_template_id uuid, p_values jsonb, p_reference_id text)',
                  'spec_write_scope_payload_internal_v1(p_product_id uuid, p_template_id uuid, p_values jsonb, p_reference_id text, p_scope text)')
    writer = once(writer, 'v_old:=public.spec_product_payload_internal_v1(p_product_id);',
                  'v_old:=public.spec_product_scope_payload_internal_v1(p_product_id,p_scope);')
    if writer.count('f.subject_scope is null') != 2:
        raise ValueError('Unexpected writer scope filters')
    writer = writer.replace('f.subject_scope is null', 'f.subject_scope is not distinct from p_scope')
    writer = once(writer, 'insert into public.spec_facts (tenant_id,subject_type,subject_id,spec_definition_id,',
                  'insert into public.spec_facts (tenant_id,subject_type,subject_id,subject_scope,spec_definition_id,')
    writer = once(writer, "values (v_tenant,'product',p_product_id,v_def.id,",
                  "values (v_tenant,'product',p_product_id,p_scope,v_def.id,")

    editor = bodies['get_product_spec_editor_context_v2']
    start = editor.index('   select jsonb_build_object')
    end = editor.index('\n end if;', start)
    editor_template = ('create or replace function public.spec_template_editor_internal_v1(template_id uuid,tenant uuid)\n'
        'returns jsonb language plpgsql stable set search_path=pg_catalog,public,pg_temp as $$\n'
        '#variable_conflict use_variable\n'
        'declare template jsonb; fields jsonb;\nbegin\n' + editor[start:end] + '\n return template;\nend $$;\n')
    editor = editor[:start] + '   template:=public.spec_template_editor_internal_v1(template_id,tenant);' + editor[end:]

    validator = bodies['spec_validate_product_internal_v1']
    shape_start = validator.index('  if exists(select 1 from public.spec_facts')
    shape_end = validator.index('\n  if v_product.spec_reference_id', shape_start)
    shape = validator[shape_start:shape_end].replace('f.subject_scope is null', 'f.subject_scope is not distinct from p_scope')
    shape_validator = ('create or replace function public.spec_validate_product_fact_shape_internal_v1(p_product_id uuid,p_scope text)\n'
        'returns void language plpgsql stable set search_path=pg_catalog,public,pg_temp as $$\nbegin\n'
        + shape + '\nend $$;\n')
    validator = validator[:shape_start] + '  perform public.spec_validate_product_fact_shape_internal_v1(p_product_id,null);' + validator[shape_end:]
    validator = once(validator, '  if not found then return; end if;',
        '  if not found then return; end if;\n  perform public.spec_validate_product_member_profiles_internal_v1(p_product_id);')

    saver = bodies['save_product_with_specs_v1']
    v1_signature = saver.split('\n')[0].removeprefix('CREATE OR REPLACE FUNCTION public.')
    saver = once(saver, 'save_product_with_specs_v1(', 'spec_save_product_with_specs_internal_v2(')
    saver = once(saver, 'p_components jsonb DEFAULT NULL::jsonb)',
                  'p_components jsonb, p_member_profiles jsonb, p_protocol integer)')
    saver = once(saver, '  if p_is_new is null', '''  if p_protocol not in (1,2) or p_protocol is null
    or (p_protocol=1 and p_member_profiles is not null)
    or (p_protocol=2 and jsonb_typeof(p_member_profiles) is distinct from 'object') then
    raise exception 'Invalid specification save protocol' using errcode='22023';
  end if;
  if p_is_new is null''')
    saver = once(saver, "    'reference',p_reference_id,'components',p_components)::text);", """    'reference',p_reference_id,'components',p_components)::text);
  -- v1 hashes remain byte-identical so existing retries keep their receipt.
  -- The v2 protocol hashes the entire member command before reading a receipt.
  if p_protocol=2 then
    v_hash:=md5(jsonb_build_object('protocol',2,'root_hash',v_hash,'member_profiles',p_member_profiles)::text);
  end if;""")
    saver = once(saver, '  perform public.spec_validate_product_internal_v1(v_id);', '''  if p_protocol=2 then
    perform public.spec_apply_member_profiles_internal_v1(v_id,p_member_profiles);
  end if;
  perform public.spec_validate_product_internal_v1(v_id);''')
    saver = once(saver, "  insert into public.product_spec_save_receipts(tenant_id,operation_key,request_hash,result)", """  if p_protocol=2 then
    v_result:=v_result||jsonb_build_object('member_profiles',public.get_product_spec_member_profiles_v1(v_id),
      'editor_context',public.get_product_spec_editor_context_v3(v_id,
        (select category_id from public.products where id=v_id)));
  end if;
  insert into public.product_spec_save_receipts(tenant_id,operation_key,request_hash,result)""")
    call = ('public.spec_save_product_with_specs_internal_v2(p_product,p_is_new,p_template_id,p_contract_version,'
            'p_values,p_expected_revision,p_reference_id,p_operation_key,p_expected_updated_at,p_components,')
    v2_signature = v1_signature.replace('save_product_with_specs_v1(', 'save_product_with_specs_v2(').replace(
        'p_components jsonb DEFAULT NULL::jsonb)', 'p_member_profiles jsonb, p_components jsonb DEFAULT NULL::jsonb)')

    core = (SQL / 'product_spec_member_profiles_core.sql').read_text()
    statements = [payload, template_payload, writer, editor_template, shape_validator, core,
        wrapper('spec_product_payload_internal_v1(p_product_id uuid)', 'jsonb',
                'public.spec_product_scope_payload_internal_v1(p_product_id,null)', stable=True),
        wrapper('spec_template_product_payload_internal_v1(p_product_id uuid,p_template_id uuid,p_include_legacy boolean)',
                'jsonb', 'public.spec_template_product_scope_payload_internal_v1(p_product_id,p_template_id,p_include_legacy,null)', stable=True),
        wrapper('spec_write_payload_internal_v2(p_product_id uuid,p_template_id uuid,p_values jsonb,p_reference_id text)',
                'integer', 'public.spec_write_scope_payload_internal_v1(p_product_id,p_template_id,p_values,p_reference_id,null)', definer=True),
        editor, validator, saver,
        wrapper(v1_signature, 'jsonb', call+'null,1)', definer=True),
        wrapper(v2_signature, 'jsonb', call+'p_member_profiles,2)', definer=True),
    ]
    # No implicit PUBLIC execute on any newly created function, including
    # trigger functions. Public RPCs receive only the existing authenticated role.
    grant_sql = '''
do $acl$
declare fn record;
begin
 for fn in select p.oid::regprocedure as signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname=any(array[
     'spec_product_scope_payload_internal_v1','spec_template_product_scope_payload_internal_v1',
     'spec_write_scope_payload_internal_v1','spec_template_editor_internal_v1',
     'spec_validate_product_fact_shape_internal_v1','spec_member_collection_contract_internal_v1',
     'spec_member_identity_enrichment_internal_v1',
     'spec_member_graph_touch_internal_v1',
     'spec_member_event_immutable_internal_v1','spec_member_category_constraint_internal_v1',
     'spec_member_reading_revision_internal_v1',
     'spec_member_binding_internal_v1','spec_member_profile_issues_internal_v1',
     'spec_validate_product_member_profiles_internal_v1','spec_member_profile_guard_internal_v1',
     'spec_member_profile_revision_internal_v1','spec_member_profile_constraint_internal_v1',
     'spec_member_metadata_constraint_internal_v1','get_product_spec_member_template_v1',
     'spec_member_fact_guard_internal_v1','spec_apply_member_profiles_internal_v1',
     'spec_save_product_with_specs_internal_v2','get_product_spec_member_profiles_v1',
     'get_product_spec_research_snapshot_v2',
     'get_product_spec_editor_context_v3','save_product_with_specs_v2']) loop
   execute format('revoke all on function %s from public,anon,authenticated',fn.signature);
 end loop;
end $acl$;
grant execute on function public.get_product_spec_member_profiles_v1(uuid),
 public.get_product_spec_editor_context_v3(uuid,uuid),
 public.get_product_spec_member_template_v1(uuid,uuid,text),
 public.get_product_spec_research_snapshot_v2(uuid),
 public.save_product_with_specs_v2(jsonb,boolean,uuid,integer,jsonb,bigint,text,text,timestamptz,jsonb,jsonb)
 to authenticated;
'''
    statements = [s.rstrip() if s.rstrip().endswith(';') else s.rstrip()+';' for s in statements]
    return '-- REVIEW CANDIDATE. No template activation or product filling.\n' + '\n'.join(statements) + grant_sql


if __name__ == '__main__':
    TARGET.write_text(compile_sql())
    print(TARGET.relative_to(ROOT))
