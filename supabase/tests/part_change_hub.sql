begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select no_plan();

-- Cambios de partes, la maza (20260928130000). Una maza escribe sólo lo que
-- es suyo: el driver trasero (cuando su ficha técnica dice un receptor con
-- código) y el anclaje del rotor de su rueda. Sus perforaciones sólo se
-- revisan contra la rueda que queda (el Enrayado del mismo trabajo, la
-- llanta nueva o la ficha): la llanta decide cuántos rayos lleva la rueda.
-- El ancho y el eje son del cuadro y aquí no se tocan. Una línea puede
-- instalar varios datos. El cassette y el rotor se cruzan con la maza que
-- instala el mismo trabajo.
--
-- Datos reales (producción, lectura del 2026-09-28): mazas, rotores y
-- llantas por su nombre, con lo que dice su ficha técnica; bicis del taller
-- con los trabajos donde se les cambió la maza (PG-00187, PG-00231,
-- PG-00459…). Lo supuesto se dice en cada caso: en producción ninguna maza
-- dice driver y anclaje a la vez, ni un rotor flotante dice su anclaje.
--
-- La base local no trae el motor de fichas: el lector del producto se
-- reemplaza en esta transacción por dos tablas; el real se comprueba con el
-- read-back contra producción.

-- ============================================================================
-- La relación y cómo se dice
-- ============================================================================

select is(
  (select jsonb_agg(jsonb_build_object(
            'spec', spec_key, 'position', position, 'key', bike_fact_key,
            'family', template_key, 'rule', on_mismatch, 'map', value_map,
            'fits', fits, 'condition', product_condition,
            'range', case when min_value > 0 then jsonb_build_array(min_value, max_value) end)
          order by template_key, bike_fact_key, position)
     from public.bike_fact_spec_links
    where template_key in ('hub', 'rotor')),
  '[{"key": "freehubType", "fits": null, "map": {"Driver BMX": "bmx_driver", "Rosca para piñón fijo": "fixed_threaded", "Rosca para piñón (rueda libre)": "threaded_freewheel"},
     "rule": "change", "spec": "hub_drive_receiver_kind", "range": null, "family": "hub", "position": "rear",
     "condition": {"values": ["Trasera", "Universal"], "spec_key": "hub_package_position", "missing_ok": true}},
    {"key": "frontRotorMount", "fits": null, "map": {"6 pernos": "six_bolt", "Centerlock": "centerlock"},
     "rule": "change", "spec": "rotor_mount_type", "range": null, "family": "hub", "position": "front",
     "condition": {"values": ["Delantera", "Universal"], "spec_key": "hub_package_position", "missing_ok": true}},
    {"key": "frontSpokeHoles", "fits": null, "map": null, "rule": "check", "spec": "spoke_hole_count",
     "range": [12, 48], "family": "hub", "position": "front",
     "condition": {"values": ["Delantera", "Universal"], "spec_key": "hub_package_position", "missing_ok": true}},
    {"key": "rearRotorMount", "fits": null, "map": {"6 pernos": "six_bolt", "Centerlock": "centerlock"},
     "rule": "change", "spec": "rotor_mount_type", "range": null, "family": "hub", "position": "rear",
     "condition": {"values": ["Trasera", "Universal"], "spec_key": "hub_package_position", "missing_ok": true}},
    {"key": "rearSpokeHoles", "fits": null, "map": null, "rule": "check", "spec": "spoke_hole_count",
     "range": [12, 48], "family": "hub", "position": "rear",
     "condition": {"values": ["Trasera", "Universal"], "spec_key": "hub_package_position", "missing_ok": true}},
    {"key": "frontRotorMount", "fits": {"six_bolt": ["centerlock"]}, "map": {"6 pernos": "six_bolt", "Centerlock": "centerlock"},
     "rule": "check", "spec": "rotor_mount_type", "range": null, "family": "rotor", "position": "front", "condition": null},
    {"key": "rearRotorMount", "fits": {"six_bolt": ["centerlock"]}, "map": {"6 pernos": "six_bolt", "Centerlock": "centerlock"},
     "rule": "check", "spec": "rotor_mount_type", "range": null, "family": "rotor", "position": "rear", "condition": null}]'::jsonb,
  'la maza escribe su driver y su anclaje; sus perforaciones y el anclaje del rotor sólo se revisan');
select is(
  jsonb_build_array(
    public.installed_bike_fact_label('frontRotorMount', '"centerlock"'),
    public.installed_bike_fact_label('rearRotorMount', '"six_bolt"'),
    public.installed_bike_fact_label('freehubType', '"bmx_driver"'),
    public.bike_fact_requirement_text('rearSpokeHoles', '36'),
    public.bike_fact_requirement_text('frontRotorMount', 'six_bolt'),
    public.bike_fact_requirement_text('freehubType', 'threaded_freewheel'),
    public.installed_bike_fact_label('rearRotorSizeMm', '180'),
    public.installed_bike_fact_label('frontSpokeHoles', '32')),
  '["Center Lock en el anclaje del rotor delantero", "6 pernos en el anclaje del rotor trasero",
    "Driver BMX en el driver trasero", "la rueda trasera lleva 36 rayos",
    "el anclaje del rotor delantero es «6 pernos»", "el driver trasero es «Rueda libre roscada»",
    "180 mm en el rotor trasero", "32H en la rueda delantera"]'::jsonb,
  'se dice como en el taller, y lo de antes se sigue diciendo igual');
select is(
  jsonb_build_array(
    public.hub_lacing_fits(36, 36), public.hub_lacing_fits(36, 32),
    public.hub_lacing_fits(36, 28), public.hub_lacing_fits(32, 24),
    public.hub_lacing_fits(48, 36), public.hub_lacing_fits(32, 36),
    public.hub_lacing_fits(28, 32), public.hub_lacing_fits(36, 20)),
  '[true, true, true, true, true, false, false, false]'::jsonb,
  'una maza con más perforaciones que la llanta se raya en los patrones de Sheldon Brown; con menos, no');
select is(
  jsonb_build_array(
    public.job_line_part_change_marks_internal('{"key": "freehubType", "value": "threaded_freewheel"}'),
    public.job_line_part_change_marks_internal(
      '[{"key": "rearRotorMount", "value": "centerlock"}, {"key": "freehubType", "value": "threaded_freewheel"}, "x", {"value": 1}]'),
    public.job_line_part_change_marks_internal('"freehubType"'),
    public.job_line_part_change_marks_internal(null)),
  '[[{"key": "freehubType", "value": "threaded_freewheel"}],
    [{"key": "freehubType", "value": "threaded_freewheel"}, {"key": "rearRotorMount", "value": "centerlock"}],
    [], []]'::jsonb,
  'una marca o una lista de marcas, ordenada por clave; lo que no es una marca no cuenta');
select ok(
  not has_function_privilege('authenticated',
    'public.job_line_part_change_internal(uuid,uuid,text)', 'EXECUTE')
  and not has_function_privilege('authenticated',
    'public.job_hub_at_wheel_internal(uuid,uuid,uuid,text)', 'EXECUTE')
  and not has_function_privilege('authenticated',
    'public.job_wheel_spokes_internal(uuid,uuid,uuid,text,jsonb)', 'EXECUTE')
  and not has_function_privilege('authenticated',
    'public.bike_fact_product_condition_met_internal(uuid,uuid,jsonb)', 'EXECUTE')
  and not has_function_privilege('authenticated',
    'public.hub_lacing_fits(integer,integer)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.job_part_change_writers_v1(uuid)', 'EXECUTE')
  and has_function_privilege('authenticated',
    'public.job_part_change_writers_v1(uuid)', 'EXECUTE'),
  'las reglas nuevas son internas');

-- ============================================================================
-- Fixture
-- ============================================================================

insert into public.tenants (id, shop_name) values
  ('e2830000-0000-4000-8000-000000000001', 'Taller ruedas');

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('e2830000-0000-4000-8000-000000000099', 'authenticated', 'authenticated',
   'ruedas@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now());

insert into public.user_profiles (user_id, tenant_id, role) values
  ('e2830000-0000-4000-8000-000000000099',
   'e2830000-0000-4000-8000-000000000001', 'admin');

insert into public.customers (id, tenant_id, name) values
  ('e2830000-0000-4000-8000-000000000010',
   'e2830000-0000-4000-8000-000000000001', 'Cliente ruedas');

insert into public.bikes (id, tenant_id, customer_id, brand, model, wheel_size)
select ('e2830000-0000-4000-8000-0000000000' || b.n)::uuid,
       'e2830000-0000-4000-8000-000000000001',
       'e2830000-0000-4000-8000-000000000010', b.brand, b.model, b.wheel
  from (values
    ('31', 'Totem', '4423', '29'), ('32', 'Oxford', 'Orion 4', '29"'),
    ('33', 'Scott', 'Scale 960', '29"'), ('34', 'Trek', 'Marlin 7', '29''''' ),
    ('35', 'Jeep', 'Gaspio', '29"'), ('36', 'Vision', 'Krypton 29', '29'''''),
    ('37', 'Trek', 'Marlin 4', '29'''''), ('38', 'Mongoose', 'Legion L20', '20"'),
    ('39', 'Upland', 'X200', '29'''''), ('40', 'Phoenix', '04D', '29"'),
    ('41', 'Besatti', 'Priore', '27.5"'), ('42', 'Oxford', 'Merak 1', '29"'),
    ('43', 'Totem', 'Fussion', '29"'), ('44', 'Voltta', 'Prato', '29"'),
    ('45', 'Xelentia', 'Antonio', '26'''''), ('46', 'Opaltech', 'Amarok', '29"'),
    ('47', 'Lahsen', 'Rocket 2600', '26"'), ('48', 'Thompson', 'Tara 26', '26"'),
    ('49', 'Barret', '29 MTB', '29"'), ('50', 'Jeep', 'Baltoro', '29'),
    ('51', 'Oxford', 'Orion 1', '29"'), ('52', 'Lashen', 'XT9007', '29"'),
    ('53', 'Cross', 'Cross', '29"'), ('54', 'Oxford', 'Hurricane', '29"'),
    ('55', 'Trek', '3700', '26"'), ('56', 'Trek', 'Marlin 5', '29"'),
    ('57', 'Oxford', 'Merak 2', '29"')
  ) b(n, brand, model, wheel);

-- Las fichas que el mecánico ya confirmó. El anclaje del rotor no existe en
-- producción todavía: el de la Trek, el Jeep y el Baltoro es supuesto.
insert into public.bike_profiles (tenant_id, bike_id, technical_profile)
select 'e2830000-0000-4000-8000-000000000001',
       ('e2830000-0000-4000-8000-0000000000' || p.n)::uuid,
       jsonb_build_object(
         'values', p.facts,
         'sources', (select coalesce(jsonb_object_agg(k, 'mechanic'), '{}'::jsonb)
                       from jsonb_object_keys(p.facts) k),
         'confirmed', (select coalesce(jsonb_object_agg(k, true), '{}'::jsonb)
                         from jsonb_object_keys(p.facts) k
                        where p.facts->>k <> 'unknown'))
  from (values
    ('32', '{"freehubType": "threaded_freewheel", "frontSpokeHoles": 36, "rearSpokeHoles": 36, "brakeType": "mechanical_disc"}'::jsonb),
    ('33', '{"brakeType": "hydraulic_disc", "frontSpokeHoles": 32, "rearSpokeHoles": 32, "freehubType": "microspline", "frontRotorSizeMm": 203, "rearRotorSizeMm": 160}'::jsonb),
    ('34', '{"brakeType": "hydraulic_disc", "frontRotorMount": "six_bolt", "frontRotorSizeMm": 160}'::jsonb),
    ('35', '{"brakeType": "mechanical_disc", "frontRotorMount": "centerlock", "frontRotorSizeMm": 160}'::jsonb),
    ('36', '{"freehubType": "shimano_hg", "drivetrainConfig": "3x7", "drivetrainSpeeds": 21}'::jsonb),
    ('37', '{"freehubType": "shimano_hg", "drivetrainConfig": "3x7", "drivetrainSpeeds": 21}'::jsonb),
    ('39', '{"freehubType": "threaded_freewheel", "drivetrainConfig": "3x8", "drivetrainSpeeds": 24}'::jsonb),
    ('41', '{"rearSpokeHoles": 32}'::jsonb),
    ('42', '{"rearSpokeHoles": 36}'::jsonb),
    ('43', '{"rearSpokeHoles": 32}'::jsonb),
    ('44', '{"brakeType": "mechanical_disc", "frontSpokeHoles": 36}'::jsonb),
    ('45', '{"brakeType": "mechanical_disc", "frontSpokeHoles": 36}'::jsonb),
    ('49', '{"freehubType": "threaded_freewheel", "drivetrainConfig": "3x7", "drivetrainSpeeds": 21}'::jsonb),
    ('50', '{"brakeType": "mechanical_disc", "frontRotorMount": "unknown"}'::jsonb),
    ('53', '{"rearSpokeHoles": 40}'::jsonb),
    ('54', '{"brakeType": "rim", "rimBrakeFamily": "v_brake"}'::jsonb),
    ('55', '{"freehubType": "shimano_hg", "drivetrainConfig": "3x7", "drivetrainSpeeds": 21}'::jsonb),
    ('56', '{"freehubType": "shimano_hg", "drivetrainConfig": "3x7", "drivetrainSpeeds": 21}'::jsonb)
  ) p(n, facts);

insert into public.products (id, tenant_id, name, category_name)
select ('e2830000-0000-4000-8000-000000000' || p.n)::uuid,
       'e2830000-0000-4000-8000-000000000001', p.name, p.category
  from (values
    ('101', 'Maza Trasera Disco 36H para Piñon con hilo QR 13mm 8S', 'Mazas'),
    ('102', 'maza shimano hb-rm66 36h (cl) delantero negro bolsa', 'Mazas'),
    ('103', 'Maza Trasera Novatec 32H 135x10mm HG D042SB', 'Mazas'),
    ('104', 'Maza Eclipse GL-B10R QR SELLADA BLACK 135MM 32H 8V', 'Mazas'),
    ('105', 'Maza Trasera Freestyle sellada 14mm 9T 36H Red', 'Mazas'),
    ('106', 'Maza Blooke Trasera Nucleo 8-9-10 disco negra 36h 135x10MM', 'Mazas'),
    ('107', 'Mazas Novatec 32H Microspline QR', 'Mazas'),
    ('108', 'Maza Delantera Novatec 32H 100x9mm HG D041SB', 'Mazas'),
    ('109', 'Maza Trasera Freewheel Disco 32h Betta', 'Mazas'),
    ('110', 'Maza trasera 36H rueda libre Center Lock (supuesta)', 'Mazas'),
    ('111', 'Maza trasera 36H rueda libre sin posición (supuesta)', 'Mazas'),
    ('112', 'Maza delantera 36H Center Lock (supuesta)', 'Mazas'),
    ('121', 'ROTOR FRENO DISCO SHIMANO SM-RT10 160MM AE', 'Frenos'),
    ('122', 'Disco freno G3 AE 160mm Genérico con tornillos 1Un', 'Frenos'),
    ('123', 'Disco de Freno Flotante 160mm Cyclami', 'Frenos'),
    ('131', 'Llanta FOSS F22 Aluminio Doble Pared con Ojetillos 29x32H', 'Llantas'),
    ('132', 'Llanta Aluminio FOSS Pared Simple 26x1,75x36H Black.', 'Llantas'),
    ('133', 'Llanta Aluminio 26 Negra (sin perforaciones en su ficha)', 'Llantas'),
    ('141', 'Cassette Shimano 7V CS-HG200-7 12/32T', 'Transmisión'),
    ('142', 'PIÑON ATORNILLADO 7 VELOCIDADES FALCON MOD.FW71', 'Transmisión'),
    ('143', 'PIÑON CASSETTE HG 8V 12-32T SUNRACE MOD.CSM400 8BU 8BU', 'Transmisión'),
    ('144', 'Mando Shimano Tourney SL-TX50 8V derecho', 'Transmisión')
  ) p(n, name, category);

create temporary table test_product_templates (
  product_id uuid primary key,
  template_key text
);
insert into test_product_templates
select ('e2830000-0000-4000-8000-000000000' || t.n)::uuid, t.template_key
  from (values
    ('101', 'hub'), ('102', 'hub'), ('103', 'hub'), ('104', 'hub'), ('105', 'hub'),
    ('106', 'hub'), ('107', 'hub'), ('108', 'hub'), ('109', 'hub'), ('110', 'hub'),
    ('111', 'hub'), ('112', 'hub'), ('121', 'rotor'), ('122', 'rotor'), ('123', 'rotor'),
    ('131', 'rim'), ('132', 'rim'), ('133', 'rim'), ('141', 'cassette'), ('142', 'freewheel'),
    ('143', 'cassette'), ('144', 'shifter')
  ) t(n, template_key);

-- Lo que dice cada ficha técnica, como la da el lector. Ninguna verificada
-- en producción. Supuesto: el anclaje Center Lock de 107 y 108 (no lo
-- dicen), el anclaje de 6 pernos del Cyclami flotante (no lo dice), y 110 y
-- 111 enteras.
create temporary table test_product_specs (
  product_id uuid,
  spec_key text,
  value jsonb,
  verified boolean default false
);
insert into test_product_specs (product_id, spec_key, value, verified)
select ('e2830000-0000-4000-8000-000000000' || s.n)::uuid, s.spec_key, s.value::jsonb, s.verified
  from (values
    ('101', 'hub_package_position', '"Trasera"', false),
    ('101', 'spoke_hole_count', '36', false),
    ('101', 'hub_drive_receiver_kind', '"Rosca para piñón (rueda libre)"', false),
    ('101', 'hub_rotor_mount_present', 'true', false),
    ('101', 'hub_axle_mount_kind', '"Cierre rápido"', false),
    ('102', 'hub_package_position', '"Delantera"', false),
    ('102', 'spoke_hole_count', '36', false),
    ('102', 'rotor_mount_type', '"Centerlock"', false),
    ('102', 'hub_rotor_mount_present', 'true', false),
    ('103', 'hub_package_position', '"Trasera"', false),
    ('103', 'spoke_hole_count', '32', false),
    ('103', 'hub_old_mm', '135', false),
    ('103', 'hub_axle_diameter_mm', '10', false),
    ('104', 'spoke_hole_count', '32', false),
    ('104', 'hub_old_mm', '135', false),
    ('105', 'hub_package_position', '"Trasera"', false),
    ('105', 'spoke_hole_count', '36', false),
    ('105', 'hub_drive_receiver_kind', '"Driver BMX"', false),
    ('106', 'hub_package_position', '"Trasera"', false),
    ('106', 'spoke_hole_count', '36', false),
    ('106', 'hub_drive_receiver_kind', '"Núcleo de cassette"', false),
    ('107', 'hub_package_position', '"Juego (delantera y trasera)"', false),
    ('107', 'rotor_mount_type', '"Centerlock"', false),
    ('108', 'hub_package_position', '"Delantera"', false),
    ('108', 'spoke_hole_count', '32', false),
    ('108', 'rotor_mount_type', '"Centerlock"', false),
    ('109', 'hub_package_position', '"Trasera"', false),
    ('109', 'spoke_hole_count', '32', false),
    ('109', 'hub_drive_receiver_kind', '"Rosca para piñón (rueda libre)"', false),
    ('109', 'hub_rotor_mount_present', 'true', false),
    ('110', 'hub_package_position', '"Trasera"', false),
    ('110', 'spoke_hole_count', '36', false),
    ('110', 'hub_drive_receiver_kind', '"Rosca para piñón (rueda libre)"', false),
    ('110', 'rotor_mount_type', '"Centerlock"', false),
    ('111', 'spoke_hole_count', '36', false),
    ('112', 'hub_package_position', '"Delantera"', false),
    ('112', 'spoke_hole_count', '36', false),
    ('112', 'rotor_mount_type', '"Centerlock"', false),
    ('111', 'hub_drive_receiver_kind', '"Rosca para piñón (rueda libre)"', false),
    ('121', 'rotor_diameter_mm_value', '160', false),
    ('121', 'rotor_mount_type', '"Centerlock"', false),
    ('122', 'rotor_diameter_mm_value', '160', false),
    ('122', 'rotor_mount_type', '"6 pernos"', false),
    ('123', 'rotor_diameter_mm_value', '160', false),
    ('123', 'rotor_floating', 'true', false),
    ('123', 'rotor_mount_type', '"6 pernos"', false),
    ('131', 'spoke_hole_count', '32', false),
    ('132', 'spoke_hole_count', '36', false),
    ('141', 'cassette_spline_standard', '"Shimano HG spline S (7v)"', false),
    ('141', 'sprocket_count', '7', false),
    ('142', 'sprocket_count', '7', false),
    ('143', 'cassette_spline_standard', '"Shimano HG spline M (8/9/10v y MTB 11v; ROAD 11v y 7v sólo según filas C-731; LINKGLIDE según C-649)"', false),
    ('143', 'sprocket_count', '8', false),
    ('144', 'shifter_position', '"Derecho (trasero)"', false)) s(n, spec_key, value, verified);

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

-- Un trabajo por bici.
insert into public.mechanic_jobs (id, tenant_id, customer_id, bike_id, job_number, created_by)
select ('e2830000-0000-4000-8000-000000000' || j.n)::uuid,
       'e2830000-0000-4000-8000-000000000001',
       'e2830000-0000-4000-8000-000000000010',
       ('e2830000-0000-4000-8000-0000000000' || j.bike)::uuid,
       'PG-HUB-' || j.n,
       'e2830000-0000-4000-8000-000000000099'
  from (values
    ('051', '31'), ('052', '32'), ('053', '33'), ('054', '34'), ('055', '35'),
    ('056', '36'), ('057', '37'), ('058', '38'), ('059', '39'), ('060', '40'),
    ('061', '41'), ('062', '42'), ('063', '43'), ('064', '44'), ('065', '45'),
    ('066', '46'), ('067', '47'), ('068', '48'), ('069', '49'), ('070', '50'),
    ('071', '51'), ('072', '52'), ('073', '53'), ('074', '54'), ('075', '55'), ('076', '56'), ('077', '57')) j(n, bike);

insert into public.mechanic_job_bikes (tenant_id, job_id, bike_id)
select 'e2830000-0000-4000-8000-000000000001', j.id, j.bike_id
  from public.mechanic_jobs j
 where j.tenant_id = 'e2830000-0000-4000-8000-000000000001';

-- Las líneas, con la marca que deja el mecánico al elegir la rueda. Una
-- marca de varios datos es una lista. Las de un Enrayado dicen sus
-- perforaciones y su rueda, como el asistente.
-- Cada una va en la pestaña de su bici: una de General no es de ninguna
-- (20261001195000).
insert into public.mechanic_job_items (
  id, tenant_id, job_id, job_bike_id, product_id, product_name, item_type, location_key,
  quantity, unit_price, service_configuration_data
)
select ('e2830000-0000-4000-8000-000000000' || l.n)::uuid,
       'e2830000-0000-4000-8000-000000000001',
       ('e2830000-0000-4000-8000-000000000' || l.job)::uuid,
       (select jb.id from public.mechanic_job_bikes jb
         where jb.job_id = ('e2830000-0000-4000-8000-000000000' || l.job)::uuid),
       case when l.product is not null
         then ('e2830000-0000-4000-8000-000000000' || l.product)::uuid end,
       coalesce(p.name, 'Enrayado + Centrado'),
       case when l.product is null then 'service' else 'product' end,
       l.location_key, 1, 19990,
       coalesce(l.data::jsonb, '{}'::jsonb)
  from (values
    -- PG-00187: la maza de rueda libre en la Totem sin ficha.
    ('151', '051', '101', 'rear', '{"part_change": {"key": "freehubType", "value": "threaded_freewheel"}}'),
    ('152', '051', null, 'none', '{"hole_count": "36", "which_wheel": "rear"}'),
    -- PG-00459: una maza de 32H en la Orion 4, que lleva 36 atrás.
    ('153', '052', '109', 'rear', '{"part_change": {"key": "freehubType", "value": "threaded_freewheel"}}'),
    -- La Scott: la HB-RM66 adelante, armada a 36 (la ficha dice 32).
    ('154', '053', '102', 'front', '{"part_change": {"key": "frontRotorMount", "value": "centerlock"}}'),
    ('155', '053', null, 'none', '{"hole_count": "36", "which_wheel": "front"}'),
    -- Un SM-RT10 Center Lock en la Trek de 6 pernos.
    ('156', '054', '121', 'front', '{"part_change": {"key": "frontRotorSizeMm", "value": 160}}'),
    -- Un G3 de 6 pernos en el Jeep Center Lock: entra con el SM-RTAD05.
    ('157', '055', '122', 'front', '{"part_change": {"key": "frontRotorSizeMm", "value": 160}}'),
    -- La Vision HG: maza de rueda libre y un cassette HG en el mismo trabajo.
    ('158', '056', '101', 'rear', '{"part_change": {"key": "freehubType", "value": "threaded_freewheel"}}'),
    ('159', '056', '141', 'rear', '{"part_change": {"key": "freehubType", "value": "shimano_hg"}}'),
    -- La Marlin 4 HG: maza de rueda libre y un FW71.
    ('160', '057', '101', 'rear', '{"part_change": {"key": "freehubType", "value": "threaded_freewheel"}}'),
    ('161', '057', '142', 'rear', '{"part_change": {"key": "freehubType", "value": "threaded_freewheel"}}'),
    -- BMX.
    ('162', '058', '105', 'rear', '{"part_change": {"key": "freehubType", "value": "bmx_driver"}}'),
    -- La Upland de rueda libre: maza con núcleo de cassette sin familia y un
    -- cassette HG 8v.
    ('163', '059', '106', 'rear', null),
    ('164', '059', '143', 'rear', '{"part_change": {"key": "freehubType", "value": "shimano_hg"}}'),
    -- Driver y anclaje en una línea (supuesta), en la Phoenix sin ficha.
    ('165', '060', '110', 'rear', '{"part_change": [{"key": "freehubType", "value": "threaded_freewheel"}, {"key": "rearRotorMount", "value": "centerlock"}]}'),
    ('166', '060', null, 'none', '{"hole_count": "36", "which_wheel": "rear"}'),
    -- La Besatti dice 32 atrás, pero el trabajo pone una llanta de 36.
    ('167', '061', '109', 'rear', '{"part_change": {"key": "freehubType", "value": "threaded_freewheel"}}'),
    ('168', '061', '132', 'rear', null),
    -- y otra llanta en esa rueda que no dice sus perforaciones: manda la que sí.
    ('189', '061', '133', 'rear', null),
    -- La Merak dice 36 atrás, pero el Enrayado la arma a 32.
    ('169', '062', '109', 'rear', '{"part_change": {"key": "freehubType", "value": "threaded_freewheel"}}'),
    ('170', '062', null, 'rear', '{"hole_count": "32"}'),
    -- La Fussion lleva 32 atrás y la maza tiene 36: se raya 36 en 32.
    ('171', '063', '101', 'rear', '{"part_change": {"key": "freehubType", "value": "threaded_freewheel"}}'),
    -- La Prato: HB-RM66 adelante y un G3 de 6 pernos en la misma rueda.
    ('172', '064', '102', 'front', '{"part_change": {"key": "frontRotorMount", "value": "centerlock"}}'),
    ('173', '064', '122', 'front', '{"part_change": {"key": "frontRotorSizeMm", "value": 160}}'),
    -- La Antonio: HB-RM66 y un rotor flotante de 6 pernos (araña de aluminio).
    ('174', '065', '102', 'front', '{"part_change": {"key": "frontRotorMount", "value": "centerlock"}}'),
    ('175', '065', '123', 'front', '{"part_change": {"key": "frontRotorSizeMm", "value": 160}}'),
    -- Un juego no instala nada, aunque diga su anclaje.
    ('176', '066', '107', 'rear', '{"part_change": {"key": "rearRotorMount", "value": "centerlock"}}'),
    -- Una maza delantera marcada atrás no vale; la misma adelante sí.
    ('177', '067', '108', 'rear', '{"part_change": {"key": "rearRotorMount", "value": "centerlock"}}'),
    -- Sin posición dicha, la rueda que eligió el mecánico.
    ('178', '068', '111', 'rear', '{"part_change": {"key": "freehubType", "value": "threaded_freewheel"}}'),
    -- Maza sin posición ni rueda en el trabajo del cassette: no decide.
    ('179', '069', '104', 'none', null),
    ('180', '069', '141', 'rear', '{"part_change": {"key": "freehubType", "value": "shimano_hg"}}'),
    -- Anclaje desconocido: no refuta.
    ('181', '070', '122', 'front', '{"part_change": {"key": "frontRotorSizeMm", "value": 160}}'),
    -- Driver bien y anclaje mal marcado: entra sólo el driver.
    ('182', '071', '110', 'rear', '{"part_change": [{"key": "freehubType", "value": "threaded_freewheel"}, {"key": "rearRotorMount", "value": "six_bolt"}]}'),
    -- Una maza con driver y anclaje que no calza en la rueda de 40.
    ('183', '073', '110', 'rear', '{"part_change": [{"key": "freehubType", "value": "threaded_freewheel"}, {"key": "rearRotorMount", "value": "centerlock"}]}'),
    -- La misma maza en una bici con freno de llanta (para el recibo parcial).
    ('184', '074', '110', 'rear', '{"part_change": [{"key": "freehubType", "value": "threaded_freewheel"}, {"key": "rearRotorMount", "value": "centerlock"}]}'),
    -- La Trek 3700 HG: sólo el cassette (la maza llega después).
    ('185', '075', '141', 'rear', '{"part_change": {"key": "freehubType", "value": "shimano_hg"}}'),
    -- La Marlin 5 HG: el FW71 antes que la maza de rueda libre en el trabajo.
    ('187', '076', '142', 'rear', '{"part_change": {"key": "freehubType", "value": "threaded_freewheel"}}'),
    ('188', '076', '101', 'rear', '{"part_change": {"key": "freehubType", "value": "threaded_freewheel"}}'),
    -- La Merak 2: dos Enrayados traseros que no dicen lo mismo y la Betta.
    ('191', '077', null, 'none', '{"hole_count": "36", "which_wheel": "rear"}'),
    ('192', '077', null, 'none', '{"hole_count": "40", "which_wheel": "rear"}'),
    ('193', '077', '109', 'rear', '{"part_change": {"key": "freehubType", "value": "threaded_freewheel"}}')
  ) l(n, job, product, location_key, data)
  left join public.products p
    on p.id = ('e2830000-0000-4000-8000-000000000' || l.product)::uuid;

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'e2830000-0000-4000-8000-000000000099', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub',
  'e2830000-0000-4000-8000-000000000099', true);

create temporary table status_ids as
select code, id
  from public.job_statuses
 where tenant_id = 'e2830000-0000-4000-8000-000000000001';

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
   where bp.bike_id = ('e2830000-0000-4000-8000-0000000000' || p_bike)::uuid
$$;

create or replace function pg_temp.finish(p_job text, p_code text default 'FINALIZADO')
returns jsonb
language plpgsql
as $$
declare
  v_detail text;
  v_hint text;
begin
  return public.transition_mechanic_job_status(
    ('e2830000-0000-4000-8000-000000000' || p_job)::uuid,
    (select id from status_ids where code = p_code),
    'hub-' || p_job || '-' || p_code);
exception when check_violation then
  get stacked diagnostics v_detail = pg_exception_detail, v_hint = pg_exception_hint;
  if v_hint is distinct from 'job_completion_blocked' then
    raise;
  end if;
  return jsonb_build_object('blocked', true, 'problems', (v_detail::jsonb)->'problems');
end;
$$;

create or replace function pg_temp.problems(p_label text)
returns jsonb
language sql
as $$
  select coalesce(jsonb_agg(problem - 'item_id' - 'bike_id' - 'item_name'
                            order by problem->>'key'), '[]'::jsonb)
    from results r
   cross join lateral jsonb_array_elements(
           coalesce(r.result->'installed_bike_facts'->'problems', r.result->'problems')) problem
   where r.label = p_label
$$;

create or replace function pg_temp.receipts(p_job text)
returns jsonb
language sql
as $$
  select coalesce(jsonb_agg(regexp_replace(operation_key,
           '^job_completion:e2830000-0000-4000-8000-000000000', 'job_completion:')
           order by operation_key), '[]'::jsonb)
    from public.bike_technical_fact_patches
   where job_id = ('e2830000-0000-4000-8000-000000000' || p_job)::uuid
$$;

create or replace function pg_temp.line(p_n text)
returns uuid
language sql
as $$ select ('e2830000-0000-4000-8000-000000000' || p_n)::uuid $$;

-- ============================================================================
-- La regla: qué marca vale
-- ============================================================================

select is(
  jsonb_build_array(
    public.job_line_part_change_internal('e2830000-0000-4000-8000-000000000001',
      pg_temp.line('151'), 'freehubType') - 'link_id',
    public.job_line_part_change_internal('e2830000-0000-4000-8000-000000000001',
      pg_temp.line('151')) - 'link_id',
    public.job_line_part_change_internal('e2830000-0000-4000-8000-000000000001',
      pg_temp.line('154'), 'frontRotorMount') - 'link_id'),
  '[{"key": "freehubType", "value": "threaded_freewheel", "spec_key": "hub_drive_receiver_kind", "position": "rear",
     "verified": false, "on_mismatch": "change", "template_key": "hub"},
    {"key": "freehubType", "value": "threaded_freewheel", "spec_key": "hub_drive_receiver_kind", "position": "rear",
     "verified": false, "on_mismatch": "change", "template_key": "hub"},
    {"key": "frontRotorMount", "value": "centerlock", "spec_key": "rotor_mount_type", "position": "front",
     "verified": false, "on_mismatch": "change", "template_key": "hub"}]'::jsonb,
  'la maza de rueda libre marca el driver y la HB-RM66 su anclaje Center Lock; la regla de un dato sigue igual');
select is(
  jsonb_build_array(
    public.job_line_part_change_internal('e2830000-0000-4000-8000-000000000001',
      pg_temp.line('165'), 'freehubType')->>'value',
    public.job_line_part_change_internal('e2830000-0000-4000-8000-000000000001',
      pg_temp.line('165'), 'rearRotorMount')->>'value',
    public.job_line_part_change_internal('e2830000-0000-4000-8000-000000000001',
      pg_temp.line('165')),
    public.job_line_part_change_internal('e2830000-0000-4000-8000-000000000001',
      pg_temp.line('182'), 'rearRotorMount'),
    public.job_line_part_change_internal('e2830000-0000-4000-8000-000000000001',
      pg_temp.line('176'), 'rearRotorMount'),
    public.job_line_part_change_internal('e2830000-0000-4000-8000-000000000001',
      pg_temp.line('177'), 'rearRotorMount'),
    public.job_line_part_change_internal('e2830000-0000-4000-8000-000000000001',
      pg_temp.line('178'), 'freehubType')->>'value',
    public.job_line_part_change_internal('e2830000-0000-4000-8000-000000000001',
      pg_temp.line('156'), 'frontRotorMount')),
  '["threaded_freewheel", "centerlock", null, null, null, null, "threaded_freewheel", null]'::jsonb,
  'una lista vale por clave; un anclaje mal marcado, un juego o una maza delantera atrás no valen; sin posición dicha, sí; un rotor no marca el anclaje');

-- Un núcleo de cassette no dice qué driver es: no se puede marcar.
update public.mechanic_job_items
   set service_configuration_data = '{"part_change": {"key": "freehubType", "value": "shimano_hg"}}'
 where id = pg_temp.line('163');
select is(
  public.job_line_part_change_internal('e2830000-0000-4000-8000-000000000001',
    pg_temp.line('163'), 'freehubType'),
  null,
  'una maza con «Núcleo de cassette» no marca ningún driver');
update public.mechanic_job_items
   set service_configuration_data = '{}'
 where id = pg_temp.line('163');

-- ============================================================================
-- Terminar: lo que la maza escribe
-- ============================================================================

insert into results select 'totem', pg_temp.finish('051');
select is(
  jsonb_build_array(
    pg_temp.fact('31', 'freehubType'),
    pg_temp.fact('31', 'rearSpokeHoles'),
    pg_temp.problems('totem'),
    pg_temp.receipts('051')),
  '[["threaded_freewheel", null, "job_completion"], [36, true, "job_completion"], [],
    ["job_completion:151:1:freehubType=threaded_freewheel", "job_completion:152:1:rearSpokeHoles=36"]]'::jsonb,
  'la Totem sin ficha toma la rueda libre declarada, y las 36 las anota el Enrayado confirmadas, no la maza');

insert into results select 'totem_replay', pg_temp.finish('051');
insert into results select 'totem_entregado', pg_temp.finish('051', 'ENTREGADO');
select is(
  jsonb_build_array(
    pg_temp.receipts('051'),
    pg_temp.problems('totem_entregado')),
  '[["job_completion:151:1:freehubType=threaded_freewheel", "job_completion:152:1:rearSpokeHoles=36"], []]'::jsonb,
  'el replay y entregar no agregan recibos');

insert into results select 'orion', pg_temp.finish('052');
select is(
  jsonb_build_array(
    pg_temp.fact('32', 'freehubType'),
    pg_temp.problems('orion'),
    pg_temp.receipts('052'),
    (select count(*) from public.bike_events
      where bike_id = 'e2830000-0000-4000-8000-000000000032'
        and event_type = 'installed_fact_incompatible'
        and summary like '%la ficha de la bici dice la rueda trasera lleva 36 rayos%')),
  '[["threaded_freewheel", true, "mechanic"],
    [{"key": "freehubType", "value": "threaded_freewheel", "reason": "incompatible",
      "requires_key": "rearSpokeHoles", "requires_value": "36"}],
    [], 0]'::jsonb,
  'PG-00459: la Orion no termina con la maza de 32H, ni deja aviso o ficha a medias');
select is(
  jsonb_build_array(
    (select status from public.mechanic_jobs where id = 'e2830000-0000-4000-8000-000000000052'),
    (select count(*) from public.workshop_command_attempts where operation_key = 'hub-052-FINALIZADO')),
  '["PENDIENTE", 0]'::jsonb,
  'la incompatibilidad deshace estado y recibo para corregir y reintentar');

insert into results select 'scott', pg_temp.finish('053');
select is(
  jsonb_build_array(
    pg_temp.fact('33', 'frontRotorMount'),
    pg_temp.fact('33', 'frontSpokeHoles'),
    pg_temp.problems('scott')),
  '[["centerlock", null, "job_completion"], [36, true, "job_completion"], []]'::jsonb,
  'la Scott toma el anclaje Center Lock de la HB-RM66, y la rueda armada a 36 calza aunque la ficha dijera 32');

insert into results select 'bmx', pg_temp.finish('058');
insert into results select 'sin_posicion', pg_temp.finish('068');
select is(
  jsonb_build_array(
    pg_temp.fact('38', 'freehubType'),
    pg_temp.fact('48', 'freehubType'),
    pg_temp.problems('bmx') || pg_temp.problems('sin_posicion')),
  '[["bmx_driver", null, "job_completion"], ["threaded_freewheel", null, "job_completion"], []]'::jsonb,
  'la Freestyle anota su driver BMX; la maza sin posición dicha, en la rueda que eligió el mecánico');

insert into results select 'juego', pg_temp.finish('066');
insert into results select 'delantera_atras', pg_temp.finish('067');
select is(
  jsonb_build_array(
    pg_temp.problems('juego'),
    pg_temp.problems('delantera_atras'),
    pg_temp.receipts('066') || pg_temp.receipts('067')),
  '[[{"key": "rearRotorMount", "value": "centerlock", "reason": "stale_change"}],
    [{"key": "rearRotorMount", "value": "centerlock", "reason": "stale_change"}], []]'::jsonb,
  'un juego y una maza delantera marcada atrás no escriben y lo dicen');

-- ============================================================================
-- Varios datos en una línea
-- ============================================================================

insert into results select 'phoenix', pg_temp.finish('060');
select is(
  jsonb_build_array(
    pg_temp.fact('40', 'freehubType'),
    pg_temp.fact('40', 'rearRotorMount'),
    pg_temp.problems('phoenix'),
    pg_temp.receipts('060')),
  '[["threaded_freewheel", null, "job_completion"], ["centerlock", null, "job_completion"], [],
    ["job_completion:165:1:freehubType=threaded_freewheel,rearRotorMount=centerlock",
     "job_completion:166:1:rearSpokeHoles=36"]]'::jsonb,
  'una maza con driver y anclaje escribe los dos en un solo recibo de la línea');
select is(
  public.job_part_change_writers_v1('e2830000-0000-4000-8000-000000000060')
    -> 'e2830000-0000-4000-8000-000000000165',
  '[{"key": "freehubType", "value": "threaded_freewheel"}, {"key": "rearRotorMount", "value": "centerlock"}]'::jsonb,
  'el formulario lee los dos datos que escribió la línea');
insert into results select 'phoenix_replay', pg_temp.finish('060', 'ENTREGADO');
select is(
  pg_temp.receipts('060'),
  '["job_completion:165:1:freehubType=threaded_freewheel,rearRotorMount=centerlock",
    "job_completion:166:1:rearSpokeHoles=36"]'::jsonb,
  'y entregar no la repite');

insert into results select 'orion1', pg_temp.finish('071');
select is(
  jsonb_build_array(
    pg_temp.fact('51', 'freehubType'),
    pg_temp.fact('51', 'rearRotorMount'),
    pg_temp.problems('orion1'),
    pg_temp.receipts('071')),
  '[null, null,
    [{"key": "rearRotorMount", "value": "six_bolt", "reason": "stale_change"}],
    []]'::jsonb,
  'con el anclaje mal marcado no termina ni escribe el driver');

insert into results select 'cross', pg_temp.finish('073');
select is(
  jsonb_build_array(
    pg_temp.fact('53', 'freehubType'),
    pg_temp.problems('cross'),
    pg_temp.receipts('073')),
  '[[null, null, null],
    [{"key": "freehubType", "value": "threaded_freewheel", "reason": "incompatible",
      "requires_key": "rearSpokeHoles", "requires_value": "40"},
     {"key": "rearRotorMount", "value": "centerlock", "reason": "incompatible",
      "requires_key": "rearSpokeHoles", "requires_value": "40"}],
    []]'::jsonb,
  'una maza de 36H no se raya en una rueda de 40: ninguno de sus datos entra');

-- ============================================================================
-- La rueda que queda: el Enrayado y la llanta del mismo trabajo
-- ============================================================================

insert into results select 'besatti', pg_temp.finish('061');
insert into results select 'merak', pg_temp.finish('062');
insert into results select 'fussion', pg_temp.finish('063');
select is(
  jsonb_build_array(
    pg_temp.problems('besatti'),
    pg_temp.fact('41', 'freehubType'),
    pg_temp.problems('merak'),
    pg_temp.fact('42', 'freehubType'),
    pg_temp.fact('42', 'rearSpokeHoles'),
    pg_temp.problems('fussion'),
    pg_temp.fact('43', 'freehubType'),
    pg_temp.fact('43', 'rearSpokeHoles')),
  '[[{"key": "freehubType", "value": "threaded_freewheel", "reason": "incompatible",
      "requires_key": "rearSpokeHoles", "requires_value": "36", "requires_source": "job_rim"}],
    [null, null, null],
    [], ["threaded_freewheel", null, "job_completion"], [32, true, "job_completion"],
    [], ["threaded_freewheel", null, "job_completion"], [32, true, "mechanic"]]'::jsonb,
  'la llanta nueva de 36 decide aunque la ficha diga 32; el Enrayado a 32 decide aunque la ficha diga 36; una maza de 36 se raya en la rueda de 32');
select is(
  (select count(*)::integer from public.bike_events
    where bike_id = 'e2830000-0000-4000-8000-000000000041'
      and event_type = 'installed_fact_incompatible'
      and summary like '%pero la llanta que instala el trabajo dice la rueda trasera lleva 36 rayos%'),
  0,
  'el cierre rechazado no deja historia como si hubiera instalado la pieza');

-- ============================================================================
-- El cassette con la maza del mismo trabajo
-- ============================================================================

insert into results select 'vision', pg_temp.finish('056');
insert into results select 'marlin4', pg_temp.finish('057');
insert into results select 'upland', pg_temp.finish('059');
insert into results select 'barret', pg_temp.finish('069');
select is(
  jsonb_build_array(
    pg_temp.fact('36', 'freehubType'),
    pg_temp.problems('vision'),
    pg_temp.fact('37', 'freehubType'),
    pg_temp.problems('marlin4'),
    pg_temp.receipts('057'),
    pg_temp.fact('39', 'freehubType'),
    pg_temp.problems('upland'),
    pg_temp.problems('barret'),
    pg_temp.fact('49', 'freehubType')),
  '[["shimano_hg", true, "mechanic"],
    [{"key": "freehubType", "value": "shimano_hg", "reason": "incompatible",
      "requires_key": "freehubType", "requires_value": "threaded_freewheel", "requires_source": "job_hub"}],
    ["threaded_freewheel", null, "job_completion"], [],
    ["job_completion:160:1:freehubType=threaded_freewheel", "job_completion:161:1:freehubType=threaded_freewheel"],
    ["threaded_freewheel", true, "mechanic"],
    [{"key": "freehubType", "value": "shimano_hg", "reason": "pending", "pending": "hub_change",
      "requires_key": "freehubType", "requires_value": "threaded_freewheel"}],
    [{"key": "freehubType", "value": "shimano_hg", "reason": "incompatible",
      "requires_key": "freehubType", "requires_value": "threaded_freewheel"}],
    ["threaded_freewheel", true, "mechanic"]]'::jsonb,
  'la Vision no termina con cassette HG y maza roscada; el FW71 sí; con núcleo sin familia queda pendiente');

insert into results select 'marlin5', pg_temp.finish('076');
select is(
  jsonb_build_array(
    pg_temp.fact('56', 'freehubType'),
    pg_temp.problems('marlin5'),
    pg_temp.receipts('076')),
  '[["threaded_freewheel", null, "job_completion"], [],
    ["job_completion:187:1:freehubType=threaded_freewheel", "job_completion:188:1:freehubType=threaded_freewheel"]]'::jsonb,
  'el orden de las líneas no importa: el FW71 antes que su maza también calza y los dos quedan');

-- Un recibo con parte de lo marcado. Hoy ninguna fila de la maza pide algo de
-- la bici, así que driver y anclaje entran o no entran juntos; el mecanismo
-- es de toda línea de varios datos (la llanta lo va a usar). Se prueba con
-- una fila de prueba en esta transacción: el anclaje sólo con freno de disco.
update public.bike_fact_spec_links
   set requires_fact_key = 'brakeType',
       requires_fact_values = '{mechanical_disc,hydraulic_disc}'
 where template_key = 'hub'
   and bike_fact_key = 'rearRotorMount';
update public.bike_profiles
   set technical_profile = jsonb_set(technical_profile, '{confirmed,brakeType}', 'true')
 where bike_id = 'e2830000-0000-4000-8000-000000000054';
insert into results select 'hurricane', pg_temp.finish('074');
insert into results select 'hurricane_replay', pg_temp.finish('074', 'ENTREGADO');
select is(
  jsonb_build_array(
    pg_temp.fact('54', 'freehubType'),
    pg_temp.fact('54', 'rearRotorMount'),
    pg_temp.problems('hurricane'),
    pg_temp.receipts('074')),
  '[[null, null, null], [null, null, null],
    [{"key": "rearRotorMount", "value": "centerlock", "reason": "incompatible",
      "requires_key": "brakeType", "requires_value": "rim"}],
    []]'::jsonb,
  'si un dato de la línea no entra, no termina ni deja recibo parcial');
update public.bike_fact_spec_links
   set requires_fact_key = null,
       requires_fact_values = '{}'
 where template_key = 'hub'
   and bike_fact_key = 'rearRotorMount';

-- ============================================================================
-- El rotor con el anclaje de su maza
-- ============================================================================

insert into results select 'marlin7', pg_temp.finish('054');
insert into results select 'gaspio', pg_temp.finish('055');
insert into results select 'prato', pg_temp.finish('064');
insert into results select 'antonio', pg_temp.finish('065');
insert into results select 'baltoro', pg_temp.finish('070');
select is(
  jsonb_build_array(
    pg_temp.problems('marlin7'),
    pg_temp.problems('gaspio'),
    pg_temp.fact('35', 'frontRotorSizeMm'),
    pg_temp.problems('prato'),
    pg_temp.fact('44', 'frontRotorMount'),
    pg_temp.fact('44', 'frontRotorSizeMm'),
    pg_temp.problems('antonio'),
    pg_temp.fact('45', 'frontRotorMount'),
    pg_temp.fact('45', 'frontRotorSizeMm'),
    pg_temp.problems('baltoro'),
    pg_temp.fact('50', 'frontRotorSizeMm')),
  '[[{"key": "frontRotorSizeMm", "value": 160, "reason": "incompatible",
      "requires_key": "frontRotorMount", "requires_value": "six_bolt"}],
    [], [160, true, "mechanic"],
    [], ["centerlock", null, "job_completion"], [160, null, "job_completion"],
    [{"key": "frontRotorSizeMm", "value": 160, "reason": "incompatible",
      "requires_key": "frontRotorMount", "requires_value": "centerlock", "requires_source": "job_hub"}],
    [null, null, null], [null, null, null],
    [], [160, null, "job_completion"]]'::jsonb,
  'un Center Lock no va en 6 pernos; el cierre se revierte entero aunque la maza calce, y un anclaje desconocido no refuta');

-- Puertas de línea/parche para trabajos históricos terminados bajo el contrato
-- anterior; la transición nueva que rechazó estas piezas ya fue comprobada.
set local session_replication_role = replica;
update public.mechanic_jobs
   set status = 'FINALIZADO',
       status_id = (select id from status_ids where code = 'FINALIZADO')
 where id in ('e2830000-0000-4000-8000-000000000052',
              'e2830000-0000-4000-8000-000000000054',
              'e2830000-0000-4000-8000-000000000056',
              'e2830000-0000-4000-8000-000000000065');
set local session_replication_role = origin;

-- ============================================================================
-- El parche directo y la puerta del trabajo terminado
-- ============================================================================

select throws_ok(
  $$select public.patch_bike_technical_facts_v1(
    'job_completion:e2830000-0000-4000-8000-000000000156:1:frontRotorMount=centerlock',
    'e2830000-0000-4000-8000-000000000034',
    'e2830000-0000-4000-8000-000000000054',
    'job_completion',
    '[{"key": "frontRotorMount", "op": "declare", "value": "centerlock", "expected": "six_bolt", "expected_confirmed": true}]'::jsonb)$$,
  'P0001',
  'The job line did not install frontRotorMount',
  'un rotor no instala el anclaje, tampoco por el parche');
select throws_ok(
  $$select public.patch_bike_technical_facts_v1(
    'job_completion:e2830000-0000-4000-8000-000000000154:9:frontRotorMount=campagnolo',
    'e2830000-0000-4000-8000-000000000033',
    'e2830000-0000-4000-8000-000000000053',
    'job_completion',
    '[{"key": "frontRotorMount", "op": "declare", "value": "campagnolo", "expected": "centerlock", "expected_confirmed": false}]'::jsonb)$$,
  'P0001',
  'Bicycle fact frontRotorMount has an unknown value',
  'el anclaje sólo es 6 pernos o Center Lock');
select throws_ok(
  $$select public.patch_bike_technical_facts_v1(
    'job_completion:e2830000-0000-4000-8000-000000000153:1:freehubType=threaded_freewheel',
    'e2830000-0000-4000-8000-000000000032',
    'e2830000-0000-4000-8000-000000000052',
    'job_completion',
    '[{"key": "freehubType", "op": "declare", "value": "threaded_freewheel", "expected": "threaded_freewheel", "expected_confirmed": true}]'::jsonb)$$,
  '23514',
  'Installed part freehubType does not fit the bicycle (rearSpokeHoles is 36)',
  'una llamada directa al parche tampoco pasa la maza de 32H de la Orion');

-- En la Orion terminada, agregar la maza de 32H no se guarda; una de 36H sí.
select throws_like(
  $$insert into public.mechanic_job_items (
      tenant_id, job_id, job_bike_id, product_id, product_name, item_type, location_key,
      quantity, unit_price, service_configuration_data)
    values ('e2830000-0000-4000-8000-000000000001',
            'e2830000-0000-4000-8000-000000000052',
            (select id from public.mechanic_job_bikes where job_id = 'e2830000-0000-4000-8000-000000000052'),
            'e2830000-0000-4000-8000-000000000109',
            'Maza Trasera Freewheel Disco 32h Betta', 'product', 'rear', 1, 19990,
            '{"part_change": {"key": "freehubType", "value": "threaded_freewheel"}}')$$,
  '%no calza con la ficha de la bici (la rueda trasera lleva 36 rayos)%',
  'en un trabajo terminado, la maza que no se raya en la rueda no se guarda, y lo dice');
select lives_ok(
  $$insert into public.mechanic_job_items (
      tenant_id, job_id, job_bike_id, product_id, product_name, item_type, location_key,
      quantity, unit_price, service_configuration_data)
    values ('e2830000-0000-4000-8000-000000000001',
            'e2830000-0000-4000-8000-000000000052',
            (select id from public.mechanic_job_bikes where job_id = 'e2830000-0000-4000-8000-000000000052'),
            'e2830000-0000-4000-8000-000000000101',
            'Maza Trasera Disco 36H para Piñon con hilo QR 13mm 8S', 'product', 'rear', 1, 19990,
            '{"part_change": {"key": "freehubType", "value": "threaded_freewheel"}}')$$,
  'y la de 36H, que calza, sí');

-- En un trabajo terminado, la maza o la rueda que cambia tampoco puede dejar
-- mal otra línea de esa rueda que ya tiene su recibo.
insert into results select 'trek3700', pg_temp.finish('075');
select is(
  jsonb_build_array(pg_temp.problems('trek3700'), pg_temp.receipts('075')),
  '[[], ["job_completion:185:1:freehubType=shimano_hg"]]'::jsonb,
  'la Trek 3700 termina con su cassette HG');
select throws_like(
  $$insert into public.mechanic_job_items (
      tenant_id, job_id, job_bike_id, product_id, product_name, item_type, location_key,
      quantity, unit_price, service_configuration_data)
    values ('e2830000-0000-4000-8000-000000000001',
            'e2830000-0000-4000-8000-000000000075',
            (select id from public.mechanic_job_bikes where job_id = 'e2830000-0000-4000-8000-000000000075'),
            'e2830000-0000-4000-8000-000000000101',
            'Maza Trasera Disco 36H para Piñon con hilo QR 13mm 8S', 'product', 'rear', 1, 19990,
            '{"part_change": {"key": "freehubType", "value": "threaded_freewheel"}}')$$,
  '«Maza Trasera Disco 36H para Piñon con hilo QR 13mm 8S» no se guardó: «Cassette Shimano 7V CS-HG200-7 12/32T», del mismo trabajo, no calza con esta maza (el driver trasero es «Rueda libre roscada»)%',
  'agregar después una maza de rueda libre al trabajo terminado del cassette HG no se guarda');
select is(pg_temp.fact('55', 'freehubType'), '["shimano_hg", true, "mechanic"]'::jsonb,
  'y la ficha sigue diciendo HG');
select throws_like(
  $$insert into public.mechanic_job_items (
      tenant_id, job_id, job_bike_id, product_id, product_name, item_type, location_key,
      quantity, unit_price, service_configuration_data)
    values ('e2830000-0000-4000-8000-000000000001',
            'e2830000-0000-4000-8000-000000000075',
            (select id from public.mechanic_job_bikes where job_id = 'e2830000-0000-4000-8000-000000000075'),
            'e2830000-0000-4000-8000-000000000101',
            'Maza Trasera Disco 36H para Piñon con hilo QR 13mm 8S', 'product', 'rear', 1, 19990, '{}')$$,
  '«Maza Trasera Disco 36H para Piñon con hilo QR 13mm 8S» no se guardó: «Cassette Shimano 7V CS-HG200-7 12/32T», del mismo trabajo, no calza con esta maza%',
  'tampoco sin marca: no cambia la ficha, pero el cassette del trabajo se mide con ella');

select throws_like(
  $$update public.mechanic_job_items
       set service_configuration_data = '{"hole_count": "40", "which_wheel": "rear"}'
     where id = 'e2830000-0000-4000-8000-000000000152'$$,
  '«Enrayado + Centrado» no se guardó: «Maza Trasera Disco 36H para Piñon con hilo QR 13mm 8S», del mismo trabajo, no calza con la rueda que arma esta línea (la rueda trasera lleva 40 rayos)%',
  'la Totem entregada: rayar a 40 la rueda de una maza de 36H no se guarda');
select lives_ok(
  $$update public.mechanic_job_items
       set service_configuration_data = '{"hole_count": "32", "which_wheel": "rear"}'
     where id = 'e2830000-0000-4000-8000-000000000152'$$,
  'y rayarla a 32 sí: una maza de 36H se raya en una llanta de 32');
select is(pg_temp.fact('31', 'rearSpokeHoles'), '[32, true, "job_completion"]'::jsonb,
  'la ficha de la Totem dice 32');

select lives_ok(
  $$update public.mechanic_job_items set unit_price = 21990
     where id = 'e2830000-0000-4000-8000-000000000174'$$,
  'en la Antonio terminada, cambiar el precio de la maza no mira la ficha');
-- Cambiar el repuesto conservando la marca deja el mismo recibo; lo que
-- depende del repuesto se revisa igual (revisión de Codex, 2026-09-28).
select throws_like(
  $$update public.mechanic_job_items
       set product_id = 'e2830000-0000-4000-8000-000000000108',
           product_name = 'Maza Delantera Novatec 32H 100x9mm HG D041SB'
     where id = 'e2830000-0000-4000-8000-000000000174'$$,
  '«Maza Delantera Novatec 32H 100x9mm HG D041SB» no se guardó: Center Lock en el anclaje del rotor delantero no calza con la ficha de la bici (la rueda delantera lleva 36 rayos)%',
  'cambiarla por una Novatec de 32H con la misma marca no se guarda: no se raya en la rueda de 36');
select throws_like(
  $$update public.mechanic_job_items
       set product_id = 'e2830000-0000-4000-8000-000000000112',
           product_name = 'Maza delantera 36H Center Lock (supuesta)'
     where id = 'e2830000-0000-4000-8000-000000000174'$$,
  '«Maza delantera 36H Center Lock (supuesta)» no se guardó: «Disco de Freno Flotante 160mm Cyclami», del mismo trabajo, no calza con esta maza (el anclaje del rotor delantero es «Center Lock»)%',
  'y por otra Center Lock de 36H tampoco: el rotor flotante del mismo trabajo sigue sin calzar');

-- La Vision terminó con el cassette HG que no calza con su maza de rueda
-- libre. Lo que se agrega en otra rueda, o lo que no se mide con esa maza, no
-- queda preso de eso.
select lives_ok(
  $$insert into public.mechanic_job_items (
      tenant_id, job_id, job_bike_id, product_id, product_name, item_type, location_key,
      quantity, unit_price, service_configuration_data)
    values ('e2830000-0000-4000-8000-000000000001',
            'e2830000-0000-4000-8000-000000000056',
            (select id from public.mechanic_job_bikes where job_id = 'e2830000-0000-4000-8000-000000000056'),
            'e2830000-0000-4000-8000-000000000102',
            'maza shimano hb-rm66 36h (cl) delantero negro bolsa', 'product', 'front', 1, 19990,
            '{"part_change": {"key": "frontRotorMount", "value": "centerlock"}}')$$,
  'en la Vision terminada, una maza delantera se guarda aunque atrás el cassette no calce');
select lives_ok(
  $$insert into public.mechanic_job_items (
      tenant_id, job_id, job_bike_id, product_name, item_type, location_key,
      quantity, unit_price, service_configuration_data)
    values ('e2830000-0000-4000-8000-000000000001',
            'e2830000-0000-4000-8000-000000000056',
            (select id from public.mechanic_job_bikes where job_id = 'e2830000-0000-4000-8000-000000000056'),
            'Enrayado + Centrado', 'service', 'none', 1, 15000,
            '{"hole_count": "36", "which_wheel": "rear"}')$$,
  'y un Enrayado trasero de 36 también: el cassette no se mide con los rayos');
select throws_like(
  $$insert into public.mechanic_job_items (
      tenant_id, job_id, job_bike_id, product_id, product_name, item_type, location_key,
      quantity, unit_price, service_configuration_data)
    values ('e2830000-0000-4000-8000-000000000001',
            'e2830000-0000-4000-8000-000000000056',
            (select id from public.mechanic_job_bikes where job_id = 'e2830000-0000-4000-8000-000000000056'),
            'e2830000-0000-4000-8000-000000000141',
            'Cassette Shimano 7V CS-HG200-7 12/32T', 'product', 'rear', 1, 19990,
            '{"part_change": {"key": "freehubType", "value": "shimano_hg"}}')$$,
  '«Cassette Shimano 7V CS-HG200-7 12/32T» no se guardó: Shimano HG en el driver trasero no calza con la maza que instala el trabajo (el driver trasero es «Rueda libre roscada»)%',
  'otro cassette HG en la Vision terminada no se guarda, y dice que es por la maza del trabajo');

-- Cambiar el cassette de 7 por uno de 8 con la misma marca, con un mando
-- trasero nuevo en el trabajo: espera la decisión de la transmisión, aunque
-- el recibo ya exista (revisión de Codex, 2026-09-28).
select lives_ok(
  $$insert into public.mechanic_job_items (
      tenant_id, job_id, job_bike_id, product_id, product_name, item_type, location_key,
      quantity, unit_price, service_configuration_data)
    values ('e2830000-0000-4000-8000-000000000001',
            'e2830000-0000-4000-8000-000000000075',
            (select id from public.mechanic_job_bikes where job_id = 'e2830000-0000-4000-8000-000000000075'),
            'e2830000-0000-4000-8000-000000000144',
            'Mando Shimano Tourney SL-TX50 8V derecho', 'product', 'none', 1, 12990, '{}')$$,
  'la Trek 3700 terminada suma un mando trasero');
select lives_ok(
  $$update public.mechanic_job_items
       set product_id = 'e2830000-0000-4000-8000-000000000143',
           product_name = 'PIÑON CASSETTE HG 8V 12-32T SUNRACE MOD.CSM400 8BU 8BU'
     where id = 'e2830000-0000-4000-8000-000000000185'$$,
  'y su cassette pasa a uno de 8: se guarda');
select is(
  (select count(*)::integer from public.bike_events
    where bike_id = 'e2830000-0000-4000-8000-000000000055'
      and event_type = 'installed_fact_needs_decision'
      and summary like '%el trabajo también cambia el mando trasero%'),
  1,
  'pero la ficha dice que espera la decisión de la transmisión');

-- La maza que faltaba arregla el rotor: el SM-RT10 de la Marlin 7 no calzaba
-- con la ficha de 6 pernos; con la HB-RM66 en el mismo trabajo, sí.
select lives_ok(
  $$insert into public.mechanic_job_items (
      id, tenant_id, job_id, job_bike_id, product_id, product_name, item_type, location_key,
      quantity, unit_price, service_configuration_data)
    values ('e2830000-0000-4000-8000-000000000186',
            'e2830000-0000-4000-8000-000000000001',
            'e2830000-0000-4000-8000-000000000054',
            (select id from public.mechanic_job_bikes where job_id = 'e2830000-0000-4000-8000-000000000054'),
            'e2830000-0000-4000-8000-000000000102',
            'maza shimano hb-rm66 36h (cl) delantero negro bolsa', 'product', 'front', 1, 19990,
            '{"part_change": {"key": "frontRotorMount", "value": "centerlock"}}')$$,
  'agregar la HB-RM66 al trabajo terminado de la Marlin 7 se guarda');
select is(
  jsonb_build_array(
    pg_temp.fact('34', 'frontRotorMount'),
    pg_temp.fact('34', 'frontRotorSizeMm'),
    pg_temp.receipts('054')),
  '[["centerlock", null, "job_completion"], [160, true, "mechanic"],
    ["job_completion:156:1:frontRotorSizeMm=160", "job_completion:186:1:frontRotorMount=centerlock"]]'::jsonb,
  'y la ficha toma el Center Lock declarado, y el rotor que ahora calza deja su recibo (sus 160 ya estaban)');

-- Una maza que cambia su repuesto conservando la marca, y dos Enrayados de la
-- misma rueda que no dicen lo mismo (revisión de Codex, 2026-09-28).
select lives_ok(
  $$update public.mechanic_job_items
       set service_configuration_data = '{"hole_count": "36", "which_wheel": "rear"}'
     where id = 'e2830000-0000-4000-8000-000000000152'$$,
  'la Totem vuelve a su rueda de 36');
select throws_like(
  $$update public.mechanic_job_items
       set product_id = 'e2830000-0000-4000-8000-000000000109',
           product_name = 'Maza Trasera Freewheel Disco 32h Betta'
     where id = 'e2830000-0000-4000-8000-000000000151'$$,
  '«Maza Trasera Freewheel Disco 32h Betta» no se guardó: Rueda libre roscada en el driver trasero no calza con la rueda que arma el trabajo (la rueda trasera lleva 36 rayos)%',
  'cambiar su maza de 36H por la Betta de 32H con la misma marca no se guarda');
select throws_like(
  $$insert into public.mechanic_job_items (
      tenant_id, job_id, job_bike_id, product_name, item_type, location_key,
      quantity, unit_price, service_configuration_data)
    values ('e2830000-0000-4000-8000-000000000001',
            'e2830000-0000-4000-8000-000000000051',
            (select id from public.mechanic_job_bikes where job_id = 'e2830000-0000-4000-8000-000000000051'),
            'Enrayado + Centrado', 'service', 'none', 1, 15000,
            '{"hole_count": "40", "which_wheel": "rear"}')$$,
  '«Enrayado + Centrado» no se guardó: otro Enrayado del mismo trabajo arma la rueda trasera a 36 rayos%',
  'un segundo Enrayado trasero de 40 no se guarda');
select is(pg_temp.fact('31', 'rearSpokeHoles'), '[36, true, "job_completion"]'::jsonb,
  'y la ficha de la Totem sigue en 36');

-- Los dos Enrayados ya estaban al terminar: la rueda no se sabe, y la maza
-- no se da por buena (revisión de Codex, 2026-09-28).
insert into results select 'merak2', pg_temp.finish('077');
select is(
  jsonb_build_array(
    pg_temp.problems('merak2'),
    pg_temp.fact('57', 'rearSpokeHoles'),
    pg_temp.fact('57', 'freehubType'),
    pg_temp.receipts('077')),
  '[[{"key": "freehubType", "value": "threaded_freewheel", "reason": "incompatible",
      "requires_key": "rearSpokeHoles", "requires_value": "36 o 40", "requires_source": "job_build"},
     {"key": "rearSpokeHoles", "value": 36, "reason": "conflicting_build", "requires_value": "40"},
     {"key": "rearSpokeHoles", "value": 40, "reason": "conflicting_build", "requires_value": "36"}],
    null, null, []]'::jsonb,
  'con dos Enrayados traseros que no coinciden nada se escribe y se dice por qué');

-- Quitarle la marca a la maza mientras se cambia no salta la otra línea.
select throws_like(
  $$update public.mechanic_job_items
       set product_id = 'e2830000-0000-4000-8000-000000000105',
           product_name = 'Maza Trasera Freestyle sellada 14mm 9T 36H Red',
           service_configuration_data = '{}'
     where id = 'e2830000-0000-4000-8000-000000000188'$$,
  '«Maza Trasera Freestyle sellada 14mm 9T 36H Red» no se guardó: «PIÑON ATORNILLADO 7 VELOCIDADES FALCON MOD.FW71», del mismo trabajo, no calza con esta maza (el driver trasero es «Driver BMX»)%',
  'en la Marlin 5 terminada, cambiar la maza por una BMX sin marca no se guarda: el FW71 del trabajo no entra');

-- Una maza que dice ser de la otra rueda no es la maza de ésta.
select lives_ok(
  $$insert into public.mechanic_job_items (
      id, tenant_id, job_id, job_bike_id, product_id, product_name, item_type, location_key,
      quantity, unit_price, service_configuration_data)
    values ('e2830000-0000-4000-8000-000000000190',
            'e2830000-0000-4000-8000-000000000001',
            'e2830000-0000-4000-8000-000000000067',
            (select id from public.mechanic_job_bikes where job_id = 'e2830000-0000-4000-8000-000000000067'),
            'e2830000-0000-4000-8000-000000000122',
            'Disco freno G3 AE 160mm Genérico con tornillos 1Un', 'product', 'rear', 1, 9990, '{}')$$,
  'un rotor trasero en el trabajo de la Lahsen');
select is(
  jsonb_build_array(
    public.job_hub_at_wheel_internal('e2830000-0000-4000-8000-000000000001',
      pg_temp.line('190'), 'e2830000-0000-4000-8000-000000000047', 'rear'),
    public.job_hub_at_wheel_internal('e2830000-0000-4000-8000-000000000001',
      pg_temp.line('190'), 'e2830000-0000-4000-8000-000000000047', 'front')),
  '[null, null]'::jsonb,
  'la Novatec delantera marcada atrás no es la maza de ninguna rueda');

-- Borrar la maza después de terminar no deshace la ficha: lo dice.
delete from public.mechanic_job_items where id = pg_temp.line('154');
select is(
  jsonb_build_array(
    pg_temp.fact('33', 'frontRotorMount'),
    (select count(*)::integer from public.bike_events
      where bike_id = 'e2830000-0000-4000-8000-000000000033'
        and event_type = 'installed_fact_unsupported'
        and summary like 'La ficha dice Center Lock en el anclaje del rotor delantero por «una línea que ya no está»%')),
  '[["centerlock", null, "job_completion"], 1]'::jsonb,
  'borrar la HB-RM66 deja el anclaje y el aviso');

select * from finish();
rollback;
