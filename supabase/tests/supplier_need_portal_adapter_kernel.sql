begin;

select no_plan();

select has_column(
  'public', 'supplier_portal_probes', 'need_search_adapter',
  'provider need-search behavior is durable configuration'
);
select col_type_is(
  'public', 'supplier_portal_probes', 'need_search_adapter', 'jsonb',
  'the versioned provider adapter is structured JSON'
);
select ok(
  exists (
    select 1
    from pg_constraint
    where conrelid = 'public.supplier_portal_probes'::regclass
      and conname = 'supplier_portal_probes_need_adapter_check'
  ),
  'malformed adapters are rejected by the database'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.record_supplier_need_portal_search_v1(uuid,uuid,text,text,text,jsonb,jsonb)',
    'execute'
  ),
  'the ERP writes need evidence only through the guarded command'
);
select ok(
  not has_table_privilege(
    'authenticated', 'public.supplier_need_portal_searches', 'insert'
  ),
  'clients still cannot bypass the guarded need-search command'
);

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select throws_ok(
  $$select public.record_supplier_need_portal_search_v1(
    '99010000-0000-4000-8000-000000000001',
    '99010000-0000-4000-8000-000000000002',
    'eje sellado', 'completed',
    'https://proveedor.example/catalogo?token=privado',
    '[]'::jsonb, '{}'::jsonb
  )$$,
  '42501',
  'No tenant context',
  'the command rejects callers before accepting any evidence'
);

select * from finish();
rollback;
