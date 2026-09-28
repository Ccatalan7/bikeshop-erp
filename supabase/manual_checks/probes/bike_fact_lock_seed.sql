-- Fixture of the two-connection race between cancelling a finished job and
-- writing what it installed, committed on the synthetic LOCAL stack only.
-- Driven by scripts/db/bike_fact_completion_lock_probe.sh; never run against
-- a hosted project.
begin;
select set_config('request.jwt.claims', '{}', true);
insert into public.tenants (id, shop_name) values ('e2790000-0000-4000-8000-000000000001', 'Taller carrera');
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('e2790000-0000-4000-8000-000000000099', 'authenticated', 'authenticated', 'carrera@example.invalid', '', now(), '{}', '{}', now(), now());
insert into public.user_profiles (user_id, tenant_id, role) values ('e2790000-0000-4000-8000-000000000099', 'e2790000-0000-4000-8000-000000000001', 'admin');
insert into public.customers (id, tenant_id, name) values ('e2790000-0000-4000-8000-000000000010', 'e2790000-0000-4000-8000-000000000001', 'Cliente carrera');
insert into public.bikes (id, tenant_id, customer_id, brand, model) values ('e2790000-0000-4000-8000-000000000031', 'e2790000-0000-4000-8000-000000000001', 'e2790000-0000-4000-8000-000000000010', 'Phoenix', 'Carrera');
insert into public.bike_profiles (id, tenant_id, bike_id, technical_profile) values ('e2790000-0000-4000-8000-000000000041', 'e2790000-0000-4000-8000-000000000001', 'e2790000-0000-4000-8000-000000000031', '{"values": {"frontSpokeHoles": 32}, "sources": {}, "confirmed": {}}');
insert into public.mechanic_jobs (id, tenant_id, customer_id, bike_id, job_number, created_by, status) values ('e2790000-0000-4000-8000-000000000051', 'e2790000-0000-4000-8000-000000000001', 'e2790000-0000-4000-8000-000000000010', 'e2790000-0000-4000-8000-000000000031', 'PG-CARRERA', 'e2790000-0000-4000-8000-000000000099', 'FINALIZADO');
-- The Enrayado line says what it installed (20260928020000): front wheel, 28H.
insert into public.mechanic_job_items (id, tenant_id, job_id, product_name, item_type, service_configuration_data) values ('e2790000-0000-4000-8000-000000000061', 'e2790000-0000-4000-8000-000000000001', 'e2790000-0000-4000-8000-000000000051', 'Enrayado + Centrado', 'service', '{"which_wheel": "front", "hole_count": "28"}');
commit;
