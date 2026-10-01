-- Deployment status: NOT DEPLOYED
-- Cambios de partes, cuarto concepto: la maza delantera y la trasera
-- (BIKE_WORKSHOP_MASTER_SCHEMA.md, «Cambios de partes: la maza»).
--
-- Lo que la evidencia de producción (2026-09-28, sólo lectura) y las fuentes
-- mecánicas cambiaron del pedido «perforaciones, eje, anclaje y driver»:
--
-- * Las 52 mazas del inventario no tienen ningún dato verificado. Dicen su
--   posición 47 (Trasera 24, Delantera 15, Juego 8), sus perforaciones 36, su
--   ancho (OLD) 20, el diámetro del eje 14, el tipo de eje 10, «para disco» 14
--   y su anclaje del rotor sólo 1 (Center Lock, la Shimano HB-RM66). Su
--   núcleo lo dicen 9, y sólo como tipo: «Núcleo de cassette» no dice si es
--   HG, Micro Spline o XD; «Rosca para piñón (rueda libre)» y «Driver BMX» sí
--   son un driver de la ficha de la bici.
-- * Las 29 líneas reales de maza vienen todas con un «Enrayado + Centrado» en
--   el mismo trabajo, ninguna con rueda elegida. Cambiar la maza es armar la
--   rueda otra vez.
-- * **Las perforaciones de la rueda son de la llanta, no de la maza.** Una
--   maza con más perforaciones que la llanta se raya con patrones especiales
--   (36 en 32, 32 en 24…; Sheldon Brown, «Spoking patterns for large
--   hubs»): la llanta usa todas las suyas y la rueda queda con las de la
--   llanta. Una con menos no se puede rayar. La maza no escribe
--   `front/rearSpokeHoles`: sólo tiene que calzar con la rueda que arma el
--   trabajo (el Enrayado de esa rueda, o la llanta nueva, o la ficha).
-- * **El ancho entre punteras y el eje son del cuadro u horquilla.** Una maza
--   distinta se adapta con tapas o adaptadores de su fabricante, o un cuadro
--   de acero se abre en frío; la maza no los cambia. No se escriben ni se
--   rechazan aquí: la app los dice como condición de armado, igual que la
--   matriz.
-- * Lo que sí es de la maza: el driver trasero (el núcleo es parte de la
--   maza) y el anclaje del rotor de su rueda (6 pernos o Center Lock). El
--   anclaje es un dato nuevo de la ficha de la bici, por rueda
--   (`frontRotorMount` / `rearRotorMount`): el rotor tiene que calzar con él.
--   Un rotor de 6 pernos entra en una maza Center Lock con el adaptador
--   Shimano SM-RTAD05, que no sirve para rotores con araña de aluminio
--   (Shimano excluye SM-RT86 y SM-RT76; un flotante la tiene); un rotor Center
--   Lock no tiene adaptador de Shimano para una maza de 6 pernos. El catálogo
--   no tiene la araña como campo: se lee de `rotor_floating`.
-- * Una maza trasera puede decir driver y anclaje a la vez: una línea puede
--   instalar varios datos (`part_change` pasa a aceptar una lista de marcas;
--   la marca de un solo dato sigue siendo un objeto). La llanta lo va a
--   necesitar también (BSD y perforaciones).
-- * El cassette y el piñón de rosca ya no quedan pendientes siempre que el
--   trabajo cambia la maza trasera: si esa maza dice su driver, se comparan
--   con él (decisión D2 del cassette, ahora con dato). Si no lo dice, siguen
--   pendientes.
--
-- Depende de `20260928120000`.
begin;

-- ============================================================================
-- La relación única: la maza y el rotor
-- ============================================================================

comment on column public.bike_fact_spec_links.product_condition is
  'La fila vale sólo si el producto cumple la condición: {spec_key, min, max} (un piñón de rosca de 2 a 14 coronas) o {spec_key, values, missing_ok} (una maza trasera o sin posición dicha).';

-- La posición de la maza la dice su ficha técnica; si no la dice, la rueda que
-- eligió el mecánico. Un juego (dos mazas en una línea) no instala nada: una
-- línea es una rueda.
insert into public.bike_fact_spec_links (
  spec_key, position, bike_fact_key, component_label, component_article,
  unit, requires_fact_key, requires_fact_values, min_value, max_value,
  template_key, on_mismatch, value_map, constant_value, fits,
  product_condition
) values
  -- El driver es de la maza trasera: sólo lo que es un código de la ficha.
  ('hub_drive_receiver_kind', 'rear', 'freehubType', 'driver trasero', 'el',
   null, null, '{}', 0, 0, 'hub', 'change',
   jsonb_build_object(
     'Rosca para piñón (rueda libre)', 'threaded_freewheel',
     'Driver BMX', 'bmx_driver',
     'Rosca para piñón fijo', 'fixed_threaded'),
   null, null,
   '{"spec_key": "hub_package_position", "values": ["Trasera", "Universal"], "missing_ok": true}'::jsonb),
  -- El anclaje del rotor lo pone la maza de esa rueda.
  ('rotor_mount_type', 'front', 'frontRotorMount', 'anclaje del rotor delantero', 'el',
   null, null, '{}', 0, 0, 'hub', 'change',
   jsonb_build_object('6 pernos', 'six_bolt', 'Centerlock', 'centerlock'),
   null, null,
   '{"spec_key": "hub_package_position", "values": ["Delantera", "Universal"], "missing_ok": true}'::jsonb),
  ('rotor_mount_type', 'rear', 'rearRotorMount', 'anclaje del rotor trasero', 'el',
   null, null, '{}', 0, 0, 'hub', 'change',
   jsonb_build_object('6 pernos', 'six_bolt', 'Centerlock', 'centerlock'),
   null, null,
   '{"spec_key": "hub_package_position", "values": ["Trasera", "Universal"], "missing_ok": true}'::jsonb),
  -- Las perforaciones de la maza sólo se revisan contra la rueda que se arma.
  ('spoke_hole_count', 'front', 'frontSpokeHoles', 'rueda delantera', 'la',
   null, null, '{}', 12, 48, 'hub', 'check', null, null, null,
   '{"spec_key": "hub_package_position", "values": ["Delantera", "Universal"], "missing_ok": true}'::jsonb),
  ('spoke_hole_count', 'rear', 'rearSpokeHoles', 'rueda trasera', 'la',
   null, null, '{}', 12, 48, 'hub', 'check', null, null, null,
   '{"spec_key": "hub_package_position", "values": ["Trasera", "Universal"], "missing_ok": true}'::jsonb),
  -- El rotor tiene que calzar con el anclaje de su maza; uno de 6 pernos entra
  -- en una Center Lock con el SM-RTAD05 (no con araña de aluminio).
  ('rotor_mount_type', 'front', 'frontRotorMount', 'anclaje del rotor delantero', 'el',
   null, null, '{}', 0, 0, 'rotor', 'check',
   jsonb_build_object('6 pernos', 'six_bolt', 'Centerlock', 'centerlock'),
   null, '{"six_bolt": ["centerlock"]}'::jsonb, null),
  ('rotor_mount_type', 'rear', 'rearRotorMount', 'anclaje del rotor trasero', 'el',
   null, null, '{}', 0, 0, 'rotor', 'check',
   jsonb_build_object('6 pernos', 'six_bolt', 'Centerlock', 'centerlock'),
   null, '{"six_bolt": ["centerlock"]}'::jsonb, null)
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

-- Los nombres de `kBikeRotorMountOptions` (`brake_canonical_data.dart`).
create or replace function public.rotor_mount_label(p_code text)
returns text
language sql
immutable
set search_path to 'public'
as $function$
  select case p_code
    when 'six_bolt' then '6 pernos'
    when 'centerlock' then 'Center Lock'
    else coalesce(p_code, '?')
  end;
$function$;

revoke all on function public.rotor_mount_label(text)
  from public, anon, authenticated, service_role;

-- «Center Lock en el anclaje del rotor delantero», y lo de antes igual.
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
    when p_key in ('frontRotorMount', 'rearRotorMount') then
      public.rotor_mount_label(p_value #>> '{}') || ' en el anclaje del rotor '
        || case p_key when 'frontRotorMount' then 'delantero' else 'trasero' end
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

-- «la rueda trasera lleva 36 rayos», «el anclaje del rotor delantero es
-- «6 pernos»».
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
    when p_requires_key in ('frontSpokeHoles', 'rearSpokeHoles') then
      'la rueda '
        || case p_requires_key when 'frontSpokeHoles' then 'delantera' else 'trasera' end
        || ' lleva ' || coalesce(p_requires_value, '?') || ' rayos'
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

-- Qué hacer cuando no calza.
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
-- Las marcas de una línea, y la regla de cada una
-- ============================================================================

-- Lo que el mecánico confirmó en la línea: una marca `{key, value}` o, si la
-- pieza instala varios datos (una maza trasera con driver y anclaje), una
-- lista. Siempre como lista ordenada por clave; lo que no es una marca no
-- cuenta.
create or replace function public.job_line_part_change_marks_internal(p_marks jsonb)
returns jsonb
language sql
immutable
set search_path to 'public'
as $function$
  select coalesce((
    select jsonb_agg(mark order by mark->>'key')
      from jsonb_array_elements(case jsonb_typeof(p_marks)
             when 'object' then jsonb_build_array(p_marks)
             when 'array' then p_marks
             else '[]'::jsonb
           end) mark
     where jsonb_typeof(mark) = 'object'
       and jsonb_typeof(mark->'key') = 'string'), '[]'::jsonb);
$function$;

revoke all on function public.job_line_part_change_marks_internal(jsonb)
  from public, anon, authenticated, service_role;

-- Lo que la fila exige del producto: una cuenta entre dos medidas, o uno de
-- unos valores (sin el dato, sólo si la fila lo permite).
create or replace function public.bike_fact_product_condition_met_internal(
  p_tenant_id uuid,
  p_product_id uuid,
  p_condition jsonb
)
returns boolean
language plpgsql
stable
set search_path to 'public'
as $function$
declare
  v_text text;
begin
  if p_condition is null or jsonb_typeof(p_condition) <> 'object' then
    return true;
  end if;
  v_text := public.product_bike_fact_spec_internal(
    p_tenant_id, p_product_id, p_condition->>'spec_key')->'value' #>> '{}';
  if p_condition ? 'values' then
    if v_text is null or btrim(v_text) = '' then
      return coalesce((p_condition->>'missing_ok')::boolean, false);
    end if;
    return p_condition->'values' ? v_text;
  end if;
  if v_text is null or v_text !~ '^[0-9]{1,4}(\.0+)?$' then
    return false;
  end if;
  return v_text::numeric >= (p_condition->>'min')::numeric
     and v_text::numeric
         <= coalesce((p_condition->>'max')::numeric, v_text::numeric);
end;
$function$;

revoke all on function public.bike_fact_product_condition_met_internal(uuid, uuid, jsonb)
  from public, anon, authenticated, service_role;

-- La marca de una clave, si todavía calza con el repuesto, la rueda y la
-- ficha técnica del producto. La misma regla de antes, por clave: una línea
-- puede marcar varias, cada una una vez.
create or replace function public.job_line_part_change_internal(
  p_tenant_id uuid,
  p_item_id uuid,
  p_key text
)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare
  v_item public.mechanic_job_items%rowtype;
  v_link public.bike_fact_spec_links%rowtype;
  v_marks jsonb;
  v_marked jsonb;
  v_spec jsonb;
  v_value jsonb;
  v_found boolean := false;
begin
  select *
    into v_item
    from public.mechanic_job_items i
   where i.id = p_item_id
     and i.tenant_id = p_tenant_id;
  if not found or v_item.product_id is null or p_key is null then
    return null;
  end if;

  v_marks := public.job_line_part_change_marks_internal(
    v_item.service_configuration_data->'part_change');
  -- Una clave, una marca: dos marcas de la misma clave no dicen cuál vale.
  if (select count(*) from jsonb_array_elements(v_marks) m
       where m->>'key' = p_key) <> 1 then
    return null;
  end if;
  select m->'value'
    into v_marked
    from jsonb_array_elements(v_marks) m
   where m->>'key' = p_key;

  for v_link in
    select *
      from public.bike_fact_spec_links l
     where l.bike_fact_key = p_key
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
  -- coronas; una maza delantera, trasera o sin posición dicha (no un juego).
  if not public.bike_fact_product_condition_met_internal(
       p_tenant_id, v_item.product_id, v_link.product_condition) then
    return null;
  end if;

  v_value := public.bike_fact_link_value_internal(v_link, v_spec);
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

revoke all on function public.job_line_part_change_internal(uuid, uuid, text)
  from public, anon, authenticated, service_role;

-- La de siempre, para una línea de un solo dato (el rotor, el neumático, el
-- cassette); con varias marcas no dice cuál.
create or replace function public.job_line_part_change_internal(
  p_tenant_id uuid,
  p_item_id uuid
)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare
  v_marks jsonb;
begin
  select public.job_line_part_change_marks_internal(
           i.service_configuration_data->'part_change')
    into v_marks
    from public.mechanic_job_items i
   where i.id = p_item_id
     and i.tenant_id = p_tenant_id;
  if v_marks is null or jsonb_array_length(v_marks) <> 1 then
    return null;
  end if;
  return public.job_line_part_change_internal(
    p_tenant_id, p_item_id, v_marks->0->>'key');
end;
$function$;

revoke all on function public.job_line_part_change_internal(uuid, uuid)
  from public, anon, authenticated, service_role;

-- ============================================================================
-- Lo que el mismo trabajo instala en esa rueda
-- ============================================================================

-- Una maza que otra línea del mismo trabajo instala en esa rueda de esa bici,
-- con evidencia: la rueda de la línea, o (sin rueda) la posición del
-- producto; un juego cuenta en las dos. Dice el driver o el anclaje sólo si
-- todas las mazas de esa rueda lo dicen igual. Nula si no hay ninguna.
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
               and l.on_mismatch = 'change') as rotor_mount
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
           end)
         end
    from hubs;
$function$;

revoke all on function public.job_hub_at_wheel_internal(uuid, uuid, uuid, text)
  from public, anon, authenticated, service_role;

-- Cuántos rayos lleva la rueda que queda: la que arma el mismo trabajo
-- (el `hole_count` del Enrayado de esa rueda), si no la llanta nueva de esa
-- rueda (sus perforaciones), si no la ficha. Nula si nada lo dice; una
-- llanta nueva sin perforaciones dichas tampoco refuta.
create or replace function public.job_wheel_spokes_internal(
  p_tenant_id uuid,
  p_item_id uuid,
  p_bike_id uuid,
  p_position text,
  p_bike_values jsonb
)
returns jsonb
language plpgsql
stable
set search_path to 'public'
as $function$
declare
  v_counts integer[];
  v_rims integer;
  v_rim_holes integer[];
  v_text text;
begin
  select array_agg(distinct (other.service_configuration_data->>'hole_count')::integer)
    into v_counts
    from public.mechanic_job_items self
    join public.mechanic_job_items other
      on other.job_id = self.job_id
     and other.tenant_id = self.tenant_id
     and other.id <> self.id
   where self.id = p_item_id
     and self.tenant_id = p_tenant_id
     and other.service_configuration_data ? 'hole_count'
     and (other.service_configuration_data->>'hole_count') ~ '^[1-9][0-9]{0,2}$'
     -- Fuera del rango de taller es un error de tipeo, no una rueda.
     and (other.service_configuration_data->>'hole_count')::integer between 12 and 48
     and coalesce(nullif(other.location_key, 'none'),
                  other.service_configuration_data->>'which_wheel') = p_position
     and public.job_line_bike_internal(p_tenant_id, other.id) = p_bike_id;
  if cardinality(v_counts) = 1 then
    return jsonb_build_object('value', v_counts[1], 'source', 'job_build');
  elsif cardinality(v_counts) > 1 then
    -- Dos Enrayados de la misma rueda que dicen otra cantidad: el trabajo la
    -- decide, pero no se sabe cuál; una maza no se da por buena (revisión de
    -- Codex, 2026-09-28).
    return jsonb_build_object(
      'value', null,
      'either', (select string_agg(c::text, ' o ' order by c) from unnest(v_counts) c),
      'source', 'job_build');
  end if;

  select count(*)::integer,
         array_agg(distinct (spec->'value' #>> '{}')::numeric::integer)
           filter (where (spec->'value' #>> '{}') ~ '^[0-9]{1,3}(\.0+)?$')
    into v_rims, v_rim_holes
    from public.mechanic_job_items self
    join public.mechanic_job_items other
      on other.job_id = self.job_id
     and other.tenant_id = self.tenant_id
     and other.id <> self.id
    cross join lateral (
      select public.product_bike_fact_spec_internal(
               p_tenant_id, other.product_id, 'spoke_hole_count') as spec
    ) s
   where self.id = p_item_id
     and self.tenant_id = p_tenant_id
     and other.product_id is not null
     and other.location_key = p_position
     and public.job_line_bike_internal(p_tenant_id, other.id) = p_bike_id
     and public.product_bike_fact_spec_internal(
           p_tenant_id, other.product_id, '_family')->>'template_key' = 'rim';
  if v_rims > 0 then
    if cardinality(v_rim_holes) = 1 then
      return jsonb_build_object('value', v_rim_holes[1], 'source', 'job_rim');
    elsif cardinality(v_rim_holes) > 1 then
      return jsonb_build_object(
        'value', null,
        'either', (select string_agg(c::text, ' o ' order by c) from unnest(v_rim_holes) c),
        'source', 'job_rim');
    end if;
    return null;
  end if;

  v_text := p_bike_values->>(case p_position
    when 'front' then 'frontSpokeHoles' else 'rearSpokeHoles' end);
  if v_text ~ '^[0-9]{1,3}(\.0+)?$' then
    return jsonb_build_object('value', v_text::numeric::integer, 'source', 'bike');
  end if;
  return null;
end;
$function$;

revoke all on function public.job_wheel_spokes_internal(uuid, uuid, uuid, text, jsonb)
  from public, anon, authenticated, service_role;

-- Una maza con más perforaciones que la llanta se raya en los patrones de
-- Sheldon Brown («Spoking patterns for large hubs»): 5:3, 4:3, 3:2, 5:4,
-- 9:7, 2:1 y cuatro perforaciones más. Con menos, o en otra razón, no.
create or replace function public.hub_lacing_fits(p_hub integer, p_rim integer)
returns boolean
language sql
immutable
set search_path to 'public'
as $function$
  select p_hub = p_rim
      or (p_hub, p_rim) in (
           (40, 24), (32, 24), (48, 36), (36, 24), (48, 32), (40, 32),
           (36, 28), (48, 24), (28, 24), (32, 28), (36, 32), (40, 36));
$function$;

revoke all on function public.hub_lacing_fits(integer, integer)
  from public, anon, authenticated, service_role;

-- ============================================================================
-- El calce
-- ============================================================================

-- Lo que sólo se revisa de una pieza marcada, contra su rueda: sus piñones
-- contra la transmisión, sus perforaciones contra la rueda que queda, el
-- anclaje de un rotor contra el de su maza. Depende del repuesto, no sólo del
-- dato que escribe: se vuelve a mirar aunque el recibo de la línea ya exista
-- (la misma marca en otra maza deja el mismo recibo; revisión de Codex,
-- 2026-09-28).
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

-- El calce de 20260928120000, por clave, con tres cosas nuevas:
-- * el driver del cassette o del piñón de rosca se compara con el de la maza
--   trasera que instala el mismo trabajo, si esa maza lo dice (si no lo dice,
--   queda pendiente como antes);
-- * lo que sólo se revisa de una maza: sus perforaciones contra la rueda que
--   queda (`job_wheel_spokes_internal`, `hub_lacing_fits`);
-- * lo que sólo se revisa de un rotor: su anclaje contra el de la maza de esa
--   rueda (la del mismo trabajo, si no la ficha); uno de 6 pernos entra en una
--   Center Lock con el SM-RTAD05, salvo con araña de aluminio (flotante).
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
  v_known boolean;
  v_own boolean := false;
  v_candidates integer[];
  v_fits jsonb;
  v_rear_hub jsonb;
  v_hub_decided boolean := false;
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

    if not v_hub_decided then
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
  end if;

  -- Lo que sólo se revisa, de la misma familia y rueda
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
-- Lo que cada línea escribió: por clave
-- ============================================================================

-- `{línea: {key, value}}` para una línea de un dato, como antes, y
-- `{línea: [{key, value}, …]}` cuando escribió varios (una maza trasera).
create or replace function public.job_part_change_writers_v1(p_job_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare
  v_tenant_id uuid;
  v_item record;
  v_mark jsonb;
  v_bike_id uuid;
  v_key text;
  v_current jsonb;
  v_written jsonb;
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
    select i.id,
           public.job_line_part_change_marks_internal(
             i.service_configuration_data->'part_change') as marks
      from public.mechanic_job_items i
     where i.job_id = p_job_id
       and i.tenant_id = v_tenant_id
       and jsonb_typeof(i.service_configuration_data->'part_change')
           in ('object', 'array')
  loop
    v_bike_id := public.job_line_bike_internal(v_tenant_id, v_item.id);
    if v_bike_id is null then
      continue;
    end if;
    v_written := '[]'::jsonb;
    for v_mark in select value from jsonb_array_elements(v_item.marks)
    loop
      v_key := v_mark->>'key';
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
        v_written := v_written || jsonb_build_array(jsonb_build_object(
          'key', v_key,
          'value', case
            when jsonb_typeof(v_current) = 'number'
              then to_jsonb(((v_current #>> '{}')::numeric)::integer)
            else v_current
          end));
      end if;
    end loop;
    if jsonb_array_length(v_written) = 1 then
      v_result := v_result || jsonb_build_object(v_item.id::text, v_written->0);
    elsif jsonb_array_length(v_written) > 1 then
      v_result := v_result || jsonb_build_object(v_item.id::text, v_written);
    end if;
  end loop;
  return v_result;
end;
$function$;

revoke all on function public.job_part_change_writers_v1(uuid)
  from public, anon, service_role;
grant execute on function public.job_part_change_writers_v1(uuid) to authenticated;

-- ============================================================================
-- Aplicar lo instalado: una línea, uno o varios datos
-- ============================================================================

-- El aplicador de 20260928120000 con una línea que instala varios datos (una
-- maza trasera: driver y anclaje). Cada marca se verifica por su clave; lo
-- que no calza se informa por dato; lo que sí, se escribe en un solo recibo
-- de la línea (`job_completion:<línea>:<n>:<k1>=<v1>,<k2>=<v2>`), como antes
-- con un dato. La bici se toma una vez por línea.
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
  v_mark jsonb;
  v_verified jsonb;
  v_facts jsonb;
  v_kept jsonb;
  v_write jsonb;
  v_fact jsonb;
  v_value jsonb;
  v_key text;
  v_link public.bike_fact_spec_links%rowtype;
  v_misfit text;
  v_requires jsonb;
  v_wheel_size text;
  v_profile_values jsonb;
  v_profile_sources jsonb;
  v_profile_confirmed jsonb;
  v_bike_id uuid;
  v_facts_suffix text;
  v_write_suffix text;
  v_latest integer;
  v_latest_suffix text;
  v_operation_key text;
  v_current jsonb;
  v_latest_bike_id uuid;
  v_claims jsonb := '[]'::jsonb;
  v_prior record;
  v_receipt jsonb;
  v_applied jsonb := '[]'::jsonb;
  v_problems jsonb := '[]'::jsonb;
  v_evaluated boolean;
  v_other_holes text;
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
    -- Una línea instala perforaciones (un servicio) o un repuesto. Con las
    -- dos, se informa y no se escribe ninguna.
    if v_item.data ? 'hole_count' and v_item.data ? 'part_change' then
      v_problems := v_problems || jsonb_build_array(jsonb_build_object(
        'item_id', v_item.id,
        'item_name', v_item.product_name,
        'reason', 'mixed_change'
      ));
      continue;
    end if;

    v_facts := '[]'::jsonb;
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
      -- Dos Enrayados de la misma rueda de la misma bici que dicen otra
      -- cantidad: no se sabe cuál vale, y con eso una maza nueva no se puede
      -- revisar. Ninguno escribe y se dice (revisión de Codex,
      -- 2026-09-28).
      v_other_holes := null;
      -- (Uno propio fuera de rango lo informa el rango, más abajo.)
      select min(o.service_configuration_data->>'hole_count')
        into v_other_holes
        from public.mechanic_job_items o
       where o.job_id = p_job_id
         and o.tenant_id = p_tenant_id
         and o.id <> v_item.id
         and (o.service_configuration_data->>'hole_count') ~ '^[1-9][0-9]{0,2}$'
         -- Uno fuera del rango de taller es un error de tipeo, y ya se informa.
         and (o.service_configuration_data->>'hole_count')::integer between 12 and 48
         and o.service_configuration_data->>'hole_count' <> v_holes_text
         and coalesce(nullif(o.location_key, 'none'),
                      o.service_configuration_data->>'which_wheel') = v_position
         and public.job_line_bike_internal(p_tenant_id, o.id)
             is not distinct from public.job_line_bike_internal(p_tenant_id, v_item.id)
         and v_holes_text::integer between 12 and 48;
      if v_other_holes is not null then
        v_problems := v_problems || jsonb_build_array(jsonb_build_object(
          'item_id', v_item.id,
          'item_name', v_item.product_name,
          'key', case v_position
            when 'front' then 'frontSpokeHoles'
            else 'rearSpokeHoles'
          end,
          'value', to_jsonb(v_holes_text::integer),
          'reason', 'conflicting_build',
          'requires_value', v_other_holes
        ));
        continue;
      end if;
      -- Las perforaciones las contó el mecánico en el asistente: confirmadas.
      v_facts := jsonb_build_array(jsonb_build_object(
        'key', case v_position
          when 'front' then 'frontSpokeHoles'
          else 'rearSpokeHoles'
        end,
        'value', to_jsonb(v_holes_text::integer),
        'op', 'set',
        'link_id', null));
    else
      -- Un repuesto con sus marcas: cada una es lo que el mecánico vio al
      -- elegir la rueda, si todavía calza con el repuesto, la rueda y la ficha
      -- técnica del producto. Si no, se informa esa y no se escribe.
      if jsonb_array_length(public.job_line_part_change_marks_internal(
           v_item.data->'part_change')) = 0 then
        v_problems := v_problems || jsonb_build_array(jsonb_build_object(
          'item_id', v_item.id,
          'item_name', v_item.product_name,
          'key', null,
          'value', v_item.data->'part_change',
          'reason', 'stale_change'
        ));
        continue;
      end if;
      for v_mark in
        select value
          from jsonb_array_elements(public.job_line_part_change_marks_internal(
                 v_item.data->'part_change'))
      loop
        v_verified := public.job_line_part_change_internal(
          p_tenant_id, v_item.id, v_mark->>'key');
        if v_verified is null then
          v_problems := v_problems || jsonb_build_array(jsonb_build_object(
            'item_id', v_item.id,
            'item_name', v_item.product_name,
            'key', v_mark->>'key',
            'value', v_mark->'value',
            'reason', 'stale_change'
          ));
          continue;
        end if;
        -- Lo que dice la ficha técnica del repuesto entra declarado; sólo un
        -- dato verificado del producto se escribe confirmado (20260928110000).
        v_facts := v_facts || jsonb_build_array(jsonb_build_object(
          'key', v_verified->>'key',
          'value', v_verified->'value',
          'op', case
            when coalesce((v_verified->>'verified')::boolean, false) then 'set'
            else 'declare'
          end,
          'link_id', v_verified->>'link_id'));
      end loop;
    end if;
    if jsonb_array_length(v_facts) = 0 then
      continue;
    end if;

    -- La bici de la línea, con la misma regla que el parche: una línea de
    -- General es de la única bici del trabajo (o de la bici del trabajo, si no
    -- tiene filas de bicis).
    v_bike_id := public.job_line_bike_internal(p_tenant_id, v_item.id);
    if v_bike_id is null then
      for v_fact in select value from jsonb_array_elements(v_facts)
      loop
        v_problems := v_problems || jsonb_build_array(jsonb_build_object(
          'item_id', v_item.id,
          'item_name', v_item.product_name,
          'key', v_fact->>'key',
          'value', v_fact->'value',
          'reason', 'line_without_bike'
        ));
      end loop;
      continue;
    end if;

    -- Rangos de taller, los mismos del parche (el de un repuesto, el de su
    -- relación): fuera de ellos es un error de tipeo en la línea o en la
    -- ficha técnica del producto.
    v_kept := '[]'::jsonb;
    for v_fact in select value from jsonb_array_elements(v_facts)
    loop
      v_key := v_fact->>'key';
      v_value := v_fact->'value';
      v_link := null;
      if v_fact->>'link_id' is not null then
        select * into v_link
          from public.bike_fact_spec_links l
         where l.id = (v_fact->>'link_id')::uuid;
      end if;
      if not (case
        when v_key in ('frontSpokeHoles', 'rearSpokeHoles') and v_link.id is null
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
      v_kept := v_kept || jsonb_build_array(v_fact);
    end loop;
    v_facts := v_kept;
    if jsonb_array_length(v_facts) = 0 then
      continue;
    end if;

    -- Lo que esta línea dice hoy que instaló: con esto se reconoce abajo lo
    -- que escribió antes y ya no respalda.
    for v_fact in select value from jsonb_array_elements(v_facts)
    loop
      v_claims := v_claims || jsonb_build_array(jsonb_build_object(
        'item_id', v_item.id,
        'bike_id', v_bike_id,
        'key', v_fact->>'key',
        'value', v_fact->'value'
      ));
    end loop;

    select string_agg((f->>'key') || '=' || (f->'value' #>> '{}'), ','
                      order by f->>'key')
      into v_facts_suffix
      from jsonb_array_elements(v_facts) f;
    v_latest := null;
    v_latest_suffix := null;
    v_latest_bike_id := null;
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
      -- Nada que escribir, pero lo que depende del repuesto se vuelve a
      -- revisar: la misma marca en otra maza (se cambió el repuesto) deja el
      -- mismo recibo y saltaba sus perforaciones (revisión de Codex,
      -- 2026-09-28). Sin tomar la bici: aquí no se escribe.
      if v_item.data ? 'part_change' then
        select coalesce(bp.technical_profile->'values', '{}'::jsonb)
          into v_profile_values
          from public.bike_profiles bp
         where bp.bike_id = v_bike_id
           and bp.tenant_id = p_tenant_id;
        for v_fact in select value from jsonb_array_elements(v_facts)
        loop
          v_requires := public.bike_fact_part_checks_internal(
            p_tenant_id, v_item.id, v_bike_id, v_fact->>'key',
            coalesce(v_profile_values, '{}'::jsonb));
          if v_requires->>'reason' = 'pending' then
            -- Lo mismo que en el camino normal: espera una decisión.
            v_problems := v_problems || jsonb_build_array(jsonb_build_object(
              'item_id', v_item.id,
              'item_name', v_item.product_name,
              'bike_id', v_bike_id,
              'key', v_fact->>'key',
              'value', v_fact->'value',
              'reason', 'pending',
              'pending', v_requires->>'pending',
              'requires_key', v_requires->>'requires_key',
              'requires_value', v_requires->>'requires_value'
            ));
            perform public.record_installed_bike_fact_notice(
              p_tenant_id, v_bike_id, p_job_id,
              'decision:' || v_item.id::text || ':' || (v_fact->>'key') || '='
                || (v_fact->'value' #>> '{}') || ':' || (v_requires->>'requires_value'),
              'installed_fact_needs_decision',
              'Pendiente: la ficha espera una decisión',
              format(
                '«%s» dice %s y la ficha de la bici dice %s, pero %s y guarda el '
                'trabajo. La ficha no cambió.',
                coalesce(v_item.product_name, 'Una línea'),
                public.installed_bike_fact_label(v_fact->>'key', v_fact->'value'),
                public.bike_fact_requirement_text(
                  v_requires->>'requires_key', v_requires->>'requires_value'),
                public.bike_fact_pending_text(v_requires->>'pending')),
              jsonb_build_object(
                'item_id', v_item.id,
                'key', v_fact->>'key',
                'value', v_fact->'value',
                'pending', v_requires->>'pending',
                'requires_key', v_requires->>'requires_key',
                'requires_value', v_requires->>'requires_value'),
              p_notices_required);
            continue;
          end if;
          if v_requires->>'reason' is distinct from 'incompatible' then
            continue;
          end if;
          v_problems := v_problems || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
            'item_id', v_item.id,
            'item_name', v_item.product_name,
            'bike_id', v_bike_id,
            'key', v_fact->>'key',
            'value', v_fact->'value',
            'reason', 'incompatible',
            'requires_key', v_requires->>'requires_key',
            'requires_value', v_requires->>'requires_value',
            'requires_source', v_requires->>'source'
          )));
          perform public.record_installed_bike_fact_notice(
            p_tenant_id, v_bike_id, p_job_id,
            'incompatible:' || v_item.id::text || ':' || (v_fact->>'key') || '='
              || (v_fact->'value' #>> '{}') || ':' || (v_requires->>'requires_value'),
            'installed_fact_incompatible',
            'Aviso: lo instalado no calza con la ficha',
            format(
              '«%s» dice %s, pero %s dice %s: la ficha no cambió. %s',
              coalesce(v_item.product_name, 'Una línea'),
              public.installed_bike_fact_label(v_fact->>'key', v_fact->'value'),
              case v_requires->>'source'
                when 'job_hub' then 'la maza que instala el trabajo'
                when 'job_build' then 'la rueda que arma el trabajo'
                when 'job_rim' then 'la llanta que instala el trabajo'
                else 'la ficha de la bici'
              end,
              public.bike_fact_requirement_text(
                v_requires->>'requires_key', v_requires->>'requires_value'),
              public.bike_fact_requirement_advice(v_requires->>'requires_key')),
            jsonb_strip_nulls(jsonb_build_object(
              'item_id', v_item.id,
              'key', v_fact->>'key',
              'value', v_fact->'value',
              'requires_key', v_requires->>'requires_key',
              'requires_value', v_requires->>'requires_value',
              'requires_source', v_requires->>'source')),
            p_notices_required);
        end loop;
      end if;
      continue;
    end if;
    v_operation_key := 'job_completion:' || v_item.id::text || ':'
      || (coalesce(v_latest, 0) + 1)::text || ':' || v_facts_suffix;
    v_write := null;
    v_evaluated := false;

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
      v_profile_values := null;
      v_profile_sources := null;
      v_profile_confirmed := null;
      select coalesce(bp.technical_profile->'values', '{}'::jsonb),
             coalesce(bp.technical_profile->'sources', '{}'::jsonb),
             coalesce(bp.technical_profile->'confirmed', '{}'::jsonb)
        into v_profile_values, v_profile_sources, v_profile_confirmed
        from public.bike_profiles bp
       where bp.bike_id = v_bike_id
         and bp.tenant_id = p_tenant_id
       for update;
      v_profile_values := coalesce(v_profile_values, '{}'::jsonb);
      v_profile_sources := coalesce(v_profile_sources, '{}'::jsonb);
      v_profile_confirmed := coalesce(v_profile_confirmed, '{}'::jsonb);

      -- Cada dato tiene que calzar con la bici real, mirada con la ficha ya
      -- tomada: lo que su relación pide (un rotor, freno de disco), y lo que
      -- la bici ya es (un neumático, su BSD; un cassette, su driver; una maza,
      -- la rueda que queda). Lo que no calza o espera una decisión se informa
      -- y no se escribe; lo demás va en un solo recibo.
      v_write := '[]'::jsonb;
      for v_fact in select value from jsonb_array_elements(v_facts)
      loop
        v_key := v_fact->>'key';
        v_value := v_fact->'value';
        v_link := null;
        if v_fact->>'link_id' is not null then
          select * into v_link
            from public.bike_fact_spec_links l
           where l.id = (v_fact->>'link_id')::uuid;
        end if;
        v_current := v_profile_values->v_key;
        v_misfit := public.bike_fact_part_misfit_internal(
          v_key, v_profile_values, v_profile_confirmed);
        v_requires := case
          when v_misfit is not null then jsonb_build_object(
            'requires_key', v_link.requires_fact_key,
            'requires_value', v_misfit)
          else public.bike_fact_part_conflict_internal(
            p_tenant_id, v_item.id, v_bike_id, v_key, v_value,
            v_profile_values, v_profile_sources, v_wheel_size)
        end;
        -- Calza con lo que la ficha ya dice y es otro código: no es un
        -- problema, y el parche no cambia la ficha (20260928120000).
        if v_requires->>'reason' = 'fits' then
          v_requires := null;
        end if;
        if v_requires->>'reason' = 'pending' then
          -- No calza con la ficha, pero el mismo trabajo cambia la pieza que
          -- lo decide: la maza nueva dice el driver, el mando nuevo la
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
          v_problems := v_problems || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
            'item_id', v_item.id,
            'item_name', v_item.product_name,
            'bike_id', v_bike_id,
            'key', v_key,
            'value', v_value,
            'reason', 'incompatible',
            'requires_key', v_requires->>'requires_key',
            'requires_value', v_requires->>'requires_value',
            'requires_source', v_requires->>'source'
          )));
          perform public.record_installed_bike_fact_notice(
            p_tenant_id, v_bike_id, p_job_id,
            'incompatible:' || v_item.id::text || ':' || v_key || '='
              || (v_value #>> '{}') || ':' || (v_requires->>'requires_value'),
            'installed_fact_incompatible',
            'Aviso: lo instalado no calza con la ficha',
            format(
              '«%s» dice %s, pero %s dice %s: la ficha no cambió. %s',
              coalesce(v_item.product_name, 'Una línea'),
              public.installed_bike_fact_label(v_key, v_value),
              case v_requires->>'source'
                when 'job_hub' then 'la maza que instala el trabajo'
                when 'job_build' then 'la rueda que arma el trabajo'
                when 'job_rim' then 'la llanta que instala el trabajo'
                else 'la ficha de la bici'
              end,
              public.bike_fact_requirement_text(
                v_requires->>'requires_key', v_requires->>'requires_value'),
              public.bike_fact_requirement_advice(v_requires->>'requires_key')),
            jsonb_strip_nulls(jsonb_build_object(
              'item_id', v_item.id,
              'key', v_key,
              'value', v_value,
              'requires_key', v_requires->>'requires_key',
              'requires_value', v_requires->>'requires_value',
              'requires_source', v_requires->>'source')),
            p_notices_required);
          continue;
        end if;
        v_write := v_write || jsonb_build_array(jsonb_build_object(
          'key', v_key,
          'op', v_fact->>'op',
          'value', v_value,
          'expected', coalesce(v_current, 'null'::jsonb),
          'expected_confirmed', coalesce(v_profile_confirmed->>v_key, 'false') = 'true'
        ));
      end loop;
      v_evaluated := true;
    exception
      when others then
        -- No se pudo tomar la bici ni mirar la ficha: se reintenta con la
        -- misma llave, y mientras tanto la bici lo dice en su historia.
        for v_fact in select value from jsonb_array_elements(v_facts)
        loop
          v_problems := v_problems || jsonb_build_array(jsonb_build_object(
            'item_id', v_item.id,
            'item_name', v_item.product_name,
            'bike_id', v_bike_id,
            'key', v_fact->>'key',
            'value', v_fact->'value',
            'reason', 'rejected',
            'code', sqlstate,
            'message', sqlerrm
          ));
        end loop;
        perform public.record_installed_bike_fact_notice(
          p_tenant_id, v_bike_id, p_job_id,
          'pending:' || v_operation_key,
          'installed_fact_pending',
          'Pendiente: la ficha no tomó lo instalado',
          format(
            'La ficha no tomó %s de «%s» (%s). Se reintenta al guardar el '
            'trabajo o volver a cambiar su estado.',
            (select string_agg(public.installed_bike_fact_label(f->>'key', f->'value'), ', '
                               order by f->>'key')
               from jsonb_array_elements(v_facts) f),
            coalesce(v_item.product_name, 'una línea'),
            sqlerrm),
          -- Con un dato, como antes: su clave y su valor; con varios, la lista.
          jsonb_strip_nulls(jsonb_build_object(
            'operation_key', v_operation_key,
            'item_id', v_item.id,
            'key', case when jsonb_array_length(v_facts) = 1 then v_facts->0->>'key' end,
            'value', case when jsonb_array_length(v_facts) = 1 then v_facts->0->'value' end,
            'facts', case when jsonb_array_length(v_facts) > 1 then v_facts end,
            'code', sqlstate)),
          p_notices_required);
    end;
    if not v_evaluated or jsonb_array_length(v_write) = 0 then
      continue;
    end if;

    -- Si algún dato no entró, el recibo lleva sólo lo que se escribe; si ya
    -- se escribió eso mismo en esta bici, no se repite.
    select string_agg((f->>'key') || '=' || (f->'value' #>> '{}'), ','
                      order by f->>'key')
      into v_write_suffix
      from jsonb_array_elements(v_write) f;
    if v_write_suffix is distinct from v_facts_suffix then
      if v_latest_suffix is not distinct from v_write_suffix
         and v_latest_bike_id is not distinct from v_bike_id then
        continue;
      end if;
      v_operation_key := 'job_completion:' || v_item.id::text || ':'
        || (coalesce(v_latest, 0) + 1)::text || ':' || v_write_suffix;
    end if;

    begin
      v_receipt := public.patch_bike_technical_facts_v1(
        v_operation_key,
        v_bike_id,
        p_job_id,
        'job_completion',
        v_write
      );
      for v_fact in select value from jsonb_array_elements(v_write)
      loop
        v_applied := v_applied || jsonb_build_array(jsonb_build_object(
          'item_id', v_item.id,
          'item_name', v_item.product_name,
          'bike_id', v_bike_id,
          'key', v_fact->>'key',
          'value', v_fact->'value',
          'op', v_fact->>'op',
          'previous', v_fact->'expected',
          'operation_key', v_operation_key,
          'changed', exists (
            select 1
              from jsonb_array_elements(coalesce(v_receipt->'applied', '[]'::jsonb)) a
             where a->>'key' = v_fact->>'key')
        ));
      end loop;
    exception
      when others then
        for v_fact in select value from jsonb_array_elements(v_write)
        loop
          v_problems := v_problems || jsonb_build_array(jsonb_build_object(
            'item_id', v_item.id,
            'item_name', v_item.product_name,
            'bike_id', v_bike_id,
            'key', v_fact->>'key',
            'value', v_fact->'value',
            'reason', 'rejected',
            'code', sqlstate,
            'message', sqlerrm
          ));
        end loop;
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
            (select string_agg(public.installed_bike_fact_label(f->>'key', f->'value'), ', '
                               order by f->>'key')
               from jsonb_array_elements(v_write) f),
            coalesce(v_item.product_name, 'una línea'),
            sqlerrm),
          -- Con un dato, como antes: su clave y su valor; con varios, la lista.
          jsonb_strip_nulls(jsonb_build_object(
            'operation_key', v_operation_key,
            'item_id', v_item.id,
            'key', case when jsonb_array_length(v_write) = 1 then v_write->0->>'key' end,
            'value', case when jsonb_array_length(v_write) = 1 then v_write->0->'value' end,
            'facts', case when jsonb_array_length(v_write) > 1 then v_write end,
            'code', sqlstate)),
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

revoke all on function public.apply_job_installed_bike_facts_internal(uuid, uuid, boolean)
  from public, anon, authenticated, service_role;

-- ============================================================================
-- La puerta del trabajo terminado: también la otra línea
-- ============================================================================

-- La de 20260928100000 con dos cambios: dice con qué no calza (la ficha, o la
-- maza, la llanta o la rueda que instala el mismo trabajo), y una maza, una
-- llanta o un Enrayado que cambia en un trabajo terminado no puede dejar mal
-- otra línea de esa rueda (un cassette HG ya aplicado y una maza de rueda
-- libre agregada después). Guardar las líneas no reescribe las que no
-- cambiaron (20260928080000): esto sólo mira la línea que cambió.
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
  v_kind text;
  v_wheel text;
  v_bike_id uuid;
  v_sibling jsonb;
  v_evidence_only boolean := false;
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
    -- Una maza o una llanta sin marca no cambia la ficha, pero las otras
    -- líneas de su rueda se miden con ella: en un trabajo terminado también
    -- pasa por la revisión de la otra línea (revisión de Codex, 2026-09-28).
    if tg_op = 'DELETE'
       or new.product_id is null
       or coalesce(public.product_bike_fact_spec_internal(
            new.tenant_id, new.product_id, '_family')->>'template_key', '')
          not in ('hub', 'rim') then
      return null;
    end if;
    v_evidence_only := true;
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
  if not v_evidence_only then
    v_result := public.apply_job_installed_bike_facts_internal(
      v_line.tenant_id,
      v_line.job_id,
      true
    );

    if not v_installs then
      -- Se le quitó la marca: no instala, pero si es una maza o una llanta
      -- las otras líneas de su rueda se siguen midiendo con ella (revisión de
      -- Codex, 2026-09-28).
      if tg_op = 'DELETE'
         or new.product_id is null
         or coalesce(public.product_bike_fact_spec_internal(
              new.tenant_id, new.product_id, '_family')->>'template_key', '')
            not in ('hub', 'rim') then
        return null;
      end if;
      v_evidence_only := true;
    end if;
  end if;

  if not v_evidence_only then
    -- Lo que esta línea instala tiene que quedar en la ficha con ella.
    select problem
      into v_problem
      from jsonb_array_elements(coalesce(v_result->'problems', '[]'::jsonb)) problem
     where problem->>'item_id' = v_line.id::text
       and problem->>'reason' in (
         'rejected', 'out_of_range', 'no_wheel', 'invalid_value',
         'line_without_bike', 'incompatible', 'stale_change', 'mixed_change',
         'conflicting_build'
       )
     limit 1;
  end if;
  if v_problem is null then
    -- Una maza, una llanta o un Enrayado que cambia en un trabajo terminado
    -- tampoco puede dejar mal otra línea del mismo trabajo y de la misma rueda
    -- que se mide con ella (20260928130000): el cassette o el piñón con el
    -- driver de la maza, el rotor con su anclaje, la maza con los rayos de la
    -- rueda. Esa otra línea ya tiene su recibo y no se vuelve a mirar sola.
    v_kind := case
      when v_line.service_configuration_data ? 'hole_count' then 'job_build'
      when v_line.product_id is not null then
        case public.product_bike_fact_spec_internal(
               v_line.tenant_id, v_line.product_id, '_family')->>'template_key'
          when 'hub' then 'job_hub'
          when 'rim' then 'job_rim'
        end
    end;
    if v_kind is null then
      return null;
    end if;
    v_wheel := case
      when v_kind = 'job_build' then coalesce(
        nullif(v_line.location_key, 'none'),
        v_line.service_configuration_data->>'which_wheel')
      when v_line.location_key in ('front', 'rear') then v_line.location_key
      when v_kind = 'job_hub' then
        case public.product_bike_fact_spec_internal(
               v_line.tenant_id, v_line.product_id, 'hub_package_position')->>'value'
          when 'Delantera' then 'front'
          when 'Trasera' then 'rear'
          when 'Juego (delantera y trasera)' then 'both'
        end
    end;
    v_bike_id := public.job_line_bike_internal(v_line.tenant_id, v_line.id);
    if v_wheel is null or v_bike_id is null then
      return null;
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
     where s.job_id = v_line.job_id
       and s.tenant_id = v_line.tenant_id
       and s.id <> v_line.id
       and marked.part is not null
       and v_wheel in (marked.part->>'position', 'both')
       and public.job_line_bike_internal(s.tenant_id, s.id) = v_bike_id
       and conflict.c->>'reason' = 'incompatible'
       and conflict.c->>'source' = v_kind
     order by s.created_at, s.id, m->>'key'
     limit 1;
    if v_sibling is null then
      return null;
    end if;
    raise exception '%', format(
        '«%s» no se guardó: «%s», del mismo trabajo, no calza con %s (%s). '
        'En un trabajo terminado las líneas y la ficha se guardan juntas: '
        'corrige una de las dos líneas.',
        coalesce(nullif(btrim(v_line.product_name), ''), 'La línea'),
        coalesce(nullif(btrim(v_sibling->>'item_name'), ''), 'otra línea'),
        case v_kind
          when 'job_hub' then 'esta maza'
          when 'job_rim' then 'esta llanta'
          else 'la rueda que arma esta línea'
        end,
        public.bike_fact_requirement_text(
          v_sibling->>'requires_key', v_sibling->>'requires_value'))
      using errcode = '23514',
            detail = (v_sibling || jsonb_build_object(
              'reason', 'sibling_incompatible', 'source', v_kind))::text;
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
        '«%s» no se guardó: %s no calza con %s (%s). En un trabajo terminado '
        'la línea y la ficha se guardan juntas: corrige la ficha o la línea.',
        v_line_name, v_fact,
        -- Con qué no calza: la ficha, o lo que instala el mismo trabajo.
        case v_problem->>'requires_source'
          when 'job_hub' then 'la maza que instala el trabajo'
          when 'job_build' then 'la rueda que arma el trabajo'
          when 'job_rim' then 'la llanta que instala el trabajo'
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

revoke all on function public.apply_installed_bike_facts_on_job_line_change()
  from public, anon, authenticated, service_role;

-- ============================================================================
-- El parche: el anclaje del rotor, y cada marca por su clave
-- ============================================================================

-- Se inserta sobre la definición vigente (la de 20260928120000) y es
-- reejecutable: anclas exactas, cada una una sola vez.
do $do$
declare
  v_fn regprocedure :=
    'public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)'::regprocedure;
  v_def text;
  v_anchors text[] := array[
$a$        'frontBrakeFluidType', 'rearBrakeFluidType', 'frontAxleInterface',
        'rearAxleInterface'
      ) then 'string'
$a$,
$a$          else v_text ~ '^[a-z0-9_]{2,40}$'
$a$,
$a$          public.job_line_part_change_internal(v_tenant_id, v_item.id)
            @> jsonb_build_object('key', v_fact->>'key', 'value', v_fact->'value')
          and v_fact->>'op' = case
            when (public.job_line_part_change_internal(v_tenant_id, v_item.id)
                  ->> 'verified')::boolean then 'set'
$a$
  ];
  v_blocks text[] := array[
$a$        'frontBrakeFluidType', 'rearBrakeFluidType', 'frontAxleInterface',
        'rearAxleInterface',
        -- El anclaje del rotor de cada rueda lo pone su maza (20260928130000).
        'frontRotorMount', 'rearRotorMount'
      ) then 'string'
$a$,
$a$          when 'frontRotorMount' then v_text in ('six_bolt', 'centerlock')
          when 'rearRotorMount' then v_text in ('six_bolt', 'centerlock')
          else v_text ~ '^[a-z0-9_]{2,40}$'
$a$,
$a$          -- Cada marca por su clave: una línea puede instalar varios datos
          -- (una maza trasera, driver y anclaje; 20260928130000).
          public.job_line_part_change_internal(v_tenant_id, v_item.id, v_fact->>'key')
            @> jsonb_build_object('key', v_fact->>'key', 'value', v_fact->'value')
          and v_fact->>'op' = case
            when (public.job_line_part_change_internal(v_tenant_id, v_item.id, v_fact->>'key')
                  ->> 'verified')::boolean then 'set'
$a$
  ];
  v_index integer;
begin
  v_def := pg_get_functiondef(v_fn);
  if position('El anclaje del rotor de cada rueda lo pone su maza (20260928130000)' in v_def) > 0 then
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

commit;
