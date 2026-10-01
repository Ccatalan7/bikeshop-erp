begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select no_plan();

-- Cambios de partes, el rotor (20260928100000): un repuesto instalado cambia
-- la ficha al terminar el trabajo, por la puerta de siempre, sólo si la línea
-- lleva el cambio que el mecánico vio al elegir la rueda y si la pieza calza
-- con la bici real.
--
-- Datos y claves reales (producción, lectura del 2026-09-28): la Scott Scale
-- 960 del taller tiene freno hidráulico confirmado, rotor delantero 203 y
-- trasero 160 confirmados, y recibió un «Disco freno Shimano Deore RT56
-- 180MM» sin rueda; la Norco Charger 9 lleva 160/160; la Trek 820 tiene freno
-- de llanta (V-brake) confirmado. Los diámetros son los que devuelve el
-- lector canónico de fichas para esos productos (`rotor_diameter_mm_value`).
--
-- La base local no trae el motor de fichas (`spec_facts`, plantillas y
-- `spec_active_product_values_internal_v1`; ver
-- docs/development/product-specs-research-2026-09-05/local-engine-restore-2026-09-16.md):
-- aquí el lector del producto se reemplaza, dentro de esta transacción, por
-- una tabla con esos valores. El lector real se comprueba contra producción
-- con su read-back (supabase/manual_checks/verification/20260928100000_*).

-- ============================================================================
-- La relación única y sus permisos
-- ============================================================================

select is(
  (select jsonb_agg(jsonb_build_object(
            'spec', spec_key, 'position', position, 'key', bike_fact_key,
            'requires', requires_fact_key,
            'values', to_jsonb(requires_fact_values))
          order by position)
     from public.bike_fact_spec_links
    where spec_key = 'rotor_diameter_mm_value'),
  '[{"key": "frontRotorSizeMm", "spec": "rotor_diameter_mm_value", "values": ["mechanical_disc", "hydraulic_disc"], "position": "front", "requires": "brakeType"},
    {"key": "rearRotorSizeMm", "spec": "rotor_diameter_mm_value", "values": ["mechanical_disc", "hydraulic_disc"], "position": "rear", "requires": "brakeType"}]'::jsonb,
  'el rotor: diámetro por rueda, y pide freno de disco');
select ok(
  has_table_privilege('authenticated', 'public.bike_fact_spec_links', 'SELECT')
  and not has_table_privilege('authenticated', 'public.bike_fact_spec_links', 'INSERT')
  and not has_table_privilege('authenticated', 'public.bike_fact_spec_links', 'UPDATE')
  and not has_table_privilege('anon', 'public.bike_fact_spec_links', 'SELECT'),
  'la app lee la relación; nadie la escribe desde la app');
select ok(
  not has_function_privilege('authenticated',
    'public.product_bike_fact_spec_value_internal(uuid,uuid,text)', 'EXECUTE')
  and not has_function_privilege('authenticated',
    'public.product_bike_fact_spec_internal(uuid,uuid,text)', 'EXECUTE')
  and not has_function_privilege('authenticated',
    'public.job_line_part_change_internal(uuid,uuid)', 'EXECUTE'),
  'el lector y la regla de la marca son internos');
select ok(
  position('spec_active_product_values_internal_v1' in pg_get_functiondef(
    'public.product_bike_fact_spec_internal(uuid,uuid,text)'::regprocedure)) > 0
  and position('spec_facts' in pg_get_functiondef(
    'public.product_bike_fact_spec_internal(uuid,uuid,text)'::regprocedure)) > 0
  and position('product_bike_fact_spec_internal' in pg_get_functiondef(
    'public.product_bike_fact_spec_value_internal(uuid,uuid,text)'::regprocedure)) > 0,
  'el servidor lee la ficha del producto con el mismo lector que la app, y si el dato está verificado');
select is(
  public.installed_bike_fact_label('rearRotorSizeMm', '180'::jsonb)
    || ' · ' || public.installed_bike_fact_label('frontSpokeHoles', '28'::jsonb),
  '180 mm en el rotor trasero · 28H en la rueda delantera',
  'el rotor se dice como en el taller y las perforaciones no cambian');

-- ============================================================================
-- Fixture
-- ============================================================================

insert into public.tenants (id, shop_name) values
  ('e2800000-0000-4000-8000-000000000001', 'Taller partes A'),
  ('e2800000-0000-4000-8000-000000000002', 'Taller partes B');

-- Sembrar un taller deja su sesión en las variables: se vacían.
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('e2800000-0000-4000-8000-000000000099', 'authenticated', 'authenticated',
   'partes-a@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now());

insert into public.user_profiles (user_id, tenant_id, role) values
  ('e2800000-0000-4000-8000-000000000099',
   'e2800000-0000-4000-8000-000000000001', 'admin');

insert into public.customers (id, tenant_id, name) values
  ('e2800000-0000-4000-8000-000000000010',
   'e2800000-0000-4000-8000-000000000001', 'Cliente partes');

insert into public.bikes (id, tenant_id, customer_id, brand, model, wheel_size) values
  ('e2800000-0000-4000-8000-000000000031',
   'e2800000-0000-4000-8000-000000000001',
   'e2800000-0000-4000-8000-000000000010', 'Scott', 'Scale 960', '29"'),
  ('e2800000-0000-4000-8000-000000000032',
   'e2800000-0000-4000-8000-000000000001',
   'e2800000-0000-4000-8000-000000000010', 'Norco', 'Charger 9', '29"'),
  ('e2800000-0000-4000-8000-000000000033',
   'e2800000-0000-4000-8000-000000000001',
   'e2800000-0000-4000-8000-000000000010', 'Trek', '820', '26"'),
  ('e2800000-0000-4000-8000-000000000034',
   'e2800000-0000-4000-8000-000000000001',
   'e2800000-0000-4000-8000-000000000010', 'Norco', 'Charger 9 (2)', '29"');

insert into public.bike_profiles (tenant_id, bike_id, technical_profile) values
  ('e2800000-0000-4000-8000-000000000001',
   'e2800000-0000-4000-8000-000000000031',
   '{"values": {"brakeType": "hydraulic_disc", "frontRotorSizeMm": 203, "rearRotorSizeMm": 160},
     "sources": {"brakeType": "mechanic", "frontRotorSizeMm": "mechanic", "rearRotorSizeMm": "mechanic"},
     "confirmed": {"brakeType": true, "frontRotorSizeMm": true, "rearRotorSizeMm": true}}'::jsonb),
  ('e2800000-0000-4000-8000-000000000001',
   'e2800000-0000-4000-8000-000000000032',
   '{"values": {"brakeType": "hydraulic_disc", "frontRotorSizeMm": 160, "rearRotorSizeMm": 160},
     "sources": {"brakeType": "mechanic", "frontRotorSizeMm": "mechanic", "rearRotorSizeMm": "mechanic"},
     "confirmed": {"brakeType": true, "frontRotorSizeMm": true, "rearRotorSizeMm": true}}'::jsonb),
  ('e2800000-0000-4000-8000-000000000001',
   'e2800000-0000-4000-8000-000000000033',
   '{"values": {"brakeType": "rim", "rimBrakeFamily": "v_brake"},
     "sources": {"brakeType": "mechanic", "rimBrakeFamily": "mechanic"},
     "confirmed": {"brakeType": true, "rimBrakeFamily": true}}'::jsonb),
  ('e2800000-0000-4000-8000-000000000001',
   'e2800000-0000-4000-8000-000000000034',
   '{"values": {"brakeType": "hydraulic_disc", "frontRotorSizeMm": 160, "rearRotorSizeMm": 160},
     "sources": {"brakeType": "mechanic", "frontRotorSizeMm": "mechanic", "rearRotorSizeMm": "mechanic"},
     "confirmed": {"brakeType": true, "frontRotorSizeMm": true, "rearRotorSizeMm": true}}'::jsonb);

insert into public.products (id, tenant_id, name, category_name) values
  ('e2800000-0000-4000-8000-000000000101',
   'e2800000-0000-4000-8000-000000000001',
   'Disco freno Shimano Deore RT56 180MM', 'Rotores'),
  ('e2800000-0000-4000-8000-000000000102',
   'e2800000-0000-4000-8000-000000000001',
   'Disco freno Shimano Deore RT56 160MM', 'Rotores'),
  ('e2800000-0000-4000-8000-000000000103',
   'e2800000-0000-4000-8000-000000000001',
   'Rotor ZTTO Acero Inoxidable 203x2.3mm', 'Rotores'),
  ('e2800000-0000-4000-8000-000000000104',
   'e2800000-0000-4000-8000-000000000001',
   'Pastillas de freno Shimano B01S resina', 'Pastillas'),
  ('e2800000-0000-4000-8000-000000000105',
   'e2800000-0000-4000-8000-000000000001',
   'Disco freno SRAM 180MM Acero Inoxidable', 'Rotores');

-- El lector de la ficha del producto, con lo que dice producción.
-- Como en producción: ningún dato de ficha técnica está verificado (0 de
-- 4.604 `spec_facts` el 2026-09-28; los diámetros de rotor son lecturas del
-- nombre). El SRAM de 180 se marca verificado sólo para probar que un dato
-- verificado sí se confirma.
create temporary table test_product_specs (
  product_id uuid,
  spec_key text,
  value jsonb,
  template_key text default 'rotor',
  verified boolean default false
);
insert into test_product_specs (product_id, spec_key, value, verified) values
  ('e2800000-0000-4000-8000-000000000101', 'rotor_diameter_mm_value', '180', false),
  ('e2800000-0000-4000-8000-000000000102', 'rotor_diameter_mm_value', '160', false),
  ('e2800000-0000-4000-8000-000000000103', 'rotor_diameter_mm_value', '203', false),
  ('e2800000-0000-4000-8000-000000000105', 'rotor_diameter_mm_value', '180', true);

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
           'template_key', s.template_key,
           'verified', s.verified)
    from test_product_specs s
    join public.products p on p.id = s.product_id
   where s.product_id = p_product_id
     and s.spec_key = p_spec_key
     and p.tenant_id = p_tenant_id
$$;

insert into public.mechanic_jobs (id, tenant_id, customer_id, bike_id, job_number, created_by) values
  ('e2800000-0000-4000-8000-000000000051',
   'e2800000-0000-4000-8000-000000000001',
   'e2800000-0000-4000-8000-000000000010',
   'e2800000-0000-4000-8000-000000000031', 'PG-PARTE-1',
   'e2800000-0000-4000-8000-000000000099'),
  ('e2800000-0000-4000-8000-000000000052',
   'e2800000-0000-4000-8000-000000000001',
   'e2800000-0000-4000-8000-000000000010',
   'e2800000-0000-4000-8000-000000000032', 'PG-PARTE-2',
   'e2800000-0000-4000-8000-000000000099'),
  ('e2800000-0000-4000-8000-000000000053',
   'e2800000-0000-4000-8000-000000000001',
   'e2800000-0000-4000-8000-000000000010',
   'e2800000-0000-4000-8000-000000000033', 'PG-PARTE-3',
   'e2800000-0000-4000-8000-000000000099'),
  ('e2800000-0000-4000-8000-000000000054',
   'e2800000-0000-4000-8000-000000000001',
   'e2800000-0000-4000-8000-000000000010',
   'e2800000-0000-4000-8000-000000000034', 'PG-PARTE-4',
   'e2800000-0000-4000-8000-000000000099');

insert into public.mechanic_job_bikes (tenant_id, job_id, bike_id) values
  ('e2800000-0000-4000-8000-000000000001',
   'e2800000-0000-4000-8000-000000000051',
   'e2800000-0000-4000-8000-000000000031'),
  ('e2800000-0000-4000-8000-000000000001',
   'e2800000-0000-4000-8000-000000000052',
   'e2800000-0000-4000-8000-000000000032'),
  ('e2800000-0000-4000-8000-000000000001',
   'e2800000-0000-4000-8000-000000000053',
   'e2800000-0000-4000-8000-000000000033'),
  ('e2800000-0000-4000-8000-000000000001',
   'e2800000-0000-4000-8000-000000000054',
   'e2800000-0000-4000-8000-000000000034')
on conflict (job_id, bike_id) do nothing;

-- Cada línea va en la pestaña de su bici: una de General no es de ninguna
-- (20261001195000).
-- Trabajo 1 (Scott): el RT56 de 180 va atrás con su marca; un RT56 de 160
-- adelante sin marca (como las 4 líneas antiguas con rueda: no cambia nada),
-- y unas pastillas en General.
-- Trabajo 2 (Norco): un ZTTO de 203 adelante con marca, que se borra antes de
-- terminar. Trabajo 3 (Trek, freno de llanta): un RT56 de 180 adelante.
-- Trabajo 4 (otra Norco): un RT56 de 180 atrás cuya marca dice 160.
insert into public.mechanic_job_items (
  id, tenant_id, job_id, job_bike_id, product_id, product_name, item_type,
  location_key, quantity, unit_price, service_configuration_data
) values
  ('e2800000-0000-4000-8000-000000000061',
   'e2800000-0000-4000-8000-000000000001',
   'e2800000-0000-4000-8000-000000000051',
   (select id from public.mechanic_job_bikes
     where job_id = 'e2800000-0000-4000-8000-000000000051'),
   'e2800000-0000-4000-8000-000000000101',
   'Disco freno Shimano Deore RT56 180MM', 'product', 'rear', 1, 25990,
   '{"part_change": {"key": "rearRotorSizeMm", "value": 180}}'::jsonb),
  ('e2800000-0000-4000-8000-000000000062',
   'e2800000-0000-4000-8000-000000000001',
   'e2800000-0000-4000-8000-000000000051',
   (select id from public.mechanic_job_bikes
     where job_id = 'e2800000-0000-4000-8000-000000000051'),
   'e2800000-0000-4000-8000-000000000102',
   'Disco freno Shimano Deore RT56 160MM', 'product', 'front', 1, 22990, null),
  ('e2800000-0000-4000-8000-000000000063',
   'e2800000-0000-4000-8000-000000000001',
   'e2800000-0000-4000-8000-000000000051', null,
   'e2800000-0000-4000-8000-000000000104',
   'Pastillas de freno Shimano B01S resina', 'product', 'none', 1, 8990, null),
  ('e2800000-0000-4000-8000-000000000064',
   'e2800000-0000-4000-8000-000000000001',
   'e2800000-0000-4000-8000-000000000052',
   (select id from public.mechanic_job_bikes
     where job_id = 'e2800000-0000-4000-8000-000000000052'),
   'e2800000-0000-4000-8000-000000000103',
   'Rotor ZTTO Acero Inoxidable 203x2.3mm', 'product', 'front', 1, 19990,
   '{"part_change": {"key": "frontRotorSizeMm", "value": 203}}'::jsonb),
  ('e2800000-0000-4000-8000-000000000065',
   'e2800000-0000-4000-8000-000000000001',
   'e2800000-0000-4000-8000-000000000053',
   (select id from public.mechanic_job_bikes
     where job_id = 'e2800000-0000-4000-8000-000000000053'),
   'e2800000-0000-4000-8000-000000000101',
   'Disco freno Shimano Deore RT56 180MM', 'product', 'front', 1, 25990,
   '{"part_change": {"key": "frontRotorSizeMm", "value": 180}}'::jsonb),
  ('e2800000-0000-4000-8000-000000000066',
   'e2800000-0000-4000-8000-000000000001',
   'e2800000-0000-4000-8000-000000000054',
   (select id from public.mechanic_job_bikes
     where job_id = 'e2800000-0000-4000-8000-000000000054'),
   'e2800000-0000-4000-8000-000000000101',
   'Disco freno Shimano Deore RT56 180MM', 'product', 'rear', 1, 25990,
   '{"part_change": {"key": "rearRotorSizeMm", "value": 160}}'::jsonb);

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'e2800000-0000-4000-8000-000000000099', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub',
  'e2800000-0000-4000-8000-000000000099', true);

create temporary table status_ids as
select code, id
  from public.job_statuses
 where tenant_id = 'e2800000-0000-4000-8000-000000000001';

create temporary table results (label text primary key, result jsonb);

create temporary table scott_profile as
select technical_profile
  from public.bike_profiles
 where bike_id = 'e2800000-0000-4000-8000-000000000031';

-- ============================================================================
-- La marca, leída con la regla única
-- ============================================================================

select is(
  public.job_line_part_change_internal(
    'e2800000-0000-4000-8000-000000000001',
    'e2800000-0000-4000-8000-000000000061')
    - 'link_id'
    || jsonb_build_object('link_is_rear_rotor', (
         select l.bike_fact_key = 'rearRotorSizeMm'
           from public.bike_fact_spec_links l
          where l.id = (public.job_line_part_change_internal(
                  'e2800000-0000-4000-8000-000000000001',
                  'e2800000-0000-4000-8000-000000000061')->>'link_id')::uuid)),
  '{"key": "rearRotorSizeMm", "value": 180, "spec_key": "rotor_diameter_mm_value", "position": "rear", "verified": false, "on_mismatch": "change", "template_key": "rotor", "link_is_rear_rotor": true}'::jsonb,
  'la línea del RT56 de 180 atrás respalda 180 mm en el rotor trasero, con su fila');
select is(
  public.job_line_part_change_internal(
    'e2800000-0000-4000-8000-000000000002',
    'e2800000-0000-4000-8000-000000000061'),
  null,
  'otro taller no lee la línea');
select is(
  public.job_line_part_change_internal(
    'e2800000-0000-4000-8000-000000000001',
    'e2800000-0000-4000-8000-000000000062'),
  null,
  'una línea con rueda y sin marca no instala nada');
select is(
  public.job_line_part_change_internal(
    'e2800000-0000-4000-8000-000000000001',
    'e2800000-0000-4000-8000-000000000066'),
  null,
  'una marca de 160 en un RT56 de 180 no se respalda');

-- ============================================================================
-- Reemplazo: 160 → 180 atrás, sólo al terminar
-- ============================================================================

insert into results
select 'en_curso', public.transition_mechanic_job_status(
  'e2800000-0000-4000-8000-000000000051',
  (select id from status_ids where code = 'EN_CURSO'),
  'parte-en-curso');

select is(
  (select technical_profile from public.bike_profiles
    where bike_id = 'e2800000-0000-4000-8000-000000000031'),
  (select technical_profile from scott_profile),
  'con el trabajo en curso la ficha de la Scott no cambia');

insert into results
select 'terminado', public.transition_mechanic_job_status(
  'e2800000-0000-4000-8000-000000000051',
  (select id from status_ids where code = 'FINALIZADO'),
  'parte-terminado');

select is(
  (select jsonb_path_query_array(result, '$.installed_bike_facts.applied[*].operation_key')
     from results where label = 'terminado'),
  '["job_completion:e2800000-0000-4000-8000-000000000061:1:rearRotorSizeMm=180"]'::jsonb,
  'terminar escribe el rotor trasero con la llave de siempre, una vez');
select is(
  (select result#>'{installed_bike_facts,applied,0,previous}'
     from results where label = 'terminado'),
  '160'::jsonb,
  'la respuesta dice lo que había: 160');
select is(
  (select technical_profile->'values'->'rearRotorSizeMm' || jsonb_build_array(
            technical_profile->'confirmed'->'rearRotorSizeMm',
            technical_profile->'sources'->'rearRotorSizeMm')
     from public.bike_profiles
    where bike_id = 'e2800000-0000-4000-8000-000000000031'),
  '[180, null, "job_completion"]'::jsonb,
  'la ficha dice 180 atrás, puesto por el trabajo pero sin confirmar: el 180 es una lectura del nombre (20260928110000)');
select is(
  (select technical_profile->'values'->'frontRotorSizeMm'
     from public.bike_profiles
    where bike_id = 'e2800000-0000-4000-8000-000000000031'),
  '203'::jsonb,
  'el RT56 de 160 adelante sin marca no pisa el 203 que el taller confirmó');
select is(
  (select result->'installed_bike_facts'->'problems' from results where label = 'terminado'),
  '[]'::jsonb,
  'ni las pastillas ni la línea sin marca son un problema');
select is(
  (select count(*)::integer from public.bike_events
    where bike_id = 'e2800000-0000-4000-8000-000000000031'
      and job_id = 'e2800000-0000-4000-8000-000000000051'
      and source = 'job_completion'),
  1,
  'la historia de la bici cuenta el cambio');

-- ============================================================================
-- Replay: la misma llave, el mismo estado, la sincronización
-- ============================================================================

insert into results
select 'replay', public.transition_mechanic_job_status(
  'e2800000-0000-4000-8000-000000000051',
  (select id from status_ids where code = 'FINALIZADO'),
  'parte-terminado');
insert into results
select 'entregado', public.transition_mechanic_job_status(
  'e2800000-0000-4000-8000-000000000051',
  (select id from status_ids where code = 'ENTREGADO'),
  'parte-entregado');
insert into results
select 'sync', public.sync_job_installed_bike_facts_v1(
  'e2800000-0000-4000-8000-000000000051');

select is(
  (select (result->>'replay')::boolean from results where label = 'replay'),
  true,
  'la misma llave devuelve el recibo de la transición');
select is(
  (select result->'installed_bike_facts' from results where label = 'replay'),
  (select result->'installed_bike_facts' from results where label = 'terminado'),
  'con la misma respuesta');
select is(
  (select jsonb_build_array(
            (select result->'installed_bike_facts'->'applied' from results where label = 'entregado'),
            (select result->'applied' from results where label = 'sync'))),
  '[[], []]'::jsonb,
  'entregar y sincronizar no escriben lo que ya está');
select is(
  (select count(*)::integer from public.bike_technical_fact_patches
    where tenant_id = 'e2800000-0000-4000-8000-000000000001'
      and job_id = 'e2800000-0000-4000-8000-000000000051'),
  1,
  'un solo recibo del trabajo');

-- El parche directo con la misma llave y el mismo contenido es un replay.
select is(
  (public.patch_bike_technical_facts_v1(
    'job_completion:e2800000-0000-4000-8000-000000000061:1:rearRotorSizeMm=180',
    'e2800000-0000-4000-8000-000000000031',
    'e2800000-0000-4000-8000-000000000051',
    'job_completion',
    '[{"key": "rearRotorSizeMm", "op": "declare", "value": 180, "expected": 160, "expected_confirmed": true}]'::jsonb
  )->>'replayed')::boolean,
  true,
  'el parche con la llave ya usada no escribe de nuevo');

-- El parche no acepta un rotor que ninguna línea respalde.
select throws_ok(
  $$select public.patch_bike_technical_facts_v1(
    'job_completion:e2800000-0000-4000-8000-000000000062:1:frontRotorSizeMm=160',
    'e2800000-0000-4000-8000-000000000031',
    'e2800000-0000-4000-8000-000000000051',
    'job_completion',
    '[{"key": "frontRotorSizeMm", "op": "declare", "value": 160, "expected": 203, "expected_confirmed": true}]'::jsonb)$$,
  'P0001',
  'The job line did not install frontRotorSizeMm',
  'una línea con rueda y sin marca no instala un rotor, tampoco por el parche');
select throws_ok(
  $$select public.patch_bike_technical_facts_v1(
    'job_completion:e2800000-0000-4000-8000-000000000061:9:rearRotorSizeMm=203',
    'e2800000-0000-4000-8000-000000000031',
    'e2800000-0000-4000-8000-000000000051',
    'job_completion',
    '[{"key": "rearRotorSizeMm", "op": "declare", "value": 203, "expected": 180, "expected_confirmed": true}]'::jsonb)$$,
  'P0001',
  'The job line did not install rearRotorSizeMm',
  'la línea del RT56 de 180 no respalda 203');
select throws_ok(
  $$select public.patch_bike_technical_facts_v1(
    'job_completion:e2800000-0000-4000-8000-000000000061:9:frontRotorSizeMm=180',
    'e2800000-0000-4000-8000-000000000031',
    'e2800000-0000-4000-8000-000000000051',
    'job_completion',
    '[{"key": "frontRotorSizeMm", "op": "declare", "value": 180, "expected": 203, "expected_confirmed": true}]'::jsonb)$$,
  'P0001',
  'The job line did not install frontRotorSizeMm',
  'ni lo respalda en la otra rueda');

-- Revisión de Codex (2026-09-28): una línea delantera sin `hole_count` dejaba
-- pasar 28H por un nulo en la condición del parche (desde 20260928020000).
select throws_ok(
  $$select public.patch_bike_technical_facts_v1(
    'job_completion:e2800000-0000-4000-8000-000000000062:1:frontSpokeHoles=28',
    'e2800000-0000-4000-8000-000000000031',
    'e2800000-0000-4000-8000-000000000051',
    'job_completion',
    '[{"key": "frontSpokeHoles", "op": "set", "value": 28, "expected": null, "expected_confirmed": false}]'::jsonb)$$,
  'P0001',
  'The job line did not install frontSpokeHoles',
  'una línea delantera sin perforaciones no instala 28H por el parche');
select is(
  (select technical_profile->'values' ? 'frontSpokeHoles'
     from public.bike_profiles
    where bike_id = 'e2800000-0000-4000-8000-000000000031'),
  false,
  'la ficha de la Scott no toma perforaciones');

-- ============================================================================
-- Línea borrada
-- ============================================================================

-- Antes de terminar: el ZTTO de 203 de la Norco se quita y el trabajo termina.
delete from public.mechanic_job_items
 where id = 'e2800000-0000-4000-8000-000000000064';
insert into results
select 'norco_terminado', public.transition_mechanic_job_status(
  'e2800000-0000-4000-8000-000000000052',
  (select id from status_ids where code = 'FINALIZADO'),
  'parte-norco');

select is(
  (select technical_profile->'values'->'frontRotorSizeMm'
     from public.bike_profiles
    where bike_id = 'e2800000-0000-4000-8000-000000000032'),
  '160'::jsonb,
  'una línea borrada antes de terminar nunca cambia la bici');
select is(
  (select count(*)::integer from public.bike_technical_fact_patches
    where job_id = 'e2800000-0000-4000-8000-000000000052')
  + (select count(*)::integer from public.bike_events
      where job_id = 'e2800000-0000-4000-8000-000000000052'
        and source in ('job_completion', 'installed_fact_notice')),
  0,
  'ni deja recibo ni aviso');

-- Después de terminar: el RT56 de 180 de la Scott se borra.
delete from public.mechanic_job_items
 where id = 'e2800000-0000-4000-8000-000000000061';

select is(
  (select technical_profile->'values'->'rearRotorSizeMm'
     from public.bike_profiles
    where bike_id = 'e2800000-0000-4000-8000-000000000031'),
  '180'::jsonb,
  'borrarla no deshace la ficha en silencio: no se sabe si el rotor se sacó');
select ok(
  (select summary like '%180 mm en el rotor trasero%una línea que ya no está%antes: 160 mm en el rotor trasero%Si esa pieza no se instaló%'
     from public.bike_events
    where bike_id = 'e2800000-0000-4000-8000-000000000031'
      and source = 'installed_fact_notice'
      and event_type = 'installed_fact_unsupported'),
  'queda el aviso en la historia de la bici, en la misma transacción, con lo que había antes');

insert into results
select 'scott_sync_borrada', public.sync_job_installed_bike_facts_v1(
  'e2800000-0000-4000-8000-000000000051');

select is(
  (select jsonb_path_query_array(result, '$.problems[*].reason')
     from results where label = 'scott_sync_borrada'),
  '["no_longer_installed"]'::jsonb,
  'guardar el trabajo lo sigue diciendo');
select is(
  (select count(*)::integer from public.bike_events
    where bike_id = 'e2800000-0000-4000-8000-000000000031'
      and source = 'installed_fact_notice'),
  1,
  'el aviso se anota una vez');

-- ============================================================================
-- Incompatibilidad: un rotor en una bici con freno de llanta
-- ============================================================================

select throws_ok(
  $$select public.transition_mechanic_job_status(
    'e2800000-0000-4000-8000-000000000053',
    (select id from status_ids where code = 'FINALIZADO'),
    'parte-trek')$$,
  '23514', null,
  'un rotor de 180 ante freno de llanta confirmado bloquea el cierre');
select is(
  (select status from public.mechanic_jobs
    where id = 'e2800000-0000-4000-8000-000000000053'),
  'PENDIENTE',
  'la Trek sigue pendiente, sin cierre parcial');
select is(
  (select technical_profile->'values' ? 'frontRotorSizeMm'
     from public.bike_profiles
    where bike_id = 'e2800000-0000-4000-8000-000000000033'),
  false,
  'la ficha de la Trek no toma un rotor');
select is(
  (select count(*)::integer from public.bike_technical_fact_patches
    where job_id = 'e2800000-0000-4000-8000-000000000053'),
  0,
  'ni queda un recibo');
select is(
  (select count(*)::integer from public.mechanic_job_status_transition_events
    where operation_key = 'parte-trek'),
  0,
  'el cierre rechazado no deja recibo y puede repetirse tras corregir');
select throws_ok(
  $$select public.transition_mechanic_job_status(
    'e2800000-0000-4000-8000-000000000053',
    (select id from status_ids where code = 'ENTREGADO'),
    'parte-trek-entregado')$$,
  '23514', null,
  'tampoco se puede entregar una pieza incompatible');
select is(
  (select count(*)::integer from public.bike_events
    where bike_id = 'e2800000-0000-4000-8000-000000000033'
      and event_type = 'installed_fact_incompatible'),
  0,
  'el aviso dentro de un intento rechazado se deshace con la transacción');

-- Revisión de Codex: el parche directo también mira la ficha, bajo su lock.
-- Esta llamada directa representa un trabajo histórico que ya había quedado
-- finalizado antes de que el nuevo cierre bloqueara la incompatibilidad.
set local session_replication_role = replica;
update public.mechanic_jobs
   set status = 'FINALIZADO',
       status_id = (select id from status_ids where code = 'FINALIZADO')
 where id = 'e2800000-0000-4000-8000-000000000053';
set local session_replication_role = origin;
select throws_ok(
  $$select public.patch_bike_technical_facts_v1(
    'job_completion:e2800000-0000-4000-8000-000000000065:1:frontRotorSizeMm=180',
    'e2800000-0000-4000-8000-000000000033',
    'e2800000-0000-4000-8000-000000000053',
    'job_completion',
    '[{"key": "frontRotorSizeMm", "op": "declare", "value": 180, "expected": null, "expected_confirmed": false}]'::jsonb)$$,
  '23514',
  'Installed part frontRotorSizeMm does not fit the bicycle (brakeType is rim)',
  'una llamada directa al parche tampoco pone un rotor en la Trek');
select is(
  (select count(*)::integer from public.bike_technical_fact_patches
    where job_id = 'e2800000-0000-4000-8000-000000000053')
  + (select (technical_profile->'values' ? 'frontRotorSizeMm')::integer
       from public.bike_profiles
      where bike_id = 'e2800000-0000-4000-8000-000000000033'),
  0,
  'ni recibo ni rotor en la ficha');
-- La puerta de edición también protege ese trabajo histórico incompatible.
-- El aplicador mira si calza sólo dentro de la sentencia que toma la ficha
-- (`for update`, después de tomar la bici), y el parche después de tomarla.
select ok(
  (select count(*) from regexp_matches(pg_get_functiondef(
     'public.apply_job_installed_bike_facts_internal(uuid,uuid,boolean)'::regprocedure),
     'bike_fact_part_misfit_internal', 'g')) = 1
  and pg_get_functiondef(
     'public.apply_job_installed_bike_facts_internal(uuid,uuid,boolean)'::regprocedure)
     -- Desde 20260928130000 la ficha se toma una vez por línea y cada dato
     -- se mira después, con la bici y la ficha tomadas.
     ~ 'from public\.bikes b[^;]*for update;\s+v_profile_values := null;\s+v_profile_sources := null;\s+v_profile_confirmed := null;\s+select[^;]*from public\.bike_profiles bp[^;]*for update;[^$]*bike_fact_part_misfit_internal\([^$]*bike_fact_part_conflict_internal\('
  and (select count(*) from regexp_matches(pg_get_functiondef(
     'public.apply_job_installed_bike_facts_internal(uuid,uuid,boolean)'::regprocedure),
     'bike_fact_part_conflict_internal', 'g')) = 1
  and strpos(pg_get_functiondef(
        'public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)'::regprocedure),
        'v_conflict := public.bike_fact_part_conflict_internal(')
      > strpos(pg_get_functiondef(
        'public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)'::regprocedure),
        'v_profile_exists := found;')
  and strpos(pg_get_functiondef(
        'public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)'::regprocedure),
        'v_misfit_value := public.bike_fact_part_misfit_internal(')
      > strpos(pg_get_functiondef(
        'public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)'::regprocedure),
        'v_profile_exists := found;')
  and strpos(pg_get_functiondef(
        'public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)'::regprocedure),
        'v_profile_exists := found;') > 0,
  'el aplicador y el parche miran si calza con la ficha ya tomada, no antes');

-- Una línea que cambia la ficha no se mueve a otro trabajo.
select throws_like(
  $$update public.mechanic_job_items
       set job_id = 'e2800000-0000-4000-8000-000000000051',
           job_bike_id = (select id from public.mechanic_job_bikes
                           where job_id = 'e2800000-0000-4000-8000-000000000051')
     where id = 'e2800000-0000-4000-8000-000000000065'$$,
  '%no pasa a otro trabajo%',
  'mover el rotor de la Trek al trabajo de la Scott se detiene');

-- Una línea nueva con rotor en el trabajo terminado de la Trek no se guarda.
select throws_ok(
  $$insert into public.mechanic_job_items (
      id, tenant_id, job_id, job_bike_id, product_id, product_name, item_type,
      location_key, quantity, unit_price, service_configuration_data)
    values (
      'e2800000-0000-4000-8000-000000000067',
      'e2800000-0000-4000-8000-000000000001',
      'e2800000-0000-4000-8000-000000000053',
      (select id from public.mechanic_job_bikes
        where job_id = 'e2800000-0000-4000-8000-000000000053'),
      'e2800000-0000-4000-8000-000000000102',
      'Disco freno Shimano Deore RT56 160MM', 'product', 'rear', 1, 22990,
      '{"part_change": {"key": "rearRotorSizeMm", "value": 160}}'::jsonb)$$,
  '23514',
  '«Disco freno Shimano Deore RT56 160MM» no se guardó: 160 mm en el rotor trasero no calza con la ficha de la bici (tipo de freno «Llanta (rim)»). En un trabajo terminado la línea y la ficha se guardan juntas: corrige la ficha o la línea.',
  'en un trabajo terminado un rotor que no calza no se guarda, y lo dice');
select ok(
  not exists (select 1 from public.mechanic_job_items
               where id = 'e2800000-0000-4000-8000-000000000067'),
  'y la línea no queda');

-- Un repuesto sin relación en un trabajo terminado se guarda como siempre.
select lives_ok(
  $$insert into public.mechanic_job_items (
      id, tenant_id, job_id, product_id, product_name, item_type,
      location_key, quantity, unit_price)
    values (
      'e2800000-0000-4000-8000-000000000068',
      'e2800000-0000-4000-8000-000000000001',
      'e2800000-0000-4000-8000-000000000053',
      'e2800000-0000-4000-8000-000000000104',
      'Pastillas de freno Shimano B01S resina', 'product', 'none', 1, 8990)$$,
  'unas pastillas en el trabajo terminado de la Trek se guardan');

-- ============================================================================
-- Marca vencida: la línea dice 160 y el repuesto es de 180
-- ============================================================================

select throws_ok(
  $$select public.transition_mechanic_job_status(
    'e2800000-0000-4000-8000-000000000054',
    (select id from status_ids where code = 'FINALIZADO'),
    'parte-norco2')$$,
  '23514', null,
  'la marca 160 vencida ante un repuesto 180 impide cerrar');
select is(
  (select technical_profile->'values'->'rearRotorSizeMm'
     from public.bike_profiles
    where bike_id = 'e2800000-0000-4000-8000-000000000034'),
  '160'::jsonb,
  'la Norco sigue en 160 atrás');

-- El mecánico corrige primero la marca; el cierre con la misma llave ya puede
-- instalar el dato verdadero en la misma transacción.
update public.mechanic_job_items
   set service_configuration_data = '{"part_change": {"key": "rearRotorSizeMm", "value": 180}}'::jsonb
 where id = 'e2800000-0000-4000-8000-000000000066';

insert into results
select 'norco2_terminado', public.transition_mechanic_job_status(
  'e2800000-0000-4000-8000-000000000054',
  (select id from status_ids where code = 'FINALIZADO'),
  'parte-norco2');

select is(
  (select technical_profile->'values'->'rearRotorSizeMm'
     from public.bike_profiles
    where bike_id = 'e2800000-0000-4000-8000-000000000034'),
  '180'::jsonb,
  'corregida la marca antes del cierre, la ficha pasa a 180 con la línea');

-- Cambiar la rueda o el repuesto sin volver a marcar no se guarda.
select throws_like(
  $$update public.mechanic_job_items
       set location_key = 'front'
     where id = 'e2800000-0000-4000-8000-000000000066'$$,
  '%ya no calza con su repuesto o con la rueda elegida%',
  'pasar el rotor a la otra rueda sin su marca no se guarda');
select throws_like(
  $$update public.mechanic_job_items
       set product_id = 'e2800000-0000-4000-8000-000000000102',
           product_name = 'Disco freno Shimano Deore RT56 160MM'
     where id = 'e2800000-0000-4000-8000-000000000066'$$,
  '%ya no calza con su repuesto o con la rueda elegida%',
  'cambiar el repuesto por uno de 160 sin su marca tampoco');
select is(
  (select array[location_key, product_id::text]
     from public.mechanic_job_items
    where id = 'e2800000-0000-4000-8000-000000000066'),
  array['rear', 'e2800000-0000-4000-8000-000000000101'],
  'la línea queda como estaba');

-- ============================================================================
-- La bici de una línea es la de su fila: ni la cabecera ni General
-- ============================================================================

-- Trabajo 5: la cabecera dice Scott, pero su única fila de bicis es la
-- Norco. Una línea de la Norco es de la Norco, también para el parche. Lleva
-- además una línea mal formada que dice perforaciones y un repuesto.
insert into public.mechanic_jobs (id, tenant_id, customer_id, bike_id, job_number, created_by)
values ('e2800000-0000-4000-8000-000000000055',
        'e2800000-0000-4000-8000-000000000001',
        'e2800000-0000-4000-8000-000000000010',
        'e2800000-0000-4000-8000-000000000031', 'PG-PARTE-5',
        'e2800000-0000-4000-8000-000000000099');
delete from public.mechanic_job_bikes
 where job_id = 'e2800000-0000-4000-8000-000000000055';
insert into public.mechanic_job_bikes (tenant_id, job_id, bike_id) values
  ('e2800000-0000-4000-8000-000000000001',
   'e2800000-0000-4000-8000-000000000055',
   'e2800000-0000-4000-8000-000000000032');
insert into public.mechanic_job_items (
  id, tenant_id, job_id, job_bike_id, product_id, product_name, item_type,
  location_key, quantity, unit_price, service_configuration_data
) values
  ('e2800000-0000-4000-8000-000000000069',
   'e2800000-0000-4000-8000-000000000001',
   'e2800000-0000-4000-8000-000000000055',
   (select id from public.mechanic_job_bikes
     where job_id = 'e2800000-0000-4000-8000-000000000055'),
   'e2800000-0000-4000-8000-000000000101',
   'Disco freno Shimano Deore RT56 180MM', 'product', 'rear', 1, 25990,
   '{"part_change": {"key": "rearRotorSizeMm", "value": 180}}'::jsonb),
  ('e2800000-0000-4000-8000-000000000070',
   'e2800000-0000-4000-8000-000000000001',
   'e2800000-0000-4000-8000-000000000055',
   (select id from public.mechanic_job_bikes
     where job_id = 'e2800000-0000-4000-8000-000000000055'),
   'e2800000-0000-4000-8000-000000000103',
   'Rotor ZTTO Acero Inoxidable 203x2.3mm', 'product', 'front', 1, 19990,
   '{"hole_count": "28", "part_change": {"key": "frontRotorSizeMm", "value": 203}}'::jsonb);

select is(
  public.job_line_bike_internal(
    'e2800000-0000-4000-8000-000000000001',
    'e2800000-0000-4000-8000-000000000069'),
  'e2800000-0000-4000-8000-000000000032'::uuid,
  'la línea es de la bici de su fila, no de la cabecera');

-- General es lo que el cliente compra aparte: no es de ninguna bici, tampoco
-- en un trabajo de una sola (dueño, 2026-10-01).
select is(
  public.job_line_bike_internal(
    'e2800000-0000-4000-8000-000000000001',
    'e2800000-0000-4000-8000-000000000063'),
  null::uuid,
  'las pastillas de General no son de la única bici del trabajo');

select throws_ok(
  $$select public.transition_mechanic_job_status(
    'e2800000-0000-4000-8000-000000000055',
    (select id from status_ids where code = 'FINALIZADO'),
    'parte-cinco')$$,
  '23514', null,
  'una línea que dice Enrayado y rotor a la vez bloquea el cierre');
select is(
  (select technical_profile->'values'->'rearRotorSizeMm'
     from public.bike_profiles
    where bike_id = 'e2800000-0000-4000-8000-000000000032'),
  '160'::jsonb,
  'el intento rechazado también deshace la otra línea válida del trabajo');
update public.mechanic_job_items
   set service_configuration_data = '{}'::jsonb
 where id = 'e2800000-0000-4000-8000-000000000070';
insert into results
select 'cinco_terminado', public.transition_mechanic_job_status(
  'e2800000-0000-4000-8000-000000000055',
  (select id from status_ids where code = 'FINALIZADO'),
  'parte-cinco');

select is(
  (select jsonb_build_array(
            (select technical_profile->'values'->'rearRotorSizeMm'
               from public.bike_profiles
              where bike_id = 'e2800000-0000-4000-8000-000000000032'),
            (select jsonb_path_query_array(result, '$.installed_bike_facts.problems[*].reason')
               from results where label = 'cinco_terminado'),
            (select technical_profile->'values'->'frontRotorSizeMm'
               from public.bike_profiles
              where bike_id = 'e2800000-0000-4000-8000-000000000032'))),
  '[180, [], 160]'::jsonb,
  'corregida la línea mixta, el rotor va a la Norco y no a la bici de cabecera');
select throws_ok(
  $$select public.patch_bike_technical_facts_v1(
    'job_completion:e2800000-0000-4000-8000-000000000069:2:rearRotorSizeMm=180',
    'e2800000-0000-4000-8000-000000000031',
    'e2800000-0000-4000-8000-000000000055',
    'job_completion',
    '[{"key": "rearRotorSizeMm", "op": "declare", "value": 180, "expected": 160, "expected_confirmed": true}]'::jsonb)$$,
  '42501',
  'The job line is not part of this job and bicycle',
  'el parche no lo escribe en la Scott de la cabecera');
select throws_ok(
  $$insert into public.mechanic_job_items (
      id, tenant_id, job_id, job_bike_id, product_id, product_name, item_type,
      location_key, quantity, unit_price, service_configuration_data)
    values (
      'e2800000-0000-4000-8000-000000000071',
      'e2800000-0000-4000-8000-000000000001',
      'e2800000-0000-4000-8000-000000000055',
      (select id from public.mechanic_job_bikes
        where job_id = 'e2800000-0000-4000-8000-000000000055'),
      'e2800000-0000-4000-8000-000000000102',
      'Disco freno Shimano Deore RT56 160MM', 'product', 'front', 1, 22990,
      '{"hole_count": "28", "part_change": {"key": "frontRotorSizeMm", "value": 160}}'::jsonb)$$,
  '23514',
  '«Disco freno Shimano Deore RT56 160MM» no se guardó: dice perforaciones y un cambio de repuesto a la vez, y una línea instala una sola cosa.',
  'en un trabajo terminado una línea mixta no se guarda');

-- ============================================================================
-- Revisión de Codex: lo ya instalado no se vuelve a imponer
-- ============================================================================

-- El taller corrige la ficha de la otra Norco a 160 atrás después de que la
-- línea escribió 180. Una llamada directa con la llave siguiente no la pisa.
update public.bike_profiles
   set technical_profile = jsonb_set(
         jsonb_set(technical_profile, '{values,rearRotorSizeMm}', '160'::jsonb),
         '{sources,rearRotorSizeMm}', '"mechanic"'::jsonb)
 where bike_id = 'e2800000-0000-4000-8000-000000000034';

select throws_ok(
  $$select public.patch_bike_technical_facts_v1(
    'job_completion:e2800000-0000-4000-8000-000000000066:2:rearRotorSizeMm=180',
    'e2800000-0000-4000-8000-000000000034',
    'e2800000-0000-4000-8000-000000000054',
    'job_completion',
    '[{"key": "rearRotorSizeMm", "op": "declare", "value": 180, "expected": 160, "expected_confirmed": true}]'::jsonb)$$,
  'P0001',
  'The job line already installed these facts on this bicycle; later corrections are kept',
  'lo que la línea ya escribió no se impone de nuevo con otra llave');
select is(
  (select technical_profile->'values'->'rearRotorSizeMm'
     from public.bike_profiles
    where bike_id = 'e2800000-0000-4000-8000-000000000034'),
  '160'::jsonb,
  'la corrección del taller se queda');

-- ============================================================================
-- Declarado o confirmado (20260928110000)
-- ============================================================================

-- Trabajo 6: un SRAM de 180 cuya ficha técnica está verificada, adelante en
-- la Norco (160 confirmado). Trabajo 7: un ZTTO de 203 adelante en la Scott,
-- que ya tiene 203 confirmado por el mecánico.
insert into public.mechanic_jobs (id, tenant_id, customer_id, bike_id, job_number, created_by) values
  ('e2800000-0000-4000-8000-000000000056',
   'e2800000-0000-4000-8000-000000000001',
   'e2800000-0000-4000-8000-000000000010',
   'e2800000-0000-4000-8000-000000000032', 'PG-PARTE-6',
   'e2800000-0000-4000-8000-000000000099'),
  ('e2800000-0000-4000-8000-000000000057',
   'e2800000-0000-4000-8000-000000000001',
   'e2800000-0000-4000-8000-000000000010',
   'e2800000-0000-4000-8000-000000000031', 'PG-PARTE-7',
   'e2800000-0000-4000-8000-000000000099');
insert into public.mechanic_job_bikes (tenant_id, job_id, bike_id) values
  ('e2800000-0000-4000-8000-000000000001',
   'e2800000-0000-4000-8000-000000000056',
   'e2800000-0000-4000-8000-000000000032'),
  ('e2800000-0000-4000-8000-000000000001',
   'e2800000-0000-4000-8000-000000000057',
   'e2800000-0000-4000-8000-000000000031')
on conflict (job_id, bike_id) do nothing;
insert into public.mechanic_job_items (
  id, tenant_id, job_id, job_bike_id, product_id, product_name, item_type,
  location_key, quantity, unit_price, service_configuration_data
) values
  ('e2800000-0000-4000-8000-000000000072',
   'e2800000-0000-4000-8000-000000000001',
   'e2800000-0000-4000-8000-000000000056',
   (select id from public.mechanic_job_bikes where job_id = 'e2800000-0000-4000-8000-000000000056'),
   'e2800000-0000-4000-8000-000000000105',
   'Disco freno SRAM 180MM Acero Inoxidable', 'product', 'front', 1, 24990,
   '{"part_change": {"key": "frontRotorSizeMm", "value": 180}}'::jsonb),
  ('e2800000-0000-4000-8000-000000000073',
   'e2800000-0000-4000-8000-000000000001',
   'e2800000-0000-4000-8000-000000000057',
   (select id from public.mechanic_job_bikes where job_id = 'e2800000-0000-4000-8000-000000000057'),
   'e2800000-0000-4000-8000-000000000103',
   'Rotor ZTTO Acero Inoxidable 203x2.3mm', 'product', 'front', 1, 19990,
   '{"part_change": {"key": "frontRotorSizeMm", "value": 203}}'::jsonb);

insert into results
select 'seis_terminado', public.transition_mechanic_job_status(
  'e2800000-0000-4000-8000-000000000056',
  (select id from status_ids where code = 'FINALIZADO'),
  'parte-seis');
insert into results
select 'siete_terminado', public.transition_mechanic_job_status(
  'e2800000-0000-4000-8000-000000000057',
  (select id from status_ids where code = 'FINALIZADO'),
  'parte-siete');

select is(
  (select jsonb_build_array(
            (select result#>'{installed_bike_facts,applied,0,op}'
               from results where label = 'seis_terminado'),
            (select technical_profile->'values'->'frontRotorSizeMm'
               from public.bike_profiles
              where bike_id = 'e2800000-0000-4000-8000-000000000032'),
            (select technical_profile->'confirmed'->'frontRotorSizeMm'
               from public.bike_profiles
              where bike_id = 'e2800000-0000-4000-8000-000000000032'))),
  '["set", 180, true]'::jsonb,
  'un dato verificado de la ficha técnica sí queda confirmado');
-- Dos líneas marcadas que todavía no se aplicaron (sembradas sin
-- disparadores): el parche exige `set` para lo verificado y `declare` para
-- lo que no lo está.
set local session_replication_role = replica;
insert into public.mechanic_job_items (
  id, tenant_id, job_id, job_bike_id, product_id, product_name, item_type,
  location_key, quantity, unit_price, service_configuration_data
) values
  ('e2800000-0000-4000-8000-000000000074',
   'e2800000-0000-4000-8000-000000000001',
   'e2800000-0000-4000-8000-000000000056',
   (select id from public.mechanic_job_bikes where job_id = 'e2800000-0000-4000-8000-000000000056'),
   'e2800000-0000-4000-8000-000000000105',
   'Disco freno SRAM 180MM Acero Inoxidable', 'product', 'rear', 1, 24990,
   '{"part_change": {"key": "rearRotorSizeMm", "value": 180}}'::jsonb),
  ('e2800000-0000-4000-8000-000000000075',
   'e2800000-0000-4000-8000-000000000001',
   'e2800000-0000-4000-8000-000000000057',
   (select id from public.mechanic_job_bikes where job_id = 'e2800000-0000-4000-8000-000000000057'),
   'e2800000-0000-4000-8000-000000000101',
   'Disco freno Shimano Deore RT56 180MM', 'product', 'rear', 1, 25990,
   '{"part_change": {"key": "rearRotorSizeMm", "value": 180}}'::jsonb);
set local session_replication_role = origin;

select throws_ok(
  $$select public.patch_bike_technical_facts_v1(
    'job_completion:e2800000-0000-4000-8000-000000000074:1:rearRotorSizeMm=180',
    'e2800000-0000-4000-8000-000000000032',
    'e2800000-0000-4000-8000-000000000056',
    'job_completion',
    '[{"key": "rearRotorSizeMm", "op": "declare", "value": 180, "expected": 180, "expected_confirmed": false}]'::jsonb)$$,
  'P0001',
  'The job line did not install rearRotorSizeMm',
  'lo verificado no se degrada a declarado por el parche');
select throws_ok(
  $$select public.patch_bike_technical_facts_v1(
    'job_completion:e2800000-0000-4000-8000-000000000075:1:rearRotorSizeMm=180',
    'e2800000-0000-4000-8000-000000000031',
    'e2800000-0000-4000-8000-000000000057',
    'job_completion',
    '[{"key": "rearRotorSizeMm", "op": "set", "value": 180, "expected": 180, "expected_confirmed": false}]'::jsonb)$$,
  'P0001',
  'The job line did not install rearRotorSizeMm',
  'y lo que sólo está declarado no se confirma por el parche');
select is(
  (select jsonb_build_array(
            (select result#>'{installed_bike_facts,applied,0,changed}'
               from results where label = 'siete_terminado'),
            (select technical_profile->'values'->'frontRotorSizeMm'
               from public.bike_profiles
              where bike_id = 'e2800000-0000-4000-8000-000000000031'),
            (select technical_profile->'confirmed'->'frontRotorSizeMm'
               from public.bike_profiles
              where bike_id = 'e2800000-0000-4000-8000-000000000031'),
            (select technical_profile->'sources'->'frontRotorSizeMm'
               from public.bike_profiles
              where bike_id = 'e2800000-0000-4000-8000-000000000031'))),
  '[false, 203, true, "mechanic"]'::jsonb,
  'lo declarado igual a lo que confirmó el mecánico no le quita la confirmación');

select * from finish();
rollback;
