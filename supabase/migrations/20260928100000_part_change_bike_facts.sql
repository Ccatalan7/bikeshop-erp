-- Deployment status: NOT DEPLOYED
-- Cambios de partes, primer corte vertical: el rotor
-- (BIKE_WORKSHOP_MASTER_SCHEMA.md, «Cambios de partes: el rotor»).
--
-- Hasta aquí sólo el Enrayado cambiaba la ficha al terminar un trabajo. Un
-- repuesto instalado no la tocaba: un rotor de 180 mm puesto atrás dejaba la
-- ficha en 160 mm. Ahora:
--
-- * `bike_fact_spec_links` es la relación única concepto + posición entre la
--   ficha técnica del producto y la ficha de la bici: `rotor_diameter_mm_value`
--   en la rueda delantera es `frontRotorSizeMm`; en la trasera,
--   `rearRotorSizeMm`. Lleva también lo que la bici tiene que tener para que
--   la pieza calce (`requires_fact_key` / `requires_fact_values`: un rotor
--   pide freno de disco). La leen el servidor al terminar y el formulario para
--   mostrar el cambio en la línea; ningún módulo tiene la suya.
-- * El valor del producto se lee con el mismo lector que la app
--   (`get_product_spec_contexts_v1` → `spec_active_product_values_internal_v1`):
--   los valores vigentes de su plantilla, sin campos retirados. El diámetro
--   retirado `rotor_diameter_mm` (que guarda pares como 180/160) no cuenta.
-- * La línea de repuesto guarda en `service_configuration_data.part_change`
--   el cambio que el mecánico vio al elegir la rueda (`{"key", "value"}`).
--   Sin esa marca un repuesto no cambia la ficha: las 667 líneas de repuesto
--   de producción no tienen configuración, y 4 líneas de rotor antiguas
--   tienen rueda; al volver a guardar esos trabajos terminados no reescriben
--   fichas que el taller corrigió después.
-- * `apply_job_installed_bike_facts_internal` aplica la marca al terminar o
--   entregar (la transición) y al guardar un trabajo terminado, por la misma
--   puerta (`patch_bike_technical_facts_v1`, fuente `job_completion`), con la
--   misma llave `job_completion:<línea>:<n>:<clave>=<valor>`, los mismos
--   recibos y el mismo aviso de lo que una línea borrada ya no respalda.
--   Antes de escribir comprueba, con la ficha real de la bici, que la pieza
--   calce: un rotor en una bici con freno de llanta confirmado no se escribe;
--   vuelve como problema y queda en la historia de la bici. Si la marca ya no
--   coincide con el repuesto o con la rueda de la línea (se cambió el
--   repuesto, la rueda o su ficha técnica), tampoco.
-- * `patch_bike_technical_facts_v1` acepta las claves de la relación con
--   fuente `job_completion` sólo si la línea las respalda con las mismas
--   reglas que el aplicador: la marca (`job_line_part_change_internal`), la
--   bici de la línea (`job_line_bike_internal`) y que la pieza calce con la
--   ficha bajo su lock (`bike_fact_part_misfit_internal`). Además, desde esta
--   migración y para toda fuente `job_completion` (revisión de Codex,
--   2026-09-28): la condición de la línea tiene que ser verdadera, no sólo
--   «no falsa» (una línea delantera sin `hole_count` dejaba pasar 28H por un
--   nulo, desde `20260928020000`); una línea no instala perforaciones y un
--   repuesto a la vez; y lo que una línea ya escribió en una bici no se
--   vuelve a imponer con otra llave, así que una corrección posterior de la
--   ficha se respeta también ante una llamada directa.
-- * El disparador de líneas de `20260928070000` cuenta también las líneas con
--   marca y el cambio de repuesto (`product_id`), y una línea que instala algo
--   no se mueve a otro trabajo (nada en la app lo hace; un `update` directo
--   dejaba el recibo en una bici sin aviso).
--
-- Si un conflicto real impide terminar el trabajo sigue siendo una decisión
-- abierta del dueño: hoy lo que no entra vuelve como problema y no lo impide.
--
-- Depende de `20260928060000` y `20260928070000`.
begin;

-- ============================================================================
-- La relación única concepto + posición
-- ============================================================================

create table if not exists public.bike_fact_spec_links (
  spec_key text not null,
  position text not null check (position in ('front', 'rear')),
  bike_fact_key text not null unique,
  component_label text not null,
  unit text,
  requires_fact_key text,
  requires_fact_values text[] not null default '{}'::text[],
  min_value numeric not null default 0,
  max_value numeric not null default 0,
  created_at timestamptz not null default now(),
  primary key (spec_key, position),
  check ((requires_fact_key is null) = (cardinality(requires_fact_values) = 0))
);

-- El rango de taller de la clave, el mismo del parche: una medida fuera de él
-- es un error de la ficha técnica y no se propone.
alter table public.bike_fact_spec_links
  add column if not exists min_value numeric not null default 0,
  add column if not exists max_value numeric not null default 0;

comment on table public.bike_fact_spec_links is
  'Relación única concepto + posición entre la ficha técnica de un producto '
  '(spec_definitions.key) y la ficha de la bici (technical_profile.values). '
  'La leen el servidor al terminar un trabajo y el formulario del trabajo.';

-- Un rotor pide freno de disco (vocabulario de `brakeType`,
-- brake_canonical_data.dart). Las medidas por rueda son las de la ficha.
insert into public.bike_fact_spec_links (
  spec_key, position, bike_fact_key, component_label, unit,
  requires_fact_key, requires_fact_values, min_value, max_value
) values
  ('rotor_diameter_mm_value', 'front', 'frontRotorSizeMm', 'rotor delantero',
   'mm', 'brakeType', array['mechanical_disc', 'hydraulic_disc'], 100, 260),
  ('rotor_diameter_mm_value', 'rear', 'rearRotorSizeMm', 'rotor trasero',
   'mm', 'brakeType', array['mechanical_disc', 'hydraulic_disc'], 100, 260)
on conflict (spec_key, position) do update
   set bike_fact_key = excluded.bike_fact_key,
       component_label = excluded.component_label,
       unit = excluded.unit,
       requires_fact_key = excluded.requires_fact_key,
       requires_fact_values = excluded.requires_fact_values,
       min_value = excluded.min_value,
       max_value = excluded.max_value;

alter table public.bike_fact_spec_links
  drop constraint if exists bike_fact_spec_links_range_check;
alter table public.bike_fact_spec_links
  add constraint bike_fact_spec_links_range_check
  check (min_value > 0 and max_value >= min_value);

-- Configuración global, igual para todo taller: se lee, no se escribe desde
-- la app.
alter table public.bike_fact_spec_links enable row level security;
revoke all on table public.bike_fact_spec_links from public, anon, authenticated;
grant select on table public.bike_fact_spec_links to authenticated;
drop policy if exists bike_fact_spec_links_read on public.bike_fact_spec_links;
create policy bike_fact_spec_links_read
  on public.bike_fact_spec_links
  for select
  to authenticated
  using (true);

-- ============================================================================
-- El valor del producto y la marca de la línea
-- ============================================================================

-- El mismo lector que la app (`get_product_spec_contexts_v1`): los valores
-- vigentes de la plantilla del producto, sin campos retirados.
create or replace function public.product_bike_fact_spec_value_internal(
  p_tenant_id uuid,
  p_product_id uuid,
  p_spec_key text
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_value jsonb;
begin
  select public.spec_active_product_values_internal_v1(p.id, t.id) -> p_spec_key
    into v_value
    from public.products p
    join public.product_spec_bindings_internal_v1 b
      on b.product_id = p.id
    join public.spec_templates t
      on t.id = b.template_id
     and t.is_active
     and (t.tenant_id is null or t.tenant_id = p.tenant_id)
   where p.id = p_product_id
     and p.tenant_id = p_tenant_id;
  return v_value;
end;
$function$;

revoke all on function public.product_bike_fact_spec_value_internal(uuid, uuid, text)
  from public, anon, authenticated, service_role;

-- Lo que una línea de repuesto instala en la ficha, si su marca todavía lo
-- respalda: la clave es la de la relación para la rueda de la línea y el
-- valor es el que dice hoy la ficha técnica de su producto. Una sola regla
-- para el servidor que aplica y para el parche que lo valida.
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
  v_marked text;
  v_spec text;
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

  select *
    into v_link
    from public.bike_fact_spec_links l
   where l.bike_fact_key = v_item.service_configuration_data->'part_change'->>'key'
     and l.position = v_item.location_key;
  if not found then
    return null;
  end if;

  v_marked := v_item.service_configuration_data->'part_change'->>'value';
  v_spec := public.product_bike_fact_spec_value_internal(
    p_tenant_id, v_item.product_id, v_link.spec_key) #>> '{}';
  -- Medidas enteras (mm): un decimal no se redondea a una medida de la ficha.
  if v_marked is null
     or v_spec is null
     or v_marked !~ '^[0-9]{1,4}(\.0+)?$'
     or v_spec !~ '^[0-9]{1,4}(\.0+)?$' then
    return null;
  end if;
  if v_marked::numeric <> v_spec::numeric then
    return null;
  end if;

  return jsonb_build_object(
    'key', v_link.bike_fact_key,
    'value', v_spec::numeric::integer,
    'spec_key', v_link.spec_key,
    'position', v_link.position
  );
end;
$function$;

revoke all on function public.job_line_part_change_internal(uuid, uuid)
  from public, anon, authenticated, service_role;

-- La bici de una línea, una sola regla para el aplicador y el parche: la de
-- su pestaña; una línea de General es de la única bici del trabajo, o de la
-- bici del trabajo si no tiene filas de bicis; en un trabajo de varias, de
-- ninguna. Antes el parche aceptaba también la bici de la cabecera, que puede
-- no ser la única fila de bicis (revisión de Codex, 2026-09-28).
create or replace function public.job_line_bike_internal(
  p_tenant_id uuid,
  p_item_id uuid
)
returns uuid
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_item public.mechanic_job_items%rowtype;
  v_count integer;
  v_single uuid;
begin
  select *
    into v_item
    from public.mechanic_job_items i
   where i.id = p_item_id
     and i.tenant_id = p_tenant_id;
  if not found then
    return null;
  end if;
  if v_item.job_bike_id is not null then
    return (
      select jb.bike_id
        from public.mechanic_job_bikes jb
       where jb.id = v_item.job_bike_id
         and jb.job_id = v_item.job_id
         and jb.tenant_id = p_tenant_id
    );
  end if;
  select count(*)::integer, min(jb.bike_id::text)::uuid
    into v_count, v_single
    from public.mechanic_job_bikes jb
   where jb.job_id = v_item.job_id
     and jb.tenant_id = p_tenant_id;
  if v_count = 1 then
    return v_single;
  end if;
  if v_count = 0 then
    return (
      select j.bike_id
        from public.mechanic_jobs j
       where j.id = v_item.job_id
         and j.tenant_id = p_tenant_id
    );
  end if;
  return null;
end;
$function$;

revoke all on function public.job_line_bike_internal(uuid, uuid)
  from public, anon, authenticated, service_role;

-- Con qué no calza la pieza de esa clave en una ficha: lo que su relación
-- pide de la bici, confirmado con otro valor (un rotor y un freno de llanta).
-- Nulo si calza o si la ficha no lo confirma. Una sola regla para el
-- aplicador, que la mira después de tomar la ficha, y el parche.
create or replace function public.bike_fact_part_misfit_internal(
  p_bike_fact_key text,
  p_values jsonb,
  p_confirmed jsonb
)
returns text
language sql
stable
set search_path to 'public'
as $function$
  select p_values->>l.requires_fact_key
    from public.bike_fact_spec_links l
   where l.bike_fact_key = p_bike_fact_key
     and l.requires_fact_key is not null
     and coalesce(p_confirmed->>l.requires_fact_key, 'false') = 'true'
     and p_values->>l.requires_fact_key is not null
     and not ((p_values->>l.requires_fact_key) = any (l.requires_fact_values));
$function$;

revoke all on function public.bike_fact_part_misfit_internal(text, jsonb, jsonb)
  from public, anon, authenticated, service_role;

-- Lo que la ficha confirma y con lo que una pieza no calza, con la etiqueta
-- del editor de la ficha (`kBikeProfileBrakeTypeOptions`).
create or replace function public.bike_fact_requirement_label(p_value text)
returns text
language sql
immutable
set search_path to 'public'
as $function$
  select case p_value
    when 'rim' then 'Llanta (rim)'
    when 'mechanical_disc' then 'Disco mecánico'
    when 'hydraulic_disc' then 'Disco hidráulico'
    when 'roller_brake' then 'Roller brake'
    when 'drum_brake' then 'Tambor'
    when 'coaster_brake' then 'Contrapedal'
    when 'band_brake' then 'Banda'
    else coalesce(p_value, 'otro sistema')
  end;
$function$;

revoke all on function public.bike_fact_requirement_label(text)
  from public, anon, authenticated, service_role;

-- «36H en la rueda delantera», «180 mm en el rotor trasero»: como lo dice el
-- taller. Lo que no es perforación sale de la relación.
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
    else coalesce(
      (select coalesce(p_value #>> '{}', '?') || coalesce(' ' || l.unit, '')
                || ' en el ' || l.component_label
         from public.bike_fact_spec_links l
        where l.bike_fact_key = p_key),
      coalesce(p_key, '?') || ' = ' || coalesce(p_value #>> '{}', '?'))
  end;
$function$;

revoke all on function public.installed_bike_fact_label(text, jsonb)
  from public, anon, authenticated, service_role;

-- ============================================================================
-- Aplicar lo instalado: también los repuestos con marca
-- ============================================================================

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
  v_value integer;
  v_key text;
  v_link public.bike_fact_spec_links%rowtype;
  v_verified jsonb;
  v_misfit text;
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
    -- repuesto. Con las dos, se informa y no se escribe ninguna (revisión de
    -- Codex, 2026-09-28: antes se tomaban las perforaciones y el rotor se
    -- perdía en silencio).
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
      v_value := v_holes_text::integer;
      v_key := case v_position
        when 'front' then 'frontSpokeHoles'
        else 'rearSpokeHoles'
      end;
    else
      -- Un repuesto con marca (2026-09-28): lo que el mecánico vio al elegir
      -- la rueda, si todavía calza con el repuesto, la rueda y la ficha
      -- técnica del producto. Si no, se informa y no se escribe nada.
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
      v_value := (v_verified->>'value')::integer;
      select *
        into v_link
        from public.bike_fact_spec_links l
       where l.bike_fact_key = v_key;
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
        then v_value between 12 and 48
      when v_link.bike_fact_key is not null
        then v_value between v_link.min_value and v_link.max_value
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

    v_facts_suffix := v_key || '=' || v_value::text;
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
      perform 1
         from public.bikes b
        where b.id = v_bike_id
          and b.tenant_id = p_tenant_id
        for update;
      v_current := null;
      v_current_confirmed := false;
      v_misfit := null;
      select bp.technical_profile->'values'->v_key,
             coalesce(bp.technical_profile->'confirmed'->>v_key, 'false') = 'true',
             public.bike_fact_part_misfit_internal(
               v_key,
               coalesce(bp.technical_profile->'values', '{}'::jsonb),
               coalesce(bp.technical_profile->'confirmed', '{}'::jsonb))
        into v_current, v_current_confirmed, v_misfit
        from public.bike_profiles bp
       where bp.bike_id = v_bike_id
         and bp.tenant_id = p_tenant_id
       for update;

      -- La pieza tiene que calzar con la bici real, mirada con la ficha ya
      -- tomada (revisión de Codex, 2026-09-28: leerla antes del lock dejaba
      -- pasar un cambio a freno de llanta hecho entre medio). Lo que su
      -- relación pide (un rotor, freno de disco) no puede estar confirmado con
      -- otro valor; sin confirmar no se refuta: la pieza instalada es el dato.
      if v_misfit is not null then
        v_problems := v_problems || jsonb_build_array(jsonb_build_object(
          'item_id', v_item.id,
          'item_name', v_item.product_name,
          'bike_id', v_bike_id,
          'key', v_key,
          'value', v_value,
          'reason', 'incompatible',
          'requires_key', v_link.requires_fact_key,
          'requires_value', v_misfit
        ));
        perform public.record_installed_bike_fact_notice(
          p_tenant_id, v_bike_id, p_job_id,
          'incompatible:' || v_item.id::text || ':' || v_key || '='
            || v_value::text || ':' || v_misfit,
          'installed_fact_incompatible',
          'Aviso: lo instalado no calza con la ficha',
          format(
            '«%s» dice %s, pero en la ficha el tipo de freno es «%s»: la '
            'ficha no cambió. Si la bici lleva freno de disco, corrige el tipo '
            'de freno en su ficha y guarda el trabajo; si no, quita la línea.',
            coalesce(v_item.product_name, 'Una línea'),
            public.installed_bike_fact_label(v_key, to_jsonb(v_value)),
            public.bike_fact_requirement_label(v_misfit)),
          jsonb_build_object(
            'item_id', v_item.id,
            'key', v_key,
            'value', v_value,
            'requires_key', v_link.requires_fact_key,
            'requires_value', v_misfit),
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
          'op', 'set',
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
            public.installed_bike_fact_label(v_key, to_jsonb(v_value)),
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
-- El parche: las claves de la relación, respaldadas por su línea
-- ============================================================================

-- Se inserta sobre la definición vigente (sin tocar el resto) y es
-- reejecutable: cuatro anclas exactas, cada una una sola vez.
do $do$
declare
  v_fn regprocedure :=
    'public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)'::regprocedure;
  v_def text;
  v_anchors text[] := array[
    $a$  v_facts_suffix text;
begin
$a$,
    $a$    if p_source = 'job_completion'
       and v_key not in ('frontSpokeHoles', 'rearSpokeHoles') then
      raise exception 'Bicycle fact % is not installed by a job', v_key;
$a$,
    $a$    for v_fact in select value from jsonb_array_elements(p_facts)
    loop
      if not (
        (
          (v_fact->>'key' = 'frontSpokeHoles' and v_item_position = 'front')
          or (v_fact->>'key' = 'rearSpokeHoles' and v_item_position = 'rear')
        )
        and v_item.service_configuration_data->>'hole_count'
            = v_fact->>'value'
      ) then
        raise exception 'The job line did not install %', v_fact->>'key';
      end if;
    end loop;
$a$,
    $a$  v_wheel_size := v_bike.wheel_size;
$a$
  ];
  v_blocks text[] := array[
    $a$  v_facts_suffix text;
  v_line_latest_suffix text;
  v_line_latest_bike_id uuid;
  v_misfit_value text;
begin
$a$,
    $a$    -- Un repuesto instala las claves de la relación concepto + posición
    -- (20260928100000).
    if p_source = 'job_completion'
       and v_key not in ('frontSpokeHoles', 'rearSpokeHoles')
       and not exists (
         select 1
           from public.bike_fact_spec_links l
          where l.bike_fact_key = v_key
       ) then
      raise exception 'Bicycle fact % is not installed by a job', v_key;
$a$,
    $a$    -- Una línea instala una sola cosa: perforaciones o un repuesto
    -- (20260928100000).
    if v_item.service_configuration_data ? 'hole_count'
       and v_item.service_configuration_data ? 'part_change' then
      raise exception 'A job line installs spoke holes or a part, not both';
    end if;

    -- La bici de la línea es una sola, con la regla del aplicador: la
    -- cabecera no sirve de puerta para una línea de General cuya única fila
    -- de bicis es otra (20260928100000).
    if public.job_line_bike_internal(v_tenant_id, v_item.id)
       is distinct from v_bike.id then
      raise exception 'The job line is not part of this job and bicycle'
        using errcode = 'insufficient_privilege';
    end if;

    -- Lo que la línea ya escribió en esta bici no se vuelve a imponer con
    -- otra llave: una corrección posterior de la ficha se respeta también
    -- ante una llamada directa (20260928100000). La misma llave es un replay
    -- y ya volvió arriba.
    select parts[2], receipt_bike_id
      into v_line_latest_suffix, v_line_latest_bike_id
      from (
        select regexp_match(
                 p.operation_key,
                 '^job_completion:[^:]+:([0-9]+):(.*)$'
               ) as parts,
               p.bike_id as receipt_bike_id
          from public.bike_technical_fact_patches p
         where p.tenant_id = v_tenant_id
           and p.operation_key like 'job_completion:' || v_item_id::text || ':%'
      ) receipts
     where parts is not null
     order by parts[1]::integer desc
     limit 1;
    if v_line_latest_suffix is not distinct from v_facts_suffix
       and v_line_latest_bike_id is not distinct from v_bike.id then
      raise exception 'The job line already installed these facts on this bicycle; later corrections are kept';
    end if;

    for v_fact in select value from jsonb_array_elements(p_facts)
    loop
      -- Toda la condición tiene que ser verdadera: un nulo (una línea sin
      -- `hole_count`) no deja pasar (20260928100000). O las perforaciones que
      -- armó la línea en su rueda, o el repuesto cuya marca respalda esa
      -- clave y ese valor en la rueda de la línea.
      if (
        (
          (
            (v_fact->>'key' = 'frontSpokeHoles' and v_item_position = 'front')
            or (v_fact->>'key' = 'rearSpokeHoles' and v_item_position = 'rear')
          )
          and v_item.service_configuration_data->>'hole_count'
              = v_fact->>'value'
        )
        or public.job_line_part_change_internal(v_tenant_id, v_item.id)
           @> jsonb_build_object('key', v_fact->>'key', 'value', v_fact->'value')
      ) is not true then
        raise exception 'The job line did not install %', v_fact->>'key';
      end if;
    end loop;
$a$,
    $a$  v_wheel_size := v_bike.wheel_size;

  -- Una pieza instalada tiene que calzar con la bici, mirada con la ficha ya
  -- tomada: lo que su relación pide (un rotor, freno de disco) no puede estar
  -- confirmado con otro valor (20260928100000). La misma regla que el
  -- aplicador, que no llega aquí con una pieza que no calza.
  if p_source = 'job_completion' then
    for v_fact in select value from jsonb_array_elements(p_facts)
    loop
      v_misfit_value := public.bike_fact_part_misfit_internal(
        v_fact->>'key', v_values, v_confirmed);
      if v_misfit_value is not null then
        raise exception 'Installed part % does not fit the bicycle (% is %)',
          v_fact->>'key',
          (select l.requires_fact_key
             from public.bike_fact_spec_links l
            where l.bike_fact_key = v_fact->>'key'),
          v_misfit_value
          using errcode = '23514';
      end if;
    end loop;
  end if;
$a$
  ];
  i integer;
begin
  v_def := pg_get_functiondef(v_fn);
  if position('Una línea instala una sola cosa: perforaciones o un repuesto' in v_def) > 0 then
    return;
  end if;
  for i in 1 .. array_length(v_anchors, 1) loop
    if (length(v_def) - length(replace(v_def, v_anchors[i], ''))) / length(v_anchors[i]) <> 1 then
      raise exception 'patch_bike_technical_facts_v1 no tiene el ancla % esperada', i;
    end if;
  end loop;
  for i in 1 .. array_length(v_anchors, 1) loop
    v_def := replace(v_def, v_anchors[i], v_blocks[i]);
  end loop;
  execute v_def;
end;
$do$;

-- ============================================================================
-- El disparador de líneas: también los repuestos con marca
-- ============================================================================

create or replace function public.apply_installed_bike_facts_on_job_line_change()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_line public.mechanic_job_items%rowtype;
  v_installs boolean := false;
  v_installed_before boolean := false;
  v_status text;
  v_result jsonb;
  v_problem jsonb;
  v_line_name text;
  v_fact text;
begin
  if tg_op = 'DELETE' then
    v_line := old;
    v_installed_before := old.service_configuration_data ? 'hole_count'
      or old.service_configuration_data ? 'part_change';
  else
    v_line := new;
    v_installs := new.service_configuration_data ? 'hole_count'
      or new.service_configuration_data ? 'part_change';
    if tg_op = 'UPDATE' then
      v_installed_before := old.service_configuration_data ? 'hole_count'
        or old.service_configuration_data ? 'part_change';
    end if;
  end if;
  if not v_installs and not v_installed_before then
    return null;
  end if;

  -- Una línea que instala algo no se mueve a otro trabajo: su recibo quedaría
  -- en la bici del primero sin aviso y el segundo no la aplicaría. Nada en la
  -- app lo hace (revisión de Codex, 2026-09-28).
  if tg_op = 'UPDATE' and old.job_id is distinct from new.job_id then
    raise exception '«%» no se movió: una línea que cambia la ficha de la bici no pasa a otro trabajo. Bórrala y agrégala en el otro.',
      coalesce(nullif(btrim(new.product_name), ''), 'La línea')
      using errcode = '23514';
  end if;

  select j.status
    into v_status
    from public.mechanic_jobs j
   where j.id = v_line.job_id
     and j.tenant_id = v_line.tenant_id
     and j.deleted_at is null
   for no key update;

  if v_status is null or v_status not in ('FINALIZADO', 'ENTREGADO') then
    return null;
  end if;

  -- Los avisos que anota este cambio son obligatorios: si la historia de la
  -- bici no los acepta, la línea no se borra ni se guarda.
  v_result := public.apply_job_installed_bike_facts_internal(
    v_line.tenant_id,
    v_line.job_id,
    true
  );

  if not v_installs then
    return null;
  end if;

  -- Lo que esta línea instala tiene que quedar en la ficha con ella.
  select problem
    into v_problem
    from jsonb_array_elements(coalesce(v_result->'problems', '[]'::jsonb)) problem
   where problem->>'item_id' = v_line.id::text
     and problem->>'reason' in (
       'rejected', 'out_of_range', 'no_wheel', 'invalid_value',
       'line_without_bike', 'incompatible', 'stale_change', 'mixed_change'
     )
   limit 1;
  if v_problem is null then
    return null;
  end if;

  v_line_name := coalesce(nullif(btrim(v_line.product_name), ''), 'La línea');
  v_fact := case
    when v_problem ? 'key' and v_problem->>'key' is not null
      then public.installed_bike_fact_label(v_problem->>'key', v_problem->'value')
    else coalesce(v_problem->>'value', '?') || ' perforaciones'
  end;
  raise exception '%', case v_problem->>'reason'
      when 'rejected' then format(
        '«%s» no se guardó: la ficha de la bici no tomó %s (%s). En un '
        'trabajo terminado la línea y la ficha se guardan juntas; vuelve a '
        'intentarlo.', v_line_name, v_fact, v_problem->>'message')
      when 'out_of_range' then case
        when v_problem->>'key' in ('frontSpokeHoles', 'rearSpokeHoles')
          then format(
            '«%s» no se guardó: %s está fuera de 12 a 48 perforaciones.',
            v_line_name, v_fact)
        else format(
          '«%s» no se guardó: %s está fuera de lo que acepta la ficha. '
          'Revisa la ficha técnica del repuesto.', v_line_name, v_fact)
      end
      when 'no_wheel' then format(
        '«%s» no se guardó: tiene perforaciones pero no dice qué rueda armó.',
        v_line_name)
      when 'invalid_value' then format(
        '«%s» no se guardó: %s no es un número de perforaciones.',
        v_line_name, coalesce(v_problem->>'value', '?'))
      when 'incompatible' then format(
        '«%s» no se guardó: %s no calza con la ficha de la bici (tipo de '
        'freno «%s»). En un trabajo terminado la línea y la ficha se guardan '
        'juntas: corrige la ficha o la línea.',
        v_line_name, v_fact,
        public.bike_fact_requirement_label(v_problem->>'requires_value'))
      when 'mixed_change' then format(
        '«%s» no se guardó: dice perforaciones y un cambio de repuesto a la '
        'vez, y una línea instala una sola cosa.', v_line_name)
      when 'stale_change' then format(
        '«%s» no se guardó: el cambio de ficha que dice (%s) ya no calza con '
        'su repuesto o con la rueda elegida. Vuelve a elegir la rueda y '
        'guarda.', v_line_name, v_fact)
      else format(
        '«%s» no se guardó: no dice de qué bici del trabajo es.', v_line_name)
    end
    using errcode = '23514',
          detail = v_problem::text;
end;
$function$;

revoke all on function public.apply_installed_bike_facts_on_job_line_change()
  from public, anon, authenticated, service_role;

-- Cambiar el repuesto de una línea con marca también cuenta, y moverla de
-- trabajo se detiene.
drop trigger if exists trg_mechanic_job_items_installed_bike_facts_update
  on public.mechanic_job_items;
create trigger trg_mechanic_job_items_installed_bike_facts_update
  after update of service_configuration_data, location_key, job_bike_id,
    product_id, job_id
  on public.mechanic_job_items
  for each row
  when (
    old.service_configuration_data is distinct from new.service_configuration_data
    or old.location_key is distinct from new.location_key
    or old.job_bike_id is distinct from new.job_bike_id
    or old.product_id is distinct from new.product_id
    or old.job_id is distinct from new.job_id
  )
  execute function public.apply_installed_bike_facts_on_job_line_change();

commit;
