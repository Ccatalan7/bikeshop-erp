-- A workshop need already owns a durable job and optional job-bike link, but
-- the only edit command could not change that workshop attribution. Jobs must
-- be able to correct the destination without granting direct UPDATE access or
-- moving the generic Purchasing editor across its ownership boundary.

create or replace function public.update_workshop_supply_need_v1(
  p_need_id uuid,
  p_expected_version bigint,
  p_description text,
  p_product_id uuid,
  p_quantity numeric,
  p_unit text,
  p_job_bike_id uuid,
  p_operation_key text
)
returns jsonb
language plpgsql
security definer
set search_path = public
set lock_timeout = '750ms'
as $$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_actor_id uuid := auth.uid();
  v_operation_key text := btrim(coalesce(p_operation_key, ''));
  v_unit text := btrim(coalesce(p_unit, ''));
  v_request jsonb;
  v_response jsonb;
  v_event public.supply_need_events%rowtype;
  v_need public.supply_needs%rowtype;
  v_identity_state text;
  v_changed boolean;
  v_interpretation_changed boolean;
begin
  if v_tenant_id is null or v_actor_id is null then
    raise exception 'No hay una sesión de negocio activa.' using errcode = '42501';
  end if;
  if p_need_id is null or p_expected_version is null
     or p_description is null or btrim(p_description) = ''
     or octet_length(p_description) > 2000
     or p_quantity is null or p_quantity <= 0 or p_quantity > 999999
     or v_unit = '' or octet_length(v_unit) > 32
     or v_operation_key = '' or octet_length(v_operation_key) > 200 then
    raise exception 'Los datos de la necesidad no son válidos.'
      using errcode = '22023';
  end if;

  v_request := jsonb_build_object(
    'need_id', p_need_id,
    'expected_version', p_expected_version,
    'description', p_description,
    'product_id', p_product_id,
    'quantity', p_quantity,
    'unit', v_unit,
    'job_bike_id', p_job_bike_id
  );

  -- Serialize the replay key before inspecting its receipt. Two identical
  -- clicks must not race into a stale-version error after the first commits.
  perform pg_advisory_xact_lock(hashtextextended(
    v_tenant_id::text || ':workshop_supply_need:' || v_operation_key,
    0
  ));

  select event.* into v_event
  from public.supply_need_events event
  where event.tenant_id = v_tenant_id
    and event.operation_key = v_operation_key;
  if found then
    if v_event.action <> 'updated'
       or v_event.supply_need_id <> p_need_id
       or v_event.request_snapshot is distinct from v_request then
      raise exception 'La clave de operación ya pertenece a otro cambio.'
        using errcode = '23505';
    end if;
    return to_jsonb(v_event) || v_event.response_snapshot
      || jsonb_build_object('replay', true);
  end if;

  select need.* into v_need
  from public.supply_needs need
  where need.tenant_id = v_tenant_id and need.id = p_need_id
  for update;
  if not found or v_need.origin_kind <> 'mechanic_job' then
    raise exception 'Necesidad de taller no encontrada.' using errcode = 'P0002';
  end if;
  if v_need.version <> p_expected_version then
    raise exception 'La necesidad cambió; vuelve a cargarla antes de guardar.'
      using errcode = '40001';
  end if;
  if v_need.supply_state in ('covered', 'cancelled') then
    raise exception 'La necesidad ya está cerrada y no puede editarse.'
      using errcode = '55000';
  end if;
  if v_need.supply_state = 'committed'
     and v_need.product_id is distinct from p_product_id then
    raise exception 'Libera primero el stock asignado antes de cambiar el producto.'
      using errcode = '55000';
  end if;
  if v_need.usage_state in ('installed', 'reconciled')
     and v_need.job_bike_id is distinct from p_job_bike_id then
    raise exception 'Un repuesto ya aplicado no puede moverse a otra bicicleta.'
      using errcode = '55000';
  end if;

  if p_job_bike_id is not null and not exists (
    select 1
    from public.mechanic_job_bikes job_bike
    where job_bike.tenant_id = v_tenant_id
      and job_bike.id = p_job_bike_id
      and job_bike.job_id = v_need.mechanic_job_id
  ) then
    raise exception 'La bicicleta no pertenece a este trabajo.'
      using errcode = '23514';
  end if;

  if p_product_id is not null and not exists (
    select 1
    from public.products product
    where product.tenant_id = v_tenant_id
      and product.id = p_product_id
      and product.is_active is true
      and not coalesce(product.is_service, false)
      and coalesce(product.product_type, 'product') <> 'service'
  ) then
    raise exception 'El producto no existe, está inactivo o no es un repuesto.'
      using errcode = '23514';
  end if;

  v_identity_state := case
    when p_product_id is null then 'unresolved'
    else 'confirmed'
  end;
  v_interpretation_changed :=
    v_need.original_description is distinct from p_description
    or v_need.product_id is distinct from p_product_id
    or v_need.quantity is distinct from p_quantity
    or v_need.unit is distinct from v_unit
    or v_need.identity_state is distinct from v_identity_state;
  v_changed := v_interpretation_changed
    or v_need.job_bike_id is distinct from p_job_bike_id;

  if v_changed then
    update public.supply_needs need
    set original_description = p_description,
        product_id = p_product_id,
        quantity = p_quantity,
        unit = v_unit,
        job_bike_id = p_job_bike_id,
        identity_state = v_identity_state,
        internal_stock_rejection_reason = case
          when need.product_id is distinct from p_product_id
            or need.quantity is distinct from p_quantity
            then null
          else need.internal_stock_rejection_reason
        end,
        internal_stock_rejected_at = case
          when need.product_id is distinct from p_product_id
            or need.quantity is distinct from p_quantity
            then null
          else need.internal_stock_rejected_at
        end,
        internal_stock_rejected_by = case
          when need.product_id is distinct from p_product_id
            or need.quantity is distinct from p_quantity
            then null
          else need.internal_stock_rejected_by
        end,
        version = need.version + 1,
        updated_by = v_actor_id,
        updated_at = clock_timestamp()
    where need.tenant_id = v_tenant_id and need.id = p_need_id
    returning * into v_need;

    if v_interpretation_changed then
      insert into public.supply_need_interpretation_revisions (
        tenant_id, supply_need_id, revision_no, source, raw_description,
        identity_state, canonical_product_id, constraints, clarifications,
        evidence_snapshot, formula_version, created_by
      ) values (
        v_tenant_id, v_need.id, v_need.version, 'manual', p_description,
        v_identity_state, p_product_id, '[]'::jsonb, '[]'::jsonb,
        '{}'::jsonb, 'manual-v1', v_actor_id
      );
    end if;
  end if;

  v_response := jsonb_build_object(
    'need_id', v_need.id,
    'changed', v_changed,
    'version', v_need.version,
    'need', to_jsonb(v_need)
  );

  insert into public.supply_need_events (
    tenant_id, supply_need_id, action, changed, actor_id, operation_key,
    request_snapshot, response_snapshot, occurred_at
  ) values (
    v_tenant_id, v_need.id, 'updated', v_changed, v_actor_id,
    v_operation_key, v_request, v_response, clock_timestamp()
  ) returning * into v_event;

  return to_jsonb(v_event) || v_response
    || jsonb_build_object('replay', false);
end;
$$;

revoke all on function public.update_workshop_supply_need_v1(
  uuid, bigint, text, uuid, numeric, text, uuid, text
) from public, anon, authenticated, service_role;
grant execute on function public.update_workshop_supply_need_v1(
  uuid, bigint, text, uuid, numeric, text, uuid, text
) to authenticated;

comment on function public.update_workshop_supply_need_v1(
  uuid, bigint, text, uuid, numeric, text, uuid, text
) is
  'Versioned Jobs-origin edit for a workshop supply need, including its validated mechanic_job_bikes attribution. Generic Purchasing edits remain context-neutral.';
