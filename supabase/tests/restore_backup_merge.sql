-- C2: contacts and catalogue through the installed public recovery RPCs
-- (contract restore_missing_keep_live, 20260930172000). The full workshop
-- graph, effect isolation, atomicity and cost are decided by
-- restore_workshop_graph.sql; this file keeps the catalogue rules:
--   A. a legacy partial backup brings back missing contacts/brands/models
--      with real INSERT defaults, never rewrites an existing contact, and
--      never rebinds a portal identity;
--   B. a row that collides with a live UNIQUE key stays out and is reported,
--      the rest comes back;
--   C/D. an unreviewed default or INSERT rule refuses without running;
--   E. a stored generated value is recomputed, never replayed;
--   F. another tenant's administrator cannot plan or recover.
-- Local only, synthetic tenants, transaction rolled back.
begin;
select no_plan();
do $guard$
begin
  if exists (select 1 from vault.secrets) then
    raise exception 'restore_backup_merge: local database only';
  end if;
end;
$guard$;

create temporary table merge_results(label text primary key, result jsonb);
grant all on merge_results to authenticated;
create function pg_temp.merge_id(p_suffix text) returns uuid language sql
as $$ select ('e2899000-0000-4000-8000-0000000000' || p_suffix)::uuid $$;
create function pg_temp.merge_claims(p_user text) returns void language plpgsql
as $$
begin
  perform set_config('request.jwt.claims', jsonb_build_object(
    'sub', pg_temp.merge_id(p_user), 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', pg_temp.merge_id(p_user)::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
end;
$$;
create function pg_temp.merge_backup(p_suffix text, p_data jsonb) returns uuid language sql
as $$
  insert into public.database_backups(id, tenant_id, backup_name, backup_type, status, backup_data)
  values (pg_temp.merge_id(p_suffix), pg_temp.merge_id('01'), 'Respaldo ' || p_suffix, 'manual',
    'completed', p_data)
  returning id
$$;
create function pg_temp.merge_run(p_label text, p_backup uuid) returns void language plpgsql
as $$
begin
  insert into merge_results values (p_label || '-preflight',
    public.restore_backup_merge_preflight(p_backup, pg_temp.merge_id('01')));
  insert into merge_results values (p_label || '-apply',
    public.restore_backup_merge(p_backup, pg_temp.merge_id('01')));
end;
$$;
grant execute on function pg_temp.merge_run(text, uuid) to authenticated;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
insert into public.tenants(id, shop_name) values
  (pg_temp.merge_id('01'), 'Recuperación de contactos'),
  (pg_temp.merge_id('02'), 'Recuperación otro taller');
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
insert into auth.users(id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at) values
  (pg_temp.merge_id('91'), 'authenticated', 'authenticated', 'merge-admin@example.invalid', '', now(), '{}', '{}', now(), now()),
  (pg_temp.merge_id('92'), 'authenticated', 'authenticated', 'merge-otro@example.invalid', '', now(), '{}', '{}', now(), now()),
  (pg_temp.merge_id('93'), 'authenticated', 'authenticated', 'merge-portal@example.invalid', '', now(), '{}', '{}', now(), now());
insert into public.user_profiles(user_id, tenant_id, role) values
  (pg_temp.merge_id('91'), pg_temp.merge_id('01'), 'admin'),
  (pg_temp.merge_id('92'), pg_temp.merge_id('02'), 'admin');
select pg_temp.merge_claims('91');
insert into public.customers(id, tenant_id, name, phone, email) values
  (pg_temp.merge_id('10'), pg_temp.merge_id('01'), 'Cliente de hoy', '111', null),
  (pg_temp.merge_id('11'), pg_temp.merge_id('01'), 'Cliente con correo', '222', 'taken@example.invalid');

-- A. Legacy partial backup.
select pg_temp.merge_backup('50', jsonb_build_object(
  'bike_brands', jsonb_build_array(jsonb_build_object('id', pg_temp.merge_id('22'),
    'tenant_id', pg_temp.merge_id('01'), 'name', 'Marca repuesta')),
  'bike_models', jsonb_build_array(jsonb_build_object('id', pg_temp.merge_id('23'),
    'tenant_id', pg_temp.merge_id('01'), 'brand_id', pg_temp.merge_id('22'), 'name', 'Modelo repuesto')),
  'customers', jsonb_build_array(
    jsonb_build_object('id', pg_temp.merge_id('10'), 'tenant_id', pg_temp.merge_id('01'), 'phone', '444'),
    jsonb_build_object('id', pg_temp.merge_id('12'), 'tenant_id', pg_temp.merge_id('01'),
      'name', 'Cliente repuesto', 'auth_user_id', pg_temp.merge_id('93')))));
set local role authenticated;
select pg_temp.merge_run('legacy', pg_temp.merge_id('50'));
reset role;
select ok((select (result ->> 'can_restore')::boolean from merge_results where label = 'legacy-preflight')
    and (select (result ->> 'success')::boolean and (result ->> 'changed_rows')::integer = 3
      from merge_results where label = 'legacy-apply'),
  'a legacy partial backup brings back the missing brand, model and contact');
select is((select phone from public.customers where id = pg_temp.merge_id('10')), '111',
  'an existing contact is never rewritten by the backup');
select ok((select is_active and created_at is not null from public.bike_brands where id = pg_temp.merge_id('22'))
    and (select brand_id = pg_temp.merge_id('22') from public.bike_models where id = pg_temp.merge_id('23')),
  'omitted columns take real defaults and the model keeps its restored brand');
select ok((select auth_user_id is null and name = 'Cliente repuesto' from public.customers where id = pg_temp.merge_id('12'))
    and (select jsonb_path_exists(result, '$.links_dropped[*] ? (@.parent_table == "portal_access" && @.rows == 1)')
      from merge_results where label = 'legacy-apply'),
  'a contact that comes back does not get its old portal account back, and it is reported');

-- B. A live UNIQUE key wins; the colliding row stays out, the rest returns.
select pg_temp.merge_backup('51', jsonb_build_object(
  'bike_brands', jsonb_build_array(jsonb_build_object('id', pg_temp.merge_id('24'),
    'tenant_id', pg_temp.merge_id('01'), 'name', 'Marca nueva')),
  'customers', jsonb_build_array(jsonb_build_object('id', pg_temp.merge_id('13'),
    'tenant_id', pg_temp.merge_id('01'), 'name', 'Correo repetido', 'email', 'TAKEN@example.invalid'))));
set local role authenticated;
select pg_temp.merge_run('unique', pg_temp.merge_id('51'));
reset role;
select ok((select jsonb_path_exists(result, '$.not_restored[*] ? (@.table == "customers" && @.reason == "conflict" && @.rows == 1)')
      from merge_results where label = 'unique-preflight')
    and (select (result ->> 'success')::boolean from merge_results where label = 'unique-apply')
    and not exists (select 1 from public.customers where id = pg_temp.merge_id('13'))
    and exists (select 1 from public.bike_brands where id = pg_temp.merge_id('24')),
  'a contact whose e-mail belongs to a contact of today stays out, reported; the brand returns');

-- C. An unreviewed default is refused without being evaluated.
create temporary table merge_effects(value boolean);
grant all on merge_effects to authenticated;
create function pg_temp.merge_effectful_default() returns boolean language sql volatile
as $$ insert into merge_effects values (true) returning value $$;
alter table public.bike_brands alter column is_active set default pg_temp.merge_effectful_default();
select pg_temp.merge_backup('52', jsonb_build_object('bike_brands', jsonb_build_array(
  jsonb_build_object('id', pg_temp.merge_id('25'), 'tenant_id', pg_temp.merge_id('01'), 'name', 'Default desconocido'))));
set local role authenticated;
select pg_temp.merge_run('default', pg_temp.merge_id('52'));
reset role;
select ok((select result -> 'refusal' ->> 'code' = 'unreviewed_default' from merge_results where label = 'default-preflight')
    and (select not (result ->> 'success')::boolean from merge_results where label = 'default-apply')
    and (select count(*) = 0 from merge_effects)
    and not exists (select 1 from public.bike_brands where id = pg_temp.merge_id('25')),
  'an unknown default refuses both entrypoints without running');
alter table public.bike_brands alter column is_active set default true;

-- D. An INSERT rule is an unreviewed write path.
create rule merge_unknown_rule as on insert to public.bike_brands
  do also insert into merge_effects values (true);
select pg_temp.merge_backup('53', jsonb_build_object('bike_brands', jsonb_build_array(
  jsonb_build_object('id', pg_temp.merge_id('26'), 'tenant_id', pg_temp.merge_id('01'), 'name', 'Con regla'))));
set local role authenticated;
select pg_temp.merge_run('rule', pg_temp.merge_id('53'));
reset role;
select ok((select result -> 'refusal' ->> 'code' = 'unreviewed_effect' from merge_results where label = 'rule-preflight')
    and (select not (result ->> 'success')::boolean from merge_results where label = 'rule-apply')
    and (select count(*) = 0 from merge_effects)
    and not exists (select 1 from public.bike_brands where id = pg_temp.merge_id('26')),
  'an INSERT rule refuses both entrypoints without running');
drop rule merge_unknown_rule on public.bike_brands;

-- E. Generated values are observations, recomputed by PostgreSQL.
alter table public.bike_brands add column merge_generated_test boolean
  generated always as (name is not null) stored;
select pg_temp.merge_backup('54', jsonb_build_object('bike_brands', jsonb_build_array(
  jsonb_build_object('id', pg_temp.merge_id('27'), 'tenant_id', pg_temp.merge_id('01'),
    'name', 'Generada', 'merge_generated_test', false))));
set local role authenticated;
select pg_temp.merge_run('generated', pg_temp.merge_id('54'));
reset role;
select ok((select (result ->> 'success')::boolean from merge_results where label = 'generated-apply')
    and (select merge_generated_test from public.bike_brands where id = pg_temp.merge_id('27')),
  'a stored generated value in the backup is not replayed');

-- F. Authority.
select pg_temp.merge_claims('92');
set local role authenticated;
select throws_ok(format('select public.restore_backup_merge_preflight(%L, %L)',
  pg_temp.merge_id('50'), pg_temp.merge_id('01')), '42501', null,
  'an administrator of another tenant cannot read the plan');
select throws_ok(format('select public.restore_backup_merge(%L, %L)',
  pg_temp.merge_id('50'), pg_temp.merge_id('01')), '42501', null,
  'an administrator of another tenant cannot apply it');
reset role;
select * from finish();
rollback;
