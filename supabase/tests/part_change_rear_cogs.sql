begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select no_plan();

-- Cambios de partes, el cassette y el piñón de rosca (20260928120000): lo
-- que se instala atrás tiene que calzar con el driver de la maza
-- (`freehubType`) y con los piñones de la transmisión (`drivetrainConfig`).
-- Si la ficha no sabe el driver, lo instalado lo dice, declarado. Si no calza,
-- nada se escribe: es incompatible, o queda pendiente cuando el mismo trabajo
-- cambia la pieza que lo decide (la maza trasera, el mando trasero). Lo que
-- calza sin ser lo mismo (un cassette HG en un núcleo HG Road 11) no cambia
-- la ficha. La cuenta de piñones nunca se escribe.
--
-- Datos reales (producción, lectura del 2026-09-28): los productos por su
-- nombre, con su familia, estrías y piñones tal como los da el lector; los
-- mandos y mazas por su nombre y posición. Las bicis llevan nombres del
-- taller y configuraciones que existen en producción (3x7, 2x8, 3x6, 1x6,
-- 1x9, 3x8, 1x10 con `shimano_hg`, `threaded_freewheel` o `unknown`); la
-- bici con núcleo HG Road 11 no existe en producción y se arma para el caso.
--
-- La base local no trae el motor de fichas: el lector del producto se
-- reemplaza en esta transacción por dos tablas con esos valores; el real se
-- comprueba con el read-back contra producción.

-- ============================================================================
-- La relación y cómo se dice
-- ============================================================================

select is(
  (select jsonb_agg(jsonb_build_object(
            'spec', spec_key, 'key', bike_fact_key, 'family', template_key,
            'rule', on_mismatch, 'constant', constant_value,
            'condition', product_condition)
          order by bike_fact_key, template_key)
     from public.bike_fact_spec_links
    where bike_fact_key in ('freehubType', 'drivetrainConfig')
      -- La fila de la maza (20260928130000) la prueba su suite.
      and template_key in ('cassette', 'freewheel')),
  '[{"key": "drivetrainConfig", "rule": "check", "spec": "sprocket_count", "family": "cassette", "constant": null, "condition": null},
    {"key": "drivetrainConfig", "rule": "check", "spec": "sprocket_count", "family": "freewheel", "constant": null, "condition": null},
    {"key": "freehubType", "rule": "conflict", "spec": "cassette_spline_standard", "family": "cassette", "constant": null, "condition": null},
    {"key": "freehubType", "rule": "conflict", "spec": "_family", "family": "freewheel", "constant": "threaded_freewheel",
     "condition": {"max": 14, "min": 2, "spec_key": "sprocket_count"}}]'::jsonb,
  'el driver trasero lo dicen las estrías del cassette o la familia del piñón de rosca de 2 a 14 coronas, y tiene que calzar; los piñones sólo se revisan');
select is(
  (select value_map
     from public.bike_fact_spec_links
    where spec_key = 'cassette_spline_standard'),
  '{"Shimano HG spline S (7v)": "shimano_hg",
    "Shimano HG spline M (8/9/10v y MTB 11v; ROAD 11v y 7v sólo según filas C-731; LINKGLIDE según C-649)": "shimano_hg",
    "Shimano HG spline L (ROAD 11/12v; otras coronas sólo según filas C-731)": "shimano_hg_road_11",
    "Shimano MICRO SPLINE (MTB 12v)": "microspline",
    "SRAM XD": "sram_xd", "SRAM XDR": "sram_xdr",
    "Campagnolo": "campagnolo", "Campagnolo N3W": "campagnolo_n3w"}'::jsonb,
  'cada estría con código en la ficha de la bici; L2 y XD SLIM no lo tienen');
select is(
  jsonb_build_array(
    public.drivetrain_rear_cog_count('3x7'),
    public.drivetrain_rear_cog_count('1x12'),
    public.drivetrain_rear_cog_count('singlespeed'),
    public.drivetrain_rear_cog_count(' 3 x 8 '),
    public.drivetrain_rear_cog_count('4x7'),
    public.drivetrain_rear_cog_count('2x15'),
    public.drivetrain_rear_cog_count('unknown'),
    public.drivetrain_rear_cog_count(null)),
  '[7, 12, 1, 8, null, null, null, null]'::jsonb,
  'los piñones salen de la configuración; lo que no se lee no refuta');
select is(
  jsonb_build_array(
    public.installed_bike_fact_label('freehubType', '"shimano_hg"'),
    public.installed_bike_fact_label('freehubType', '"threaded_freewheel"'),
    public.bike_fact_requirement_text('freehubType', 'microspline'),
    public.bike_fact_requirement_text('drivetrainConfig', '3x7'),
    public.installed_bike_fact_label('rearRotorSizeMm', '180'),
    public.bike_fact_requirement_text('rearWheelBsdMm', '622')),
  '["Shimano HG en el driver trasero", "Rueda libre roscada en el driver trasero",
    "el driver trasero es «Micro Spline»", "la transmisión es 3x7",
    "180 mm en el rotor trasero", "la rueda trasera es 622 (29″/700c)"]'::jsonb,
  'se dice como en el taller, y el rotor y el neumático se siguen diciendo igual');
select ok(
  not has_function_privilege('authenticated',
    'public.bike_fact_line_wrote_internal(uuid,uuid,uuid,text,jsonb)', 'EXECUTE')
  and not has_function_privilege('authenticated',
    'public.job_installs_rear_family_internal(uuid,uuid,uuid,text)', 'EXECUTE')
  and not has_function_privilege('authenticated',
    'public.bike_fact_link_value_internal(public.bike_fact_spec_links,jsonb)', 'EXECUTE')
  and not has_function_privilege('authenticated',
    'public.drivetrain_rear_cog_count(text)', 'EXECUTE')
  and not exists (
    select 1 from pg_proc
     where proname = 'bike_fact_line_wrote_internal'
       and pg_get_function_identity_arguments(oid) like '%numeric%')
  and has_function_privilege('authenticated',
    'public.job_part_change_writers_v1(uuid)', 'EXECUTE'),
  'las reglas son internas y la regla de medidas quedó reemplazada');

-- ============================================================================
-- Fixture
-- ============================================================================

insert into public.tenants (id, shop_name) values
  ('e2820000-0000-4000-8000-000000000001', 'Taller transmisiones');

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('e2820000-0000-4000-8000-000000000099', 'authenticated', 'authenticated',
   'transmisiones@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now());

insert into public.user_profiles (user_id, tenant_id, role) values
  ('e2820000-0000-4000-8000-000000000099',
   'e2820000-0000-4000-8000-000000000001', 'admin');

insert into public.customers (id, tenant_id, name) values
  ('e2820000-0000-4000-8000-000000000010',
   'e2820000-0000-4000-8000-000000000001', 'Cliente transmisiones');

insert into public.bikes (id, tenant_id, customer_id, brand, model)
select ('e2820000-0000-4000-8000-0000000000' || b.n)::uuid,
       'e2820000-0000-4000-8000-000000000001',
       'e2820000-0000-4000-8000-000000000010', b.brand, b.model
  from (values
    ('31', 'Giant', 'Talon'), ('32', 'Trek', 'Marlin 5'), ('33', 'Fuji', 'Addy 2.0'),
    ('34', 'Bianchi', 'Classic 24'), ('35', 'Trek', 'Marlin 7'), ('36', 'RAM', 'Rebel'),
    ('37', 'Hyper', 'Spinfit 7000'), ('38', 'GT', 'Outpost'), ('39', 'Trek', 'Marlin 6'),
    ('40', 'Oxford', 'Capital'), ('41', 'Radost', 'Daruk'), ('42', 'Kona', 'Rondabout'),
    ('43', 'Scott', 'Scale 60'), ('44', 'Ozark', '20'), ('45', 'Oxford', 'Jade'),
    ('46', 'Fuji', 'Roubaix'), ('47', 'Oxford', 'Rally'), ('48', 'Altitude', 'K10'),
    ('49', 'Bianchi', 'Stone Mountain 29sx'), ('50', 'Oxford', 'Orion 4')
  ) b(n, brand, model);

-- La ficha que el mecánico ya confirmó: driver, transmisión y su total.
insert into public.bike_profiles (tenant_id, bike_id, technical_profile)
select 'e2820000-0000-4000-8000-000000000001',
       ('e2820000-0000-4000-8000-0000000000' || p.n)::uuid,
       jsonb_build_object(
         'values', jsonb_strip_nulls(jsonb_build_object(
           'freehubType', p.driver, 'drivetrainConfig', p.config,
           'drivetrainSpeeds', p.total)),
         'sources', jsonb_strip_nulls(jsonb_build_object(
           'freehubType', case when p.driver is not null then 'mechanic' end,
           'drivetrainConfig', 'mechanic', 'drivetrainSpeeds', 'mechanic')),
         'confirmed', jsonb_strip_nulls(jsonb_build_object(
           'freehubType', case when p.driver not in ('unknown') then true end,
           'drivetrainConfig', true, 'drivetrainSpeeds', true)))
  from (values
    ('31', null, '2x8', 16), ('32', 'shimano_hg', '3x7', 21),
    ('33', 'shimano_hg_road_11', '2x9', 18), ('34', 'shimano_hg', '3x6', 18),
    ('35', 'shimano_hg', '1x10', 10), ('36', 'threaded_freewheel', '2x7', 14),
    ('37', 'threaded_freewheel', '3x7', 21), ('38', 'shimano_hg', '3x8', 24),
    ('39', 'shimano_hg', '3x8', 24), ('40', 'threaded_freewheel', '1x6', 6),
    ('42', 'unknown', '1x9', 9), ('44', 'shimano_hg', 'singlespeed', 1),
    ('45', 'threaded_freewheel', '2x7', 14), ('46', 'shimano_hg_road_11', '2x8', 16)
  ) p(n, driver, config, total);

-- La Ozark tiene driver sin fuente ni confirmación, como una ficha anterior
-- a las fuentes: no es de ninguna línea.
update public.bike_profiles
   set technical_profile = jsonb_set(technical_profile, '{sources}',
         (technical_profile->'sources') - 'freehubType')
       #- '{confirmed,freehubType}'
 where bike_id = 'e2820000-0000-4000-8000-000000000044';

insert into public.products (id, tenant_id, name, category_name)
select ('e2820000-0000-4000-8000-000000000' || p.n)::uuid,
       'e2820000-0000-4000-8000-000000000001', p.name, p.category
  from (values
    ('101', 'Cassette Shimano 7V CS-HG200-7 12/32T', 'Transmisión'),
    ('102', 'PIÑON CASSETTE HG 8V 12-32T SUNRACE MOD.CSM400 8BU 8BU', 'Transmisión'),
    ('103', 'CASSETTE SHIMANO 9V. (11-32) HG200 AE', 'Transmisión'),
    ('104', 'Cassette 12v Shimano SLX CS-M7100 10-51T Microspline', 'Transmisión'),
    ('105', 'Cassette Shimano 105 CS-R7100 12V 11-34T', 'Transmisión'),
    ('106', 'Piñón SRAM HG Eagle NX PowerGlide 2 A1 PG1230 12V 11-50T', 'Transmisión'),
    ('107', 'PIÑON FW-61 FOR 6 SPEED 14-28T,COLOR:BR+ED,INDEX WITH FALCON LOGO PACKING:1PCON WHITE BOX', 'Transmisión'),
    ('108', 'PIÑON ATORNILLADO 7 VELOCIDADES FALCON MOD.FW71', 'Transmisión'),
    ('109', 'PIÑON 15T FIJO MOD. PMA7-15T', 'Transmisión'),
    ('110', 'PIÑON 16T LIBRE ROCKET COMPATIBLE / GENERICO', 'Transmisión'),
    ('111', 'Maza Trasera ARC 32H 135x10mm HG MT001', 'Mazas'),
    ('112', 'MAZA (JUEGO) ALUMINIO (36H) SILVER QS-401 C/TUERCA', 'Mazas'),
    ('113', 'Shifter Genérico Trasero', 'Mandos'),
    ('114', 'MANILLA CAMBIO SHIMANO SL-M315, IZQ. 3-SPEED RAPIDFIRE PLUS', 'Mandos'),
    ('115', 'PIÑON LIBRE 14T MOD. DTO14T', 'Transmisión'),
    ('116', 'Piñon 7 Veloc 12/32T CS-HG200-7V', 'Transmisión'),
    ('117', 'PIÑON FW-71 FOR 7 SPEED 14-28T,COLOR:BR+ED, INDEX WITH FALCON LOGO PACKING:1PCON WHITE BOX', 'Transmisión'),
    ('118', 'Maza Neco MTB 7/8/9 Vel.36 H. Black', 'Mazas'),
    ('119', 'PIÑON FW-734 FOR 7 SPEED 14-34T,COLOR:BR+ED, INDEX WITH FALCON LOGO PACKING:1PCON WHITE BOX', 'Transmisión'),
    ('120', 'Cassette Shimano HG200 Altus 9V 11-34T', 'Transmisión')
  ) p(n, name, category);

-- El lector de la ficha del producto: la familia de cada uno y lo que dice.
-- Ninguna estría ni cuenta está verificada en producción; 116 y 117 lo
-- están aquí para ver qué cambia. La cuenta 1 de 115 es supuesta (en
-- producción no la dice): un piñón de una corona no se anota aunque la diga.
-- La Maza Neco no dice su posición (como 5 de 52 mazas en producción). Las
-- cuentas 99 de 119 y 120 son un error de tipeo supuesto de la ficha técnica.
create temporary table test_product_templates (
  product_id uuid primary key,
  template_key text
);
insert into test_product_templates
select ('e2820000-0000-4000-8000-000000000' || t.n)::uuid, t.template_key
  from (values
    ('101', 'cassette'), ('102', 'cassette'), ('103', 'cassette'), ('104', 'cassette'),
    ('105', 'cassette'), ('106', 'cassette'), ('107', 'freewheel'), ('108', 'freewheel'),
    ('109', 'freewheel'), ('110', 'freewheel'), ('111', 'hub'), ('112', 'hub'),
    ('113', 'shifter'), ('114', 'shifter'), ('115', 'freewheel'), ('116', 'cassette'),
    ('117', 'freewheel'), ('118', 'hub'), ('119', 'freewheel'), ('120', 'cassette')
  ) t(n, template_key);

create temporary table test_product_specs (
  product_id uuid,
  spec_key text,
  value jsonb,
  verified boolean default false
);
insert into test_product_specs (product_id, spec_key, value, verified)
select ('e2820000-0000-4000-8000-000000000' || s.n)::uuid, s.spec_key, s.value::jsonb, s.verified
  from (values
    ('101', 'cassette_spline_standard', '"Shimano HG spline S (7v)"', false),
    ('101', 'sprocket_count', '7', false),
    ('102', 'cassette_spline_standard', '"Shimano HG spline M (8/9/10v y MTB 11v; ROAD 11v y 7v sólo según filas C-731; LINKGLIDE según C-649)"', false),
    ('102', 'sprocket_count', '8', false),
    ('103', 'cassette_spline_standard', '"Shimano HG spline M (8/9/10v y MTB 11v; ROAD 11v y 7v sólo según filas C-731; LINKGLIDE según C-649)"', false),
    ('103', 'sprocket_count', '9', false),
    ('104', 'cassette_spline_standard', '"Shimano MICRO SPLINE (MTB 12v)"', false),
    ('104', 'sprocket_count', '12', false),
    ('105', 'cassette_spline_standard', '"Shimano HG spline L2 (ROAD 12v dedicado)"', false),
    ('105', 'sprocket_count', '12', false),
    ('106', 'sprocket_count', '12', false),
    ('107', 'sprocket_count', '6', false),
    ('108', 'sprocket_count', '7', false),
    ('111', 'hub_package_position', '"Trasera"', false),
    ('112', 'hub_package_position', '"Juego (delantera y trasera)"', false),
    ('113', 'shifter_position', '"Derecho (trasero)"', false),
    ('114', 'shifter_position', '"Izquierdo (delantero)"', false),
    ('115', 'sprocket_count', '1', false),
    ('116', 'cassette_spline_standard', '"Shimano HG spline S (7v)"', true),
    ('116', 'sprocket_count', '7', true),
    ('117', 'sprocket_count', '7', true),
    ('119', 'sprocket_count', '99', false),
    ('120', 'cassette_spline_standard', '"Shimano HG spline M (8/9/10v y MTB 11v; ROAD 11v y 7v sólo según filas C-731; LINKGLIDE según C-649)"', false),
    ('120', 'sprocket_count', '99', false)) s(n, spec_key, value, verified);

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

-- Un trabajo por bici; 063 y 064 son dos trabajos de la misma Scott, y 065
-- sólo lleva líneas para leer la regla.
insert into public.mechanic_jobs (id, tenant_id, customer_id, bike_id, job_number, created_by)
select ('e2820000-0000-4000-8000-000000000' || j.n)::uuid,
       'e2820000-0000-4000-8000-000000000001',
       'e2820000-0000-4000-8000-000000000010',
       ('e2820000-0000-4000-8000-0000000000' || j.bike)::uuid,
       'PG-PIN-' || j.n,
       'e2820000-0000-4000-8000-000000000099'
  from (values
    ('051', '31'), ('052', '32'), ('053', '33'), ('054', '34'), ('055', '35'),
    ('056', '36'), ('057', '37'), ('058', '38'), ('059', '39'), ('060', '40'),
    ('061', '41'), ('062', '42'), ('063', '43'), ('064', '43'), ('065', '44'),
    ('066', '44'), ('067', '45'), ('068', '46'), ('069', '47'), ('070', '49'),
    ('071', '49'), ('072', '49')) j(n, bike);

insert into public.mechanic_job_bikes (tenant_id, job_id, bike_id)
select 'e2820000-0000-4000-8000-000000000001', j.id, j.bike_id
  from public.mechanic_jobs j
 where j.tenant_id = 'e2820000-0000-4000-8000-000000000001'
on conflict (job_id, bike_id) do nothing;
-- El trabajo 069 tiene dos bicis: la Oxford Rally de la cabecera y la
-- Altitude K10.
insert into public.mechanic_job_bikes (tenant_id, job_id, bike_id) values
  ('e2820000-0000-4000-8000-000000000001',
   'e2820000-0000-4000-8000-000000000069',
   'e2820000-0000-4000-8000-000000000048'),
  -- 070 y 071: la Bianchi Stone Mountain 29sx y la Oxford Orion 4.
  ('e2820000-0000-4000-8000-000000000001',
   'e2820000-0000-4000-8000-000000000070',
   'e2820000-0000-4000-8000-000000000050'),
  ('e2820000-0000-4000-8000-000000000001',
   'e2820000-0000-4000-8000-000000000071',
   'e2820000-0000-4000-8000-000000000050');

insert into public.mechanic_job_items (
  id, tenant_id, job_id, product_id, product_name, item_type, location_key,
  quantity, unit_price, service_configuration_data
)
select ('e2820000-0000-4000-8000-000000000' || l.n)::uuid,
       'e2820000-0000-4000-8000-000000000001',
       ('e2820000-0000-4000-8000-000000000' || l.job)::uuid,
       p.id, p.name, 'product', l.location_key, 1, 19990,
       coalesce(l.data::jsonb, '{}'::jsonb)
  from (values
    ('161', '051', '102', 'rear', '{"part_change": {"key": "freehubType", "value": "shimano_hg"}}'),
    ('162', '052', '101', 'rear', '{"part_change": {"key": "freehubType", "value": "shimano_hg"}}'),
    ('163', '053', '103', 'rear', '{"part_change": {"key": "freehubType", "value": "shimano_hg"}}'),
    ('164', '054', '107', 'rear', '{"part_change": {"key": "freehubType", "value": "threaded_freewheel"}}'),
    ('165', '055', '104', 'rear', '{"part_change": {"key": "freehubType", "value": "microspline"}}'),
    ('166', '056', '101', 'rear', '{"part_change": {"key": "freehubType", "value": "shimano_hg"}}'),
    ('167', '056', '111', 'rear', null),
    ('168', '057', '101', 'rear', '{"part_change": {"key": "freehubType", "value": "shimano_hg"}}'),
    ('169', '057', '112', 'front', null),
    ('170', '058', '103', 'rear', '{"part_change": {"key": "freehubType", "value": "shimano_hg"}}'),
    ('171', '058', '113', 'none', null),
    ('172', '059', '103', 'rear', '{"part_change": {"key": "freehubType", "value": "shimano_hg"}}'),
    ('173', '059', '114', 'none', null),
    ('174', '060', '108', 'rear', '{"part_change": {"key": "freehubType", "value": "threaded_freewheel"}}'),
    ('175', '061', '108', 'rear', '{"part_change": {"key": "freehubType", "value": "threaded_freewheel"}}'),
    ('176', '062', '103', 'rear', '{"part_change": {"key": "freehubType", "value": "shimano_hg"}}'),
    ('177', '063', '103', 'rear', '{"part_change": {"key": "freehubType", "value": "shimano_hg"}}'),
    ('178', '064', '103', 'rear', '{"part_change": {"key": "freehubType", "value": "shimano_hg"}}'),
    ('181', '065', '105', 'rear', '{"part_change": {"key": "freehubType", "value": "shimano_hg"}}'),
    ('182', '065', '106', 'rear', '{"part_change": {"key": "freehubType", "value": "shimano_hg"}}'),
    ('183', '065', '109', 'rear', '{"part_change": {"key": "freehubType", "value": "threaded_freewheel"}}'),
    ('184', '065', '110', 'rear', '{"part_change": {"key": "freehubType", "value": "threaded_freewheel"}}'),
    ('185', '065', '115', 'rear', '{"part_change": {"key": "freehubType", "value": "threaded_freewheel"}}'),
    ('186', '065', '101', 'rear', '{"part_change": {"key": "freehubType", "value": "microspline"}}'),
    ('187', '065', '101', 'rear', '{"part_change": {"key": "drivetrainConfig", "value": 7}}'),
    ('188', '065', '101', 'front', '{"part_change": {"key": "freehubType", "value": "shimano_hg"}}'),
    ('189', '065', '101', 'rear', '{"part_change": {"key": "freehubType", "value": "shimano_hg"}}'),
    ('190', '065', '108', 'rear', '{"part_change": {"key": "freehubType", "value": "threaded_freewheel"}}'),
    ('191', '065', '116', 'rear', '{"part_change": {"key": "freehubType", "value": "shimano_hg"}}'),
    ('192', '065', '117', 'rear', '{"part_change": {"key": "freehubType", "value": "threaded_freewheel"}}'),
    ('193', '066', '108', 'rear', '{"part_change": {"key": "freehubType", "value": "threaded_freewheel"}}'),
    ('194', '065', '119', 'rear', '{"part_change": {"key": "freehubType", "value": "threaded_freewheel"}}'),
    ('195', '065', '120', 'rear', '{"part_change": {"key": "freehubType", "value": "shimano_hg"}}'),
    ('196', '068', '103', 'rear', '{"part_change": {"key": "freehubType", "value": "shimano_hg"}}'),
    ('197', '067', '101', 'rear', '{"part_change": {"key": "freehubType", "value": "shimano_hg"}}'),
    ('198', '067', '118', 'none', null),
    -- En General (sin fila de bici) de un trabajo con dos bicis.
    ('199', '069', '101', 'rear', '{"part_change": {"key": "freehubType", "value": "shimano_hg"}}'),
    -- En General de 070 y 071, cada una con su marca de antes.
    ('200', '070', '101', 'rear', '{"part_change": {"key": "freehubType", "value": "shimano_hg"}}'),
    ('201', '071', '101', 'rear', '{"part_change": {"key": "freehubType", "value": "shimano_hg"}}'),
    -- En General de 072, que sólo tiene la Bianchi; la Orion llega al guardar.
    ('202', '072', '101', 'rear', '{"part_change": {"key": "freehubType", "value": "shimano_hg"}}')
  ) l(n, job, product, location_key, data)
  join public.products p on p.id = ('e2820000-0000-4000-8000-000000000' || l.product)::uuid;

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'e2820000-0000-4000-8000-000000000099', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub',
  'e2820000-0000-4000-8000-000000000099', true);

create temporary table status_ids as
select code, id
  from public.job_statuses
 where tenant_id = 'e2820000-0000-4000-8000-000000000001';

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
   where bp.bike_id = ('e2820000-0000-4000-8000-0000000000' || p_bike)::uuid
$$;

create or replace function pg_temp.finish(p_job text, p_code text default 'FINALIZADO')
returns jsonb
language sql
as $$
  select public.transition_mechanic_job_status(
    ('e2820000-0000-4000-8000-000000000' || p_job)::uuid,
    (select id from status_ids where code = p_code),
    'pin-' || p_job || '-' || p_code);
$$;

-- El cierre nuevo rechaza la incompatibilidad y deshace sus escrituras. El
-- detalle de ese rechazo mantiene los casos de matriz discriminantes.
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
  return jsonb_build_object('blocked', true, 'problems', v_detail::jsonb->'problems');
end;
$$;

-- Lo que se informa de una línea, sin sus ids.
create or replace function pg_temp.problems(p_label text)
returns jsonb
language sql
as $$
  select coalesce(jsonb_agg(problem - 'item_id' - 'bike_id' - 'item_name'), '[]'::jsonb)
    from results r
   cross join lateral jsonb_array_elements(
           coalesce(r.result->'installed_bike_facts'->'problems', r.result->'problems')) problem
   where r.label = p_label
$$;

create or replace function pg_temp.line(p_n text)
returns uuid
language sql
as $$ select ('e2820000-0000-4000-8000-000000000' || p_n)::uuid $$;

-- ============================================================================
-- La regla: qué línea marca el driver
-- ============================================================================

select is(
  public.job_line_part_change_internal('e2820000-0000-4000-8000-000000000001', pg_temp.line('189'))
    - 'link_id',
  '{"key": "freehubType", "value": "shimano_hg", "spec_key": "cassette_spline_standard",
    "position": "rear", "on_mismatch": "conflict", "template_key": "cassette", "verified": false}'::jsonb,
  'el CS-HG200-7 atrás respalda Shimano HG en el driver trasero, por sus estrías');
select is(
  public.job_line_part_change_internal('e2820000-0000-4000-8000-000000000001', pg_temp.line('190'))
    - 'link_id',
  '{"key": "freehubType", "value": "threaded_freewheel", "spec_key": "_family",
    "position": "rear", "on_mismatch": "conflict", "template_key": "freewheel", "verified": false}'::jsonb,
  'el piñón de rosca FW71 de 7 coronas respalda rueda libre roscada, por su familia');
select is(
  jsonb_build_array(
    (public.job_line_part_change_internal('e2820000-0000-4000-8000-000000000001', pg_temp.line('191'))->'verified'),
    (public.job_line_part_change_internal('e2820000-0000-4000-8000-000000000001', pg_temp.line('192'))->'verified')),
  '[true, false]'::jsonb,
  'unas estrías verificadas se confirman; la familia nunca es un dato verificado del producto');
select is(
  (select jsonb_agg(public.job_line_part_change_internal(
            'e2820000-0000-4000-8000-000000000001', pg_temp.line(n)) order by n)
     from unnest(array['181', '182', '183', '184', '185', '186', '187', '188', '194']) n),
  '[null, null, null, null, null, null, null, null, null]'::jsonb,
  'no marcan: el 105 L2 y el SRAM sin estrías (sin código), el piñón fijo, los libres de una corona o sin cuenta, otra estría, la transmisión (sólo se revisa), la rueda delantera y un piñón de rosca de 99 coronas');
-- Una cuenta de 99 en la ficha técnica no es una transmisión: no refuta.
select is(
  public.bike_fact_part_conflict_internal(
    'e2820000-0000-4000-8000-000000000001', pg_temp.line('195'),
    'e2820000-0000-4000-8000-000000000044', 'freehubType', '"shimano_hg"',
    '{"freehubType": "shimano_hg", "drivetrainConfig": "3x8"}', '{}', null),
  null,
  'un cassette que dice 99 piñones no choca con una 3x8');

-- ============================================================================
-- Sin driver en la ficha: el cassette lo dice, declarado
-- ============================================================================

insert into results select 'uno', pg_temp.finish('051');
select is(
  (select jsonb_path_query_array(result, '$.installed_bike_facts.applied[*]')
     from results where label = 'uno')
    #- '{0,item_id}' #- '{0,bike_id}' #- '{0,item_name}',
  '[{"op": "declare", "key": "freehubType", "value": "shimano_hg", "changed": true, "previous": null,
     "operation_key": "job_completion:e2820000-0000-4000-8000-000000000161:1:freehubType=shimano_hg"}]'::jsonb,
  'la Giant Talon toma Shimano HG del SUNRACE CSM400, declarado');
select is(
  jsonb_build_array(
    pg_temp.fact('31', 'freehubType'),
    pg_temp.fact('31', 'drivetrainConfig'),
    pg_temp.problems('uno')),
  '[["shimano_hg", null, "job_completion"], ["2x8", true, "mechanic"], []]'::jsonb,
  'el driver queda sin confirmar y la transmisión no se toca: 8 piñones en una 2x8 calzan');

-- Reintento: la misma llave, entregar y guardar.
insert into results select 'uno_replay', pg_temp.finish('051');
insert into results select 'uno_entregado', pg_temp.finish('051', 'ENTREGADO');
insert into results
select 'uno_sync', public.sync_job_installed_bike_facts_v1(
  'e2820000-0000-4000-8000-000000000051');
select is(
  jsonb_build_array(
    (select (result->>'replay')::boolean from results where label = 'uno_replay'),
    (select result->'installed_bike_facts'->'applied' from results where label = 'uno_entregado'),
    (select result->'applied' from results where label = 'uno_sync'),
    (select count(*) from public.bike_technical_fact_patches
      where job_id = 'e2820000-0000-4000-8000-000000000051')),
  '[true, [], [], 1]'::jsonb,
  'la misma llave devuelve lo mismo; entregar y guardar no escriben; un solo recibo');

-- Conflicto: una llamada directa con lo que ya no dice la ficha. La línea se
-- siembra sin disparadores para que no se aplique sola.
set local session_replication_role = replica;
insert into public.mechanic_job_items (
  id, tenant_id, job_id, product_id, product_name, item_type, location_key,
  quantity, unit_price, service_configuration_data
) values
  ('e2820000-0000-4000-8000-000000000179', 'e2820000-0000-4000-8000-000000000001',
   'e2820000-0000-4000-8000-000000000051', 'e2820000-0000-4000-8000-000000000102',
   'PIÑON CASSETTE HG 8V 12-32T SUNRACE MOD.CSM400 8BU 8BU', 'product', 'rear', 1, 19990,
   '{"part_change": {"key": "freehubType", "value": "shimano_hg"}}');
set local session_replication_role = origin;
select throws_ok(
  $$select public.patch_bike_technical_facts_v1(
    'job_completion:e2820000-0000-4000-8000-000000000179:1:freehubType=shimano_hg',
    'e2820000-0000-4000-8000-000000000031',
    'e2820000-0000-4000-8000-000000000051',
    'job_completion',
    '[{"key": "freehubType", "op": "declare", "value": "shimano_hg", "expected": null, "expected_confirmed": false}]'::jsonb)$$,
  'PT409',
  'Bicycle facts changed since they were loaded; reload before saving',
  'con lo que ya no dice la ficha, el parche choca y no escribe');
select throws_ok(
  $$select public.patch_bike_technical_facts_v1(
    'job_completion:e2820000-0000-4000-8000-000000000179:1:freehubType=shimano_hg',
    'e2820000-0000-4000-8000-000000000031',
    'e2820000-0000-4000-8000-000000000051',
    'job_completion',
    '[{"key": "freehubType", "op": "set", "value": "shimano_hg", "expected": "shimano_hg", "expected_confirmed": false}]'::jsonb)$$,
  'P0001',
  'The job line did not install freehubType',
  'y lo declarado por la ficha técnica no se confirma por el parche');
delete from public.mechanic_job_items where id = 'e2820000-0000-4000-8000-000000000179';

-- ============================================================================
-- Lo mismo, y lo que calza sin ser lo mismo: la ficha no cambia
-- ============================================================================

insert into results select 'dos', pg_temp.finish('052');
insert into results select 'tres', pg_temp.finish('053');
select is(
  jsonb_build_array(
    pg_temp.fact('32', 'freehubType'),
    pg_temp.problems('dos'),
    pg_temp.fact('33', 'freehubType'),
    pg_temp.problems('tres'),
    (select jsonb_agg(p.applied order by p.operation_key)
       from public.bike_technical_fact_patches p
      where p.job_id in ('e2820000-0000-4000-8000-000000000052',
                         'e2820000-0000-4000-8000-000000000053'))),
  '[["shimano_hg", true, "mechanic"], [],
    ["shimano_hg_road_11", true, "mechanic"], [],
    [[], []]]'::jsonb,
  'un CS-HG200-7 en la Marlin 5 HG no le quita la confirmación; un HG200 9v calza en el núcleo HG Road 11 de la Addy y la ficha no cambia');

-- ============================================================================
-- No calza: incompatible
-- ============================================================================

insert into results select 'cuatro', pg_temp.blocked_finish('054');
insert into results select 'cinco', pg_temp.blocked_finish('055');
select is(
  jsonb_build_array(pg_temp.problems('cuatro'), pg_temp.problems('cinco'),
                    pg_temp.fact('34', 'freehubType'), pg_temp.fact('35', 'freehubType')),
  '[[{"key": "freehubType", "value": "threaded_freewheel", "reason": "incompatible",
      "requires_key": "freehubType", "requires_value": "shimano_hg"}],
    [{"key": "freehubType", "value": "microspline", "reason": "incompatible",
      "requires_key": "freehubType", "requires_value": "shimano_hg"}],
    ["shimano_hg", true, "mechanic"], ["shimano_hg", true, "mechanic"]]'::jsonb,
  'un piñón de rosca en un núcleo HG y un cassette Micro Spline en un núcleo HG no calzan, y la ficha no cambia');
select is(
  (select count(*)::integer from public.mechanic_job_status_transition_events
    where operation_key in ('pin-054-FINALIZADO', 'pin-055-FINALIZADO')),
  0,
  'las dos incompatibilidades deshacen estado, aviso y recibo de cierre');
-- Una versión antigua pudo dejar esa línea en un trabajo ya finalizado. La
-- puerta de edición y el parche directo siguen protegiendo ese caso.
set local session_replication_role = replica;
update public.mechanic_jobs
   set status = 'FINALIZADO',
       status_id = (select id from status_ids where code = 'FINALIZADO')
 where id = 'e2820000-0000-4000-8000-000000000054';
set local session_replication_role = origin;
select throws_ok(
  $$select public.patch_bike_technical_facts_v1(
    'job_completion:e2820000-0000-4000-8000-000000000164:1:freehubType=threaded_freewheel',
    'e2820000-0000-4000-8000-000000000034',
    'e2820000-0000-4000-8000-000000000054',
    'job_completion',
    '[{"key": "freehubType", "op": "declare", "value": "threaded_freewheel", "expected": "shimano_hg", "expected_confirmed": true}]'::jsonb)$$,
  '23514',
  'Installed part freehubType does not fit the bicycle (freehubType is shimano_hg)',
  'ni por una llamada directa al parche');
-- La puerta: en un trabajo terminado, la línea y la ficha se guardan juntas.
select throws_like(
  $$update public.mechanic_job_items
       set product_id = 'e2820000-0000-4000-8000-000000000108',
           product_name = 'PIÑON ATORNILLADO 7 VELOCIDADES FALCON MOD.FW71'
     where id = 'e2820000-0000-4000-8000-000000000164'$$,
  '%FW71» no se guardó: Rueda libre roscada en el driver trasero no calza con la ficha de la bici (el driver trasero es «Shimano HG»)%',
  'otro piñón de rosca en el trabajo terminado tampoco se guarda');

-- Los piñones: un piñón de rosca de 7 en una 1x6, un cassette de 9 en una
-- 3x8 cuyo trabajo sólo cambió el mando delantero.
insert into results select 'diez', pg_temp.blocked_finish('060');
insert into results select 'nueve', pg_temp.blocked_finish('059');
select is(
  jsonb_build_array(pg_temp.problems('diez'), pg_temp.problems('nueve'),
                    pg_temp.fact('40', 'drivetrainConfig'), pg_temp.fact('39', 'drivetrainConfig')),
  '[[{"key": "freehubType", "value": "threaded_freewheel", "reason": "incompatible",
      "requires_key": "drivetrainConfig", "requires_value": "1x6"}],
    [{"key": "freehubType", "value": "shimano_hg", "reason": "incompatible",
      "requires_key": "drivetrainConfig", "requires_value": "3x8"}],
    ["1x6", true, "mechanic"], ["3x8", true, "mechanic"]]'::jsonb,
  'la cuenta de piñones no calza con la transmisión: incompatible, y la transmisión no se escribe');
select is(
  (select count(*)::integer from public.bike_events
    where bike_id = 'e2820000-0000-4000-8000-000000000039'
      and event_type = 'installed_fact_incompatible'),
  0,
  'el rechazo del cassette no anota una instalación que no sucedió');

-- Una maza montada adelante no decide el driver trasero, aunque venga en
-- juego.
insert into results select 'siete', pg_temp.blocked_finish('057');
select is(
  pg_temp.problems('siete'),
  '[{"key": "freehubType", "value": "shimano_hg", "reason": "incompatible",
     "requires_key": "freehubType", "requires_value": "threaded_freewheel"}]'::jsonb,
  'con una maza montada adelante en el trabajo, el cassette en la maza de rosca sigue incompatible');

-- Un driver sin fuente no es de ninguna línea: no se corrige solo.
insert into results select 'ozark', pg_temp.blocked_finish('066');
select is(
  jsonb_build_array(pg_temp.problems('ozark'), pg_temp.fact('44', 'freehubType')),
  '[[{"key": "freehubType", "value": "threaded_freewheel", "reason": "incompatible",
      "requires_key": "freehubType", "requires_value": "shimano_hg"}],
    ["shimano_hg", null, null]]'::jsonb,
  'la Ozark dice Shimano HG sin fuente: el FW71 no calza y la ficha no cambia');

-- Calzar con el driver no salva los piñones: un HG200 9v en el núcleo HG
-- Road 11 de una 2x8.
insert into results select 'roubaix', pg_temp.blocked_finish('068');
select is(
  jsonb_build_array(pg_temp.problems('roubaix'), pg_temp.fact('46', 'freehubType')),
  '[[{"key": "freehubType", "value": "shimano_hg", "reason": "incompatible",
      "requires_key": "drivetrainConfig", "requires_value": "2x8"}],
    ["shimano_hg_road_11", true, "mechanic"]]'::jsonb,
  'el HG200 9v calza en el núcleo de la Roubaix, pero no con sus 8 piñones');
set local session_replication_role = replica;
update public.mechanic_jobs
   set status = 'FINALIZADO',
       status_id = (select id from status_ids where code = 'FINALIZADO')
 where id = 'e2820000-0000-4000-8000-000000000068';
set local session_replication_role = origin;
select throws_ok(
  $$select public.patch_bike_technical_facts_v1(
    'job_completion:e2820000-0000-4000-8000-000000000196:1:freehubType=shimano_hg',
    'e2820000-0000-4000-8000-000000000046',
    'e2820000-0000-4000-8000-000000000068',
    'job_completion',
    '[{"key": "freehubType", "op": "declare", "value": "shimano_hg", "expected": "shimano_hg_road_11", "expected_confirmed": true}]'::jsonb)$$,
  '23514',
  'Installed part freehubType does not fit the bicycle (drivetrainConfig is 2x8)',
  'ni por una llamada directa al parche');

-- Una maza sin posición ni rueda no es la trasera: no deja pendiente.
insert into results select 'jade', pg_temp.blocked_finish('067');
select is(
  pg_temp.problems('jade'),
  '[{"key": "freehubType", "value": "shimano_hg", "reason": "incompatible",
     "requires_key": "freehubType", "requires_value": "threaded_freewheel"}]'::jsonb,
  'la Maza Neco sin posición ni rueda no decide el driver trasero de la Jade');
-- Elegida la rueda trasera en su línea, sí: guardar el trabajo lo deja
-- pendiente.
update public.mechanic_job_items
   set location_key = 'rear'
 where id = 'e2820000-0000-4000-8000-000000000198';
insert into results select 'jade_terminado', pg_temp.finish('067');
insert into results
select 'jade_sync', public.sync_job_installed_bike_facts_v1(
  'e2820000-0000-4000-8000-000000000067');
select is(
  jsonb_build_array(pg_temp.problems('jade_sync'), pg_temp.fact('45', 'freehubType')),
  '[[{"key": "freehubType", "value": "shimano_hg", "reason": "pending", "pending": "hub_change",
      "requires_key": "freehubType", "requires_value": "threaded_freewheel"}],
    ["threaded_freewheel", true, "mechanic"]]'::jsonb,
  'con la maza en la rueda trasera, el cassette queda pendiente');

-- ============================================================================
-- Pendiente: el mismo trabajo cambia la pieza que lo decide
-- ============================================================================

insert into results select 'seis', pg_temp.finish('056');
insert into results select 'ocho', pg_temp.finish('058');
select is(
  jsonb_build_array(
    pg_temp.problems('seis'),
    pg_temp.problems('ocho'),
    pg_temp.fact('36', 'freehubType'),
    pg_temp.fact('38', 'drivetrainConfig'),
    (select count(*) from public.bike_technical_fact_patches
      where job_id in ('e2820000-0000-4000-8000-000000000056',
                       'e2820000-0000-4000-8000-000000000058'))),
  '[[{"key": "freehubType", "value": "shimano_hg", "reason": "pending", "pending": "hub_change",
      "requires_key": "freehubType", "requires_value": "threaded_freewheel"}],
    [{"key": "freehubType", "value": "shimano_hg", "reason": "pending", "pending": "shifter_change",
      "requires_key": "drivetrainConfig", "requires_value": "3x8"}],
    ["threaded_freewheel", true, "mechanic"], ["3x8", true, "mechanic"], 0]'::jsonb,
  'con una maza trasera o un mando trasero nuevos en el trabajo, lo que no calza queda pendiente y nada se escribe');
select ok(
  (select summary like '%CS-HG200-7%Shimano HG en el driver trasero%el driver trasero es «Rueda libre roscada»%el trabajo también cambia la maza trasera%guarda el trabajo%'
     from public.bike_events
    where bike_id = 'e2820000-0000-4000-8000-000000000036'
      and event_type = 'installed_fact_needs_decision'),
  'la historia de la RAM Rebel dice qué decidir');
select throws_ok(
  $$select public.patch_bike_technical_facts_v1(
    'job_completion:e2820000-0000-4000-8000-000000000166:1:freehubType=shimano_hg',
    'e2820000-0000-4000-8000-000000000036',
    'e2820000-0000-4000-8000-000000000056',
    'job_completion',
    '[{"key": "freehubType", "op": "declare", "value": "shimano_hg", "expected": "threaded_freewheel", "expected_confirmed": true}]'::jsonb)$$,
  '23514',
  'Installed part freehubType waits for a decision (freehubType is threaded_freewheel)',
  'una llamada directa no escribe lo pendiente');
-- Pendiente no es un error: la línea se sigue guardando en el trabajo
-- terminado.
select lives_ok(
  $$update public.mechanic_job_items
       set service_configuration_data = service_configuration_data || '{"obs": "revisado"}'
     where id = 'e2820000-0000-4000-8000-000000000166'$$,
  'la línea pendiente se guarda');

-- El mecánico mira la maza nueva y elige su núcleo: Shimano HG. Guardar el
-- trabajo después no escribe nada más y no queda nada pendiente.
update public.bike_profiles
   set technical_profile = technical_profile
         || jsonb_build_object(
              'values', technical_profile->'values' || '{"freehubType": "shimano_hg"}',
              'sources', technical_profile->'sources' || '{"freehubType": "mechanic"}',
              'confirmed', technical_profile->'confirmed' || '{"freehubType": true}')
 where bike_id = 'e2820000-0000-4000-8000-000000000036';
insert into results
select 'seis_sync', public.sync_job_installed_bike_facts_v1(
  'e2820000-0000-4000-8000-000000000056');
select is(
  jsonb_build_array(
    pg_temp.problems('seis_sync'),
    (select jsonb_path_query_array(result, '$.applied[*].changed') from results where label = 'seis_sync'),
    pg_temp.fact('36', 'freehubType')),
  '[[], [false], ["shimano_hg", true, "mechanic"]]'::jsonb,
  'decidido en la ficha, el cassette calza y la confirmación del mecánico se queda');

-- ============================================================================
-- Rueda libre sin ficha y driver «desconocido»: se llenan
-- ============================================================================

insert into results select 'once', pg_temp.finish('061');
insert into results select 'doce', pg_temp.finish('062');
select is(
  jsonb_build_array(
    pg_temp.fact('41', 'freehubType'), pg_temp.fact('41', 'drivetrainConfig'),
    pg_temp.fact('42', 'freehubType'),
    (select result->'installed_bike_facts'->'applied'->0->'previous' from results where label = 'doce'),
    pg_temp.problems('once'), pg_temp.problems('doce')),
  '[["threaded_freewheel", null, "job_completion"], [null, null, null],
    ["shimano_hg", null, "job_completion"], "unknown", [], []]'::jsonb,
  'la Radost sin ficha toma rueda libre roscada del FW71 (sin transmisión no se refuta); «desconocido» en la Kona no refuta y se llena');

-- La línea de la Radost resulta ser un HG200 9v: lo que escribió ella misma
-- se corrige, con la llave siguiente.
update public.mechanic_job_items
   set product_id = 'e2820000-0000-4000-8000-000000000103',
       product_name = 'CASSETTE SHIMANO 9V. (11-32) HG200 AE',
       service_configuration_data = '{"part_change": {"key": "freehubType", "value": "shimano_hg"}}'
 where id = 'e2820000-0000-4000-8000-000000000175';
select is(
  jsonb_build_array(
    pg_temp.fact('41', 'freehubType'),
    (select jsonb_agg(operation_key order by operation_key)
       from public.bike_technical_fact_patches
      where operation_key like 'job_completion:e2820000-0000-4000-8000-000000000175:%'),
    public.job_part_change_writers_v1('e2820000-0000-4000-8000-000000000061')),
  '[["shimano_hg", null, "job_completion"],
    ["job_completion:e2820000-0000-4000-8000-000000000175:1:freehubType=threaded_freewheel",
     "job_completion:e2820000-0000-4000-8000-000000000175:2:freehubType=shimano_hg"],
    {"e2820000-0000-4000-8000-000000000175": {"key": "freehubType", "value": "shimano_hg"}}]'::jsonb,
  'la línea que escribió el driver lo corrige, con la llave siguiente');

-- Lo que el mecánico vuelve a elegir en la ficha ya es suyo, aunque sea el
-- mismo código: la línea no lo vuelve a cambiar.
update public.bike_profiles
   set technical_profile = technical_profile
         || jsonb_build_object(
              'sources', technical_profile->'sources' || '{"freehubType": "mechanic"}',
              'confirmed', coalesce(technical_profile->'confirmed', '{}') || '{"freehubType": true}')
 where bike_id = 'e2820000-0000-4000-8000-000000000041';
select throws_like(
  $$update public.mechanic_job_items
       set product_id = 'e2820000-0000-4000-8000-000000000108',
           product_name = 'PIÑON ATORNILLADO 7 VELOCIDADES FALCON MOD.FW71',
           service_configuration_data = '{"part_change": {"key": "freehubType", "value": "threaded_freewheel"}}'
     where id = 'e2820000-0000-4000-8000-000000000175'$$,
  '%FW71» no se guardó: Rueda libre roscada en el driver trasero no calza%el driver trasero es «Shimano HG»%',
  'lo que el mecánico confirmó no lo pisa la línea que antes lo escribió');

-- Sin fuente (una ficha guardada por un camino que la perdió) tampoco es de
-- la línea, aunque su recibo sea el último.
update public.bike_profiles
   set technical_profile = jsonb_set(technical_profile, '{sources}',
         (technical_profile->'sources') - 'freehubType')
       #- '{confirmed,freehubType}'
 where bike_id = 'e2820000-0000-4000-8000-000000000041';
select throws_like(
  $$update public.mechanic_job_items
       set product_id = 'e2820000-0000-4000-8000-000000000108',
           product_name = 'PIÑON ATORNILLADO 7 VELOCIDADES FALCON MOD.FW71',
           service_configuration_data = '{"part_change": {"key": "freehubType", "value": "threaded_freewheel"}}'
     where id = 'e2820000-0000-4000-8000-000000000175'$$,
  '%FW71» no se guardó: Rueda libre roscada en el driver trasero no calza%el driver trasero es «Shimano HG»%',
  'un driver sin fuente no es de la línea, aunque ella lo haya escrito');

-- ============================================================================
-- Dos líneas en la misma bici: sólo es suyo lo que de verdad escribió
-- ============================================================================

insert into results select 'j7', pg_temp.finish('063');
insert into results select 'j8', pg_temp.finish('064');
select is(
  jsonb_build_array(
    pg_temp.fact('43', 'freehubType'),
    (select jsonb_agg(p.applied order by p.operation_key)
       from public.bike_technical_fact_patches p
      where p.bike_id = 'e2820000-0000-4000-8000-000000000043'),
    public.job_part_change_writers_v1('e2820000-0000-4000-8000-000000000063'),
    public.job_part_change_writers_v1('e2820000-0000-4000-8000-000000000064')),
  '[["shimano_hg", null, "job_completion"],
    [[{"op": "declare", "to": "shimano_hg", "key": "freehubType", "from": null}], []],
    {}, {}]'::jsonb,
  'la segunda línea con el mismo driver no escribe nada, y ninguna de las dos puede corregirlo: la primera lo escribió, la segunda lo instaló después');

-- La del trabajo 8 pasa a un Micro Spline con su marca: el HG no es suyo.
select throws_like(
  $$update public.mechanic_job_items
       set product_id = 'e2820000-0000-4000-8000-000000000104',
           product_name = 'Cassette 12v Shimano SLX CS-M7100 10-51T Microspline',
           service_configuration_data = '{"part_change": {"key": "freehubType", "value": "microspline"}}'
     where id = 'e2820000-0000-4000-8000-000000000178'$$,
  '%Microspline» no se guardó: Micro Spline en el driver trasero no calza con la ficha de la bici (el driver trasero es «Shimano HG»)%',
  'una línea no se apropia del driver que escribió otra');
-- Tampoco la del trabajo 7, que lo escribió: el trabajo 8 instaló después un
-- cassette que dice ese driver, y corregirlo contradiría esa instalación
-- (revisión de Codex, 2026-09-28).
select throws_like(
  $$update public.mechanic_job_items
       set product_id = 'e2820000-0000-4000-8000-000000000104',
           product_name = 'Cassette 12v Shimano SLX CS-M7100 10-51T Microspline',
           service_configuration_data = '{"part_change": {"key": "freehubType", "value": "microspline"}}'
     where id = 'e2820000-0000-4000-8000-000000000177'$$,
  '%Microspline» no se guardó: Micro Spline en el driver trasero no calza con la ficha de la bici (el driver trasero es «Shimano HG»)%',
  'una instalación posterior del mismo driver quita la corrección a la primera línea');
select is(
  jsonb_build_array(
    pg_temp.fact('43', 'freehubType'),
    (select count(*) from public.bike_technical_fact_patches
      where bike_id = 'e2820000-0000-4000-8000-000000000043'),
    pg_temp.problems('j8')),
  '[["shimano_hg", null, "job_completion"], 2, []]'::jsonb,
  'la Scott sigue con el HG que instalaron los dos, sin recibo nuevo');

-- ============================================================================
-- General con dos bicis: la línea no es de ninguna
-- ============================================================================

-- Con una sola bici, una línea de General es de esa bici (todas las líneas de
-- arriba lo son). Con dos, no: al terminar no se escribe nada y se informa.
insert into results select 'dos_bicis', pg_temp.blocked_finish('069');
select is(
  jsonb_build_array(
    pg_temp.problems('dos_bicis'),
    (select count(*) from public.bike_technical_fact_patches
      where job_id = 'e2820000-0000-4000-8000-000000000069'),
    (select count(*) from public.bike_profiles
      where bike_id in ('e2820000-0000-4000-8000-000000000047',
                        'e2820000-0000-4000-8000-000000000048'))),
  '[[{"key": "freehubType", "value": "shimano_hg", "reason": "line_without_bike"}], 0, 0]'::jsonb,
  'un cassette en General de un trabajo con dos bicis bloquea el cierre sin escribir ficha');
-- Simula un trabajo histórico finalizado antes de la puerta nueva para
-- comprobar que editar la misma línea tampoco elude la atribución.
set local session_replication_role = replica;
update public.mechanic_jobs
   set status = 'FINALIZADO',
       status_id = (select id from status_ids where code = 'FINALIZADO')
 where id = 'e2820000-0000-4000-8000-000000000069';
set local session_replication_role = origin;
-- La puerta: en el trabajo terminado esa línea no se guarda así.
select throws_like(
  $$update public.mechanic_job_items
       set service_configuration_data = service_configuration_data || '{"obs": "revisado"}'
     where id = 'e2820000-0000-4000-8000-000000000199'$$,
  '%CS-HG200-7 12/32T» no se guardó: no dice de qué bici del trabajo es. Asígnala a su bici («Asignar a…» en el menú de la línea) y guarda.%',
  'en un trabajo terminado, la línea sin bici no se guarda, y dice cómo resolverlo');
-- Asignada a la Oxford Rally, escribe en ella y en nadie más, una vez.
update public.mechanic_job_items
   set job_bike_id = (select jb.id from public.mechanic_job_bikes jb
                       where jb.job_id = 'e2820000-0000-4000-8000-000000000069'
                         and jb.bike_id = 'e2820000-0000-4000-8000-000000000047')
 where id = 'e2820000-0000-4000-8000-000000000199';
insert into results
select 'dos_bicis_sync', public.sync_job_installed_bike_facts_v1(
  'e2820000-0000-4000-8000-000000000069');
select is(
  jsonb_build_array(
    pg_temp.fact('47', 'freehubType'),
    (select count(*) from public.bike_profiles
      where bike_id = 'e2820000-0000-4000-8000-000000000048'),
    (select jsonb_agg(operation_key) from public.bike_technical_fact_patches
      where job_id = 'e2820000-0000-4000-8000-000000000069'),
    (select result->'applied' from results where label = 'dos_bicis_sync'),
    pg_temp.problems('dos_bicis_sync')),
  '[["shimano_hg", null, "job_completion"], 0,
    ["job_completion:e2820000-0000-4000-8000-000000000199:1:freehubType=shimano_hg"],
    [], []]'::jsonb,
  'asignada a la Oxford Rally, la línea la anota al guardarse, con un solo recibo, y guardar después no escribe otra vez');

-- ============================================================================
-- «Asignar a <bici>»: la misma línea pasa a su bici por el comando de guardado
-- ============================================================================

-- Lo que el formulario vio y lo que manda de una línea (`jobLineFromPart`).
create or replace function pg_temp.seen(p_job text) returns jsonb language sql as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', id, 'updated_at', updated_at) order by id), '[]'::jsonb)
    from public.mechanic_job_items
   where job_id = ('e2820000-0000-4000-8000-000000000' || p_job)::uuid
$$;
create or replace function pg_temp.job_bike(p_job text, p_bike text) returns uuid language sql as $$
  select jb.id from public.mechanic_job_bikes jb
   where jb.job_id = ('e2820000-0000-4000-8000-000000000' || p_job)::uuid
     and jb.bike_id = ('e2820000-0000-4000-8000-0000000000' || p_bike)::uuid
$$;
create or replace function pg_temp.sent(p_line text, p_job_bike uuid, p_config jsonb)
returns jsonb language sql as $$
  select jsonb_build_object(
           'client_key', i.id, 'id', i.id, 'job_bike_id', p_job_bike,
           'product_id', i.product_id, 'product_name', i.product_name,
           'product_sku', i.product_sku, 'quantity', i.quantity,
           'unit_price', i.unit_price, 'notes', i.notes,
           'service_configuration_data', p_config, 'item_type', i.item_type,
           'location_key', i.location_key,
           'creates_lifecycle', i.creates_lifecycle)
    from public.mechanic_job_items i
   where i.id = pg_temp.line(p_line)
$$;
create or replace function pg_temp.commercial(p_job text) returns jsonb language sql as $$
  select jsonb_agg(jsonb_build_object(
           'id', i.id, 'job_bike_id', i.job_bike_id, 'product_id', i.product_id,
           'name', i.product_name, 'quantity', i.quantity,
           'unit_price', i.unit_price, 'notes', i.notes,
           'configuration', i.service_configuration_data) order by i.id)
    from public.mechanic_job_items i
   where i.job_id = ('e2820000-0000-4000-8000-000000000' || p_job)::uuid
$$;
create or replace function pg_temp.save_error(
  p_key text, p_job text, p_seen jsonb, p_lines jsonb
) returns jsonb language plpgsql as $$
declare
  v_state text;
  v_detail text;
  v_hint text;
begin
  perform public.save_mechanic_job_lines_v1(
    p_key, ('e2820000-0000-4000-8000-000000000' || p_job)::uuid,
    p_seen, p_lines, '[]'::jsonb);
  return null;
exception when others then
  get stacked diagnostics
    v_state = returned_sqlstate,
    v_detail = pg_exception_detail,
    v_hint = pg_exception_hint;
  return jsonb_build_object('state', v_state, 'hint', v_hint, 'detail', v_detail);
end;
$$;

update public.mechanic_job_items
   set notes = 'Cambio de cassette, cadena revisada'
 where id = pg_temp.line('200');
create temporary table assign_before as
select pg_temp.commercial('070') as row;

-- Trabajo 070, abierto: el cassette de General se asigna a la Bianchi. Va con
-- su id y lo que vio el formulario, y sin la marca que había visto sin bici.
insert into results
select 'asignar', public.save_mechanic_job_lines_v1(
  'pin-asignar-070',
  'e2820000-0000-4000-8000-000000000070',
  pg_temp.seen('070'),
  jsonb_build_array(pg_temp.sent('200', pg_temp.job_bike('070', '49'), null)),
  '[]'::jsonb);
select is(
  jsonb_build_array(
    (select jsonb_build_object('updated', result->'updated', 'inserted', result->'inserted')
       from results where label = 'asignar'),
    pg_temp.commercial('070')),
  jsonb_build_array(
    '{"updated": 1, "inserted": 0}'::jsonb,
    (select jsonb_agg(line
                        || jsonb_build_object('job_bike_id', pg_temp.job_bike('070', '49'),
                                              'configuration', null))
       from assign_before, jsonb_array_elements(row) line)),
  'la misma línea (id, producto, cantidad, precio y descripción) queda en la Bianchi, sola y sin la marca de antes');

-- Terminar sin volver a confirmar no escribe nada ni se queja.
insert into results select 'asignada_terminada', pg_temp.finish('070');
select is(
  jsonb_build_array(
    pg_temp.problems('asignada_terminada'),
    (select count(*) from public.bike_technical_fact_patches
      where job_id = 'e2820000-0000-4000-8000-000000000070')),
  '[[], 0]'::jsonb,
  'sin reconfirmar, terminar no cambia ninguna ficha ni informa una línea sin bici');

-- Reconfirmada en su bici (el chip deja la marca), se guarda y la anota una
-- vez, en la Bianchi y en nadie más.
insert into results
select 'reconfirmar', public.save_mechanic_job_lines_v1(
  'pin-reconfirmar-070',
  'e2820000-0000-4000-8000-000000000070',
  pg_temp.seen('070'),
  jsonb_build_array(pg_temp.sent('200', pg_temp.job_bike('070', '49'),
    '{"part_change": {"key": "freehubType", "value": "shimano_hg"}}')),
  '[]'::jsonb);
select is(
  jsonb_build_array(
    pg_temp.fact('49', 'freehubType'),
    (select count(*) from public.bike_profiles
      where bike_id = 'e2820000-0000-4000-8000-000000000050'),
    (select jsonb_agg(operation_key) from public.bike_technical_fact_patches
      where job_id = 'e2820000-0000-4000-8000-000000000070'),
    (select count(*) from public.mechanic_job_items
      where job_id = 'e2820000-0000-4000-8000-000000000070')),
  '[["shimano_hg", null, "job_completion"], 0,
    ["job_completion:e2820000-0000-4000-8000-000000000200:1:freehubType=shimano_hg"], 1]'::jsonb,
  'reconfirmada, la línea anota el driver en la Bianchi con un solo recibo, y sigue siendo una');

-- Trabajo 071, con su factura confirmada: pasar la línea cambiaría lo que ya
-- se cobró por bici, y el comando la rechaza sin escribir.
insert into public.sales_invoices (
  id, tenant_id, invoice_number, customer_id, customer_name, source, status,
  subtotal, net_amount, iva_amount, total, paid_amount, balance,
  tax_treatment, items
) values (
  'e2820000-0000-4000-8000-000000000084',
  'e2820000-0000-4000-8000-000000000001', 'FV-PIN-CONFIRMADA',
  'e2820000-0000-4000-8000-000000000010', 'Cliente transmisiones', 'manual_sale',
  'confirmed', 19990, 19990, 0, 19990, 0, 19990, 'no_tax', '[]'::jsonb);
update public.mechanic_jobs
   set invoice_id = 'e2820000-0000-4000-8000-000000000084'
 where id = 'e2820000-0000-4000-8000-000000000071';
create temporary table posted_before as
select pg_temp.commercial('071') as row;
select is(
  (select jsonb_build_object('state', e->>'state', 'hint', e->>'hint',
            'detail', nullif(e->>'detail', '')::jsonb)
     from pg_temp.save_error('pin-asignar-071', '071', pg_temp.seen('071'),
       jsonb_build_array(pg_temp.sent('201', pg_temp.job_bike('071', '49'), null))) e),
  '{"state": "55000", "hint": "invoice_posted", "detail": ["línea: Cassette Shimano 7V CS-HG200-7 12/32T"]}'::jsonb,
  'con la factura confirmada, asignar la línea a una bici se rechaza');
-- Aunque sólo cambie la bici (la misma configuración): también es cambiar lo
-- cobrado. Lo rechaza el comando, que nombra la línea; el disparador de las
-- líneas (guard_paid_workshop_child_mutation) lo rechazaría igual, pero sin
-- decir cuál.
select is(
  (select jsonb_build_object('state', e->>'state', 'hint', e->>'hint',
            'detail', nullif(e->>'detail', '')::jsonb)
     from pg_temp.save_error('pin-asignar-071-sola', '071', pg_temp.seen('071'),
       jsonb_build_array(pg_temp.sent('201', pg_temp.job_bike('071', '49'),
         (select service_configuration_data from public.mechanic_job_items
           where id = pg_temp.line('201'))))) e),
  '{"state": "55000", "hint": "invoice_posted", "detail": ["línea: Cassette Shimano 7V CS-HG200-7 12/32T"]}'::jsonb,
  'también si sólo cambia la bici de la línea, y el comando dice cuál');
-- Control: la misma línea tal como está pasa (no hay otra diferencia que la
-- bici en el caso de arriba).
select is(
  pg_temp.save_error('pin-asignar-071-igual', '071', pg_temp.seen('071'),
    jsonb_build_array(pg_temp.sent('201', null,
      (select service_configuration_data from public.mechanic_job_items
        where id = pg_temp.line('201'))))),
  null,
  'la misma línea sin cambios no choca con la factura confirmada');
select is(
  pg_temp.commercial('071'),
  (select row from posted_before),
  'y la línea queda en General, con su marca, como estaba');

-- Trabajo 072: se agrega la Orion en el formulario y en el mismo guardado el
-- cassette de General pasa a ella, que todavía no tiene id: la línea la nombra
-- por su llave, como una línea nueva, pero va por su id y se actualiza.
create temporary table new_bike_before as
select pg_temp.commercial('072') as row;
insert into results
select 'asignar_nueva', public.save_mechanic_job_lines_v1(
  'pin-asignar-072',
  'e2820000-0000-4000-8000-000000000072',
  pg_temp.seen('072'),
  jsonb_build_array((pg_temp.sent('202', null, null) - 'job_bike_id')
    || jsonb_build_object('job_bike_key', 'orion')),
  '[]'::jsonb,
  null,
  jsonb_build_array(jsonb_build_object(
    'client_key', 'orion',
    'bike_id', 'e2820000-0000-4000-8000-000000000050')));
select is(
  jsonb_build_array(
    (select jsonb_build_object('updated', result->'updated',
              'inserted', result->'inserted',
              'job_bikes_inserted', result->'job_bikes_inserted')
       from results where label = 'asignar_nueva'),
    pg_temp.commercial('072')),
  jsonb_build_array(
    '{"updated": 1, "inserted": 0, "job_bikes_inserted": 1}'::jsonb,
    (select jsonb_agg(line
                        || jsonb_build_object('job_bike_id', pg_temp.job_bike('072', '50'),
                                              'configuration', null))
       from new_bike_before, jsonb_array_elements(row) line)),
  'a una bici recién agregada también pasa la misma línea, sin marca, y el trabajo sigue con una');

-- ============================================================================
-- Línea borrada después de terminar
-- ============================================================================

delete from public.mechanic_job_items
 where id = 'e2820000-0000-4000-8000-000000000161';
select is(
  pg_temp.fact('31', 'freehubType'),
  '["shimano_hg", null, "job_completion"]'::jsonb,
  'borrar la línea no deshace la ficha');
select ok(
  (select summary like '%Shimano HG en el driver trasero%una línea que ya no está%antes no tenía el dato%Si esa pieza no se instaló%'
     from public.bike_events
    where bike_id = 'e2820000-0000-4000-8000-000000000031'
      and event_type = 'installed_fact_unsupported'),
  'y la historia de la Giant lo dice');

-- ============================================================================
-- El parche: la transmisión no la escribe un trabajo, y su total
-- ============================================================================

select throws_ok(
  $$select public.patch_bike_technical_facts_v1(
    'job_completion:e2820000-0000-4000-8000-000000000162:1:drivetrainConfig=1x7',
    'e2820000-0000-4000-8000-000000000032',
    'e2820000-0000-4000-8000-000000000052',
    'job_completion',
    '[{"key": "drivetrainConfig", "op": "declare", "value": "1x7", "expected": "3x7", "expected_confirmed": true}]'::jsonb)$$,
  'P0001',
  'Bicycle fact drivetrainConfig is not installed by a job',
  'una fila que sólo revisa no deja al trabajo escribir la transmisión');
-- El total es platos × piñones: 24 en una 2x8 no se escribe; 3x8 y 24 sí.
select throws_ok(
  $$select public.patch_bike_technical_facts_v1(
    'pin-total-24-en-2x8',
    'e2820000-0000-4000-8000-000000000031',
    'e2820000-0000-4000-8000-000000000051',
    'service_wizard',
    '[{"key": "drivetrainSpeeds", "op": "set", "value": 24, "expected": 16, "expected_confirmed": true}]'::jsonb)$$,
  'P0001',
  'Bicycle drivetrain speeds 24 do not match its configuration 2x8',
  'un total que no es platos × piñones no se escribe');
select lives_ok(
  $$select public.patch_bike_technical_facts_v1(
    'pin-total-24',
    'e2820000-0000-4000-8000-000000000031',
    'e2820000-0000-4000-8000-000000000051',
    'service_wizard',
    '[{"key": "drivetrainConfig", "op": "set", "value": "3x8", "expected": "2x8", "expected_confirmed": true},
      {"key": "drivetrainSpeeds", "op": "set", "value": 24, "expected": 16, "expected_confirmed": true}]'::jsonb)$$,
  'el asistente escribe el total de una transmisión de tres platos (3 × 8 = 24)');
select throws_ok(
  $$select public.patch_bike_technical_facts_v1(
    'pin-total-43',
    'e2820000-0000-4000-8000-000000000031',
    'e2820000-0000-4000-8000-000000000051',
    'service_wizard',
    '[{"key": "drivetrainSpeeds", "op": "set", "value": 43, "expected": 24, "expected_confirmed": true}]'::jsonb)$$,
  'P0001',
  'Bicycle fact drivetrainSpeeds is out of its workshop range',
  'y el total tiene su techo: 3 × 14');
-- Por valor, no por cómo se escribe: 16.0 en una 3x8 tampoco.
select throws_ok(
  $$select public.patch_bike_technical_facts_v1(
    'pin-total-16-decimal',
    'e2820000-0000-4000-8000-000000000031',
    'e2820000-0000-4000-8000-000000000051',
    'service_wizard',
    '[{"key": "drivetrainSpeeds", "op": "set", "value": 16.0, "expected": 24, "expected_confirmed": true}]'::jsonb)$$,
  'P0001',
  'Bicycle drivetrain speeds 16.0 do not match its configuration 3x8',
  'un total con decimales se compara por valor');
select is(
  jsonb_build_array(pg_temp.fact('31', 'drivetrainConfig'), pg_temp.fact('31', 'drivetrainSpeeds')),
  '[["3x8", true, "mechanic"], [24, true, "mechanic"]]'::jsonb,
  'la Giant dice 3x8 y 24 velocidades en total, confirmadas por el mecánico en el asistente');

select * from finish();
rollback;
