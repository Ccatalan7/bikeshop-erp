begin;

select plan(12);

-- El mismo cliente creado otra vez en minutos lo rechaza la base
-- (20261125191700_guard_customer_recent_duplicate).

insert into public.tenants (id, shop_name) values
  ('d3c70000-0000-4000-8000-0000000000a1', 'Taller repetidos A'),
  ('d3c70000-0000-4000-8000-0000000000a2', 'Taller repetidos B');
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into public.customers (id, tenant_id, name, phone) values
  ('d3c70000-0000-4000-8000-0000000000b1', 'd3c70000-0000-4000-8000-0000000000a1',
   'Karla Concha Gonzalez', '+56 9 5400 2018');

select has_trigger('public', 'customers', 'trg_guard_customer_recent_duplicate',
  'customers has the recent duplicate guard');
select ok(
  (select p.prosecdef and p.proconfig @> array['search_path=public, pg_temp']
     from pg_proc p where p.oid = 'public.guard_customer_recent_duplicate()'::regprocedure),
  'the guard sees every row (security definer, fixed search_path)');

select throws_ok(
  $$insert into public.customers (id, tenant_id, name, phone) values
      ('d3c70000-0000-4000-8000-0000000000b2', 'd3c70000-0000-4000-8000-0000000000a1',
       '  karla  CONCHA gonzalez ', '954002018')$$,
  '23505', 'Este cliente ya se creó hace un momento: búscalo en la lista.',
  'the same name and phone, typed otherwise, is refused');

create temporary table refusal (detail text, hint text);
do $$
declare
  v_detail text;
  v_hint text;
begin
  insert into public.customers (id, tenant_id, name, phone) values
    ('d3c70000-0000-4000-8000-0000000000b3', 'd3c70000-0000-4000-8000-0000000000a1',
     'Karla Concha Gonzalez', '+56954002018');
exception when unique_violation then
  get stacked diagnostics v_detail = pg_exception_detail, v_hint = pg_exception_hint;
  insert into refusal values (v_detail, v_hint);
end;
$$;
select is((select detail from refusal), 'customer_recent_duplicate',
  'the refusal names itself in the detail');
select is((select hint from refusal), 'd3c70000-0000-4000-8000-0000000000b1',
  'and its hint is the customer that already exists');

select throws_ok(
  $$insert into public.customers (id, tenant_id, name, phone) values
      ('d3c70000-0000-4000-8000-0000000000b1', 'd3c70000-0000-4000-8000-0000000000a1',
       'Karla Concha Gonzalez', '+56954002018')$$,
  '23505', 'duplicate key value violates unique constraint "customers_pkey"',
  'a retry with the same identity meets its own primary key, not the guard');

select lives_ok(
  $$insert into public.customers (id, tenant_id, name, phone) values
      ('d3c70000-0000-4000-8000-0000000000b4', 'd3c70000-0000-4000-8000-0000000000a1',
       'Tomás Concha', '+56 9 5400 2018')$$,
  'another person sharing the phone is created');
select lives_ok(
  $$insert into public.customers (id, tenant_id, name, phone) values
      ('d3c70000-0000-4000-8000-0000000000b5', 'd3c70000-0000-4000-8000-0000000000a1',
       'Karla Concha Gonzalez', '+56 9 5400 2019')$$,
  'the same name with another phone is created');
select lives_ok(
  $$insert into public.customers (id, tenant_id, name, phone) values
      ('d3c70000-0000-4000-8000-0000000000b6', 'd3c70000-0000-4000-8000-0000000000a2',
       'Karla Concha Gonzalez', '+56 9 5400 2018')$$,
  'the same customer in another shop is created');

insert into public.customers (id, tenant_id, name, phone, created_at) values
  ('d3c70000-0000-4000-8000-0000000000c1', 'd3c70000-0000-4000-8000-0000000000a1',
   'Ana Pérez', '+56 9 1111 2222', now() - interval '11 minutes');
select lives_ok(
  $$insert into public.customers (id, tenant_id, name, phone) values
      ('d3c70000-0000-4000-8000-0000000000c2', 'd3c70000-0000-4000-8000-0000000000a1',
       'Ana Pérez', '+56 9 1111 2222')$$,
  'a customer created more than ten minutes ago is a person''s call (restores pass)');

select lives_ok(
  $$insert into public.customers (id, tenant_id, name, phone) values
      ('d3c70000-0000-4000-8000-0000000000c3', 'd3c70000-0000-4000-8000-0000000000a1',
       'Mostrador', '123'),
     ('d3c70000-0000-4000-8000-0000000000c4', 'd3c70000-0000-4000-8000-0000000000a1',
       'Mostrador', '123')$$,
  'without a real phone there is nothing to compare');

select is(
  (select count(*)::int from public.customers
    where tenant_id = 'd3c70000-0000-4000-8000-0000000000a1'
      and lower(name) like 'karla concha gonzalez'
      and right(regexp_replace(phone, '\D', '', 'g'), 9) = '954002018'),
  1,
  'Karla stays once');

select * from finish();
rollback;
