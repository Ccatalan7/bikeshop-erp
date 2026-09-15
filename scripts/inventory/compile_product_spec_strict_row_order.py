#!/usr/bin/env python3
"""Compile the local v2 row-order extension from its immutable predecessor.

This writes a review candidate, never a deployable migration or catalogue data.
"""
from pathlib import Path
from copy import deepcopy
import json

ROOT = Path(__file__).resolve().parents[2]
PREDECESSOR = ROOT / 'supabase/migrations/20260906190000_product_spec_structured_rows.sql'
TARGET = ROOT / 'scripts/inventory/sql/product_spec_strict_row_order_candidate.sql'


def replace_once(body, old, new):
    if body.count(old) != 1:
        raise ValueError('Row-order predecessor changed: ' + old[:90])
    return body.replace(old, new)


def compile_sql():
    source = PREDECESSOR.read_text()
    start = source.index('create or replace function public.spec_rows_schema_validate_internal_v1(')
    end = source.index('\nend $schema$;', start) + len('\nend $schema$;')
    schema = source[start:end]
    start = source.index('create or replace function public.spec_rows_validate_internal_v1(')
    end = source.index('\nend $rows$;', start) + len('\nend $rows$;')
    rows = source[start:end]
    schema = replace_once(schema, "p_schema->'version' is distinct from '1'::jsonb",
                          "coalesce(p_schema->'version' not in ('1'::jsonb,'2'::jsonb),true)")
    schema = replace_once(schema, "('version','columns','ordered_pairs','unique_by')",
                          "('version','columns','ordered_pairs','strict_ordered_pairs','unique_by')")
    schema = replace_once(schema, " for c in select value from jsonb_array_elements(p_schema->'columns') loop", """ if p_schema ? 'strict_ordered_pairs' and p_schema->'version' is distinct from '2'::jsonb then
   raise exception 'El orden estricto requiere esquema de filas v2' using errcode='22023';
 end if;
 for c in select value from jsonb_array_elements(p_schema->'columns') loop""")
    schema = replace_once(schema, "array['ordered_pairs','unique_by']",
                          "array['ordered_pairs','strict_ordered_pairs','unique_by']")
    if schema.count("k='ordered_pairs'") != 2:
        raise ValueError('Unexpected numeric group checks')
    schema = schema.replace("k='ordered_pairs'", "k in ('ordered_pairs','strict_ordered_pairs')")
    schema = replace_once(schema, """       raise exception 'Relación de columnas inválida' using errcode='22023';
     end if;
   end loop;""", """       raise exception 'Relación de columnas inválida' using errcode='22023';
     end if;
     if k in ('ordered_pairs','strict_ordered_pairs') and
       (select col->>'unit' from jsonb_array_elements(p_schema->'columns') col where col->>'key'=g->>0)
       is distinct from
       (select col->>'unit' from jsonb_array_elements(p_schema->'columns') col where col->>'key'=g->>1) then
       raise exception 'El orden necesita columnas con la misma unidad' using errcode='22023';
     end if;
   end loop;""")
    schema = replace_once(schema, '\nend $schema$;', """
 for g in select value from jsonb_array_elements(coalesce(p_schema->'strict_ordered_pairs','[]')) loop
   if exists(with recursive edges as (
       select x->>0 as a,x->>1 as b from jsonb_array_elements(
         coalesce(p_schema->'ordered_pairs','[]')||coalesce(p_schema->'strict_ordered_pairs','[]')) x
     ), reachable(node) as (
       select g->>1
       union
       select e.b from reachable r join edges e on e.a=r.node
     ) select 1 from reachable where node=g->>0) then
     raise exception 'El esquema de filas contiene órdenes contradictorios' using errcode='22023';
   end if;
 end loop;
end $schema$;""")
    rows = replace_once(rows, "   for g in select value from jsonb_array_elements(coalesce(p_schema->'unique_by','[]')) loop", """   for g in select value from jsonb_array_elements(coalesce(p_schema->'strict_ordered_pairs','[]')) loop
     lo:=public.spec_rule_number_internal_v1(cells->(g->>0));
     hi:=public.spec_rule_number_internal_v1(cells->(g->>1));
     if lo>=hi then raise exception 'La primera cota de fila debe ser menor que la segunda' using errcode='23514'; end if;
   end loop;
   for g in select value from jsonb_array_elements(coalesce(p_schema->'unique_by','[]')) loop""")
    return '-- LOCAL CANDIDATE ONLY. No metadata activation, product writes or new grants.\n' + schema + '\n\n' + rows + '\n'


def compile_fixtures():
    fixture = json.loads((ROOT / 'test/fixtures/product_spec_strict_row_order.json').read_text())
    cases = []
    for entry in fixture['cases']:
        schema = deepcopy(fixture['schema'])
        if entry.get('legacy_schema'):
            schema['version'] = 1
            schema.pop('strict_ordered_pairs')
            schema['ordered_pairs'] = [['inner', 'outer']]
        schema.update(deepcopy(entry.get('schema_set', {})))
        cases.append({'id': entry['id'], 'schema': schema,
            'value': {'schema_version': entry.get('envelope_version', schema['version']),
                      'rows': [{'id': f'piece-{i}', 'values': values, 'sources': []}
                               for i, values in enumerate(entry['values'])]},
            'valid': entry['valid'], 'missing_required': entry.get('missing_required')})
    invalid = []
    for entry in fixture['invalid_schemas']:
        schema = {**deepcopy(fixture['schema']), **entry['set']}
        for key in entry.get('remove', []):
            schema.pop(key)
        invalid.append({'id': entry['id'], 'schema': schema})
    def sql_json(value):
        return "'" + json.dumps(value, ensure_ascii=False).replace("'", "''") + "'::jsonb"
    lines = ['-- Generated from test/fixtures/product_spec_strict_row_order.json.']
    lines += ['insert into strict_order_cases values (' + sql_json(case) + ');' for case in cases]
    lines += ['insert into strict_order_invalid_schemas values (' + sql_json(case) + ');' for case in invalid]
    return '\n'.join(lines) + '\n'


if __name__ == '__main__':
    TARGET.write_text(compile_sql())
    (ROOT / 'supabase/tests/fixtures/product_spec_strict_row_order_cases.sql').write_text(compile_fixtures())
    print(TARGET.relative_to(ROOT))
