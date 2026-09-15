-- Supplier credential origin metadata command.
--
-- Forward behavior:
--   * adds an idempotent, optimistic-concurrency command that changes only a
--     credential's canonical HTTPS origin;
--   * never reads, receives, creates, rotates, or deletes Vault secret bytes;
--   * records a durable command receipt and a metadata-only audit event;
--   * preserves an explicitly managed origin across the transitional legacy
--     username/password bridge; and
--   * limits the historical ACL cutover preflight to the legacy fields it
--     actually mirrors (username and password/Vault state).
--
-- Recovery behavior: replace the functions with their prior definitions if
-- required. Do not delete receipts or audit events. An applied origin can be
-- cleared through the same command with a new operation id and the current
-- updated_at token. The two widened CHECK domains must remain while any
-- update_origin receipt/event exists.
--
-- Lock behavior: DDL first blocks supplier/credential writers in their
-- canonical order, then locks the two tiny private audit tables. The command
-- itself always locks supplier -> operation id -> credential key -> row.
-- deployment_status: reviewed_deployable
-- deployment_gate: production_derived_supplier_relationship_pgtap_pass
-- deployment_gate: exact_sha256_and_schema_history_readback_at_rollout

begin;

set local lock_timeout = '5s';
set local statement_timeout = '30s';

-- EXCLUSIVE conflicts with the ROW SHARE table lock taken by SELECT FOR
-- UPDATE. A weaker SHARE ROW EXCLUSIVE lock permits that first writer lock and
-- can deadlock when the writer later reaches credentials in the opposite
-- direction.
lock table public.suppliers in exclusive mode;
lock table public.supplier_credentials in share row exclusive mode;
lock table public.supplier_credential_command_receipts in access exclusive mode;
lock table public.supplier_credential_access_events in access exclusive mode;

alter table public.supplier_credential_command_receipts
  drop constraint if exists supplier_credential_command_receipts_command_kind_check;
alter table public.supplier_credential_command_receipts
  add constraint supplier_credential_command_receipts_command_kind_check
  check (command_kind in ('upsert', 'delete', 'update_origin')) not valid;
alter table public.supplier_credential_command_receipts
  validate constraint supplier_credential_command_receipts_command_kind_check;

alter table public.supplier_credential_access_events
  drop constraint if exists supplier_credential_access_events_action_check;
alter table public.supplier_credential_access_events
  add constraint supplier_credential_access_events_action_check
  check (action in ('create', 'rotate', 'reveal', 'delete', 'update_origin'))
  not valid;
alter table public.supplier_credential_access_events
  validate constraint supplier_credential_access_events_action_check;

create or replace function public.update_supplier_credential_origin_v1(
  p_tenant_id uuid,
  p_supplier_id uuid,
  p_credential_kind text,
  p_credential_key text,
  p_operation_id uuid,
  p_expected_updated_at timestamptz,
  p_origin_url text,
  p_clear_origin boolean
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, extensions, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
  v_kind text := lower(btrim(coalesce(p_credential_kind, '')));
  v_key text := lower(btrim(coalesce(p_credential_key, 'default')));
  v_origin_input text := nullif(btrim(p_origin_url), '');
  v_origin_url text := public.canonical_https_origin(v_origin_input);
  v_target_origin text;
  v_previous_origin text;
  v_credential public.supplier_credentials%rowtype;
  v_receipt public.supplier_credential_command_receipts%rowtype;
  v_request_fingerprint text;
  v_changed boolean := false;
  v_current jsonb;
  v_result jsonb;
begin
  if v_role <> 'service_role'
     and not public.can_manage_supplier_credentials(p_tenant_id) then
    raise exception 'Supplier credential authority required'
      using errcode = '42501';
  end if;

  if v_kind not in ('portal_password', 'api_token', 'other')
     or v_key !~ '^[a-z][a-z0-9_.-]*$'
     or p_operation_id is null
     or p_expected_updated_at is null
     or (coalesce(p_clear_origin, false) and v_origin_input is not null)
     or (
       not coalesce(p_clear_origin, false)
       and (v_origin_input is null or v_origin_url is null)
     ) then
    raise exception 'Valid credential kind, key, operation id, expected updated_at, and canonical HTTPS origin are required'
      using errcode = '22023';
  end if;

  v_target_origin := case
    when coalesce(p_clear_origin, false) then null
    else v_origin_url
  end;

  v_request_fingerprint := encode(extensions.digest(
    jsonb_build_object(
      'supplier_id', p_supplier_id,
      'credential_kind', v_kind,
      'credential_key', v_key,
      'expected_updated_at', p_expected_updated_at,
      'origin_url', v_target_origin,
      'clear_origin', coalesce(p_clear_origin, false)
    )::text,
    'sha256'
  ), 'hex');

  -- Canonical lock order shared by every supplier-credential writer.
  perform 1
  from public.suppliers supplier
  where supplier.tenant_id = p_tenant_id
    and supplier.id = p_supplier_id
  for update;

  if not found then
    raise exception 'Supplier not found in tenant' using errcode = 'P0002';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    'supplier_credential_operation:' || p_tenant_id::text || ':' ||
    p_operation_id::text,
    0
  ));

  select receipt.*
  into v_receipt
  from public.supplier_credential_command_receipts receipt
  where receipt.tenant_id = p_tenant_id
    and receipt.operation_id = p_operation_id;

  if found then
    if v_receipt.command_kind <> 'update_origin'
       or v_receipt.supplier_id <> p_supplier_id
       or v_receipt.credential_kind <> v_kind
       or v_receipt.credential_key <> v_key
       or v_receipt.request_fingerprint <> v_request_fingerprint then
      raise exception 'Supplier credential operation id was reused with different content'
        using errcode = '23505';
    end if;

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

    if found then
      v_current := jsonb_build_object(
        'tenant_id', v_credential.tenant_id,
        'supplier_id', v_credential.supplier_id,
        'credential_kind', v_credential.credential_kind,
        'credential_key', v_credential.credential_key,
        'origin_url', v_credential.origin_url,
        'has_secret', v_credential.vault_secret_id is not null,
        'updated_at', v_credential.updated_at
      );
    else
      v_current := null;
    end if;

    return v_receipt.result || jsonb_build_object(
      'idempotent_replay', true,
      'current_credential', v_current
    );
  end if;

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

  if not found then
    raise exception 'Supplier credential not found' using errcode = 'P0002';
  end if;

  if v_credential.updated_at is distinct from p_expected_updated_at then
    raise exception 'Supplier credential changed concurrently'
      using errcode = '40001';
  end if;

  v_previous_origin := v_credential.origin_url;
  v_changed := v_previous_origin is distinct from v_target_origin;

  if v_changed then
    update public.supplier_credentials credential
    set origin_url = v_target_origin
    where credential.id = v_credential.id
    returning * into v_credential;

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
      p_tenant_id,
      p_supplier_id,
      v_credential.id,
      v_kind,
      v_key,
      'update_origin',
      case when v_role = 'service_role' then null else auth.uid() end,
      jsonb_build_object(
        'source', case when v_role = 'service_role'
          then 'service_role' else 'authorized_user' end,
        'operation_id', p_operation_id,
        'origin_cleared', v_target_origin is null,
        'had_previous_origin', v_previous_origin is not null
      )
    );
  end if;

  if v_kind = 'portal_password' and v_key = 'default' then
    perform public.refresh_supplier_portal_origin_issue(
      p_tenant_id,
      p_supplier_id
    );
  end if;

  v_current := jsonb_build_object(
    'tenant_id', v_credential.tenant_id,
    'supplier_id', v_credential.supplier_id,
    'credential_kind', v_credential.credential_kind,
    'credential_key', v_credential.credential_key,
    'origin_url', v_credential.origin_url,
    'has_secret', v_credential.vault_secret_id is not null,
    'updated_at', v_credential.updated_at
  );

  v_result := jsonb_build_object(
    'operation_id', p_operation_id,
    'idempotent_replay', false,
    'action', 'update_origin',
    'origin_updated', v_changed,
    'tenant_id', v_credential.tenant_id,
    'supplier_id', v_credential.supplier_id,
    'credential_kind', v_credential.credential_kind,
    'credential_key', v_credential.credential_key,
    'previous_origin_url', v_previous_origin,
    'origin_url', v_credential.origin_url,
    'has_secret', v_credential.vault_secret_id is not null,
    'updated_at', v_credential.updated_at,
    'current_credential', v_current
  );

  insert into public.supplier_credential_command_receipts (
    tenant_id,
    operation_id,
    supplier_id,
    credential_kind,
    credential_key,
    command_kind,
    request_fingerprint,
    expected_updated_at,
    credential_id,
    result,
    actor_id
  ) values (
    p_tenant_id,
    p_operation_id,
    p_supplier_id,
    v_kind,
    v_key,
    'update_origin',
    v_request_fingerprint,
    p_expected_updated_at,
    v_credential.id,
    v_result,
    case when v_role = 'service_role' then null else auth.uid() end
  );

  return v_result;
end;
$$;

revoke all on function public.update_supplier_credential_origin_v1(
  uuid, uuid, text, text, uuid, timestamptz, text, boolean
) from public, anon, authenticated, service_role;
grant execute on function public.update_supplier_credential_origin_v1(
  uuid, uuid, text, text, uuid, timestamptz, text, boolean
) to authenticated, service_role;

comment on function public.update_supplier_credential_origin_v1(
  uuid, uuid, text, text, uuid, timestamptz, text, boolean
) is
  'Idempotent optimistic-concurrency command for canonical HTTPS origin metadata. It never accepts, reads, or changes supplier credential secret bytes.';

-- Legacy supplier username/password writes may create a missing default
-- credential, but they must never replace an origin explicitly managed by the
-- credential command.
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
      set label = 'Portal principal',
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
      case when v_expected_updated_at is null then v_origin_url else null end,
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

-- The cutover copies legacy username/password state. A portal origin is a
-- separate exact-origin security binding and may intentionally differ from a
-- supplier's public corporate website.
create or replace function public.supplier_credential_acl_cutover_ready_internal()
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, vault, pg_temp
as $$
  select not exists (
    select 1
    from public.suppliers supplier
    where supplier.tenant_id is not null
      and (
        nullif(btrim(supplier.portal_username), '') is not null
        or nullif(supplier.portal_password, '') is not null
      )
      and not exists (
        select 1
        from public.supplier_credentials credential
        where credential.tenant_id = supplier.tenant_id
          and credential.supplier_id = supplier.id
          and credential.credential_kind = 'portal_password'
          and credential.credential_key = 'default'
          and credential.username is not distinct from
            nullif(btrim(supplier.portal_username), '')
          and (
            (
              nullif(supplier.portal_password, '') is null
              and nullif(btrim(supplier.portal_username), '') is not null
              and credential.vault_secret_id is null
            )
            or (
              nullif(supplier.portal_password, '') is not null
              and credential.vault_secret_id is not null
              and exists (
                select 1
                from vault.decrypted_secrets secret
                where secret.id = credential.vault_secret_id
                  and secret.decrypted_secret is not distinct from
                    supplier.portal_password
              )
            )
          )
      )
  )
$$;

revoke all on function public.supplier_credential_acl_cutover_ready_internal()
  from public, anon, authenticated, service_role;

do $$
begin
  if not public.supplier_credential_acl_cutover_ready_internal() then
    raise exception 'Supplier credential legacy copy is not ready: username or Vault state differs'
      using errcode = '23514';
  end if;
end
$$;

commit;
