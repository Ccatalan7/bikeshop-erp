-- Deployment status: APPLIED to production 2026-10-03, read-back verified;
-- the history pass wrote 31 facts on 27 bikes, all unconfirmed.
-- Dirección y cockpit en la ficha de la bici (lienzo «Bicicletas — lo que
-- falta», 3 de 3; el dueño: «aplica 2 y 3», 2026-10-02). La sección 6 de la
-- hoja deja de estar vacía y se llena con lo que el taller instala, no a mano
-- (BIKE_WORKSHOP_MASTER_SCHEMA.md, «Dirección y cockpit»; wiki
-- `docs/wiki/compatibilidad/paginas/direccion.md` y
-- `manubrio-potencia-y-tija.md`).
--
-- Lo que dicen los datos de producción (2026-10-02, sólo lectura):
--
-- * Fichas técnicas con la medida: 10 horquillas (`steerer_fit`: 9 «1 1/8"
--   (28.6 mm)», 1 cónica), 10 manubrios (`bar_clamp_diameter_mm` 31.8 o
--   25.4; 12 con `grip_area_diameter_mm` 22.2), 14 potencias
--   (`bar_clamp_diameter_mm` 31.8 o 25.4), 13 tijas (`seatpost_diameter_mm`
--   22.2 a 31.6; 13 «Rígida»), 45 manillas y mandos (`handlebar_clamp_mm`
--   22.2; un mando 23.8) y 27 puños (`grip_bar_nominal_diameter_mm` 22.2).
--   Ninguna dirección dice su SHIS: la dirección queda en la hoja, a mano,
--   hasta que el inventario la diga.
-- * Instalado de verdad (trabajos entregados): 4 manubrios en 4 bicis, 2
--   tijas, 1 potencia, 0 horquillas; 7 manillas, 14 mandos y 17 puños en unas
--   20 bicis. Casi todas las líneas van sin rueda (`location_key = 'none'`).
--
-- Lo que se decidió con eso:
--
-- * La relación única (`bike_fact_spec_links`) admite piezas de toda la bici:
--   posición `none`, la de esas líneas. Una línea con lado (una manilla
--   «izquierda») no cambia la ficha.
-- * Medidas con décimas: 31,8; 22,2; 27,2. La fila dice cuántos decimales
--   acepta (`value_decimals`); un valor con más no se redondea, no se toma.
-- * Cambian la ficha (`change`): la horquilla el tubo de dirección
--   (`steererFit`), el manubrio su abrazadera (`handlebarClampMm`) y su zona
--   de mandos (`controlsBarDiameterMm`), la tija su diámetro
--   (`seatpostDiameterMm`, sin contar un suplemento) y su tipo
--   (`seatpostKind`).
-- * Tienen que calzar (`conflict`): manillas, mandos y puños con la zona de
--   mandos. Si la ficha no lo sabe, lo anotan; si dice otra medida, no
--   calzan: no hay laina que lo cambie. Una manilla que aprieta 22,2 dice que
--   el manubrio es de 22,2 ahí: es evidencia, no un supuesto.
-- * La potencia queda fuera de la relación: una de 31,8 aprieta un manubrio
--   de 25,4 con laina (y una de 28,6 un tubo recto o uno cónico), así que su
--   medida no dice la del manubrio ni la de la horquilla, y una distinta no
--   es «no calza». La revisa la matriz de la app al buscarla: más chica que
--   el manubrio no entra, más grande va con laina (revisión de Codex,
--   2026-10-02: la primera versión bloqueaba terminar el trabajo).
-- * La pasada sobre el historial: la misma relación sobre las líneas de
--   trabajos terminados o entregados, lo último de cada bici y dato, sólo
--   donde la ficha no lo sabe. No marca las líneas viejas (la factura pagada
--   protege sus productos: `guard_paid_workshop_child_mutation`) ni deja
--   recibos de línea (el aplicador los leería como algo que la línea ya no
--   respalda): escribe la ficha como la puerta (origen `job_completion`, sin
--   confirmar salvo que la ficha del producto esté verificada) y lo dice en la
--   historia de la bici.
--
-- Depende de `20260928140000`.
begin;

-- ============================================================================
-- La relación: piezas de toda la bici y medidas con décimas
-- ============================================================================

alter table public.bike_fact_spec_links
  drop constraint if exists bike_fact_spec_links_position_check;
alter table public.bike_fact_spec_links
  add constraint bike_fact_spec_links_position_check
  check (position in ('front', 'rear', 'none'));

alter table public.bike_fact_spec_links
  add column if not exists value_decimals smallint not null default 0;
alter table public.bike_fact_spec_links
  drop constraint if exists bike_fact_spec_links_value_decimals_check;
alter table public.bike_fact_spec_links
  add constraint bike_fact_spec_links_value_decimals_check
  check (
    value_decimals between 0 and 2
    and (value_decimals = 0 or (value_map is null and constant_value is null))
  );

comment on column public.bike_fact_spec_links.value_decimals is
  'Decimales que acepta la medida (31,8 mm: 1). Un valor con más no se redondea: no se toma.';

insert into public.bike_fact_spec_links (
  spec_key, position, bike_fact_key, component_label, component_article,
  unit, requires_fact_key, requires_fact_values, min_value, max_value,
  template_key, on_mismatch, value_map, constant_value, fits,
  product_condition, value_decimals
) values
  -- La horquilla cambia el tubo de dirección de la bici.
  ('steerer_fit', 'none', 'steererFit', 'tubo de horquilla', 'el',
   null, null, '{}', 0, 0, 'fork', 'change',
   jsonb_build_object(
     '1" (25.4 mm)', 'straight_1',
     '1 1/8" (28.6 mm)', 'straight_1_1_8',
     '1 1/4" (31.8 mm)', 'straight_1_1_4',
     '1.5" (38.1 mm)', 'straight_1_5',
     'Tapered 1 1/8" – 1.5"', 'tapered_1_1_8_1_5',
     'Tapered 1 1/8" - 1.5"', 'tapered_1_1_8_1_5'),
   null, null, null, 0),
  -- El manubrio cambia su abrazadera y su zona de mandos.
  ('bar_clamp_diameter_mm', 'none', 'handlebarClampMm',
   'abrazadera del manubrio', 'la',
   'mm', null, '{}', 20, 40, 'handlebar', 'change', null, null, null, null, 1),
  ('grip_area_diameter_mm', 'none', 'controlsBarDiameterMm',
   'zona de mandos', 'la',
   'mm', null, '{}', 20, 30, 'handlebar', 'change', null, null, null, null, 1),
  -- Manillas, mandos y puños calzan en la zona de mandos.
  ('handlebar_clamp_mm', 'none', 'controlsBarDiameterMm',
   'zona de mandos', 'la',
   'mm', null, '{}', 20, 30, 'brake_lever', 'conflict', null, null, null, null, 1),
  ('handlebar_clamp_mm', 'none', 'controlsBarDiameterMm',
   'zona de mandos', 'la',
   'mm', null, '{}', 20, 30, 'shifter', 'conflict', null, null, null, null, 1),
  ('grip_bar_nominal_diameter_mm', 'none', 'controlsBarDiameterMm',
   'zona de mandos', 'la',
   'mm', null, '{}', 20, 30, 'grip', 'conflict', null, null, null, null, 1),
  -- La tija cambia su diámetro (un suplemento no es la tija) y su tipo.
  ('seatpost_diameter_mm', 'none', 'seatpostDiameterMm', 'tija', 'la',
   'mm', null, '{}', 20, 36, 'seatpost', 'change', null, null, null,
   jsonb_build_object(
     'spec_key', 'seatpost_kind',
     'values', jsonb_build_array(
       'Rígida', 'Con suspensión', 'Telescópica (dropper)'),
     'missing_ok', true),
   1),
  ('seatpost_kind', 'none', 'seatpostKind', 'tipo de tija', 'el',
   null, null, '{}', 0, 0, 'seatpost', 'change',
   jsonb_build_object(
     'Rígida', 'rigid',
     'Con suspensión', 'suspension',
     'Telescópica (dropper)', 'dropper'),
   null, null, null, 0)
on conflict (spec_key, position, coalesce(template_key, '')) do update
   set bike_fact_key = excluded.bike_fact_key,
       component_label = excluded.component_label,
       component_article = excluded.component_article,
       unit = excluded.unit,
       requires_fact_key = excluded.requires_fact_key,
       requires_fact_values = excluded.requires_fact_values,
       min_value = excluded.min_value,
       max_value = excluded.max_value,
       on_mismatch = excluded.on_mismatch,
       value_map = excluded.value_map,
       constant_value = excluded.constant_value,
       fits = excluded.fits,
       product_condition = excluded.product_condition,
       value_decimals = excluded.value_decimals;

-- ============================================================================
-- Lo que dice el producto en la ficha
-- ============================================================================

-- La de 20260928100000, y las medidas con décimas: hasta los decimales de la
-- fila, sin redondear («31.8» sí; «31.85» en una fila de un decimal, no).
create or replace function public.bike_fact_link_value_internal(
  p_link public.bike_fact_spec_links,
  p_spec jsonb
)
returns jsonb
language plpgsql
immutable
set search_path to 'public'
as $function$
declare
  v_text text;
  v_number numeric;
begin
  if p_link.constant_value is not null then
    return to_jsonb(p_link.constant_value);
  end if;
  v_text := p_spec->'value' #>> '{}';
  if v_text is null then
    return null;
  end if;
  if p_link.value_map is not null then
    return p_link.value_map->v_text;
  end if;
  if coalesce(p_link.value_decimals, 0) > 0 then
    v_text := replace(btrim(v_text), ',', '.');
    if v_text !~ '^[0-9]{1,4}(\.[0-9]+)?$' then
      return null;
    end if;
    v_number := v_text::numeric;
    if v_number <> round(v_number, p_link.value_decimals) then
      return null;
    end if;
    return to_jsonb(trim_scale(v_number));
  end if;
  -- Medidas enteras (mm, piñones): un decimal no se redondea.
  if v_text !~ '^[0-9]{1,4}(\.0+)?$' then
    return null;
  end if;
  return to_jsonb(v_text::numeric::integer);
end;
$function$;

-- ============================================================================
-- Reemplazos por ancla en las funciones vivas
-- ============================================================================

-- Cada ancla tiene que estar exactamente una vez; si la función ya trae la
-- marca, ya se aplicó.
create or replace function pg_temp.cockpit_patch_function(
  p_function regprocedure,
  p_marker text,
  p_anchors text[],
  p_blocks text[]
)
returns void
language plpgsql
as $function$
declare
  v_def text := pg_get_functiondef(p_function);
  i integer;
begin
  if position(p_marker in v_def) > 0 then
    return;
  end if;
  for i in 1 .. array_length(p_anchors, 1) loop
    if (length(v_def) - length(replace(v_def, p_anchors[i], '')))
         / length(p_anchors[i]) <> 1 then
      raise exception '% no tiene el ancla % esperada', p_function, i;
    end if;
  end loop;
  for i in 1 .. array_length(p_anchors, 1) loop
    v_def := replace(v_def, p_anchors[i], p_blocks[i]);
  end loop;
  if position(p_marker in v_def) = 0 then
    raise exception '% quedó sin la marca %', p_function, p_marker;
  end if;
  execute v_def;
end;
$function$;

-- La marca de una línea: una medida con décimas también se compara por valor
-- (31.8). Una fila entera sigue sin aceptar 180,5: la igualdad es numérica.
select pg_temp.cockpit_patch_function(
  'public.job_line_part_change_internal(uuid, uuid, text)'::regprocedure,
  '(\.[0-9]+)?$''',
  array[
    $a$    -- Una medida: «180» o 180, nunca 180,5.
    if (v_marked #>> '{}') !~ '^[0-9]{1,4}(\.0+)?$'$a$
  ],
  array[
    $a$    -- Una medida: «180» o 180, y nunca 180,5 en una fila entera (la
    -- igualdad es por valor); 31.8 en una con décimas (20261002170000).
    if (v_marked #>> '{}') !~ '^[0-9]{1,4}(\.[0-9]+)?$'$a$
  ]
);

-- La puerta de la ficha: las claves nuevas, sus rangos de taller y sus
-- vocabularios.
select pg_temp.cockpit_patch_function(
  'public.patch_bike_technical_facts_v1(text, uuid, uuid, text, jsonb)'::regprocedure,
  'handlebarClampMm',
  array[
    $a$        'rearSpokeHoles', 'frontWheelBsdMm', 'rearWheelBsdMm'
      ) then 'number'$a$,
    $a$        'frontRotorMount', 'rearRotorMount'
      ) then 'string'$a$,
    $a$          when 'bbShellDiameterMm' then v_number between 30 and 60$a$,
    $a$          when 'rearRotorMount' then v_text in ('six_bolt', 'centerlock')$a$
  ],
  array[
    $a$        'rearSpokeHoles', 'frontWheelBsdMm', 'rearWheelBsdMm',
        -- Dirección y cockpit (20261002170000).
        'handlebarClampMm', 'controlsBarDiameterMm', 'seatpostDiameterMm'
      ) then 'number'$a$,
    $a$        'frontRotorMount', 'rearRotorMount',
        -- Dirección y cockpit (20261002170000).
        'steererFit', 'seatpostKind'
      ) then 'string'$a$,
    $a$          when 'bbShellDiameterMm' then v_number between 30 and 60
          -- Abrazadera 22,2 a 35; zona de mandos 22,2 o 23,8; tija 22,2 a
          -- 34,9 (20261002170000).
          when 'handlebarClampMm' then v_number between 20 and 40
          when 'controlsBarDiameterMm' then v_number between 20 and 30
          when 'seatpostDiameterMm' then v_number between 20 and 36$a$,
    $a$          when 'rearRotorMount' then v_text in ('six_bolt', 'centerlock')
          -- Registro `steerer_fit` y `seatpost_kind` (20261002170000).
          when 'steererFit' then v_text in (
            'straight_1', 'straight_1_1_8', 'straight_1_1_4', 'straight_1_5',
            'tapered_1_1_8_1_5')
          when 'seatpostKind' then v_text in ('rigid', 'suspension', 'dropper')$a$
  ]
);

-- Lo que no calza: una medida con décimas se dice entera (antes 22,2 se
-- decía 22).
select pg_temp.cockpit_patch_function(
  'public.bike_fact_part_conflict_internal(uuid, uuid, uuid, text, jsonb, jsonb, jsonb, text)'::regprocedure,
  'trim_scale((v_current',
  array[
    $a$                then ((v_current #>> '{}')::numeric)::integer::text$a$
  ],
  array[
    $a$                then trim_scale((v_current #>> '{}')::numeric)::text$a$
  ]
);

-- Cómo se dice lo que pide una pieza que no calza.
select pg_temp.cockpit_patch_function(
  'public.bike_fact_requirement_text(text, text)'::regprocedure,
  'controlsBarDiameterMm',
  array[
    $a$    else coalesce(
      (select l.component_article || ' ' || l.component_label || ' es '$a$
  ],
  array[
    $a$    -- Dirección y cockpit, con coma decimal (20261002170000).
    when p_requires_key = 'handlebarClampMm' then
      'la abrazadera del manubrio es de '
        || replace(coalesce(p_requires_value, '?'), '.', ',') || ' mm'
    when p_requires_key = 'controlsBarDiameterMm' then
      'la zona de mandos del manubrio es de '
        || replace(coalesce(p_requires_value, '?'), '.', ',') || ' mm'
    else coalesce(
      (select l.component_article || ' ' || l.component_label || ' es '$a$
  ]
);

select pg_temp.cockpit_patch_function(
  'public.bike_fact_requirement_advice(text)'::regprocedure,
  'controlsBarDiameterMm',
  array[
    $a$    else
      'Revisa la medida del neumático y la de esa rueda$a$
  ],
  array[
    $a$    -- Dirección y cockpit (20261002170000).
    when p_requires_key = 'handlebarClampMm' then
      'Una potencia aprieta el manubrio por su centro y tiene que ser de su '
      || 'misma medida (con laina, un manubrio más delgado en una potencia '
      || 'más grande, nunca al revés): si también cambiaste el manubrio, '
      || 'agrega su línea; si la bici tiene otra medida, corrige la ficha; si '
      || 'no, cambia la línea.'
    when p_requires_key = 'controlsBarDiameterMm' then
      'Manillas, mandos y puños calzan por la zona de mandos del manubrio '
      || '(22,2 mm en uno plano, 23,8 mm en uno de ruta): si también '
      || 'cambiaste el manubrio, agrega su línea; si la bici tiene otro, '
      || 'corrige la ficha; si no, cambia la línea.'
    else
      'Revisa la medida del neumático y la de esa rueda$a$
  ]
);

-- ============================================================================
-- Cómo se dice lo instalado
-- ============================================================================

-- La de 20260928130000; los códigos de dirección y tija con su nombre del
-- taller, y las medidas con coma decimal.
create or replace function public.installed_bike_fact_label(
  p_key text,
  p_value jsonb
)
returns text
language sql
stable
set search_path to 'public'
as $function$
  select case
    when p_key in ('frontSpokeHoles', 'rearSpokeHoles') then
      coalesce(p_value #>> '{}', '?') || 'H en la rueda '
        || case p_key when 'frontSpokeHoles' then 'delantera' else 'trasera' end
    when p_key = 'freehubType' then
      public.freehub_type_label(p_value #>> '{}') || ' en el driver trasero'
    when p_key in ('frontRotorMount', 'rearRotorMount') then
      public.rotor_mount_label(p_value #>> '{}') || ' en el anclaje del rotor '
        || case p_key when 'frontRotorMount' then 'delantero' else 'trasero' end
    when p_key = 'steererFit' then
      case p_value #>> '{}'
        when 'straight_1' then '1″'
        when 'straight_1_1_8' then '1⅛″'
        when 'straight_1_1_4' then '1¼″'
        when 'straight_1_5' then '1,5″'
        when 'tapered_1_1_8_1_5' then 'cónico 1⅛″–1,5″'
        else coalesce(p_value #>> '{}', '?')
      end || ' en el tubo de horquilla'
    when p_key = 'seatpostKind' then
      'tija ' || case p_value #>> '{}'
        when 'rigid' then 'rígida'
        when 'suspension' then 'con suspensión'
        when 'dropper' then 'telescópica'
        else coalesce(p_value #>> '{}', '?')
      end
    else coalesce(
      (select case
                when p_key in ('frontWheelBsdMm', 'rearWheelBsdMm')
                     and (p_value #>> '{}') ~ '^[0-9]{1,4}(\.0+)?$'
                  then public.iso_bsd_wheel_label((p_value #>> '{}')::numeric)
                when l.value_decimals > 0
                  then replace(coalesce(p_value #>> '{}', '?'), '.', ',')
                       || coalesce(' ' || l.unit, '')
                else coalesce(p_value #>> '{}', '?') || coalesce(' ' || l.unit, '')
              end
              || ' en ' || l.component_article || ' ' || l.component_label
         from public.bike_fact_spec_links l
        where l.bike_fact_key = p_key
          and l.on_mismatch <> 'check'
        order by l.on_mismatch = 'change' desc
        limit 1),
      coalesce(p_key, '?') || ' = ' || coalesce(p_value #>> '{}', '?'))
  end;
$function$;

-- ============================================================================
-- La pasada sobre el historial
-- ============================================================================

-- Lo que el taller ya instaló, con la misma relación: lo último de cada bici
-- y dato, de trabajos terminados o entregados, sólo donde la ficha no lo
-- sabe. Escribe como la puerta y lo dice en la historia de la bici.
do $backfill$
declare
  v_bike record;
  v_profile public.bike_profiles%rowtype;
  v_values jsonb;
  v_sources jsonb;
  v_confirmed jsonb;
  v_applied jsonb;
  v_fact jsonb;
  v_current jsonb;
  v_bikes integer := 0;
  v_facts integer := 0;
begin
  for v_bike in
    with lines as (
      select i.tenant_id,
             i.id as item_id,
             i.job_id,
             i.product_id,
             i.product_name,
             j.job_number,
             coalesce(j.delivered_at, j.completed_at, j.updated_at) as installed_at,
             public.job_line_bike_internal(i.tenant_id, i.id) as bike_id
        from public.mechanic_job_items i
        join public.mechanic_jobs j
          on j.id = i.job_id
         and j.tenant_id = i.tenant_id
       where j.deleted_at is null
         and j.status in ('FINALIZADO', 'ENTREGADO')
         and i.product_id is not null
         and i.location_key = 'none'
    ),
    facts as (
      select l.*,
             k.bike_fact_key as key,
             k.on_mismatch,
             public.bike_fact_link_value_internal(k, s.spec) as value,
             coalesce((s.spec->>'verified')::boolean, false) as verified,
             k.min_value,
             k.max_value
        from lines l
        join public.bike_fact_spec_links k
          on k.position = 'none'
         and k.on_mismatch <> 'check'
        cross join lateral (
          select public.product_bike_fact_spec_internal(
                   l.tenant_id, l.product_id, k.spec_key) as spec
        ) s
       where l.bike_id is not null
         and s.spec is not null
         and (k.template_key is null or k.template_key = s.spec->>'template_key')
         and public.bike_fact_product_condition_met_internal(
               l.tenant_id, l.product_id, k.product_condition)
    ),
    latest as (
      select distinct on (tenant_id, bike_id, key) *
        from facts
       where value is not null
         -- La puerta no deja escribir una medida fuera de su rango; esta
         -- pasada no pasa por la puerta, así que lo mira aquí.
         and (jsonb_typeof(value) <> 'number'
              or (value #>> '{}')::numeric between min_value and max_value)
       order by tenant_id, bike_id, key,
                installed_at desc, (on_mismatch = 'change') desc, item_id
    )
    select tenant_id,
           bike_id,
           jsonb_agg(jsonb_build_object(
             'key', key,
             'value', value,
             'verified', verified,
             'item_id', item_id,
             'job_id', job_id,
             'job_number', job_number,
             'item_name', product_name)
             order by key) as facts
      from latest
     group by tenant_id, bike_id
     order by tenant_id, bike_id
  loop
    select *
      into v_profile
      from public.bike_profiles bp
     where bp.bike_id = v_bike.bike_id
       and bp.tenant_id = v_bike.tenant_id
     for update;
    v_values := coalesce(v_profile.technical_profile->'values', '{}'::jsonb);
    v_sources := coalesce(v_profile.technical_profile->'sources', '{}'::jsonb);
    v_confirmed := coalesce(v_profile.technical_profile->'confirmed', '{}'::jsonb);
    v_applied := '[]'::jsonb;

    for v_fact in select value from jsonb_array_elements(v_bike.facts)
    loop
      v_current := v_values->(v_fact->>'key');
      -- Lo que la ficha ya sabe no se toca: lo puso el mecánico, el catálogo
      -- o un trabajo posterior.
      if v_current is not null
         and v_current <> 'null'::jsonb
         and lower(v_current #>> '{}') not in ('unknown', 'desconocido', '') then
        continue;
      end if;
      v_values := v_values || jsonb_build_object(v_fact->>'key', v_fact->'value');
      v_sources := v_sources || jsonb_build_object(v_fact->>'key', 'job_completion');
      if (v_fact->>'verified')::boolean then
        v_confirmed := v_confirmed || jsonb_build_object(v_fact->>'key', true);
      else
        v_confirmed := v_confirmed - (v_fact->>'key');
      end if;
      v_applied := v_applied || jsonb_build_array(jsonb_build_object(
        'key', v_fact->>'key',
        'op', case when (v_fact->>'verified')::boolean then 'set' else 'declare' end,
        'from', coalesce(v_current, 'null'::jsonb),
        'to', v_fact->'value',
        'job_id', v_fact->'job_id',
        'job_number', v_fact->'job_number',
        'item_id', v_fact->'item_id',
        'item_name', v_fact->'item_name'));
    end loop;

    if jsonb_array_length(v_applied) = 0 then
      continue;
    end if;

    if v_profile.id is not null then
      update public.bike_profiles
         set technical_profile = coalesce(technical_profile, '{}'::jsonb)
               || jsonb_build_object(
                    'values', v_values,
                    'sources', v_sources,
                    'confirmed', v_confirmed),
             summary_snapshot = '{}'::jsonb
       where id = v_profile.id
         and tenant_id = v_bike.tenant_id;
    else
      insert into public.bike_profiles (
        tenant_id, bike_id, intake_profile, technical_profile, summary_snapshot
      ) values (
        v_bike.tenant_id,
        v_bike.bike_id,
        '{}'::jsonb,
        jsonb_build_object(
          'values', v_values,
          'sources', v_sources,
          'confirmed', v_confirmed),
        '{}'::jsonb
      );
    end if;

    insert into public.bike_events (
      tenant_id, bike_id, job_id, event_type, event_category, event_date,
      title, summary, source, payload
    ) values (
      v_bike.tenant_id,
      v_bike.bike_id,
      (v_applied->0->>'job_id')::uuid,
      case when v_profile.id is null then 'profile_created' else 'profile_updated' end,
      'state',
      clock_timestamp(),
      'Ficha completada con lo que instaló el taller',
      'La dirección y el cockpit de la ficha se llenaron con las piezas que '
        || 'dejaron instaladas trabajos ya entregados ('
        || (select string_agg(distinct coalesce(a->>'job_number', 's/n'), ', ')
              from jsonb_array_elements(v_applied) a)
        || '), sin confirmar salvo ficha verificada.',
      'job_completion',
      jsonb_build_object(
        'migration', '20261002170000_cockpit_bike_facts',
        'facts', v_applied)
    );
    v_bikes := v_bikes + 1;
    v_facts := v_facts + jsonb_array_length(v_applied);
  end loop;
  raise notice 'Dirección y cockpit: % datos en % bicis', v_facts, v_bikes;
end;
$backfill$;

commit;
