#!/usr/bin/env python3
"""Local two-connection publication regression for total-only observations.

Reuse the reviewed transaction schedules and cleanup owner. Only their metadata
and observed endpoint change: writers populate a numeric total, while the rows
endpoint stays empty. Every rewrite is asserted so fixture drift fails closed.
"""
import re

import test_product_spec_publication_concurrency as runner


def replace_once(text, before, after):
    if text.count(before) != 1:
        raise ValueError(f"Expected one fixture anchor: {before[:70]}")
    return text.replace(before, after)


def main():
    output = runner.ROOT / '.tmp/product-spec-cardinality-concurrency'
    fixtures = output / 'fixtures'
    fixtures.mkdir(parents=True, exist_ok=True)
    original = runner.FIXTURES
    condition = '''jsonb_build_object('version',1,'fields',jsonb_build_object(p_field,
    '{"allowed_when":{"detail":{"kind":"when","rows":[[{"field":"flag","operator":"eq","value_type":"boolean","value":true}]]}}}'::jsonb))'''
    cardinality = """jsonb_build_object('version',2,'links','[]'::jsonb,
      'cardinalities',jsonb_build_array(jsonb_build_object(
        'id','observed_occurrences','field',p_field,'total_field',p_field||'_total')))"""
    totals = """
insert into public.spec_definitions(id,key,label,data_type,validation_rules)
select id::uuid,key,key,'number','{"integer":true,"min":0}'::jsonb
from (values
 ('c0bf0000-0000-4000-8000-000000000031','row_race_product_configs_total'),
 ('c0bf0000-0000-4000-8000-000000000032','row_race_reference_configs_total'),
 ('c0bf0000-0000-4000-8000-000000000033','row_race_new_configs_total')) d(id,key);
"""
    fields = """
insert into public.spec_template_fields(template_id,spec_definition_id,section_key,sort_order)
values
 ('c0bf0000-0000-4000-8000-000000000050','c0bf0000-0000-4000-8000-000000000031','measurement',2),
 ('c0bf0000-0000-4000-8000-000000000051','c0bf0000-0000-4000-8000-000000000032','measurement',2),
 ('c0bf0000-0000-4000-8000-000000000052','c0bf0000-0000-4000-8000-000000000033','measurement',2);
"""
    for suffix in ('', '-reverse'):
        name = f'row-conditions-review-concurrency{suffix}.sql'
        text = (original / name).read_text()
        text = replace_once(text, 'insert into public.spec_templates(', totals + '\ninsert into public.spec_templates(')
        text = replace_once(text, "jsonb_build_object(field,'measurement')", "jsonb_build_object(field,'measurement',field||'_total','measurement')")
        text = replace_once(text, 'insert into public.product_categories(', fields + '\ninsert into public.product_categories(')
        # Normalize only whitespace around this exact known expression.
        pattern = r'\s*'.join(re.escape(token) for token in condition.split())
        text, count = re.subn(pattern, lambda _: cardinality, text)
        if count != 1:
            raise ValueError(f'Expected one condition expression in {name}: {count}')
        text = text.replace("'row_conditions'", "'row_coherence'")
        for old, new in (('011', '031'), ('012', '032'), ('013', '033')):
            before = ('{"c0bf0000-0000-4000-8000-000000000' + old + '":{"rows":'
                      '{"schema_version":1,"rows":[{"id":"a","values":{"flag":false,'
                      '"detail":"Observed under prior contract"},"sources":'
                      '["https://example.test/row-race"]}]}}}')
            after = '{"c0bf0000-0000-4000-8000-000000000' + new + '":{"number":"0"}}'
            text = replace_once(text, before, after)
        (fixtures / name).write_text('-- GENERATED total-only cardinality race; local only.\n' + text)
    name = 'row-conditions-review-concurrency-cleanup.sql'
    cleanup = (original / name).read_text()
    anchor = "'c0bf0000-0000-4000-8000-000000000013'"
    if cleanup.count(anchor) != 2:
        raise ValueError('Cleanup definition anchors changed')
    cleanup = cleanup.replace(anchor, anchor + ",\n    'c0bf0000-0000-4000-8000-000000000031','c0bf0000-0000-4000-8000-000000000032','c0bf0000-0000-4000-8000-000000000033'")
    (fixtures / name).write_text(cleanup)
    runner.FIXTURES = fixtures
    runner.OUTPUT = output
    runner.main()


if __name__ == '__main__':
    main()
