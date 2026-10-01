-- Fixture of the two-connection race between two jobs of the same bike that
-- finish at the same time, one with a Shimano HG cassette and one with a
-- threaded freewheel (20260928120000), committed on the synthetic LOCAL stack
-- only. Driven by scripts/db/part_change_rear_cogs_race_probe.sh; never run
-- against a hosted project.
--
-- The local stack has no spec engine: the product reader is saved and
-- replaced by one that reads this fixture; the cleanup puts it back.
begin;
create schema probe_rear_cogs;
create table probe_rear_cogs.saved_reader as
select pg_get_functiondef(
  'public.product_bike_fact_spec_internal(uuid,uuid,text)'::regprocedure) as def;
create table probe_rear_cogs.specs (
  product_id uuid,
  spec_key text,
  value jsonb,
  template_key text
);
create or replace function public.product_bike_fact_spec_internal(
  p_tenant_id uuid,
  p_product_id uuid,
  p_spec_key text
)
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $$
  select jsonb_build_object(
           'value', (select s.value from probe_rear_cogs.specs s
                      where s.product_id = p.id and s.spec_key = p_spec_key),
           'template_key', (select min(s.template_key) from probe_rear_cogs.specs s
                             where s.product_id = p.id),
           'verified', false)
    from public.products p
   where p.id = p_product_id
     and p.tenant_id = p_tenant_id
     and exists (select 1 from probe_rear_cogs.specs s where s.product_id = p.id)
$$;

select set_config('request.jwt.claims', '{}', true);
insert into public.tenants (id, shop_name) values ('e2830000-0000-4000-8000-000000000001', 'Taller carrera de piñones');
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('e2830000-0000-4000-8000-000000000099', 'authenticated', 'authenticated', 'carrera-pinones@example.invalid', '', now(), '{}', '{}', now(), now());
insert into public.user_profiles (user_id, tenant_id, role) values ('e2830000-0000-4000-8000-000000000099', 'e2830000-0000-4000-8000-000000000001', 'admin');
insert into public.customers (id, tenant_id, name) values ('e2830000-0000-4000-8000-000000000010', 'e2830000-0000-4000-8000-000000000001', 'Cliente carrera de piñones');
-- An Oxford Rako whose ficha knows its drivetrain (3x7) but not the driver.
insert into public.bikes (id, tenant_id, customer_id, brand, model) values ('e2830000-0000-4000-8000-000000000031', 'e2830000-0000-4000-8000-000000000001', 'e2830000-0000-4000-8000-000000000010', 'Oxford', 'Rako');
insert into public.bike_profiles (tenant_id, bike_id, technical_profile) values ('e2830000-0000-4000-8000-000000000001', 'e2830000-0000-4000-8000-000000000031', '{"values": {"drivetrainConfig": "3x7"}, "sources": {"drivetrainConfig": "mechanic"}, "confirmed": {"drivetrainConfig": true}}');
insert into public.products (id, tenant_id, name, category_name) values
  ('e2830000-0000-4000-8000-000000000101', 'e2830000-0000-4000-8000-000000000001', 'Cassette Shimano 7V CS-HG200-7 12/32T', 'Transmisión'),
  ('e2830000-0000-4000-8000-000000000108', 'e2830000-0000-4000-8000-000000000001', 'PIÑON ATORNILLADO 7 VELOCIDADES FALCON MOD.FW71', 'Transmisión');
insert into probe_rear_cogs.specs values
  ('e2830000-0000-4000-8000-000000000101', 'cassette_spline_standard', '"Shimano HG spline S (7v)"', 'cassette'),
  ('e2830000-0000-4000-8000-000000000101', 'sprocket_count', '7', 'cassette'),
  ('e2830000-0000-4000-8000-000000000108', 'sprocket_count', '7', 'freewheel');
-- Two open jobs of the same bike: A installs the cassette, B the freewheel.
insert into public.mechanic_jobs (id, tenant_id, customer_id, bike_id, job_number, created_by) values
  ('e2830000-0000-4000-8000-000000000051', 'e2830000-0000-4000-8000-000000000001', 'e2830000-0000-4000-8000-000000000010', 'e2830000-0000-4000-8000-000000000031', 'PG-CARRERA-A', 'e2830000-0000-4000-8000-000000000099'),
  ('e2830000-0000-4000-8000-000000000052', 'e2830000-0000-4000-8000-000000000001', 'e2830000-0000-4000-8000-000000000010', 'e2830000-0000-4000-8000-000000000031', 'PG-CARRERA-B', 'e2830000-0000-4000-8000-000000000099');
insert into public.mechanic_job_bikes (tenant_id, job_id, bike_id)
select tenant_id, id, bike_id from public.mechanic_jobs where tenant_id = 'e2830000-0000-4000-8000-000000000001'
on conflict (job_id, bike_id) do nothing;
insert into public.mechanic_job_items (id, tenant_id, job_id, product_id, product_name, item_type, location_key, quantity, unit_price, service_configuration_data) values
  ('e2830000-0000-4000-8000-000000000061', 'e2830000-0000-4000-8000-000000000001', 'e2830000-0000-4000-8000-000000000051', 'e2830000-0000-4000-8000-000000000101', 'Cassette Shimano 7V CS-HG200-7 12/32T', 'product', 'rear', 1, 19990, '{"part_change": {"key": "freehubType", "value": "shimano_hg"}}'),
  ('e2830000-0000-4000-8000-000000000062', 'e2830000-0000-4000-8000-000000000001', 'e2830000-0000-4000-8000-000000000052', 'e2830000-0000-4000-8000-000000000108', 'PIÑON ATORNILLADO 7 VELOCIDADES FALCON MOD.FW71', 'product', 'rear', 1, 12990, '{"part_change": {"key": "freehubType", "value": "threaded_freewheel"}}');
commit;
