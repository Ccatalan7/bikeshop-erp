-- El sello `account_type` en auth.users.raw_app_meta_data es estado DERIVADO
-- del perfil ERP activo, y GoTrue puede pisarlo con una copia vieja de la fila
-- (observado 2026-08-05: la verificación de correo lo selló y ~1 s después un
-- write-back lo borró, dejando fuera a un admin válido). Este archivo fija el
-- contrato de `get_my_erp_profile()`: repara un sello AUSENTE desde la única
-- autoridad —la fila activa de user_profiles—, jamás inventa acceso sin
-- perfil, y jamás convierte un sello en conflicto.
begin;
select set_config('request.jwt.claims','{}',true);
select set_config('request.jwt.claim.sub','',true);
select plan(14);

insert into public.tenants(id,shop_name,owner_email)
values('99810000-0000-4000-8000-000000000001','Stamp Heal Test','duena@example.invalid');

-- 1) Staff con el sello borrado por el write-back: queda el estado
--    post-registro ({provider, providers, hash pendiente}) y el perfil activo.
insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values('99810000-0000-4000-8000-000000000011','authenticated','authenticated','staff@example.invalid','',now(),
jsonb_build_object('provider','email','providers',jsonb_build_array('email'),'pending_invitation_token_hash',repeat('ab',32)),
'{}'::jsonb,now(),now());
insert into public.user_profiles(user_id,tenant_id,role,is_active,permissions)
values('99810000-0000-4000-8000-000000000011','99810000-0000-4000-8000-000000000001','admin',true,'{"access_pos":true}'::jsonb);

-- 2) Dueña del negocio en el mismo estado corrupto.
insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values('99810000-0000-4000-8000-000000000012','authenticated','authenticated','duena@example.invalid','',now(),
jsonb_build_object('provider','email','providers',jsonb_build_array('email')),'{}'::jsonb,now(),now());
insert into public.user_profiles(user_id,tenant_id,role,is_active)
values('99810000-0000-4000-8000-000000000012','99810000-0000-4000-8000-000000000001','admin',true);

-- 3) Cliente de tienda con perfil ERP activo: sello en conflicto, no vacío.
insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values('99810000-0000-4000-8000-000000000013','authenticated','authenticated','cliente@example.invalid','',now(),
jsonb_build_object('provider','email','account_type','public_store_customer'),'{}'::jsonb,now(),now());
insert into public.user_profiles(user_id,tenant_id,role,is_active)
values('99810000-0000-4000-8000-000000000013','99810000-0000-4000-8000-000000000001','admin',true);

-- 4) Sesión sin ningún perfil ERP.
insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values('99810000-0000-4000-8000-000000000014','authenticated','authenticated','sinperfil@example.invalid','',now(),
jsonb_build_object('provider','email'),'{}'::jsonb,now(),now());

-- 5) Staff sano ya sellado: la reparación no debe tocarlo.
insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values('99810000-0000-4000-8000-000000000015','authenticated','authenticated','sano@example.invalid','',now(),
jsonb_build_object('provider','email','account_type','erp_staff','tenant_id','99810000-0000-4000-8000-000000000001','role','admin'),
'{}'::jsonb,now(),now());
insert into public.user_profiles(user_id,tenant_id,role,is_active)
values('99810000-0000-4000-8000-000000000015','99810000-0000-4000-8000-000000000001','admin',true);

-- 6) Staff suspendido (banned) con el sello borrado: la puerta va primero.
insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at,banned_until)
values('99810000-0000-4000-8000-000000000016','authenticated','authenticated','banned@example.invalid','',now(),
jsonb_build_object('provider','email'),'{}'::jsonb,now(),now(),now()+interval '1 day');
insert into public.user_profiles(user_id,tenant_id,role,is_active)
values('99810000-0000-4000-8000-000000000016','99810000-0000-4000-8000-000000000001','admin',true);

-- ── Staff corrupto: una sola llamada repara y entra ──────────────────────────
select set_config('request.jwt.claims',jsonb_build_object('sub','99810000-0000-4000-8000-000000000011','role','authenticated')::text,true);
select set_config('request.jwt.claim.sub','99810000-0000-4000-8000-000000000011',true);

select is((public.get_my_erp_profile())->>'tenantId','99810000-0000-4000-8000-000000000001',
  'la llamada corrupta entra igual: repara y devuelve el perfil');
select is((select raw_app_meta_data->>'account_type' from auth.users where id='99810000-0000-4000-8000-000000000011'),
  'erp_staff','el sello queda restaurado como erp_staff');
select is((select raw_app_meta_data->>'tenant_id' from auth.users where id='99810000-0000-4000-8000-000000000011'),
  '99810000-0000-4000-8000-000000000001','el tenant sellado sale del perfil, no de la sesión');
select ok((select raw_app_meta_data ? 'pending_invitation_token_hash' is false from auth.users where id='99810000-0000-4000-8000-000000000011'),
  'el hash pendiente huérfano se retira en la misma reparación');
select is((public.get_my_erp_profile())->>'role','admin',
  'la segunda llamada es idéntica: la reparación es idempotente');

-- ── Dueña: el sello reparado respeta erp_owner ───────────────────────────────
select set_config('request.jwt.claims',jsonb_build_object('sub','99810000-0000-4000-8000-000000000012','role','authenticated')::text,true);
select set_config('request.jwt.claim.sub','99810000-0000-4000-8000-000000000012',true);

select is((public.get_my_erp_profile())->>'tenantId','99810000-0000-4000-8000-000000000001',
  'la dueña corrupta también entra a la primera');
select is((select raw_app_meta_data->>'account_type' from auth.users where id='99810000-0000-4000-8000-000000000012'),
  'erp_owner','el correo del tenant distingue erp_owner de erp_staff');

-- ── Sello en conflicto: jamás se convierte ───────────────────────────────────
select set_config('request.jwt.claims',jsonb_build_object('sub','99810000-0000-4000-8000-000000000013','role','authenticated')::text,true);
select set_config('request.jwt.claim.sub','99810000-0000-4000-8000-000000000013',true);

select throws_ok('select public.get_my_erp_profile()','P0001','erp_profile_context_invalid',
  'un sello de cliente con perfil ERP es deriva de identidad y falla cerrado');
select is((select raw_app_meta_data->>'account_type' from auth.users where id='99810000-0000-4000-8000-000000000013'),
  'public_store_customer','el sello en conflicto queda intacto');

-- ── Sin perfil: la reparación no inventa acceso ──────────────────────────────
select set_config('request.jwt.claims',jsonb_build_object('sub','99810000-0000-4000-8000-000000000014','role','authenticated')::text,true);
select set_config('request.jwt.claim.sub','99810000-0000-4000-8000-000000000014',true);

select throws_ok('select public.get_my_erp_profile()','P0001','erp_profile_context_invalid',
  'sin perfil activo no hay nada que reparar y se rechaza igual que hoy');
select ok((select raw_app_meta_data ? 'account_type' is false from auth.users where id='99810000-0000-4000-8000-000000000014'),
  'a la sesión sin perfil no se le escribe ningún sello');

-- ── Sano: cero efectos secundarios ───────────────────────────────────────────
select set_config('request.jwt.claims',jsonb_build_object('sub','99810000-0000-4000-8000-000000000015','role','authenticated')::text,true);
select set_config('request.jwt.claim.sub','99810000-0000-4000-8000-000000000015',true);

create temp table stamp_before on commit drop as
select raw_app_meta_data from auth.users where id='99810000-0000-4000-8000-000000000015';
select is((public.get_my_erp_profile())->>'role','admin','el staff sano entra como siempre');
select is((select raw_app_meta_data from auth.users where id='99810000-0000-4000-8000-000000000015'),
  (select raw_app_meta_data from stamp_before),'sus metadatos quedan byte a byte iguales');

-- ── Suspendido: la puerta de baneo va antes que la reparación ────────────────
select set_config('request.jwt.claims',jsonb_build_object('sub','99810000-0000-4000-8000-000000000016','role','authenticated')::text,true);
select set_config('request.jwt.claim.sub','99810000-0000-4000-8000-000000000016',true);

select throws_ok('select public.get_my_erp_profile()','42501','ERP profile access denied',
  'una cuenta suspendida no obtiene reparación ni perfil');

select * from finish();
rollback;
