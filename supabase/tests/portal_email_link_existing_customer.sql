begin;
select plan(5);

-- La cuenta del portal se liga por correo confirmado a la ficha que el taller
-- ya tenía (20261104240000); la guardia de identidad sigue sin dejar que el
-- cliente cambie la cuenta de una ficha por su cuenta.
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
insert into public.tenants (id, shop_name, owner_email, timezone, is_active) values
  ('b2050000-0000-4000-8000-000000000001', 'Prueba enlace', 'enlace@example.invalid', 'America/Santiago', true);
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at) values
  ('b2050000-0000-4000-8000-000000000091', 'authenticated', 'authenticated',
   'cliente-erp@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now());
-- El taller creó al cliente con su correo, sin cuenta.
insert into public.customers (id, tenant_id, name, email, is_active) values
  ('b2050000-0000-4000-8000-000000000011', 'b2050000-0000-4000-8000-000000000001',
   'Cliente del taller', 'cliente-erp@example.invalid', true);
-- Después el cliente crea su cuenta con ese correo y entra.
select set_config('request.jwt.claims', '{"sub":"b2050000-0000-4000-8000-000000000091","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'b2050000-0000-4000-8000-000000000091', true);
select lives_ok(
  $$select public.provision_current_public_store_customer('b2050000-0000-4000-8000-000000000001')$$,
  'entrar con el correo de una ficha existente no falla'
);
select is(
  (select auth_user_id from public.customers where id = 'b2050000-0000-4000-8000-000000000011'),
  'b2050000-0000-4000-8000-000000000091'::uuid,
  'la ficha del taller queda ligada a la cuenta'
);
select is(
  (select count(*)::integer from public.customers where tenant_id = 'b2050000-0000-4000-8000-000000000001'),
  1,
  'sin crear otra ficha'
);
set local role authenticated;
select throws_ok(
  $$update public.customers set auth_user_id = null
     where id = 'b2050000-0000-4000-8000-000000000011'$$,
  '42501',
  'Customer tenant and Auth identity are immutable',
  'el cliente sigue sin poder soltar ni pasar su ficha'
);
reset role;
select is(
  public.provision_current_public_store_customer('b2050000-0000-4000-8000-000000000001'),
  'b2050000-0000-4000-8000-000000000011'::uuid,
  'y al volver a entrar es la misma ficha'
);
select * from finish();
rollback;
