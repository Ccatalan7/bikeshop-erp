-- El vendedor vuelve a ser editable (20260902220000).
--
-- Comando estrecho `update_supplier_sales_rep`, calcado del de la plantilla
-- OCR: mismo borde de tenant, misma concurrencia optimista, mismo recibo
-- idempotente. Vive en su propio archivo porque la batería de la fundación
-- muere hoy en su prueba 38 (un trigger de facturas que producción corrigió a
-- mano y el repositorio no tiene) antes de llegar a este bloque.
begin;
select no_plan();

select set_config(
  'request.jwt.claims',
  '{"role":"service_role"}',
  true
);

insert into public.tenants (id, shop_name) values
  ('b2c40902-0000-4000-8000-000000000001', 'Vendedor Test');
insert into public.suppliers (id, tenant_id, name, phone) values
  (
    'b2c40902-0001-4000-8000-000000000101',
    'b2c40902-0000-4000-8000-000000000001',
    'Comercial Ciclo (prueba)',
    '+56934867574'
  );

select has_function(
  'public', 'update_supplier_sales_rep',
  array['uuid', 'uuid', 'timestamp with time zone', 'uuid', 'jsonb'],
  'supplier sales rep has one narrow canonical write command'
);
select ok(
  not has_table_privilege(
    'authenticated',
    'public.supplier_sales_rep_command_receipts',
    'SELECT'
  ) and not has_function_privilege(
    'public',
    'public.update_supplier_sales_rep(uuid,uuid,timestamptz,uuid,jsonb)',
    'EXECUTE'
  ) and has_function_privilege(
    'authenticated',
    'public.update_supplier_sales_rep(uuid,uuid,timestamptz,uuid,jsonb)',
    'EXECUTE'
  ),
  'sales-rep receipts stay private while the narrow command is authenticated-only'
);

create temporary table sales_rep_before as
select updated_at
from public.suppliers
where id = 'b2c40902-0001-4000-8000-000000000101';
create temporary table sales_rep_result (payload jsonb);
insert into sales_rep_result
select public.update_supplier_sales_rep(
  'b2c40902-0000-4000-8000-000000000001',
  'b2c40902-0001-4000-8000-000000000101',
  (select updated_at from sales_rep_before),
  'b2c40902-0120-4000-8000-000000000001',
  '{"name":" Fabiola Morales ","phone":"+56 9 8815 5152","email":null}'::jsonb
);
select ok(
  (
    select payload->>'idempotent_replay' = 'false'
      and payload->'sales_rep' = '{"name":"Fabiola Morales","phone":"+56 9 8815 5152","email":null}'::jsonb
      and (payload->>'updated_at')::timestamptz >
        (select updated_at from sales_rep_before)
    from sales_rep_result
  ),
  'narrow sales-rep command trims, applies and returns only the canonical contact'
);
select is(
  (
    select sales_rep_name || '|' || sales_rep_phone || '|'
      || coalesce(sales_rep_email, '') || '|' || phone
    from public.suppliers
    where id = 'b2c40902-0001-4000-8000-000000000101'
  ),
  'Fabiola Morales|+56 9 8815 5152||+56934867574',
  'sales-rep command writes the three columns and leaves the profile phone alone'
);
select is(
  public.update_supplier_sales_rep(
    'b2c40902-0000-4000-8000-000000000001',
    'b2c40902-0001-4000-8000-000000000101',
    (select updated_at from sales_rep_before),
    'b2c40902-0120-4000-8000-000000000001',
    '{"name":" Fabiola Morales ","phone":"+56 9 8815 5152","email":null}'::jsonb
  )->>'idempotent_replay',
  'true',
  'lost-ack sales-rep update replays its durable receipt'
);
select throws_ok(
  $$select public.update_supplier_sales_rep(
    'b2c40902-0000-4000-8000-000000000001',
    'b2c40902-0001-4000-8000-000000000101',
    (select updated_at from sales_rep_before),
    'b2c40902-0120-4000-8000-000000000001',
    '{"name":"Otra Persona","phone":null,"email":null}'::jsonb
  )$$,
  '23505',
  'Sales rep operation id was reused with different content',
  'sales-rep operation id cannot be reused with different content'
);
select throws_ok(
  $$select public.update_supplier_sales_rep(
    'b2c40902-0000-4000-8000-000000000001',
    'b2c40902-0001-4000-8000-000000000101',
    (select updated_at from sales_rep_before),
    'b2c40902-0120-4000-8000-000000000002',
    '{"name":null,"phone":null,"email":null}'::jsonb
  )$$,
  '40001',
  'Supplier changed concurrently',
  'a stale expected updated_at is rejected'
);
select throws_ok(
  $$select public.update_supplier_sales_rep(
    'b2c40902-0000-4000-8000-000000000001',
    'b2c40902-0001-4000-8000-000000000101',
    (select updated_at from public.suppliers
      where id = 'b2c40902-0001-4000-8000-000000000101'),
    'b2c40902-0120-4000-8000-000000000003',
    '{"name":"X","phone":"12345","email":null}'::jsonb
  )$$,
  '22023',
  'Sales rep phone must have at least 8 digits',
  'a phone that cannot receive a message is rejected before writing'
);
select throws_ok(
  $$select public.update_supplier_sales_rep(
    'b2c40902-0000-4000-8000-000000000001',
    'b2c40902-0001-4000-8000-000000000101',
    (select updated_at from public.suppliers
      where id = 'b2c40902-0001-4000-8000-000000000101'),
    'b2c40902-0120-4000-8000-000000000004',
    '{"name":"X","phone":null,"email":null,"contact_person":"Y"}'::jsonb
  )$$,
  '22023',
  'Sales rep accepts only name, phone and email as text',
  'the command cannot be used to write any other supplier column'
);
select throws_ok(
  $$select public.update_supplier_sales_rep(
    'b2c40902-0000-4000-8000-000000000001',
    'b2c40902-0001-4000-8000-000000000999',
    now(),
    'b2c40902-0120-4000-8000-000000000006',
    '{"name":"X","phone":null,"email":null}'::jsonb
  )$$,
  'P0002',
  'Supplier not found in tenant',
  'a supplier outside the tenant is not found, never updated'
);
-- Vaciar el vendedor también es un cambio válido: sin vendedor, el WhatsApp
-- cae al Teléfono de la ficha.
select is(
  public.update_supplier_sales_rep(
    'b2c40902-0000-4000-8000-000000000001',
    'b2c40902-0001-4000-8000-000000000101',
    (select updated_at from public.suppliers
      where id = 'b2c40902-0001-4000-8000-000000000101'),
    'b2c40902-0120-4000-8000-000000000005',
    '{"name":"","phone":"  ","email":""}'::jsonb
  )->'sales_rep',
  '{"name":null,"phone":null,"email":null}'::jsonb,
  'blank sales-rep fields clear the contact instead of storing whitespace'
);

select * from finish();
rollback;
