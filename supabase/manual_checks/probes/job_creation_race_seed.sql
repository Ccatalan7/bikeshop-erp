-- Fixture of the job creation race (20260929010000): one workshop, one
-- employee, one customer with one bike. Local only.
insert into public.tenants(id, shop_name)
values ('e2870000-0000-4000-8000-000000000001', 'Carrera de altas');
insert into auth.users(id, aud, role, email, encrypted_password,
                       email_confirmed_at, raw_app_meta_data,
                       raw_user_meta_data, created_at, updated_at)
values ('e2870000-0000-4000-8000-000000000091', 'authenticated',
        'authenticated', 'carrera-altas@example.invalid', '', now(), '{}',
        '{}', now(), now());
insert into public.user_profiles(user_id, tenant_id, role)
values ('e2870000-0000-4000-8000-000000000091',
        'e2870000-0000-4000-8000-000000000001', 'admin');
select set_config('request.jwt.claims', '{"sub":"e2870000-0000-4000-8000-000000000091","role":"authenticated"}', false);
select set_config('request.jwt.claim.sub', 'e2870000-0000-4000-8000-000000000091', false);
insert into public.customers(id, tenant_id, name)
values ('e2870000-0000-4000-8000-000000000010',
        'e2870000-0000-4000-8000-000000000001', 'Cliente de la carrera');
insert into public.bikes(id, tenant_id, customer_id, brand, model)
values ('e2870000-0000-4000-8000-000000000020',
        'e2870000-0000-4000-8000-000000000001',
        'e2870000-0000-4000-8000-000000000010', 'Trek', 'FX');
