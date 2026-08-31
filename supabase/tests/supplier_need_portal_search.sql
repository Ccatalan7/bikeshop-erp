begin;

select no_plan();

select has_column(
  'public', 'supplier_portal_probes', 'need_search_url_template',
  'a provider can configure a search for a need without a SKU'
);
select has_table(
  'public', 'supplier_need_portal_searches',
  'need-scoped portal results have a durable owner'
);
select has_function(
  'public', 'record_supplier_need_portal_search_v1',
  array['uuid', 'uuid', 'text', 'text', 'text', 'jsonb', 'jsonb', 'jsonb',
        'bigint', 'bigint', 'uuid', 'text'],
  'the guarded write exists'
);
select has_function(
  'public', 'supplier_last_need_portal_search_v1',
  array['uuid', 'uuid'],
  'the need-scoped latest read exists'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.record_supplier_need_portal_search_v1(uuid,uuid,text,text,text,jsonb,jsonb,jsonb,bigint,bigint,uuid,text)',
    'execute'
  ),
  'the authenticated ERP can record a search through the guarded command'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.supplier_last_need_portal_search_v1(uuid,uuid)',
    'execute'
  ),
  'the authenticated ERP can read the last result'
);
select ok(
  not has_table_privilege(
    'authenticated', 'public.supplier_need_portal_searches', 'insert'
  ) and not has_table_privilege(
    'authenticated', 'public.supplier_need_portal_searches', 'update'
  ) and not has_table_privilege(
    'authenticated', 'public.supplier_need_portal_searches', 'delete'
  ),
  'clients cannot bypass validation with direct writes'
);
select policies_are(
  'public', 'supplier_need_portal_searches',
  array['supplier_need_portal_searches_tenant_select'],
  'the history has one tenant-scoped read policy'
);

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select throws_ok(
  $$select public.record_supplier_need_portal_search_v1(
    '99010000-0000-4000-8000-000000000001',
    '99010000-0000-4000-8000-000000000002',
    'motor', 'completed', null, '[]'::jsonb, '{}'::jsonb, '{}'::jsonb,
    1, 1, '99010000-0000-4000-8000-000000000003', 'bottom_bracket'
  )$$,
  '42501',
  'No tenant context',
  'a caller without tenant context cannot write portal evidence'
);

select * from finish();
rollback;
