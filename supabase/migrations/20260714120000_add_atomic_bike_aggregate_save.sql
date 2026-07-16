-- Deployment status: DEPLOYED to production xzdvtzdqjeyqxnkqprtf on 2026-07-15
-- Deployment verification: RPC/ACL/RLS smoke passed; browser canary persisted
-- 1 bike, 1 profile, 2 audit events and 1 receipt; migration history recorded.
-- One bicycle form submission is one durable command: identity, optional
-- profile truth, audit events, and the retry receipt commit or roll back
-- together.
begin;

create table if not exists public.bike_aggregate_save_operations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  operation_key text not null,
  payload_hash text not null,
  operation_kind text not null check (operation_kind in ('create', 'update')),
  bike_id uuid references public.bikes(id) on delete set null,
  profile_id uuid references public.bike_profiles(id) on delete set null,
  result_snapshot jsonb not null default '{}'::jsonb,
  created_by uuid references auth.users(id) on delete set null,
  completed_at timestamptz not null default clock_timestamp(),
  unique (tenant_id, operation_key)
);

comment on table public.bike_aggregate_save_operations is
  'Idempotency and forensic receipts for atomic bicycle identity/profile saves. This is command evidence, not a second bike truth store.';
comment on column public.bike_aggregate_save_operations.operation_key is
  'Stable client-generated key reused while the outcome of one save attempt is uncertain.';
comment on column public.bike_aggregate_save_operations.payload_hash is
  'Server-computed fingerprint that prevents one operation key from being reused for different bicycle content.';

create index if not exists idx_bike_aggregate_save_operations_bike
  on public.bike_aggregate_save_operations(tenant_id, bike_id, completed_at desc);

alter table public.bike_aggregate_save_operations enable row level security;

drop policy if exists bike_aggregate_save_operations_select
  on public.bike_aggregate_save_operations;
create policy bike_aggregate_save_operations_select
  on public.bike_aggregate_save_operations
  for select
  to authenticated
  using (tenant_id = public.user_tenant_id());

revoke select, insert, update, delete
  on public.bike_aggregate_save_operations
  from public, anon, authenticated;

create or replace function public.get_bike_aggregate(p_bike_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
  v_tenant_id uuid;
  v_active_profile_count integer;
  v_bike public.bikes%rowtype;
  v_profile public.bike_profiles%rowtype;
begin
  select count(*)::integer
    into v_active_profile_count
    from public.user_profiles
   where user_id = v_actor_id
     and is_active is true;

  if v_actor_id is null or v_active_profile_count <> 1 then
    raise exception 'Exactly one active employee tenant is required'
      using errcode = 'insufficient_privilege';
  end if;

  select tenant_id
    into v_tenant_id
    from public.user_profiles
   where user_id = v_actor_id
     and is_active is true;

  select *
    into v_bike
    from public.bikes
   where id = p_bike_id
     and tenant_id = v_tenant_id;

  if not found then
    raise exception 'Bicycle not found for current tenant'
      using errcode = 'no_data_found';
  end if;

  select *
    into v_profile
    from public.bike_profiles
   where bike_id = v_bike.id
     and tenant_id = v_tenant_id;

  return jsonb_build_object(
    'bike', to_jsonb(v_bike),
    'profile', case when v_profile.id is null then null else to_jsonb(v_profile) end
  );
end;
$$;

create or replace function public.get_bike_aggregate_save_operation(
  p_operation_key text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
  v_tenant_id uuid;
  v_active_profile_count integer;
  v_operation public.bike_aggregate_save_operations%rowtype;
begin
  select count(*)::integer
    into v_active_profile_count
    from public.user_profiles
   where user_id = v_actor_id
     and is_active is true;

  if v_actor_id is null or v_active_profile_count <> 1 then
    raise exception 'Exactly one active employee tenant is required'
      using errcode = 'insufficient_privilege';
  end if;

  select tenant_id
    into v_tenant_id
    from public.user_profiles
   where user_id = v_actor_id
     and is_active is true;

  select *
    into v_operation
    from public.bike_aggregate_save_operations
   where tenant_id = v_tenant_id
     and operation_key = nullif(btrim(p_operation_key), '');

  if not found then
    return null;
  end if;

  -- A retry receipt is evidence of the command that committed. Returning the
  -- mutable current aggregate here would let a lost-response retry appear to
  -- have committed changes made by a later, unrelated operation.
  return v_operation.result_snapshot || jsonb_build_object('replayed', true);
end;
$$;

create or replace function public.save_bike_aggregate(
  p_operation_key text,
  p_bike_id uuid,
  p_customer_id uuid,
  p_expected_bike_updated_at timestamptz,
  p_expected_profile_updated_at timestamptz,
  p_bike_payload jsonb,
  p_profile_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
  v_tenant_id uuid;
  v_active_profile_count integer;
  v_operation_key text := nullif(btrim(p_operation_key), '');
  v_operation_id uuid := gen_random_uuid();
  v_payload_hash text;
  v_operation public.bike_aggregate_save_operations%rowtype;
  v_existing_bike public.bikes%rowtype;
  v_saved_bike public.bikes%rowtype;
  v_existing_profile public.bike_profiles%rowtype;
  v_saved_profile public.bike_profiles%rowtype;
  v_bike_exists boolean := false;
  v_profile_exists boolean := false;
  v_operation_kind text;
  v_result jsonb;
  v_brand_id uuid;
  v_model_id uuid;
  v_effective_brand_id uuid;
  v_effective_model_id uuid;
  v_factory_rim_id uuid;
  v_catalog_bike_id uuid;
  v_profile_id uuid;
  v_image_urls text[];
begin
  select count(*)::integer
    into v_active_profile_count
    from public.user_profiles
   where user_id = v_actor_id
     and is_active is true;

  if v_actor_id is null or v_active_profile_count <> 1 then
    raise exception 'Exactly one active employee tenant is required'
      using errcode = 'insufficient_privilege';
  end if;

  select tenant_id
    into v_tenant_id
    from public.user_profiles
   where user_id = v_actor_id
     and is_active is true;

  if v_operation_key is null or length(v_operation_key) > 128 then
    raise exception 'A valid bicycle save operation key is required';
  end if;

  if p_bike_id is null or p_customer_id is null then
    raise exception 'Bicycle id and customer id are required';
  end if;

  if p_bike_payload is null or jsonb_typeof(p_bike_payload) <> 'object' then
    raise exception 'Bicycle payload must be an object';
  end if;

  if p_profile_payload is not null
     and jsonb_typeof(p_profile_payload) <> 'object' then
    raise exception 'Bicycle profile payload must be an object or null';
  end if;

  if octet_length(p_bike_payload::text) > 65536 then
    raise exception 'Bicycle payload exceeds the 64 KiB command limit';
  end if;

  if p_profile_payload is not null
     and octet_length(p_profile_payload::text) > 262144 then
    raise exception 'Bicycle profile payload exceeds the 256 KiB command limit';
  end if;

  if exists (
    select 1
      from jsonb_object_keys(p_bike_payload) as key_name
     where key_name <> all (array[
       'brand_id', 'model_id', 'brand', 'model', 'year', 'serial_number',
       'color', 'frame_size', 'wheel_size', 'bike_type',
       'front_hub_spacing_mm', 'rear_hub_spacing_mm', 'spoke_count',
       'factory_rim_id', 'purchase_date', 'purchase_price',
       'warranty_until', 'qr_code', 'notes', 'image_url', 'image_urls',
       'is_active'
     ]::text[])
  ) then
    raise exception 'Bicycle payload contains unsupported or server-owned fields';
  end if;

  if p_profile_payload is not null and exists (
    select 1
      from jsonb_object_keys(p_profile_payload) as key_name
     where key_name <> all (array[
       'id', 'catalog_bike_id', 'intake_profile', 'technical_profile',
       'summary_snapshot', 'last_confirmed_at'
     ]::text[])
  ) then
    raise exception 'Bicycle profile payload contains unsupported or server-owned fields';
  end if;

  if p_profile_payload is not null and (
    (p_profile_payload ? 'intake_profile'
      and jsonb_typeof(p_profile_payload->'intake_profile') is distinct from 'object')
    or (p_profile_payload ? 'technical_profile'
      and jsonb_typeof(p_profile_payload->'technical_profile') is distinct from 'object')
    or (p_profile_payload ? 'summary_snapshot'
      and jsonb_typeof(p_profile_payload->'summary_snapshot') is distinct from 'object')
  ) then
    raise exception 'Bicycle profile maps must be JSON objects';
  end if;

  if p_profile_payload is not null
     and p_profile_payload ? 'technical_profile'
     and (
       (p_profile_payload->'technical_profile' ? 'values'
         and jsonb_typeof(p_profile_payload->'technical_profile'->'values')
           is distinct from 'object')
       or (p_profile_payload->'technical_profile' ? 'sources'
         and jsonb_typeof(p_profile_payload->'technical_profile'->'sources')
           is distinct from 'object')
       or (p_profile_payload->'technical_profile' ? 'confirmed'
         and jsonb_typeof(p_profile_payload->'technical_profile'->'confirmed')
           is distinct from 'object')
     ) then
    raise exception 'Bicycle technical profile values, sources and confirmed maps must be JSON objects';
  end if;

  if p_bike_payload ? 'image_urls'
     and p_bike_payload->'image_urls' <> 'null'::jsonb
     and jsonb_typeof(p_bike_payload->'image_urls') <> 'array' then
    raise exception 'Bicycle image_urls must be an array or null';
  end if;

  v_payload_hash := encode(extensions.digest(jsonb_build_object(
    'bike_id', p_bike_id,
    'customer_id', p_customer_id,
    'expected_bike_updated_at', p_expected_bike_updated_at,
    'expected_profile_updated_at', p_expected_profile_updated_at,
    'bike', p_bike_payload,
    'profile', p_profile_payload
  )::text, 'sha256'), 'hex');

  perform pg_advisory_xact_lock(
    hashtextextended(v_tenant_id::text || ':bike_aggregate:' || v_operation_key, 0)
  );

  select *
    into v_operation
    from public.bike_aggregate_save_operations
   where tenant_id = v_tenant_id
     and operation_key = v_operation_key;

  if found then
    if v_operation.payload_hash is distinct from v_payload_hash then
      raise exception 'Bicycle save key was already used with different content'
        using errcode = 'integrity_constraint_violation';
    end if;

    return v_operation.result_snapshot || jsonb_build_object('replayed', true);
  end if;

  if not exists (
    select 1
      from public.customers
     where id = p_customer_id
       and tenant_id = v_tenant_id
  ) then
    raise exception 'Bicycle customer not found for current tenant'
      using errcode = 'insufficient_privilege';
  end if;

  v_brand_id := nullif(p_bike_payload->>'brand_id', '')::uuid;
  v_model_id := nullif(p_bike_payload->>'model_id', '')::uuid;
  v_factory_rim_id := nullif(p_bike_payload->>'factory_rim_id', '')::uuid;

  if v_brand_id is not null and not exists (
    select 1 from public.bike_brands
     where id = v_brand_id and tenant_id = v_tenant_id
  ) then
    raise exception 'Bicycle brand not found for current tenant'
      using errcode = 'insufficient_privilege';
  end if;

  if v_factory_rim_id is not null and not exists (
    select 1 from public.wheel_rims
     where id = v_factory_rim_id and tenant_id = v_tenant_id
  ) then
    raise exception 'Bicycle factory rim not found for current tenant'
      using errcode = 'insufficient_privilege';
  end if;

  select *
    into v_existing_bike
    from public.bikes
   where id = p_bike_id
     and tenant_id = v_tenant_id
   for update;
  v_bike_exists := found;

  if not v_bike_exists and exists (
    select 1 from public.bikes where id = p_bike_id
  ) then
    raise exception 'Bicycle not found for current tenant'
      using errcode = 'insufficient_privilege';
  end if;

  if v_bike_exists
     and v_existing_bike.customer_id is distinct from p_customer_id then
    raise exception 'Bicycle customer cannot be reassigned through the aggregate save command'
      using errcode = 'integrity_constraint_violation';
  end if;

  v_effective_brand_id := case
    when p_bike_payload ? 'brand_id' then v_brand_id
    else v_existing_bike.brand_id
  end;
  v_effective_model_id := case
    when p_bike_payload ? 'model_id' then v_model_id
    else v_existing_bike.model_id
  end;

  if v_effective_model_id is not null and (
    v_effective_brand_id is null or not exists (
      select 1
        from public.bike_models
       where id = v_effective_model_id
         and tenant_id = v_tenant_id
         and brand_id = v_effective_brand_id
    )
  ) then
    raise exception 'Bicycle model not found for current tenant or effective brand'
      using errcode = 'integrity_constraint_violation';
  end if;

  if v_bike_exists then
    if p_expected_bike_updated_at is null
       or v_existing_bike.updated_at is distinct from p_expected_bike_updated_at then
      raise exception 'Bicycle changed since it was loaded; reload before saving'
        using errcode = 'serialization_failure';
    end if;

    update public.bikes
       set customer_id = p_customer_id,
           brand_id = case when p_bike_payload ? 'brand_id' then v_brand_id else brand_id end,
           model_id = case when p_bike_payload ? 'model_id' then v_model_id else model_id end,
           brand = case when p_bike_payload ? 'brand' then p_bike_payload->>'brand' else brand end,
           model = case when p_bike_payload ? 'model' then p_bike_payload->>'model' else model end,
           year = case when p_bike_payload ? 'year' then nullif(p_bike_payload->>'year', '')::integer else year end,
           serial_number = case when p_bike_payload ? 'serial_number' then nullif(btrim(p_bike_payload->>'serial_number'), '') else serial_number end,
           color = case when p_bike_payload ? 'color' then nullif(btrim(p_bike_payload->>'color'), '') else color end,
           frame_size = case when p_bike_payload ? 'frame_size' then nullif(btrim(p_bike_payload->>'frame_size'), '') else frame_size end,
           wheel_size = case when p_bike_payload ? 'wheel_size' then nullif(btrim(p_bike_payload->>'wheel_size'), '') else wheel_size end,
           bike_type = case when p_bike_payload ? 'bike_type' then nullif(p_bike_payload->>'bike_type', '') else bike_type end,
           front_hub_spacing_mm = case when p_bike_payload ? 'front_hub_spacing_mm' then nullif(p_bike_payload->>'front_hub_spacing_mm', '')::numeric else front_hub_spacing_mm end,
           rear_hub_spacing_mm = case when p_bike_payload ? 'rear_hub_spacing_mm' then nullif(p_bike_payload->>'rear_hub_spacing_mm', '')::numeric else rear_hub_spacing_mm end,
           spoke_count = case when p_bike_payload ? 'spoke_count' then nullif(p_bike_payload->>'spoke_count', '')::integer else spoke_count end,
           factory_rim_id = case when p_bike_payload ? 'factory_rim_id' then v_factory_rim_id else factory_rim_id end,
           purchase_date = case when p_bike_payload ? 'purchase_date' then nullif(p_bike_payload->>'purchase_date', '')::date else purchase_date end,
           purchase_price = case when p_bike_payload ? 'purchase_price' then nullif(p_bike_payload->>'purchase_price', '')::numeric else purchase_price end,
           warranty_until = case when p_bike_payload ? 'warranty_until' then nullif(p_bike_payload->>'warranty_until', '')::date else warranty_until end,
           qr_code = case when p_bike_payload ? 'qr_code' then nullif(btrim(p_bike_payload->>'qr_code'), '') else qr_code end,
           notes = case when p_bike_payload ? 'notes' then nullif(btrim(p_bike_payload->>'notes'), '') else notes end,
           image_url = case when p_bike_payload ? 'image_url' then nullif(btrim(p_bike_payload->>'image_url'), '') else image_url end,
           image_urls = case
             when p_bike_payload->'image_urls' = 'null'::jsonb then array[]::text[]
             when p_bike_payload ? 'image_urls' then coalesce(
               array(select jsonb_array_elements_text(p_bike_payload->'image_urls')),
               array[]::text[]
             )
             else image_urls
           end,
           is_active = case when p_bike_payload ? 'is_active' then coalesce((p_bike_payload->>'is_active')::boolean, true) else is_active end
     where id = p_bike_id
       and tenant_id = v_tenant_id
     returning * into v_saved_bike;
    v_operation_kind := 'update';
  else
    if p_expected_bike_updated_at is not null then
      raise exception 'Bicycle no longer exists; reload before saving'
        using errcode = 'serialization_failure';
    end if;

    if p_bike_payload->'image_urls' = 'null'::jsonb then
      v_image_urls := array[]::text[];
    elsif p_bike_payload ? 'image_urls' then
      select coalesce(array_agg(value), array[]::text[])
        into v_image_urls
        from jsonb_array_elements_text(p_bike_payload->'image_urls') as value;
    else
      v_image_urls := array[]::text[];
    end if;

    insert into public.bikes (
      id, tenant_id, customer_id, brand_id, model_id, brand, model, year,
      serial_number, color, frame_size, wheel_size, bike_type,
      front_hub_spacing_mm, rear_hub_spacing_mm, spoke_count, factory_rim_id,
      purchase_date, purchase_price, warranty_until, qr_code, notes,
      image_url, image_urls, is_active
    ) values (
      p_bike_id,
      v_tenant_id,
      p_customer_id,
      v_brand_id,
      v_model_id,
      p_bike_payload->>'brand',
      p_bike_payload->>'model',
      nullif(p_bike_payload->>'year', '')::integer,
      nullif(btrim(p_bike_payload->>'serial_number'), ''),
      nullif(btrim(p_bike_payload->>'color'), ''),
      nullif(btrim(p_bike_payload->>'frame_size'), ''),
      nullif(btrim(p_bike_payload->>'wheel_size'), ''),
      nullif(p_bike_payload->>'bike_type', ''),
      nullif(p_bike_payload->>'front_hub_spacing_mm', '')::numeric,
      nullif(p_bike_payload->>'rear_hub_spacing_mm', '')::numeric,
      nullif(p_bike_payload->>'spoke_count', '')::integer,
      v_factory_rim_id,
      nullif(p_bike_payload->>'purchase_date', '')::date,
      nullif(p_bike_payload->>'purchase_price', '')::numeric,
      nullif(p_bike_payload->>'warranty_until', '')::date,
      nullif(btrim(p_bike_payload->>'qr_code'), ''),
      nullif(btrim(p_bike_payload->>'notes'), ''),
      nullif(btrim(p_bike_payload->>'image_url'), ''),
      v_image_urls,
      coalesce((p_bike_payload->>'is_active')::boolean, true)
    )
    returning * into v_saved_bike;
    v_operation_kind := 'create';
  end if;

  select *
    into v_existing_profile
    from public.bike_profiles
   where bike_id = v_saved_bike.id
     and tenant_id = v_tenant_id
   for update;
  v_profile_exists := found;

  if not v_profile_exists and exists (
    select 1
      from public.bike_profiles
     where bike_id = v_saved_bike.id
  ) then
    raise exception 'Bicycle profile not found for current tenant'
      using errcode = 'insufficient_privilege';
  end if;

  if p_profile_payload is null then
    v_saved_profile := v_existing_profile;
  else
    v_catalog_bike_id := nullif(p_profile_payload->>'catalog_bike_id', '')::uuid;
    v_profile_id := nullif(p_profile_payload->>'id', '')::uuid;

    if v_catalog_bike_id is not null and not exists (
      select 1 from public.bike_catalog where id = v_catalog_bike_id
    ) then
      raise exception 'Catalog bicycle not found';
    end if;

    if v_profile_exists then
      if p_expected_profile_updated_at is null
         or v_existing_profile.updated_at is distinct from p_expected_profile_updated_at then
        raise exception 'Bicycle profile changed since it was loaded; reload before saving'
          using errcode = 'serialization_failure';
      end if;

      if v_profile_id is not null and v_profile_id is distinct from v_existing_profile.id then
        raise exception 'Bicycle profile identity does not match the loaded profile'
          using errcode = 'integrity_constraint_violation';
      end if;

      update public.bike_profiles
         set catalog_bike_id = case
               when p_profile_payload ? 'catalog_bike_id' then v_catalog_bike_id
               else catalog_bike_id
             end,
             intake_profile = case
               when p_profile_payload ? 'intake_profile' then p_profile_payload->'intake_profile'
               else intake_profile
             end,
             technical_profile = case
               when p_profile_payload ? 'technical_profile' then p_profile_payload->'technical_profile'
               else technical_profile
             end,
             summary_snapshot = case
               when p_profile_payload ? 'summary_snapshot' then p_profile_payload->'summary_snapshot'
               else summary_snapshot
             end,
             last_confirmed_at = case
               when p_profile_payload ? 'last_confirmed_at'
                 then nullif(p_profile_payload->>'last_confirmed_at', '')::timestamptz
               else last_confirmed_at
             end
       where id = v_existing_profile.id
         and tenant_id = v_tenant_id
       returning * into v_saved_profile;
    else
      if p_expected_profile_updated_at is not null then
        raise exception 'Bicycle profile no longer exists; reload before saving'
          using errcode = 'serialization_failure';
      end if;

      insert into public.bike_profiles (
        id, tenant_id, bike_id, catalog_bike_id, intake_profile,
        technical_profile, summary_snapshot, last_confirmed_at
      ) values (
        coalesce(v_profile_id, gen_random_uuid()),
        v_tenant_id,
        v_saved_bike.id,
        v_catalog_bike_id,
        coalesce(p_profile_payload->'intake_profile', '{}'::jsonb),
        coalesce(p_profile_payload->'technical_profile', '{}'::jsonb),
        coalesce(p_profile_payload->'summary_snapshot', '{}'::jsonb),
        nullif(p_profile_payload->>'last_confirmed_at', '')::timestamptz
      )
      returning * into v_saved_profile;
    end if;
  end if;

  if not v_bike_exists then
    insert into public.bike_events (
      tenant_id, bike_id, event_type, event_category, event_date, title,
      summary, source, payload, created_by
    ) values (
      v_tenant_id,
      v_saved_bike.id,
      'bike_registered',
      'state',
      v_saved_bike.created_at,
      'Bicicleta registrada',
      concat_ws(' ', nullif(v_saved_bike.brand, ''), nullif(v_saved_bike.model, ''), v_saved_bike.year::text),
      'atomic_bike_save',
      jsonb_build_object(
        'operation_id', v_operation_id,
        'operation_key', v_operation_key
      ),
      v_actor_id
    );
  end if;

  if p_profile_payload is not null then
    insert into public.bike_events (
      tenant_id, bike_id, event_type, event_category, event_date, title,
      summary, source, payload, created_by
    ) values (
      v_tenant_id,
      v_saved_bike.id,
      case when v_profile_exists then 'profile_updated' else 'profile_created' end,
      'state',
      v_saved_profile.updated_at,
      case when v_profile_exists then 'Ficha actualizada' else 'Ficha creada' end,
      case
        when v_profile_exists then 'Se actualizó la ficha de la bicicleta.'
        else 'Se creó la ficha de la bicicleta.'
      end,
      'atomic_bike_save',
      jsonb_build_object(
        'operation_id', v_operation_id,
        'operation_key', v_operation_key,
        'technical_keys', coalesce((
          select jsonb_agg(key_name order by key_name)
            from jsonb_object_keys(
              coalesce(v_saved_profile.technical_profile->'values', '{}'::jsonb)
            ) as key_name
        ), '[]'::jsonb)
      ),
      v_actor_id
    );
  end if;

  v_result := jsonb_build_object(
    'operation_id', v_operation_id,
    'bike', to_jsonb(v_saved_bike),
    'profile', case
      when v_saved_profile.id is null then null
      else to_jsonb(v_saved_profile)
    end,
    'replayed', false
  );

  insert into public.bike_aggregate_save_operations (
    id, tenant_id, operation_key, payload_hash, operation_kind, bike_id,
    profile_id, result_snapshot, created_by
  ) values (
    v_operation_id,
    v_tenant_id,
    v_operation_key,
    v_payload_hash,
    v_operation_kind,
    v_saved_bike.id,
    v_saved_profile.id,
    v_result,
    v_actor_id
  );

  return v_result;
end;
$$;

revoke all on function public.get_bike_aggregate(uuid)
  from public, anon, service_role;
revoke all on function public.get_bike_aggregate_save_operation(text)
  from public, anon, service_role;
revoke all on function public.save_bike_aggregate(
  text, uuid, uuid, timestamptz, timestamptz, jsonb, jsonb
) from public, anon, service_role;

grant execute on function public.get_bike_aggregate(uuid)
  to authenticated;
grant execute on function public.get_bike_aggregate_save_operation(text)
  to authenticated;
grant execute on function public.save_bike_aggregate(
  text, uuid, uuid, timestamptz, timestamptz, jsonb, jsonb
) to authenticated;

commit;
