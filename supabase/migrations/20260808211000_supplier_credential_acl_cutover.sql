-- Supplier credential client cutover.
--
-- Apply only after every supported ERP client reads supplier credential state
-- through the v2/status/origin RPCs and no longer requests suppliers.* or
-- legacy portal fields in INSERT/UPDATE RETURNING clauses. The preceding
-- foundation migration is deliberately copy-first and remains compatible with
-- those clients; this migration is the explicit forced-upgrade boundary.
-- Plaintext cleanup remains a later readback-gated migration.

begin;

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
          and credential.origin_url is not distinct from
            public.canonical_https_origin(supplier.website)
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
    raise exception 'Supplier credential ACL cutover blocked: legacy portal state does not exactly match metadata-only or Vault-backed readback'
      using errcode = '23514';
  end if;
end
$$;

-- Durable supplier identity is command-owned. The current domain offers
-- deactivation, not hard deletion, so legacy tenant-wide RLS must not leave a
-- direct DELETE escape hatch after the cutover.
revoke all privileges on table public.suppliers
  from public, anon, authenticated;
do $$
declare
  v_safe_columns text;
begin
  select string_agg(
    quote_ident(attribute.attname),
    ', ' order by attribute.attnum
  )
  into v_safe_columns
  from pg_attribute attribute
  where attribute.attrelid = 'public.suppliers'::regclass
    and attribute.attnum > 0
    and not attribute.attisdropped
    and attribute.attname not in ('portal_username', 'portal_password');

  execute format(
    'grant select (%s) on table public.suppliers to authenticated',
    v_safe_columns
  );
end
$$;

revoke all on function public.upsert_supplier_credential(
  uuid, uuid, text, text, text, text
) from authenticated;
revoke all on function public.get_supplier_credential(uuid, uuid, text)
  from authenticated;
revoke all on function public.delete_supplier_credential(uuid, uuid, text)
  from authenticated;

comment on column public.suppliers.portal_username is
  'LEGACY COPY ONLY. Hidden from client roles at the 20260808211000 cutover; current clients use Vault-backed credential metadata RPCs.';
comment on column public.suppliers.portal_password is
  'LEGACY COPY ONLY. Hidden from client roles at the 20260808211000 cutover. A later migration may clear it only after full Vault/client readback.';

commit;
