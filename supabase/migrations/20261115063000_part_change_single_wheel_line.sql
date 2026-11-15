-- Un repuesto de una sola rueda va en ella aunque la línea no la diga
-- ============================================================================
--
-- Un cassette, un piñón de rosca o una maza trasera sólo van atrás (dueño,
-- 2026-10-01: «acaso existe un piñón delantero»). La app ya lo trata así:
-- `partWheelPositions` no ofrece rueda que elegir y `_settleSingleWheelParts`
-- deja la línea en su rueda. El servidor, en cambio, verificaba la marca del
-- cambio de ficha sólo contra la rueda escrita en la línea
-- (`l.position = v_item.location_key`). Una línea guardada con
-- `location_key = 'none'` y su marca del driver no se podía verificar: el
-- cierre la rechazaba como `stale_change` y aconsejaba «vuelve a elegir la
-- rueda», algo que la app no ofrece porque no hay rueda que elegir.
--
-- Pasó el 2026-11-14 en un trabajo de dos bicis (una con piñón de rosca y
-- otra con cassette): el cassette CS-HG200-7 de la Trek tenía su marca
-- «Shimano HG en el driver trasero» y la línea sin rueda, y el trabajo no se
-- podía entregar. En producción había 2 líneas así, las dos de un driver.
--
-- `part_line_single_wheel_internal` dice la rueda de un producto con la misma
-- regla que `partWheelPositions` en la app: las filas de la relación que no
-- sólo se revisan, de su familia, con un valor del producto (cumpliendo la
-- condición de la fila), y en una sola rueda. Un rotor, una llanta o un
-- neumático van en las dos y siguen pidiendo la rueda.
-- `job_line_part_change_internal` la usa cuando la línea no dice rueda; todo
-- lo demás de la función queda como en producción (20260928130000, con la
-- comparación de décimas que le puso 20261002170000).

create or replace function public.part_line_single_wheel_internal(
  p_tenant_id uuid,
  p_product_id uuid
)
returns text
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare
  v_positions text[];
begin
  if p_tenant_id is null or p_product_id is null then
    return null;
  end if;
  select array_agg(distinct l.position)
    into v_positions
    from public.bike_fact_spec_links l
    cross join lateral (
      select public.product_bike_fact_spec_internal(
               p_tenant_id, p_product_id, l.spec_key) as spec
    ) s
   where l.on_mismatch <> 'check'
     and l.position in ('front', 'rear')
     and (l.template_key is null or l.template_key = s.spec->>'template_key')
     and public.bike_fact_product_condition_met_internal(
           p_tenant_id, p_product_id, l.product_condition)
     and public.bike_fact_link_value_internal(l, s.spec) is not null;
  if coalesce(array_length(v_positions, 1), 0) <> 1 then
    return null;
  end if;
  return v_positions[1];
end;
$function$;

comment on function public.part_line_single_wheel_internal(uuid, uuid) is
  'La única rueda en que va un repuesto según su ficha técnica (rear para un cassette, un piñón de rosca o una maza trasera); null si va en las dos o no le escribe nada a la ficha de la bici. La misma regla que partWheelPositions en la app.';

revoke all on function public.part_line_single_wheel_internal(uuid, uuid)
  from public, anon, authenticated, service_role;

-- La marca de una clave, si todavía calza con el repuesto, la rueda y la
-- ficha técnica del producto. La rueda es la de la línea o, si la línea no la
-- dice, la única en que va el repuesto.
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
  v_implied_wheel text;
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

  -- La fila de la rueda de la línea, como siempre (un repuesto de toda la
  -- bici, sin rueda: sus filas son de `none`). Si la línea no dice rueda,
  -- también la de la única rueda en que va el repuesto (20261115063000); un
  -- repuesto de las dos ruedas sigue pidiéndola.
  if coalesce(v_item.location_key, 'none') not in ('front', 'rear') then
    v_implied_wheel := public.part_line_single_wheel_internal(
      p_tenant_id, v_item.product_id);
  end if;

  for v_link in
    select *
      from public.bike_fact_spec_links l
     where l.bike_fact_key = p_key
       and (l.position = v_item.location_key
            or l.position = v_implied_wheel)
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
    -- Una medida: «180» o 180, y nunca 180,5 en una fila entera (la
    -- igualdad es por valor); 31.8 en una con décimas (20261002170000).
    if (v_marked #>> '{}') !~ '^[0-9]{1,4}(\.[0-9]+)?$'
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
