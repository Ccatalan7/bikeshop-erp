-- 20261030031500: two shops that receive the same supplier folio keep their
-- own purchase journal entries when one posts, walks back, reposts, changes
-- amounts or corrects its date.
begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

select plan(10);

insert into public.tenants(id, shop_name, timezone) values
  ('9d310000-0000-4000-8000-000000000001',
   'Journal Scope Tenant A', 'America/Santiago'),
  ('9d310000-0000-4000-8000-000000000002',
   'Journal Scope Tenant B', 'America/Santiago');

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into public.suppliers (id, tenant_id, name, is_active, updated_at) values
  ('9d310000-0000-4000-8000-000000000011',
   '9d310000-0000-4000-8000-000000000001', 'Distribuidor Común', true, now()),
  ('9d310000-0000-4000-8000-000000000012',
   '9d310000-0000-4000-8000-000000000002', 'Distribuidor Común', true, now());

create function pg_temp.scope_entries()
returns table(tenant_id uuid, total numeric, entry_date date)
language sql
stable
as $$
  select entry.tenant_id, entry.total_debit, entry.entry_date::date
    from public.journal_entries entry
   where entry.tenant_id in ('9d310000-0000-4000-8000-000000000001',
                             '9d310000-0000-4000-8000-000000000002')
     and entry.source_module = 'purchase_invoices'
     and entry.source_reference = '777001'
$$;

-- Both shops buy from the same distributor and receive folio 777001.
insert into public.purchase_invoices (
  id, tenant_id, invoice_number, supplier_id, supplier_name, status, date,
  subtotal, net_amount, tax, iva_amount, total, paid_amount, balance, items
) values
  ('9d310000-0000-4000-8000-000000000021',
   '9d310000-0000-4000-8000-000000000001', '777001',
   '9d310000-0000-4000-8000-000000000011', 'Distribuidor Común', 'confirmed',
   now(), 10000, 10000, 1900, 1900, 11900, 0, 11900, '[]'::jsonb),
  ('9d310000-0000-4000-8000-000000000022',
   '9d310000-0000-4000-8000-000000000002', '777001',
   '9d310000-0000-4000-8000-000000000012', 'Distribuidor Común', 'confirmed',
   now(), 20000, 20000, 3800, 3800, 23800, 0, 23800, '[]'::jsonb);

select results_eq(
  $$select tenant_id, total from pg_temp.scope_entries() order by total$$,
  $$values ('9d310000-0000-4000-8000-000000000001'::uuid, 11900::numeric),
           ('9d310000-0000-4000-8000-000000000002'::uuid, 23800::numeric)$$,
  'each shop posts its own entry for the same folio'
);

update public.purchase_invoices
   set status = 'draft'
 where id = '9d310000-0000-4000-8000-000000000021';

select results_eq(
  $$select tenant_id, total from pg_temp.scope_entries()$$,
  $$values ('9d310000-0000-4000-8000-000000000002'::uuid, 23800::numeric)$$,
  'walking shop A back removes only its own entry'
);

update public.purchase_invoices
   set status = 'confirmed'
 where id = '9d310000-0000-4000-8000-000000000021';

select results_eq(
  $$select tenant_id, total from pg_temp.scope_entries() order by total$$,
  $$values ('9d310000-0000-4000-8000-000000000001'::uuid, 11900::numeric),
           ('9d310000-0000-4000-8000-000000000002'::uuid, 23800::numeric)$$,
  'shop A reposts although shop B already has that folio'
);

update public.purchase_invoices
   set subtotal = 30000, net_amount = 30000, tax = 5700, iva_amount = 5700,
       total = 35700, balance = 35700
 where id = '9d310000-0000-4000-8000-000000000022';

select results_eq(
  $$select tenant_id, total from pg_temp.scope_entries() order by total$$,
  $$values ('9d310000-0000-4000-8000-000000000001'::uuid, 11900::numeric),
           ('9d310000-0000-4000-8000-000000000002'::uuid, 35700::numeric)$$,
  'an amount change in shop B reposts only its own entry'
);

update public.purchase_invoices
   set date = now() - interval '3 days'
 where id = '9d310000-0000-4000-8000-000000000021';

select is(
  (select entry_date from pg_temp.scope_entries()
    where tenant_id = '9d310000-0000-4000-8000-000000000001'),
  (now() at time zone 'America/Santiago')::date - 3,
  'a date correction in shop A moves its entry'
);

select is(
  (select entry_date from pg_temp.scope_entries()
    where tenant_id = '9d310000-0000-4000-8000-000000000002'),
  (now() at time zone 'America/Santiago')::date,
  'and leaves shop B''s entry on its own date'
);

select lives_ok(
  $$select public.delete_purchase_invoice_journal_entry(
      '9d310000-0000-4000-8000-000000000002'::uuid, '777001')$$,
  'the tenant-scoped delete runs'
);

select results_eq(
  $$select tenant_id from pg_temp.scope_entries()$$,
  $$values ('9d310000-0000-4000-8000-000000000001'::uuid)$$,
  'and removes only that shop''s entry'
);

select throws_ok(
  $$select public.delete_purchase_invoice_journal_entry('777001'::text)$$,
  '42883',
  null,
  'the helper that cannot tell shops apart refuses'
);

select ok(
  not has_function_privilege('authenticated',
    'public.delete_purchase_invoice_journal_entry(uuid,text)', 'EXECUTE')
  and not has_function_privilege('anon',
    'public.delete_purchase_invoice_journal_entry(uuid,text)', 'EXECUTE'),
  'the scoped delete is not callable from the API'
);

select * from finish();
rollback;
