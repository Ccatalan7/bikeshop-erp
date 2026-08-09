-- Preserve legacy supplier portal usernames that do not yet have a password.
--
-- Forward behavior:
--   * permits a Vault-less metadata row only for portal_password/default when
--     it has a non-empty username;
--   * copies username-only legacy rows without inventing a secret or leaking a
--     non-canonical website into origin_url;
--   * publishes has_secret in the canonical status payload;
--   * promotes metadata-only rows atomically when v2 receives a real secret;
--   * keeps the legacy bridge compatible through the explicit ACL cutover.
--
-- Recovery behavior: the functions can be replaced with their preceding
-- definitions. Restoring vault_secret_id NOT NULL is safe only after every
-- metadata-only row has either received a real secret or been explicitly
-- deleted; this migration intentionally performs neither destructive action.
-- The table is small, but the constraint/column changes still take a brief
-- table lock. The backfill is ordered, idempotent, and limited to legacy rows
-- with a username and no password.

begin;

-- Legacy supplier writes already own suppliers before their credential
-- trigger runs. Match that global order during DDL so deployment cannot wait
-- credentials -> suppliers while an old client waits suppliers -> credentials.
lock table public.suppliers in exclusive mode;

alter table public.supplier_credentials
  alter column vault_secret_id drop not null;

alter table public.supplier_credentials
  drop constraint if exists supplier_credentials_secret_or_username_check;
alter table public.supplier_credentials
  add constraint supplier_credentials_secret_or_username_check check (
    vault_secret_id is not null
    or (
      credential_kind = 'portal_password'
      and credential_key = 'default'
      and nullif(btrim(username), '') is not null
    )
  ) not valid;
alter table public.supplier_credentials
  validate constraint supplier_credentials_secret_or_username_check;

comment on column public.supplier_credentials.vault_secret_id is
  'Vault reference. It may be NULL only for portal-password metadata that preserves a non-empty username while no secret exists.';

-- The v2 transition wrapper attaches Vault before delegating to the original
-- command owner. Preserve the caller-visible optimistic-concurrency token for
-- that one internal attachment; the delegated command then advances it once.
create or replace function public.set_supplier_credential_updated_at()
returns trigger
language plpgsql
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_guard text := coalesce(
    current_setting('app.supplier_credential_attach_guard', true),
    ''
  );
  v_expected_guard text := txid_current()::text || ':' || new.id::text;
begin
  if v_guard = v_expected_guard then
    return new;
  end if;

  new.updated_at := greatest(
    clock_timestamp(),
    old.updated_at + interval '1 microsecond'
  );
  return new;
end;
$$;

revoke all on function public.set_supplier_credential_updated_at()
  from public, anon, authenticated, service_role;

-- Keep the already-reviewed secret-required command intact behind a private
-- name. The public v2 owner below only adds the metadata-only promotion.
do $$
begin
  if to_regprocedure(
    'public.upsert_supplier_credential_v2_secret_required_internal(uuid,uuid,text,text,uuid,timestamptz,uuid,text,text,text,text,boolean,boolean)'
  ) is null then
    if to_regprocedure(
      'public.upsert_supplier_credential_v2(uuid,uuid,text,text,uuid,timestamptz,uuid,text,text,text,text,boolean,boolean)'
    ) is null then
      raise exception 'Missing canonical supplier credential v2 command';
    end if;

    alter function public.upsert_supplier_credential_v2(
      uuid, uuid, text, text, uuid, timestamptz,
      uuid, text, text, text, text, boolean, boolean
    ) rename to upsert_supplier_credential_v2_secret_required_internal;
  end if;
end
$$;

revoke all on function public.upsert_supplier_credential_v2_secret_required_internal(
  uuid, uuid, text, text, uuid, timestamptz,
  uuid, text, text, text, text, boolean, boolean
) from public, anon, authenticated, service_role;

create or replace function public.upsert_supplier_credential_v2(
  p_tenant_id uuid,
  p_supplier_id uuid,
  p_credential_kind text,
  p_credential_key text,
  p_operation_id uuid,
  p_expected_updated_at timestamptz,
  p_engagement_id uuid,
  p_origin_url text,
  p_label text,
  p_username text,
  p_secret text,
  p_clear_engagement boolean,
  p_clear_origin boolean
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, vault, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
  v_kind text := lower(btrim(coalesce(p_credential_kind, '')));
  v_key text := lower(btrim(coalesce(p_credential_key, 'default')));
  v_origin_input text := nullif(btrim(p_origin_url), '');
  v_origin_url text := public.canonical_https_origin(v_origin_input);
  v_credential public.supplier_credentials%rowtype;
  v_receipt_exists boolean;
  v_secret_id uuid;
  v_secret_name text;
  v_result jsonb;
  v_has_secret boolean := false;
begin
  if v_role <> 'service_role'
     and not public.can_manage_supplier_credentials(p_tenant_id) then
    raise exception 'Supplier credential authority required'
      using errcode = '42501';
  end if;

  if v_kind not in ('portal_password', 'api_token', 'other')
     or v_key !~ '^[a-z][a-z0-9_.-]*$'
     or p_operation_id is null
     or nullif(p_secret, '') is null
     or (v_origin_input is not null and v_origin_url is null)
     or (coalesce(p_clear_engagement, false)
       and p_engagement_id is not null)
     or (coalesce(p_clear_origin, false) and v_origin_input is not null) then
    raise exception 'Valid credential kind, key, operation id, HTTPS origin, and secret are required'
      using errcode = '22023';
  end if;

  -- Preserve the canonical lock order: supplier, operation, credential.
  perform 1
  from public.suppliers supplier
  where supplier.tenant_id = p_tenant_id
    and supplier.id = p_supplier_id
  for update;

  if not found then
    raise exception 'Supplier not found in tenant' using errcode = 'P0002';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      'supplier_credential_operation:' || p_tenant_id::text || ':' ||
      p_operation_id::text,
      0
    )
  );

  select exists (
    select 1
    from public.supplier_credential_command_receipts receipt
    where receipt.tenant_id = p_tenant_id
      and receipt.operation_id = p_operation_id
  ) into v_receipt_exists;

  if not v_receipt_exists then
    perform pg_advisory_xact_lock(hashtextextended(
      'supplier_credential:' || p_tenant_id::text || ':' ||
      p_supplier_id::text || ':' || v_kind || ':' || v_key,
      0
    ));

    select credential.*
    into v_credential
    from public.supplier_credentials credential
    where credential.tenant_id = p_tenant_id
      and credential.supplier_id = p_supplier_id
      and credential.credential_kind = v_kind
      and credential.credential_key = v_key
    for update;

    if found and v_credential.vault_secret_id is null then
      if p_expected_updated_at is null then
        raise exception 'Expected credential updated_at is required for rotation'
          using errcode = '22023';
      end if;
      if v_credential.updated_at is distinct from p_expected_updated_at then
        raise exception 'Supplier credential changed concurrently'
          using errcode = '40001';
      end if;

      v_secret_name := 'supplier_' || v_kind || '_' ||
        p_supplier_id::text || case when v_key = 'default'
          then '' else '_' || v_key end;

      select secret.id
      into v_secret_id
      from vault.secrets secret
      where secret.name = v_secret_name
      limit 1;

      if v_secret_id is null then
        v_secret_id := vault.create_secret(
          p_secret,
          v_secret_name,
          'Supplier credential ' || v_kind || '/' || v_key || ' for ' ||
            p_supplier_id::text
        );
      else
        perform vault.update_secret(
          v_secret_id,
          p_secret,
          v_secret_name,
          'Supplier credential ' || v_kind || '/' || v_key || ' for ' ||
            p_supplier_id::text
        );
      end if;

      perform set_config(
        'app.supplier_credential_attach_guard',
        txid_current()::text || ':' || v_credential.id::text,
        true
      );
      update public.supplier_credentials credential
      set vault_secret_id = v_secret_id,
          updated_at = v_credential.updated_at
      where credential.id = v_credential.id;
      perform set_config('app.supplier_credential_attach_guard', '', true);
    end if;
  end if;

  v_result := public.upsert_supplier_credential_v2_secret_required_internal(
    p_tenant_id,
    p_supplier_id,
    v_kind,
    v_key,
    p_operation_id,
    p_expected_updated_at,
    p_engagement_id,
    p_origin_url,
    p_label,
    p_username,
    p_secret,
    p_clear_engagement,
    p_clear_origin
  );

  select credential.vault_secret_id is not null
  into v_has_secret
  from public.supplier_credentials credential
  where credential.tenant_id = p_tenant_id
    and credential.supplier_id = p_supplier_id
    and credential.credential_kind = v_kind
    and credential.credential_key = v_key;

  v_has_secret := coalesce(v_has_secret, false);
  v_result := v_result || jsonb_build_object('has_secret', v_has_secret);

  if jsonb_typeof(v_result -> 'applied_credential') = 'object' then
    v_result := jsonb_set(
      v_result,
      '{applied_credential,has_secret}',
      'true'::jsonb,
      true
    );
  end if;

  if jsonb_typeof(v_result -> 'current_credential') = 'object' then
    v_result := jsonb_set(
      v_result,
      '{current_credential,has_secret}',
      to_jsonb(v_has_secret),
      true
    );
  end if;

  return v_result;
end;
$$;

revoke all on function public.upsert_supplier_credential_v2(
  uuid, uuid, text, text, uuid, timestamptz,
  uuid, text, text, text, text, boolean, boolean
) from public, anon, authenticated, service_role;
grant execute on function public.upsert_supplier_credential_v2(
  uuid, uuid, text, text, uuid, timestamptz,
  uuid, text, text, text, text, boolean, boolean
) to authenticated, service_role;

do $$
begin
  if to_regprocedure(
    'public.find_supplier_credential_for_origin_v1_internal(uuid,text,text)'
  ) is null then
    alter function public.find_supplier_credential_for_origin(uuid, text, text)
      rename to find_supplier_credential_for_origin_v1_internal;
  end if;

  if to_regprocedure(
    'public.delete_supplier_credential_v2_without_secret_status_internal(uuid,uuid,text,text,uuid,timestamptz)'
  ) is null then
    alter function public.delete_supplier_credential_v2(
      uuid, uuid, text, text, uuid, timestamptz
    ) rename to delete_supplier_credential_v2_without_secret_status_internal;
  end if;
end
$$;

revoke all on function public.find_supplier_credential_for_origin_v1_internal(
  uuid, text, text
) from public, anon, authenticated, service_role;
revoke all on function public.delete_supplier_credential_v2_without_secret_status_internal(
  uuid, uuid, text, text, uuid, timestamptz
) from public, anon, authenticated, service_role;

create or replace function public.find_supplier_credential_for_origin(
  p_tenant_id uuid,
  p_origin_url text,
  p_credential_kind text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_result jsonb;
  v_candidates jsonb;
  v_match jsonb;
begin
  v_result :=
    public.find_supplier_credential_for_origin_v1_internal(
      p_tenant_id,
      p_origin_url,
      p_credential_kind
    );

  select coalesce(
    jsonb_agg(
      candidate.item || jsonb_build_object(
        'has_secret', exists (
          select 1
          from public.supplier_credentials credential
          where credential.tenant_id = p_tenant_id
            and credential.supplier_id =
              (candidate.item ->> 'supplier_id')::uuid
            and credential.credential_kind =
              candidate.item ->> 'credential_kind'
            and credential.credential_key =
              candidate.item ->> 'credential_key'
            and credential.vault_secret_id is not null
        )
      ) order by candidate.ordinality
    ),
    '[]'::jsonb
  )
  into v_candidates
  from jsonb_array_elements(v_result -> 'candidates')
    with ordinality as candidate(item, ordinality);

  if v_result ->> 'match_status' = 'unique' then
    v_match := v_candidates -> 0;
  else
    v_match := 'null'::jsonb;
  end if;

  return jsonb_set(
    jsonb_set(v_result, '{candidates}', v_candidates, true),
    '{match}', v_match, true
  );
end;
$$;

revoke all on function public.find_supplier_credential_for_origin(
  uuid, text, text
) from public, anon, authenticated, service_role;
grant execute on function public.find_supplier_credential_for_origin(
  uuid, text, text
) to authenticated, service_role;

create or replace function public.delete_supplier_credential_v2(
  p_tenant_id uuid,
  p_supplier_id uuid,
  p_credential_kind text,
  p_credential_key text,
  p_operation_id uuid,
  p_expected_updated_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_result jsonb;
  v_has_secret boolean := false;
begin
  v_result :=
    public.delete_supplier_credential_v2_without_secret_status_internal(
      p_tenant_id,
      p_supplier_id,
      p_credential_kind,
      p_credential_key,
      p_operation_id,
      p_expected_updated_at
    );

  select credential.vault_secret_id is not null
  into v_has_secret
  from public.supplier_credentials credential
  where credential.tenant_id = p_tenant_id
    and credential.supplier_id = p_supplier_id
    and credential.credential_kind =
      lower(btrim(coalesce(p_credential_kind, '')))
    and credential.credential_key =
      lower(btrim(coalesce(p_credential_key, 'default')));

  v_has_secret := coalesce(v_has_secret, false);
  v_result := v_result || jsonb_build_object('has_secret', v_has_secret);

  if jsonb_typeof(v_result -> 'current_credential') = 'object' then
    v_result := jsonb_set(
      v_result,
      '{current_credential,has_secret}',
      to_jsonb(v_has_secret),
      true
    );
  end if;

  return v_result;
end;
$$;

revoke all on function public.delete_supplier_credential_v2(
  uuid, uuid, text, text, uuid, timestamptz
) from public, anon, authenticated, service_role;
grant execute on function public.delete_supplier_credential_v2(
  uuid, uuid, text, text, uuid, timestamptz
) to authenticated, service_role;

create or replace function public.get_supplier_credential_status(
  p_tenant_id uuid,
  p_supplier_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
  v_credentials jsonb;
begin
  if v_role <> 'service_role'
     and not public.can_manage_supplier_credentials(p_tenant_id) then
    raise exception 'Supplier credential authority required'
      using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.suppliers supplier
    where supplier.tenant_id = p_tenant_id
      and supplier.id = p_supplier_id
  ) then
    raise exception 'Supplier not found in tenant' using errcode = 'P0002';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'credential_kind', credential.credential_kind,
        'credential_key', credential.credential_key,
        'engagement_id', credential.engagement_id,
        'origin_url', credential.origin_url,
        'label', credential.label,
        'username', credential.username,
        'has_secret', credential.vault_secret_id is not null,
        'updated_at', credential.updated_at
      ) order by credential.credential_kind, credential.credential_key,
        credential.id
    ),
    '[]'::jsonb
  )
  into v_credentials
  from public.supplier_credentials credential
  where credential.tenant_id = p_tenant_id
    and credential.supplier_id = p_supplier_id;

  return jsonb_build_object(
    'tenant_id', p_tenant_id,
    'supplier_id', p_supplier_id,
    'has_portal_credential', exists (
      select 1
      from public.supplier_credentials credential
      where credential.tenant_id = p_tenant_id
        and credential.supplier_id = p_supplier_id
        and credential.credential_kind = 'portal_password'
    ),
    'has_portal_secret', exists (
      select 1
      from public.supplier_credentials credential
      where credential.tenant_id = p_tenant_id
        and credential.supplier_id = p_supplier_id
        and credential.credential_kind = 'portal_password'
        and credential.vault_secret_id is not null
    ),
    'credentials', v_credentials
  );
end;
$$;

revoke all on function public.get_supplier_credential_status(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.get_supplier_credential_status(uuid, uuid)
  to authenticated, service_role;

create or replace function public.backfill_supplier_username_only_credentials()
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  supplier_row record;
  v_credential_id uuid;
  v_inserted integer;
  v_count integer := 0;
begin
  for supplier_row in
    select
      supplier.id,
      supplier.tenant_id,
      nullif(btrim(supplier.portal_username), '') as portal_username,
      supplier.website
    from public.suppliers supplier
    where supplier.tenant_id is not null
      and nullif(btrim(supplier.portal_username), '') is not null
      and nullif(supplier.portal_password, '') is null
    order by supplier.id
    for update
  loop
    v_credential_id := null;

    insert into public.supplier_credentials (
      tenant_id,
      supplier_id,
      credential_kind,
      credential_key,
      origin_url,
      label,
      username,
      vault_secret_id
    ) values (
      supplier_row.tenant_id,
      supplier_row.id,
      'portal_password',
      'default',
      public.canonical_https_origin(supplier_row.website),
      'Portal principal',
      supplier_row.portal_username,
      null
    ) on conflict (
      tenant_id, supplier_id, credential_kind, credential_key
    ) do nothing
    returning id into v_credential_id;

    get diagnostics v_inserted = row_count;

    if v_inserted = 1 then
      insert into public.supplier_credential_access_events (
        tenant_id,
        supplier_id,
        credential_id,
        credential_kind,
        credential_key,
        action,
        actor_id,
        metadata
      ) values (
        supplier_row.tenant_id,
        supplier_row.id,
        v_credential_id,
        'portal_password',
        'default',
        'create',
        null,
        jsonb_build_object(
          'source', 'legacy_username_only_backfill',
          'metadata_only', true
        )
      );
    end if;

    perform public.refresh_supplier_portal_origin_issue(
      supplier_row.tenant_id,
      supplier_row.id
    );

    v_count := v_count + v_inserted;
  end loop;

  return v_count;
end;
$$;

revoke all on function public.backfill_supplier_username_only_credentials()
  from public, anon, authenticated;
grant execute on function public.backfill_supplier_username_only_credentials()
  to service_role;

create or replace function public.sync_legacy_supplier_portal_credential()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, vault, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
  v_guard text := coalesce(
    current_setting('app.supplier_credential_sync_guard', true),
    ''
  );
  v_expected_guard text := txid_current()::text || ':' || new.id::text;
  v_operation_id uuid := gen_random_uuid();
  v_expected_updated_at timestamptz;
  v_origin_url text := public.canonical_https_origin(new.website);
  v_credential public.supplier_credentials%rowtype;
  v_secret_id uuid;
begin
  if v_guard = v_expected_guard then
    return new;
  end if;

  if v_role <> 'service_role'
     and not public.can_manage_supplier_credentials(new.tenant_id) then
    raise exception 'Supplier credential authority required'
      using errcode = '42501';
  end if;

  -- The supplier row is already locked by the triggering statement. Make the
  -- lock owner explicit before any advisory/credential coordination.
  perform 1
  from public.suppliers supplier
  where supplier.tenant_id = new.tenant_id
    and supplier.id = new.id
  for update;

  if nullif(new.portal_password, '') is null
     and nullif(btrim(new.portal_username), '') is not null then
    perform pg_advisory_xact_lock(hashtextextended(
      'supplier_credential:' || new.tenant_id::text || ':' ||
      new.id::text || ':portal_password:default',
      0
    ));

    select credential.*
    into v_credential
    from public.supplier_credentials credential
    where credential.tenant_id = new.tenant_id
      and credential.supplier_id = new.id
      and credential.credential_kind = 'portal_password'
      and credential.credential_key = 'default'
    for update;

    if found then
      v_secret_id := v_credential.vault_secret_id;

      update public.supplier_credentials credential
      set origin_url = case
            when v_origin_url is not null then v_origin_url
            else credential.origin_url
          end,
          label = 'Portal principal',
          username = nullif(btrim(new.portal_username), ''),
          vault_secret_id = null
      where credential.id = v_credential.id
      returning * into v_credential;

      if v_secret_id is not null then
        delete from vault.secrets secret
        where secret.id = v_secret_id;

        insert into public.supplier_credential_access_events (
          tenant_id, supplier_id, credential_id, credential_kind,
          credential_key, action, actor_id, metadata
        ) values (
          new.tenant_id, new.id, v_credential.id, 'portal_password',
          'default', 'delete',
          case when v_role = 'service_role' then null else auth.uid() end,
          jsonb_build_object(
            'source', case when v_role = 'service_role'
              then 'service_role_legacy_supplier_write'
              else 'legacy_supplier_write' end,
            'metadata_retained', true
          )
        );
      end if;
    else
      insert into public.supplier_credentials (
        tenant_id, supplier_id, credential_kind, credential_key,
        origin_url, label, username, vault_secret_id
      ) values (
        new.tenant_id, new.id, 'portal_password', 'default',
        v_origin_url, 'Portal principal',
        nullif(btrim(new.portal_username), ''), null
      ) returning * into v_credential;

      insert into public.supplier_credential_access_events (
        tenant_id, supplier_id, credential_id, credential_kind,
        credential_key, action, actor_id, metadata
      ) values (
        new.tenant_id, new.id, v_credential.id, 'portal_password',
        'default', 'create',
        case when v_role = 'service_role' then null else auth.uid() end,
        jsonb_build_object(
          'source', case when v_role = 'service_role'
            then 'service_role_legacy_supplier_write'
            else 'legacy_supplier_write' end,
          'metadata_only', true
        )
      );
    end if;

    perform public.refresh_supplier_portal_origin_issue(
      new.tenant_id,
      new.id
    );
  elsif nullif(new.portal_password, '') is null then
    select credential.updated_at
    into v_expected_updated_at
    from public.supplier_credentials credential
    where credential.tenant_id = new.tenant_id
      and credential.supplier_id = new.id
      and credential.credential_kind = 'portal_password'
      and credential.credential_key = 'default';

    if v_expected_updated_at is not null then
      perform public.delete_supplier_credential_v2(
        new.tenant_id,
        new.id,
        'portal_password',
        'default',
        v_operation_id,
        v_expected_updated_at
      );
    else
      perform public.refresh_supplier_portal_origin_issue(
        new.tenant_id,
        new.id
      );
    end if;
  else
    select credential.updated_at
    into v_expected_updated_at
    from public.supplier_credentials credential
    where credential.tenant_id = new.tenant_id
      and credential.supplier_id = new.id
      and credential.credential_kind = 'portal_password'
      and credential.credential_key = 'default';

    perform public.upsert_supplier_credential_v2(
      new.tenant_id,
      new.id,
      'portal_password',
      'default',
      v_operation_id,
      v_expected_updated_at,
      null,
      v_origin_url,
      'Portal principal',
      new.portal_username,
      new.portal_password,
      false,
      false
    );
  end if;

  return new;
end;
$$;

revoke all on function public.sync_legacy_supplier_portal_credential()
  from public, anon, authenticated, service_role;

select public.backfill_supplier_username_only_credentials();

commit;
