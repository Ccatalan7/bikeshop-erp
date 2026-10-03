begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select no_plan();

-- Cambios de partes, la llanta (20260928140000). Una llanta cambia la rueda:
-- su BSD y sus perforaciones, una marca por dato y un recibo por línea. La
-- rueda que queda tiene que calzar: el Enrayado y otra llanta del trabajo en
-- esa rueda (la misma cuenta), la maza en que se raya (la del trabajo, o la
-- que queda según la ficha de antes del trabajo) y el neumático de esa rueda
-- (el del trabajo, o el que queda). El neumático se mide con la llanta del
-- trabajo antes que con la ficha. Guardar varias líneas en un trabajo
-- terminado es un solo cambio.
--
-- Datos reales (producción, lectura del 2026-09-28): llantas, mazas y
-- neumáticos por su nombre y lo que dice su ficha técnica (sólo 9 de 44
-- llantas dicen su BSD; ninguna su posición); PG-00389 (Oxford Orion 4:
-- llanta FOSS F22, maza Eclipse, neumático Kenda y Enrayado). Las fichas de
-- las bicis y los trabajos que no son de producción se dicen supuestos.
--
-- La base local no trae el motor de fichas: el lector del producto se
-- reemplaza en esta transacción por dos tablas.

-- ============================================================================
-- La relación y cómo se dice
-- ============================================================================

select is(
  (select jsonb_agg(jsonb_build_object(
            'spec', spec_key, 'position', position, 'key', bike_fact_key,
            'label', component_label, 'rule', on_mismatch,
            'range', jsonb_build_array(min_value, max_value),
            'condition', product_condition)
          order by bike_fact_key, position)
     from public.bike_fact_spec_links
    where template_key = 'rim'),
  '[{"key": "frontSpokeHoles", "spec": "spoke_hole_count", "label": "rueda delantera", "rule": "change", "range": [12, 48], "position": "front", "condition": null},
    {"key": "frontWheelBsdMm", "spec": "bead_seat_diameter_mm", "label": "rueda delantera", "rule": "change", "range": [150, 700], "position": "front", "condition": null},
    {"key": "rearSpokeHoles", "spec": "spoke_hole_count", "label": "rueda trasera", "rule": "change", "range": [12, 48], "position": "rear", "condition": null},
    {"key": "rearWheelBsdMm", "spec": "bead_seat_diameter_mm", "label": "rueda trasera", "rule": "change", "range": [150, 700], "position": "rear", "condition": null}]'::jsonb,
  'la llanta cambia el BSD y las perforaciones de la rueda que eligió el mecánico');
select is(
  (select count(*)::integer from public.bike_fact_spec_links
    where position in ('front', 'rear')), 19,
  'la relación tiene sus 19 filas de rueda: las 15 de antes y las 4 de la llanta');
select is(
  jsonb_build_array(
    public.bike_fact_requirement_text('rearHubSpokeHoles', '28'),
    public.bike_fact_requirement_text('frontHubSpokeHoles', '32 o 36'),
    public.bike_fact_requirement_text('rearBuildSpokeHoles', '36'),
    public.bike_fact_requirement_text('rearTireBsdMm', '584'),
    public.bike_fact_requirement_text('frontTireBsdMm', '622'),
    public.bike_fact_requirement_text('rearRimBsdMm', '622'),
    public.bike_fact_requirement_text('frontRimBsdMm', '584 o 622'),
    public.bike_fact_requirement_text('rearSpokeHoles', '36'),
    public.bike_fact_requirement_text('frontWheelBsdMm', '584'),
    public.installed_bike_fact_label('rearSpokeHoles', '28'),
    public.installed_bike_fact_label('rearWheelBsdMm', '622')),
  '["la maza trasera tiene 28 perforaciones", "la maza delantera tiene 32 o 36 perforaciones",
    "la rueda trasera lleva 36 rayos", "el neumático trasero es 584 (27,5″/650b)",
    "el neumático delantero es 622 (29″/700c)", "la llanta trasera es 622 (29″/700c)",
    "la llanta delantera es 584 o 622", "la rueda trasera lleva 36 rayos",
    "la rueda delantera es 584 (27,5″/650b)", "28H en la rueda trasera",
    "622 (29″/700c) en la rueda trasera"]'::jsonb,
  'se dice con qué pieza de la rueda no calza, y lo de antes se dice igual');
select ok(
  public.bike_fact_requirement_advice('rearHubSpokeHoles') like 'Una llanta se raya en una maza%'
  and public.bike_fact_requirement_advice('rearBuildSpokeHoles') like 'La rueda queda con las perforaciones de su llanta%'
  and public.bike_fact_requirement_advice('rearTireBsdMm') like 'Una llanta y su neumático tienen el mismo BSD%'
  and public.bike_fact_requirement_advice('rearRimBsdMm') like 'Un neumático calza sólo en una llanta de su mismo BSD%'
  and public.bike_fact_requirement_advice('rearSpokeHoles') like 'Una maza con menos perforaciones que la llanta%'
  and public.bike_fact_requirement_advice('frontWheelBsdMm') like 'Revisa la medida del neumático%',
  'cada rechazo trae qué hacer; los de antes, igual');
select ok(
  not has_function_privilege('authenticated',
    'public.bike_fact_rim_checks_internal(uuid,uuid,uuid,text,jsonb)', 'EXECUTE')
  and not has_function_privilege('authenticated',
    'public.job_wheel_bsd_internal(uuid,uuid,uuid,text,text)', 'EXECUTE')
  and not has_function_privilege('authenticated',
    'public.bike_fact_before_job_internal(uuid,uuid,uuid,text,jsonb)', 'EXECUTE')
  and not has_function_privilege('authenticated',
    'public.job_line_gate_check_internal(public.mechanic_job_items,boolean,jsonb)', 'EXECUTE')
  and not has_function_privilege('authenticated',
    'public.mechanic_job_line_gate_internal(uuid,uuid,text)', 'EXECUTE')
  and not has_function_privilege('service_role',
    'public.mechanic_job_line_gate_internal(uuid,uuid,text)', 'EXECUTE')
  and not has_function_privilege('authenticated',
    'public.job_lines_bike_changed_internal(uuid,uuid)', 'EXECUTE')
  and not has_table_privilege('authenticated',
    'public.mechanic_job_line_gate_deferrals', 'SELECT,INSERT,UPDATE,DELETE')
  and not has_table_privilege('service_role',
    'public.mechanic_job_line_gate_deferrals', 'SELECT,INSERT,UPDATE,DELETE')
  and not has_table_privilege('anon',
    'public.mechanic_job_line_gate_deferrals', 'SELECT,INSERT,UPDATE,DELETE'),
  'las reglas nuevas son internas, y la espera de la puerta no la abre nadie más');

-- ============================================================================
-- Fixture
-- ============================================================================

insert into public.tenants (id, shop_name) values
  ('e2840000-0000-4000-8000-000000000001', 'Taller llantas');

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('e2840000-0000-4000-8000-000000000099', 'authenticated', 'authenticated',
   'llantas@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now());

insert into public.user_profiles (user_id, tenant_id, role) values
  ('e2840000-0000-4000-8000-000000000099',
   'e2840000-0000-4000-8000-000000000001', 'admin');

insert into public.customers (id, tenant_id, name) values
  ('e2840000-0000-4000-8000-000000000010',
   'e2840000-0000-4000-8000-000000000001', 'Cliente llantas');

insert into public.bikes (id, tenant_id, customer_id, brand, model, wheel_size)
select ('e2840000-0000-4000-8000-0000000000' || b.n)::uuid,
       'e2840000-0000-4000-8000-000000000001',
       'e2840000-0000-4000-8000-000000000010', b.brand, b.model, b.wheel
  from (values
    ('31', 'Oxford', 'Orion 4', '29"'), ('32', 'Trek', 'Xcaliber 8', '29'''''),
    ('33', 'Rockrider', 'ST520', null), ('34', 'Lahsen', 'Rocket 2600', '26"'),
    ('35', 'Opaltech', 'Amarok', '29"'), ('36', 'Besatti', 'Priore', '27.5"'),
    ('37', 'Totem', 'Fussion', '29"'), ('38', 'Oxford', 'Merak 1', '29"'),
    ('39', 'Voltta', 'Prato', '29"'), ('40', 'Trek', 'Marlin 7', '29'''''),
    ('41', 'Jeep', 'Gaspio', '29"'), ('42', 'Vision', 'Krypton 29', '29'''''),
    ('43', 'Upland', 'X200', '29'''''), ('44', 'Phoenix', '04D', '29"'),
    ('45', 'Trek', 'Marlin 5', '29"'), ('46', 'Oxford', 'Hurricane', '29"'),
    ('47', 'Cross', 'Cross', '29"'), ('48', 'Oxford', 'Merak 2', '29"'),
    ('49', 'Lashen', 'XT9007', '29"'), ('50', 'Jeep', 'Baltoro', '29'),
    ('51', 'Totem', '4423', '29'), ('52', 'Oxford', 'Orion 1', '29"'),
    ('53', 'Scott', 'Scale 960', '29"'), ('54', 'Oxford', 'Merak 3', '29"'),
    ('55', 'Trek', '4300', '26"'), ('56', 'Oxford', 'Orion 2', null),
    ('57', 'Oxford', 'Orion 3', '27.5"'), ('58', 'Trek', 'Marlin 6', '29"'),
    ('59', 'Trek', 'Roscoe 7', '29"'), ('60', 'Jeep', 'Gaspio 2', '29"'),
    ('61', 'Oxford', 'Orion 5', '29"'), ('62', 'Bianchi', 'Duel 27', '29"'),
    ('63', 'Trek', 'Marlin 4', '29"'), ('64', 'Oxford', 'Orion 6', '29"'),
    ('65', 'Oxford', 'Orion 7', '29"'), ('66', 'Trek', 'Marlin 8', '29"'),
    ('67', 'Trek', 'Fuel EX', '29"'), ('68', 'Oxford', 'Orion 8', null),
    ('69', 'Scott', 'Aspect 950', '29"'), ('70', 'Oxford', 'Orion 9', '29"'),
    ('71', 'Oxford', 'Merak 4', '29"')
  ) b(n, brand, model, wheel);

-- Las fichas. La Orion 4 dice 32 adelante y atrás (producción); las demás son
-- supuestas, cada una para su caso.
insert into public.bike_profiles (tenant_id, bike_id, technical_profile)
select 'e2840000-0000-4000-8000-000000000001',
       ('e2840000-0000-4000-8000-0000000000' || p.n)::uuid,
       jsonb_build_object(
         'values', p.facts,
         'sources', (select coalesce(jsonb_object_agg(k, 'mechanic'), '{}'::jsonb)
                       from jsonb_object_keys(p.facts) k),
         'confirmed', (select coalesce(jsonb_object_agg(k, true), '{}'::jsonb)
                         from jsonb_object_keys(p.facts) k))
  from (values
    ('31', '{"frontSpokeHoles": 32, "rearSpokeHoles": 32}'::jsonb),
    ('32', '{"rearSpokeHoles": 32}'::jsonb),
    ('33', '{"rearSpokeHoles": 32}'::jsonb),
    ('36', '{"rearSpokeHoles": 32}'::jsonb),
    ('37', '{"rearSpokeHoles": 32}'::jsonb),
    ('38', '{"rearSpokeHoles": 36}'::jsonb),
    ('40', '{"rearWheelBsdMm": 584}'::jsonb),
    ('41', '{"rearWheelBsdMm": 584}'::jsonb),
    ('42', '{"rearSpokeHoles": 28}'::jsonb),
    ('43', '{"rearSpokeHoles": 28}'::jsonb),
    ('53', '{"brakeType": "hydraulic_disc"}'::jsonb),
    ('60', '{"rearWheelBsdMm": 584}'::jsonb),
    ('68', '{"rearSpokeHoles": 28}'::jsonb)
  ) p(n, facts);

insert into public.products (id, tenant_id, name, category_name)
select ('e2840000-0000-4000-8000-000000000' || p.n)::uuid,
       'e2840000-0000-4000-8000-000000000001', p.name, p.category
  from (values
    ('201', 'Llanta FOSS F22 Aluminio Doble Pared con Ojetillos 29x32H', 'Llantas'),
    ('202', 'Llanta Weinmann U32 TL 29" Ojetillos 32H Presta Negro', 'Llantas'),
    ('203', 'Llanta Weinmann U32 TL 27.5" Ojetillos 28H Presta Negro', 'Llantas'),
    ('204', 'Llanta Aluminio FOSS Pared Simple 26x1,75x36H Black.', 'Llantas'),
    ('205', 'Llanta Weinmann ZAC19 26" Ojetillos 36H Schrader Negro', 'Llantas'),
    ('206', 'Llanta Weinmann U28 27.5" Ojetillos 36H Schrader Negro', 'Llantas'),
    ('207', 'Llanta Weinmann U28 27.5" Ojetillos 32H Schrader Negro', 'Llantas'),
    ('221', 'Maza Eclipse GL-B10R QR SELLADA BLACK 135MM 32H 8V', 'Mazas'),
    ('222', 'Maza Trasera Disco 36H para Piñon con hilo QR 13mm 8S', 'Mazas'),
    ('223', 'Maza Trasera Freewheel Disco 32h Betta', 'Mazas'),
    ('224', 'maza shimano hb-rm66 36h (cl) delantero negro bolsa', 'Mazas'),
    ('225', 'Maza trasera 28H rueda libre (supuesta)', 'Mazas'),
    ('226', 'Maza delantera 36H 6 pernos (supuesta)', 'Mazas'),
    ('227', 'Maza trasera rueda libre sin perforaciones (supuesta)', 'Mazas'),
    ('231', 'NEUM. (W) 29 x 2.25" KENDA " MOSER K1259 BK/BSK 3', 'Neumáticos'),
    ('232', 'MAXXIS ALAMBRE 29X2.25 M315P ARDENT', 'Neumáticos'),
    ('233', 'Neumatico Bicicleta Aro 27.5 X 2.10 Voltage Best', 'Neumáticos'),
    ('234', 'Neumático sin BSD en su ficha (supuesto)', 'Neumáticos'),
    ('241', 'ROTOR FRENO DISCO SHIMANO SM-RT10 160MM AE', 'Frenos'),
    ('242', 'Disco de Freno Flotante 160mm Cyclami', 'Frenos')
  ) p(n, name, category);

create temporary table test_product_templates (
  product_id uuid primary key,
  template_key text
);
insert into test_product_templates
select ('e2840000-0000-4000-8000-000000000' || t.n)::uuid, t.template_key
  from (values
    ('201', 'rim'), ('202', 'rim'), ('203', 'rim'), ('204', 'rim'), ('205', 'rim'),
    ('206', 'rim'), ('207', 'rim'), ('221', 'hub'), ('222', 'hub'), ('223', 'hub'), ('224', 'hub'),
    ('225', 'hub'), ('226', 'hub'), ('227', 'hub'), ('231', 'tire'), ('232', 'tire'),
    ('233', 'tire'), ('234', 'tire'),
    ('241', 'rotor'), ('242', 'rotor')
  ) t(n, template_key);

-- Lo que dice cada ficha técnica. Ninguna verificada en producción. La FOSS
-- F22, la ZAC19 y la U28 de 36H no dicen su BSD: su nombre dice 29, 26 y
-- 27.5 y eso no se lee. Supuestas: 225 y 226 enteras, y el anclaje de 6
-- pernos del Cyclami.
create temporary table test_product_specs (
  product_id uuid,
  spec_key text,
  value jsonb,
  verified boolean default false
);
insert into test_product_specs (product_id, spec_key, value)
select ('e2840000-0000-4000-8000-000000000' || s.n)::uuid, s.spec_key, s.value::jsonb
  from (values
    ('201', 'spoke_hole_count', '32'),
    ('201', 'rim_wall_type', '"Doble pared"'),
    ('202', 'spoke_hole_count', '32'),
    ('202', 'bead_seat_diameter_mm', '622'),
    ('203', 'spoke_hole_count', '28'),
    ('203', 'bead_seat_diameter_mm', '584'),
    ('203', 'rim_etrto', '"584x27.4"'),
    ('204', 'spoke_hole_count', '36'),
    ('204', 'bead_seat_diameter_mm', '559'),
    ('205', 'spoke_hole_count', '36'),
    ('206', 'spoke_hole_count', '36'),
    ('207', 'spoke_hole_count', '32'),
    ('207', 'bead_seat_diameter_mm', '584'),
    ('221', 'spoke_hole_count', '32'),
    ('221', 'hub_old_mm', '135'),
    ('222', 'hub_package_position', '"Trasera"'),
    ('222', 'spoke_hole_count', '36'),
    ('222', 'hub_drive_receiver_kind', '"Rosca para piñón (rueda libre)"'),
    ('223', 'hub_package_position', '"Trasera"'),
    ('223', 'spoke_hole_count', '32'),
    ('223', 'hub_drive_receiver_kind', '"Rosca para piñón (rueda libre)"'),
    ('224', 'hub_package_position', '"Delantera"'),
    ('224', 'spoke_hole_count', '36'),
    ('224', 'rotor_mount_type', '"Centerlock"'),
    ('225', 'hub_package_position', '"Trasera"'),
    ('225', 'spoke_hole_count', '28'),
    ('225', 'hub_drive_receiver_kind', '"Rosca para piñón (rueda libre)"'),
    ('226', 'hub_package_position', '"Delantera"'),
    ('226', 'spoke_hole_count', '36'),
    ('226', 'rotor_mount_type', '"6 pernos"'),
    ('227', 'hub_package_position', '"Trasera"'),
    ('227', 'hub_drive_receiver_kind', '"Rosca para piñón (rueda libre)"'),
    ('234', 'tire_width_mm', '57.1'),
    ('231', 'bead_seat_diameter_mm', '622'),
    ('231', 'tire_width_mm', '57.1'),
    ('232', 'bead_seat_diameter_mm', '622'),
    ('233', 'bead_seat_diameter_mm', '584'),
    ('241', 'rotor_diameter_mm_value', '160'),
    ('241', 'rotor_mount_type', '"Centerlock"'),
    ('242', 'rotor_diameter_mm_value', '160'),
    ('242', 'rotor_floating', 'true'),
    ('242', 'rotor_mount_type', '"6 pernos"')) s(n, spec_key, value);

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

-- Un trabajo por bici; el 069 lleva dos bicis.
insert into public.mechanic_jobs (id, tenant_id, customer_id, bike_id, job_number, created_by)
select ('e2840000-0000-4000-8000-000000000' || j.n)::uuid,
       'e2840000-0000-4000-8000-000000000001',
       'e2840000-0000-4000-8000-000000000010',
       ('e2840000-0000-4000-8000-0000000000' || j.bike)::uuid,
       'PG-RIM-' || j.n,
       'e2840000-0000-4000-8000-000000000099'
  from (values
    ('051', '31'), ('052', '32'), ('053', '33'), ('054', '34'), ('055', '35'),
    ('056', '36'), ('057', '37'), ('058', '38'), ('059', '39'), ('060', '40'),
    ('061', '41'), ('062', '42'), ('063', '43'), ('064', '44'), ('065', '45'),
    ('066', '46'), ('067', '47'), ('068', '48'), ('069', '49'), ('070', '51'),
    ('071', '52'), ('072', '53'), ('073', '32'), ('074', '32'), ('075', '42'),
    ('076', '54'), ('077', '55'), ('078', '56'), ('079', '61'), ('080', '60'),
    ('081', '57'), ('082', '58'), ('083', '62'), ('084', '63'), ('085', '64'),
    ('086', '66'), ('087', '68'), ('088', '70'), ('089', '71')
  ) j(n, bike);

insert into public.mechanic_job_bikes (id, tenant_id, job_id, bike_id)
select case j.id
         when 'e2840000-0000-4000-8000-000000000069'::uuid
           then 'e2840000-0000-4000-8000-000000000691'::uuid
         when 'e2840000-0000-4000-8000-000000000087'::uuid
           then 'e2840000-0000-4000-8000-000000000871'::uuid
         when 'e2840000-0000-4000-8000-000000000088'::uuid
           then 'e2840000-0000-4000-8000-000000000881'::uuid
         else gen_random_uuid() end,
       'e2840000-0000-4000-8000-000000000001', j.id, j.bike_id
  from public.mechanic_jobs j
 where j.tenant_id = 'e2840000-0000-4000-8000-000000000001';
insert into public.mechanic_job_bikes (id, tenant_id, job_id, bike_id) values
  ('e2840000-0000-4000-8000-000000000692', 'e2840000-0000-4000-8000-000000000001',
   'e2840000-0000-4000-8000-000000000069', 'e2840000-0000-4000-8000-000000000050'),
  ('e2840000-0000-4000-8000-000000000862', 'e2840000-0000-4000-8000-000000000001',
   'e2840000-0000-4000-8000-000000000086', 'e2840000-0000-4000-8000-000000000067');
-- El 085 es de los viejos, sin filas de bicis: su bici es la de la cabecera.
delete from public.mechanic_job_bikes
 where job_id = 'e2840000-0000-4000-8000-000000000085';

-- Las líneas, con la marca que deja el mecánico al elegir la rueda (una
-- lista si son varios datos). Un Enrayado dice sus perforaciones y su rueda.
-- En cada trabajo se escriben en el orden de su número. Cada una va en la
-- pestaña de la única bici de su trabajo, en la que dice (a, b, d, e) o en
-- General (g): una línea de General no es de ninguna bici (20261001195000).
insert into public.mechanic_job_items (
  id, tenant_id, job_id, job_bike_id, product_id, product_name, item_type,
  location_key, quantity, unit_price, service_configuration_data, created_at
)
select ('e2840000-0000-4000-8000-000000000' || l.n)::uuid,
       'e2840000-0000-4000-8000-000000000001',
       ('e2840000-0000-4000-8000-000000000' || l.job)::uuid,
       case l.tab
         when 'a' then 'e2840000-0000-4000-8000-000000000691'::uuid
         when 'b' then 'e2840000-0000-4000-8000-000000000692'::uuid
         when 'd' then 'e2840000-0000-4000-8000-000000000871'::uuid
         when 'e' then 'e2840000-0000-4000-8000-000000000881'::uuid
         when 'g' then null
         else (select jb.id from public.mechanic_job_bikes jb
                where jb.job_id = ('e2840000-0000-4000-8000-000000000' || l.job)::uuid)
       end,
       case when l.product is not null
         then ('e2840000-0000-4000-8000-000000000' || l.product)::uuid end,
       coalesce(p.name, 'Enrayado + Centrado'),
       case when l.product is null then 'service' else 'product' end,
       l.location_key, 1, 19990,
       coalesce(l.data::jsonb, '{}'::jsonb),
       now() + (l.n::integer * interval '1 millisecond')
  from (values
    -- PG-00389, como en producción pero con rueda y marcas: llanta FOSS F22
    -- 32H, maza Eclipse 32H sin posición, neumático Kenda y el Enrayado.
    ('301', '051', '201', 'rear', '{"part_change": {"key": "rearSpokeHoles", "value": 32}}', null),
    ('302', '051', '221', 'rear', null, null),
    ('303', '051', '231', 'rear', '{"part_change": {"key": "rearWheelBsdMm", "value": 622}}', null),
    ('304', '051', null, 'none', '{"hole_count": "32", "which_wheel": "rear"}', null),
    -- La Xcaliber (PG-00260): la U32 TL 29" con su BSD y sus 32H.
    ('305', '052', '202', 'rear', '{"part_change": [{"key": "rearWheelBsdMm", "value": 622}, {"key": "rearSpokeHoles", "value": 32}]}', null),
    ('306', '052', null, 'none', '{"hole_count": "32", "which_wheel": "rear"}', null),
    -- La Rockrider: de 32 a 28H (una maza de 32 se raya en 28).
    ('307', '053', '203', 'rear', '{"part_change": [{"key": "rearSpokeHoles", "value": 28}, {"key": "rearWheelBsdMm", "value": 584}]}', null),
    ('308', '053', null, 'none', '{"hole_count": "28", "which_wheel": "rear"}', null),
    -- La Rocket 26": 26″ no refuta un 584 atrás ni un 559 adelante.
    ('309', '054', '203', 'rear', '{"part_change": [{"key": "rearSpokeHoles", "value": 28}, {"key": "rearWheelBsdMm", "value": 584}]}', null),
    ('310', '054', '204', 'front', '{"part_change": [{"key": "frontSpokeHoles", "value": 36}, {"key": "frontWheelBsdMm", "value": 559}]}', null),
    -- La Amarok 29": un 584 no entra.
    ('311', '055', '203', 'rear', '{"part_change": [{"key": "rearSpokeHoles", "value": 28}, {"key": "rearWheelBsdMm", "value": 584}]}', null),
    -- La Priore: una llanta de 36 y la Betta de 32 en la misma rueda.
    ('312', '056', '205', 'rear', '{"part_change": {"key": "rearSpokeHoles", "value": 36}}', null),
    ('313', '056', '223', 'rear', '{"part_change": {"key": "freehubType", "value": "threaded_freewheel"}}', null),
    -- La Fussion: la FOSS de 32 en la maza de 36 del trabajo (36 en 32).
    ('314', '057', '201', 'rear', '{"part_change": {"key": "rearSpokeHoles", "value": 32}}', null),
    ('315', '057', '222', 'rear', '{"part_change": {"key": "freehubType", "value": "threaded_freewheel"}}', null),
    -- La Merak 1: la FOSS de 32 y un Enrayado que cuenta 36.
    ('316', '058', '201', 'rear', '{"part_change": {"key": "rearSpokeHoles", "value": 32}}', null),
    ('317', '058', null, 'rear', '{"hole_count": "36"}', null),
    -- La Prato: la U32 TL 29" y un Voltage de 584 en la misma rueda.
    ('318', '059', '202', 'rear', '{"part_change": [{"key": "rearWheelBsdMm", "value": 622}, {"key": "rearSpokeHoles", "value": 32}]}', null),
    ('319', '059', '233', 'rear', '{"part_change": {"key": "rearWheelBsdMm", "value": 584}}', null),
    -- La Marlin 7 dice 584 atrás: su neumático se queda y la llanta es 622.
    ('320', '060', '202', 'rear', '{"part_change": [{"key": "rearWheelBsdMm", "value": 622}, {"key": "rearSpokeHoles", "value": 32}]}', null),
    -- El Gaspio dice 584 atrás, pero el trabajo cambia llanta y neumático a
    -- 622 (el neumático primero).
    ('321', '061', '232', 'rear', '{"part_change": {"key": "rearWheelBsdMm", "value": 622}}', null),
    ('322', '061', '202', 'rear', '{"part_change": [{"key": "rearWheelBsdMm", "value": 622}, {"key": "rearSpokeHoles", "value": 32}]}', null),
    -- La Krypton lleva 28 atrás: la FOSS de 32 no se raya en su maza.
    ('323', '062', '201', 'rear', '{"part_change": {"key": "rearSpokeHoles", "value": 32}}', null),
    -- La Upland lleva 28 atrás, y el Enrayado de 32 se escribe antes que la
    -- llanta: la maza que queda sigue siendo de 28.
    ('324', '063', null, 'none', '{"hole_count": "32", "which_wheel": "rear"}', null),
    ('325', '063', '201', 'rear', '{"part_change": {"key": "rearSpokeHoles", "value": 32}}', null),
    -- La Phoenix: dos llantas atrás que no dicen lo mismo.
    ('326', '064', '201', 'rear', '{"part_change": {"key": "rearSpokeHoles", "value": 32}}', null),
    ('327', '064', '205', 'rear', '{"part_change": {"key": "rearSpokeHoles", "value": 36}}', null),
    -- La Marlin 5, para lo que pasa después.
    ('328', '065', '202', 'rear', '{"part_change": [{"key": "rearWheelBsdMm", "value": 622}, {"key": "rearSpokeHoles", "value": 32}]}', null),
    -- La Hurricane, para quitarle la marca en el trabajo terminado.
    ('329', '066', '202', 'rear', '{"part_change": [{"key": "rearWheelBsdMm", "value": 622}, {"key": "rearSpokeHoles", "value": 32}]}', null),
    -- La Cross: el Ardent atrás (la llanta llega después).
    ('330', '067', '232', 'rear', '{"part_change": {"key": "rearWheelBsdMm", "value": 622}}', null),
    -- La Merak 2: la U32 TL atrás (el neumático llega después).
    ('331', '068', '202', 'rear', '{"part_change": [{"key": "rearWheelBsdMm", "value": 622}, {"key": "rearSpokeHoles", "value": 32}]}', null),
    -- Dos bicis: la llanta en General no es de ninguna; en la pestaña del
    -- Baltoro, es suya.
    ('332', '069', '202', 'rear', '{"part_change": [{"key": "rearWheelBsdMm", "value": 622}, {"key": "rearSpokeHoles", "value": 32}]}', 'g'),
    ('333', '069', '202', 'rear', '{"part_change": [{"key": "rearWheelBsdMm", "value": 622}, {"key": "rearSpokeHoles", "value": 32}]}', 'b'),
    -- y un Voltage de 584 en la pestaña de la XT9007: no es la rueda del
    -- Baltoro.
    ('347', '069', '233', 'rear', '{"part_change": {"key": "rearWheelBsdMm", "value": 584}}', 'a'),
    -- La Totem 4423: maza de 36, llanta de 36 y su Enrayado.
    ('334', '070', null, 'none', '{"hole_count": "36", "which_wheel": "rear"}', null),
    ('335', '070', '222', 'rear', '{"part_change": {"key": "freehubType", "value": "threaded_freewheel"}}', null),
    ('336', '070', '206', 'rear', '{"part_change": {"key": "rearSpokeHoles", "value": 36}}', null),
    -- La Orion 1, lo mismo.
    ('337', '071', null, 'none', '{"hole_count": "36", "which_wheel": "rear"}', null),
    ('338', '071', '222', 'rear', '{"part_change": {"key": "freehubType", "value": "threaded_freewheel"}}', null),
    ('339', '071', '206', 'rear', '{"part_change": {"key": "rearSpokeHoles", "value": 36}}', null),
    -- La Scott: HB-RM66 y SM-RT10 adelante, Center Lock.
    ('340', '072', '224', 'front', '{"part_change": {"key": "frontRotorMount", "value": "centerlock"}}', null),
    ('341', '072', '241', 'front', '{"part_change": {"key": "frontRotorSizeMm", "value": 160}}', null),
    -- Después, en la Xcaliber: un Voltage de 584 solo, y otro con la U32 TL
    -- de 27,5.
    ('342', '073', '233', 'rear', '{"part_change": {"key": "rearWheelBsdMm", "value": 584}}', null),
    ('343', '074', '233', 'rear', '{"part_change": {"key": "rearWheelBsdMm", "value": 584}}', null),
    ('344', '074', '203', 'rear', '{"part_change": [{"key": "rearWheelBsdMm", "value": 584}, {"key": "rearSpokeHoles", "value": 28}]}', null),
    -- La Krypton, otra vez: la FOSS de 32 con una maza nueva de 32.
    ('348', '075', '201', 'rear', '{"part_change": {"key": "rearSpokeHoles", "value": 32}}', null),
    ('349', '075', '223', 'rear', '{"part_change": {"key": "freehubType", "value": "threaded_freewheel"}}', null),
    -- La Merak 3: la FOSS de 32 y dos mazas traseras que no dicen lo mismo.
    ('360', '076', '201', 'rear', '{"part_change": {"key": "rearSpokeHoles", "value": 32}}', null),
    ('361', '076', '223', 'rear', null, null),
    ('362', '076', '222', 'rear', null, null),
    -- La 4300: dos llantas de 32H atrás, una de 622 y otra de 584.
    ('363', '077', '202', 'rear', '{"part_change": [{"key": "rearWheelBsdMm", "value": 622}, {"key": "rearSpokeHoles", "value": 32}]}', null),
    ('364', '077', '207', 'rear', '{"part_change": [{"key": "rearWheelBsdMm", "value": 584}, {"key": "rearSpokeHoles", "value": 32}]}', null),
    -- La Orion 2: la U32 TL 29" con dos neumáticos atrás, un Voltage de 584 y
    -- uno cuya ficha no dice su BSD (sin marca: sólo se miden).
    ('365', '078', '202', 'rear', '{"part_change": [{"key": "rearWheelBsdMm", "value": 622}, {"key": "rearSpokeHoles", "value": 32}]}', null),
    ('366', '078', '233', 'rear', null, null),
    ('367', '078', '234', 'rear', null, null),
    -- La Orion 5: la FOSS de 32 con dos mazas atrás, una de 28 y otra que no
    -- dice sus perforaciones.
    ('368', '079', '201', 'rear', '{"part_change": {"key": "rearSpokeHoles", "value": 32}}', null),
    ('369', '079', '225', 'rear', null, null),
    ('370', '079', '227', 'rear', null, null),
    -- El Gaspio 2: su ficha dice 584 atrás y su aro escrito, 29″; el trabajo
    -- cambia llanta y neumático, los dos de 584.
    ('371', '080', '207', 'rear', '{"part_change": [{"key": "rearWheelBsdMm", "value": 584}, {"key": "rearSpokeHoles", "value": 32}]}', null),
    ('372', '080', '233', 'rear', '{"part_change": {"key": "rearWheelBsdMm", "value": 584}}', null),
    -- La Orion 3 (27,5″) y la Duel (29″): la U28 de 584, todavía sin marca.
    ('373', '081', '207', 'rear', '{}', null),
    ('374', '083', '207', 'rear', '{}', null),
    -- La U32 TL en General de la Marlin 6 (su única bici) y de la Orion 6 (sin
    -- filas de bicis); en la pestaña de la Marlin 4.
    ('375', '082', '202', 'rear', '{"part_change": [{"key": "rearWheelBsdMm", "value": 622}, {"key": "rearSpokeHoles", "value": 32}]}', 'g'),
    ('376', '084', '202', 'rear', '{"part_change": [{"key": "rearWheelBsdMm", "value": 622}, {"key": "rearSpokeHoles", "value": 32}]}', null),
    ('377', '085', '202', 'rear', '{"part_change": [{"key": "rearWheelBsdMm", "value": 622}, {"key": "rearSpokeHoles", "value": 32}]}', 'g'),
    -- La Marlin 8 y la Fuel EX: la U32 TL en General de un trabajo de dos.
    ('378', '086', '202', 'rear', '{"part_change": [{"key": "rearWheelBsdMm", "value": 622}, {"key": "rearSpokeHoles", "value": 32}]}', 'g'),
    -- La Orion 8 (28 atrás): la FOSS de 32 en su pestaña, con una maza de 32
    -- sin marca en General.
    ('380', '087', '201', 'rear', '{"part_change": {"key": "rearSpokeHoles", "value": 32}}', 'd'),
    ('381', '087', '223', 'rear', null, 'g'),
    -- La Orion 9: la U32 TL en su pestaña.
    ('382', '088', '202', 'rear', '{"part_change": [{"key": "rearWheelBsdMm", "value": 622}, {"key": "rearSpokeHoles", "value": 32}]}', 'e')
  ) l(n, job, product, location_key, data, tab)
  left join public.products p
    on p.id = ('e2840000-0000-4000-8000-000000000' || l.product)::uuid;

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

create or replace function pg_temp.id(p_n text)
returns uuid
language sql
as $$ select ('e2840000-0000-4000-8000-000000000' || p_n)::uuid $$;

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
language plpgsql
as $$
declare
  v_detail text;
  v_hint text;
begin
  return public.transition_mechanic_job_status(
    pg_temp.id(p_job),
    (select id from status_ids where code = p_code),
    'rim-' || p_job || '-' || p_code);
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
                            order by problem->>'reason', problem->>'key', problem->>'value',
                                     problem->>'requires_value'), '[]'::jsonb)
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
           '^job_completion:e2840000-0000-4000-8000-000000000', 'job_completion:')
           order by operation_key), '[]'::jsonb)
    from public.bike_technical_fact_patches
   where job_id = pg_temp.id(p_job)
$$;

-- Lo que el formulario manda al guardar: todas las líneas que cargó, cada
-- una como está salvo lo que cambia (`p_changes`, por número de línea), en
-- el orden de `p_order`.
create or replace function pg_temp.save(
  p_job text,
  p_key text,
  p_order text[],
  p_changes jsonb,
  p_bike_facts jsonb default '[]'::jsonb,
  p_job_bikes jsonb default null
)
returns jsonb
language plpgsql
as $$
declare
  v_job uuid := pg_temp.id(p_job);
begin
  return public.save_mechanic_job_lines_v1(
    p_key,
    v_job,
    (select coalesce(jsonb_agg(jsonb_build_object('id', i.id, 'updated_at', i.updated_at)), '[]'::jsonb)
       from public.mechanic_job_items i
      where i.job_id = v_job),
    (select jsonb_agg(jsonb_build_object(
              'client_key', 'l' || o.n,
              'id', i.id,
              'job_bike_id', i.job_bike_id,
              'product_id', i.product_id,
              'product_name', i.product_name,
              'quantity', i.quantity,
              'unit_price', i.unit_price,
              'item_type', i.item_type,
              'location_key', i.location_key,
              'service_configuration_data', i.service_configuration_data)
            || coalesce(p_changes->o.n, '{}'::jsonb)
            order by o.ord)
       from unnest(p_order) with ordinality o(n, ord)
       join public.mechanic_job_items i on i.id = pg_temp.id(o.n)),
    p_bike_facts,
    null,
    p_job_bikes);
end;
$$;

-- ============================================================================
-- La regla: qué marca vale
-- ============================================================================

select is(
  jsonb_build_array(
    public.job_line_part_change_internal('e2840000-0000-4000-8000-000000000001',
      pg_temp.id('305'), 'rearWheelBsdMm') - 'link_id',
    public.job_line_part_change_internal('e2840000-0000-4000-8000-000000000001',
      pg_temp.id('305'), 'rearSpokeHoles') - 'link_id',
    public.job_line_part_change_internal('e2840000-0000-4000-8000-000000000001',
      pg_temp.id('305'))),
  '[{"key": "rearWheelBsdMm", "value": 622, "spec_key": "bead_seat_diameter_mm", "position": "rear",
     "verified": false, "on_mismatch": "change", "template_key": "rim"},
    {"key": "rearSpokeHoles", "value": 32, "spec_key": "spoke_hole_count", "position": "rear",
     "verified": false, "on_mismatch": "change", "template_key": "rim"},
    null]'::jsonb,
  'la U32 TL marca su BSD y sus perforaciones con la fila de la llanta; con dos marcas la regla de un dato no elige');

-- La FOSS F22 dice 29 en el nombre, no en su ficha técnica: su BSD no vale.
update public.mechanic_job_items
   set service_configuration_data = '{"part_change": [{"key": "rearWheelBsdMm", "value": 622}, {"key": "rearSpokeHoles", "value": 32}]}'
 where id = pg_temp.id('323');
select is(
  jsonb_build_array(
    public.job_line_part_change_internal('e2840000-0000-4000-8000-000000000001',
      pg_temp.id('323'), 'rearWheelBsdMm'),
    public.job_line_part_change_internal('e2840000-0000-4000-8000-000000000001',
      pg_temp.id('323'), 'rearSpokeHoles')->'value'),
  '[null, 32]'::jsonb,
  'el BSD no se infiere del nombre ni de la pulgada: una llanta sin BSD en su ficha propone sólo sus perforaciones');
update public.mechanic_job_items
   set service_configuration_data = '{"part_change": {"key": "rearSpokeHoles", "value": 32}}'
 where id = pg_temp.id('323');

-- Sin rueda, en otra rueda, o un neumático con perforaciones: no vale.
update public.mechanic_job_items set location_key = 'none' where id = pg_temp.id('326');
select is(
  jsonb_build_array(
    public.job_line_part_change_internal('e2840000-0000-4000-8000-000000000001',
      pg_temp.id('326'), 'rearSpokeHoles'),
    public.job_line_part_change_internal('e2840000-0000-4000-8000-000000000001',
      pg_temp.id('310'), 'rearWheelBsdMm'),
    public.job_line_part_change_internal('e2840000-0000-4000-8000-000000000001',
      pg_temp.id('310'), 'frontWheelBsdMm')->'value'),
  '[null, null, 559]'::jsonb,
  'la marca vale sólo en la rueda de la línea');
update public.mechanic_job_items set location_key = 'rear' where id = pg_temp.id('326');

-- ============================================================================
-- Lo que la ficha decía antes del trabajo
-- ============================================================================

select is(
  jsonb_build_array(
    public.bike_fact_before_job_internal('e2840000-0000-4000-8000-000000000001',
      'e2840000-0000-4000-8000-000000000043', pg_temp.id('063'), 'rearSpokeHoles',
      '{"rearSpokeHoles": 28}'),
    public.bike_fact_before_job_internal('e2840000-0000-4000-8000-000000000001',
      'e2840000-0000-4000-8000-000000000045', pg_temp.id('065'), 'rearSpokeHoles',
      '{}')),
  '[28, null]'::jsonb,
  'sin recibos del trabajo, lo que la ficha dice ahora (o nada)');

-- ============================================================================
-- Al terminar: lo que calza
-- ============================================================================

-- PG-00389: todo calza. La FOSS no dice BSD: el neumático Kenda lo anota
-- (el aro 29" lo admite); sus 32H son las de la ficha, de la maza y del
-- Enrayado, así que nada cambia de valor.
insert into results select 'orion', pg_temp.finish('051');
select is(
  jsonb_build_array(
    pg_temp.problems('orion'),
    pg_temp.fact('31', 'rearWheelBsdMm'),
    pg_temp.fact('31', 'rearSpokeHoles'),
    pg_temp.receipts('051')),
  '[[], [622, null, "job_completion"], [32, true, "mechanic"],
    ["job_completion:301:1:rearSpokeHoles=32", "job_completion:303:1:rearWheelBsdMm=622",
     "job_completion:304:1:rearSpokeHoles=32"]]'::jsonb,
  'PG-00389 calza: la llanta, la maza, el neumático y el Enrayado dicen la misma rueda');

-- La Xcaliber: el BSD entra declarado, en un recibo con las perforaciones.
insert into results select 'xcaliber', pg_temp.finish('052');
select is(
  jsonb_build_array(
    pg_temp.problems('xcaliber'),
    pg_temp.fact('32', 'rearWheelBsdMm'),
    pg_temp.fact('32', 'rearSpokeHoles'),
    pg_temp.receipts('052')),
  '[[], [622, null, "job_completion"], [32, true, "mechanic"],
    ["job_completion:305:1:rearSpokeHoles=32,rearWheelBsdMm=622",
     "job_completion:306:1:rearSpokeHoles=32"]]'::jsonb,
  'la U32 TL escribe su BSD y sus perforaciones en un solo recibo; las 32 que el mecánico ya confirmó quedan suyas');

-- La Rockrider: la rueda pasa de 32 a 28H (la maza de 32 que queda se raya
-- en 28) y el BSD 584 entra (sin aro escrito no se refuta).
insert into results select 'rockrider', pg_temp.finish('053');
select is(
  jsonb_build_array(
    pg_temp.problems('rockrider'),
    pg_temp.fact('33', 'rearSpokeHoles'),
    pg_temp.fact('33', 'rearWheelBsdMm')),
  '[[], [28, true, "job_completion"], [584, null, "job_completion"]]'::jsonb,
  'una llanta de 28H cambia la ficha de 32 a 28: la maza de 32 que queda se raya en 28');

-- La Rocket 26": 26″ son varios BSD; un 584 atrás y un 559 adelante entran.
insert into results select 'rocket', pg_temp.finish('054');
select is(
  jsonb_build_array(
    pg_temp.problems('rocket'),
    pg_temp.fact('34', 'rearWheelBsdMm'),
    pg_temp.fact('34', 'frontWheelBsdMm'),
    pg_temp.fact('34', 'frontSpokeHoles'),
    pg_temp.fact('34', 'rearSpokeHoles')),
  '[[], [584, null, "job_completion"], [559, null, "job_completion"],
    [36, null, "job_completion"], [28, null, "job_completion"]]'::jsonb,
  '26″ no refuta: cada rueda toma su llanta, y una rueda no se mide con la otra');

-- La Fussion: la FOSS de 32 en la maza de 36 del trabajo (patrón 36 en 32).
insert into results select 'fussion', pg_temp.finish('057');
select is(
  jsonb_build_array(pg_temp.problems('fussion'), pg_temp.fact('37', 'rearSpokeHoles')),
  '[[], [32, true, "mechanic"]]'::jsonb,
  'una llanta de 32 en la maza de 36 del mismo trabajo se raya: no es un rechazo');

-- El Gaspio: su ficha dice 584 atrás, pero el trabajo cambia neumático y
-- llanta a 622; el neumático se mide con la llanta del trabajo, no con la
-- ficha vieja.
insert into results select 'gaspio', pg_temp.finish('061');
select is(
  jsonb_build_array(
    pg_temp.problems('gaspio'),
    pg_temp.fact('41', 'rearWheelBsdMm'),
    pg_temp.fact('41', 'rearSpokeHoles')),
  '[[], [622, null, "job_completion"], [32, null, "job_completion"]]'::jsonb,
  'llanta y neumático de 622 en el mismo trabajo cambian la rueda aunque la ficha dijera 584');

-- ============================================================================
-- Al terminar: lo que no calza
-- ============================================================================

-- La Amarok 29": un 584 no entra (el aro escrito es un solo diámetro). La
-- llanta es una pieza: tampoco anota sus perforaciones.
insert into results select 'amarok', pg_temp.finish('055');
select is(
  jsonb_build_array(
    pg_temp.problems('amarok'),
    pg_temp.fact('35', 'rearWheelBsdMm'),
    pg_temp.fact('35', 'rearSpokeHoles')),
  '[[{"key": "rearSpokeHoles", "value": 28, "reason": "incompatible", "requires_key": "bikes.wheel_size", "requires_value": "29\""},
     {"key": "rearWheelBsdMm", "value": 584, "reason": "incompatible", "requires_key": "bikes.wheel_size", "requires_value": "29\""}],
    null, null]'::jsonb,
  'en una 29" la llanta de 27,5 no se instala: ni su BSD ni sus perforaciones');

-- La Priore: la llanta de 36 y la Betta de 32 en la misma rueda. No calza
-- ninguna de las dos (la maza, contra la llanta del trabajo).
insert into results select 'priore', pg_temp.finish('056');
select is(
  pg_temp.problems('priore'),
  '[{"key": "freehubType", "value": "threaded_freewheel", "reason": "incompatible", "requires_key": "rearSpokeHoles", "requires_value": "36", "requires_source": "job_rim"},
    {"key": "rearSpokeHoles", "value": 36, "reason": "incompatible", "requires_key": "rearHubSpokeHoles", "requires_value": "32", "requires_source": "job_hub"}]'::jsonb,
  'una llanta de 36 no se raya en la maza de 32 del mismo trabajo, en las dos direcciones');
select ok(
  not exists (select 1 from public.bike_events bi
           where bi.bike_id = 'e2840000-0000-4000-8000-000000000036'
             and bi.summary like '%Llanta Weinmann ZAC19%36H en la rueda trasera%la maza que instala el trabajo dice la maza trasera tiene 32 perforaciones%Una llanta se raya en una maza%'),
  'un cierre rechazado no deja historia de una llanta instalada');

-- La Merak 1: el Enrayado cuenta 36 y la llanta es de 32.
insert into results select 'merak', pg_temp.finish('058');
select is(
  jsonb_build_array(pg_temp.problems('merak'), pg_temp.fact('38', 'rearSpokeHoles')),
  '[[{"key": "rearSpokeHoles", "value": 32, "reason": "incompatible", "requires_key": "rearBuildSpokeHoles", "requires_value": "36", "requires_source": "job_build"}],
    [36, true, "mechanic"]]'::jsonb,
  'la rueda queda con las perforaciones de su llanta: un Enrayado de 36 no calza con una de 32');

-- La Prato: llanta 622 y neumático 584 en la misma rueda.
insert into results select 'prato', pg_temp.finish('059');
select is(
  jsonb_build_array(pg_temp.problems('prato'), pg_temp.fact('39', 'rearWheelBsdMm')),
  '[[{"key": "rearSpokeHoles", "value": 32, "reason": "incompatible", "requires_key": "rearTireBsdMm", "requires_value": "584", "requires_source": "job_tire"},
     {"key": "rearWheelBsdMm", "value": 584, "reason": "incompatible", "requires_key": "rearRimBsdMm", "requires_value": "622", "requires_source": "job_rim"},
     {"key": "rearWheelBsdMm", "value": 622, "reason": "incompatible", "requires_key": "rearTireBsdMm", "requires_value": "584", "requires_source": "job_tire"}],
    null]'::jsonb,
  'llanta y neumático de otro BSD en la misma rueda: ninguno escribe nada');
select ok(
  not exists (select 1 from public.bike_events bi
           where bi.bike_id = 'e2840000-0000-4000-8000-000000000039'
             and bi.summary like '%el neumático que instala el trabajo dice el neumático trasero es 584%')
  and not exists (select 1 from public.bike_events bi
           where bi.bike_id = 'e2840000-0000-4000-8000-000000000039'
             and bi.summary like '%la llanta que instala el trabajo dice la llanta trasera es 622%'),
  'el cierre incompatible tampoco deja eventos parciales de llanta y neumático');

-- La Marlin 7: su neumático de 584 se queda.
insert into results select 'marlin7', pg_temp.finish('060');
select is(
  jsonb_build_array(pg_temp.problems('marlin7'), pg_temp.fact('40', 'rearWheelBsdMm'),
                    pg_temp.fact('40', 'rearSpokeHoles')),
  '[[{"key": "rearSpokeHoles", "value": 32, "reason": "incompatible", "requires_key": "rearTireBsdMm", "requires_value": "584"},
     {"key": "rearWheelBsdMm", "value": 622, "reason": "incompatible", "requires_key": "rearTireBsdMm", "requires_value": "584"}],
    [584, true, "mechanic"], [null, null, null]]'::jsonb,
  'una llanta de otro BSD sin su neumático no calza con el que queda, y no anota nada');

-- La Krypton lleva 28: su maza no toma una llanta de 32.
insert into results select 'krypton', pg_temp.finish('062');
select is(
  jsonb_build_array(pg_temp.problems('krypton'), pg_temp.fact('42', 'rearSpokeHoles')),
  '[[{"key": "rearSpokeHoles", "value": 32, "reason": "incompatible", "requires_key": "rearHubSpokeHoles", "requires_value": "28"}],
    [28, true, "mechanic"]]'::jsonb,
  'una llanta con más perforaciones que la maza que queda no se raya');

-- La Upland: el mismo caso con un Enrayado de 32 escrito antes que la llanta.
insert into results select 'upland', pg_temp.finish('063');
select is(
  jsonb_build_array(pg_temp.problems('upland'), pg_temp.fact('43', 'rearSpokeHoles')),
  '[[{"key": "rearSpokeHoles", "value": 32, "reason": "incompatible", "requires_key": "rearHubSpokeHoles", "requires_value": "28"}],
    [28, true, "mechanic"]]'::jsonb,
  'la maza que queda es la de antes del trabajo y el cierre no escribe ni el Enrayado');

-- El readback de autoría también cubre un trabajo histórico terminado bajo
-- el contrato anterior, que sí alcanzó a escribir sólo el Enrayado.
set local session_replication_role = replica;
update public.mechanic_jobs
   set status = 'FINALIZADO',
       status_id = (select id from status_ids where code = 'FINALIZADO')
 where id = pg_temp.id('063');
set local session_replication_role = origin;
insert into results select 'upland_historico',
  public.apply_job_installed_bike_facts_internal(
    'e2840000-0000-4000-8000-000000000001', pg_temp.id('063'), false);
select is(pg_temp.fact('43', 'rearSpokeHoles'), '[32, true, "job_completion"]'::jsonb,
  'el fixture histórico conserva el escritor parcial para probar autoría');
select is(
  public.bike_fact_before_job_internal('e2840000-0000-4000-8000-000000000001',
    'e2840000-0000-4000-8000-000000000043', pg_temp.id('063'), 'rearSpokeHoles',
    '{"rearSpokeHoles": 32}'),
  '28'::jsonb,
  'lo que el trabajo escribió no borra lo que la ficha decía antes');

-- Después el mecánico elige 32 en la ficha (la maza también era otra): eso
-- ya es suyo, y la llanta entra.
update public.bike_profiles
   set technical_profile = jsonb_set(technical_profile, '{sources,rearSpokeHoles}', '"mechanic"')
 where bike_id = 'e2840000-0000-4000-8000-000000000043';
insert into results select 'upland_despues',
  public.apply_job_installed_bike_facts_internal(
    'e2840000-0000-4000-8000-000000000001', pg_temp.id('063'), false);
select is(
  jsonb_build_array(pg_temp.problems('upland_despues'), pg_temp.receipts('063')),
  '[[], ["job_completion:324:1:rearSpokeHoles=32", "job_completion:325:1:rearSpokeHoles=32"]]'::jsonb,
  'lo que el mecánico eligió después es la rueda que queda');

-- La Krypton otra vez, con una maza nueva de 32: la maza vieja de 28 ya no
-- cuenta.
insert into results select 'krypton_maza', pg_temp.finish('075');
select is(
  jsonb_build_array(pg_temp.problems('krypton_maza'), pg_temp.fact('42', 'rearSpokeHoles')),
  '[[], [32, null, "job_completion"]]'::jsonb,
  'con la maza del trabajo, la ficha de antes ya no es la maza');

-- La Merak 3: dos mazas traseras de 32 y 36 en el trabajo.
insert into results select 'merak3', pg_temp.finish('076');
select is(
  pg_temp.problems('merak3'),
  '[{"key": "rearSpokeHoles", "value": 32, "reason": "incompatible", "requires_key": "rearHubSpokeHoles", "requires_value": "32 o 36", "requires_source": "job_hub"}]'::jsonb,
  'dos mazas que no dicen lo mismo: la llanta no se da por buena');

-- La 4300: dos llantas de otro BSD en la misma rueda.
insert into results select 'trek4300', pg_temp.finish('077');
select is(
  jsonb_build_array(pg_temp.problems('trek4300'), pg_temp.fact('55', 'rearWheelBsdMm')),
  '[[{"key": "rearSpokeHoles", "value": 32, "reason": "incompatible", "requires_key": "rearRimBsdMm", "requires_value": "584", "requires_source": "job_rim"},
     {"key": "rearSpokeHoles", "value": 32, "reason": "incompatible", "requires_key": "rearRimBsdMm", "requires_value": "622", "requires_source": "job_rim"},
     {"key": "rearWheelBsdMm", "value": 584, "reason": "incompatible", "requires_key": "rearRimBsdMm", "requires_value": "622", "requires_source": "job_rim"},
     {"key": "rearWheelBsdMm", "value": 622, "reason": "incompatible", "requires_key": "rearRimBsdMm", "requires_value": "584", "requires_source": "job_rim"}],
    null]'::jsonb,
  'dos llantas de otro BSD en la misma rueda: no se sabe cuál va, ninguna escribe');

-- La Orion 2: un neumático de 584 y otro que no dice su BSD, con una llanta
-- de 622. El que no lo dice no esconde al que sí (revisión de Codex,
-- 2026-09-29).
insert into results select 'orion2', pg_temp.finish('078');
select is(
  jsonb_build_array(pg_temp.problems('orion2'), pg_temp.fact('56', 'rearWheelBsdMm')),
  '[[{"key": "rearSpokeHoles", "value": 32, "reason": "incompatible", "requires_key": "rearTireBsdMm", "requires_value": "584", "requires_source": "job_tire"},
     {"key": "rearWheelBsdMm", "value": 622, "reason": "incompatible", "requires_key": "rearTireBsdMm", "requires_value": "584", "requires_source": "job_tire"}],
    null]'::jsonb,
  'un neumático sin BSD no esconde al de 584: la llanta de 622 no se instala');

-- La Orion 5: una maza de 28 y otra sin cuenta, con la FOSS de 32.
insert into results select 'orion5', pg_temp.finish('079');
select is(
  jsonb_build_array(pg_temp.problems('orion5'), pg_temp.fact('61', 'rearSpokeHoles')),
  '[[{"key": "rearSpokeHoles", "value": 32, "reason": "incompatible", "requires_key": "rearHubSpokeHoles", "requires_value": "28", "requires_source": "job_hub"}],
    null]'::jsonb,
  'una maza sin perforaciones no esconde a la de 28: la llanta de 32 no se raya');

-- El Gaspio 2: la ficha dice 584 y el aro escrito 29″, que no lo admite: el
-- aro es el que quedó viejo, y una llanta y un neumático de 584 calzan.
insert into results select 'gaspio2', pg_temp.finish('080');
select is(
  jsonb_build_array(
    pg_temp.problems('gaspio2'),
    pg_temp.fact('60', 'rearWheelBsdMm'),
    pg_temp.fact('60', 'rearSpokeHoles')),
  '[[], [584, true, "mechanic"], [32, null, "job_completion"]]'::jsonb,
  'un aro escrito que la ficha ya contradice no refuta la llanta ni el neumático del mismo BSD');

-- La Phoenix: dos llantas atrás con otra cuenta.
insert into results select 'phoenix', pg_temp.finish('064');
select is(
  jsonb_build_array(pg_temp.problems('phoenix'), pg_temp.fact('44', 'rearSpokeHoles')),
  '[[{"key": "rearSpokeHoles", "value": 32, "reason": "incompatible", "requires_key": "rearBuildSpokeHoles", "requires_value": "36", "requires_source": "job_rim"},
     {"key": "rearSpokeHoles", "value": 36, "reason": "incompatible", "requires_key": "rearBuildSpokeHoles", "requires_value": "32", "requires_source": "job_rim"}],
    null]'::jsonb,
  'dos llantas en la misma rueda con otra cuenta: no se sabe cuál va');

-- Dos bicis: la llanta de General no es de ninguna; la de la pestaña del
-- Baltoro escribe en el Baltoro.
insert into results select 'dos_bicis', pg_temp.finish('069');
select is(
  jsonb_build_array(
    pg_temp.problems('dos_bicis'),
    pg_temp.fact('50', 'rearSpokeHoles'),
    pg_temp.fact('49', 'rearSpokeHoles')),
  '[[{"key": "rearWheelBsdMm", "value": 584, "reason": "incompatible", "requires_key": "bikes.wheel_size", "requires_value": "29\""},
     {"key": "rearSpokeHoles", "value": 32, "reason": "line_without_bike"},
     {"key": "rearWheelBsdMm", "value": 622, "reason": "line_without_bike"}],
    null, null]'::jsonb,
  'con dos bicis y una línea ambigua o incompatible no termina ni escribe en otra bici');
select is(
  pg_temp.fact('50', 'rearWheelBsdMm'),
  null,
  'la rueda de la otra bici tampoco cambia en el cierre bloqueado');

-- ============================================================================
-- Después: el replay, la autoría y lo que cambió
-- ============================================================================

insert into results select 'marlin5', pg_temp.finish('065');
select is(
  jsonb_build_array(
    pg_temp.problems('marlin5'),
    public.job_part_change_writers_v1(pg_temp.id('065'))->(pg_temp.id('328')::text)),
  '[[], [{"key": "rearSpokeHoles", "value": 32}, {"key": "rearWheelBsdMm", "value": 622}]]'::jsonb,
  'el formulario lee que la llanta escribió sus dos datos');

insert into results select 'marlin5_entregado', pg_temp.finish('065', 'ENTREGADO');
select is(
  jsonb_build_array(pg_temp.problems('marlin5_entregado'), pg_temp.receipts('065')),
  '[[], ["job_completion:328:1:rearSpokeHoles=32,rearWheelBsdMm=622"]]'::jsonb,
  'entregar no repite el recibo');

-- El mecánico mide la rueda y dice 584 (hecho posterior, en la ficha).
update public.bike_profiles
   set technical_profile = jsonb_set(jsonb_set(jsonb_set(technical_profile,
         '{values,rearWheelBsdMm}', '584'), '{sources,rearWheelBsdMm}', '"mechanic"'),
         '{confirmed,rearWheelBsdMm}', 'true')
 where bike_id = 'e2840000-0000-4000-8000-000000000045';
insert into results select 'marlin5_despues',
  public.apply_job_installed_bike_facts_internal(
    'e2840000-0000-4000-8000-000000000001', pg_temp.id('065'), false);
select is(
  jsonb_build_array(
    pg_temp.problems('marlin5_despues'),
    pg_temp.fact('45', 'rearWheelBsdMm'),
    pg_temp.receipts('065'),
    public.job_part_change_writers_v1(pg_temp.id('065'))->(pg_temp.id('328')::text)),
  '[[{"key": "rearSpokeHoles", "value": 32, "reason": "incompatible", "requires_key": "rearTireBsdMm", "requires_value": "584"},
     {"key": "rearWheelBsdMm", "value": 622, "reason": "incompatible", "requires_key": "rearTireBsdMm", "requires_value": "584"}],
    [584, true, "mechanic"],
    ["job_completion:328:1:rearSpokeHoles=32,rearWheelBsdMm=622"],
    {"key": "rearSpokeHoles", "value": 32}]'::jsonb,
  'lo que el mecánico midió después no se pisa; volver a mirar lo dice, y la llanta ya no es autora del BSD');

-- Otro trabajo en la Xcaliber, después: un Voltage de 584 no calza con la
-- rueda de 622 que dejó la llanta; y con la U32 TL de 27,5 tampoco, porque
-- la bici sigue siendo 29''.
insert into results select 'xcaliber_voltage', pg_temp.finish('073');
insert into results select 'xcaliber_275', pg_temp.finish('074');
select is(
  jsonb_build_array(
    pg_temp.problems('xcaliber_voltage'),
    pg_temp.problems('xcaliber_275'),
    pg_temp.fact('32', 'rearWheelBsdMm')),
  '[[{"key": "rearWheelBsdMm", "value": 584, "reason": "incompatible", "requires_key": "rearWheelBsdMm", "requires_value": "622"}],
    [{"key": "rearSpokeHoles", "value": 28, "reason": "incompatible", "requires_key": "bikes.wheel_size", "requires_value": "29''''"},
     {"key": "rearWheelBsdMm", "value": 584, "reason": "incompatible", "requires_key": "bikes.wheel_size", "requires_value": "29''''"},
     {"key": "rearWheelBsdMm", "value": 584, "reason": "incompatible", "requires_key": "bikes.wheel_size", "requires_value": "29''''"}],
    [622, null, "job_completion"]]'::jsonb,
  'lo que otro trabajo escribió después se respeta, y el aro escrito sigue refutando');

-- ============================================================================
-- El trabajo terminado: la puerta
-- ============================================================================

-- La Hurricane: se le quita la marca a la llanta en el trabajo terminado.
insert into results select 'hurricane', pg_temp.finish('066');
update public.mechanic_job_items
   set service_configuration_data = '{}'
 where id = pg_temp.id('329');
select is(
  jsonb_build_array(
    pg_temp.fact('46', 'rearWheelBsdMm'),
    (select count(*)::integer from public.bike_events bi
      where bi.bike_id = 'e2840000-0000-4000-8000-000000000046'
        and bi.event_type = 'installed_fact_unsupported')),
  '[[622, null, "job_completion"], 2]'::jsonb,
  'quitar la marca guarda la línea, deja el dato y avisa de los dos');

-- La Cross: el Ardent ya escribió 622; una llanta de 584 no entra.
insert into results select 'cross', pg_temp.finish('067');
select throws_ok(
  $$insert into public.mechanic_job_items (
      id, tenant_id, job_id, job_bike_id, product_id, product_name, item_type, location_key,
      quantity, unit_price, service_configuration_data)
    values ('e2840000-0000-4000-8000-000000000350', 'e2840000-0000-4000-8000-000000000001',
      'e2840000-0000-4000-8000-000000000067',
      (select id from public.mechanic_job_bikes where job_id = 'e2840000-0000-4000-8000-000000000067'),
      'e2840000-0000-4000-8000-000000000203',
      'Llanta Weinmann U32 TL 27.5" Ojetillos 28H Presta Negro', 'product', 'rear', 1, 0,
      '{"part_change": [{"key": "rearWheelBsdMm", "value": 584}, {"key": "rearSpokeHoles", "value": 28}]}')$$,
  '23514',
  '«Llanta Weinmann U32 TL 27.5" Ojetillos 28H Presta Negro» no se guardó: 584 (27,5″/650b) en la rueda trasera no calza con el neumático que instala el trabajo (el neumático trasero es 622 (29″/700c)). En un trabajo terminado la línea y la ficha se guardan juntas: corrige la ficha o la línea.',
  'en un trabajo terminado, una llanta que no calza con su neumático no se guarda, y se nombra su BSD');

-- La Merak 2: la U32 TL ya escribió 622; un Voltage de 584 no entra, con
-- marca (su calce) ni sin ella (la llanta se mide con él).
insert into results select 'merak2', pg_temp.finish('068');
select throws_ok(
  $$insert into public.mechanic_job_items (
      id, tenant_id, job_id, job_bike_id, product_id, product_name, item_type, location_key,
      quantity, unit_price, service_configuration_data)
    values ('e2840000-0000-4000-8000-000000000351', 'e2840000-0000-4000-8000-000000000001',
      'e2840000-0000-4000-8000-000000000068',
      (select id from public.mechanic_job_bikes where job_id = 'e2840000-0000-4000-8000-000000000068'),
      'e2840000-0000-4000-8000-000000000233',
      'Neumatico Bicicleta Aro 27.5 X 2.10 Voltage Best', 'product', 'rear', 1, 0,
      '{"part_change": {"key": "rearWheelBsdMm", "value": 584}}')$$,
  '23514',
  '«Neumatico Bicicleta Aro 27.5 X 2.10 Voltage Best» no se guardó: 584 (27,5″/650b) en la rueda trasera no calza con la llanta que instala el trabajo (la llanta trasera es 622 (29″/700c)). En un trabajo terminado la línea y la ficha se guardan juntas: corrige la ficha o la línea.',
  'un neumático marcado que no calza con la llanta del trabajo no se guarda');
select throws_ok(
  $$insert into public.mechanic_job_items (
      id, tenant_id, job_id, job_bike_id, product_id, product_name, item_type, location_key,
      quantity, unit_price, service_configuration_data)
    values ('e2840000-0000-4000-8000-000000000352', 'e2840000-0000-4000-8000-000000000001',
      'e2840000-0000-4000-8000-000000000068',
      (select id from public.mechanic_job_bikes where job_id = 'e2840000-0000-4000-8000-000000000068'),
      'e2840000-0000-4000-8000-000000000233',
      'Neumatico Bicicleta Aro 27.5 X 2.10 Voltage Best', 'product', 'rear', 1, 0, '{}')$$,
  '23514',
  '«Neumatico Bicicleta Aro 27.5 X 2.10 Voltage Best» no se guardó: «Llanta Weinmann U32 TL 29" Ojetillos 32H Presta Negro», del mismo trabajo, no calza con este neumático (el neumático trasero es 584 (27,5″/650b)). En un trabajo terminado las líneas y la ficha se guardan juntas: corrige una de las dos líneas.',
  'ni sin marca: la llanta que ya escribió se mide con él');
select lives_ok(
  $$insert into public.mechanic_job_items (
      id, tenant_id, job_id, job_bike_id, product_id, product_name, item_type, location_key,
      quantity, unit_price, service_configuration_data)
    values ('e2840000-0000-4000-8000-000000000353', 'e2840000-0000-4000-8000-000000000001',
      'e2840000-0000-4000-8000-000000000068',
      (select id from public.mechanic_job_bikes where job_id = 'e2840000-0000-4000-8000-000000000068'),
      'e2840000-0000-4000-8000-000000000233',
      'Neumatico Bicicleta Aro 27.5 X 2.10 Voltage Best', 'product', 'front', 1, 0, '{}')$$,
  'en la otra rueda no queda preso');
select lives_ok(
  $$delete from public.mechanic_job_items where id = 'e2840000-0000-4000-8000-000000000331'$$,
  'borrar la llanta de un trabajo terminado se puede');
select is(
  pg_temp.fact('48', 'rearWheelBsdMm'),
  '[622, null, "job_completion"]'::jsonb,
  'y deja el dato con su aviso');

-- Mover de trabajo: una línea cualquiera sí (un rotor sin marca); un
-- neumático, aunque no tenga marca, no (su rueda se mide con él).
insert into public.mechanic_job_items (
  id, tenant_id, job_id, job_bike_id, product_id, product_name, item_type, location_key,
  quantity, unit_price, service_configuration_data)
values
  ('e2840000-0000-4000-8000-000000000354', 'e2840000-0000-4000-8000-000000000001',
   'e2840000-0000-4000-8000-000000000073',
   (select id from public.mechanic_job_bikes where job_id = 'e2840000-0000-4000-8000-000000000073'),
   'e2840000-0000-4000-8000-000000000241',
   'ROTOR FRENO DISCO SHIMANO SM-RT10 160MM AE', 'product', 'none', 1, 0, '{}'),
  ('e2840000-0000-4000-8000-000000000355', 'e2840000-0000-4000-8000-000000000001',
   'e2840000-0000-4000-8000-000000000073',
   (select id from public.mechanic_job_bikes where job_id = 'e2840000-0000-4000-8000-000000000073'),
   'e2840000-0000-4000-8000-000000000232',
   'MAXXIS ALAMBRE 29X2.25 M315P ARDENT', 'product', 'front', 1, 0, '{}');
select lives_ok(
  $$update public.mechanic_job_items
       set job_id = 'e2840000-0000-4000-8000-000000000074',
           job_bike_id = (select id from public.mechanic_job_bikes
                           where job_id = 'e2840000-0000-4000-8000-000000000074')
     where id = 'e2840000-0000-4000-8000-000000000354'$$,
  'una línea que no instala ni se mide pasa a otro trabajo');
select throws_like(
  $$update public.mechanic_job_items
       set job_id = 'e2840000-0000-4000-8000-000000000074',
           job_bike_id = (select id from public.mechanic_job_bikes
                           where job_id = 'e2840000-0000-4000-8000-000000000074')
     where id = 'e2840000-0000-4000-8000-000000000355'$$,
  '%no se movió: una línea que cambia la ficha de la bici no pasa a otro trabajo%',
  'un neumático sin marca no pasa a otro trabajo');

-- ============================================================================
-- Guardar varias líneas a la vez en un trabajo terminado
-- ============================================================================

-- La Totem 4423: maza de 36, llanta de 36 y su Enrayado, terminados.
insert into results select 'totem', pg_temp.finish('070');
select is(
  jsonb_build_array(pg_temp.problems('totem'), pg_temp.fact('51', 'rearSpokeHoles')),
  '[[], [36, true, "job_completion"]]'::jsonb,
  'la rueda de 36 quedó en la ficha');

-- Cambiarla a 32 línea por línea no se puede: siempre hay un paso que no
-- calza. Es la puerta inmediata que tiene cualquier escritor directo.
select throws_like(
  $$update public.mechanic_job_items
       set service_configuration_data = '{"hole_count": "32", "which_wheel": "rear"}'
     where id = 'e2840000-0000-4000-8000-000000000334'$$,
  '%«Llanta Weinmann U28 27.5" Ojetillos 36H Schrader Negro», del mismo trabajo, no calza con la rueda que arma esta línea%',
  'un Enrayado de 32 solo deja mal la llanta de 36 que ya escribió');
select throws_like(
  $$update public.mechanic_job_items
       set product_id = 'e2840000-0000-4000-8000-000000000201',
           product_name = 'Llanta FOSS F22 Aluminio Doble Pared con Ojetillos 29x32H',
           service_configuration_data = '{"part_change": {"key": "rearSpokeHoles", "value": 32}}'
     where id = 'e2840000-0000-4000-8000-000000000336'$$,
  '%no calza con la rueda que arma el trabajo (la rueda trasera lleva 36 rayos)%',
  'y una llanta de 32 sola no calza con el Enrayado de 36');

-- El comando de guardado lo escribe como un solo cambio: la puerta mira lo
-- que quedó, con el Enrayado primero como lo manda el formulario.
insert into results select 'totem_guardado', pg_temp.save('070', 'rueda-32',
  array['334', '335', '336'],
  jsonb_build_object(
    '334', jsonb_build_object('service_configuration_data',
      '{"hole_count": "32", "which_wheel": "rear"}'::jsonb),
    '335', jsonb_build_object(
      'product_id', pg_temp.id('223'),
      'product_name', 'Maza Trasera Freewheel Disco 32h Betta'),
    '336', jsonb_build_object(
      'product_id', pg_temp.id('201'),
      'product_name', 'Llanta FOSS F22 Aluminio Doble Pared con Ojetillos 29x32H',
      'service_configuration_data',
      '{"part_change": {"key": "rearSpokeHoles", "value": 32}}'::jsonb)));
select is(
  jsonb_build_array(
    (select result->'updated' from results where label = 'totem_guardado'),
    pg_temp.fact('51', 'rearSpokeHoles'),
    pg_temp.receipts('070'),
    (select count(*)::integer from public.mechanic_job_line_gate_deferrals)),
  '[3, [32, true, "job_completion"],
    ["job_completion:334:1:rearSpokeHoles=36", "job_completion:334:2:rearSpokeHoles=32",
     "job_completion:335:1:freehubType=threaded_freewheel",
     "job_completion:336:1:rearSpokeHoles=36", "job_completion:336:2:rearSpokeHoles=32"],
    0]'::jsonb,
  'maza, llanta y Enrayado de 32 en un guardado: se guarda, la ficha dice 32, y la espera de la puerta se cierra');
select is(
  (select count(*)::integer from public.bike_events bi
    where bi.bike_id = 'e2840000-0000-4000-8000-000000000051'
      and bi.event_type in ('installed_fact_incompatible', 'installed_fact_unsupported')),
  0,
  'sin avisos de los pasos intermedios');
-- La señal de sesión del borrador (revisión de Codex, 2026-09-29) ya no
-- abre nada: un escritor que la fija sigue con la puerta inmediata.
select set_config('vinabike.job_line_gate_job', pg_temp.id('070')::text, true);
select throws_like(
  $$update public.mechanic_job_items
       set service_configuration_data = '{"hole_count": "36", "which_wheel": "rear"}'
     where id = 'e2840000-0000-4000-8000-000000000334'$$,
  '%no calza con la rueda que arma esta línea%',
  'después del comando, la puerta vuelve a ser inmediata en la misma transacción, aunque se fije una señal de sesión');
select set_config('vinabike.job_line_gate_job', '', true);

-- La Orion 1: lo mismo, pero la maza nueva es de 28: lo que queda no calza.
insert into results select 'orion1', pg_temp.finish('071');
select throws_like(
  $$select pg_temp.save('071', 'rueda-28',
      array['337', '338', '339'],
      jsonb_build_object(
        '337', jsonb_build_object('service_configuration_data',
          '{"hole_count": "32", "which_wheel": "rear"}'::jsonb),
        '338', jsonb_build_object(
          'product_id', pg_temp.id('225'),
          'product_name', 'Maza trasera 28H rueda libre (supuesta)'),
        '339', jsonb_build_object(
          'product_id', pg_temp.id('201'),
          'product_name', 'Llanta FOSS F22 Aluminio Doble Pared con Ojetillos 29x32H',
          'service_configuration_data',
          '{"part_change": {"key": "rearSpokeHoles", "value": 32}}'::jsonb)))$$,
  '%«Enrayado + Centrado» no se guardó: «Maza trasera 28H rueda libre (supuesta)», del mismo trabajo, no calza con la rueda que arma esta línea (la rueda trasera lleva 32 rayos)%',
  'si lo que queda no calza, el guardado se rechaza con el mismo mensaje');
select is(
  jsonb_build_array(
    pg_temp.fact('52', 'rearSpokeHoles'),
    (select service_configuration_data from public.mechanic_job_items
      where id = pg_temp.id('337'))),
  '[[36, true, "job_completion"], {"hole_count": "36", "which_wheel": "rear"}]'::jsonb,
  'y nada queda a medias');

-- La Scott: HB-RM66 con SM-RT10 por una maza de 6 pernos con un Cyclami
-- flotante (el límite de 20260928130000). En el mismo trabajo, una llanta
-- delantera sin configuración (nula), como las líneas viejas.
insert into public.mechanic_job_items (
  id, tenant_id, job_id, job_bike_id, product_id, product_name, item_type, location_key,
  quantity, unit_price, service_configuration_data)
values ('e2840000-0000-4000-8000-000000000346', 'e2840000-0000-4000-8000-000000000001',
  'e2840000-0000-4000-8000-000000000072',
  (select id from public.mechanic_job_bikes where job_id = 'e2840000-0000-4000-8000-000000000072'),
  'e2840000-0000-4000-8000-000000000201',
  'Llanta FOSS F22 Aluminio Doble Pared con Ojetillos 29x32H', 'product', 'front', 1, 0, null);
insert into results select 'scott', pg_temp.finish('072');
select throws_like(
  $$update public.mechanic_job_items
       set product_id = 'e2840000-0000-4000-8000-000000000226',
           product_name = 'Maza delantera 36H 6 pernos (supuesta)',
           service_configuration_data = '{"part_change": {"key": "frontRotorMount", "value": "six_bolt"}}'
     where id = 'e2840000-0000-4000-8000-000000000340'$$,
  '%«ROTOR FRENO DISCO SHIMANO SM-RT10 160MM AE», del mismo trabajo, no calza con esta maza%',
  'línea por línea, la maza de 6 pernos deja mal el rotor Center Lock');
insert into results select 'scott_guardado', pg_temp.save('072', 'rotor-6-pernos',
  array['340', '341', '346'],
  jsonb_build_object(
    '346', jsonb_build_object('service_configuration_data', '{}'::jsonb),
    '340', jsonb_build_object(
      'product_id', pg_temp.id('226'),
      'product_name', 'Maza delantera 36H 6 pernos (supuesta)',
      'service_configuration_data',
      '{"part_change": {"key": "frontRotorMount", "value": "six_bolt"}}'::jsonb),
    '341', jsonb_build_object(
      'product_id', pg_temp.id('242'),
      'product_name', 'Disco de Freno Flotante 160mm Cyclami')));
select is(
  jsonb_build_array(
    (select result->'updated' from results where label = 'scott_guardado'),
    pg_temp.fact('53', 'frontRotorMount')),
  '[3, ["six_bolt", null, "job_completion"]]'::jsonb,
  'la maza y el rotor juntos, en un guardado, sí; una línea sin configuración en el mismo guardado no borra lo anotado');

-- ============================================================================
-- Lo que quedó: «Configurar» y las bicis del trabajo
-- ============================================================================

-- La Orion 3 (27,5″): marcar la U28 de 584 y, en el mismo guardado, dejar el
-- aro en 29″ por «Configurar». La puerta mira lo que quedó: el aro final
-- (revisión de Codex, 2026-09-29).
insert into results select 'orion3', pg_temp.finish('081');
select throws_like(
  $$select pg_temp.save('081', 'aro-29', array['373'],
      jsonb_build_object('373', jsonb_build_object('service_configuration_data',
        '{"part_change": [{"key": "rearWheelBsdMm", "value": 584}, {"key": "rearSpokeHoles", "value": 32}]}'::jsonb)),
      jsonb_build_array(jsonb_build_object(
        'bike_id', 'e2840000-0000-4000-8000-000000000057',
        'facts', jsonb_build_array(jsonb_build_object(
          'key', 'bikes.wheel_size', 'op', 'set', 'value', '29"',
          'expected', '27.5"', 'expected_confirmed', false)))))$$,
  '%«Llanta Weinmann U28 27.5" Ojetillos 32H Schrader Negro» no se guardó:%no calza con la ficha de la bici (aro 29")%',
  'una llanta de 584 con el aro que el mismo guardado deja en 29″: se rechaza');
select is(
  jsonb_build_array(
    (select wheel_size from public.bikes where id = 'e2840000-0000-4000-8000-000000000057'),
    pg_temp.fact('57', 'rearWheelBsdMm')),
  '["27.5\"", null]'::jsonb,
  'y nada queda a medias');

-- La Duel (29″): al revés, el mismo guardado deja el aro en 27,5″.
insert into results select 'duel', pg_temp.finish('083');
insert into results select 'duel_guardado', pg_temp.save('083', 'aro-27', array['374'],
  jsonb_build_object('374', jsonb_build_object('service_configuration_data',
    '{"part_change": [{"key": "rearWheelBsdMm", "value": 584}, {"key": "rearSpokeHoles", "value": 32}]}'::jsonb)),
  jsonb_build_array(jsonb_build_object(
    'bike_id', 'e2840000-0000-4000-8000-000000000062',
    'facts', jsonb_build_array(jsonb_build_object(
      'key', 'bikes.wheel_size', 'op', 'set', 'value', '27.5"',
      'expected', '29"', 'expected_confirmed', false)))));
select is(
  jsonb_build_array(
    (select wheel_size from public.bikes where id = 'e2840000-0000-4000-8000-000000000062'),
    pg_temp.fact('62', 'rearWheelBsdMm'),
    pg_temp.fact('62', 'rearSpokeHoles')),
  '["27.5\"", [584, null, "job_completion"], [32, null, "job_completion"]]'::jsonb,
  'con el aro que queda en 27,5″, la llanta de 584 se instala en el mismo guardado');

-- General es lo que el cliente compra aparte (dueño, 2026-10-01): una línea
-- de General no es de ninguna bici, tenga el trabajo una, dos o ninguna fila
-- de bicis (20261001195000).

-- La Marlin 6: la U32 TL en General de un trabajo de una sola bici. No es de
-- la Marlin: el cierre lo dice y no escribe su ficha.
insert into results select 'marlin6', pg_temp.finish('082');
select is(
  jsonb_build_array(pg_temp.problems('marlin6'), pg_temp.fact('58', 'rearWheelBsdMm')),
  '[[{"key": "rearSpokeHoles", "value": 32, "reason": "line_without_bike"},
     {"key": "rearWheelBsdMm", "value": 622, "reason": "line_without_bike"}],
    null]'::jsonb,
  'la llanta de General no es de la única bici: el cierre la informa sin escribir la ficha');
-- Asignada a su pestaña en el mismo guardado que agrega una segunda bici, el
-- cierre la instala en la Marlin y en nadie más.
insert into results select 'marlin6_asignada', pg_temp.save('082', 'segunda-bici-asignada',
  array['375'],
  jsonb_build_object('375', jsonb_build_object('job_bike_id',
    (select jb.id from public.mechanic_job_bikes jb
      where jb.job_id = pg_temp.id('082')
        and jb.bike_id = 'e2840000-0000-4000-8000-000000000058'))),
  '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'client_key', 'b2', 'bike_id', 'e2840000-0000-4000-8000-000000000059')));
insert into results select 'marlin6_terminada', pg_temp.finish('082');
select is(
  jsonb_build_array(
    (select count(*)::integer from public.mechanic_job_bikes where job_id = pg_temp.id('082')),
    pg_temp.problems('marlin6_terminada'),
    pg_temp.fact('58', 'rearWheelBsdMm'),
    pg_temp.fact('59', 'rearWheelBsdMm'),
    (select count(*)::integer from public.mechanic_job_line_gate_deferrals)),
  '[2, [], [622, null, "job_completion"], null, 0]'::jsonb,
  'asignada a su bici, la llanta se instala en la Marlin; la segunda bici no la toca');

-- La Marlin 4: la U32 TL en su pestaña. Una segunda bici agregada directo,
-- sin el comando, no cambia de quién es ninguna línea.
insert into results select 'marlin4', pg_temp.finish('084');
select lives_ok(
  $$insert into public.mechanic_job_bikes (tenant_id, job_id, bike_id)
    values ('e2840000-0000-4000-8000-000000000001',
            'e2840000-0000-4000-8000-000000000084',
            'e2840000-0000-4000-8000-000000000059')$$,
  'una segunda bici agregada directo se acepta: la llanta sigue en su pestaña');
select is(
  jsonb_build_array(pg_temp.problems('marlin4'), pg_temp.fact('63', 'rearWheelBsdMm'),
                    public.job_line_bike_internal('e2840000-0000-4000-8000-000000000001',
                                                  pg_temp.id('376'))),
  jsonb_build_array('[]'::jsonb, '[622, null, "job_completion"]'::jsonb,
                    'e2840000-0000-4000-8000-000000000063'),
  'y la llanta sigue siendo de la Marlin 4');

-- La Orion 6 es de los trabajos viejos, sin filas de bicis: sus líneas están
-- en General (el formulario ya las cargaba así) y la cabecera no las hace de
-- su bici.
insert into results select 'orion6', pg_temp.finish('085');
select is(
  jsonb_build_array(pg_temp.problems('orion6'), pg_temp.fact('64', 'rearWheelBsdMm')),
  '[[{"key": "rearSpokeHoles", "value": 32, "reason": "line_without_bike"},
     {"key": "rearWheelBsdMm", "value": 622, "reason": "line_without_bike"}],
    null]'::jsonb,
  'sin filas de bicis, la llanta no es de la bici de la cabecera');

-- La Marlin 8 y la Fuel EX: la llanta de General no es de ninguna. Quitar la
-- Fuel (sin líneas propias) tampoco la hace de la Marlin; asignada a su
-- pestaña, el mismo cierre reintentado la instala.
insert into results select 'marlin8', pg_temp.finish('086');
select is(
  jsonb_build_array(
    (select jsonb_agg(distinct problem->>'reason') from results r,
       jsonb_array_elements(coalesce(r.result->'installed_bike_facts'->'problems',
                                   r.result->'problems')) problem
      where r.label = 'marlin8'),
    pg_temp.fact('66', 'rearWheelBsdMm')),
  '[["line_without_bike"], null]'::jsonb,
  'con dos bicis, la llanta de General bloquea el cierre');
delete from public.mechanic_job_bikes
 where id = 'e2840000-0000-4000-8000-000000000862';
insert into results select 'marlin8_una_bici', pg_temp.finish('086');
select is(
  jsonb_build_array(
    (select jsonb_agg(distinct problem->>'reason') from results r,
       jsonb_array_elements(coalesce(r.result->'installed_bike_facts'->'problems',
                                   r.result->'problems')) problem
      where r.label = 'marlin8_una_bici'),
    pg_temp.fact('66', 'rearWheelBsdMm')),
  '[["line_without_bike"], null]'::jsonb,
  'quitada la otra bici, la llanta de General sigue sin ser de la Marlin');
update public.mechanic_job_items
   set job_bike_id = (select jb.id from public.mechanic_job_bikes jb
                       where jb.job_id = pg_temp.id('086'))
 where id = pg_temp.id('378');
insert into results select 'marlin8_corregida', pg_temp.finish('086');
select is(
  jsonb_build_array(pg_temp.problems('marlin8_corregida'),
                    pg_temp.fact('66', 'rearWheelBsdMm'),
                    pg_temp.fact('66', 'rearSpokeHoles')),
  '[[], [622, null, "job_completion"], [32, null, "job_completion"]]'::jsonb,
  'asignada a la Marlin, el mismo cierre reintentado la instala');

-- La Orion 8 (28 atrás): la FOSS de 32 en su pestaña y una maza de 32 sin
-- marca en General. Esa maza no es de la Orion: la llanta se mide con la
-- maza de 28 de su ficha y el cierre lo dice. Asignada la maza a la Orion,
-- la llanta entra, y una segunda bici ya no le quita nada.
insert into results select 'orion8', pg_temp.finish('087');
select is(
  jsonb_build_array(pg_temp.problems('orion8'), pg_temp.fact('68', 'rearSpokeHoles')),
  '[[{"key": "rearSpokeHoles", "value": 32, "reason": "incompatible", "requires_key": "rearHubSpokeHoles", "requires_value": "28"}],
    [28, true, "mechanic"]]'::jsonb,
  'la maza de General no es de la Orion: la llanta de 32 no calza con su maza de 28');
update public.mechanic_job_items
   set job_bike_id = 'e2840000-0000-4000-8000-000000000871'
 where id = pg_temp.id('381');
insert into results select 'orion8_asignada', pg_temp.finish('087');
select is(
  jsonb_build_array(pg_temp.problems('orion8_asignada'), pg_temp.fact('68', 'rearSpokeHoles')),
  '[[], [32, null, "job_completion"]]'::jsonb,
  'con la maza de 32 en su pestaña, la llanta de 32 entra');
select lives_ok(
  $$insert into public.mechanic_job_bikes (tenant_id, job_id, bike_id)
    values ('e2840000-0000-4000-8000-000000000001',
            'e2840000-0000-4000-8000-000000000087',
            'e2840000-0000-4000-8000-000000000069')$$,
  'una segunda bici no le quita a la Orion la maza de su pestaña');

-- La Orion 9: su fila de bici no se va a otro trabajo dejando la llanta de su
-- pestaña sin bici (segunda revisión de Codex, 2026-09-29).
insert into results select 'orion9', pg_temp.finish('088');
select throws_like(
  $$update public.mechanic_job_bikes
       set job_id = 'e2840000-0000-4000-8000-000000000089'
     where id = 'e2840000-0000-4000-8000-000000000881'$$,
  '%no dice de qué bici del trabajo es%',
  'mover la fila de bici a otro trabajo deja sin bici la llanta que instaló: se rechaza');

select * from finish();
rollback;
