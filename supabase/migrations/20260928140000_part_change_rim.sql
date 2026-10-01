-- Deployment status: NOT DEPLOYED
-- Cambios de partes, quinto concepto: la llanta de cada rueda
-- (BIKE_WORKSHOP_MASTER_SCHEMA.md, «Cambios de partes: la llanta»).
--
-- Lo que dicen los datos de producción (2026-09-28, sólo lectura) y lo que
-- se decidió con ellos:
--
-- * 44 llantas (plantilla `rim`), ninguna verificada. Las 44 dicen sus
--   perforaciones (`spoke_hole_count`: 28, 32 o 36); sólo 9 dicen su BSD
--   (`bead_seat_diameter_mm`: 559, 584 o 622) y 5 su ETRTO. Ninguna dice su
--   posición: la rueda la elige el mecánico. El nombre de las otras 35 dice
--   «26», «27,5», «29» o «700c», pero eso es la pulgada nominal: 26″ son al
--   menos seis BSD. **El BSD no se infiere del nombre ni del rótulo**: una
--   llanta sin BSD en su ficha técnica propone sólo sus perforaciones.
-- * Las 10 líneas reales de llanta están ENTREGADAS, ninguna con rueda
--   elegida (dos con cantidad 2), y todas vienen con un «Enrayado +
--   Centrado». PG-00389 (Oxford Orion 4, ficha 36/36): llanta FOSS F22 32H,
--   maza Eclipse 32H y neumático Kenda 622 en el mismo trabajo.
-- * La llanta **cambia** la rueda: sus perforaciones (`front/rearSpokeHoles`)
--   y su BSD (`front/rearWheelBsdMm`), una marca por dato y un recibo por
--   línea. Pero cambiar no es escribir cualquier cosa: la rueda que queda
--   tiene que calzar.
--   - Perforaciones: la rueda la arma el Enrayado del mismo trabajo (su
--     cuenta tiene que ser la de la llanta; otra llanta en esa rueda con otra
--     cuenta tampoco se sabe cuál vale), y se raya en la maza de esa rueda: la
--     maza del mismo trabajo, si no la que queda, que es la que la ficha
--     decía antes de este trabajo. Una maza con menos perforaciones que la
--     llanta no se raya; con más, sólo en los patrones de Sheldon Brown
--     (`hub_lacing_fits`).
--   - BSD: el neumático de esa rueda tiene el mismo BSD. El del mismo
--     trabajo, si no el que queda (el BSD que la ficha decía antes de este
--     trabajo); y el aro escrito de la bici con ISO 5775, como el neumático
--     (29″ y 27,5″ refutan; 26″ no), salvo que la ficha de antes del trabajo
--     sepa un BSD que ese aro no admite: entonces el aro es el que quedó
--     viejo.
--   - Una pieza del trabajo que no dice su medida no esconde otra que sí la
--     dice: dos neumáticos (584 y uno sin BSD) dicen 584.
--   - El neumático, a su vez, calza con la llanta que instala el mismo
--     trabajo antes que con la ficha (como el cassette con la maza).
-- * «Lo que la ficha decía antes de este trabajo»: si el último recibo que
--   tocó el dato es de este trabajo (su Enrayado, su llanta), el valor es el
--   de antes del primero de ellos (`bike_fact_before_job_internal`). Sin eso,
--   el orden de las líneas decidía: un Enrayado que escribía primero borraba
--   la maza que queda.
-- * En un trabajo terminado, un neumático que cambia tampoco puede dejar mal
--   la llanta de su rueda (la puerta mira `job_tire`), y un neumático sin
--   marca con rueda pasa por esa revisión como una maza o una llanta.
-- * Guardar varias líneas en un trabajo terminado es un solo cambio: el
--   comando `save_mechanic_job_lines_v1` las escribe una por una y la puerta
--   miraba cada paso, así que reemplazar a la vez la llanta y lo que se mide
--   con ella (el Enrayado, la maza, el neumático; o la maza y su rotor,
--   20260928130000) siempre tenía un paso intermedio que no calzaba. Ahora el
--   comando abre una espera privada de su transacción
--   (`mechanic_job_line_gate_deferrals`, que ningún rol de la API puede
--   escribir), y corre la puerta al final, en la misma transacción y con el
--   mismo mensaje, sobre lo que quedó: después de lo que confirmó
--   «Configurar». Cualquier otro escritor sigue con la puerta inmediata.
-- * Las bicis del trabajo deciden de quién es cada línea: agregar, quitar,
--   mover o cambiar una bici (o la de la cabecera, sin filas de bicis) en un
--   trabajo terminado pasa todas sus líneas por la puerta; una marca que se
--   queda sin bici se rechaza.
--
-- Depende de `20260928130000`.
begin;

-- ============================================================================
-- La relación única: la llanta
-- ============================================================================

-- La llanta cambia la rueda: su BSD y sus perforaciones, en la rueda que
-- eligió el mecánico (la llanta no dice su posición).
insert into public.bike_fact_spec_links (
  spec_key, position, bike_fact_key, component_label, component_article,
  unit, requires_fact_key, requires_fact_values, min_value, max_value,
  template_key, on_mismatch, value_map, constant_value, fits,
  product_condition
) values
  ('bead_seat_diameter_mm', 'front', 'frontWheelBsdMm', 'rueda delantera', 'la',
   null, null, '{}', 150, 700, 'rim', 'change', null, null, null, null),
  ('bead_seat_diameter_mm', 'rear', 'rearWheelBsdMm', 'rueda trasera', 'la',
   null, null, '{}', 150, 700, 'rim', 'change', null, null, null, null),
  ('spoke_hole_count', 'front', 'frontSpokeHoles', 'rueda delantera', 'la',
   null, null, '{}', 12, 48, 'rim', 'change', null, null, null, null),
  ('spoke_hole_count', 'rear', 'rearSpokeHoles', 'rueda trasera', 'la',
   null, null, '{}', 12, 48, 'rim', 'change', null, null, null, null)
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

-- Lo de 20260928130000, y con qué pieza de la rueda no calza una llanta o un
-- neumático: «la maza trasera tiene 32 perforaciones», «el neumático
-- delantero es 584 (27,5″/650b)», «la llanta trasera es 622 (29″/700c)». Una
-- rueda con dos cantidades se dice tal cual («36 o 40»).
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
    when p_requires_key in ('frontSpokeHoles', 'rearSpokeHoles',
                            'frontBuildSpokeHoles', 'rearBuildSpokeHoles') then
      'la rueda '
        || case when p_requires_key like 'front%' then 'delantera' else 'trasera' end
        || ' lleva ' || coalesce(p_requires_value, '?') || ' rayos'
    when p_requires_key in ('frontHubSpokeHoles', 'rearHubSpokeHoles') then
      'la maza '
        || case when p_requires_key like 'front%' then 'delantera' else 'trasera' end
        || ' tiene ' || coalesce(p_requires_value, '?') || ' perforaciones'
    when p_requires_key in ('frontTireBsdMm', 'rearTireBsdMm',
                            'frontRimBsdMm', 'rearRimBsdMm') then
      case when p_requires_key like '%Tire%' then 'el neumático ' else 'la llanta ' end
        || case
             when p_requires_key like 'front%' and p_requires_key like '%Tire%' then 'delantero'
             when p_requires_key like 'front%' then 'delantera'
             when p_requires_key like '%Tire%' then 'trasero'
             else 'trasera'
           end
        || ' es '
        || case
             when p_requires_value ~ '^[0-9]{1,4}$'
               then public.iso_bsd_wheel_label(p_requires_value::numeric)
             else coalesce(p_requires_value, '?')
           end
    when p_requires_key in ('frontRotorMount', 'rearRotorMount') then
      'el anclaje del rotor '
        || case p_requires_key when 'frontRotorMount' then 'delantero' else 'trasero' end
        || ' es «' || public.rotor_mount_label(p_requires_value) || '»'
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

-- Qué hacer cuando no calza. Lo de antes igual; lo de la llanta, nuevo.
create or replace function public.bike_fact_requirement_advice(p_requires_key text)
returns text
language sql
immutable
set search_path to 'public'
as $function$
  select case
    when p_requires_key = 'brakeType' then
      'Si la bici lleva freno de disco, corrige el tipo de freno en su ficha '
      || 'y guarda el trabajo; si no, quita la línea.'
    -- El aro escrito refuta un neumático y una llanta: el consejo es de los
    -- dos (antes hablaba del neumático).
    when p_requires_key = 'bikes.wheel_size' then
      'Revisa la medida de la pieza y el aro de la bici: si la pieza sí va '
      || 'ahí, corrige el aro en la ficha de la bici y guarda el trabajo; si '
      || 'no, cambia la línea.'
    when p_requires_key = 'freehubType' then
      'Revisa el núcleo de la maza trasera: si es otro, corrige el driver en '
      || 'la ficha de la bici y guarda el trabajo; si no, cambia la línea.'
    when p_requires_key = 'drivetrainConfig' then
      'Un cassette o piñón de otra velocidad necesita el mando de esa '
      || 'velocidad: si también lo cambiaste, agrega su línea o corrige la '
      || 'transmisión en la ficha; si no, cambia la línea.'
    when p_requires_key in ('frontSpokeHoles', 'rearSpokeHoles') then
      'Una maza con menos perforaciones que la llanta no se puede rayar: si '
      || 'también cambiaste la llanta, agrega su línea en esa rueda; si la '
      || 'rueda lleva otra cantidad, corrige la ficha; si no, cambia la línea.'
    when p_requires_key in ('frontBuildSpokeHoles', 'rearBuildSpokeHoles') then
      'La rueda queda con las perforaciones de su llanta: si el Enrayado u '
      || 'otra llanta de esa rueda dice otra cantidad, corrige esa línea; si '
      || 'no, cambia ésta.'
    when p_requires_key in ('frontHubSpokeHoles', 'rearHubSpokeHoles') then
      'Una llanta se raya en una maza con sus mismas perforaciones (o con '
      || 'más, en los patrones de Sheldon Brown), nunca con menos: si también '
      || 'cambiaste la maza, agrega su línea en esa rueda; si la maza tiene '
      || 'otra cantidad, corrige la ficha; si no, cambia la línea.'
    when p_requires_key in ('frontTireBsdMm', 'rearTireBsdMm') then
      'Una llanta y su neumático tienen el mismo BSD: si también cambiaste el '
      || 'neumático, agrega su línea en esa rueda; si la rueda es otra, '
      || 'corrige la ficha; si no, cambia la línea.'
    when p_requires_key in ('frontRimBsdMm', 'rearRimBsdMm') then
      'Un neumático calza sólo en una llanta de su mismo BSD: si la llanta '
      || 'del trabajo es la que va, cambia esta línea; si no, corrige la de la '
      || 'llanta.'
    when p_requires_key in ('frontRotorMount', 'rearRotorMount') then
      'Un rotor Center Lock no va en una maza de 6 pernos, y uno de 6 pernos '
      || 'va en una Center Lock sólo con el adaptador SM-RTAD05, que no sirve '
      || 'con araña de aluminio (flotantes, SM-RT86 y SM-RT76): si la maza es '
      || 'otra, corrige la ficha; si no, cambia la línea.'
    else
      'Revisa la medida del neumático y la de esa rueda: si el neumático sí '
      || 'va ahí, corrige la ficha de la bici y guarda el trabajo; si no, '
      || 'cambia la línea.'
  end;
$function$;

revoke all on function public.bike_fact_requirement_advice(text)
  from public, anon, authenticated, service_role;

-- ============================================================================
-- Lo que el mismo trabajo instala en esa rueda
-- ============================================================================

-- La de 20260928130000, que además dice las perforaciones de la maza de esa
-- rueda (`holes`) si las mazas que las dicen dicen una sola cantidad, o las
-- cantidades (`holes_either`) si dicen más de una. Una maza que no las dice
-- no esconde la que sí (revisión de Codex, 2026-09-29). Una llanta se raya en
-- ella.
create or replace function public.job_hub_at_wheel_internal(
  p_tenant_id uuid,
  p_item_id uuid,
  p_bike_id uuid,
  p_position text
)
returns jsonb
language sql
stable
set search_path to 'public'
as $function$
  with hubs as (
    select other.id,
           other.product_id,
           (select public.bike_fact_link_value_internal(l,
                     public.product_bike_fact_spec_internal(
                       p_tenant_id, other.product_id, l.spec_key))
              from public.bike_fact_spec_links l
             where l.bike_fact_key = 'freehubType'
               and l.position = 'rear'
               and l.template_key = 'hub'
               and l.on_mismatch = 'change') as driver,
           (select public.bike_fact_link_value_internal(l,
                     public.product_bike_fact_spec_internal(
                       p_tenant_id, other.product_id, l.spec_key))
              from public.bike_fact_spec_links l
             where l.bike_fact_key = case p_position
                     when 'front' then 'frontRotorMount'
                     else 'rearRotorMount'
                   end
               and l.position = p_position
               and l.template_key = 'hub'
               and l.on_mismatch = 'change') as rotor_mount,
           (select case
                     when (s.spec->'value' #>> '{}') ~ '^[0-9]{1,2}(\.0+)?$'
                          and (s.spec->'value' #>> '{}')::numeric between 12 and 48
                       then (s.spec->'value' #>> '{}')::numeric::integer
                   end
              from (select public.product_bike_fact_spec_internal(
                             p_tenant_id, other.product_id, 'spoke_hole_count') as spec) s
           ) as holes
      from public.mechanic_job_items self
      join public.mechanic_job_items other
        on other.job_id = self.job_id
       and other.tenant_id = self.tenant_id
       and other.id <> self.id
     where self.id = p_item_id
       and self.tenant_id = p_tenant_id
       and other.product_id is not null
       and public.job_line_bike_internal(p_tenant_id, other.id) = p_bike_id
       and public.product_bike_fact_spec_internal(
             p_tenant_id, other.product_id, '_family')->>'template_key' = 'hub'
       and (
         (
           other.location_key = p_position
           -- Una maza que dice ser de la otra rueda no es evidencia de ésta
           -- (revisión de Codex, 2026-09-28).
           and coalesce(nullif(btrim(public.product_bike_fact_spec_internal(
                 p_tenant_id, other.product_id, 'hub_package_position')->>'value'), ''),
                 'Universal')
               <> case p_position when 'front' then 'Trasera' else 'Delantera' end
         )
         or (
           coalesce(other.location_key, 'none') not in ('front', 'rear')
           and public.product_bike_fact_spec_internal(
                 p_tenant_id, other.product_id, 'hub_package_position')->>'value'
               in (case p_position when 'front' then 'Delantera' else 'Trasera' end,
                   'Juego (delantera y trasera)')
         )
       )
  )
  select case when count(*) = 0 then null else jsonb_build_object(
           'hubs', count(*),
           'driver', case
             when p_position = 'rear'
                  and count(*) = count(driver)
                  and count(distinct driver) = 1
               then min(driver #>> '{}')
           end,
           'rotor_mount', case
             when count(*) = count(rotor_mount)
                  and count(distinct rotor_mount) = 1
               then min(rotor_mount #>> '{}')
           end,
           'holes', case
             when count(distinct holes) = 1 then min(holes)
           end,
           'holes_either', case
             when count(distinct holes) > 1
               then string_agg(distinct holes::text, ' o ' order by holes::text)
           end)
         end
    from hubs;
$function$;

revoke all on function public.job_hub_at_wheel_internal(uuid, uuid, uuid, text)
  from public, anon, authenticated, service_role;

-- El BSD que dicen las llantas o los neumáticos (`p_family`) que otras
-- líneas del mismo trabajo instalan en esa rueda de esa bici. Cuenta la
-- rueda de la línea (ni la llanta ni el neumático dicen su posición). Nulo
-- si no hay ninguno; `value` si los que lo dicen dicen uno solo; `either` si
-- dicen más de uno («584 o 622»); ninguno de los dos si ninguno lo dice (no
-- refuta). Una pieza sin BSD no esconde la que sí lo dice (revisión de Codex,
-- 2026-09-29).
create or replace function public.job_wheel_bsd_internal(
  p_tenant_id uuid,
  p_item_id uuid,
  p_bike_id uuid,
  p_position text,
  p_family text
)
returns jsonb
language sql
stable
set search_path to 'public'
as $function$
  with parts as (
    select case
             when (s.spec->'value' #>> '{}') ~ '^[0-9]{1,4}(\.0+)?$'
                  and (s.spec->'value' #>> '{}')::numeric between 150 and 700
               then (s.spec->'value' #>> '{}')::numeric::integer
           end as bsd
      from public.mechanic_job_items self
      join public.mechanic_job_items other
        on other.job_id = self.job_id
       and other.tenant_id = self.tenant_id
       and other.id <> self.id
     cross join lateral (
       select public.product_bike_fact_spec_internal(
                p_tenant_id, other.product_id, 'bead_seat_diameter_mm') as spec
     ) s
     where self.id = p_item_id
       and self.tenant_id = p_tenant_id
       and other.product_id is not null
       and other.location_key = p_position
       and public.job_line_bike_internal(p_tenant_id, other.id) = p_bike_id
       and public.product_bike_fact_spec_internal(
             p_tenant_id, other.product_id, '_family')->>'template_key' = p_family
  )
  select case when count(*) = 0 then null else jsonb_build_object(
           'lines', count(*),
           'value', case
             when count(distinct bsd) = 1 then min(bsd)
           end,
           'either', case
             when count(distinct bsd) > 1
               then string_agg(distinct bsd::text, ' o ' order by bsd::text)
           end)
         end
    from parts;
$function$;

revoke all on function public.job_wheel_bsd_internal(uuid, uuid, uuid, text, text)
  from public, anon, authenticated, service_role;

-- Lo que la ficha decía de esa clave antes de este trabajo: si lo que dice
-- ahora lo escribió el trabajo al terminar (su Enrayado, su llanta), el
-- valor de antes del primero de sus recibos seguidos; si no (otro trabajo,
-- el mecánico en la ficha, o nadie), lo que dice ahora. Con esto la pieza
-- que queda (la maza, el neumático) se mide igual en cualquier orden de
-- líneas y también al volver a mirar un trabajo terminado.
create or replace function public.bike_fact_before_job_internal(
  p_tenant_id uuid,
  p_bike_id uuid,
  p_job_id uuid,
  p_key text,
  p_values jsonb
)
returns jsonb
language plpgsql
stable
set search_path to 'public'
as $function$
declare
  v_current jsonb := coalesce(p_values, '{}'::jsonb)->p_key;
  v_top_to jsonb;
  v_before jsonb;
begin
  if v_current is null
     or (select bp.technical_profile->'sources'->>p_key
           from public.bike_profiles bp
          where bp.bike_id = p_bike_id
            and bp.tenant_id = p_tenant_id)
        is distinct from 'job_completion' then
    return v_current;
  end if;

  with touches as (
    select p.job_id,
           p.source,
           e->'from' as from_value,
           e->'to' as to_value,
           row_number() over (order by p.completed_at desc, p.operation_key desc) as rn
      from public.bike_technical_fact_patches p
     cross join lateral jsonb_array_elements(
             case when jsonb_typeof(p.applied) = 'array'
                  then p.applied else '[]'::jsonb end) e
     where p.tenant_id = p_tenant_id
       and p.bike_id = p_bike_id
       and e->>'key' = p_key
  ),
  cut as (
    select coalesce(min(rn), 2147483647) as first_other
      from touches
     where job_id is distinct from p_job_id
        or source is distinct from 'job_completion'
  )
  select (select t.to_value
            from touches t
           where t.rn = 1
             and t.job_id = p_job_id
             and t.source = 'job_completion'),
         (select t.from_value
            from touches t, cut
           where t.rn < cut.first_other
           order by t.rn desc
           limit 1)
    into v_top_to, v_before;

  if v_top_to is null
     or not public.bike_fact_value_equal(v_top_to, v_current) then
    return v_current;
  end if;
  return coalesce(v_before, 'null'::jsonb);
end;
$function$;

revoke all on function public.bike_fact_before_job_internal(uuid, uuid, uuid, text, jsonb)
  from public, anon, authenticated, service_role;

-- ============================================================================
-- El calce de la llanta
-- ============================================================================

-- Lo que una llanta marcada tiene que calzar en su rueda. La llanta es una
-- pieza: si no calza por un dato, no se instala ninguno (como la maza con lo
-- que se revisa). Con lo que dice su ficha técnica, esté marcado o no:
-- * su BSD, con otra llanta del trabajo en esa rueda y con el neumático de
--   esa rueda (el del mismo trabajo; si no, el que queda, según la ficha de
--   antes de este trabajo): el mismo; y con el aro escrito leído con ISO
--   5775, salvo que esa ficha sepa un BSD que el aro no admite;
-- * sus perforaciones, con la rueda que arma el trabajo (el Enrayado de esa
--   rueda, u otra llanta del trabajo en ella: la misma cantidad) y con la
--   maza en que se raya (la del mismo trabajo; si no, la que queda, según la
--   ficha de antes de este trabajo): igual, o una maza con más en un patrón
--   de Sheldon Brown.
-- Nulo si calza o si nada lo refuta. Depende del repuesto y de las otras
-- líneas: se vuelve a mirar aunque el recibo de la línea ya exista.
create or replace function public.bike_fact_rim_checks_internal(
  p_tenant_id uuid,
  p_item_id uuid,
  p_bike_id uuid,
  p_position text,
  p_values jsonb
)
returns jsonb
language plpgsql
stable
set search_path to 'public'
as $function$
declare
  v_job_id uuid;
  v_product_id uuid;
  v_side text;
  v_bsd integer;
  v_holes integer;
  v_reference jsonb;
  v_hub jsonb;
  v_part jsonb;
  v_before text;
  v_wheel_size text;
  v_candidates integer[];
begin
  if p_position is null or p_position not in ('front', 'rear') then
    return null;
  end if;
  v_side := p_position;
  select i.job_id, i.product_id
    into v_job_id, v_product_id
    from public.mechanic_job_items i
   where i.id = p_item_id
     and i.tenant_id = p_tenant_id;
  if v_job_id is null or v_product_id is null then
    return null;
  end if;
  -- Lo que la llanta dice por las filas de su rueda (una medida en su rango).
  select max(case l.spec_key when 'bead_seat_diameter_mm' then v.value end),
         max(case l.spec_key when 'spoke_hole_count' then v.value end)
    into v_bsd, v_holes
    from public.bike_fact_spec_links l
   cross join lateral (
     select (public.bike_fact_link_value_internal(l,
               public.product_bike_fact_spec_internal(
                 p_tenant_id, v_product_id, l.spec_key)) #>> '{}')::numeric::integer as value
   ) v
   where l.template_key = 'rim'
     and l.position = p_position
     and l.on_mismatch = 'change';

  if v_bsd is not null then
    -- Otra llanta del trabajo en esa rueda con otro BSD: no se sabe cuál va.
    v_part := public.job_wheel_bsd_internal(
      p_tenant_id, p_item_id, p_bike_id, p_position, 'rim');
    if v_part is not null
       and (v_part->>'either' is not null
            or (v_part->>'value' is not null
                and (v_part->>'value')::integer <> v_bsd)) then
      return jsonb_build_object(
        'requires_key', v_side || 'RimBsdMm',
        'requires_value', coalesce(v_part->>'value', v_part->>'either'),
        'reason', 'incompatible',
        'source', 'job_rim');
    end if;

    -- El neumático de esa rueda: el del mismo trabajo decide (si ninguno dice
    -- su BSD, no refuta); si no hay, el que queda.
    v_before := public.bike_fact_before_job_internal(
      p_tenant_id, p_bike_id, v_job_id, v_side || 'WheelBsdMm', p_values) #>> '{}';
    if v_before !~ '^[0-9]{1,4}(\.0+)?$' then
      v_before := null;
    end if;
    v_part := public.job_wheel_bsd_internal(
      p_tenant_id, p_item_id, p_bike_id, p_position, 'tire');
    if v_part is not null then
      if v_part->>'either' is not null
         or (v_part->>'value' is not null
             and (v_part->>'value')::integer <> v_bsd) then
        return jsonb_build_object(
          'requires_key', v_side || 'TireBsdMm',
          'requires_value', coalesce(v_part->>'value', v_part->>'either'),
          'reason', 'incompatible',
          'source', 'job_tire');
      end if;
    elsif v_before is not null and v_before::numeric <> v_bsd then
      return jsonb_build_object(
        'requires_key', v_side || 'TireBsdMm',
        'requires_value', (v_before::numeric::integer)::text,
        'reason', 'incompatible');
    end if;

    -- El aro escrito, leído con ISO 5775: sólo 29″/700c y 27,5″/650b refutan
    -- (20260928110000). Si la ficha de antes del trabajo sabe un BSD que ese
    -- aro no admite, el aro escrito es el que quedó viejo y no refuta
    -- (revisión de Codex, 2026-09-29); con el mismo BSD tampoco.
    select b.wheel_size
      into v_wheel_size
      from public.bikes b
     where b.id = p_bike_id
       and b.tenant_id = p_tenant_id;
    v_candidates := public.iso_bsd_candidates_for_wheel_size(v_wheel_size);
    if cardinality(v_candidates) > 0
       and not (v_bsd = any (v_candidates))
       and (v_before is null
            or v_before::numeric::integer = any (v_candidates)) then
      return jsonb_build_object(
        'requires_key', 'bikes.wheel_size',
        'requires_value', btrim(v_wheel_size),
        'reason', 'incompatible');
    end if;
  end if;

  if v_holes is not null then
    -- La rueda que arma el trabajo: el Enrayado de esa rueda, o si no hay,
    -- las otras llantas del trabajo en ella (sin la ficha).
    v_reference := public.job_wheel_spokes_internal(
      p_tenant_id, p_item_id, p_bike_id, p_position, '{}'::jsonb);
    if v_reference is not null
       and (v_reference->>'value' is null
            or (v_reference->>'value')::integer <> v_holes) then
      return jsonb_build_object(
        'requires_key', v_side || 'BuildSpokeHoles',
        'requires_value', coalesce(v_reference->>'value', v_reference->>'either'),
        'reason', 'incompatible',
        'source', v_reference->>'source');
    end if;

    -- La maza en que se raya: la del mismo trabajo. Si esa maza no dice sus
    -- perforaciones, no refuta; la ficha ya no es su maza.
    v_hub := public.job_hub_at_wheel_internal(
      p_tenant_id, p_item_id, p_bike_id, p_position);
    if v_hub is not null then
      if v_hub->>'holes_either' is not null then
        return jsonb_build_object(
          'requires_key', v_side || 'HubSpokeHoles',
          'requires_value', v_hub->>'holes_either',
          'reason', 'incompatible',
          'source', 'job_hub');
      end if;
      if v_hub->>'holes' is not null
         and not public.hub_lacing_fits((v_hub->>'holes')::integer, v_holes) then
        return jsonb_build_object(
          'requires_key', v_side || 'HubSpokeHoles',
          'requires_value', v_hub->>'holes',
          'reason', 'incompatible',
          'source', 'job_hub');
      end if;
      return null;
    end if;

    -- Si no, la maza que queda: la rueda que la ficha decía antes de este
    -- trabajo se rayó en ella.
    v_before := public.bike_fact_before_job_internal(
      p_tenant_id, p_bike_id, v_job_id, v_side || 'SpokeHoles', p_values) #>> '{}';
    if v_before ~ '^[0-9]{1,2}(\.0+)?$'
       and v_before::numeric between 12 and 48
       and not public.hub_lacing_fits(v_before::numeric::integer, v_holes) then
      return jsonb_build_object(
        'requires_key', v_side || 'HubSpokeHoles',
        'requires_value', (v_before::numeric::integer)::text,
        'reason', 'incompatible');
    end if;
  end if;
  return null;
end;
$function$;

revoke all on function public.bike_fact_rim_checks_internal(uuid, uuid, uuid, text, jsonb)
  from public, anon, authenticated, service_role;

-- La de 20260928130000 con la llanta: lo que se revisa de una llanta está en
-- `bike_fact_rim_checks_internal` (su fila es un cambio, no tiene filas de
-- revisión).
create or replace function public.bike_fact_part_checks_internal(
  p_tenant_id uuid,
  p_item_id uuid,
  p_bike_id uuid,
  p_key text,
  p_values jsonb
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
  v_product_id uuid;
  v_product jsonb;
  v_bike_count integer;
  v_bike_text text;
  v_wheel_hub jsonb;
  v_reference jsonb;
  v_source text;
begin
  v_part := public.job_line_part_change_internal(p_tenant_id, p_item_id, p_key);
  if v_part is null then
    return null;
  end if;
  select * into v_link
    from public.bike_fact_spec_links l
   where l.id = (v_part->>'link_id')::uuid;

  -- La llanta: la rueda que se arma, su maza y su neumático (20260928140000).
  if v_part->>'template_key' = 'rim' then
    return public.bike_fact_rim_checks_internal(
      p_tenant_id, p_item_id, p_bike_id, v_link.position, p_values);
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
    if v_product is null then
      continue;
    end if;

    if v_check.bike_fact_key in ('frontSpokeHoles', 'rearSpokeHoles') then
      -- Las perforaciones de la maza contra la rueda que queda: la misma
      -- cantidad, o un patrón de Sheldon Brown con más en la maza.
      if jsonb_typeof(v_product) <> 'number'
         or (v_product #>> '{}')::integer
            not between v_check.min_value and v_check.max_value then
        continue;
      end if;
      v_reference := public.job_wheel_spokes_internal(
        p_tenant_id, p_item_id, p_bike_id, v_check.position, p_values);
      if v_reference is not null and v_reference->>'value' is null then
        -- El trabajo arma esa rueda con dos cantidades: no calza con ninguna
        -- hasta que quede una.
        return jsonb_build_object(
          'requires_key', v_check.bike_fact_key,
          'requires_value', v_reference->>'either',
          'reason', 'incompatible',
          'source', v_reference->>'source');
      end if;
      if v_reference is null
         or public.hub_lacing_fits(
              (v_product #>> '{}')::integer,
              (v_reference->>'value')::integer) then
        continue;
      end if;
      -- La ficha no se nombra como fuente, igual que en las otras reglas.
      return jsonb_strip_nulls(jsonb_build_object(
        'requires_key', v_check.bike_fact_key,
        'requires_value', v_reference->>'value',
        'reason', 'incompatible',
        'source', nullif(v_reference->>'source', 'bike')));
    end if;

    if v_check.bike_fact_key in ('frontRotorMount', 'rearRotorMount') then
      -- El anclaje del rotor contra el de la maza de su rueda: la que instala
      -- el mismo trabajo, si no la ficha. Una maza nueva que no lo dice no
      -- refuta.
      v_wheel_hub := public.job_hub_at_wheel_internal(
        p_tenant_id, p_item_id, p_bike_id, v_check.position);
      if v_wheel_hub is not null then
        v_bike_text := v_wheel_hub->>'rotor_mount';
        v_source := 'job_hub';
      else
        v_bike_text := coalesce(p_values, '{}'::jsonb)->>v_check.bike_fact_key;
        v_source := null;
      end if;
      if v_bike_text is null
         or lower(v_bike_text) in ('unknown', 'desconocido', '')
         or v_bike_text = v_product #>> '{}'
         or (
           coalesce((v_check.fits->(v_product #>> '{}')) ? v_bike_text, false)
           -- El SM-RTAD05 no sirve con araña de aluminio (un flotante).
           and coalesce(public.product_bike_fact_spec_internal(
                 p_tenant_id, v_product_id, 'rotor_floating')->'value',
                 'false'::jsonb) <> 'true'::jsonb
         ) then
        continue;
      end if;
      return jsonb_strip_nulls(jsonb_build_object(
        'requires_key', v_check.bike_fact_key,
        'requires_value', v_bike_text,
        'reason', 'incompatible',
        'source', v_source));
    end if;

    -- Los piñones de un cassette o piñón de rosca contra la transmisión.
    v_bike_text := coalesce(p_values, '{}'::jsonb)->>v_check.bike_fact_key;
    v_bike_count := case v_check.bike_fact_key
      when 'drivetrainConfig' then public.drivetrain_rear_cog_count(v_bike_text)
      else case when v_bike_text ~ '^[0-9]{1,4}$' then v_bike_text::integer end
    end;
    -- Una cuenta fuera del rango de la fila (1 a 14) es un error de la ficha
    -- técnica, no una transmisión: no refuta.
    if jsonb_typeof(v_product) <> 'number'
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
  return null;
end;
$function$;

revoke all on function public.bike_fact_part_checks_internal(uuid, uuid, uuid, text, jsonb)
  from public, anon, authenticated, service_role;

-- La de 20260928130000, con el neumático medido contra la llanta que instala
-- el mismo trabajo en su rueda antes que contra la ficha (como el cassette
-- con la maza): si esa llanta dice su BSD, manda; si no lo dice, no refuta
-- y la ficha vieja ya no es su rueda. En los dos casos, el aro escrito sigue
-- refutando lo imposible.
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
  v_current jsonb;
  v_known boolean := false;
  v_own boolean := false;
  v_candidates integer[];
  v_fits jsonb;
  v_rear_hub jsonb;
  v_hub_decided boolean := false;
  v_rim jsonb;
  v_rim_decided boolean := false;
  v_before text;
  v_checked jsonb;
begin
  v_part := public.job_line_part_change_internal(p_tenant_id, p_item_id, p_key);
  if v_part is null or p_value is null then
    return null;
  end if;
  select * into v_link
    from public.bike_fact_spec_links l
   where l.id = (v_part->>'link_id')::uuid;

  if v_link.on_mismatch = 'conflict' then
    -- El driver lo decide la maza trasera que instala el mismo trabajo, si lo
    -- dice (20260928130000): se compara con ella, no con la ficha vieja.
    if p_key = 'freehubType' then
      v_rear_hub := public.job_hub_at_wheel_internal(
        p_tenant_id, p_item_id, p_bike_id, 'rear');
      if v_rear_hub->>'driver' is not null then
        v_hub_decided := true;
        if not public.bike_fact_value_equal(v_rear_hub->'driver', p_value) then
          if coalesce(
               (v_link.fits->(p_value #>> '{}')) ? (v_rear_hub->>'driver'),
               false) then
            v_fits := jsonb_build_object(
              'requires_key', p_key,
              'requires_value', v_rear_hub->>'driver',
              'reason', 'fits',
              'source', 'job_hub');
          else
            return jsonb_build_object(
              'requires_key', p_key,
              'requires_value', v_rear_hub->>'driver',
              'reason', 'incompatible',
              'source', 'job_hub');
          end if;
        end if;
      end if;
    end if;

    -- El BSD de un neumático lo decide la llanta que instala el mismo
    -- trabajo en esa rueda (20260928140000).
    if p_key in ('frontWheelBsdMm', 'rearWheelBsdMm') then
      v_rim := public.job_wheel_bsd_internal(
        p_tenant_id, p_item_id, p_bike_id, v_link.position, 'rim');
      if v_rim is not null then
        v_rim_decided := true;
        if v_rim->>'either' is not null
           or (v_rim->>'value' is not null
               and not public.bike_fact_value_equal(v_rim->'value', p_value)) then
          return jsonb_build_object(
            'requires_key', v_link.position || 'RimBsdMm',
            'requires_value', coalesce(v_rim->>'value', v_rim->>'either'),
            'reason', 'incompatible',
            'source', 'job_rim');
        end if;
      end if;
    end if;

    if not v_hub_decided and not v_rim_decided then
      v_current := coalesce(p_values, '{}'::jsonb)->p_key;
      v_known := v_current is not null
        and v_current <> 'null'::jsonb
        and lower(v_current #>> '{}') not in ('unknown', 'desconocido', '');
      if v_known and not public.bike_fact_value_equal(v_current, p_value) then
        -- Lo escribió esta misma línea en esta bici y sigue siendo suyo: se
        -- está corrigiendo (20260928110000). Si el mecánico lo volvió a elegir
        -- en la ficha (fuente `mechanic`), aunque sea el mismo valor, ya es
        -- suyo.
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
          -- Una maza trasera nueva que no dice su driver: la decide el
          -- mecánico en la ficha.
          if p_key = 'freehubType' and v_rear_hub is not null then
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
    end if;

    -- El aro escrito, cuando la ficha no dice el BSD, cuando lo escribió esta
    -- misma línea, o cuando lo decide la llanta del trabajo. En este último
    -- caso, si la ficha de antes del trabajo sabe un BSD que el aro no admite,
    -- el aro es el que quedó viejo y no refuta (revisión de Codex,
    -- 2026-09-29), igual que para la llanta.
    if p_key in ('frontWheelBsdMm', 'rearWheelBsdMm')
       and jsonb_typeof(p_value) = 'number'
       and (v_rim_decided or not v_known or v_own) then
      v_candidates := public.iso_bsd_candidates_for_wheel_size(p_wheel_size);
      if v_rim_decided and cardinality(v_candidates) > 0 then
        v_before := public.bike_fact_before_job_internal(
          p_tenant_id, p_bike_id,
          (select i.job_id
             from public.mechanic_job_items i
            where i.id = p_item_id
              and i.tenant_id = p_tenant_id),
          p_key, p_values) #>> '{}';
        if v_before ~ '^[0-9]{1,4}(\.0+)?$'
           and not (v_before::numeric::integer = any (v_candidates)) then
          v_candidates := '{}'::integer[];
        end if;
      end if;
      if cardinality(v_candidates) > 0
         and not (((p_value #>> '{}')::numeric)::integer = any (v_candidates)) then
        return jsonb_build_object(
          'requires_key', 'bikes.wheel_size',
          'requires_value', btrim(p_wheel_size),
          'reason', 'incompatible');
      end if;
    end if;
  end if;

  -- Lo que sólo se revisa, de la misma familia y rueda, y lo de la llanta
  -- (`bike_fact_part_checks_internal`).
  v_checked := public.bike_fact_part_checks_internal(
    p_tenant_id, p_item_id, p_bike_id, p_key, p_values);
  if v_checked is not null then
    return v_checked;
  end if;
  return v_fits;
end;
$function$;

revoke all on function public.bike_fact_part_conflict_internal(uuid, uuid, uuid, text, jsonb, jsonb, jsonb, text)
  from public, anon, authenticated, service_role;

-- ============================================================================
-- El aplicador: el neumático del trabajo también se nombra
-- ============================================================================

-- El aviso de lo que no calza dice con qué pieza del mismo trabajo (la maza,
-- la rueda, la llanta y ahora el neumático). Se inserta sobre la definición
-- de 20260928130000, reejecutable: el ancla está dos veces (el camino normal
-- y la revisión al saltar por recibo).
do $do$
declare
  v_fn regprocedure :=
    'public.apply_job_installed_bike_facts_internal(uuid,uuid,boolean)'::regprocedure;
  v_def text;
  v_anchor text := $a$when 'job_rim' then 'la llanta que instala el trabajo'
$a$;
  v_block text := $a$when 'job_rim' then 'la llanta que instala el trabajo'
                -- El neumático de esa rueda (20260928140000).
                when 'job_tire' then 'el neumático que instala el trabajo'
$a$;
begin
  v_def := pg_get_functiondef(v_fn);
  if position('el neumático que instala el trabajo' in v_def) > 0 then
    return;
  end if;
  if (length(v_def) - length(replace(v_def, v_anchor, ''))) / length(v_anchor) <> 2 then
    raise exception 'applier anchor not found exactly twice';
  end if;
  execute replace(v_def, v_anchor, v_block);
end;
$do$;

-- ============================================================================
-- La puerta del trabajo terminado
-- ============================================================================

-- Lo que la puerta revisa de una línea que quedó en un trabajo terminado:
-- lo que la línea instala tiene que entrar en la ficha con ella, y una maza,
-- una llanta, un neumático o un Enrayado no puede dejar mal otra línea de su
-- rueda que se mide con ella. `p_evidence_only`: la línea no instala nada
-- (sin marca), pero las otras de su rueda se miden con ella. Rechaza con el
-- mismo mensaje de siempre; la usan el disparador (cada cambio) y el comando
-- de guardado (una vez, al final).
create or replace function public.job_line_gate_check_internal(
  p_line public.mechanic_job_items,
  p_evidence_only boolean,
  p_result jsonb
)
returns void
language plpgsql
stable
set search_path to 'public'
as $function$
declare
  v_problem jsonb;
  v_line_name text;
  v_fact text;
  v_kind text;
  v_wheel text;
  v_bike_id uuid;
  v_sibling jsonb;
begin
  if not p_evidence_only then
    -- Lo que esta línea instala tiene que quedar en la ficha con ella. Una
    -- llanta que no calza lo informa en sus dos datos: se nombra el dato que
    -- no calza (el BSD con el neumático o el aro; las perforaciones con la
    -- maza o la rueda); si no, el primero, como siempre.
    select problem
      into v_problem
      from jsonb_array_elements(coalesce(p_result->'problems', '[]'::jsonb))
           with ordinality as problems(problem, ord)
     where problem->>'item_id' = p_line.id::text
       and problem->>'reason' in (
         'rejected', 'out_of_range', 'no_wheel', 'invalid_value',
         'line_without_bike', 'incompatible', 'stale_change', 'mixed_change',
         'conflicting_build'
       )
     order by case
                when problem->>'key' like '%WheelBsdMm'
                     and (problem->>'requires_key' like '%BsdMm'
                          or problem->>'requires_key' = 'bikes.wheel_size') then 0
                when problem->>'key' like '%SpokeHoles'
                     and problem->>'requires_key' like '%SpokeHoles' then 0
                else 1
              end,
              ord
     limit 1;
  end if;
  if v_problem is null then
    -- Una maza, una llanta, un neumático o un Enrayado que cambia en un
    -- trabajo terminado tampoco puede dejar mal otra línea del mismo trabajo
    -- y de la misma rueda que se mide con ella (20260928130000,
    -- 20260928140000): el cassette con el driver de la maza, el rotor con su
    -- anclaje, la maza y la llanta con los rayos de la rueda, el neumático y
    -- la llanta con su BSD. Esa otra línea ya tiene su recibo y no se vuelve
    -- a mirar sola.
    v_kind := case
      when p_line.service_configuration_data ? 'hole_count' then 'job_build'
      when p_line.product_id is not null then
        case public.product_bike_fact_spec_internal(
               p_line.tenant_id, p_line.product_id, '_family')->>'template_key'
          when 'hub' then 'job_hub'
          when 'rim' then 'job_rim'
          when 'tire' then 'job_tire'
        end
    end;
    if v_kind is null then
      return;
    end if;
    v_wheel := case
      when v_kind = 'job_build' then coalesce(
        nullif(p_line.location_key, 'none'),
        p_line.service_configuration_data->>'which_wheel')
      when p_line.location_key in ('front', 'rear') then p_line.location_key
      when v_kind = 'job_hub' then
        case public.product_bike_fact_spec_internal(
               p_line.tenant_id, p_line.product_id, 'hub_package_position')->>'value'
          when 'Delantera' then 'front'
          when 'Trasera' then 'rear'
          when 'Juego (delantera y trasera)' then 'both'
        end
    end;
    v_bike_id := public.job_line_bike_internal(p_line.tenant_id, p_line.id);
    if v_wheel is null or v_bike_id is null then
      return;
    end if;
    select jsonb_build_object(
             'item_name', s.product_name,
             'requires_key', conflict.c->>'requires_key',
             'requires_value', conflict.c->>'requires_value')
      into v_sibling
      from public.mechanic_job_items s
      cross join lateral jsonb_array_elements(
        public.job_line_part_change_marks_internal(
          s.service_configuration_data->'part_change')) m
      cross join lateral (
        select public.job_line_part_change_internal(
                 s.tenant_id, s.id, m->>'key') as part
      ) marked
      left join public.bike_profiles bp
        on bp.bike_id = v_bike_id
       and bp.tenant_id = s.tenant_id
      left join public.bikes b
        on b.id = v_bike_id
       and b.tenant_id = s.tenant_id
      cross join lateral (
        select public.bike_fact_part_conflict_internal(
                 s.tenant_id, s.id, v_bike_id, m->>'key', marked.part->'value',
                 coalesce(bp.technical_profile->'values', '{}'::jsonb),
                 coalesce(bp.technical_profile->'sources', '{}'::jsonb),
                 b.wheel_size) as c
      ) conflict
     where s.job_id = p_line.job_id
       and s.tenant_id = p_line.tenant_id
       and s.id <> p_line.id
       and marked.part is not null
       and v_wheel in (marked.part->>'position', 'both')
       and public.job_line_bike_internal(s.tenant_id, s.id) = v_bike_id
       and conflict.c->>'reason' = 'incompatible'
       and conflict.c->>'source' = v_kind
     order by s.created_at, s.id, m->>'key'
     limit 1;
    if v_sibling is null then
      return;
    end if;
    raise exception '%', format(
        '«%s» no se guardó: «%s», del mismo trabajo, no calza con %s (%s). '
        'En un trabajo terminado las líneas y la ficha se guardan juntas: '
        'corrige una de las dos líneas.',
        coalesce(nullif(btrim(p_line.product_name), ''), 'La línea'),
        coalesce(nullif(btrim(v_sibling->>'item_name'), ''), 'otra línea'),
        case v_kind
          when 'job_hub' then 'esta maza'
          when 'job_rim' then 'esta llanta'
          when 'job_tire' then 'este neumático'
          else 'la rueda que arma esta línea'
        end,
        public.bike_fact_requirement_text(
          v_sibling->>'requires_key', v_sibling->>'requires_value'))
      using errcode = '23514',
            detail = (v_sibling || jsonb_build_object(
              'reason', 'sibling_incompatible', 'source', v_kind))::text;
  end if;

  v_line_name := coalesce(nullif(btrim(p_line.product_name), ''), 'La línea');
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
        '«%s» no se guardó: %s no calza con %s (%s). En un trabajo terminado '
        'la línea y la ficha se guardan juntas: corrige la ficha o la línea.',
        v_line_name, v_fact,
        -- Con qué no calza: la ficha, o lo que instala el mismo trabajo.
        case v_problem->>'requires_source'
          when 'job_hub' then 'la maza que instala el trabajo'
          when 'job_build' then 'la rueda que arma el trabajo'
          when 'job_rim' then 'la llanta que instala el trabajo'
          when 'job_tire' then 'el neumático que instala el trabajo'
          else 'la ficha de la bici'
        end,
        public.bike_fact_requirement_text(
          v_problem->>'requires_key', v_problem->>'requires_value'))
      when 'conflicting_build' then format(
        '«%s» no se guardó: otro Enrayado del mismo trabajo arma la rueda %s '
        'a %s rayos. Una rueda se arma una vez: deja una sola línea con la '
        'cantidad real.',
        v_line_name,
        case v_problem->>'key' when 'frontSpokeHoles' then 'delantera' else 'trasera' end,
        v_problem->>'requires_value')
      when 'mixed_change' then format(
        '«%s» no se guardó: dice perforaciones y un cambio de repuesto a la '
        'vez, y una línea instala una sola cosa.', v_line_name)
      when 'stale_change' then format(
        '«%s» no se guardó: el cambio de ficha que dice (%s) ya no calza con '
        'su repuesto o con la rueda elegida. Vuelve a elegir la rueda y '
        'guarda.', v_line_name, v_fact)
      else format(
        '«%s» no se guardó: no dice de qué bici del trabajo es. Asígnala a '
        'su bici («Asignar a…» en el menú de la línea) y guarda.', v_line_name)
    end
    using errcode = '23514',
          detail = v_problem::text;
end;
$function$;

revoke all on function public.job_line_gate_check_internal(public.mechanic_job_items, boolean, jsonb)
  from public, anon, authenticated, service_role;

-- Qué líneas de un trabajo cambió el comando de guardado en esta
-- transacción. La abre y la cierra sólo el comando (una fila por transacción
-- y trabajo, que borra al terminar); los disparadores anotan en ella en vez
-- de correr la puerta. Es privada: sin grants ni políticas, sólo la escriben
-- las funciones del dueño. Antes era una variable de sesión, y cualquier
-- escritor con SQL podía fijarla y saltarse la puerta (revisión de Codex,
-- 2026-09-29).
create table if not exists public.mechanic_job_line_gate_deferrals (
  txid bigint not null,
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  job_id uuid not null references public.mechanic_jobs(id) on delete cascade,
  lines text not null default '',
  primary key (txid, tenant_id, job_id)
);

alter table public.mechanic_job_line_gate_deferrals enable row level security;
revoke all on table public.mechanic_job_line_gate_deferrals
  from public, anon, authenticated, service_role;

comment on table public.mechanic_job_line_gate_deferrals is
  'Private, transaction-scoped: lines save_mechanic_job_lines_v1 changed while the finished-job gate waits for the end of the command. Opened and deleted by the command in the same transaction; never readable or writable by API roles.';

-- El disparador de 20260928130000 con dos cambios: un neumático cuenta como
-- pieza de su rueda (con marca o sin ella), y mientras el comando de guardado
-- escribe un trabajo, la puerta sólo anota qué cambió y el comando la corre
-- al final sobre lo que quedó (`mechanic_job_line_gate_internal`). La espera
-- la abre sólo el comando; cualquier otro escritor tiene la puerta inmediata.
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
  v_evidence_only boolean := false;
begin
  -- Una línea sin configuración (nula) no instala nada: sin el `coalesce`
  -- la cuenta quedaba nula y, anotada, borraba la lista entera.
  if tg_op = 'DELETE' then
    v_line := old;
    v_installed_before := coalesce(old.service_configuration_data ? 'hole_count'
      or old.service_configuration_data ? 'part_change', false);
  else
    v_line := new;
    v_installs := coalesce(new.service_configuration_data ? 'hole_count'
      or new.service_configuration_data ? 'part_change', false);
    if tg_op = 'UPDATE' then
      v_installed_before := coalesce(old.service_configuration_data ? 'hole_count'
        or old.service_configuration_data ? 'part_change', false);
    end if;
  end if;
  if not v_installs and not v_installed_before then
    -- Una maza, una llanta o un neumático sin marca no cambia la ficha, pero
    -- las otras líneas de su rueda se miden con ella: en un trabajo terminado
    -- también pasa por la revisión de la otra línea (revisión de Codex,
    -- 2026-09-28). Su familia se lee recién con el trabajo terminado.
    if tg_op = 'DELETE' or new.product_id is null then
      return null;
    end if;
    v_evidence_only := true;
  end if;

  -- Una línea que instala algo no se mueve a otro trabajo: su recibo quedaría
  -- en la bici del primero sin aviso y el segundo no la aplicaría. Nada en la
  -- app lo hace (revisión de Codex, 2026-09-28). Una línea cualquiera sí.
  if tg_op = 'UPDATE' and old.job_id is distinct from new.job_id then
    if v_evidence_only
       and coalesce(public.product_bike_fact_spec_internal(
             new.tenant_id, new.product_id, '_family')->>'template_key', '')
           not in ('hub', 'rim', 'tire') then
      return null;
    end if;
    raise exception '«%» no se movió: una línea que cambia la ficha de la bici no pasa a otro trabajo. Bórrala y agrégala en el otro.',
      coalesce(nullif(btrim(new.product_name), ''), 'La línea')
      using errcode = '23514';
  end if;

  -- El comando de guardado escribe las líneas de este trabajo como un solo
  -- cambio (20260928140000): se anota la línea y la puerta corre al final
  -- (que mira el estado del trabajo y la familia de lo que no instala).
  update public.mechanic_job_line_gate_deferrals d
     set lines = d.lines || case when d.lines = '' then '' else ',' end
           || v_line.id::text || ':' || tg_op || ':' || v_installed_before::text
   where d.txid = txid_current()
     and d.tenant_id = v_line.tenant_id
     and d.job_id = v_line.job_id;
  if found then
    return null;
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
  if v_evidence_only
     and coalesce(public.product_bike_fact_spec_internal(
           new.tenant_id, new.product_id, '_family')->>'template_key', '')
         not in ('hub', 'rim', 'tire') then
    return null;
  end if;

  -- Los avisos que anota este cambio son obligatorios: si la historia de la
  -- bici no los acepta, la línea no se borra ni se guarda.
  if not v_evidence_only then
    v_result := public.apply_job_installed_bike_facts_internal(
      v_line.tenant_id,
      v_line.job_id,
      true
    );

    if not v_installs then
      -- Se le quitó la marca: no instala, pero si es una maza, una llanta o
      -- un neumático las otras líneas de su rueda se siguen midiendo con ella
      -- (revisión de Codex, 2026-09-28).
      if tg_op = 'DELETE'
         or new.product_id is null
         or coalesce(public.product_bike_fact_spec_internal(
              new.tenant_id, new.product_id, '_family')->>'template_key', '')
            not in ('hub', 'rim', 'tire') then
        return null;
      end if;
      v_evidence_only := true;
    end if;
  end if;

  perform public.job_line_gate_check_internal(v_line, v_evidence_only, v_result);
  return null;
end;
$function$;

revoke all on function public.apply_installed_bike_facts_on_job_line_change()
  from public, anon, authenticated, service_role;

-- La puerta del guardado, una vez, sobre lo que quedó: con las líneas que
-- anotó el disparador (`id:operación:instalaba_antes`), si el trabajo está
-- terminado aplica lo instalado una vez (si alguna línea instala o
-- instalaba) y revisa cada línea que quedó, en el orden en que se escribió.
-- Una línea borrada sólo cuenta para aplicar (un borrado nunca se rechaza).
create or replace function public.mechanic_job_line_gate_internal(
  p_tenant_id uuid,
  p_job_id uuid,
  p_lines text
)
returns void
language plpgsql
set search_path to 'public'
as $function$
declare
  v_status text;
  v_entry text;
  v_parts text[];
  v_row public.mechanic_job_items%rowtype;
  v_installs boolean;
  v_apply boolean := false;
  v_result jsonb;
  v_seen uuid[] := array[]::uuid[];
begin
  if p_lines is null or p_lines = '' then
    return;
  end if;
  select j.status
    into v_status
    from public.mechanic_jobs j
   where j.id = p_job_id
     and j.tenant_id = p_tenant_id
     and j.deleted_at is null
   for no key update;
  if v_status is null or v_status not in ('FINALIZADO', 'ENTREGADO') then
    return;
  end if;

  foreach v_entry in array string_to_array(p_lines, ',')
  loop
    v_parts := string_to_array(v_entry, ':');
    if v_parts[3] = 'true'
       or exists (
         select 1
           from public.mechanic_job_items i
          where i.id = v_parts[1]::uuid
            and i.tenant_id = p_tenant_id
            and i.job_id = p_job_id
            and (i.service_configuration_data ? 'hole_count'
                 or i.service_configuration_data ? 'part_change')) then
      v_apply := true;
    end if;
  end loop;
  if v_apply then
    v_result := public.apply_job_installed_bike_facts_internal(
      p_tenant_id, p_job_id, true);
  end if;

  foreach v_entry in array string_to_array(p_lines, ',')
  loop
    v_parts := string_to_array(v_entry, ':');
    continue when v_parts[2] = 'DELETE' or v_parts[1]::uuid = any (v_seen);
    v_seen := v_seen || v_parts[1]::uuid;
    select *
      into v_row
      from public.mechanic_job_items i
     where i.id = v_parts[1]::uuid
       and i.tenant_id = p_tenant_id
       and i.job_id = p_job_id;
    continue when not found;
    v_installs := coalesce(v_row.service_configuration_data ? 'hole_count'
      or v_row.service_configuration_data ? 'part_change', false);
    continue when not v_installs
      and (v_row.product_id is null
           or coalesce(public.product_bike_fact_spec_internal(
                v_row.tenant_id, v_row.product_id, '_family')->>'template_key', '')
              not in ('hub', 'rim', 'tire'));
    perform public.job_line_gate_check_internal(v_row, not v_installs, v_result);
  end loop;
end;
$function$;

revoke all on function public.mechanic_job_line_gate_internal(uuid, uuid, text)
  from public, anon, authenticated, service_role;

-- De qué bici es una línea lo dicen las bicis del trabajo: la de su fila
-- (si la fila sigue en el trabajo); en General, la única fila, ninguna si hay
-- dos, y sin filas la bici de la cabecera (`job_line_bike_internal`).
-- Agregar, quitar o mover una bici, cambiar la de una fila, o la de la
-- cabecera de un trabajo sin filas, cambia de quién son las líneas sin
-- tocarlas, y con ellas contra qué pieza del trabajo se mide cada una. Ninguna
-- puerta lo miraba: una marca de General en un trabajo terminado quedaba en
-- la ficha de la primera bici sin línea que la respalde (revisión de Codex,
-- 2026-09-29). Ahora todas las líneas de ese trabajo pasan por la puerta de
-- siempre —también la que tiene bici y se medía contra una pieza de General,
-- y las de una fila que se fue a otro trabajo (segunda revisión)—: una marca
-- que se queda sin bici se rechaza con «Asígnala a su bici». Dentro del
-- comando de guardado se anotan y la puerta corre al final.
create or replace function public.job_lines_bike_changed_internal(
  p_tenant_id uuid,
  p_job_id uuid
)
returns void
language plpgsql
set search_path to 'public'
as $function$
declare
  v_lines text;
begin
  select string_agg(i.id::text || ':UPDATE:false', ',' order by i.created_at, i.id)
    into v_lines
    from public.mechanic_job_items i
   where i.tenant_id = p_tenant_id
     and i.job_id = p_job_id;
  if v_lines is null then
    return;
  end if;
  update public.mechanic_job_line_gate_deferrals d
     set lines = d.lines || case when d.lines = '' then '' else ',' end || v_lines
   where d.txid = txid_current()
     and d.tenant_id = p_tenant_id
     and d.job_id = p_job_id;
  if not found then
    perform public.mechanic_job_line_gate_internal(p_tenant_id, p_job_id, v_lines);
  end if;
end;
$function$;

revoke all on function public.job_lines_bike_changed_internal(uuid, uuid)
  from public, anon, authenticated, service_role;

create or replace function public.gate_job_lines_on_job_bike_change()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if tg_table_name = 'mechanic_jobs' then
    -- La bici de la cabecera sólo decide sin filas de bicis.
    if new.bike_id is distinct from old.bike_id
       and not exists (
         select 1
           from public.mechanic_job_bikes jb
          where jb.job_id = new.id
            and jb.tenant_id = new.tenant_id) then
      perform public.job_lines_bike_changed_internal(new.tenant_id, new.id);
    end if;
    return null;
  end if;

  if tg_op = 'INSERT' then
    perform public.job_lines_bike_changed_internal(new.tenant_id, new.job_id);
  elsif tg_op = 'DELETE' then
    perform public.job_lines_bike_changed_internal(old.tenant_id, old.job_id);
  elsif new.job_id is distinct from old.job_id then
    perform public.job_lines_bike_changed_internal(old.tenant_id, old.job_id);
    perform public.job_lines_bike_changed_internal(new.tenant_id, new.job_id);
  elsif new.bike_id is distinct from old.bike_id then
    perform public.job_lines_bike_changed_internal(new.tenant_id, new.job_id);
  end if;
  return null;
end;
$function$;

revoke all on function public.gate_job_lines_on_job_bike_change()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_mechanic_job_bikes_gate_job_lines
  on public.mechanic_job_bikes;
create trigger trg_mechanic_job_bikes_gate_job_lines
  after insert or delete or update of bike_id, job_id
  on public.mechanic_job_bikes
  for each row execute function public.gate_job_lines_on_job_bike_change();

drop trigger if exists trg_mechanic_jobs_gate_job_lines_on_bike
  on public.mechanic_jobs;
create trigger trg_mechanic_jobs_gate_job_lines_on_bike
  after update of bike_id
  on public.mechanic_jobs
  for each row execute function public.gate_job_lines_on_job_bike_change();

-- El comando de guardado: abre la espera antes de escribir (la cabecera, las
-- bicis, las líneas) y corre la puerta al final, después de lo que confirmó
-- «Configurar» (que puede cambiar el aro de la bici): sobre lo que quedó de
-- verdad (revisión de Codex, 2026-09-29). Se inserta sobre la definición de
-- 20260928080000, reejecutable: anclas exactas, cada una una sola vez.
do $do$
declare
  v_fn regprocedure :=
    'public.save_mechanic_job_lines_v1(text,uuid,jsonb,jsonb,jsonb,jsonb,jsonb,boolean)'::regprocedure;
  v_def text;
  v_anchors text[] := array[
$a$  -- La cabecera: cada campo cambiado debe seguir como lo vio el formulario.
$a$,
$a$  -- La factura del trabajo al día, en la misma transacción que el recibo
$a$
  ];
  v_blocks text[] := array[
$a$  -- Lo que sigue se guarda como un solo cambio: en un trabajo terminado la
  -- puerta mira lo que quedó, no cada paso (20260928140000). La espera es de
  -- esta transacción y la cierra este mismo comando.
  insert into public.mechanic_job_line_gate_deferrals (txid, tenant_id, job_id)
  values (txid_current(), v_tenant_id, p_job_id)
  on conflict (txid, tenant_id, job_id) do update set lines = '';

  -- La cabecera: cada campo cambiado debe seguir como lo vio el formulario.
$a$,
$a$  -- La puerta del trabajo terminado, una vez, sobre lo que quedó.
  declare
    v_gate_lines text;
  begin
    delete from public.mechanic_job_line_gate_deferrals d
     where d.txid = txid_current()
       and d.tenant_id = v_tenant_id
       and d.job_id = p_job_id
    returning d.lines into v_gate_lines;
    perform public.mechanic_job_line_gate_internal(
      v_tenant_id, p_job_id, v_gate_lines);
  end;

  -- La factura del trabajo al día, en la misma transacción que el recibo
$a$
  ];
  v_index integer;
begin
  v_def := pg_get_functiondef(v_fn);
  if position('La puerta del trabajo terminado, una vez, sobre lo que quedó.' in v_def) > 0 then
    return;
  end if;
  for v_index in 1 .. array_length(v_anchors, 1) loop
    if (length(v_def) - length(replace(v_def, v_anchors[v_index], '')))
       / length(v_anchors[v_index]) <> 1 then
      raise exception 'save anchor % not found exactly once', v_index;
    end if;
    v_def := replace(v_def, v_anchors[v_index], v_blocks[v_index]);
  end loop;
  execute v_def;
end;
$do$;

commit;
