begin;

select no_plan();

-- El teléfono confirmado por WhatsApp liga la cuenta del portal
-- (20261105010000): el código sale sólo hacia la función que lo manda, se
-- guarda como hash, tiene cinco intentos y límites por cuenta y por número;
-- confirmado, la cuenta queda con la única ficha del taller que tiene ese
-- número, y si el taller la crea después, al entrar. Nunca adivina entre
-- varias fichas, nunca toma una de otra tienda y nunca archiva una cuenta con
-- historial propio.

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into public.tenants (id, shop_name, owner_email, timezone, is_active) values
  ('b2050000-0000-4000-8000-000000000001', 'Taller teléfono A',
   'telefono-a@example.invalid', 'America/Santiago', true),
  ('b2050000-0000-4000-8000-000000000002', 'Taller teléfono B',
   'telefono-b@example.invalid', 'America/Santiago', true);

-- Iniciar un taller deja la sesión con su id como usuario.
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('b2050000-0000-4000-8000-000000000081', 'authenticated', 'authenticated',
   'ana@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('b2050000-0000-4000-8000-000000000082', 'authenticated', 'authenticated',
   'beto@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('b2050000-0000-4000-8000-000000000083', 'authenticated', 'authenticated',
   'carla@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('b2050000-0000-4000-8000-000000000084', 'authenticated', 'authenticated',
   'dani@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('b2050000-0000-4000-8000-000000000085', 'authenticated', 'authenticated',
   'eva@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('b2050000-0000-4000-8000-000000000086', 'authenticated', 'authenticated',
   'sin-confirmar@example.invalid', '', null, '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('b2050000-0000-4000-8000-000000000087', 'authenticated', 'authenticated',
   'fallo@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now());

-- Encendido en A; B no lo encendió.
insert into public.company_settings (tenant_id, key, value) values
  ('b2050000-0000-4000-8000-000000000001', 'customer_portal_phone_verification_enabled', 'true');

insert into public.customers (id, tenant_id, name, phone, email, is_active) values
  -- Fichas del taller, sin cuenta.
  ('b2050000-0000-4000-8000-000000000011', 'b2050000-0000-4000-8000-000000000001',
   'Ana Ruiz', '+56 9 1111 2222', null, true),
  ('b2050000-0000-4000-8000-000000000012', 'b2050000-0000-4000-8000-000000000001',
   'Beto Mora', '+56933334444', null, true),
  ('b2050000-0000-4000-8000-000000000013', 'b2050000-0000-4000-8000-000000000001',
   'Bea Mora', '9 3333 4444', null, true),
  ('b2050000-0000-4000-8000-000000000014', 'b2050000-0000-4000-8000-000000000001',
   'Daniela Paz', '+56 9 7777 8888', null, true),
  -- En otra tienda, con el número que Carla confirmará en A.
  ('b2050000-0000-4000-8000-000000000015', 'b2050000-0000-4000-8000-000000000002',
   'Carla en B', '+56 9 5555 6666', null, true);

set local session_replication_role = replica;
insert into public.mechanic_jobs (
  id, tenant_id, customer_id, job_number, job_type, workflow_kind, status
) values
  ('b2050000-0000-4000-8000-000000000031', 'b2050000-0000-4000-8000-000000000001',
   'b2050000-0000-4000-8000-000000000011', 'PG-F1', 'service', 'service', 'PENDIENTE');
set local session_replication_role = origin;

-- Cada cuenta entra una vez al portal: queda con su ficha propia, vacía.
create temporary table test_accounts (uid uuid primary key, phone text);
insert into test_accounts values
  ('b2050000-0000-4000-8000-000000000081', '+56 9 1111 2222'),
  ('b2050000-0000-4000-8000-000000000082', null),
  ('b2050000-0000-4000-8000-000000000083', null),
  ('b2050000-0000-4000-8000-000000000084', null),
  ('b2050000-0000-4000-8000-000000000085', null),
  ('b2050000-0000-4000-8000-000000000087', null);

do $$
declare
  v_account record;
begin
  for v_account in select * from test_accounts loop
    perform set_config('request.jwt.claims',
      json_build_object('sub', v_account.uid, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_account.uid::text, true);
    perform public.provision_current_public_store_customer('b2050000-0000-4000-8000-000000000001');
    -- El teléfono de la creación de la cuenta (lo guarda la tienda al entrar).
    update public.customers
       set phone = v_account.phone
     where tenant_id = 'b2050000-0000-4000-8000-000000000001'
       and auth_user_id = v_account.uid
       and v_account.phone is not null;
  end loop;
end;
$$;

-- Dani ya tiene historial propio en su ficha de la cuenta.
insert into public.bikes (id, tenant_id, customer_id, brand, model)
select 'b2050000-0000-4000-8000-000000000021', customer.tenant_id, customer.id, 'Oxford', 'Rako'
  from public.customers customer
 where customer.tenant_id = 'b2050000-0000-4000-8000-000000000001'
   and customer.auth_user_id = 'b2050000-0000-4000-8000-000000000084';

-- Un código pedido y enviado, con lo que respondió la base guardado en
-- `test.<nombre>`.
create or replace function pg_temp.sent_code(p_name text, p_uid uuid, p_phone text)
returns jsonb
language plpgsql
as $$
declare
  v_answer jsonb;
begin
  v_answer := public.start_customer_phone_verification_internal(
    'b2050000-0000-4000-8000-000000000001', p_uid, p_phone);
  if v_answer ->> 'status' = 'issued' then
    perform public.finish_customer_phone_verification_send_internal(
      (v_answer ->> 'verification_id')::uuid, true, 'wamid.test', null);
  end if;
  perform set_config('test.' || p_name, v_answer::text, true);
  return v_answer;
end;
$$;

create or replace function pg_temp.act_as(p_uid uuid)
returns void
language sql
as $$
  select set_config('request.jwt.claims',
           json_build_object('sub', p_uid, 'role', 'authenticated')::text, true),
         set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
$$;

create or replace function pg_temp.wrong(p_code text)
returns text
language sql
as $$ select lpad(((p_code::integer + 1) % 1000000)::text, 6, '0') $$;

-- ---------------------------------------------------------------------------
-- Quién puede qué
-- ---------------------------------------------------------------------------

select ok(
  not has_function_privilege('authenticated',
    'public.start_customer_phone_verification_internal(uuid, uuid, text)', 'execute')
  and not has_function_privilege('anon',
    'public.start_customer_phone_verification_internal(uuid, uuid, text)', 'execute')
  and has_function_privilege('service_role',
    'public.start_customer_phone_verification_internal(uuid, uuid, text)', 'execute'),
  'el código sale sólo hacia la función que lo manda por WhatsApp'
);
select ok(
  not has_function_privilege('authenticated',
    'public.finish_customer_phone_verification_send_internal(uuid, boolean, text, text)', 'execute'),
  'nadie con sesión marca un código como enviado'
);
select ok(
  has_function_privilege('authenticated', 'public.confirm_customer_phone_verification_v1(uuid, text)', 'execute')
  and not has_function_privilege('anon', 'public.confirm_customer_phone_verification_v1(uuid, text)', 'execute')
  and has_function_privilege('authenticated', 'public.customer_portal_phone_state_v1(uuid)', 'execute')
  and not has_function_privilege('anon', 'public.customer_portal_phone_state_v1(uuid)', 'execute'),
  'la cuenta confirma y lee su estado; sin sesión, nada'
);
select ok(
  not has_table_privilege('authenticated', 'public.customer_portal_phone_verifications', 'select')
  and not has_table_privilege('anon', 'public.customer_portal_phone_verifications', 'select')
  and not has_table_privilege('authenticated', 'public.customer_portal_verified_phones', 'select'),
  'los códigos y los teléfonos confirmados no se leen desde la app'
);
select ok(
  not has_function_privilege('authenticated',
    'public.link_portal_account_to_customer_internal(uuid, uuid, text, uuid, text, text)', 'execute')
  and not has_function_privilege('authenticated',
    'public.customer_has_portal_history_internal(uuid, uuid)', 'execute'),
  'el paso que liga sólo lo llaman el QR y el teléfono'
);
select hasnt_column('public', 'customer_portal_phone_verifications', 'code',
  'el código no se guarda: sólo su hash');

-- ---------------------------------------------------------------------------
-- Pedir el código
-- ---------------------------------------------------------------------------

select is(
  public.start_customer_phone_verification_internal(
    'b2050000-0000-4000-8000-000000000002', 'b2050000-0000-4000-8000-000000000081',
    '+56 9 1111 2222') ->> 'status',
  'disabled',
  'una tienda que no lo encendió no manda códigos'
);
select results_eq(
  $$select public.start_customer_phone_verification_internal(
             'b2050000-0000-4000-8000-000000000001',
             'b2050000-0000-4000-8000-000000000081', phone) ->> 'status'
      from unnest(array['1234', '+56 2 2222 3333', '']) phone$$,
  $$values ('invalid_phone'::text), ('invalid_phone'), ('invalid_phone')$$,
  'sólo se confirma un celular'
);
select throws_ok(
  $$select public.start_customer_phone_verification_internal(
      'b2050000-0000-4000-8000-000000000001',
      'b2050000-0000-4000-8000-000000000086', '+56 9 1111 2222')$$,
  'phone_verification_account_required',
  'una cuenta sin el correo confirmado no pide códigos'
);

select pg_temp.act_as('b2050000-0000-4000-8000-000000000081');
select results_eq(
  $$select (s ->> 'enabled')::boolean, (s ->> 'offer')::boolean, s ->> 'suggested_phone',
           (s ->> 'linked_now')::boolean
      from (select public.customer_portal_phone_state_v1('b2050000-0000-4000-8000-000000000001') s) state$$,
  $$values (true, true, '+56 9 1111 2222'::text, false)$$,
  'una cuenta sin historial ve «Confirma tu teléfono» con el número que dejó al crearla'
);

select results_eq(
  $$select r ->> 'status', r ->> 'phone', r ->> 'phone_hint', (r ->> 'code') ~ '^[0-9]{6}$'
      from (select public.start_customer_phone_verification_internal(
              'b2050000-0000-4000-8000-000000000001',
              'b2050000-0000-4000-8000-000000000081', '+56 9 1111 2222') r) issued$$,
  $$values ('issued'::text, '56911112222'::text, '+56 9 •••• 2222'::text, true)$$,
  'el código sale para el número como lo guarda WhatsApp, y se dice adónde sin mostrarlo entero'
);
select results_eq(
  $$select r ->> 'status', (r ->> 'retry_after_seconds')::integer between 1 and 60
      from (select public.start_customer_phone_verification_internal(
              'b2050000-0000-4000-8000-000000000001',
              'b2050000-0000-4000-8000-000000000081', '+56 9 1111 2222') r) again$$,
  $$values ('too_soon'::text, true)$$,
  'otro código, pasado el minuto'
);

-- Lo pedido recién no salió todavía: no se puede confirmar.
select is(
  public.confirm_customer_phone_verification_v1('b2050000-0000-4000-8000-000000000001', '123456') ->> 'status',
  'expired',
  'un código que WhatsApp no confirmó como enviado no sirve'
);

-- Pasa el minuto y se pide de nuevo: esta vez sale.
update public.customer_portal_phone_verifications
   set created_at = created_at - interval '2 minutes'
 where auth_user_id = 'b2050000-0000-4000-8000-000000000081';
select pg_temp.sent_code('ana', 'b2050000-0000-4000-8000-000000000081', '+56 9 1111 2222');
select is(
  (select count(*)::integer from public.customer_portal_phone_verifications
    where auth_user_id = 'b2050000-0000-4000-8000-000000000081'
      and expires_at > clock_timestamp()),
  1,
  'un código nuevo retira los anteriores'
);
select ok(
  not exists (
    select 1 from public.customer_portal_phone_verifications
     where code_sha256 = encode(extensions.digest(
             convert_to(current_setting('test.ana')::jsonb ->> 'code', 'UTF8'), 'sha256'), 'hex')
  ),
  'el hash lleva el id: el mismo código no da el mismo hash en dos filas'
);

-- ---------------------------------------------------------------------------
-- Confirmar: una ficha con ese número
-- ---------------------------------------------------------------------------

select results_eq(
  format($$select r ->> 'status', (r ->> 'attempts_left')::integer
             from (select public.confirm_customer_phone_verification_v1(
                     'b2050000-0000-4000-8000-000000000001', %L) r) confirmed$$,
         pg_temp.wrong(current_setting('test.ana')::jsonb ->> 'code')),
  $$values ('wrong_code'::text, 4)$$,
  'un código equivocado dice cuántos intentos quedan'
);
select is(
  public.confirm_customer_phone_verification_v1('b2050000-0000-4000-8000-000000000002',
    current_setting('test.ana')::jsonb ->> 'code') ->> 'status',
  'expired',
  'el código de una tienda no sirve en otra'
);
select results_eq(
  format($$select r ->> 'status', r ->> 'first_name'
             from (select public.confirm_customer_phone_verification_v1(
                     'b2050000-0000-4000-8000-000000000001', %L) r) confirmed$$,
         current_setting('test.ana')::jsonb ->> 'code'),
  $$values ('linked'::text, 'Ana'::text)$$,
  'con el código correcto la cuenta queda con la ficha del taller que tiene ese número'
);
select results_eq(
  $$select auth_user_id, email, is_active
      from public.customers where id = 'b2050000-0000-4000-8000-000000000011'$$,
  $$values ('b2050000-0000-4000-8000-000000000081'::uuid, 'ana@example.invalid'::text, true)$$,
  'la ficha del taller toma la cuenta y su correo'
);
select results_eq(
  $$select count(*)::integer, bool_and(not is_active), bool_and(auth_user_id is null),
           bool_and(notes like '%con su teléfono verificado%')
      from public.customers
     where tenant_id = 'b2050000-0000-4000-8000-000000000001'
       and email is null and name like 'ana%'$$,
  $$values (1, true, true, true)$$,
  'la ficha vacía de la cuenta se archiva con la nota de cómo se unió'
);
select is(
  (select raw_app_meta_data -> 'customer_memberships' ->> 'b2050000-0000-4000-8000-000000000001'
     from auth.users where id = 'b2050000-0000-4000-8000-000000000081'),
  'b2050000-0000-4000-8000-000000000011',
  'la membresía de la cuenta apunta a la ficha del taller'
);
select results_eq(
  $$select (s ->> 'offer')::boolean, s ->> 'verified_phone'
      from (select public.customer_portal_phone_state_v1('b2050000-0000-4000-8000-000000000001') s) state$$,
  $$values (false, '+56 9 •••• 2222'::text)$$,
  'confirmado, no se vuelve a ofrecer'
);
select is(
  public.confirm_customer_phone_verification_v1('b2050000-0000-4000-8000-000000000001',
    current_setting('test.ana')::jsonb ->> 'code') ->> 'status',
  'expired',
  'un código sirve una vez'
);

-- ---------------------------------------------------------------------------
-- Confirmar: varias fichas, ninguna, o una cuenta con historial
-- ---------------------------------------------------------------------------

select pg_temp.act_as('b2050000-0000-4000-8000-000000000082');
select pg_temp.sent_code('beto', 'b2050000-0000-4000-8000-000000000082', '+56 9 3333 4444');
select is(
  public.confirm_customer_phone_verification_v1('b2050000-0000-4000-8000-000000000001',
    current_setting('test.beto')::jsonb ->> 'code') ->> 'status',
  'verified_ambiguous',
  'un teléfono de dos fichas no elige ninguna'
);
select is(
  (select count(*)::integer from public.customers
    where id in ('b2050000-0000-4000-8000-000000000012', 'b2050000-0000-4000-8000-000000000013')
      and auth_user_id is null),
  2,
  'las dos fichas siguen sin cuenta'
);

select pg_temp.act_as('b2050000-0000-4000-8000-000000000083');
select pg_temp.sent_code('carla', 'b2050000-0000-4000-8000-000000000083', '+56 9 5555 6666');
select is(
  public.confirm_customer_phone_verification_v1('b2050000-0000-4000-8000-000000000001',
    current_setting('test.carla')::jsonb ->> 'code') ->> 'status',
  'verified',
  'sin ficha con ese número, el teléfono queda confirmado'
);
select is(
  (select phone from public.customers
    where tenant_id = 'b2050000-0000-4000-8000-000000000001'
      and auth_user_id = 'b2050000-0000-4000-8000-000000000083'),
  '+56 9 5555 6666',
  'el número confirmado queda en la ficha de la cuenta, que no tenía uno'
);
select is(
  (select auth_user_id from public.customers where id = 'b2050000-0000-4000-8000-000000000015'),
  null,
  'la ficha de otra tienda con ese número no se toca'
);

select pg_temp.act_as('b2050000-0000-4000-8000-000000000084');
select pg_temp.sent_code('dani', 'b2050000-0000-4000-8000-000000000084', '+56 9 7777 8888');
select is(
  public.confirm_customer_phone_verification_v1('b2050000-0000-4000-8000-000000000001',
    current_setting('test.dani')::jsonb ->> 'code') ->> 'status',
  'verified_has_history',
  'una cuenta con historial propio no se archiva: unirlas lo hace el taller'
);
select is(
  (select auth_user_id from public.customers where id = 'b2050000-0000-4000-8000-000000000014'),
  null,
  'la ficha del taller sigue sin cuenta'
);
select is(
  (select (s ->> 'offer')::boolean
     from (select public.customer_portal_phone_state_v1('b2050000-0000-4000-8000-000000000001') s) state),
  false,
  'a una cuenta con historial propio no se le ofrece'
);

-- ---------------------------------------------------------------------------
-- Al revés: el taller crea la ficha después
-- ---------------------------------------------------------------------------

insert into public.customers (id, tenant_id, name, phone, email, is_active) values
  ('b2050000-0000-4000-8000-000000000016', 'b2050000-0000-4000-8000-000000000001',
   'Carla Soto', '+56955556666', null, true);
set local session_replication_role = replica;
insert into public.mechanic_jobs (
  id, tenant_id, customer_id, job_number, job_type, workflow_kind, status
) values
  ('b2050000-0000-4000-8000-000000000032', 'b2050000-0000-4000-8000-000000000001',
   'b2050000-0000-4000-8000-000000000016', 'PG-F2', 'service', 'service', 'PENDIENTE');
set local session_replication_role = origin;

select pg_temp.act_as('b2050000-0000-4000-8000-000000000083');
select is(
  (select (s ->> 'linked_now')::boolean
     from (select public.customer_portal_phone_state_v1('b2050000-0000-4000-8000-000000000001') s) state),
  true,
  'al entrar, la cuenta queda con la ficha que el taller creó con su teléfono confirmado'
);
select is(
  (select auth_user_id from public.customers where id = 'b2050000-0000-4000-8000-000000000016'),
  'b2050000-0000-4000-8000-000000000083'::uuid,
  'la ficha del taller tiene la cuenta'
);
select is(
  (select (s ->> 'linked_now')::boolean
     from (select public.customer_portal_phone_state_v1('b2050000-0000-4000-8000-000000000001') s) state),
  false,
  'la siguiente entrada no vuelve a ligar'
);

-- ---------------------------------------------------------------------------
-- Intentos y envíos fallidos
-- ---------------------------------------------------------------------------

select pg_temp.act_as('b2050000-0000-4000-8000-000000000085');
select pg_temp.sent_code('eva', 'b2050000-0000-4000-8000-000000000085', '+56 9 9999 0000');
select results_eq(
  format($$select public.confirm_customer_phone_verification_v1(
             'b2050000-0000-4000-8000-000000000001', %L) ->> 'status'
             from generate_series(1, 5)$$,
         pg_temp.wrong(current_setting('test.eva')::jsonb ->> 'code')),
  $$values ('wrong_code'::text), ('wrong_code'), ('wrong_code'), ('wrong_code'), ('too_many_attempts')$$,
  'cinco intentos por código'
);
select is(
  public.confirm_customer_phone_verification_v1('b2050000-0000-4000-8000-000000000001',
    current_setting('test.eva')::jsonb ->> 'code') ->> 'status',
  'too_many_attempts',
  'agotados los intentos, ni el código correcto sirve'
);

select pg_temp.act_as('b2050000-0000-4000-8000-000000000087');
select set_config('test.fallo', public.start_customer_phone_verification_internal(
  'b2050000-0000-4000-8000-000000000001', 'b2050000-0000-4000-8000-000000000087',
  '+56 9 4444 5555')::text, true);
select public.finish_customer_phone_verification_send_internal(
  (current_setting('test.fallo')::jsonb ->> 'verification_id')::uuid, false, null,
  '{"code":132001}');
select is(
  public.confirm_customer_phone_verification_v1('b2050000-0000-4000-8000-000000000001',
    current_setting('test.fallo')::jsonb ->> 'code') ->> 'status',
  'expired',
  'un código que WhatsApp rechazó no se puede confirmar'
);

-- Cinco códigos a un mismo número en un día, aunque sean de cuentas distintas.
insert into public.customer_portal_phone_verifications (
  tenant_id, auth_user_id, phone_digits, code_sha256, expires_at, created_at
)
select 'b2050000-0000-4000-8000-000000000001', 'b2050000-0000-4000-8000-000000000082',
       '56912121212', repeat('a', 64), clock_timestamp() - interval '1 hour',
       clock_timestamp() - make_interval(hours => n)
  from generate_series(2, 6) n;
update public.customer_portal_phone_verifications
   set created_at = created_at - interval '2 minutes'
 where auth_user_id = 'b2050000-0000-4000-8000-000000000087';
select is(
  public.start_customer_phone_verification_internal(
    'b2050000-0000-4000-8000-000000000001', 'b2050000-0000-4000-8000-000000000087',
    '+56 9 1212 1212') ->> 'status',
  'too_many_requests',
  'un número no recibe más de cinco códigos al día'
);

-- Sin sesión o sin correo confirmado.
select pg_temp.act_as(null);
select throws_ok(
  $$select public.confirm_customer_phone_verification_v1('b2050000-0000-4000-8000-000000000001', '123456')$$,
  'phone_verification_account_required',
  'sin sesión no se confirma nada'
);
select pg_temp.act_as('b2050000-0000-4000-8000-000000000086');
select throws_ok(
  $$select public.confirm_customer_phone_verification_v1('b2050000-0000-4000-8000-000000000001', '123456')$$,
  'A confirmed Auth email is required',
  'una cuenta sin el correo confirmado no confirma teléfonos'
);
select is(
  (select (s ->> 'enabled')::boolean
     from (select public.customer_portal_phone_state_v1('b2050000-0000-4000-8000-000000000001') s) state),
  false,
  'ni se le ofrece'
);

-- Lo que ve el taller.
insert into public.user_profiles (user_id, tenant_id, role, permissions)
select id, 'b2050000-0000-4000-8000-000000000001', 'admin', '{}'::jsonb
  from auth.users where id = 'b2050000-0000-4000-8000-000000000087';
select pg_temp.act_as('b2050000-0000-4000-8000-000000000087');
select results_eq(
  $$select (s ->> 'sent_30d')::integer > 0, (s ->> 'confirmed_30d')::integer, (s ->> 'failed_30d')::integer,
           s ? 'phone', s ? 'code'
      from (select public.customer_phone_verification_stats_v1('b2050000-0000-4000-8000-000000000001') s) stats$$,
  $$values (true, 4, 1, false, false)$$,
  'el equipo ve cuántos códigos salieron, se confirmaron y fallaron, sin números ni códigos'
);
select pg_temp.act_as('b2050000-0000-4000-8000-000000000081');
select is(
  public.customer_phone_verification_stats_v1('b2050000-0000-4000-8000-000000000001'),
  null,
  'un cliente no ve las cifras de la tienda'
);

select * from finish();
rollback;
