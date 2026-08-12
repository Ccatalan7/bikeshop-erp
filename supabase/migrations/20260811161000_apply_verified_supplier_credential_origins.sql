-- Apply the owner-reviewed exact login origins for existing supplier access.
--
-- This is a data-only manifest. It intentionally excludes Esval because its
-- RUT-only quick-payment host does not establish the origin of a password
-- login. CGE is included as username-only metadata after its official virtual
-- office was verified; no password is invented and no Vault row is created.
--
-- Forward behavior: require the exact reviewed credential generation, apply
-- each origin through the audited metadata-only command, and fail closed on
-- origin collisions or target drift.
-- Recovery behavior: use update_supplier_credential_origin_v1 with new fixed
-- operation ids, each post-apply updated_at token, and p_clear_origin=true.
-- Never delete the durable receipts or access events.
-- deployment_status: reviewed_deployable_after_20260811160000
-- deployment_gate: exact_9_target_zero_drift_zero_collision_preflight
-- deployment_gate: atomic_origin_receipt_audit_vault_preservation_readback

begin;

set local lock_timeout = '5s';
set local statement_timeout = '30s';

-- Fence every supplier/credential writer before taking the manifest snapshot.
-- Keep the same table-lock order as the credential foundation migrations: an
-- EXCLUSIVE supplier lock prevents a writer from first taking ROW SHARE there
-- and later inverting the order while this rollout waits on credentials.
lock table public.suppliers in exclusive mode;
lock table public.supplier_credentials in share row exclusive mode;

create temporary table verified_supplier_origin_manifest (
  tenant_id uuid not null,
  supplier_id uuid not null,
  credential_kind text not null,
  credential_key text not null,
  operation_id uuid not null,
  expected_updated_at timestamptz not null,
  origin_url text not null,
  expected_has_secret boolean not null,
  primary key (tenant_id, supplier_id, credential_kind, credential_key),
  unique (tenant_id, operation_id),
  unique (tenant_id, origin_url)
) on commit drop;

insert into verified_supplier_origin_manifest (
  tenant_id,
  supplier_id,
  credential_kind,
  credential_key,
  operation_id,
  expected_updated_at,
  origin_url,
  expected_has_secret
) values
  (
    '5443b130-cc28-45af-a420-cd500b288890',
    '975eb429-4666-465a-b1ee-1305e719e708',
    'portal_password', 'default',
    '59766439-e9e5-4ba0-9ab8-3f9189503f33',
    '2026-08-09 15:06:27.766326+00',
    'https://www.andesindustrial.cl', true
  ),
  (
    '5443b130-cc28-45af-a420-cd500b288890',
    'af6e54db-7474-42bc-b8e8-02b5048adc6c',
    'portal_password', 'default',
    '44de7005-89da-4b37-8da7-1f3c85766f83',
    '2026-08-09 16:31:38.951348+00',
    'https://sucursalvirtual.cge.cl', false
  ),
  (
    '5443b130-cc28-45af-a420-cd500b288890',
    'f910b968-de7e-4c26-a0a2-866d13613ab4',
    'portal_password', 'default',
    '7e592ce8-4178-4d80-954f-88753df40dc4',
    '2026-08-09 15:06:27.772679+00',
    'https://www.comercialciclo.cl', true
  ),
  (
    '5443b130-cc28-45af-a420-cd500b288890',
    'bb053eed-6676-4de1-8855-fc2ab7aea3ff',
    'portal_password', 'default',
    '1e0bf82c-67d5-4437-bb97-bc1064fc5d72',
    '2026-08-09 15:06:27.770848+00',
    'https://droppbike.cl', true
  ),
  (
    '5443b130-cc28-45af-a420-cd500b288890',
    '3f6f71dc-99b8-4f0c-9f44-cd37276fc5ee',
    'portal_password', 'default',
    'c6db94ca-6b24-41df-ba34-e59ec5555c58',
    '2026-08-09 15:06:27.764008+00',
    'https://mkr.cl', true
  ),
  (
    '5443b130-cc28-45af-a420-cd500b288890',
    '35679cbf-a3ae-4f21-9851-d485d84b9f75',
    'portal_password', 'default',
    'ac1da67e-728a-4a40-b1ab-13b6833fbb53',
    '2026-08-09 15:06:27.761657+00',
    'https://clientes.nic.cl', true
  ),
  (
    '5443b130-cc28-45af-a420-cd500b288890',
    '1443758b-9749-42ef-bbe8-59a970067991',
    'portal_password', 'default',
    '59352ebf-0499-42f3-8695-dba728852138',
    '2026-08-09 15:06:27.759320+00',
    'https://www.outsidesports.cl', true
  ),
  (
    '5443b130-cc28-45af-a420-cd500b288890',
    'b33660dc-c38a-4a2d-833f-607bc2b0c2ae',
    'portal_password', 'default',
    '63c73169-2964-4119-b2b4-59ea0a36d115',
    '2026-08-09 15:06:27.768615+00',
    'https://portal.rburgos.cl', true
  ),
  (
    '5443b130-cc28-45af-a420-cd500b288890',
    '02988500-2227-4a4d-a583-91300f322a30',
    'portal_password', 'default',
    'a7d7f49c-492c-4f13-a897-d66e17d789cd',
    '2026-08-09 15:06:27.750933+00',
    'https://zeusr.sii.cl', true
  );

create temporary table verified_supplier_origin_snapshot
on commit drop
as
select
  credential.tenant_id,
  credential.supplier_id,
  credential.credential_kind,
  credential.credential_key,
  credential.vault_secret_id,
  md5(jsonb_build_array(
    credential.username,
    credential.label,
    credential.engagement_id
  )::text) as metadata_fingerprint,
  supplier.updated_at as supplier_updated_at
from verified_supplier_origin_manifest manifest
join public.supplier_credentials credential
  on credential.tenant_id = manifest.tenant_id
 and credential.supplier_id = manifest.supplier_id
 and credential.credential_kind = manifest.credential_kind
 and credential.credential_key = manifest.credential_key
join public.suppliers supplier
  on supplier.tenant_id = credential.tenant_id
 and supplier.id = credential.supplier_id;

do $$
declare
  manifest_row record;
  credential_row public.supplier_credentials%rowtype;
  v_receipt_exists boolean;
begin
  if (select count(*) from verified_supplier_origin_manifest) <> 9 then
    raise exception 'Verified supplier origin manifest must contain exactly 9 rows'
      using errcode = '23514';
  end if;

  if exists (
    select 1
    from verified_supplier_origin_manifest manifest
    where public.canonical_https_origin(manifest.origin_url)
      is distinct from manifest.origin_url
  ) then
    raise exception 'Verified supplier origin manifest contains a non-canonical origin'
      using errcode = '23514';
  end if;

  if exists (
    with effective_origins as (
      select
        credential.tenant_id,
        credential.supplier_id,
        credential.credential_kind,
        credential.credential_key,
        credential.origin_url
      from public.supplier_credentials credential
      where credential.origin_url is not null
        and not exists (
          select 1
          from verified_supplier_origin_manifest manifest
          where manifest.tenant_id = credential.tenant_id
            and manifest.supplier_id = credential.supplier_id
            and manifest.credential_kind = credential.credential_kind
            and manifest.credential_key = credential.credential_key
        )
      union all
      select
        manifest.tenant_id,
        manifest.supplier_id,
        manifest.credential_kind,
        manifest.credential_key,
        manifest.origin_url
      from verified_supplier_origin_manifest manifest
    )
    select 1
    from effective_origins origin_binding
    group by origin_binding.tenant_id, origin_binding.origin_url
    having count(*) > 1
  ) then
    raise exception 'Verified supplier origins would create an ambiguous tenant binding'
      using errcode = '23514';
  end if;

  for manifest_row in
    select *
    from verified_supplier_origin_manifest
    order by supplier_id
  loop
    select credential.*
    into credential_row
    from public.supplier_credentials credential
    where credential.tenant_id = manifest_row.tenant_id
      and credential.supplier_id = manifest_row.supplier_id
      and credential.credential_kind = manifest_row.credential_kind
      and credential.credential_key = manifest_row.credential_key;

    if not found then
      raise exception 'Verified supplier credential target is missing: %',
        manifest_row.supplier_id
        using errcode = 'P0002';
    end if;

    if (credential_row.vault_secret_id is not null)
       is distinct from manifest_row.expected_has_secret then
      raise exception 'Verified supplier credential secret state drifted: %',
        manifest_row.supplier_id
        using errcode = '23514';
    end if;

    select exists (
      select 1
      from public.supplier_credential_command_receipts receipt
      where receipt.tenant_id = manifest_row.tenant_id
        and receipt.operation_id = manifest_row.operation_id
    ) into v_receipt_exists;

    if not v_receipt_exists and (
      credential_row.origin_url is not null
      or credential_row.updated_at is distinct from
        manifest_row.expected_updated_at
    ) then
      raise exception 'Verified supplier credential generation drifted: %',
        manifest_row.supplier_id
        using errcode = '40001';
    end if;
  end loop;
end
$$;

select set_config(
  'request.jwt.claims',
  '{"role":"service_role"}',
  true
);
select set_config('request.jwt.claim.sub', '', true);

do $$
declare
  manifest_row record;
begin
  for manifest_row in
    select *
    from verified_supplier_origin_manifest
    order by supplier_id
  loop
    perform public.update_supplier_credential_origin_v1(
      manifest_row.tenant_id,
      manifest_row.supplier_id,
      manifest_row.credential_kind,
      manifest_row.credential_key,
      manifest_row.operation_id,
      manifest_row.expected_updated_at,
      manifest_row.origin_url,
      false
    );
  end loop;
end
$$;

do $$
begin
  if (
    select count(*)
    from verified_supplier_origin_manifest manifest
    join public.supplier_credentials credential
      on credential.tenant_id = manifest.tenant_id
     and credential.supplier_id = manifest.supplier_id
     and credential.credential_kind = manifest.credential_kind
     and credential.credential_key = manifest.credential_key
     and credential.origin_url = manifest.origin_url
     and (credential.vault_secret_id is not null)
       = manifest.expected_has_secret
  ) <> 9 then
    raise exception 'Verified supplier origins did not persist exactly'
      using errcode = '23514';
  end if;

  if exists (
    with effective_origins as (
      select
        credential.tenant_id,
        credential.supplier_id,
        credential.credential_kind,
        credential.credential_key,
        credential.origin_url
      from public.supplier_credentials credential
      where credential.origin_url is not null
        and not exists (
          select 1
          from verified_supplier_origin_manifest manifest
          where manifest.tenant_id = credential.tenant_id
            and manifest.supplier_id = credential.supplier_id
            and manifest.credential_kind = credential.credential_kind
            and manifest.credential_key = credential.credential_key
        )
      union all
      select
        manifest.tenant_id,
        manifest.supplier_id,
        manifest.credential_kind,
        manifest.credential_key,
        manifest.origin_url
      from verified_supplier_origin_manifest manifest
    )
    select 1
    from effective_origins origin_binding
    group by origin_binding.tenant_id, origin_binding.origin_url
    having count(*) > 1
  ) then
    raise exception 'Verified supplier origins created an ambiguous tenant binding'
      using errcode = '23514';
  end if;

  if exists (
    select 1
    from verified_supplier_origin_snapshot snapshot
    join public.supplier_credentials credential
      on credential.tenant_id = snapshot.tenant_id
     and credential.supplier_id = snapshot.supplier_id
     and credential.credential_kind = snapshot.credential_kind
     and credential.credential_key = snapshot.credential_key
    join public.suppliers supplier
      on supplier.tenant_id = credential.tenant_id
     and supplier.id = credential.supplier_id
    where credential.vault_secret_id is distinct from snapshot.vault_secret_id
       or md5(jsonb_build_array(
         credential.username,
         credential.label,
         credential.engagement_id
       )::text) is distinct from snapshot.metadata_fingerprint
       or supplier.updated_at is distinct from snapshot.supplier_updated_at
  ) then
    raise exception 'Origin manifest changed Vault references or unrelated metadata'
      using errcode = '23514';
  end if;

  if (
    select count(*)
    from verified_supplier_origin_manifest manifest
    join public.supplier_credential_command_receipts receipt
      on receipt.tenant_id = manifest.tenant_id
     and receipt.operation_id = manifest.operation_id
     and receipt.supplier_id = manifest.supplier_id
     and receipt.credential_kind = manifest.credential_kind
     and receipt.credential_key = manifest.credential_key
     and receipt.command_kind = 'update_origin'
     and receipt.result->>'origin_url' = manifest.origin_url
  ) <> 9 then
    raise exception 'Origin manifest receipts are incomplete'
      using errcode = '23514';
  end if;

  if (
    select count(*)
    from verified_supplier_origin_manifest manifest
    join public.supplier_credential_access_events event
      on event.tenant_id = manifest.tenant_id
     and event.supplier_id = manifest.supplier_id
     and event.credential_kind = manifest.credential_kind
     and event.credential_key = manifest.credential_key
     and event.action = 'update_origin'
     and event.metadata->>'operation_id' = manifest.operation_id::text
  ) <> 9 then
    raise exception 'Origin manifest audit events are incomplete'
      using errcode = '23514';
  end if;

  if exists (
    select 1
    from verified_supplier_origin_manifest manifest
    join public.supplier_data_quality_candidates candidate
      on candidate.tenant_id = manifest.tenant_id
     and candidate.supplier_id = manifest.supplier_id
     and candidate.issue_code = 'legacy_portal_origin_not_canonical'
    where candidate.status = 'pending'
  ) then
    raise exception 'Origin manifest left a stale portal-origin incident open'
      using errcode = '23514';
  end if;

  if not public.supplier_credential_acl_cutover_ready_internal() then
    raise exception 'Legacy username or Vault parity changed during origin rollout'
      using errcode = '23514';
  end if;
end
$$;

commit;
