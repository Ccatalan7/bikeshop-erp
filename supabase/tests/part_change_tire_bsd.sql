begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select no_plan();

-- Cambios de partes, el neumático (20260928110000): su BSD (ISO 5775) va a
-- la rueda en que se instala, declarado —la ficha técnica no está
-- verificada—, sólo al terminar, y sólo si calza con lo que la rueda ya es:
-- el BSD que dice la ficha o, si no lo dice, el aro de la bici leído sin
-- adivinar.
--
-- Datos y claves reales (producción, lectura del 2026-09-28): los rótulos de
-- aro tal como están escritos en las bicis del taller, los neumáticos
-- «MAXXIS ALAMBRE 29X2.25 M315P ARDENT» (622), «Neumatico Bicicleta Aro 27.5
-- X 2.10 Voltage Best» (584), «NEUMATICO ARISUN 26 X 2.10 MOUNT CAMERON»
-- (559) y «Neumático FREEDOM Dual, 29x2.10» (622), y la llanta «Llanta
-- Weinmann U32 TL 29" Ojetillos 32H Presta Negro» (622). Las bicis: Oxford
-- Merak 1 (29"), Avalanche Bullet (26''), Trek 3900 («27.5" - 26"») y una
-- sin aro. Ningún BSD está verificado en producción (todos de texto de
-- proveedor, importación, investigación o nombre).
--
-- La base local no trae el motor de fichas: el lector del producto se
-- reemplaza en esta transacción por una tabla con esos valores; el real se
-- comprueba con el read-back contra producción.

-- ============================================================================
-- ISO 5775 y la relación
-- ============================================================================

-- Cada rótulo real de producción (2026-09-28), con lo que puede medir. La
-- misma tabla que `kIsoBsdCandidatesByWheelLabel` en Dart
-- (`wheel_canonical_data_test.dart` prueba la misma lista).
select is(
  (select jsonb_object_agg(l, to_jsonb(public.iso_bsd_candidates_for_wheel_size(l)))
     from unnest(array[
       '29"', '26"', '29''''', '700', '26''''', '700c', '29', '27.5', '27.5"',
       '26', '27.5''''', '24''''', '20"', '24"', '20', '16', '24', '700''''',
       '16''''', '27.5" - 26"', '28', '12"', '14''''', '650b', '',
       E'29"\t', ' 27,5 " ', '700 c', '2 9', '29er']) l),
  '{"29\"": [622], "26\"": [], "29''''": [622], "700": [622],
    "26''''": [], "700c": [622], "29": [622], "27.5": [584],
    "27.5\"": [584], "26": [], "27.5''''": [584],
    "24''''": [], "20\"": [], "24\"": [], "20": [], "16": [], "24": [],
    "700''''": [622], "16''''": [], "27.5\" - 26\"": [], "28": [], "12\"": [],
    "14''''": [], "650b": [584], "": [],
    "29\"\t": [622], " 27,5 \" ": [584], "700 c": [622], "2 9": [], "29er": []}'::jsonb,
  'sólo refuta un rótulo de un solo diámetro: 29/700c = 622 y 27,5/650b = 584; 26, 24, 20, 16 y 12 tienen más de los que se pueden listar; «28», «2 9» y dos aros en un campo no se leen');

select is(
  (select jsonb_agg(jsonb_build_object(
            'key', bike_fact_key, 'template', template_key,
            'on_mismatch', on_mismatch, 'min', min_value, 'max', max_value)
          order by position)
     from public.bike_fact_spec_links
    where spec_key = 'bead_seat_diameter_mm'
      and template_key = 'tire'),
  '[{"key": "frontWheelBsdMm", "max": 700, "min": 150, "template": "tire", "on_mismatch": "conflict"},
    {"key": "rearWheelBsdMm", "max": 700, "min": 150, "template": "tire", "on_mismatch": "conflict"}]'::jsonb,
  'el BSD del neumático va a su rueda, sólo desde la familia neumático, y tiene que calzar');
select is(
  (select count(*)::integer from public.bike_fact_spec_links
    where spec_key in ('tire_width_mm', 'tire_etrto')),
  0,
  'el ancho no va a la ficha: el catálogo guarda la pulgada nominal convertida, no el ETRTO');
select is(
  public.installed_bike_fact_label('rearWheelBsdMm', '622'::jsonb)
    || ' · ' || public.bike_fact_requirement_text('frontWheelBsdMm', '584')
    || ' · ' || public.bike_fact_requirement_text('bikes.wheel_size', '29"'),
  '622 (29″/700c) en la rueda trasera · la rueda delantera es 584 (27,5″/650b) · aro 29"',
  'se dice como en el taller');
select ok(
  not has_function_privilege('authenticated',
    'public.bike_fact_part_conflict_internal(uuid,uuid,uuid,text,jsonb,jsonb,jsonb,text)', 'EXECUTE')
  and not has_function_privilege('authenticated',
    'public.iso_bsd_candidates_for_wheel_size(text)', 'EXECUTE')
  and not has_function_privilege('authenticated',
    'public.bike_fact_line_wrote_internal(uuid,uuid,uuid,text,jsonb)', 'EXECUTE')
  and has_function_privilege('authenticated',
    'public.job_part_change_writers_v1(uuid)', 'EXECUTE')
  and not has_function_privilege('anon',
    'public.job_part_change_writers_v1(uuid)', 'EXECUTE'),
  'las reglas son internas; el formulario sólo lee quién escribió');

-- ============================================================================
-- Fixture
-- ============================================================================

insert into public.tenants (id, shop_name) values
  ('e2810000-0000-4000-8000-000000000001', 'Taller neumáticos');

-- Sembrar un taller deja su sesión en las variables: se vacían.
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('e2810000-0000-4000-8000-000000000099', 'authenticated', 'authenticated',
   'neumaticos@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('e2810000-0000-4000-8000-000000000098', 'authenticated', 'authenticated',
   'otro-taller@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now());

insert into public.user_profiles (user_id, tenant_id, role) values
  ('e2810000-0000-4000-8000-000000000099',
   'e2810000-0000-4000-8000-000000000001', 'admin');

insert into public.customers (id, tenant_id, name) values
  ('e2810000-0000-4000-8000-000000000010',
   'e2810000-0000-4000-8000-000000000001', 'Cliente neumáticos');

insert into public.bikes (id, tenant_id, customer_id, brand, model, wheel_size) values
  ('e2810000-0000-4000-8000-000000000031',
   'e2810000-0000-4000-8000-000000000001',
   'e2810000-0000-4000-8000-000000000010', 'Oxford', 'Merak 1', '29"'),
  ('e2810000-0000-4000-8000-000000000032',
   'e2810000-0000-4000-8000-000000000001',
   'e2810000-0000-4000-8000-000000000010', 'Avalanche', 'Bullet', '26'''''),
  ('e2810000-0000-4000-8000-000000000033',
   'e2810000-0000-4000-8000-000000000001',
   'e2810000-0000-4000-8000-000000000010', 'Trek', '3900', '27.5" - 26"'),
  ('e2810000-0000-4000-8000-000000000034',
   'e2810000-0000-4000-8000-000000000001',
   'e2810000-0000-4000-8000-000000000010', 'Bici', 'sin aro', null),
  ('e2810000-0000-4000-8000-000000000035',
   'e2810000-0000-4000-8000-000000000001',
   'e2810000-0000-4000-8000-000000000010', 'Bianchi', 'Aggreessor', '26''''');

insert into public.products (id, tenant_id, name, category_name) values
  ('e2810000-0000-4000-8000-000000000101',
   'e2810000-0000-4000-8000-000000000001',
   'MAXXIS ALAMBRE 29X2.25 M315P ARDENT', 'Neumáticos'),
  ('e2810000-0000-4000-8000-000000000102',
   'e2810000-0000-4000-8000-000000000001',
   'Neumatico Bicicleta Aro 27.5 X 2.10 Voltage Best', 'Neumáticos'),
  ('e2810000-0000-4000-8000-000000000103',
   'e2810000-0000-4000-8000-000000000001',
   'NEUMATICO ARISUN 26 X 2.10 MOUNT CAMERON', 'Neumáticos'),
  ('e2810000-0000-4000-8000-000000000104',
   'e2810000-0000-4000-8000-000000000001',
   'Neumático FREEDOM Dual, 29x2.10', 'Neumáticos'),
  ('e2810000-0000-4000-8000-000000000105',
   'e2810000-0000-4000-8000-000000000001',
   'Llanta Weinmann U32 TL 29" Ojetillos 32H Presta Negro', 'Llantas');

-- El lector de la ficha del producto, con lo que dice producción: el BSD de
-- cada neumático y la llanta, ninguno verificado.
create temporary table test_product_specs (
  product_id uuid,
  spec_key text,
  value jsonb,
  template_key text,
  verified boolean default false
);
insert into test_product_specs (product_id, spec_key, value, template_key) values
  ('e2810000-0000-4000-8000-000000000101', 'bead_seat_diameter_mm', '622', 'tire'),
  ('e2810000-0000-4000-8000-000000000101', 'tire_width_mm', '57.1', 'tire'),
  ('e2810000-0000-4000-8000-000000000102', 'bead_seat_diameter_mm', '584', 'tire'),
  ('e2810000-0000-4000-8000-000000000103', 'bead_seat_diameter_mm', '559', 'tire'),
  ('e2810000-0000-4000-8000-000000000104', 'bead_seat_diameter_mm', '622', 'tire'),
  ('e2810000-0000-4000-8000-000000000105', 'bead_seat_diameter_mm', '622', 'rim');

create or replace function public.product_bike_fact_spec_internal(
  p_tenant_id uuid,
  p_product_id uuid,
  p_spec_key text
)
returns jsonb
language sql
stable
as $$
  -- Como el lector real: la familia del producto para cualquier clave
  -- (también `_family`), y el valor de esa clave si lo tiene.
  select jsonb_build_object(
           'value', s.value,
           'template_key', (select f.template_key from test_product_specs f
                             where f.product_id = p.id limit 1),
           'verified', coalesce(s.verified, false))
    from public.products p
    left join test_product_specs s
      on s.product_id = p.id
     and s.spec_key = p_spec_key
   where p.id = p_product_id
     and p.tenant_id = p_tenant_id
     and exists (select 1 from test_product_specs f where f.product_id = p.id)
$$;

insert into public.mechanic_jobs (id, tenant_id, customer_id, bike_id, job_number, created_by) values
  ('e2810000-0000-4000-8000-000000000051',
   'e2810000-0000-4000-8000-000000000001',
   'e2810000-0000-4000-8000-000000000010',
   'e2810000-0000-4000-8000-000000000031', 'PG-NEUM-1',
   'e2810000-0000-4000-8000-000000000099'),
  ('e2810000-0000-4000-8000-000000000052',
   'e2810000-0000-4000-8000-000000000001',
   'e2810000-0000-4000-8000-000000000010',
   'e2810000-0000-4000-8000-000000000032', 'PG-NEUM-2',
   'e2810000-0000-4000-8000-000000000099'),
  ('e2810000-0000-4000-8000-000000000053',
   'e2810000-0000-4000-8000-000000000001',
   'e2810000-0000-4000-8000-000000000010',
   'e2810000-0000-4000-8000-000000000033', 'PG-NEUM-3',
   'e2810000-0000-4000-8000-000000000099'),
  ('e2810000-0000-4000-8000-000000000054',
   'e2810000-0000-4000-8000-000000000001',
   'e2810000-0000-4000-8000-000000000010',
   'e2810000-0000-4000-8000-000000000034', 'PG-NEUM-4',
   'e2810000-0000-4000-8000-000000000099'),
  ('e2810000-0000-4000-8000-000000000055',
   'e2810000-0000-4000-8000-000000000001',
   'e2810000-0000-4000-8000-000000000010',
   'e2810000-0000-4000-8000-000000000034', 'PG-NEUM-5',
   'e2810000-0000-4000-8000-000000000099'),
  ('e2810000-0000-4000-8000-000000000056',
   'e2810000-0000-4000-8000-000000000001',
   'e2810000-0000-4000-8000-000000000010',
   'e2810000-0000-4000-8000-000000000034', 'PG-NEUM-6',
   'e2810000-0000-4000-8000-000000000099'),
  ('e2810000-0000-4000-8000-000000000057',
   'e2810000-0000-4000-8000-000000000001',
   'e2810000-0000-4000-8000-000000000010',
   'e2810000-0000-4000-8000-000000000035', 'PG-NEUM-7',
   'e2810000-0000-4000-8000-000000000099'),
  ('e2810000-0000-4000-8000-000000000058',
   'e2810000-0000-4000-8000-000000000001',
   'e2810000-0000-4000-8000-000000000010',
   'e2810000-0000-4000-8000-000000000035', 'PG-NEUM-8',
   'e2810000-0000-4000-8000-000000000099'),
  ('e2810000-0000-4000-8000-000000000059',
   'e2810000-0000-4000-8000-000000000001',
   'e2810000-0000-4000-8000-000000000010',
   'e2810000-0000-4000-8000-000000000034', 'PG-NEUM-9',
   'e2810000-0000-4000-8000-000000000099'),
  ('e2810000-0000-4000-8000-000000000060',
   'e2810000-0000-4000-8000-000000000001',
   'e2810000-0000-4000-8000-000000000010',
   'e2810000-0000-4000-8000-000000000034', 'PG-NEUM-10',
   'e2810000-0000-4000-8000-000000000099');

insert into public.mechanic_job_bikes (tenant_id, job_id, bike_id)
select 'e2810000-0000-4000-8000-000000000001', j.id, j.bike_id
  from public.mechanic_jobs j
 where j.tenant_id = 'e2810000-0000-4000-8000-000000000001'
on conflict (job_id, bike_id) do nothing;

-- Cada línea va en la pestaña de su bici: una de General no es de ninguna
-- (20261001195000).
-- Trabajo 1 (Oxford 29"): el Ardent atrás y un 27,5 adelante.
-- Trabajo 2 (Avalanche 26''): el Cameron (559) adelante y el Ardent (622)
-- atrás. Trabajo 3 (Trek, «27.5" - 26"»): el Voltage (584) adelante y el
-- Cameron (559) atrás. Trabajo 4 (sin aro): el Ardent adelante. Trabajo 5
-- (la misma bici sin aro, después): el FREEDOM (622) adelante.
insert into public.mechanic_job_items (
  id, tenant_id, job_id, job_bike_id, product_id, product_name, item_type, location_key,
  quantity, unit_price, service_configuration_data
) values
  ('e2810000-0000-4000-8000-000000000061', 'e2810000-0000-4000-8000-000000000001',
   'e2810000-0000-4000-8000-000000000051',
   (select id from public.mechanic_job_bikes where job_id = 'e2810000-0000-4000-8000-000000000051'),
   'e2810000-0000-4000-8000-000000000101',
   'MAXXIS ALAMBRE 29X2.25 M315P ARDENT', 'product', 'rear', 1, 32990,
   '{"part_change": {"key": "rearWheelBsdMm", "value": 622}}'),
  ('e2810000-0000-4000-8000-000000000062', 'e2810000-0000-4000-8000-000000000001',
   'e2810000-0000-4000-8000-000000000051',
   (select id from public.mechanic_job_bikes where job_id = 'e2810000-0000-4000-8000-000000000051'),
   'e2810000-0000-4000-8000-000000000102',
   'Neumatico Bicicleta Aro 27.5 X 2.10 Voltage Best', 'product', 'front', 1, 14990,
   '{"part_change": {"key": "frontWheelBsdMm", "value": 584}}'),
  ('e2810000-0000-4000-8000-000000000063', 'e2810000-0000-4000-8000-000000000001',
   'e2810000-0000-4000-8000-000000000052',
   (select id from public.mechanic_job_bikes where job_id = 'e2810000-0000-4000-8000-000000000052'),
   'e2810000-0000-4000-8000-000000000103',
   'NEUMATICO ARISUN 26 X 2.10 MOUNT CAMERON', 'product', 'front', 1, 12990,
   '{"part_change": {"key": "frontWheelBsdMm", "value": 559}}'),
  ('e2810000-0000-4000-8000-000000000064', 'e2810000-0000-4000-8000-000000000001',
   'e2810000-0000-4000-8000-000000000052',
   (select id from public.mechanic_job_bikes where job_id = 'e2810000-0000-4000-8000-000000000052'),
   'e2810000-0000-4000-8000-000000000101',
   'MAXXIS ALAMBRE 29X2.25 M315P ARDENT', 'product', 'rear', 1, 32990,
   '{"part_change": {"key": "rearWheelBsdMm", "value": 622}}'),
  ('e2810000-0000-4000-8000-000000000065', 'e2810000-0000-4000-8000-000000000001',
   'e2810000-0000-4000-8000-000000000053',
   (select id from public.mechanic_job_bikes where job_id = 'e2810000-0000-4000-8000-000000000053'),
   'e2810000-0000-4000-8000-000000000102',
   'Neumatico Bicicleta Aro 27.5 X 2.10 Voltage Best', 'product', 'front', 1, 14990,
   '{"part_change": {"key": "frontWheelBsdMm", "value": 584}}'),
  ('e2810000-0000-4000-8000-000000000066', 'e2810000-0000-4000-8000-000000000001',
   'e2810000-0000-4000-8000-000000000053',
   (select id from public.mechanic_job_bikes where job_id = 'e2810000-0000-4000-8000-000000000053'),
   'e2810000-0000-4000-8000-000000000103',
   'NEUMATICO ARISUN 26 X 2.10 MOUNT CAMERON', 'product', 'rear', 1, 12990,
   '{"part_change": {"key": "rearWheelBsdMm", "value": 559}}'),
  ('e2810000-0000-4000-8000-000000000067', 'e2810000-0000-4000-8000-000000000001',
   'e2810000-0000-4000-8000-000000000054',
   (select id from public.mechanic_job_bikes where job_id = 'e2810000-0000-4000-8000-000000000054'),
   'e2810000-0000-4000-8000-000000000101',
   'MAXXIS ALAMBRE 29X2.25 M315P ARDENT', 'product', 'front', 1, 32990,
   '{"part_change": {"key": "frontWheelBsdMm", "value": 622}}'),
  ('e2810000-0000-4000-8000-000000000068', 'e2810000-0000-4000-8000-000000000001',
   'e2810000-0000-4000-8000-000000000055',
   (select id from public.mechanic_job_bikes where job_id = 'e2810000-0000-4000-8000-000000000055'),
   'e2810000-0000-4000-8000-000000000104',
   'Neumático FREEDOM Dual, 29x2.10', 'product', 'front', 1, 15990,
   '{"part_change": {"key": "frontWheelBsdMm", "value": 622}}'),
  ('e2810000-0000-4000-8000-000000000071', 'e2810000-0000-4000-8000-000000000001',
   'e2810000-0000-4000-8000-000000000056',
   (select id from public.mechanic_job_bikes where job_id = 'e2810000-0000-4000-8000-000000000056'),
   'e2810000-0000-4000-8000-000000000102',
   'Neumatico Bicicleta Aro 27.5 X 2.10 Voltage Best', 'product', 'front', 1, 14990,
   '{"part_change": {"key": "frontWheelBsdMm", "value": 584}}'),
  -- Trabajos 7 y 8 (Bianchi 26''): dos Voltage adelante, uno después del otro.
  ('e2810000-0000-4000-8000-000000000072', 'e2810000-0000-4000-8000-000000000001',
   'e2810000-0000-4000-8000-000000000057',
   (select id from public.mechanic_job_bikes where job_id = 'e2810000-0000-4000-8000-000000000057'),
   'e2810000-0000-4000-8000-000000000102',
   'Neumatico Bicicleta Aro 27.5 X 2.10 Voltage Best', 'product', 'front', 1, 14990,
   '{"part_change": {"key": "frontWheelBsdMm", "value": 584}}'),
  ('e2810000-0000-4000-8000-000000000073', 'e2810000-0000-4000-8000-000000000001',
   'e2810000-0000-4000-8000-000000000058',
   (select id from public.mechanic_job_bikes where job_id = 'e2810000-0000-4000-8000-000000000058'),
   'e2810000-0000-4000-8000-000000000102',
   'Neumatico Bicicleta Aro 27.5 X 2.10 Voltage Best', 'product', 'front', 1, 14990,
   '{"part_change": {"key": "frontWheelBsdMm", "value": 584}}'),
  -- Trabajo 9 (sin aro): la llanta Weinmann 29" adelante. Trabajo 10: un
  -- Voltage adelante después.
  ('e2810000-0000-4000-8000-000000000074', 'e2810000-0000-4000-8000-000000000001',
   'e2810000-0000-4000-8000-000000000059',
   (select id from public.mechanic_job_bikes where job_id = 'e2810000-0000-4000-8000-000000000059'),
   'e2810000-0000-4000-8000-000000000105',
   'Llanta Weinmann U32 TL 29" Ojetillos 32H Presta Negro', 'product', 'front', 1, 45990,
   '{"part_change": {"key": "frontWheelBsdMm", "value": 622}}'),
  ('e2810000-0000-4000-8000-000000000075', 'e2810000-0000-4000-8000-000000000001',
   'e2810000-0000-4000-8000-000000000060',
   (select id from public.mechanic_job_bikes where job_id = 'e2810000-0000-4000-8000-000000000060'),
   'e2810000-0000-4000-8000-000000000102',
   'Neumatico Bicicleta Aro 27.5 X 2.10 Voltage Best', 'product', 'front', 1, 14990,
   '{"part_change": {"key": "frontWheelBsdMm", "value": 584}}'),
  ('e2810000-0000-4000-8000-000000000076', 'e2810000-0000-4000-8000-000000000001',
   'e2810000-0000-4000-8000-000000000059',
   (select id from public.mechanic_job_bikes where job_id = 'e2810000-0000-4000-8000-000000000059'),
   'e2810000-0000-4000-8000-000000000101',
   'MAXXIS ALAMBRE 29X2.25 M315P ARDENT', 'product', 'front', 1, 24990,
   '{"part_change": {"key": "frontWheelBsdMm", "value": 622}}');

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'e2810000-0000-4000-8000-000000000099', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub',
  'e2810000-0000-4000-8000-000000000099', true);

create temporary table status_ids as
select code, id
  from public.job_statuses
 where tenant_id = 'e2810000-0000-4000-8000-000000000001';

create temporary table results (label text primary key, result jsonb);

create or replace function pg_temp.wheel(p_bike uuid, p_key text)
returns jsonb
language sql
as $$
  select jsonb_build_array(
           bp.technical_profile->'values'->p_key,
           bp.technical_profile->'confirmed'->p_key,
           bp.technical_profile->'sources'->p_key)
    from public.bike_profiles bp
   where bp.bike_id = p_bike
$$;

-- ============================================================================
-- 29": el Ardent calza atrás; un 27,5 no calza adelante
-- ============================================================================

insert into results
select 'uno_en_curso', public.transition_mechanic_job_status(
  'e2810000-0000-4000-8000-000000000051',
  (select id from status_ids where code = 'EN_CURSO'),
  'neum-uno-en-curso');
select is(
  (select count(*)::integer from public.bike_profiles
    where bike_id = 'e2810000-0000-4000-8000-000000000031'),
  0,
  'en curso, la Oxford no tiene ficha que cambie');

select throws_ok(
  $$select public.transition_mechanic_job_status(
    'e2810000-0000-4000-8000-000000000051',
    (select id from status_ids where code = 'FINALIZADO'),
    'neum-uno')$$,
  '23514', null,
  'el 584 delantero no calza con el aro 29 y bloquea el cierre entero');
select is(
  (select status from public.mechanic_jobs
    where id = 'e2810000-0000-4000-8000-000000000051'),
  'EN_CURSO',
  'la incompatibilidad conserva el estado anterior');
select is(
  pg_temp.wheel('e2810000-0000-4000-8000-000000000031', 'rearWheelBsdMm'),
  null::jsonb,
  'el cierre rechazado también deshace la ficha que habría creado el neumático trasero válido');
update public.mechanic_job_items
   set service_configuration_data = '{}'::jsonb
 where id = 'e2810000-0000-4000-8000-000000000062';
insert into results
select 'uno_terminado', public.transition_mechanic_job_status(
  'e2810000-0000-4000-8000-000000000051',
  (select id from status_ids where code = 'FINALIZADO'),
  'neum-uno');

select is(
  (select jsonb_path_query_array(result,
            '$.installed_bike_facts.applied[*] ? (@.key == "rearWheelBsdMm")')
     from results where label = 'uno_terminado')
    #- '{0,item_id}' #- '{0,bike_id}' #- '{0,item_name}',
  '[{"op": "declare", "key": "rearWheelBsdMm", "value": 622, "changed": true, "previous": null,
     "operation_key": "job_completion:e2810000-0000-4000-8000-000000000061:1:rearWheelBsdMm=622"}]'::jsonb,
  'el 622 va atrás, declarado, con la llave de siempre');
select is(
  pg_temp.wheel('e2810000-0000-4000-8000-000000000031', 'rearWheelBsdMm'),
  '[622, null, "job_completion"]'::jsonb,
  'la ficha dice 622 atrás, puesto por el trabajo y sin confirmar');
select is(
  (select jsonb_path_query_array(result,
            '$.installed_bike_facts.problems[*] ? (@.reason == "incompatible")')
     from results where label = 'uno_terminado'),
  '[]'::jsonb,
  'corregida la línea, el cierre ya no deja un neumático incompatible');
select is(
  pg_temp.wheel('e2810000-0000-4000-8000-000000000031', 'frontWheelBsdMm'),
  '[null, null, null]'::jsonb,
  'y no se escribe');
select is(
  (select count(*)::integer from public.bike_events
    where bike_id = 'e2810000-0000-4000-8000-000000000031'
      and event_type = 'installed_fact_incompatible'),
  0,
  'el intento rechazado no deja un aviso histórico de algo no instalado');

-- Replay: la misma llave, entregar y sincronizar.
insert into results
select 'uno_replay', public.transition_mechanic_job_status(
  'e2810000-0000-4000-8000-000000000051',
  (select id from status_ids where code = 'FINALIZADO'),
  'neum-uno');
insert into results
select 'uno_entregado', public.transition_mechanic_job_status(
  'e2810000-0000-4000-8000-000000000051',
  (select id from status_ids where code = 'ENTREGADO'),
  'neum-uno-entregado');
insert into results
select 'uno_sync', public.sync_job_installed_bike_facts_v1(
  'e2810000-0000-4000-8000-000000000051');
select is(
  (select jsonb_build_array(
            (select (result->>'replay')::boolean from results where label = 'uno_replay'),
            (select result->'installed_bike_facts' = (select r.result->'installed_bike_facts'
                                                         from results r where r.label = 'uno_terminado')
               from results where label = 'uno_replay'),
            (select result->'installed_bike_facts'->'applied' from results where label = 'uno_entregado'),
            (select result->'applied' from results where label = 'uno_sync'),
            (select count(*) from public.bike_technical_fact_patches
              where job_id = 'e2810000-0000-4000-8000-000000000051'),
            (select count(*) from public.bike_events
              where bike_id = 'e2810000-0000-4000-8000-000000000031'
                and event_type = 'installed_fact_incompatible'))),
  '[true, true, [], [], 1, 0]'::jsonb,
  'la misma llave devuelve lo mismo; entregar y sincronizar no escriben otro recibo');

-- Conflicto: una llamada directa con lo que ya no dice la ficha. La línea se
-- siembra sin disparadores para que no se aplique sola.
set local session_replication_role = replica;
insert into public.mechanic_job_items (
  id, tenant_id, job_id, job_bike_id, product_id, product_name, item_type, location_key,
  quantity, unit_price, service_configuration_data
) values
  ('e2810000-0000-4000-8000-000000000069', 'e2810000-0000-4000-8000-000000000001',
   'e2810000-0000-4000-8000-000000000051',
   (select id from public.mechanic_job_bikes where job_id = 'e2810000-0000-4000-8000-000000000051'),
   'e2810000-0000-4000-8000-000000000104',
   'Neumático FREEDOM Dual, 29x2.10', 'product', 'front', 1, 15990,
   '{"part_change": {"key": "frontWheelBsdMm", "value": 622}}');
set local session_replication_role = origin;

select throws_ok(
  $$select public.patch_bike_technical_facts_v1(
    'job_completion:e2810000-0000-4000-8000-000000000069:1:frontWheelBsdMm=622',
    'e2810000-0000-4000-8000-000000000031',
    'e2810000-0000-4000-8000-000000000051',
    'job_completion',
    '[{"key": "frontWheelBsdMm", "op": "declare", "value": 622, "expected": 584, "expected_confirmed": false}]'::jsonb)$$,
  'PT409',
  'Bicycle facts changed since they were loaded; reload before saving',
  'con lo que ya no dice la ficha, el parche choca y no escribe');
select throws_ok(
  $$select public.patch_bike_technical_facts_v1(
    'job_completion:e2810000-0000-4000-8000-000000000069:1:frontWheelBsdMm=622',
    'e2810000-0000-4000-8000-000000000031',
    'e2810000-0000-4000-8000-000000000051',
    'job_completion',
    '[{"key": "frontWheelBsdMm", "op": "set", "value": 622, "expected": null, "expected_confirmed": false}]'::jsonb)$$,
  'P0001',
  'The job line did not install frontWheelBsdMm',
  'y lo declarado por la ficha técnica no se confirma por el parche');
select lives_ok(
  $$select public.patch_bike_technical_facts_v1(
    'job_completion:e2810000-0000-4000-8000-000000000069:1:frontWheelBsdMm=622',
    'e2810000-0000-4000-8000-000000000031',
    'e2810000-0000-4000-8000-000000000051',
    'job_completion',
    '[{"key": "frontWheelBsdMm", "op": "declare", "value": 622, "expected": null, "expected_confirmed": false}]'::jsonb)$$,
  'con lo que de verdad dice, la llamada directa declara el 622 adelante');
select is(
  pg_temp.wheel('e2810000-0000-4000-8000-000000000031', 'frontWheelBsdMm'),
  '[622, null, "job_completion"]'::jsonb,
  'la Oxford dice 622 adelante, sin confirmar');

-- ============================================================================
-- 26'': el aro tiene varios diámetros; sólo se refuta lo que queda fuera
-- ============================================================================

insert into results
select 'dos_terminado', public.transition_mechanic_job_status(
  'e2810000-0000-4000-8000-000000000052',
  (select id from status_ids where code = 'FINALIZADO'),
  'neum-dos');
select is(
  jsonb_build_array(
    pg_temp.wheel('e2810000-0000-4000-8000-000000000032', 'frontWheelBsdMm'),
    pg_temp.wheel('e2810000-0000-4000-8000-000000000032', 'rearWheelBsdMm'),
    (select result->'installed_bike_facts'->'problems'
       from results where label = 'dos_terminado')),
  '[[559, null, "job_completion"], [622, null, "job_completion"], []]'::jsonb,
  'una 26'''' no refuta: 26″ son al menos seis diámetros; cada rueda anota su neumático');

-- Línea borrada después de terminar: el 559 se queda y lo dice la historia.
delete from public.mechanic_job_items
 where id = 'e2810000-0000-4000-8000-000000000063';
select is(
  pg_temp.wheel('e2810000-0000-4000-8000-000000000032', 'frontWheelBsdMm'),
  '[559, null, "job_completion"]'::jsonb,
  'borrar la línea no deshace la ficha');
select ok(
  (select summary like '%559 (26″) en la rueda delantera%una línea que ya no está%antes no tenía el dato%Si esa pieza no se instaló%'
     from public.bike_events
    where bike_id = 'e2810000-0000-4000-8000-000000000032'
      and event_type = 'installed_fact_unsupported'),
  'y la historia de la Avalanche lo dice');

-- ============================================================================
-- «27.5" - 26"»: el rótulo no dice nada; cada rueda toma su neumático
-- ============================================================================

insert into results
select 'tres_terminado', public.transition_mechanic_job_status(
  'e2810000-0000-4000-8000-000000000053',
  (select id from status_ids where code = 'FINALIZADO'),
  'neum-tres');
select is(
  jsonb_build_array(
    pg_temp.wheel('e2810000-0000-4000-8000-000000000033', 'frontWheelBsdMm'),
    pg_temp.wheel('e2810000-0000-4000-8000-000000000033', 'rearWheelBsdMm')),
  '[[584, null, "job_completion"], [559, null, "job_completion"]]'::jsonb,
  'la Trek 3900 toma 584 adelante y 559 atrás: dos aros en un campo no refutan nada');

-- Línea cambiada: el Voltage (584) resulta ser el FREEDOM (622). La misma
-- línea se corrige, con su marca, en el trabajo terminado: lo que escribió
-- ella misma no la contradice.
update public.mechanic_job_items
   set product_id = 'e2810000-0000-4000-8000-000000000104',
       product_name = 'Neumático FREEDOM Dual, 29x2.10',
       service_configuration_data = '{"part_change": {"key": "frontWheelBsdMm", "value": 622}}'
 where id = 'e2810000-0000-4000-8000-000000000065';
select is(
  jsonb_build_array(
    pg_temp.wheel('e2810000-0000-4000-8000-000000000033', 'frontWheelBsdMm'),
    (select array_agg(operation_key order by operation_key)
       from public.bike_technical_fact_patches
      where operation_key like 'job_completion:e2810000-0000-4000-8000-000000000065:%')),
  '[[622, null, "job_completion"],
    ["job_completion:e2810000-0000-4000-8000-000000000065:1:frontWheelBsdMm=584",
     "job_completion:e2810000-0000-4000-8000-000000000065:2:frontWheelBsdMm=622"]]'::jsonb,
  'la línea corregida reemplaza lo que ella misma había escrito, con la llave siguiente');

-- Cambiar el neumático sin volver a marcar no se guarda.
select throws_like(
  $$update public.mechanic_job_items
       set product_id = 'e2810000-0000-4000-8000-000000000103',
           product_name = 'NEUMATICO ARISUN 26 X 2.10 MOUNT CAMERON'
     where id = 'e2810000-0000-4000-8000-000000000065'$$,
  '%ya no calza con su repuesto o con la rueda elegida%',
  'otro neumático sin su marca no se guarda');

-- Lo que el mecánico vuelve a elegir en la ficha ya es suyo, aunque sea el
-- mismo número que escribió la línea: la línea cambiada no lo pisa.
update public.bike_profiles
   set technical_profile = technical_profile
         || jsonb_build_object(
              'sources', technical_profile->'sources' || '{"rearWheelBsdMm": "mechanic"}',
              'confirmed', coalesce(technical_profile->'confirmed', '{}') || '{"rearWheelBsdMm": true}')
 where bike_id = 'e2810000-0000-4000-8000-000000000033';
select throws_like(
  $$update public.mechanic_job_items
       set product_id = 'e2810000-0000-4000-8000-000000000102',
           product_name = 'Neumatico Bicicleta Aro 27.5 X 2.10 Voltage Best',
           service_configuration_data = '{"part_change": {"key": "rearWheelBsdMm", "value": 584}}'
     where id = 'e2810000-0000-4000-8000-000000000066'$$,
  '%Voltage Best» no se guardó: 584 (27,5″/650b) en la rueda trasera no calza%la rueda trasera es 559 (26″)%',
  'lo que el mecánico confirmó no lo pisa la línea que antes escribió ese mismo número: en un trabajo terminado, la línea no se guarda');
select is(
  jsonb_build_array(
    pg_temp.wheel('e2810000-0000-4000-8000-000000000033', 'rearWheelBsdMm'),
    (select count(*) from public.bike_technical_fact_patches
      where operation_key like 'job_completion:e2810000-0000-4000-8000-000000000066:%')),
  '[[559, true, "mechanic"], 1]'::jsonb,
  'y la ficha sigue con la medida del mecánico, con un solo recibo');

-- Una llanta no usa la fila del neumático: la suya (20260928140000) cambia
-- la rueda sólo si calza con el neumático de esa rueda, aquí el Arisun de
-- 559 del mismo trabajo.
select throws_like(
  $$insert into public.mechanic_job_items (
      id, tenant_id, job_id, job_bike_id, product_id, product_name, item_type, location_key,
      quantity, unit_price, service_configuration_data)
    values (
      'e2810000-0000-4000-8000-000000000070', 'e2810000-0000-4000-8000-000000000001',
      'e2810000-0000-4000-8000-000000000053',
      (select id from public.mechanic_job_bikes where job_id = 'e2810000-0000-4000-8000-000000000053'),
      'e2810000-0000-4000-8000-000000000105',
      'Llanta Weinmann U32 TL 29" Ojetillos 32H Presta Negro', 'product', 'rear', 1, 45990,
      '{"part_change": {"key": "rearWheelBsdMm", "value": 622}}')$$,
  '%Llanta Weinmann U32 TL 29" Ojetillos 32H Presta Negro» no se guardó: 622 (29″/700c) en la rueda trasera no calza con el neumático que instala el trabajo (el neumático trasero es 559 (26″))%',
  'una llanta de 622 no entra en un trabajo terminado que pone un neumático de 559 en esa rueda');

-- ============================================================================
-- Sin aro: corrección manual posterior
-- ============================================================================

insert into results
select 'cuatro_terminado', public.transition_mechanic_job_status(
  'e2810000-0000-4000-8000-000000000054',
  (select id from status_ids where code = 'FINALIZADO'),
  'neum-cuatro');
select is(
  pg_temp.wheel('e2810000-0000-4000-8000-000000000034', 'frontWheelBsdMm'),
  '[622, null, "job_completion"]'::jsonb,
  'sin aro en la bici, el 622 adelante entra declarado');

-- El mecánico mide la llanta y corrige: 584, confirmado por él.
update public.bike_profiles
   set technical_profile = technical_profile
         || jsonb_build_object(
              'values', technical_profile->'values' || '{"frontWheelBsdMm": 584}',
              'sources', technical_profile->'sources' || '{"frontWheelBsdMm": "mechanic"}',
              'confirmed', coalesce(technical_profile->'confirmed', '{}') || '{"frontWheelBsdMm": true}')
 where bike_id = 'e2810000-0000-4000-8000-000000000034';

insert into results
select 'cuatro_sync', public.sync_job_installed_bike_facts_v1(
  'e2810000-0000-4000-8000-000000000054');
select is(
  jsonb_build_array(
    pg_temp.wheel('e2810000-0000-4000-8000-000000000034', 'frontWheelBsdMm'),
    (select result->'applied' from results where label = 'cuatro_sync'),
    (select result->'problems' from results where label = 'cuatro_sync')),
  '[[584, true, "mechanic"], [], []]'::jsonb,
  'guardar el trabajo después no le pisa la corrección al mecánico ni la reclama');
select throws_ok(
  $$select public.patch_bike_technical_facts_v1(
    'job_completion:e2810000-0000-4000-8000-000000000067:2:frontWheelBsdMm=622',
    'e2810000-0000-4000-8000-000000000034',
    'e2810000-0000-4000-8000-000000000054',
    'job_completion',
    '[{"key": "frontWheelBsdMm", "op": "declare", "value": 622, "expected": 584, "expected_confirmed": true}]'::jsonb)$$,
  'P0001',
  'The job line already installed these facts on this bicycle; later corrections are kept',
  'ni una llamada directa con la llave siguiente');

-- Otro trabajo después, con otro 622 adelante: la rueda es 584 según el
-- mecánico, y el neumático no calza.
select throws_ok(
  $$select public.transition_mechanic_job_status(
    'e2810000-0000-4000-8000-000000000055',
    (select id from status_ids where code = 'FINALIZADO'),
    'neum-cinco')$$,
  '23514', null,
  'otro neumático de 622 no puede cerrar una rueda confirmada como 584');
select is(
  jsonb_build_array(
    (select status from public.mechanic_jobs
       where id = 'e2810000-0000-4000-8000-000000000055'),
    (select count(*) from public.mechanic_job_status_transition_events
       where operation_key = 'neum-cinco'),
    pg_temp.wheel('e2810000-0000-4000-8000-000000000034', 'frontWheelBsdMm')),
  '["PENDIENTE", 0, [584, true, "mechanic"]]'::jsonb,
  'la medición 584 sigue intacta y el cierre rechazado no deja recibo');
-- La llamada directa siguiente representa un trabajo histórico que ya estaba
-- finalizado con una línea incompatible antes de la puerta nueva.
set local session_replication_role = replica;
update public.mechanic_jobs
   set status = 'FINALIZADO',
       status_id = (select id from status_ids where code = 'FINALIZADO')
 where id = 'e2810000-0000-4000-8000-000000000055';
set local session_replication_role = origin;
select throws_ok(
  $$select public.patch_bike_technical_facts_v1(
    'job_completion:e2810000-0000-4000-8000-000000000068:1:frontWheelBsdMm=622',
    'e2810000-0000-4000-8000-000000000034',
    'e2810000-0000-4000-8000-000000000055',
    'job_completion',
    '[{"key": "frontWheelBsdMm", "op": "declare", "value": 622, "expected": 584, "expected_confirmed": true}]'::jsonb)$$,
  '23514',
  'Installed part frontWheelBsdMm does not fit the bicycle (frontWheelBsdMm is 584)',
  'ni por una llamada directa al parche');

-- Y un 584 en la rueda que el mecánico midió en 584: calza, y lo declarado
-- no le quita la confirmación.
insert into results
select 'seis_terminado', public.transition_mechanic_job_status(
  'e2810000-0000-4000-8000-000000000056',
  (select id from status_ids where code = 'FINALIZADO'),
  'neum-seis');
select is(
  jsonb_build_array(
    pg_temp.wheel('e2810000-0000-4000-8000-000000000034', 'frontWheelBsdMm'),
    (select result->'installed_bike_facts'->'problems' from results where label = 'seis_terminado')),
  '[[584, true, "mechanic"], []]'::jsonb,
  'un neumático que dice lo mismo que la medida del mecánico no la desconfirma');

-- ============================================================================
-- Dos líneas en la misma rueda: sólo es suyo lo que de verdad escribió
-- ============================================================================

-- El Voltage del trabajo 7 anota 584 adelante en la Bianchi. El del trabajo
-- 8 dice lo mismo: no escribe nada, aunque su recibo quede.
insert into results
select 'siete_terminado', public.transition_mechanic_job_status(
  'e2810000-0000-4000-8000-000000000057',
  (select id from status_ids where code = 'FINALIZADO'),
  'neum-siete');
insert into results
select 'ocho_terminado', public.transition_mechanic_job_status(
  'e2810000-0000-4000-8000-000000000058',
  (select id from status_ids where code = 'FINALIZADO'),
  'neum-ocho');
select is(
  jsonb_build_array(
    pg_temp.wheel('e2810000-0000-4000-8000-000000000035', 'frontWheelBsdMm'),
    (select coalesce(jsonb_agg(applied), '[]'::jsonb)
       from public.bike_technical_fact_patches
      where operation_key like 'job_completion:e2810000-0000-4000-8000-000000000073:%')),
  '[[584, null, "job_completion"], [[]]]'::jsonb,
  'la segunda línea con el mismo 584 no escribe nada: su recibo queda vacío');

-- La línea del trabajo 8 cambia a un 622 con su marca: el 584 no es suyo.
select throws_like(
  $$update public.mechanic_job_items
       set product_id = 'e2810000-0000-4000-8000-000000000104',
           product_name = 'Neumático FREEDOM Dual, 29x2.10',
           service_configuration_data = '{"part_change": {"key": "frontWheelBsdMm", "value": 622}}'
     where id = 'e2810000-0000-4000-8000-000000000073'$$,
  '%FREEDOM Dual, 29x2.10» no se guardó: 622 (29″/700c) en la rueda delantera no calza%la rueda delantera es 584 (27,5″/650b)%',
  'una línea no se apropia del BSD que escribió otra');
select is(
  jsonb_build_array(
    pg_temp.wheel('e2810000-0000-4000-8000-000000000035', 'frontWheelBsdMm'),
    (select count(*) from public.bike_technical_fact_patches
      where operation_key like 'job_completion:e2810000-0000-4000-8000-000000000073:%')),
  '[[584, null, "job_completion"], 1]'::jsonb,
  'y la Bianchi sigue con el 584 de la primera, sin recibo nuevo');

-- ============================================================================
-- Quién escribió: lo que lee el formulario, y el empate
-- ============================================================================

select is(
  jsonb_build_array(
    public.job_part_change_writers_v1('e2810000-0000-4000-8000-000000000053'),
    public.job_part_change_writers_v1('e2810000-0000-4000-8000-000000000057'),
    public.job_part_change_writers_v1('e2810000-0000-4000-8000-000000000058')),
  '[{"e2810000-0000-4000-8000-000000000065": {"key": "frontWheelBsdMm", "value": 622}},
    {},
    {}]'::jsonb,
  'el formulario sabe qué escribió cada línea: la Trek corregida; ni la trasera que el mecánico volvió a medir, ni las Voltage: la segunda instaló la misma medida después de la primera (20260928120000)');

-- Otro taller no lo lee.
select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'e2810000-0000-4000-8000-000000000098', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub',
  'e2810000-0000-4000-8000-000000000098', true);
select throws_ok(
  $$select public.job_part_change_writers_v1('e2810000-0000-4000-8000-000000000053')$$,
  '42501',
  null,
  'una cuenta de otro taller no lee quién escribió');
select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'e2810000-0000-4000-8000-000000000099', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub',
  'e2810000-0000-4000-8000-000000000099', true);

-- Dos recibos que tocan la clave en el mismo instante: ninguno es «el
-- último» de la línea; ante la duda el valor no es suyo. Uno posterior sí.
set local session_replication_role = replica;
update public.bike_technical_fact_patches b
   set applied = '[{"key": "frontWheelBsdMm", "op": "declare", "from": 584, "to": 584}]',
       completed_at = (select a.completed_at from public.bike_technical_fact_patches a
                        where a.operation_key like 'job_completion:e2810000-0000-4000-8000-000000000072:%')
 where b.operation_key like 'job_completion:e2810000-0000-4000-8000-000000000073:%';
set local session_replication_role = origin;
select is(
  jsonb_build_array(
    public.bike_fact_line_wrote_internal('e2810000-0000-4000-8000-000000000001',
      'e2810000-0000-4000-8000-000000000072', 'e2810000-0000-4000-8000-000000000035',
      'frontWheelBsdMm', '584'::jsonb),
    public.bike_fact_line_wrote_internal('e2810000-0000-4000-8000-000000000001',
      'e2810000-0000-4000-8000-000000000073', 'e2810000-0000-4000-8000-000000000035',
      'frontWheelBsdMm', '584'::jsonb)),
  '[false, false]'::jsonb,
  'con dos recibos en el mismo instante, el valor no es de ninguna de las dos líneas');
set local session_replication_role = replica;
update public.bike_technical_fact_patches b
   set completed_at = b.completed_at + interval '1 second'
 where b.operation_key like 'job_completion:e2810000-0000-4000-8000-000000000073:%';
set local session_replication_role = origin;
select is(
  jsonb_build_array(
    public.bike_fact_line_wrote_internal('e2810000-0000-4000-8000-000000000001',
      'e2810000-0000-4000-8000-000000000072', 'e2810000-0000-4000-8000-000000000035',
      'frontWheelBsdMm', '584'::jsonb),
    public.bike_fact_line_wrote_internal('e2810000-0000-4000-8000-000000000001',
      'e2810000-0000-4000-8000-000000000073', 'e2810000-0000-4000-8000-000000000035',
      'frontWheelBsdMm', '584'::jsonb)),
  '[false, true]'::jsonb,
  'el último recibo que escribió la clave decide');

-- ============================================================================
-- Cada fila dice su regla: una llanta cambia la rueda, un neumático calza
-- ============================================================================

-- La fila de la llanta (familia `rim`, `change`; 20260928140000) junto a la
-- del neumático, con la misma clave: la regla es la de la fila que usa la
-- línea. La llanta cambia la rueda con su neumático nuevo en el mismo trabajo
-- (el Ardent de 622); sin él no calzaría con el que queda.

insert into results
select 'nueve_terminado', public.transition_mechanic_job_status(
  'e2810000-0000-4000-8000-000000000059',
  (select id from status_ids where code = 'FINALIZADO'),
  'neum-nueve');
select is(
  jsonb_build_array(
    pg_temp.wheel('e2810000-0000-4000-8000-000000000034', 'frontWheelBsdMm'),
    (select result->'installed_bike_facts'->'problems' from results where label = 'nueve_terminado')),
  '[[622, null, "job_completion"], []]'::jsonb,
  'la llanta 29" cambia la rueda de 584 a 622: su fila es un cambio');

select throws_ok(
  $$select public.transition_mechanic_job_status(
    'e2810000-0000-4000-8000-000000000060',
    (select id from status_ids where code = 'FINALIZADO'),
    'neum-diez')$$,
  '23514', null,
  'el neumático 584 queda sin cerrar ante la llanta 622 instalada');
select is(
  jsonb_build_array(
    pg_temp.wheel('e2810000-0000-4000-8000-000000000034', 'frontWheelBsdMm'),
    (select status from public.mechanic_jobs
       where id = 'e2810000-0000-4000-8000-000000000060'),
    (select count(*) from public.mechanic_job_status_transition_events
       where operation_key = 'neum-diez')),
  '[[622, null, "job_completion"], "PENDIENTE", 0]'::jsonb,
  'la llanta anterior sigue en la ficha, este trabajo pendiente no deja recibo');

select * from finish();
rollback;
