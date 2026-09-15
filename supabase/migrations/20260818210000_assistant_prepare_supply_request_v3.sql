-- El borrador acepta y devuelve el objetivo comercial que la IA elige.
--
-- **Segundo corte, después del validador de tarjetas a propósito.** El primero
-- (`20260818200000`) enseñó a la base a aceptar la clave; éste enseña al
-- borrador a producirla. El orden inverso es el que rompió la vía
-- conversacional cuando la fase A amplió la línea sin migrar su validador.
--
-- **`_v3` y no un parche sobre `_v2`.** `_v2` está desplegada y sirve el camino
-- vigente del gateway; cambiarla movería el contrato bajo un llamador vivo.
--
-- **Ninguna regla se reescribe.** El dominio del objetivo ya tiene un dueño
-- desplegado y probado: `normalize_commercial_target_internal_v1`, que valida
-- gama, marca visible y activa, techo de costo —con el `between` que excluye
-- `NaN` e `Infinity`— y piso de margen, y que **rechaza** `currencyCode`
-- porque la moneda es server-owned. Reimplementar esas comprobaciones acá
-- crearía una segunda verdad que envejece; se delega.
--
-- **La marca llega ya resuelta.** El runtime cambia la `brandRef` opaca del
-- modelo por la identidad real antes de llamar, igual que hace con
-- `catalogItemRef` y `categoryRef`. Acá se recibe un UUID y se comprueba que la
-- marca sea visible para el taller; el modelo nunca vio ese identificador.
--
-- **Una línea sin objetivo no inventa uno**: la clave viaja ausente, y ausente
-- no es lo mismo que un objeto vacío —que el normalizador rechazaría—.
--
-- Forward-only. `_v2` queda intacta.

begin;

create or replace function public.assistant_prepare_supply_request_v3(
  p_items jsonb,
  p_profile text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
set statement_timeout = '4500ms'
as $$
declare
  v_authority record;
  v_inventory_authority record;
  v_normalized jsonb;
  v_items jsonb;
  v_item jsonb;
  v_base jsonb := '[]'::jsonb;
  v_targets jsonb := '{}'::jsonb;
  v_target jsonb;
  v_line_ref text;
  v_index integer := 0;
begin
  select authority.tenant_id, authority.actor_user_id,
    authority.authority_role, authority.permissions, authority.capabilities,
    authority.authority_fingerprint
  into strict v_authority
  from public.assistant_require_capability_internal_v1(
    'ai.read.purchases'
  ) authority;

  select authority.tenant_id, authority.actor_user_id
  into strict v_inventory_authority
  from public.assistant_require_capability_internal_v1(
    'ai.read.operational'
  ) authority;
  if v_inventory_authority.tenant_id <> v_authority.tenant_id
     or v_inventory_authority.actor_user_id <> v_authority.actor_user_id then
    raise exception 'Assistant authority changed during supply interpretation'
      using errcode = '42501';
  end if;
  if p_profile not in ('balanced', 'profitability', 'urgent_local') then
    raise exception 'Invalid supply request profile' using errcode = '22023';
  end if;
  if jsonb_typeof(p_items) <> 'array' then
    raise exception 'Invalid supply request items' using errcode = '22023';
  end if;

  -- El objetivo se separa antes de normalizar la línea: `_v2` mantiene su
  -- contrato de claves exactas y rechazaría una desconocida.
  for v_item in select value from jsonb_array_elements(p_items) loop
    v_index := v_index + 1;
    if jsonb_typeof(v_item) <> 'object' then
      raise exception 'Invalid supply request item' using errcode = '22023';
    end if;
    v_line_ref := v_item ->> 'lineRef';
    v_base := v_base || jsonb_build_array(v_item - 'commercialTarget');
    if v_item ? 'commercialTarget'
       and jsonb_typeof(v_item -> 'commercialTarget') <> 'null' then
      if jsonb_typeof(v_item -> 'commercialTarget') <> 'object'
         or v_line_ref is null then
        raise exception 'Invalid commercial target' using errcode = '22023';
      end if;
      -- Un dueño único de las reglas, ya desplegado y probado.
      v_target := public.normalize_commercial_target_internal_v1(
        v_authority.tenant_id, '{}'::jsonb, v_item -> 'commercialTarget'
      );
      if v_target = '{}'::jsonb then
        raise exception 'Empty commercial target' using errcode = '22023';
      end if;
      v_targets := v_targets || jsonb_build_object(v_line_ref, v_target);
    end if;
  end loop;

  v_normalized := public.normalize_supply_request_items_internal_v2(
    v_authority.tenant_id, v_base
  );

  -- El objetivo se reindexa por el `lineRef` real, nunca por posición: `_v2`
  -- acepta `line-1..line-8` en cualquier orden, y colgar un objetivo de la
  -- línea equivocada es el defecto que ya se corrigió en
  -- `create_supply_need_batch_v3`.
  select jsonb_agg(
    (item.value - 'productId') || jsonb_build_object(
      'entityId', item.value -> 'productId',
      'profile', p_profile
    ) || case
      when v_targets ? (item.value ->> 'lineRef')
        then jsonb_build_object(
          'commercialTarget', v_targets -> (item.value ->> 'lineRef')
        )
      else '{}'::jsonb
    end
    order by item.ordinality
  ) into v_items
  from jsonb_array_elements(v_normalized)
    with ordinality item(value, ordinality);

  return public.assistant_tool_envelope_internal_v1(
    v_authority.tenant_id,
    coalesce(v_items, '[]'::jsonb),
    false
  );
end;
$$;

revoke all on function public.assistant_prepare_supply_request_v3(
  jsonb, text
) from public, anon, authenticated, service_role;
grant execute on function public.assistant_prepare_supply_request_v3(
  jsonb, text
) to authenticated;

comment on function public.assistant_prepare_supply_request_v3(jsonb, text) is
  'Read-only server validation for a structured supply-request draft with category provenance and an optional typed commercial target per line. Target rules are delegated to normalize_commercial_target_internal_v1, so currencyCode stays server-owned and unrepresentable; the preferred brand arrives already resolved from an opaque brandRef, indexed by the real lineRef rather than by position.';

commit;
