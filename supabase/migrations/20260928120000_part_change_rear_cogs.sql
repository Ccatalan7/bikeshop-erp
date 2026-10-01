-- Deployment status: NOT DEPLOYED
-- Cambios de partes, tercer concepto: cassette y piñón de rosca
-- (BIKE_WORKSHOP_MASTER_SCHEMA.md, «Cambios de partes: cassette y piñón»).
--
-- Lo que la evidencia de producción (2026-09-28, sólo lectura) cambió del
-- pedido «velocidades y driver»:
--
-- * «Velocidades» de la bici no es la del cassette. `drivetrainSpeeds` es el
--   total platos × piñones (21 en las 20 bicis 3x7, 20 en la 2x10); el número
--   de piñones sólo vive en `drivetrainConfig` («3x7»). Un cassette no puede
--   escribir `drivetrainSpeeds`: su cuenta se compara con los piñones de la
--   configuración.
-- * El driver es de la maza, no del cassette. `freehubType` (25 rueda libre
--   roscada, 20 Shimano HG, 3 Micro Spline, 1 XD, 2 Desconocido) dice qué
--   recibe la maza; el cassette y el piñón de rosca tienen que calzar con él.
--   Si la ficha no lo sabe, lo que se instaló lo dice: un cassette de estrías
--   HG sólo entra en un núcleo HG, un piñón de rosca sólo en una maza roscada.
--   Entra declarado, como el BSD del neumático.
-- * En el taller «piñón» nombra las dos cosas («Piñón Shimano Cs-Hg200-7» es
--   un cassette): el nombre no separa cassette de piñón de rosca; la familia
--   del producto sí (plantilla `cassette` o `freewheel`, 32 y 29 productos).
--   El cassette dice su cuerpo en `cassette_spline_standard` (19 de 32); el
--   piñón de rosca no tiene campo: su plantilla es la rosca.
-- * Pero la familia `freewheel` también guarda piñones de una corona, y uno
--   es fijo («PIÑON 15T FIJO MOD. PMA7-15T», «PIÑON 16T LIBRE ROCKET
--   COMPATIBLE / GENERICO»): un piñón fijo va en una maza de rosca fija, no
--   en una rueda libre. Sólo un piñón de rosca de dos o más coronas es, por
--   construcción, una rueda libre roscada (21 de 29 dicen cuántas: 6, 7 u 8).
--   Uno de una corona o sin cuenta no se anota.
-- * HG no es un solo cuerpo: estrías S (7v), M (8/9/10v y MTB 11v), L (ruta
--   11/12v) y L2 (ruta 12v). La ficha de la bici tiene `shimano_hg` y
--   `shimano_hg_road_11`: S y M calzan en `shimano_hg` (en un cuerpo largo
--   con separador), un cassette HG calza en `shimano_hg_road_11` con
--   separador, y L2 y XD SLIM no tienen código en la ficha de la bici: no se
--   anotan.
-- * En 44 líneas reales (18 cassettes, 26 piñones de rosca) la velocidad
--   nunca cambió (7 en 3x7, 8 en 1x8, 9 en 1x9) y hubo dos choques de driver:
--   un piñón de rosca FW-71 en una bici con ficha `shimano_hg` (la ficha o la
--   línea está mal: queda incompatible), y un cassette HG 7v en una bici con
--   ficha `threaded_freewheel` en un trabajo que también cambió la maza (el
--   driver lo decide la maza nueva: queda pendiente).
-- * Defecto previo en la misma familia: el parche aceptaba `drivetrainSpeeds`
--   de 1 a 14, pero el asistente de transmisión y la ficha guardan el total
--   (3 × 7 = 21): un servicio de transmisión en una bici de tres platos se
--   rechazaba entero. El rango pasa a 1–42 (3 × 14).
--
-- Decisiones del dueño que quedan abiertas (Master Schema):
-- * ¿Un cassette de otra velocidad cambia la transmisión de la ficha? Hoy no:
--   es incompatible, o pendiente si el mismo trabajo instala un mando trasero.
-- * ¿La maza nueva cambia el driver? Hace falta el concepto de la maza (su
--   núcleo está en 9 de 52 mazas): hoy el cassette queda pendiente.
--
-- Depende de `20260928110000`.
begin;

-- ============================================================================
-- La relación única: valores que no son medidas, y reglas que sólo revisan
-- ============================================================================

alter table public.bike_fact_spec_links
  add column if not exists value_map jsonb,
  add column if not exists constant_value text,
  add column if not exists fits jsonb,
  add column if not exists product_condition jsonb;

comment on column public.bike_fact_spec_links.value_map is
  'Del valor de la ficha técnica del producto al código de la ficha de la bici. Un valor que no está no se anota.';
comment on column public.bike_fact_spec_links.constant_value is
  'Lo que la familia del producto ya dice (spec_key = ''_family''): un piñón de rosca es rueda libre roscada.';
comment on column public.bike_fact_spec_links.product_condition is
  'La fila vale sólo si el producto dice {spec_key} entre {min} y {max}: un piñón de rosca de 2 a 14 coronas.';
comment on column public.bike_fact_spec_links.fits is
  'Además del mismo código, con qué códigos de la bici no choca: un cassette HG entra en un núcleo HG Road 11 con separador.';

alter table public.bike_fact_spec_links
  drop constraint if exists bike_fact_spec_links_on_mismatch_check;
alter table public.bike_fact_spec_links
  add constraint bike_fact_spec_links_on_mismatch_check
  check (on_mismatch in ('change', 'conflict', 'check'));

-- Un código no tiene rango de taller; una medida sí.
alter table public.bike_fact_spec_links
  drop constraint if exists bike_fact_spec_links_range_check;
alter table public.bike_fact_spec_links
  add constraint bike_fact_spec_links_range_check
  check (
    value_map is not null
    or constant_value is not null
    or (min_value > 0 and max_value >= min_value)
  );

alter table public.bike_fact_spec_links
  drop constraint if exists bike_fact_spec_links_family_value_check;
alter table public.bike_fact_spec_links
  add constraint bike_fact_spec_links_family_value_check
  check ((spec_key = '_family') = (constant_value is not null));

-- El driver trasero: lo que dice el cassette (sus estrías) o lo que es un
-- piñón de rosca. Tiene que calzar con la maza; si la ficha no lo sabe, lo
-- anota. La cuenta de piñones sólo se revisa contra la configuración.
insert into public.bike_fact_spec_links (
  spec_key, position, bike_fact_key, component_label, component_article,
  unit, requires_fact_key, requires_fact_values, min_value, max_value,
  template_key, on_mismatch, value_map, constant_value, fits,
  product_condition
) values
  ('cassette_spline_standard', 'rear', 'freehubType', 'driver trasero', 'el',
   null, null, '{}', 0, 0, 'cassette', 'conflict',
   jsonb_build_object(
     'Shimano HG spline S (7v)', 'shimano_hg',
     'Shimano HG spline M (8/9/10v y MTB 11v; ROAD 11v y 7v sólo según filas C-731; LINKGLIDE según C-649)', 'shimano_hg',
     'Shimano HG spline L (ROAD 11/12v; otras coronas sólo según filas C-731)', 'shimano_hg_road_11',
     'Shimano MICRO SPLINE (MTB 12v)', 'microspline',
     'SRAM XD', 'sram_xd',
     'SRAM XDR', 'sram_xdr',
     'Campagnolo', 'campagnolo',
     'Campagnolo N3W', 'campagnolo_n3w'),
   null,
   '{"shimano_hg": ["shimano_hg_road_11"], "sram_xd": ["sram_xdr"]}'::jsonb,
   null),
  ('_family', 'rear', 'freehubType', 'driver trasero', 'el',
   null, null, '{}', 0, 0, 'freewheel', 'conflict',
   null, 'threaded_freewheel', null,
   '{"spec_key": "sprocket_count", "min": 2, "max": 14}'::jsonb),
  ('sprocket_count', 'rear', 'drivetrainConfig', 'transmisión', 'la',
   null, null, '{}', 1, 14, 'cassette', 'check', null, null, null, null),
  ('sprocket_count', 'rear', 'drivetrainConfig', 'transmisión', 'la',
   null, null, '{}', 1, 14, 'freewheel', 'check', null, null, null, null)
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
       product_condition = excluded.product_condition;

-- ============================================================================
-- Cómo se dice
-- ============================================================================

-- Los nombres de `kDrivetrainFreehubTypeOptions` (`drivetrain_canonical_data.dart`).
create or replace function public.freehub_type_label(p_code text)
returns text
language sql
immutable
set search_path to 'public'
as $function$
  select case p_code
    when 'shimano_hg' then 'Shimano HG'
    when 'shimano_hg_road_11' then 'Shimano HG Road 11'
    when 'microspline' then 'Micro Spline'
    when 'sram_xd' then 'SRAM XD'
    when 'sram_xdr' then 'SRAM XDR'
    when 'campagnolo' then 'Campagnolo'
    when 'campagnolo_n3w' then 'Campagnolo N3W'
    when 'threaded_freewheel' then 'Rueda libre roscada'
    when 'bmx_driver' then 'Driver BMX'
    when 'fixed_threaded' then 'Rosca fija / contratuerca'
    when 'coaster_hub' then 'Maza contrapedal'
    when 'unknown' then 'Desconocido / sin confirmar'
    else p_code
  end;
$function$;

revoke all on function public.freehub_type_label(text)
  from public, anon, authenticated, service_role;

-- Los piñones de una configuración: «3x7» → 7, «singlespeed» → 1. Nulo si
-- no se lee (la misma lectura que `_chainSpeedFromContext` de la matriz).
create or replace function public.drivetrain_rear_cog_count(p_config text)
returns integer
language sql
immutable
set search_path to 'public'
as $function$
  select case
    when lower(btrim(p_config)) in ('singlespeed', 'single_speed', 'single speed') then 1
    when lower(btrim(p_config)) ~ '^[1-3]\s*x\s*([1-9]|1[0-4])$'
      then substring(lower(btrim(p_config)) from 'x\s*([0-9]+)$')::integer
  end;
$function$;

revoke all on function public.drivetrain_rear_cog_count(text)
  from public, anon, authenticated, service_role;

-- El total platos × piñones de una configuración: «3x7» → 21,
-- «singlespeed» → 1. Nulo si no se lee.
create or replace function public.drivetrain_total_speeds(p_config text)
returns integer
language sql
immutable
set search_path to 'public'
as $function$
  select case
    when public.drivetrain_rear_cog_count(p_config) is null then null
    when lower(btrim(p_config)) ~ '^[1-3]\s*x'
      then substring(lower(btrim(p_config)) from '^([1-3])')::integer
           * public.drivetrain_rear_cog_count(p_config)
    else public.drivetrain_rear_cog_count(p_config)
  end;
$function$;

revoke all on function public.drivetrain_total_speeds(text)
  from public, anon, authenticated, service_role;

-- Dos valores de la ficha son el mismo: números por valor, códigos por texto.
create or replace function public.bike_fact_value_equal(p_a jsonb, p_b jsonb)
returns boolean
language sql
immutable
set search_path to 'public'
as $function$
  select case
    when p_a is null or p_b is null then false
    when jsonb_typeof(p_a) = 'number' and jsonb_typeof(p_b) = 'number'
      then (p_a #>> '{}')::numeric = (p_b #>> '{}')::numeric
    else (p_a #>> '{}') = (p_b #>> '{}')
  end;
$function$;

revoke all on function public.bike_fact_value_equal(jsonb, jsonb)
  from public, anon, authenticated, service_role;

-- ============================================================================
-- Lo que la ficha técnica del repuesto dice en la ficha de la bici
-- ============================================================================

-- El valor de la bici para una fila de la relación y lo que el lector dio del
-- producto (`product_bike_fact_spec_internal`): la familia, el código de su
-- mapa, o una medida entera. Nulo si el producto no lo dice o no tiene código
-- en la ficha de la bici.
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
  -- Medidas enteras (mm, piñones): un decimal no se redondea.
  if v_text !~ '^[0-9]{1,4}(\.0+)?$' then
    return null;
  end if;
  return to_jsonb(v_text::numeric::integer);
end;
$function$;

revoke all on function public.bike_fact_link_value_internal(public.bike_fact_spec_links, jsonb)
  from public, anon, authenticated, service_role;

-- La marca de la línea, leída con la regla única: la fila de la relación que
-- corresponde a su clave, su rueda y la familia del producto (las filas que
-- sólo revisan no se marcan), y el valor que el producto dice hoy. Nula si ya
-- no calza.
create or replace function public.job_line_part_change_internal(
  p_tenant_id uuid,
  p_item_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_item public.mechanic_job_items%rowtype;
  v_link public.bike_fact_spec_links%rowtype;
  v_marked jsonb;
  v_spec jsonb;
  v_value jsonb;
  v_condition text;
  v_found boolean := false;
begin
  select *
    into v_item
    from public.mechanic_job_items i
   where i.id = p_item_id
     and i.tenant_id = p_tenant_id;
  if not found
     or v_item.product_id is null
     or jsonb_typeof(v_item.service_configuration_data->'part_change')
        is distinct from 'object' then
    return null;
  end if;

  for v_link in
    select *
      from public.bike_fact_spec_links l
     where l.bike_fact_key = v_item.service_configuration_data->'part_change'->>'key'
       and l.position = v_item.location_key
       and l.on_mismatch <> 'check'
     order by l.template_key nulls last
  loop
    v_spec := public.product_bike_fact_spec_internal(
      p_tenant_id, v_item.product_id, v_link.spec_key);
    if v_link.template_key is null
       or v_link.template_key = v_spec->>'template_key' then
      v_found := true;
      exit;
    end if;
  end loop;
  if not v_found then
    return null;
  end if;
  -- Lo que la fila exige del producto: un piñón de rosca de dos o más
  -- coronas. Uno de una corona puede ser fijo; sin cuenta, no se sabe.
  if v_link.product_condition is not null then
    v_condition := public.product_bike_fact_spec_internal(
      p_tenant_id, v_item.product_id,
      v_link.product_condition->>'spec_key')->'value' #>> '{}';
    if v_condition is null
       or v_condition !~ '^[0-9]{1,4}(\.0+)?$'
       or v_condition::numeric < (v_link.product_condition->>'min')::numeric
       or v_condition::numeric
          > coalesce((v_link.product_condition->>'max')::numeric, v_condition::numeric) then
      return null;
    end if;
  end if;

  v_value := public.bike_fact_link_value_internal(v_link, v_spec);
  v_marked := v_item.service_configuration_data->'part_change'->'value';
  if v_value is null or v_marked is null then
    return null;
  end if;
  if jsonb_typeof(v_value) = 'number' then
    -- Una medida: «180» o 180, nunca 180,5.
    if (v_marked #>> '{}') !~ '^[0-9]{1,4}(\.0+)?$'
       or (v_marked #>> '{}')::numeric <> (v_value #>> '{}')::numeric then
      return null;
    end if;
  elsif jsonb_typeof(v_marked) <> 'string'
        or (v_marked #>> '{}') <> (v_value #>> '{}') then
    return null;
  end if;

  -- La fila que usó la línea: su regla (`on_mismatch`) y su familia deciden,
  -- no otra fila con la misma clave. Lo que dice la familia del producto (un
  -- piñón de rosca) no es un dato verificado del producto.
  return jsonb_build_object(
    'key', v_link.bike_fact_key,
    'value', v_value,
    'spec_key', v_link.spec_key,
    'position', v_link.position,
    'link_id', v_link.id,
    'on_mismatch', v_link.on_mismatch,
    'template_key', v_spec->>'template_key',
    'verified', v_link.constant_value is null
      and coalesce((v_spec->>'verified')::boolean, false)
  );
end;
$function$;

revoke all on function public.job_line_part_change_internal(uuid, uuid)
  from public, anon, authenticated, service_role;

-- ============================================================================
-- Lo que la bici ya dice
-- ============================================================================

-- ¿Escribió esta línea el valor que la bici tiene hoy en esa clave? La misma
-- regla de 20260928110000 (el último recibo de la bici que tocó la clave, con
-- `set` o `declare`, gana otra línea en un empate), ahora para medidas y
-- códigos, y una más: ninguna otra línea instaló después en esa clave. Un
-- recibo que no cambió nada (declaró lo mismo, o calzaba) también es una
-- instalación: si el primer trabajo pudiera corregir su driver después de que
-- otro instaló un cassette HG sobre él, la ficha contradiría la instalación
-- más nueva sin aviso (revisión de Codex, 2026-09-28).
create or replace function public.bike_fact_line_wrote_internal(
  p_tenant_id uuid,
  p_item_id uuid,
  p_bike_id uuid,
  p_key text,
  p_value jsonb
)
returns boolean
language sql
stable
set search_path to 'public'
as $function$
  select coalesce((
    select latest.operation_key like 'job_completion:' || p_item_id::text || ':%'
           and latest.op in ('set', 'declare')
           and public.bike_fact_value_equal(latest.to_value, p_value)
           and not exists (
             select 1
               from public.bike_technical_fact_patches later
              where later.tenant_id = p_tenant_id
                and later.bike_id = p_bike_id
                and later.source = 'job_completion'
                and later.operation_key not like 'job_completion:' || p_item_id::text || ':%'
                and later.completed_at >= latest.completed_at
                and split_part(later.operation_key, ':', 4) ~ ('(^|,)' || p_key || '='))
      from (
        select p.operation_key, p.completed_at, e->>'op' as op, e->'to' as to_value
          from public.bike_technical_fact_patches p
         cross join lateral jsonb_array_elements(
                 case when jsonb_typeof(p.applied) = 'array'
                      then p.applied else '[]'::jsonb end) e
         where p.tenant_id = p_tenant_id
           and p.bike_id = p_bike_id
           and e->>'key' = p_key
         order by p.completed_at desc,
                  (p.operation_key like 'job_completion:' || p_item_id::text || ':%')
         limit 1
      ) latest
  ), false);
$function$;

revoke all on function public.bike_fact_line_wrote_internal(uuid, uuid, uuid, text, jsonb)
  from public, anon, authenticated, service_role;

-- ¿Otra línea del mismo trabajo, en la misma bici, instala una pieza de esa
-- familia en la rueda trasera? Una maza nueva decide el driver; un mando
-- trasero nuevo, la velocidad. Entonces lo que no calza queda pendiente de
-- una decisión, no incompatible. Trasera con evidencia: la rueda de la línea o
-- la posición del producto (Trasera, Juego; Derecho (trasero), Par). Una sin
-- rueda ni posición no se supone trasera (revisión de Codex, 2026-09-28).
create or replace function public.job_installs_rear_family_internal(
  p_tenant_id uuid,
  p_item_id uuid,
  p_bike_id uuid,
  p_template_key text
)
returns boolean
language sql
stable
set search_path to 'public'
as $function$
  select exists (
    select 1
      from public.mechanic_job_items self
      join public.mechanic_job_items other
        on other.job_id = self.job_id
       and other.tenant_id = self.tenant_id
       and other.id <> self.id
     where self.id = p_item_id
       and self.tenant_id = p_tenant_id
       and other.product_id is not null
       and coalesce(other.location_key, 'none') <> 'front'
       and public.job_line_bike_internal(p_tenant_id, other.id) = p_bike_id
       and public.product_bike_fact_spec_internal(
             p_tenant_id, other.product_id, '_family')->>'template_key'
           = p_template_key
       and (
         other.location_key = 'rear'
         or public.product_bike_fact_spec_internal(
              p_tenant_id, other.product_id,
              case p_template_key
                when 'hub' then 'hub_package_position'
                else 'shifter_position'
              end)->>'value'
            in ('Trasera', 'Juego (delantera y trasera)', 'Derecho (trasero)', 'Par')
       )
  );
$function$;

revoke all on function public.job_installs_rear_family_internal(uuid, uuid, uuid, text)
  from public, anon, authenticated, service_role;

-- Con qué choca una pieza, con la bici y la ficha ya tomadas: `requires_key`,
-- `requires_value` y `reason`: `incompatible`, `pending` (con `pending` =
-- `hub_change` / `shifter_change`) o `fits` (calza con lo que la ficha ya
-- dice, que es otro código: no se escribe). Nulo si la pieza puede escribir
-- su valor, o si no se puede refutar.
--
-- * Una fila que tiene que calzar (`conflict`): la ficha dice otra cosa en
--   esa clave —salvo el mismo código, lo que escribió esta misma línea y
--   sigue siendo suyo (se corrige), o uno con el que calza (`fits`, y la
--   ficha no cambia)—. «Desconocido» no refuta. Un driver distinto con una
--   maza nueva en el trabajo queda pendiente.
-- * El BSD, además, contra el aro escrito (20260928110000).
-- * Las filas que sólo revisan (`check`) de la misma familia y rueda: los
--   piñones del producto contra los de la configuración de la bici. Distintos
--   con un mando trasero nuevo en el trabajo quedan pendientes.
create or replace function public.bike_fact_part_conflict_internal(
  p_tenant_id uuid,
  p_item_id uuid,
  p_bike_id uuid,
  p_key text,
  p_value jsonb,
  p_values jsonb,
  p_sources jsonb,
  p_wheel_size text
)
returns jsonb
language plpgsql
stable
set search_path to 'public'
as $function$
declare
  v_part jsonb;
  v_link public.bike_fact_spec_links%rowtype;
  v_check public.bike_fact_spec_links%rowtype;
  v_current jsonb;
  v_known boolean;
  v_own boolean := false;
  v_candidates integer[];
  v_product_id uuid;
  v_product jsonb;
  v_bike_count integer;
  v_bike_text text;
  v_fits jsonb;
begin
  v_part := public.job_line_part_change_internal(p_tenant_id, p_item_id);
  if v_part is null or v_part->>'key' is distinct from p_key or p_value is null then
    return null;
  end if;
  select * into v_link
    from public.bike_fact_spec_links l
   where l.id = (v_part->>'link_id')::uuid;

  if v_link.on_mismatch = 'conflict' then
    v_current := coalesce(p_values, '{}'::jsonb)->p_key;
    v_known := v_current is not null
      and v_current <> 'null'::jsonb
      and lower(v_current #>> '{}') not in ('unknown', 'desconocido', '');
    if v_known and not public.bike_fact_value_equal(v_current, p_value) then
      -- Lo escribió esta misma línea en esta bici y sigue siendo suyo: se está
      -- corrigiendo (20260928110000).
      -- Si el mecánico lo volvió a elegir en la ficha (fuente `mechanic`),
      -- aunque sea el mismo valor, ya es suyo.
      v_own := (coalesce(p_sources, '{}'::jsonb)->>p_key)
                 is not distinct from 'job_completion'
        and public.bike_fact_line_wrote_internal(
          p_tenant_id, p_item_id, p_bike_id, p_key, v_current);
      if not v_own
         and coalesce(
           (v_link.fits->(p_value #>> '{}')) ? (v_current #>> '{}'), false) then
        -- Calza con lo que la ficha dice, pero no es lo mismo: un cassette HG
        -- en un núcleo HG Road 11 con separador. La ficha no cambia; lo que
        -- sólo se revisa se mira igual.
        v_fits := jsonb_build_object(
          'requires_key', p_key,
          'requires_value', v_current #>> '{}',
          'reason', 'fits');
      elsif not v_own then
        if p_key = 'freehubType'
           and public.job_installs_rear_family_internal(
             p_tenant_id, p_item_id, p_bike_id, 'hub') then
          return jsonb_build_object(
            'requires_key', p_key,
            'requires_value', v_current #>> '{}',
            'reason', 'pending',
            'pending', 'hub_change');
        end if;
        return jsonb_build_object(
          'requires_key', p_key,
          'requires_value', case
            when jsonb_typeof(v_current) = 'number'
              then ((v_current #>> '{}')::numeric)::integer::text
            else v_current #>> '{}'
          end,
          'reason', 'incompatible');
      end if;
    end if;

    if p_key in ('frontWheelBsdMm', 'rearWheelBsdMm')
       and jsonb_typeof(p_value) = 'number'
       and (not v_known or v_own) then
      v_candidates := public.iso_bsd_candidates_for_wheel_size(p_wheel_size);
      if cardinality(v_candidates) > 0
         and not (((p_value #>> '{}')::numeric)::integer = any (v_candidates)) then
        return jsonb_build_object(
          'requires_key', 'bikes.wheel_size',
          'requires_value', btrim(p_wheel_size),
          'reason', 'incompatible');
      end if;
    end if;
  end if;

  -- Lo que sólo se revisa, de la misma familia y rueda.
  select i.product_id into v_product_id
    from public.mechanic_job_items i
   where i.id = p_item_id
     and i.tenant_id = p_tenant_id;
  for v_check in
    select *
      from public.bike_fact_spec_links l
     where l.on_mismatch = 'check'
       and l.position = v_link.position
       and (l.template_key is null or l.template_key = v_part->>'template_key')
     order by l.bike_fact_key
  loop
    v_product := public.bike_fact_link_value_internal(
      v_check,
      public.product_bike_fact_spec_internal(
        p_tenant_id, v_product_id, v_check.spec_key));
    v_bike_text := coalesce(p_values, '{}'::jsonb)->>v_check.bike_fact_key;
    v_bike_count := case v_check.bike_fact_key
      when 'drivetrainConfig' then public.drivetrain_rear_cog_count(v_bike_text)
      else case when v_bike_text ~ '^[0-9]{1,4}$' then v_bike_text::integer end
    end;
    -- Una cuenta fuera del rango de la fila (1 a 14) es un error de la ficha
    -- técnica, no una transmisión: no refuta.
    if v_product is null
       or jsonb_typeof(v_product) <> 'number'
       or (v_product #>> '{}')::integer
          not between v_check.min_value and v_check.max_value
       or v_bike_count is null
       or (v_product #>> '{}')::integer = v_bike_count then
      continue;
    end if;
    if public.job_installs_rear_family_internal(
         p_tenant_id, p_item_id, p_bike_id, 'shifter') then
      return jsonb_build_object(
        'requires_key', v_check.bike_fact_key,
        'requires_value', v_bike_text,
        'reason', 'pending',
        'pending', 'shifter_change');
    end if;
    return jsonb_build_object(
      'requires_key', v_check.bike_fact_key,
      'requires_value', v_bike_text,
      'reason', 'incompatible');
  end loop;
  return v_fits;
end;
$function$;

revoke all on function public.bike_fact_part_conflict_internal(uuid, uuid, uuid, text, jsonb, jsonb, jsonb, text)
  from public, anon, authenticated, service_role;

-- Lo que cada línea de un trabajo escribió y la ficha todavía dice como
-- suyo: `{línea: {key, value}}` (20260928110000), ahora también códigos.
create or replace function public.job_part_change_writers_v1(p_job_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_tenant_id uuid;
  v_item record;
  v_bike_id uuid;
  v_key text;
  v_current jsonb;
  v_result jsonb := '{}'::jsonb;
begin
  if p_job_id is null then
    raise exception 'El trabajo es obligatorio.' using errcode = '22004';
  end if;
  select job.tenant_id
    into v_tenant_id
    from public.mechanic_jobs job
   where job.id = p_job_id;
  if not found then
    raise exception 'Trabajo no encontrado.' using errcode = 'P0002';
  end if;
  perform public.assert_workshop_rpc_tenant(v_tenant_id);

  for v_item in
    select i.id, i.service_configuration_data->'part_change'->>'key' as key
      from public.mechanic_job_items i
     where i.job_id = p_job_id
       and i.tenant_id = v_tenant_id
       and jsonb_typeof(i.service_configuration_data->'part_change') = 'object'
  loop
    v_key := v_item.key;
    v_bike_id := public.job_line_bike_internal(v_tenant_id, v_item.id);
    if v_key is null or v_bike_id is null then
      continue;
    end if;
    v_current := null;
    select bp.technical_profile->'values'->v_key
      into v_current
      from public.bike_profiles bp
     where bp.bike_id = v_bike_id
       and bp.tenant_id = v_tenant_id
       and bp.technical_profile->'sources'->>v_key = 'job_completion';
    if v_current is not null
       and jsonb_typeof(v_current) in ('number', 'string')
       and public.bike_fact_line_wrote_internal(
             v_tenant_id, v_item.id, v_bike_id, v_key, v_current) then
      v_result := v_result || jsonb_build_object(
        v_item.id::text,
        jsonb_build_object('key', v_key, 'value', case
          when jsonb_typeof(v_current) = 'number'
            then to_jsonb(((v_current #>> '{}')::numeric)::integer)
          else v_current
        end));
    end if;
  end loop;
  return v_result;
end;
$function$;

revoke all on function public.job_part_change_writers_v1(uuid)
  from public, anon, service_role;
grant execute on function public.job_part_change_writers_v1(uuid) to authenticated;

-- La regla de 20260928110000 con medidas ya no tiene quién la llame.
drop function if exists public.bike_fact_line_wrote_internal(uuid, uuid, uuid, text, numeric);

-- Lo que la ficha dice y con lo que la pieza no calza, como lo dice el taller:
-- «el driver trasero es «Rueda libre roscada»», «la transmisión es 3x7».
create or replace function public.bike_fact_requirement_text(
  p_requires_key text,
  p_requires_value text
)
returns text
language sql
stable
set search_path to 'public'
as $function$
  select case
    when p_requires_key = 'brakeType' then
      'tipo de freno «' || public.bike_fact_requirement_label(p_requires_value) || '»'
    when p_requires_key = 'bikes.wheel_size' then
      'aro ' || coalesce(p_requires_value, '?')
    when p_requires_key = 'freehubType' then
      'el driver trasero es «' || public.freehub_type_label(p_requires_value) || '»'
    when p_requires_key = 'drivetrainConfig' then
      'la transmisión es ' || coalesce(p_requires_value, '?')
    else coalesce(
      (select l.component_article || ' ' || l.component_label || ' es '
                || case
                     when p_requires_key in ('frontWheelBsdMm', 'rearWheelBsdMm')
                       then public.iso_bsd_wheel_label(p_requires_value::numeric)
                     else coalesce(p_requires_value, '?') || coalesce(' ' || l.unit, '')
                   end
         from public.bike_fact_spec_links l
        where l.bike_fact_key = p_requires_key
        limit 1),
      p_requires_key || ' = ' || coalesce(p_requires_value, '?'))
  end;
$function$;

revoke all on function public.bike_fact_requirement_text(text, text)
  from public, anon, authenticated, service_role;

-- Qué hacer cuando no calza.
create or replace function public.bike_fact_requirement_advice(p_requires_key text)
returns text
language sql
immutable
set search_path to 'public'
as $function$
  select case p_requires_key
    when 'brakeType' then
      'Si la bici lleva freno de disco, corrige el tipo de freno en su ficha '
      || 'y guarda el trabajo; si no, quita la línea.'
    when 'freehubType' then
      'Revisa el núcleo de la maza trasera: si es otro, corrige el driver en '
      || 'la ficha de la bici y guarda el trabajo; si no, cambia la línea.'
    when 'drivetrainConfig' then
      'Un cassette o piñón de otra velocidad necesita el mando de esa '
      || 'velocidad: si también lo cambiaste, agrega su línea o corrige la '
      || 'transmisión en la ficha; si no, cambia la línea.'
    else
      'Revisa la medida del neumático y la de esa rueda: si el neumático sí '
      || 'va ahí, corrige la ficha de la bici y guarda el trabajo; si no, '
      || 'cambia la línea.'
  end;
$function$;

revoke all on function public.bike_fact_requirement_advice(text)
  from public, anon, authenticated, service_role;

-- Lo que queda pendiente, y qué decide el mecánico.
create or replace function public.bike_fact_pending_text(p_pending text)
returns text
language sql
immutable
set search_path to 'public'
as $function$
  select case p_pending
    when 'hub_change' then
      'el trabajo también cambia la maza trasera: el driver lo dice la maza '
      || 'nueva. Elígelo en la ficha de la bici'
    when 'shifter_change' then
      'el trabajo también cambia el mando trasero: si la transmisión cambió, '
      || 'corrígela en la ficha de la bici'
    else 'confírmalo en la ficha de la bici'
  end;
$function$;

revoke all on function public.bike_fact_pending_text(text)
  from public, anon, authenticated, service_role;

-- «36H en la rueda delantera», «180 mm en el rotor trasero», «622 (29″/700c)
-- en la rueda trasera», «Shimano HG en el driver trasero».
create or replace function public.installed_bike_fact_label(p_key text, p_value jsonb)
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
    else coalesce(
      (select case
                when p_key in ('frontWheelBsdMm', 'rearWheelBsdMm')
                     and (p_value #>> '{}') ~ '^[0-9]{1,4}(\.0+)?$'
                  then public.iso_bsd_wheel_label((p_value #>> '{}')::numeric)
                else coalesce(p_value #>> '{}', '?') || coalesce(' ' || l.unit, '')
              end
              || ' en ' || l.component_article || ' ' || l.component_label
         from public.bike_fact_spec_links l
        where l.bike_fact_key = p_key
          and l.on_mismatch <> 'check'
        limit 1),
      coalesce(p_key, '?') || ' = ' || coalesce(p_value #>> '{}', '?'))
  end;
$function$;

revoke all on function public.installed_bike_fact_label(text, jsonb)
  from public, anon, authenticated, service_role;

-- ============================================================================
-- Aplicar lo instalado: medidas y códigos, y lo que queda pendiente
-- ============================================================================

-- El aplicador de 20260928110000 con dos cambios: el valor es el de la ficha
-- (una medida o un código, `jsonb`), y lo que no calza porque el mismo
-- trabajo cambia la pieza que lo decide (la maza, el mando trasero) queda
-- pendiente: no se escribe, no se rechaza, y la bici lo dice en su historia.

create or replace function public.apply_job_installed_bike_facts_internal(
  p_tenant_id uuid,
  p_job_id uuid,
  p_notices_required boolean default false
)
returns jsonb
language plpgsql
set search_path to 'public'
as $function$
declare
  v_item record;
  v_position text;
  v_holes_text text;
  v_value jsonb;
  v_key text;
  v_op text;
  v_link public.bike_fact_spec_links%rowtype;
  v_verified jsonb;
  v_misfit text;
  v_requires jsonb;
  v_wheel_size text;
  v_profile_values jsonb;
  v_profile_sources jsonb;
  v_bike_id uuid;
  v_facts_suffix text;
  v_latest integer;
  v_latest_suffix text;
  v_operation_key text;
  v_current jsonb;
  v_current_confirmed boolean;
  v_latest_bike_id uuid;
  v_claims jsonb := '[]'::jsonb;
  v_prior record;
  v_receipt jsonb;
  v_applied jsonb := '[]'::jsonb;
  v_problems jsonb := '[]'::jsonb;
begin
  for v_item in
    select i.id,
           i.product_name,
           i.location_key,
           i.job_bike_id,
           i.service_configuration_data as data,
           jb.bike_id as line_bike_id
      from public.mechanic_job_items i
      left join public.mechanic_job_bikes jb
        on jb.id = i.job_bike_id
       and jb.tenant_id = i.tenant_id
     where i.job_id = p_job_id
       and i.tenant_id = p_tenant_id
       and (
         i.service_configuration_data ? 'hole_count'
         or i.service_configuration_data ? 'part_change'
       )
     -- Por bici, en el mismo orden en todo trabajo: dos trabajos con las
     -- mismas bicis no se toman una cada uno.
     order by jb.bike_id nulls last, i.created_at, i.id
  loop
    v_link := null;
    -- Una línea instala una sola cosa: perforaciones (un servicio) o un
    -- repuesto. Con las dos, se informa y no se escribe ninguna.
    if v_item.data ? 'hole_count' and v_item.data ? 'part_change' then
      v_problems := v_problems || jsonb_build_array(jsonb_build_object(
        'item_id', v_item.id,
        'item_name', v_item.product_name,
        'reason', 'mixed_change'
      ));
      continue;
    end if;
    if v_item.data ? 'hole_count' then
      -- La misma regla que `serviceWheelPositions` + `wheelInstalledFacts`:
      -- una sola rueda y un número de perforaciones. «Ambas» no instala: el
      -- asistente ya le dijo al mecánico que la ficha no cambia. Lo demás que
      -- no se puede leer se informa, no se salta.
      v_position := coalesce(
        nullif(v_item.location_key, 'none'),
        v_item.data->>'which_wheel'
      );
      v_holes_text := v_item.data->>'hole_count';
      if v_position = 'both' then
        continue;
      end if;
      if v_position is null or v_position not in ('front', 'rear') then
        v_problems := v_problems || jsonb_build_array(jsonb_build_object(
          'item_id', v_item.id,
          'item_name', v_item.product_name,
          'value', v_holes_text,
          'reason', 'no_wheel'
        ));
        continue;
      end if;
      if v_holes_text is null or v_holes_text !~ '^[1-9][0-9]{0,2}$' then
        v_problems := v_problems || jsonb_build_array(jsonb_build_object(
          'item_id', v_item.id,
          'item_name', v_item.product_name,
          'value', v_holes_text,
          'reason', 'invalid_value'
        ));
        continue;
      end if;
      v_value := to_jsonb(v_holes_text::integer);
      v_key := case v_position
        when 'front' then 'frontSpokeHoles'
        else 'rearSpokeHoles'
      end;
      -- Las perforaciones las contó el mecánico en el asistente: confirmadas.
      v_op := 'set';
    else
      -- Un repuesto con marca: lo que el mecánico vio al elegir la rueda, si
      -- todavía calza con el repuesto, la rueda y la ficha técnica del
      -- producto. Si no, se informa y no se escribe nada.
      v_verified := public.job_line_part_change_internal(p_tenant_id, v_item.id);
      if v_verified is null then
        v_problems := v_problems || jsonb_build_array(jsonb_build_object(
          'item_id', v_item.id,
          'item_name', v_item.product_name,
          'key', case
            when jsonb_typeof(v_item.data->'part_change'->'key') = 'string'
              then v_item.data->'part_change'->>'key'
          end,
          'value', v_item.data->'part_change'->'value',
          'reason', 'stale_change'
        ));
        continue;
      end if;
      v_key := v_verified->>'key';
      v_value := v_verified->'value';
      select *
        into v_link
        from public.bike_fact_spec_links l
       where l.id = (v_verified->>'link_id')::uuid;
      -- Lo que dice la ficha técnica del repuesto entra declarado; sólo un
      -- dato verificado del producto se escribe confirmado (20260928110000).
      v_op := case
        when coalesce((v_verified->>'verified')::boolean, false) then 'set'
        else 'declare'
      end;
    end if;

    -- La bici de la línea, con la misma regla que el parche: una línea de
    -- General es de la única bici del trabajo (o de la bici del trabajo, si no
    -- tiene filas de bicis).
    v_bike_id := public.job_line_bike_internal(p_tenant_id, v_item.id);
    if v_bike_id is null then
      v_problems := v_problems || jsonb_build_array(jsonb_build_object(
        'item_id', v_item.id,
        'item_name', v_item.product_name,
        'key', v_key,
        'value', v_value,
        'reason', 'line_without_bike'
      ));
      continue;
    end if;

    -- Rangos de taller, los mismos del parche (el de un repuesto, el de su
    -- relación): fuera de ellos es un error de tipeo en la línea o en la
    -- ficha técnica del producto.
    if not (case
      when v_key in ('frontSpokeHoles', 'rearSpokeHoles')
        then (v_value #>> '{}')::integer between 12 and 48
      -- Un código salió del mapa de su fila o de su familia: ya es de la ficha.
      when v_link.value_map is not null or v_link.constant_value is not null
        then jsonb_typeof(v_value) = 'string'
      when v_link.bike_fact_key is not null
        then jsonb_typeof(v_value) = 'number'
             and (v_value #>> '{}')::numeric
                 between v_link.min_value and v_link.max_value
      else false
    end) then
      v_problems := v_problems || jsonb_build_array(jsonb_build_object(
        'item_id', v_item.id,
        'item_name', v_item.product_name,
        'bike_id', v_bike_id,
        'key', v_key,
        'value', v_value,
        'reason', 'out_of_range'
      ));
      continue;
    end if;

    -- Lo que esta línea dice hoy que instaló: con esto se reconoce abajo lo
    -- que escribió antes y ya no respalda.
    v_claims := v_claims || jsonb_build_array(jsonb_build_object(
      'item_id', v_item.id,
      'bike_id', v_bike_id,
      'key', v_key,
      'value', v_value
    ));

    v_facts_suffix := v_key || '=' || (v_value #>> '{}');
    select parts[1]::integer, parts[2], receipt_bike_id
      into v_latest, v_latest_suffix, v_latest_bike_id
      from (
        select regexp_match(
                 p.operation_key,
                 '^job_completion:[^:]+:([0-9]+):(.*)$'
               ) as parts,
               p.bike_id as receipt_bike_id
          from public.bike_technical_fact_patches p
         where p.tenant_id = p_tenant_id
           and p.operation_key like 'job_completion:' || v_item.id::text || ':%'
      ) receipts
     where parts is not null
     order by parts[1]::integer desc
     limit 1;

    -- Ya escrito en esta bici, o alguien corrigió la ficha después: no se le
    -- pisa. Si la línea pasó a otra bici, esa otra no lo tiene todavía; lo
    -- que quedó en la primera no se deshace solo.
    if v_latest_suffix is not distinct from v_facts_suffix
       and v_latest_bike_id is not distinct from v_bike_id then
      continue;
    end if;
    v_operation_key := 'job_completion:' || v_item.id::text || ':'
      || (coalesce(v_latest, 0) + 1)::text || ':' || v_facts_suffix;

    begin
      -- Lo instalado vale aunque la ficha dijera otra cosa: se toma la bici y
      -- su ficha antes de leer el valor actual, para que el parche compare con
      -- lo que de verdad hay.
      v_wheel_size := null;
      select b.wheel_size
        into v_wheel_size
        from public.bikes b
       where b.id = v_bike_id
         and b.tenant_id = p_tenant_id
       for update;
      v_current := null;
      v_current_confirmed := false;
      v_misfit := null;
      v_profile_values := null;
      v_profile_sources := null;
      select bp.technical_profile->'values'->v_key,
             coalesce(bp.technical_profile->'confirmed'->>v_key, 'false') = 'true',
             public.bike_fact_part_misfit_internal(
               v_key,
               coalesce(bp.technical_profile->'values', '{}'::jsonb),
               coalesce(bp.technical_profile->'confirmed', '{}'::jsonb)),
             coalesce(bp.technical_profile->'values', '{}'::jsonb),
             coalesce(bp.technical_profile->'sources', '{}'::jsonb)
        into v_current, v_current_confirmed, v_misfit, v_profile_values,
             v_profile_sources
        from public.bike_profiles bp
       where bp.bike_id = v_bike_id
         and bp.tenant_id = p_tenant_id
       for update;

      -- La pieza tiene que calzar con la bici real, mirada con la ficha ya
      -- tomada: lo que su relación pide (un rotor, freno de disco), y lo que
      -- la rueda ya es (un neumático, su BSD o el aro de la bici leído con
      -- ISO 5775). Sin confirmar no se refuta lo que pide; un BSD distinto sí,
      -- venga de donde venga, salvo que lo haya escrito esta misma línea y
      -- siga siendo suyo.
      v_requires := case
        when v_misfit is not null then jsonb_build_object(
          'requires_key', v_link.requires_fact_key,
          'requires_value', v_misfit)
        else public.bike_fact_part_conflict_internal(
          p_tenant_id, v_item.id, v_bike_id, v_key, v_value,
          coalesce(v_profile_values, '{}'::jsonb),
          coalesce(v_profile_sources, '{}'::jsonb), v_wheel_size)
      end;
      -- Calza con lo que la ficha ya dice y es otro código: no es un
      -- problema, y el parche no cambia la ficha (20260928120000).
      if v_requires->>'reason' = 'fits' then
        v_requires := null;
      end if;
      if v_requires->>'reason' = 'pending' then
        -- No calza con la ficha, pero el mismo trabajo cambia la pieza que lo
        -- decide: la maza nueva dice el driver, el mando nuevo la
        -- transmisión. La ficha no cambia sola y la línea no se rechaza:
        -- queda pendiente de que el mecánico lo elija en la ficha.
        v_problems := v_problems || jsonb_build_array(jsonb_build_object(
          'item_id', v_item.id,
          'item_name', v_item.product_name,
          'bike_id', v_bike_id,
          'key', v_key,
          'value', v_value,
          'reason', 'pending',
          'pending', v_requires->>'pending',
          'requires_key', v_requires->>'requires_key',
          'requires_value', v_requires->>'requires_value'
        ));
        perform public.record_installed_bike_fact_notice(
          p_tenant_id, v_bike_id, p_job_id,
          'decision:' || v_item.id::text || ':' || v_key || '='
            || (v_value #>> '{}') || ':' || (v_requires->>'requires_value'),
          'installed_fact_needs_decision',
          'Pendiente: la ficha espera una decisión',
          format(
            '«%s» dice %s y la ficha de la bici dice %s, pero %s y guarda el '
            'trabajo. La ficha no cambió.',
            coalesce(v_item.product_name, 'Una línea'),
            public.installed_bike_fact_label(v_key, v_value),
            public.bike_fact_requirement_text(
              v_requires->>'requires_key', v_requires->>'requires_value'),
            public.bike_fact_pending_text(v_requires->>'pending')),
          jsonb_build_object(
            'item_id', v_item.id,
            'key', v_key,
            'value', v_value,
            'pending', v_requires->>'pending',
            'requires_key', v_requires->>'requires_key',
            'requires_value', v_requires->>'requires_value'),
          p_notices_required);
        continue;
      end if;
      if v_requires is not null then
        v_problems := v_problems || jsonb_build_array(jsonb_build_object(
          'item_id', v_item.id,
          'item_name', v_item.product_name,
          'bike_id', v_bike_id,
          'key', v_key,
          'value', v_value,
          'reason', 'incompatible',
          'requires_key', v_requires->>'requires_key',
          'requires_value', v_requires->>'requires_value'
        ));
        perform public.record_installed_bike_fact_notice(
          p_tenant_id, v_bike_id, p_job_id,
          'incompatible:' || v_item.id::text || ':' || v_key || '='
            || (v_value #>> '{}') || ':' || (v_requires->>'requires_value'),
          'installed_fact_incompatible',
          'Aviso: lo instalado no calza con la ficha',
          format(
            '«%s» dice %s, pero la ficha de la bici dice %s: la ficha no '
            'cambió. %s',
            coalesce(v_item.product_name, 'Una línea'),
            public.installed_bike_fact_label(v_key, v_value),
            public.bike_fact_requirement_text(
              v_requires->>'requires_key', v_requires->>'requires_value'),
            public.bike_fact_requirement_advice(v_requires->>'requires_key')),
          jsonb_build_object(
            'item_id', v_item.id,
            'key', v_key,
            'value', v_value,
            'requires_key', v_requires->>'requires_key',
            'requires_value', v_requires->>'requires_value'),
          p_notices_required);
        continue;
      end if;

      v_receipt := public.patch_bike_technical_facts_v1(
        v_operation_key,
        v_bike_id,
        p_job_id,
        'job_completion',
        jsonb_build_array(jsonb_build_object(
          'key', v_key,
          'op', v_op,
          'value', v_value,
          'expected', coalesce(v_current, 'null'::jsonb),
          'expected_confirmed', coalesce(v_current_confirmed, false)
        ))
      );
      v_applied := v_applied || jsonb_build_array(jsonb_build_object(
        'item_id', v_item.id,
        'item_name', v_item.product_name,
        'bike_id', v_bike_id,
        'key', v_key,
        'value', v_value,
        'op', v_op,
        'previous', v_current,
        'operation_key', v_operation_key,
        'changed', jsonb_array_length(coalesce(v_receipt->'applied', '[]'::jsonb)) > 0
      ));
    exception
      when others then
        v_problems := v_problems || jsonb_build_array(jsonb_build_object(
          'item_id', v_item.id,
          'item_name', v_item.product_name,
          'bike_id', v_bike_id,
          'key', v_key,
          'value', v_value,
          'reason', 'rejected',
          'code', sqlstate,
          'message', sqlerrm
        ));
        -- Queda pendiente: se reintenta con la misma llave la próxima vez, y
        -- mientras tanto la bici lo dice en su historia.
        perform public.record_installed_bike_fact_notice(
          p_tenant_id, v_bike_id, p_job_id,
          'pending:' || v_operation_key,
          'installed_fact_pending',
          'Pendiente: la ficha no tomó lo instalado',
          format(
            'La ficha no tomó %s de «%s» (%s). Se reintenta al guardar el '
            'trabajo o volver a cambiar su estado.',
            public.installed_bike_fact_label(v_key, v_value),
            coalesce(v_item.product_name, 'una línea'),
            sqlerrm),
          jsonb_build_object(
            'operation_key', v_operation_key,
            'item_id', v_item.id,
            'key', v_key,
            'value', v_value,
            'code', sqlstate),
          p_notices_required);
    end;
  end loop;

  -- Lo que una línea de este trabajo escribió y ya no respalda: pasó a otra
  -- bici o a la otra rueda, cambió de servicio o de repuesto, o se borró. Se
  -- toma lo último que cada línea escribió en cada bici y clave; si la ficha
  -- todavía lo dice con el origen de la línea (`job_completion`) y ningún
  -- recibo posterior escribió esa clave en esa bici, se informa para que el
  -- operador la corrija o la confirme. Confirmarla es elegir el dato en su
  -- campo de la ficha, que deja el origen `mechanic`; guardar la ficha por
  -- otro campo no la revisa (el formulario conserva el origen de lo que no se
  -- tocó).
  for v_prior in
    select distinct on (p.bike_id, fact->>'key', split_part(p.operation_key, ':', 2))
           split_part(p.operation_key, ':', 2) as item_id,
           p.bike_id,
           p.operation_key,
           p.completed_at,
           fact->>'key' as key,
           fact->'to' as written,
           fact->'from' as previous,
           fact->>'op' as op,
           nullif(btrim(concat_ws(' ', b.brand, b.model)), '') as bike_label,
           i.product_name as item_name
      from public.bike_technical_fact_patches p
      cross join lateral jsonb_array_elements(coalesce(p.applied, '[]'::jsonb)) fact
      join public.bikes b
        on b.id = p.bike_id
       and b.tenant_id = p.tenant_id
      left join public.mechanic_job_items i
        on i.id::text = split_part(p.operation_key, ':', 2)
       and i.tenant_id = p.tenant_id
     where p.tenant_id = p_tenant_id
       and p.job_id = p_job_id
       and p.source = 'job_completion'
       and p.operation_key ~ '^job_completion:[^:]+:[0-9]+:'
     order by p.bike_id,
              fact->>'key',
              split_part(p.operation_key, ':', 2),
              split_part(p.operation_key, ':', 3)::integer desc
  loop
    if v_claims @> jsonb_build_array(jsonb_build_object(
         'item_id', v_prior.item_id,
         'bike_id', v_prior.bike_id,
         'key', v_prior.key,
         'value', v_prior.written
       )) then
      continue;
    end if;
    if not exists (
         select 1
           from public.bike_profiles bp
          where bp.bike_id = v_prior.bike_id
            and bp.tenant_id = p_tenant_id
            and bp.technical_profile->'values'->v_prior.key = v_prior.written
            and bp.technical_profile->'sources'->>v_prior.key = 'job_completion'
       ) then
      continue;
    end if;
    if exists (
         select 1
           from public.bike_technical_fact_patches later
          where later.tenant_id = p_tenant_id
            and later.bike_id = v_prior.bike_id
            and later.completed_at > v_prior.completed_at
            and later.operation_key <> v_prior.operation_key
            and (
              later.applied @> jsonb_build_array(
                jsonb_build_object('key', v_prior.key))
              or (
                later.source = 'job_completion'
                and split_part(later.operation_key, ':', 4)
                    ~ ('(^|,)' || v_prior.key || '=')
              )
            )
       ) then
      continue;
    end if;
    v_problems := v_problems || jsonb_build_array(jsonb_build_object(
      'item_id', v_prior.item_id,
      'item_name', v_prior.item_name,
      'bike_id', v_prior.bike_id,
      'bike_label', v_prior.bike_label,
      'key', v_prior.key,
      'value', v_prior.written,
      'previous', v_prior.previous,
      'op', v_prior.op,
      'reason', 'no_longer_installed'
    ));
    perform public.record_installed_bike_fact_notice(
      p_tenant_id, v_prior.bike_id, p_job_id,
      'unsupported:' || v_prior.operation_key || ':' || v_prior.key,
      'installed_fact_unsupported',
      'Aviso: la ficha dice algo que el trabajo ya no respalda',
      format(
        'La ficha dice %s por «%s», que ya no dice haberlo instalado en esta '
        'bici (%s). %s, corrige la ficha; si sí, vuelve a elegir el dato en su '
        'campo para confirmarlo.',
        public.installed_bike_fact_label(v_prior.key, v_prior.written),
        coalesce(v_prior.item_name, 'una línea que ya no está'),
        case
          when v_prior.previous is null or v_prior.previous = 'null'::jsonb
            then 'antes no tenía el dato'
          else 'antes: '
            || public.installed_bike_fact_label(v_prior.key, v_prior.previous)
        end,
        case
          when v_prior.key in ('frontSpokeHoles', 'rearSpokeHoles')
            then 'Si esa rueda no se armó'
          else 'Si esa pieza no se instaló'
        end),
      jsonb_build_object(
        'operation_key', v_prior.operation_key,
        'item_id', v_prior.item_id,
        'key', v_prior.key,
        'value', v_prior.written,
        'previous', v_prior.previous),
      p_notices_required);
  end loop;

  return jsonb_build_object('applied', v_applied, 'problems', v_problems);
end;
$function$;

-- Sólo la llaman los comandos del servidor, que ya comprobaron el taller.
revoke all on function public.apply_job_installed_bike_facts_internal(uuid, uuid, boolean)
  from public, anon, authenticated, service_role;

-- ============================================================================
-- El parche: la transmisión no la escribe un trabajo, y su total
-- ============================================================================

-- Se inserta sobre la definición vigente (la de 20260928110000) y es
-- reejecutable: anclas exactas, cada una una sola vez.
do $do$
declare
  v_fn regprocedure :=
    'public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)'::regprocedure;
  v_def text;
  v_anchors text[] := array[
$a$          where l.bike_fact_key = v_key
       ) then
      raise exception 'Bicycle fact % is not installed by a job', v_key;
$a$,
$a$          when 'drivetrainSpeeds' then v_number = trunc(v_number) and v_number between 1 and 14
$a$,
$a$        v_misfit_value := v_conflict->>'requires_value';
        v_misfit_key := v_conflict->>'requires_key';
      end if;
$a$,
$a$    if v_op = 'declare' and v_current = v_value then
      continue;
    end if;
$a$,
$a$  v_conflict jsonb;
begin
$a$,
$a$  if jsonb_array_length(v_conflicts) > 0 then
    raise exception 'Bicycle facts changed since they were loaded; reload before saving'
      using errcode = 'PT409',
            detail = v_conflicts::text;
  end if;
$a$
  ];
  v_blocks text[] := array[
$a$          where l.bike_fact_key = v_key
            -- Una fila que sólo revisa no instala nada (20260928120000).
            and l.on_mismatch <> 'check'
       ) then
      raise exception 'Bicycle fact % is not installed by a job', v_key;
$a$,
$a$          -- El total platos × piñones, como lo guardan la ficha y el
          -- asistente: 3 × 7 = 21 (20260928120000; antes 1–14).
          when 'drivetrainSpeeds' then v_number = trunc(v_number) and v_number between 1 and 42
$a$,
$a$        v_misfit_value := v_conflict->>'requires_value';
        v_misfit_key := v_conflict->>'requires_key';
        -- Lo que calza con lo que la ficha ya dice no la cambia (un cassette
        -- HG en un núcleo HG Road 11), y lo que espera una decisión no se
        -- escribe (20260928120000).
        if v_conflict->>'reason' = 'fits' then
          v_fits := v_fits || jsonb_build_array(v_fact->>'key');
          v_misfit_value := null;
        elsif v_conflict->>'reason' = 'pending' then
          raise exception 'Installed part % waits for a decision (% is %)',
            v_fact->>'key', v_misfit_key, v_misfit_value
            using errcode = '23514';
        end if;
      end if;
$a$,
$a$    if v_op = 'declare' and v_current = v_value then
      continue;
    end if;

    -- Calza sin ser lo mismo: la ficha no cambia (20260928120000).
    if p_source = 'job_completion' and v_fits ? v_key then
      continue;
    end if;
$a$,
$a$  v_conflict jsonb;
  v_fits jsonb := '[]'::jsonb;
begin
$a$,
$a$  if jsonb_array_length(v_conflicts) > 0 then
    raise exception 'Bicycle facts changed since they were loaded; reload before saving'
      using errcode = 'PT409',
            detail = v_conflicts::text;
  end if;

  -- El total de velocidades es platos × piñones: lo que escribe un parche no
  -- deja la ficha diciendo 2x8 y 24 (20260928120000; en producción ninguna
  -- ficha lo tiene incoherente).
  if exists (
       select 1
         from jsonb_array_elements(v_applied) a
        where a->>'key' in ('drivetrainSpeeds', 'drivetrainConfig'))
     -- Por valor: 24.0 es 24 (revisión de Codex, 2026-09-28).
     and (v_values->>'drivetrainSpeeds') ~ '^[0-9]{1,3}(\.[0-9]+)?$'
     and public.drivetrain_total_speeds(v_values->>'drivetrainConfig') is not null
     and (v_values->>'drivetrainSpeeds')::numeric
         <> public.drivetrain_total_speeds(v_values->>'drivetrainConfig') then
    raise exception 'Bicycle drivetrain speeds % do not match its configuration %',
      v_values->>'drivetrainSpeeds', v_values->>'drivetrainConfig';
  end if;
$a$
  ];
  v_index integer;
begin
  v_def := pg_get_functiondef(v_fn);
  if position('Una fila que sólo revisa no instala nada (20260928120000)' in v_def) > 0 then
    return;
  end if;
  for v_index in 1 .. array_length(v_anchors, 1) loop
    if (length(v_def) - length(replace(v_def, v_anchors[v_index], '')))
       / length(v_anchors[v_index]) <> 1 then
      raise exception 'patch anchor % not found exactly once', v_index;
    end if;
    v_def := replace(v_def, v_anchors[v_index], v_blocks[v_index]);
  end loop;
  execute v_def;
end;
$do$;


-- ============================================================================
-- El disparador de líneas: una línea sin bici dice cómo resolverlo
-- ============================================================================

-- En General de un trabajo con varias bicis una línea no es de ninguna. El
-- formulario tiene «Asignar a <bici>» en el menú de la línea, que la pasa
-- con su id (2026-09-28); el rechazo lo dice. Reejecutable.
do $do$
declare
  v_fn regprocedure :=
    'public.apply_installed_bike_facts_on_job_line_change()'::regprocedure;
  v_def text;
  v_anchor text := $a$      else format(
        '«%s» no se guardó: no dice de qué bici del trabajo es.', v_line_name)
$a$;
  v_block text := $a$      else format(
        '«%s» no se guardó: no dice de qué bici del trabajo es. Asígnala a '
        'su bici («Asignar a…» en el menú de la línea) y guarda.', v_line_name)
$a$;
begin
  v_def := pg_get_functiondef(v_fn);
  if position('«Asignar a…» en el menú de la línea' in v_def) > 0 then
    return;
  end if;
  if (length(v_def) - length(replace(v_def, v_anchor, ''))) / length(v_anchor) <> 1 then
    raise exception 'apply_installed_bike_facts_on_job_line_change no tiene el texto esperado';
  end if;
  execute replace(v_def, v_anchor, v_block);
end;
$do$;

commit;
