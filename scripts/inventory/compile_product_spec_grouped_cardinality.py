#!/usr/bin/env python3
"""Compile a local-only v3 candidate from immutable, published predecessors.

No migration, connection, catalogue edit or product write is performed here.
"""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]


def replace_once(body, old, new):
    if body.count(old) != 1:
        raise ValueError('Unexpected cardinality predecessor: ' + old[:90])
    return body.replace(old, new)


def functions(path):
    return {m.group(1): m.group(0) for m in re.finditer(
        r'CREATE OR REPLACE FUNCTION public\.(\w+)\(.*?\n;\n', path.read_text(), re.S)}


def compile_sql():
    old = functions(ROOT / 'supabase/migrations/20260907025000_product_spec_row_cardinality.sql')
    applicability = functions(ROOT / 'supabase/migrations/20260907026000_product_spec_cardinality_applicability.sql')
    metadata = old['spec_coherence_metadata_internal_v1']
    metadata = replace_once(metadata, "block->>'version'<>'2'", "block->>'version' not in ('2','3')")
    metadata = replace_once(metadata, "block->'version'='2'::jsonb and (", "block->>'version' in ('2','3') and (")
    start = metadata.index('   -- V2 declares')
    end = metadata.index('   for link in select value', start)
    metadata = metadata[:start] + '''   -- V3 counts each explicit parent independently. A model's alternatives
   -- never inflate a SKU's scalar total or compensate for another parent.
   for cardinality in select value from jsonb_array_elements(coalesce(block->'cardinalities','[]')) loop
     if jsonb_typeof(cardinality) is distinct from 'object' then
       raise exception 'Cardinalidad inválida' using errcode='23514'; end if;
     if cardinality ? 'group_by' then
       if block->>'version'<>'3' or (select count(*) from jsonb_object_keys(cardinality))<>4
         or exists(select 1 from jsonb_object_keys(cardinality) k where k not in ('id','field','group_by','total_column')) then
         raise exception 'Claves de cardinalidad agrupada inválidas' using errcode='23514'; end if;
     elsif (select count(*) from jsonb_object_keys(cardinality))<>3
       or exists(select 1 from jsonb_object_keys(cardinality) k where k not in ('id','field','total_field')) then
       raise exception 'Claves de cardinalidad inválidas' using errcode='23514'; end if;
     for key in select jsonb_object_keys(cardinality) loop
       if jsonb_typeof(cardinality->key) is distinct from 'string'
         or cardinality->>key !~ '^[a-z][a-z0-9_]*$' or cardinality->>key ~ '[[:space:]]' then
         raise exception 'Identificador de cardinalidad inválido' using errcode='23514'; end if;
     end loop;
     source:=p_fields->(cardinality->>'field');
     if cardinality->>'id'=any(ids) or cardinality->>'field'=any(collections)
       or source->>'data_type' is distinct from 'json' or jsonb_typeof(source->'schema') is distinct from 'object' then
       raise exception 'Extremos de cardinalidad no disponibles o duplicados' using errcode='23514'; end if;
     perform public.spec_rows_schema_validate_internal_v1(source->'schema');
     if cardinality ? 'group_by' then
       select l into link from jsonb_array_elements(links) l where l->>'id'=cardinality->>'group_by';
       if link is null or link->>'field' is distinct from cardinality->>'field' then
         raise exception 'La agrupación necesita un vínculo de su propia tabla' using errcode='23514'; end if;
       target:=p_fields->(link->>'target_field');
       select c into col from jsonb_array_elements(target->'schema'->'columns') c where c->>'key'=cardinality->>'total_column';
       if col is null or col->>'type' is distinct from 'integer' then
         raise exception 'El total agrupado necesita una columna entera en su destino' using errcode='23514'; end if;
       rules:=coalesce(col->'validation','{}')||'{"integer":true}'::jsonb;
     else
       target:=p_fields->(cardinality->>'total_field');
       if target->>'data_type' is distinct from 'number' then
         raise exception 'El total necesita un campo numérico' using errcode='23514'; end if;
       rules:=target->'validation_rules';
     end if;
     minimum:=public.spec_rule_number_internal_v1(rules->'min');
     maximum:=public.spec_rule_number_internal_v1(rules->'max');
     if rules->'integer' is distinct from 'true'::jsonb or minimum is null or minimum<0
       or (rules->'max' is not null and rules->'max'<>'null'::jsonb and maximum is null) or minimum>maximum then
       raise exception 'El total de filas necesita un dominio entero no negativo' using errcode='23514'; end if;
     ids:=array_append(ids,cardinality->>'id'); collections:=array_append(collections,cardinality->>'field');
   end loop;
''' + metadata[end:]
    issues = old['spec_coherence_issues_internal_v1']
    issues = replace_once(issues, 'link jsonb; r jsonb; target jsonb;', 'link jsonb; r jsonb; parent jsonb; target jsonb; grouped boolean;')
    issues = replace_once(issues, "c where c->>'field'=key))", "c left join jsonb_array_elements(coalesce(p_contract->'row_coherence'->'links','[]')) l on l->>'id'=c->>'group_by' where c->>'field'=key or l->>'target_field'=key))")
    issues = replace_once(issues, "   target:=parsed->(link->>'target_field');", """   target:=parsed->(link->>'target_field');
   grouped:=exists(select 1 from jsonb_array_elements(coalesce(p_contract->'row_coherence'->'cardinalities','[]')) c where c->>'group_by'=link->>'id');""")
    issues = replace_once(issues, '     if v_cell is null then continue; end if;', """     if grouped and not public.spec_rule_known_internal_v1(v_cell)
       and not exists(select 1 from jsonb_array_elements(coalesce(target->'rows','[]')) t where t->'id'=v_cell) then
       result:=result||jsonb_build_array(jsonb_build_object('code','row_reference_pending','field',link->>'field',
         'row_id',r->>'id','column',link->>'column','message','Falta identificar la configuración de esta fila.','blocking',false));
       continue;
     end if;
     if v_cell is null then continue; end if;""")
    issues = replace_once(issues, '   if field=any(invalid) then continue; end if;', '''   if field=any(invalid) then continue; end if;
   if cardinality ? 'group_by' then
     select l into link from jsonb_array_elements(p_contract->'row_coherence'->'links') l where l->>'id'=cardinality->>'group_by';
     key:=link->>'target_field';
     if key=any(invalid) then continue; end if;
     target:=parsed->key;
     if target is null then
       result:=result||jsonb_build_array(jsonb_build_object('code','row_cardinality_pending','field',key,
         'collection_field',field,'message','Falta documentar la configuración y su total.','blocking',false));
       continue;
     end if;
     for parent in select value from jsonb_array_elements(target->'rows') loop
       total:=public.spec_rule_number_internal_v1(parent->'values'->(cardinality->>'total_column'));
       select count(*) into row_count from jsonb_array_elements(coalesce(parsed->field->'rows','[]')) child
         where child->'values'->(link->>'column')=parent->'id';
       if total=row_count then continue; end if;
       result:=result||jsonb_build_array(jsonb_build_object(
         'code',case when row_count>total then 'row_cardinality_conflict' else 'row_cardinality_pending' end,
         'field',key,'row_id',parent->>'id','column',cardinality->>'total_column','collection_field',field,
         'message',case when total is null then 'Falta confirmar el total de esta configuración.'
           when row_count>total then 'Esta configuración tiene más filas que su total declarado.'
           else 'Faltan filas por documentar en esta configuración.' end,
         'blocking',coalesce(row_count>total,false)));
     end loop;
     continue;
   end if;''')
    guard = old['spec_coherence_publication_guard_internal_v1']
    # Resolve group IDs before comparing meaning. Renaming a label or a link
    # ID together with its referring rule must not reinterpret saved row IDs.
    for label, contract in [('old', 'previous'), ('new', 'new.form_contract')]:
        original = f""" select coalesce(jsonb_agg(c-'id' order by c->>'field',c->>'total_field'),'[]') into {label}_cardinalities
   from jsonb_array_elements(coalesce({contract}->'row_coherence'->'cardinalities','[]')) c;"""
        replacement = f""" select coalesce(jsonb_agg(case when c ? 'group_by' then (c-'id'-'group_by')||jsonb_build_object('group',l-'id'-'label_columns') else c-'id' end order by c->>'field'),'[]') into {label}_cardinalities
   from jsonb_array_elements(coalesce({contract}->'row_coherence'->'cardinalities','[]')) c
   left join jsonb_array_elements(coalesce({contract}->'row_coherence'->'links','[]')) l on l->>'id'=c->>'group_by';"""
        guard = replace_once(guard, original, replacement)
    draft = applicability['spec_validate_draft_internal_v1']
    draft = replace_once(draft, "c->>'field'=any(v_inapplicable)", "(c->>'field'=any(v_inapplicable) or coalesce(c->>'collection_field',c->>'field')=any(v_inapplicable))")
    draft = replace_once(draft, "i->>'field'=c->>'field' and i->>'code'='field_applicability'", "i->>'field' in (c->>'field',c->>'collection_field') and i->>'code'='field_applicability'")
    return '-- LOCAL CANDIDATE ONLY. No template activation, fact or product writes.\n' + '\n'.join([metadata, issues, guard, draft])


if __name__ == '__main__':
    target = ROOT / 'scripts/inventory/sql/product_spec_grouped_cardinality_candidate.sql'
    target.write_text(compile_sql())
    print(target.relative_to(ROOT))
