begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select no_plan();

-- Dirección y cockpit (20261002170000). Las piezas de toda la bici van sin
-- rueda: la horquilla cambia el tubo de dirección, el manubrio su abrazadera
-- y su zona de mandos, la tija su diámetro (un suplemento no) y su tipo.
-- Manillas, mandos y puños tienen que calzar con la zona de mandos: si la
-- ficha no lo sabe, lo anotan. La potencia no está en la relación (una más
-- grande aprieta el manubrio con laina): la revisa la app al buscarla.
--
-- Datos reales (producción, lectura del 2026-10-02): los productos por su
-- nombre y lo que dice su ficha técnica (manubrio 31.8 con zona 22.2,
-- horquilla cónica, tija Kalloy 27.2 rígida, mando 22.2 y uno de ruta 23.8).
-- Las bicis, sus fichas y los trabajos son supuestos.
--
-- La base local no trae el motor de fichas: el lector del producto se
-- reemplaza en esta transacción por dos tablas.

-- ============================================================================
-- La relación y cómo se dice
-- ============================================================================

select is(
  (select jsonb_agg(jsonb_build_object(
            'spec', spec_key, 'key', bike_fact_key, 'family', template_key,
            'rule', on_mismatch, 'decimals', value_decimals,
            'range', jsonb_build_array(min_value, max_value))
          order by bike_fact_key, template_key)
     from public.bike_fact_spec_links
    where position = 'none'),
  '[{"key": "controlsBarDiameterMm", "spec": "handlebar_clamp_mm", "family": "brake_lever", "rule": "conflict", "range": [20, 30], "decimals": 1},
    {"key": "controlsBarDiameterMm", "spec": "grip_bar_nominal_diameter_mm", "family": "grip", "rule": "conflict", "range": [20, 30], "decimals": 1},
    {"key": "controlsBarDiameterMm", "spec": "grip_area_diameter_mm", "family": "handlebar", "rule": "change", "range": [20, 30], "decimals": 1},
    {"key": "controlsBarDiameterMm", "spec": "handlebar_clamp_mm", "family": "shifter", "rule": "conflict", "range": [20, 30], "decimals": 1},
    {"key": "handlebarClampMm", "spec": "bar_clamp_diameter_mm", "family": "handlebar", "rule": "change", "range": [20, 40], "decimals": 1},
    {"key": "seatpostDiameterMm", "spec": "seatpost_diameter_mm", "family": "seatpost", "rule": "change", "range": [20, 36], "decimals": 1},
    {"key": "seatpostKind", "spec": "seatpost_kind", "family": "seatpost", "rule": "change", "range": [0, 0], "decimals": 0},
    {"key": "steererFit", "spec": "steerer_fit", "family": "fork", "rule": "change", "range": [0, 0], "decimals": 0}]'::jsonb,
  'las piezas de toda la bici van sin rueda, con su regla y sus décimas');
select is(
  (select count(*)::integer from public.bike_fact_spec_links
    where position in ('front', 'rear')),
  19,
  'las 19 filas de rueda siguen iguales');
select throws_ok(
  $$insert into public.bike_fact_spec_links (
      spec_key, position, bike_fact_key, component_label, unit, min_value,
      max_value, template_key, on_mismatch, value_map, value_decimals)
    values ('x', 'none', 'x', 'x', null, 0, 0, 'x', 'change',
            '{"a": "b"}'::jsonb, 1)$$,
  '23514', null,
  'un código no lleva décimas');

select is(
  jsonb_build_array(
    public.bike_fact_link_value_internal(
      (select l from public.bike_fact_spec_links l
        where l.spec_key = 'bar_clamp_diameter_mm' and l.template_key = 'handlebar'),
      '{"value": 31.8}'),
    public.bike_fact_link_value_internal(
      (select l from public.bike_fact_spec_links l
        where l.spec_key = 'bar_clamp_diameter_mm' and l.template_key = 'handlebar'),
      '{"value": "25,4"}'),
    public.bike_fact_link_value_internal(
      (select l from public.bike_fact_spec_links l
        where l.spec_key = 'bar_clamp_diameter_mm' and l.template_key = 'handlebar'),
      '{"value": 31.85}'),
    public.bike_fact_link_value_internal(
      (select l from public.bike_fact_spec_links l
        where l.spec_key = 'seatpost_diameter_mm'),
      '{"value": 27.20}'),
    public.bike_fact_link_value_internal(
      (select l from public.bike_fact_spec_links l
        where l.spec_key = 'steerer_fit'),
      '{"value": "Tapered 1 1/8\" – 1.5\""}'),
    public.bike_fact_link_value_internal(
      (select l from public.bike_fact_spec_links l
        where l.spec_key = 'rotor_diameter_mm_value' and l.position = 'rear'),
      '{"value": 180.5}')),
  '[31.8, 25.4, null, 27.2, "tapered_1_1_8_1_5", null]'::jsonb,
  'una medida con décimas se toma tal cual; con más décimas de las que acepta, o en una fila entera, no');

select is(
  jsonb_build_array(
    public.installed_bike_fact_label('handlebarClampMm', '31.8'),
    public.installed_bike_fact_label('controlsBarDiameterMm', '22.2'),
    public.installed_bike_fact_label('seatpostDiameterMm', '27.2'),
    public.installed_bike_fact_label('steererFit', '"straight_1_1_8"'),
    public.installed_bike_fact_label('seatpostKind', '"dropper"'),
    public.installed_bike_fact_label('rearWheelBsdMm', '622'),
    public.installed_bike_fact_label('frontRotorSizeMm', '180'),
    public.bike_fact_requirement_text('controlsBarDiameterMm', '23.8'),
    public.bike_fact_requirement_text('handlebarClampMm', '25.4')),
  '["31,8 mm en la abrazadera del manubrio", "22,2 mm en la zona de mandos",
    "27,2 mm en la tija", "1⅛″ en el tubo de horquilla", "tija telescópica",
    "622 (29″/700c) en la rueda trasera", "180 mm en el rotor delantero",
    "la zona de mandos del manubrio es de 23,8 mm",
    "la abrazadera del manubrio es de 25,4 mm"]'::jsonb,
  'lo instalado y lo que no calza se dicen con coma decimal y con el nombre del taller');
select ok(
  public.bike_fact_requirement_advice('controlsBarDiameterMm') like 'Manillas, mandos y puños calzan%'
  and public.bike_fact_requirement_advice('handlebarClampMm') like 'Una potencia aprieta el manubrio%'
  and public.bike_fact_requirement_advice('frontWheelBsdMm') like 'Revisa la medida del neumático%',
  'cada rechazo trae qué hacer; los de antes, igual');

-- ============================================================================
-- Fixture
-- ============================================================================

insert into public.tenants (id, shop_name) values
  ('e2850000-0000-4000-8000-000000000001', 'Taller cockpit');

-- El alta del taller deja la sesión con su id: se limpia.
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('e2850000-0000-4000-8000-000000000099', 'authenticated', 'authenticated',
   'cockpit@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now());

insert into public.user_profiles (user_id, tenant_id, role) values
  ('e2850000-0000-4000-8000-000000000099',
   'e2850000-0000-4000-8000-000000000001', 'admin');

insert into public.customers (id, tenant_id, name) values
  ('e2850000-0000-4000-8000-000000000010',
   'e2850000-0000-4000-8000-000000000001', 'Cliente cockpit');

insert into public.bikes (id, tenant_id, customer_id, brand, model, bike_type)
select ('e2850000-0000-4000-8000-0000000000' || b.n)::uuid,
       'e2850000-0000-4000-8000-000000000001',
       'e2850000-0000-4000-8000-000000000010', b.brand, b.model, b.kind
  from (values
    ('31', 'Mountain Gear', 'E-Falcon', 'mountain_hardtail'),
    ('32', 'Oxford', 'Merak 1', 'mountain_hardtail'),
    ('33', 'Specialized', 'Allez', 'road'),
    ('34', 'Trek', 'Marlin 5', 'mountain_hardtail'),
    ('35', 'Trek', 'FX 2', 'hybrid'),
    ('36', 'Oxford', 'Orion 4', 'mountain_hardtail')
  ) b(n, brand, model, kind);

-- El Allez dice 23,8 en la zona de mandos (un manubrio de ruta) y la Marlin
-- una abrazadera de 25,4.
insert into public.bike_profiles (tenant_id, bike_id, technical_profile)
select 'e2850000-0000-4000-8000-000000000001',
       ('e2850000-0000-4000-8000-0000000000' || p.n)::uuid,
       jsonb_build_object(
         'values', p.facts,
         'sources', (select coalesce(jsonb_object_agg(k, 'mechanic'), '{}'::jsonb)
                       from jsonb_object_keys(p.facts) k),
         'confirmed', (select coalesce(jsonb_object_agg(k, true), '{}'::jsonb)
                         from jsonb_object_keys(p.facts) k))
  from (values
    ('33', '{"controlsBarDiameterMm": 23.8}'::jsonb),
    ('34', '{"handlebarClampMm": 25.4}'::jsonb)
  ) p(n, facts);

insert into public.products (id, tenant_id, name, category_name)
select ('e2850000-0000-4000-8000-000000000' || p.n)::uuid,
       'e2850000-0000-4000-8000-000000000001', p.name, p.category
  from (values
    ('201', 'Manubrio MTB Aluminio 31.8 x 720mm', 'Manubrios'),
    ('202', 'Horquilla Suspensión 29" Cónica Eje 15mm', 'Horquillas'),
    ('203', 'Tija Kalloy 27.2 x 400', 'Tijas'),
    ('204', 'Suplemento de tija 27.2 a 30.9', 'Tijas'),
    ('205', 'Mando Shimano Altus SL-M315 8v', 'Mandos'),
    ('206', 'Potencia 31.8 x 60mm', 'Potencias'),
    ('207', 'Puños Ergon GA2', 'Puños')
  ) p(n, name, category);

create temporary table test_product_templates (
  product_id uuid primary key,
  template_key text
);
insert into test_product_templates
select ('e2850000-0000-4000-8000-000000000' || t.n)::uuid, t.template_key
  from (values
    ('201', 'handlebar'), ('202', 'fork'), ('203', 'seatpost'),
    ('204', 'seatpost'), ('205', 'shifter'), ('206', 'stem'), ('207', 'grip')
  ) t(n, template_key);

create temporary table test_product_specs (
  product_id uuid,
  spec_key text,
  value jsonb,
  verified boolean default false
);
insert into test_product_specs (product_id, spec_key, value, verified)
select ('e2850000-0000-4000-8000-000000000' || s.n)::uuid, s.spec_key,
       s.value::jsonb, s.verified
  from (values
    ('201', 'bar_clamp_diameter_mm', '31.8', false),
    ('201', 'grip_area_diameter_mm', '22.2', false),
    ('202', 'steerer_fit', '"Tapered 1 1/8\" – 1.5\""', true),
    ('203', 'seatpost_diameter_mm', '27.2', false),
    ('203', 'seatpost_kind', '"Rígida"', false),
    ('204', 'seatpost_diameter_mm', '30.9', false),
    ('204', 'seatpost_kind', '"Suplemento (shim)"', false),
    ('205', 'handlebar_clamp_mm', '22.2', false),
    ('206', 'bar_clamp_diameter_mm', '31.8', false),
    ('207', 'grip_bar_nominal_diameter_mm', '22.2', false)
  ) s(n, spec_key, value, verified);

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
select ('e2850000-0000-4000-8000-000000000' || j.n)::uuid,
       'e2850000-0000-4000-8000-000000000001',
       'e2850000-0000-4000-8000-000000000010',
       ('e2850000-0000-4000-8000-0000000000' || j.bike)::uuid,
       'PG-CKP-' || j.n,
       'e2850000-0000-4000-8000-000000000099'
  from (values ('051', '31'), ('052', '32'), ('053', '33'), ('054', '34'),
               ('055', '35'), ('056', '36')) j(n, bike);

insert into public.mechanic_job_bikes (tenant_id, job_id, bike_id)
select 'e2850000-0000-4000-8000-000000000001', j.id, j.bike_id
  from public.mechanic_jobs j
 where j.tenant_id = 'e2850000-0000-4000-8000-000000000001';

-- Las líneas sin rueda, con la marca que deja la app al guardarlas.
insert into public.mechanic_job_items (
  id, tenant_id, job_id, job_bike_id, product_id, product_name, item_type,
  location_key, quantity, unit_price, service_configuration_data, created_at
)
select ('e2850000-0000-4000-8000-000000000' || l.n)::uuid,
       'e2850000-0000-4000-8000-000000000001',
       ('e2850000-0000-4000-8000-000000000' || l.job)::uuid,
       (select jb.id from public.mechanic_job_bikes jb
         where jb.job_id = ('e2850000-0000-4000-8000-000000000' || l.job)::uuid),
       ('e2850000-0000-4000-8000-000000000' || l.product)::uuid,
       p.name, 'product', l.location_key, 1, 19990,
       coalesce(l.data::jsonb, '{}'::jsonb),
       now() + (l.n::integer * interval '1 millisecond')
  from (values
    -- La E-Falcon: manubrio, horquilla, tija y puños.
    ('301', '051', '201', 'none', '{"part_change": [{"key": "controlsBarDiameterMm", "value": 22.2}, {"key": "handlebarClampMm", "value": 31.8}]}'),
    ('302', '051', '202', 'none', '{"part_change": {"key": "steererFit", "value": "tapered_1_1_8_1_5"}}'),
    ('303', '051', '203', 'none', '{"part_change": [{"key": "seatpostDiameterMm", "value": 27.2}, {"key": "seatpostKind", "value": "rigid"}]}'),
    ('304', '051', '207', 'none', '{"part_change": {"key": "controlsBarDiameterMm", "value": 22.2}}'),
    -- La Merak: un mando de 22,2 en una bici sin ficha.
    ('305', '052', '205', 'none', '{"part_change": {"key": "controlsBarDiameterMm", "value": 22.2}}'),
    -- La Orion: un suplemento marcado como si fuera la tija (la app no lo
    -- marca; una versión vieja o una llamada directa, sí).
    ('306', '056', '204', 'none', '{"part_change": {"key": "seatpostDiameterMm", "value": 30.9}}'),
    -- El Allez (23,8): un mando de MTB de 22,2.
    ('307', '053', '205', 'none', '{"part_change": {"key": "controlsBarDiameterMm", "value": 22.2}}'),
    -- La Marlin (25,4): una potencia de 31,8, que va con laina.
    ('308', '054', '206', 'none', '{}'),
    -- La FX: un mando «derecho» no es de toda la bici.
    ('309', '055', '205', 'right', '{"part_change": {"key": "controlsBarDiameterMm", "value": 22.2}}')
  ) l(n, job, product, location_key, data)
  join public.products p
    on p.id = ('e2850000-0000-4000-8000-000000000' || l.product)::uuid;

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'e2850000-0000-4000-8000-000000000099', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub',
  'e2850000-0000-4000-8000-000000000099', true);

create temporary table status_ids as
select code, id
  from public.job_statuses
 where tenant_id = 'e2850000-0000-4000-8000-000000000001';

create temporary table results (label text primary key, result jsonb);

create or replace function pg_temp.id(p_n text)
returns uuid
language sql
as $$ select ('e2850000-0000-4000-8000-000000000' || p_n)::uuid $$;

create or replace function pg_temp.fact(p_bike text, p_key text)
returns jsonb
language sql
as $$
  select jsonb_build_array(
           bp.technical_profile->'values'->p_key,
           bp.technical_profile->'confirmed'->p_key,
           bp.technical_profile->'sources'->p_key)
    from public.bike_profiles bp
   where bp.bike_id = ('e2850000-0000-4000-8000-0000000000' || p_bike)::uuid
$$;

create or replace function pg_temp.finish(p_job text)
returns jsonb
language plpgsql
as $$
declare
  v_detail text;
  v_hint text;
begin
  return public.transition_mechanic_job_status(
    pg_temp.id(p_job),
    (select id from status_ids where code = 'FINALIZADO'),
    'cockpit-' || p_job);
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
  select coalesce(jsonb_agg(jsonb_build_object(
             'key', problem->'key', 'value', problem->'value',
             'reason', problem->'reason',
             'requires_value', problem->'requires_value')
           order by problem->>'key', problem->>'reason'), '[]'::jsonb)
    from results r
   cross join lateral jsonb_array_elements(
           coalesce(r.result->'installed_bike_facts'->'problems', r.result->'problems')) problem
   where r.label = p_label
$$;

-- ============================================================================
-- Lo que el taller instala
-- ============================================================================

select is(
  public.job_line_part_change_internal(
    'e2850000-0000-4000-8000-000000000001', pg_temp.id('301'), 'handlebarClampMm')
    - 'link_id',
  '{"key": "handlebarClampMm", "value": 31.8, "spec_key": "bar_clamp_diameter_mm",
    "position": "none", "verified": false, "on_mismatch": "change",
    "template_key": "handlebar"}'::jsonb,
  'la marca de una medida con décimas calza por valor');

insert into results select 'falcon', pg_temp.finish('051');
select is(
  jsonb_build_array(
    pg_temp.problems('falcon'),
    pg_temp.fact('31', 'handlebarClampMm'),
    pg_temp.fact('31', 'controlsBarDiameterMm'),
    pg_temp.fact('31', 'steererFit'),
    pg_temp.fact('31', 'seatpostDiameterMm'),
    pg_temp.fact('31', 'seatpostKind')),
  '[[], [31.8, null, "job_completion"], [22.2, null, "job_completion"],
    ["tapered_1_1_8_1_5", true, "job_completion"],
    [27.2, null, "job_completion"], ["rigid", null, "job_completion"]]'::jsonb,
  'la E-Falcon: manubrio, horquilla y tija entran a la ficha; los puños calzan con el manubrio nuevo; sólo lo verificado queda confirmado');

insert into results select 'merak', pg_temp.finish('052');
select is(
  jsonb_build_array(
    pg_temp.problems('merak'),
    pg_temp.fact('32', 'controlsBarDiameterMm')),
  '[[], [22.2, null, "job_completion"]]'::jsonb,
  'la Merak: el mando anota la zona de mandos que la ficha no sabía, y le abre la ficha');

insert into results select 'orion', pg_temp.finish('056');
select is(
  jsonb_build_array(
    (select result->'blocked' from results where label = 'orion'),
    pg_temp.problems('orion'),
    pg_temp.fact('36', 'seatpostDiameterMm')),
  '[true, [{"key": "seatpostDiameterMm", "value": 30.9, "reason": "stale_change", "requires_value": null}], null]'::jsonb,
  'la Orion: un suplemento no es la tija; su marca no vale y el trabajo no se termina con ella');

insert into results select 'allez', pg_temp.finish('053');
select is(
  jsonb_build_array(
    pg_temp.problems('allez'),
    pg_temp.fact('33', 'controlsBarDiameterMm')),
  '[[{"key": "controlsBarDiameterMm", "value": 22.2, "reason": "incompatible", "requires_value": "23.8"}],
    [23.8, true, "mechanic"]]'::jsonb,
  'el Allez: un mando de 22,2 no calza en un manubrio de ruta de 23,8 y la ficha no cambia');
select is(
  (select result->'blocked' from results where label = 'allez'),
  'true'::jsonb,
  'y el trabajo no se termina hasta corregir la línea o la ficha');

insert into results select 'marlin', pg_temp.finish('054');
select is(
  jsonb_build_array(
    (select coalesce(result->'blocked', 'false'::jsonb) from results where label = 'marlin'),
    pg_temp.problems('marlin'),
    pg_temp.fact('34', 'handlebarClampMm')),
  '[false, [], [25.4, true, "mechanic"]]'::jsonb,
  'la Marlin: una potencia de 31,8 aprieta el manubrio de 25,4 con laina; el trabajo se termina y la ficha no cambia');

insert into results select 'fx', pg_temp.finish('055');
select is(
  jsonb_build_array(pg_temp.problems('fx'), pg_temp.fact('35', 'controlsBarDiameterMm')),
  '[[{"key": "controlsBarDiameterMm", "value": 22.2, "reason": "stale_change", "requires_value": null}], null]'::jsonb,
  'la FX: un mando con lado no cambia la ficha de toda la bici');

-- ============================================================================
-- La puerta
-- ============================================================================

select throws_like(
  $$select public.patch_bike_technical_facts_v1(
      'cockpit-range', 'e2850000-0000-4000-8000-000000000035',
      'e2850000-0000-4000-8000-000000000055', 'service_wizard',
      '[{"key": "handlebarClampMm", "op": "set", "value": 45, "expected": null, "expected_confirmed": false}]')$$,
  '%out of its workshop range%',
  'una abrazadera de 45 mm es un error de tipeo');
select throws_like(
  $$select public.patch_bike_technical_facts_v1(
      'cockpit-vocab', 'e2850000-0000-4000-8000-000000000035',
      'e2850000-0000-4000-8000-000000000055', 'service_wizard',
      '[{"key": "steererFit", "op": "set", "value": "tapered", "expected": null, "expected_confirmed": false}]')$$,
  '%unknown value%',
  'un tubo de horquilla fuera del registro no entra');
select lives_ok(
  $$select public.patch_bike_technical_facts_v1(
      'cockpit-ok', 'e2850000-0000-4000-8000-000000000035',
      'e2850000-0000-4000-8000-000000000055', 'service_wizard',
      '[{"key": "seatpostDiameterMm", "op": "set", "value": 31.6, "expected": null, "expected_confirmed": false},
        {"key": "seatpostKind", "op": "set", "value": "dropper", "expected": null, "expected_confirmed": false}]')$$,
  'una tija de 31,6 telescópica entra');
select is(
  pg_temp.fact('35', 'seatpostDiameterMm'),
  '[31.6, true, "mechanic"]'::jsonb,
  'confirmada por quien la eligió');

select * from finish();
rollback;
