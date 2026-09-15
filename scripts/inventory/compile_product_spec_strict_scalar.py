#!/usr/bin/env python3
"""Compile the bounded < scalar-pair extension from reviewed live functions.

Two-item pairs retain <=. An explicit third item "lt" forbids equality;
older validators reject this grammar rather than silently accepting equality.
This produces a local candidate only, with no metadata or product writes.
"""
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
PREIMAGE = ROOT / 'docs/development/product-specs-research-2026-09-05/strict-scalar-preimage-2026-09-15.json'
EXPECTED = {
    'spec_coherence_issues_internal_v1': 'd57404a97c12b336e64b59202b3d56f4',
    'spec_coherence_metadata_internal_v1': '62b9c8349bf9d4fa4f983d3009980171',
    'spec_coherence_pairs_internal_v1': 'f8f1df3554fcb19199e1c62e55164a65',
    'spec_coherence_publication_guard_internal_v1': '235850d2afe7e1571431c7f7c4942b7b',
}


def replace_once(body, old, new):
    if body.count(old) != 1:
        raise ValueError('Review the live scalar-order function before patching it')
    return body.replace(old, new)


def compile_candidate(path=PREIMAGE):
    rows = json.loads(path.read_text())[0]['metadata']
    functions = {f['signature'].split('(')[0]: f for f in rows}
    if set(functions) != set(EXPECTED) or len(rows) != 4:
        raise ValueError('The candidate owns exactly four existing functions')
    for name, f in functions.items():
        if (f['md5'] != EXPECTED[name] or
                hashlib.md5(f['definition'].encode()).hexdigest() != f['md5']):
            raise ValueError('Unreviewed live predecessor: ' + name)
    bodies = {name: f['definition'] for name, f in functions.items()}
    k = 'spec_coherence_metadata_internal_v1'
    bodies[k] = replace_once(bodies[k],
        "jsonb_array_length(pair)<>2 or pair->0=pair->1 or pair::text=any(seen)",
        "not (jsonb_array_length(pair)=2 or (jsonb_array_length(pair)=3 and pair->2='\"lt\"'::jsonb))\n"
        "       or pair->0=pair->1 or jsonb_build_array(pair->0,pair->1)::text=any(seen)")
    bodies[k] = replace_once(bodies[k],
        'from jsonb_array_elements(pair) k where',
        'from jsonb_array_elements(jsonb_build_array(pair->0,pair->1)) k where')
    bodies[k] = replace_once(bodies[k],
        'seen:=array_append(seen,pair::text);',
        'seen:=array_append(seen,jsonb_build_array(pair->0,pair->1)::text);')
    k = 'spec_coherence_pairs_internal_v1'
    bodies[k] = replace_once(bodies[k],
        "and (p_fields->(pair->>0)->'unit') is not distinct from (p_fields->(pair->>1)->'unit')",
        "and (p_fields->(pair->>0)->'unit') is not distinct from (p_fields->(pair->>1)->'unit')\n"
        "       and not exists(select 1 from jsonb_array_elements(coalesce(p_contract->'scalar_ordered_pairs','[]')) declared\n"
        "         where declared->0=pair->0 and declared->1=pair->1)")
    k = 'spec_coherence_issues_internal_v1'
    bodies[k] = replace_once(bodies[k],
        "if public.spec_rule_number_internal_v1(p_values->(pair->>0)) > public.spec_rule_number_internal_v1(p_values->(pair->>1)) then\n"
        '     for field in select jsonb_array_elements_text(pair) loop',
        "if public.spec_rule_number_internal_v1(p_values->(pair->>0)) > public.spec_rule_number_internal_v1(p_values->(pair->>1))\n"
        "     or (pair->>2='lt' and public.spec_rule_number_internal_v1(p_values->(pair->>0)) = public.spec_rule_number_internal_v1(p_values->(pair->>1))) then\n"
        '     for field in select jsonb_array_elements_text(jsonb_build_array(pair->0,pair->1)) loop')
    bodies[k] = replace_once(bodies[k],
        "'message','El límite inferior no puede superar el superior.','blocking',true)",
        "'message',case when pair->>2='lt' then 'La primera medida debe ser menor que la segunda.'\n"
        "           else 'El límite inferior no puede superar el superior.' end,'blocking',true)")
    k = 'spec_coherence_publication_guard_internal_v1'
    bodies[k] = replace_once(bodies[k],
        'union select jsonb_array_elements_text(pair) from jsonb_array_elements',
        'union select jsonb_array_elements_text(jsonb_build_array(pair->0,pair->1)) from jsonb_array_elements')
    return rows, bodies


def main():
    before, bodies = compile_candidate(Path(sys.argv[1]) if len(sys.argv) > 1 else PREIMAGE)
    out = ROOT / 'scripts/inventory/sql/product_spec_strict_scalar_candidate.sql'
    out.write_text('-- Candidate only: no metadata, grants or facts are changed.\n' +
                   '\n;\n'.join(bodies[k] for k in sorted(bodies)) + '\n;\n')
    print(json.dumps({'functions': len(bodies), 'candidate': str(out.relative_to(ROOT)),
                      'sha256': hashlib.sha256(out.read_bytes()).hexdigest(),
                      'applied': False, 'fills': 0}))


if __name__ == '__main__':
    main()
