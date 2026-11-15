begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select no_plan();

-- Un repuesto de una sola rueda va en ella aunque la línea no la diga
-- (20261115063000). El caso real, del 2026-11-14: un trabajo con dos bicis,
-- el piñón de rosca FW-734 en una (con su rueda) y el cassette CS-HG200-7 en
-- la otra, con la marca «Shimano HG en el driver trasero» y la línea sin
-- rueda. El cierre la rechazaba como `stale_change` y el trabajo no se podía
-- entregar. Un rotor va en las dos ruedas: sin rueda, su marca sigue sin
-- verificarse y el cierre sigue pidiendo la rueda.
--
-- La base local no trae el motor de fichas: el lector del producto se
-- reemplaza en esta transacción, como en part_change_rear_cogs.

select ok(
  not has_function_privilege('authenticated',
    'public.part_line_single_wheel_internal(uuid,uuid)', 'EXECUTE')
  and not has_function_privilege('anon',
    'public.part_line_single_wheel_internal(uuid,uuid)', 'EXECUTE')
  and not has_function_privilege('authenticated',
    'public.job_line_part_change_internal(uuid,uuid,text)', 'EXECUTE'),
  'la rueda de un repuesto y la verificación de su marca son internas');

-- ============================================================================
-- Fixture
-- ============================================================================

insert into public.tenants (id, shop_name) values
  ('e2840000-0000-4000-8000-000000000001', 'Taller una rueda');

-- El alta del taller deja su propia sesión puesta: se limpia.
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('e2840000-0000-4000-8000-000000000099', 'authenticated', 'authenticated',
   'una-rueda@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now());

insert into public.user_profiles (user_id, tenant_id, role) values
  ('e2840000-0000-4000-8000-000000000099',
   'e2840000-0000-4000-8000-000000000001', 'admin');

insert into public.customers (id, tenant_id, name) values
  ('e2840000-0000-4000-8000-000000000010',
   'e2840000-0000-4000-8000-000000000001', 'Cliente una rueda');

insert into public.bikes (id, tenant_id, customer_id, brand, model)
select ('e2840000-0000-4000-8000-0000000000' || b.n)::uuid,
       'e2840000-0000-4000-8000-000000000001',
       'e2840000-0000-4000-8000-000000000010', b.brand, b.model
  from (values
    ('31', 'Trek', 'Marlin 5'), ('32', 'Bianchi', 'Advantage'),
    ('33', 'GT', 'Outpost')
  ) b(n, brand, model);

-- Como en producción: el mecánico dejó el driver en «desconocido», sin
-- confirmar, y la transmisión 3x7 confirmada.
insert into public.bike_profiles (tenant_id, bike_id, technical_profile)
select 'e2840000-0000-4000-8000-000000000001', b.id,
       '{"values": {"freehubType": "unknown", "drivetrainConfig": "3x7", "drivetrainSpeeds": 21},
         "sources": {"freehubType": "mechanic", "drivetrainConfig": "mechanic", "drivetrainSpeeds": "mechanic"},
         "confirmed": {"drivetrainConfig": true, "drivetrainSpeeds": true}}'::jsonb
  from public.bikes b
 where b.tenant_id = 'e2840000-0000-4000-8000-000000000001';

insert into public.products (id, tenant_id, name, category_name)
select ('e2840000-0000-4000-8000-000000000' || p.n)::uuid,
       'e2840000-0000-4000-8000-000000000001', p.name, p.category
  from (values
    ('101', 'Piñon 7 Veloc 12/32T CS-HG200-7V', 'Transmisión'),
    ('102', 'PIÑON FW-734 FOR 7 SPEED 14-34T,COLOR:BR+ED, INDEX WITH FALCON LOGO PACKING:1PCON WHITE BOX', 'Transmisión'),
    ('103', 'Rotor Shimano SM-RT26 160 mm', 'Frenos')
  ) p(n, name, category);

create temporary table test_product_templates (
  product_id uuid primary key,
  template_key text
);
insert into test_product_templates values
  ('e2840000-0000-4000-8000-000000000101', 'cassette'),
  ('e2840000-0000-4000-8000-000000000102', 'freewheel'),
  ('e2840000-0000-4000-8000-000000000103', 'rotor');

create temporary table test_product_specs (
  product_id uuid,
  spec_key text,
  value jsonb,
  verified boolean default false
);
insert into test_product_specs (product_id, spec_key, value) values
  ('e2840000-0000-4000-8000-000000000101', 'cassette_spline_standard', '"Shimano HG spline S (7v)"'),
  ('e2840000-0000-4000-8000-000000000101', 'sprocket_count', '7'),
  ('e2840000-0000-4000-8000-000000000102', 'sprocket_count', '7'),
  ('e2840000-0000-4000-8000-000000000103', 'rotor_diameter_mm_value', '160');

create or replace function public.product_bike_fact_spec_internal(
  p_tenant_id uuid,
  p_product_id uuid,
  p_spec_key text
)
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
           'value', s.value,
           'template_key', t.template_key,
           'verified', coalesce(s.verified, false))
    from test_product_templates t
    join public.products p on p.id = t.product_id
    left join test_product_specs s
      on s.product_id = t.product_id
     and s.spec_key = p_spec_key
   where t.product_id = p_product_id
     and p.tenant_id = p_tenant_id
$$;

-- 051: las dos bicis del caso (la Trek en la cabecera). 052: un rotor sin
-- rueda en la GT.
insert into public.mechanic_jobs (id, tenant_id, customer_id, bike_id, job_number, created_by)
select ('e2840000-0000-4000-8000-000000000' || j.n)::uuid,
       'e2840000-0000-4000-8000-000000000001',
       'e2840000-0000-4000-8000-000000000010',
       ('e2840000-0000-4000-8000-0000000000' || j.bike)::uuid,
       'PG-UNA-' || j.n,
       'e2840000-0000-4000-8000-000000000099'
  from (values ('051', '31'), ('052', '33')) j(n, bike);

insert into public.mechanic_job_bikes (tenant_id, job_id, bike_id) values
  ('e2840000-0000-4000-8000-000000000001',
   'e2840000-0000-4000-8000-000000000051',
   'e2840000-0000-4000-8000-000000000031'),
  ('e2840000-0000-4000-8000-000000000001',
   'e2840000-0000-4000-8000-000000000051',
   'e2840000-0000-4000-8000-000000000032'),
  ('e2840000-0000-4000-8000-000000000001',
   'e2840000-0000-4000-8000-000000000052',
   'e2840000-0000-4000-8000-000000000033')
on conflict (job_id, bike_id) do nothing;

insert into public.mechanic_job_items (
  id, tenant_id, job_id, job_bike_id, product_id, product_name, item_type,
  location_key, quantity, unit_price, service_configuration_data
)
select ('e2840000-0000-4000-8000-000000000' || l.n)::uuid,
       'e2840000-0000-4000-8000-000000000001',
       ('e2840000-0000-4000-8000-000000000' || l.job)::uuid,
       (select jb.id from public.mechanic_job_bikes jb
         where jb.job_id = ('e2840000-0000-4000-8000-000000000' || l.job)::uuid
           and jb.bike_id = ('e2840000-0000-4000-8000-0000000000' || l.bike)::uuid),
       p.id, p.name, 'product', l.location_key, 1, 19990,
       coalesce(l.data::jsonb, '{}'::jsonb)
  from (values
    -- El cassette de la Trek: con su marca y sin rueda, como quedó guardado.
    ('161', '051', '31', '101', 'none', '{"part_change": {"key": "freehubType", "value": "shimano_hg"}}'),
    -- El piñón de rosca de la Bianchi: con su rueda y sin marca.
    ('162', '051', '32', '102', 'rear', null),
    -- Un rotor con marca y sin rueda: va en las dos, no se supone ninguna.
    ('163', '052', '33', '103', 'none', '{"part_change": {"key": "rearRotorSizeMm", "value": 160}}')
  ) l(n, job, bike, product, location_key, data)
  join public.products p on p.id = ('e2840000-0000-4000-8000-000000000' || l.product)::uuid;

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'e2840000-0000-4000-8000-000000000099', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub',
  'e2840000-0000-4000-8000-000000000099', true);

create temporary table status_ids as
select code, id
  from public.job_statuses
 where tenant_id = 'e2840000-0000-4000-8000-000000000001';

create temporary table results (label text primary key, result jsonb);

create or replace function pg_temp.fact(p_bike text, p_key text)
returns jsonb
language sql
as $$
  select jsonb_build_array(
           bp.technical_profile->'values'->p_key,
           bp.technical_profile->'confirmed'->p_key,
           bp.technical_profile->'sources'->p_key)
    from public.bike_profiles bp
   where bp.bike_id = ('e2840000-0000-4000-8000-0000000000' || p_bike)::uuid
$$;

create or replace function pg_temp.finish(p_job text, p_code text default 'FINALIZADO')
returns jsonb
language sql
as $$
  select public.transition_mechanic_job_status(
    ('e2840000-0000-4000-8000-000000000' || p_job)::uuid,
    (select id from status_ids where code = p_code),
    'una-' || p_job || '-' || p_code);
$$;

create or replace function pg_temp.blocked_finish(p_job text)
returns jsonb
language plpgsql
as $$
declare
  v_detail text;
  v_hint text;
begin
  perform pg_temp.finish(p_job);
  raise exception 'Se esperaba un cierre bloqueado para %', p_job;
exception when check_violation then
  get stacked diagnostics v_detail = PG_EXCEPTION_DETAIL,
                          v_hint = PG_EXCEPTION_HINT;
  if v_hint is distinct from 'job_completion_blocked' then
    raise;
  end if;
  return coalesce((
    select jsonb_agg(problem - 'item_id' - 'bike_id' - 'item_name')
      from jsonb_array_elements(v_detail::jsonb->'problems') problem),
    '[]'::jsonb);
end;
$$;

-- ============================================================================
-- La rueda de un repuesto
-- ============================================================================

select is(
  jsonb_build_array(
    public.part_line_single_wheel_internal(
      'e2840000-0000-4000-8000-000000000001', 'e2840000-0000-4000-8000-000000000101'),
    public.part_line_single_wheel_internal(
      'e2840000-0000-4000-8000-000000000001', 'e2840000-0000-4000-8000-000000000102'),
    public.part_line_single_wheel_internal(
      'e2840000-0000-4000-8000-000000000001', 'e2840000-0000-4000-8000-000000000103'),
    public.part_line_single_wheel_internal(
      'e2840000-0000-4000-8000-000000000001', null)),
  '["rear", "rear", null, null]'::jsonb,
  'un cassette y un piñón de rosca de 7 coronas van atrás; un rotor va en las dos ruedas');

select is(
  public.job_line_part_change_internal(
    'e2840000-0000-4000-8000-000000000001',
    'e2840000-0000-4000-8000-000000000161', 'freehubType') - 'link_id',
  '{"key": "freehubType", "value": "shimano_hg", "spec_key": "cassette_spline_standard",
    "position": "rear", "on_mismatch": "conflict", "template_key": "cassette", "verified": false}'::jsonb,
  'el cassette sin rueda respalda Shimano HG en el driver trasero: va atrás');

select ok(
  public.job_line_part_change_internal(
    'e2840000-0000-4000-8000-000000000001',
    'e2840000-0000-4000-8000-000000000163', 'rearRotorSizeMm') is null,
  'un rotor sin rueda no dice cuál: su marca no se verifica');

-- ============================================================================
-- El cierre
-- ============================================================================

insert into results select 'dos_bicis', pg_temp.finish('051');
select is(
  jsonb_build_array(
    (select result->'installed_bike_facts'->'problems' from results where label = 'dos_bicis'),
    pg_temp.fact('31', 'freehubType'),
    pg_temp.fact('32', 'freehubType')),
  '[[], ["shimano_hg", null, "job_completion"], ["unknown", null, "mechanic"]]'::jsonb,
  'el trabajo de dos bicis se cierra: la Trek toma Shimano HG, declarado, y la Bianchi no cambia');

select is(
  pg_temp.blocked_finish('052'),
  '[{"key": "rearRotorSizeMm", "value": 160, "reason": "stale_change"}]'::jsonb,
  'el rotor sin rueda sigue pidiendo la rueda antes de cerrar');

select * from finish();
rollback;
