begin;

select no_plan();

select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select set_config('request.jwt.claim.sub', '', true);

-- -------------------------------------------------------------------------
-- Published contract and hard security boundaries
-- -------------------------------------------------------------------------

select has_table('public', 'external_parties', 'external-party anchor exists');
select has_table(
  'public', 'external_party_identifiers',
  'tenant-scoped external identifiers exist'
);
select has_column(
  'public', 'suppliers', 'party_id',
  'durable supplier relationship links to external party'
);
select has_table(
  'public', 'supplier_role_definitions',
  'role vocabulary is canonical'
);
select has_table(
  'public', 'supplier_capability_definitions',
  'capability vocabulary is canonical'
);
select has_table(
  'public', 'supplier_tag_definitions',
  'tag vocabulary is canonical'
);
select has_table(
  'public', 'operational_nature_definitions',
  'operational nature vocabulary is canonical'
);
select has_table(
  'public', 'supplier_engagement_versions',
  'engagement facts are versioned'
);
select has_table(
  'public', 'supplier_accounting_policy_versions',
  'accounting posture is independently versioned'
);
select has_table(
  'public', 'supplier_accounting_rules',
  'matching rules are separate from posture'
);
select has_table(
  'public', 'supplier_accounting_evidence',
  'application evidence is durable'
);
select has_table(
  'public', 'received_tax_documents',
  'received tax-document identity exists'
);
select has_table(
  'public', 'purchase_invoice_lines',
  'normalized purchase lines exist'
);
select has_table(
  'public', 'supplier_credentials',
  'Vault credential metadata exists'
);
select has_table(
  'public', 'supplier_credential_command_receipts',
  'credential write idempotency receipts exist'
);
select has_table(
  'public', 'supplier_ocr_template_command_receipts',
  'OCR-template write idempotency receipts exist'
);
select has_table(
  'public', 'supplier_classification_definition_command_receipts',
  'classification master-data idempotency receipts exist'
);
select has_table(
  'public', 'supplier_credential_access_events',
  'credential access audit exists'
);
select ok(
  exists (
    select 1
    from pg_constraint credential_constraint
    where credential_constraint.conrelid =
        'public.supplier_credentials'::regclass
      and credential_constraint.conname =
        'supplier_credentials_secret_or_username_check'
      and pg_get_constraintdef(credential_constraint.oid, true) ilike
        '%vault_secret_id is not null%credential_kind = ''portal_password''%username%'
  )
  and not (
    select attribute.attnotnull
    from pg_attribute attribute
    where attribute.attrelid = 'public.supplier_credentials'::regclass
      and attribute.attname = 'vault_secret_id'
      and not attribute.attisdropped
  ),
  'credential metadata permits Vault-less rows only under the username-only contract'
);
select has_view(
  'public', 'active_business_site_read_model',
  'active business-site selector is published'
);
select has_view(
  'public', 'supplier_classification_candidate_read_model',
  'classification review queue is published'
);
select has_view(
  'public', 'supplier_profile_read_model',
  'secret-free supplier profile projection exists'
);
select has_column(
  'public', 'supplier_profile_read_model', 'service_relationship_summary',
  'profile projection publishes a server-owned relationship summary'
);
select has_column(
  'public', 'supplier_profile_read_model', 'effective_business_date',
  'profile projection publishes the server-owned tenant business date'
);
select has_column(
  'public', 'supplier_profile_read_model', 'has_credential_reference',
  'profile projection publishes any-kind credential-reference state'
);
select has_function(
  'public', 'tenant_business_date', array['uuid', 'timestamp with time zone'],
  'tenant business date has one canonical server owner'
);
select ok(
  position(
    'pg_timezone_names' in (
    select function.prosrc
    from pg_catalog.pg_proc function
    join pg_catalog.pg_namespace namespace
      on namespace.oid = function.pronamespace
    where namespace.nspname = 'public'
      and function.proname = 'tenant_business_date'
      and pg_catalog.pg_get_function_identity_arguments(function.oid)
        = 'p_tenant_id uuid, p_at timestamp with time zone'
    )
  ) > 0,
  'tenant business date keeps canonical IANA catalog validation'
);
select ok(
  lower(pg_catalog.pg_get_viewdef(
    'public.supplier_profile_read_model'::regclass,
    true
  )) ~ 'tenant_business_dates[[:space:]]+as[[:space:]]+materialized',
  'profile materializes one tenant business-date relation'
);
select is(
  (
    select count(*)
    from regexp_matches(
      lower(pg_catalog.pg_get_viewdef(
        'public.supplier_profile_read_model'::regclass,
        true
      )),
      'tenant_business_date[[:space:]]*[(]',
      'g'
    )
  ),
  1::bigint,
  'profile view invokes tenant business date exactly once in its stored query'
);
select has_function(
  'public', 'update_supplier_ocr_template',
  array['uuid', 'uuid', 'timestamp with time zone', 'uuid', 'jsonb'],
  'supplier OCR template has one narrow canonical write command'
);
select has_function(
  'public', 'supplier_credential_acl_cutover_ready_internal', array[]::text[],
  'credential cutover keeps an exact Vault readback preflight owner'
);
select has_view(
  'public', 'supplier_economic_read_model',
  'economic event projection exists'
);
select has_view(
  'public', 'supplier_economic_summary_read_model',
  'economic summary projection exists'
);
select has_trigger(
  'public', 'suppliers', 'trg_00_supplier_foundation_restore_lock',
  'supplier mutations participate in the tenant restore fence'
);
select has_trigger(
  'public', 'purchase_invoices',
  'trg_00_supplier_foundation_restore_lock',
  'purchase-invoice mutations participate in the tenant restore fence'
);
select has_function(
  'public', 'supplier_foundation_invoice_rehydrate_is_active', array['uuid'],
  'purchase-invoice restore rehydration has one explicit transaction guard'
);
select ok(
  not exists (
    select 1
    from pg_trigger trigger
    where trigger.tgrelid = 'public.purchase_invoices'::regclass
      and not trigger.tgisinternal
      and (trigger.tgtype & 16) = 16
      and trigger.tgname <> 'trg_00_supplier_foundation_restore_lock'
      and (
        trigger.tgqual is null
        or pg_get_triggerdef(trigger.oid, true)
          not ilike '%supplier_foundation_invoice_rehydrate_is_active%'
      )
  ),
  'every purchase-invoice UPDATE trigger except the restore fence consumes the internal rehydrate guard'
);
select ok(
  pg_get_functiondef(
    'public.lock_supplier_foundation_restore_mutation()'::regprocedure
  ) ilike '%pg_advisory_xact_lock_shared%',
  'ordinary foundation mutations use the shared side of the tenant restore fence'
);
select ok(
  position(
    'for update' in lower(pg_get_functiondef(
      'public.upsert_supplier_credential_v2(uuid,uuid,text,text,uuid,timestamptz,uuid,text,text,text,text,boolean,boolean)'::regprocedure
    ))
  ) < position(
    'supplier_credential_operation:' in lower(pg_get_functiondef(
      'public.upsert_supplier_credential_v2(uuid,uuid,text,text,uuid,timestamptz,uuid,text,text,text,text,boolean,boolean)'::regprocedure
    ))
  )
  and position(
    'for update' in lower(pg_get_functiondef(
      'public.delete_supplier_credential_v2_without_secret_status_internal(uuid,uuid,text,text,uuid,timestamptz)'::regprocedure
    ))
  ) < position(
    'supplier_credential_operation:' in lower(pg_get_functiondef(
      'public.delete_supplier_credential_v2_without_secret_status_internal(uuid,uuid,text,text,uuid,timestamptz)'::regprocedure
    ))
  ),
  'credential upsert/delete and their replay paths lock supplier before credential coordination'
);
select ok(
  pg_get_functiondef(
    'public.sync_legacy_supplier_portal_credential()'::regprocedure
  ) ilike '%v_operation_id uuid := gen_random_uuid()%'
  and pg_get_functiondef(
    'public.sync_legacy_supplier_portal_credential()'::regprocedure
  ) not ilike '%legacy_supplier_portal_trigger_delete:%',
  'each actual legacy portal transition owns a fresh receipt generation'
);
select ok(
  position(
    'for update' in lower(pg_get_functiondef(
      'public.sync_legacy_supplier_portal_credential()'::regprocedure
    ))
  ) < position(
    'supplier_credential:' in lower(pg_get_functiondef(
      'public.sync_legacy_supplier_portal_credential()'::regprocedure
    ))
  ),
  'legacy bridge owns the supplier row before credential coordination'
);
select ok(
  pg_get_triggerdef((
    select trigger.oid
    from pg_trigger trigger
    where trigger.tgrelid = 'public.supplier_credentials'::regclass
      and trigger.tgname = 'trg_supplier_credentials_updated_at'
      and not trigger.tgisinternal
  ), true) ilike '%set_supplier_credential_updated_at%',
  'credential versions use the monotonic clock trigger instead of transaction-stable now()'
);
select ok(
  pg_get_triggerdef((
    select trigger.oid
    from pg_trigger trigger
    where trigger.tgrelid = 'public.suppliers'::regclass
      and trigger.tgname = 'trg_suppliers_updated_at'
      and not trigger.tgisinternal
  ), true) ilike '%set_supplier_updated_at%',
  'supplier optimistic-concurrency tokens use a monotonic clock trigger'
);
select ok(
  position(
    'lock table public.suppliers, public.purchase_invoices'
      in lower(pg_get_functiondef(
        'public.restore_backup_internal(uuid,uuid)'::regprocedure
      ))
  ) > 0
  and position(
    'in share row exclusive mode'
      in lower(pg_get_functiondef(
        'public.restore_backup_internal(uuid,uuid)'::regprocedure
      ))
  ) < position(
    'pg_advisory_xact_lock(hashtextextended' in lower(pg_get_functiondef(
      'public.restore_backup_internal(uuid,uuid)'::regprocedure
    ))
  )
  and position(
    'pg_advisory_xact_lock(hashtextextended' in lower(pg_get_functiondef(
      'public.restore_backup_internal(uuid,uuid)'::regprocedure
    ))
  ) < position(
    'select backup.backup_data' in lower(pg_get_functiondef(
      'public.restore_backup_internal(uuid,uuid)'::regprocedure
    ))
  ),
  'restore drains DML before taking the tenant fence and reading the durable identity snapshot'
);

-- Disposable-clone two-session regression. dblink is created inside this
-- pgTAP transaction and disappears at the final rollback; the secondary
-- connection owns a temp table whose real row trigger takes the shared fence.
create extension if not exists dblink;
select is(
  public.dblink_connect(
    'supplier_foundation_restore_lock_probe',
    format(
      'hostaddr=%s port=%s dbname=%s user=%s password=%s',
      inet_server_addr(),
      inet_server_port(),
      current_database(),
      current_user,
      coalesce(
        nullif(current_setting('app.pgtap_database_password', true), ''),
        'postgres'
      )
    )
  ),
  'OK',
  'restore-lock regression opens an independent local database session'
);
select is(
  public.dblink_exec(
    'supplier_foundation_restore_lock_probe',
    'create temporary table supplier_foundation_lock_target (tenant_id uuid not null)'
  ),
  'CREATE TABLE',
  'secondary session owns an isolated mutation target'
);
select is(
  public.dblink_exec(
    'supplier_foundation_restore_lock_probe',
    'create trigger supplier_foundation_lock_target_trigger before insert or update or delete on supplier_foundation_lock_target for each row execute function public.lock_supplier_foundation_restore_mutation()'
  ),
  'CREATE TRIGGER',
  'secondary mutation target uses the canonical supplier restore lock trigger'
);
create temporary table supplier_restore_lock_probe_session (remote_pid integer);
insert into supplier_restore_lock_probe_session
select remote_pid
from public.dblink(
  'supplier_foundation_restore_lock_probe',
  'select pg_backend_pid()'
) as remote_session(remote_pid integer);
select is(
  public.dblink_exec(
    'supplier_foundation_restore_lock_probe',
    $remote_setup$
      create function pg_temp.hold_supplier_foundation_restore_table_fence()
      returns text
      language plpgsql
      as $remote_function$
      begin
        lock table public.suppliers, public.purchase_invoices
          in share row exclusive mode;
        perform pg_sleep(1.5);
        return 'held';
      end;
      $remote_function$
    $remote_setup$
  ),
  'CREATE FUNCTION',
  'secondary session can hold the exact canonical restore table fence'
);
select is(
  public.dblink_send_query(
    'supplier_foundation_restore_lock_probe',
    'select pg_temp.hold_supplier_foundation_restore_table_fence()'
  ),
  1,
  'secondary restore table fence starts asynchronously'
);
do $$
declare
  v_attempt integer;
begin
  for v_attempt in 1..100 loop
    exit when exists (
      select 1
      from pg_locks lock
      where lock.pid = (
        select remote_pid from supplier_restore_lock_probe_session
      )
        and lock.locktype = 'relation'
        and lock.relation = 'public.purchase_invoices'::regclass
        and lock.mode = 'ShareRowExclusiveLock'
        and lock.granted
    );
    perform pg_sleep(0.01);
  end loop;
end;
$$;
select ok(
  exists (
    select 1
    from pg_locks lock
    where lock.pid = (
      select remote_pid from supplier_restore_lock_probe_session
    )
      and lock.locktype = 'relation'
      and lock.relation in (
        'public.suppliers'::regclass,
        'public.purchase_invoices'::regclass
      )
      and lock.mode = 'ShareRowExclusiveLock'
      and lock.granted
    group by lock.pid
    having count(distinct lock.relation) = 2
  ),
  'restore table fence covers both durable identity owners before row access'
);
select throws_ok(
  $$lock table public.suppliers, public.purchase_invoices
      in share row exclusive mode nowait$$,
  '55P03',
  null,
  'a second restore cannot acquire the self-exclusive table fence concurrently'
);
select set_config('lock_timeout', '75ms', true);
select throws_ok(
  $$update public.purchase_invoices set notes = notes where false$$,
  '55P03',
  null,
  'concurrent UPDATE is stopped at its table lock before any tuple can deadlock'
);
select set_config('lock_timeout', '0', true);
select is(
  (
    select result
    from public.dblink_get_result(
      'supplier_foundation_restore_lock_probe'
    ) as remote_result(result text)
  ),
  'held',
  'secondary restore table fence releases after its transaction commits'
);
select is(
  (
    select count(*)::integer
    from public.dblink_get_result(
      'supplier_foundation_restore_lock_probe'
    ) as drained_result(result text)
  ),
  0,
  'secondary asynchronous table-fence result is fully drained before reuse'
);
select lives_ok(
  $$update public.purchase_invoices set notes = notes where false$$,
  'UPDATE proceeds after the restore table fence releases'
);
select is(
  public.dblink_send_query(
    'supplier_foundation_restore_lock_probe',
    $remote_query$
      with inserted as materialized (
        insert into supplier_foundation_lock_target (tenant_id)
        values ('a8082100-ffff-4000-8000-000000000001'::uuid)
        returning tenant_id
      )
      select tenant_id::text, pg_sleep(1.5)::text
      from inserted
    $remote_query$
  ),
  1,
  'secondary supplier mutation starts asynchronously'
);
do $$
declare
  v_attempt integer;
begin
  for v_attempt in 1..100 loop
    exit when exists (
      select 1
      from pg_locks lock
      where lock.pid = (
        select remote_pid from supplier_restore_lock_probe_session
      )
        and lock.locktype = 'advisory'
        and lock.mode = 'ShareLock'
        and lock.granted
    );
    perform pg_sleep(0.01);
  end loop;
end;
$$;
select ok(
  exists (
    select 1
    from pg_locks lock
    where lock.pid = (
      select remote_pid from supplier_restore_lock_probe_session
    )
      and lock.locktype = 'advisory'
      and lock.mode = 'ShareLock'
      and lock.granted
  ),
  'real secondary mutation holds the shared tenant fence'
);
select is(
  pg_try_advisory_xact_lock(hashtextextended(
    'supplier_foundation_restore:a8082100-ffff-4000-8000-000000000001',
    0
  )),
  false,
  'exclusive restore cannot pass while another session mutates the tenant'
);
select is(
  (
    select tenant_id
    from public.dblink_get_result(
      'supplier_foundation_restore_lock_probe'
    ) as remote_result(tenant_id text, waited text)
  ),
  'a8082100-ffff-4000-8000-000000000001',
  'secondary mutation completes without losing its tenant identity'
);
select is(
  pg_try_advisory_xact_lock(hashtextextended(
    'supplier_foundation_restore:a8082100-ffff-4000-8000-000000000001',
    0
  )),
  true,
  'exclusive restore proceeds after the secondary mutation commits'
);
select is(
  public.dblink_disconnect('supplier_foundation_restore_lock_probe'),
  'OK',
  'restore-lock secondary session closes cleanly'
);

select is(
  (
    select column_default
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'suppliers'
      and column_name = 'default_tax_treatment'
  ),
  '''no_tax''::text',
  'supplier tax-treatment default satisfies its check'
);

select ok(
  not has_column_privilege(
    'authenticated', 'public.suppliers', 'portal_password', 'SELECT'
  ) and not has_column_privilege(
    'authenticated', 'public.suppliers', 'portal_username', 'SELECT'
  ) and not has_column_privilege(
    'anon', 'public.suppliers', 'portal_password', 'SELECT'
  ) and not has_column_privilege(
    'anon', 'public.suppliers', 'portal_username', 'SELECT'
  ),
  'client roles cannot raw-read legacy supplier portal credentials'
);
select ok(
  not has_column_privilege(
    'authenticated', 'public.suppliers', 'portal_password', 'INSERT'
  ) and not has_column_privilege(
    'authenticated', 'public.suppliers', 'portal_password', 'UPDATE'
  ) and not has_column_privilege(
    'authenticated', 'public.suppliers', 'portal_username', 'INSERT'
  ) and not has_column_privilege(
    'authenticated', 'public.suppliers', 'portal_username', 'UPDATE'
  ),
  'authenticated cannot bypass credential commands through legacy writes'
);
select ok(
  has_column_privilege(
    'authenticated', 'public.suppliers', 'name', 'SELECT'
  ) and not has_column_privilege(
    'authenticated', 'public.suppliers', 'name', 'INSERT'
  ) and not has_column_privilege(
    'authenticated', 'public.suppliers', 'name', 'UPDATE'
  ),
  'cutover leaves secret-free supplier columns readable but command-owns every mutation'
);
select ok(
  not has_table_privilege(
    'authenticated', 'public.suppliers', 'DELETE'
  ) and not has_table_privilege(
    'anon', 'public.suppliers', 'DELETE'
  ) and not has_table_privilege(
    'authenticated', 'public.suppliers', 'TRUNCATE'
  ) and not has_table_privilege(
    'anon', 'public.suppliers', 'TRUNCATE'
  ) and has_table_privilege(
    'service_role', 'public.suppliers', 'DELETE'
  ),
  'destructive supplier table privileges are unavailable to clients and retained only for internal service owners'
);
select ok(
  not has_table_privilege(
    'authenticated', 'public.supplier_credentials', 'SELECT'
  ) and not has_table_privilege(
    'authenticated', 'public.supplier_credential_command_receipts', 'SELECT'
  ),
  'credential metadata and command receipts cannot be queried directly'
);
select ok(
  not has_table_privilege(
    'authenticated',
    'public.supplier_ocr_template_command_receipts',
    'SELECT'
  ) and not has_function_privilege(
    'public',
    'public.update_supplier_ocr_template(uuid,uuid,timestamptz,uuid,jsonb)',
    'EXECUTE'
  ) and has_function_privilege(
    'authenticated',
    'public.update_supplier_ocr_template(uuid,uuid,timestamptz,uuid,jsonb)',
    'EXECUTE'
  ),
  'OCR-template receipts stay private while the narrow command is authenticated-only'
);
select ok(
  not has_function_privilege(
    'public',
    'public.supplier_credential_acl_cutover_ready_internal()',
    'EXECUTE'
  ) and not has_function_privilege(
    'authenticated',
    'public.supplier_credential_acl_cutover_ready_internal()',
    'EXECUTE'
  ) and not has_function_privilege(
    'service_role',
    'public.supplier_credential_acl_cutover_ready_internal()',
    'EXECUTE'
  ),
  'global credential cutover preflight is migration-owner-only'
);
select ok(
  not has_table_privilege(
    'authenticated', 'public.supplier_credential_access_events', 'SELECT'
  ),
  'credential audit cannot be enumerated directly'
);
select ok(
  not has_table_privilege(
    'authenticated', 'vault.decrypted_secrets', 'SELECT'
  ),
  'decrypted Vault secrets are not client-readable'
);
select ok(
  not has_table_privilege(
    'authenticated', 'public.supplier_accounting_evidence', 'INSERT'
  ),
  'evidence is RPC-only for clients'
);
select ok(
  not has_table_privilege(
    'authenticated', 'public.received_tax_documents', 'INSERT'
  ) and not has_table_privilege(
    'authenticated', 'public.purchase_invoice_lines', 'UPDATE'
  ),
  'source tax documents and normalized lines are command-owned'
);
select ok(
  not has_function_privilege(
    'public',
    'public.upsert_supplier_credential_v2(uuid,uuid,text,text,uuid,timestamptz,uuid,text,text,text,text,boolean,boolean)',
    'EXECUTE'
  ) and not has_function_privilege(
    'anon',
    'public.get_supplier_credential_v2(uuid,uuid,text,text)',
    'EXECUTE'
  ) and not has_function_privilege(
    'public',
    'public.delete_supplier_credential_v2(uuid,uuid,text,text,uuid,timestamptz)',
    'EXECUTE'
  ),
  'credential v2 commands have no PUBLIC or anon execution'
);
select ok(
  not has_function_privilege(
    'public',
    'public.tenant_business_date(uuid,timestamp with time zone)',
    'EXECUTE'
  ) and not has_function_privilege(
    'anon',
    'public.tenant_business_date(uuid,timestamp with time zone)',
    'EXECUTE'
  ) and has_function_privilege(
    'authenticated',
    'public.tenant_business_date(uuid,timestamp with time zone)',
    'EXECUTE'
  ),
  'tenant business date is callable only through authenticated tenant scope or service role'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.upsert_supplier_classification_definition_v2(uuid,text,jsonb,uuid,timestamptz)',
    'EXECUTE'
  ) and not has_function_privilege(
    'authenticated',
    'public.upsert_supplier_classification_definition(uuid,text,jsonb)',
    'EXECUTE'
  ) and not has_table_privilege(
    'authenticated',
    'public.supplier_classification_definition_command_receipts',
    'SELECT'
  ),
  'classification master data is v2-command-only with private receipts'
);
select ok(
  (
    select coalesce(option = 'security_invoker=true', false)
    from pg_class relation
    cross join lateral unnest(coalesce(relation.reloptions, '{}'::text[])) option
    where relation.oid = 'public.supplier_profile_read_model'::regclass
      and option = 'security_invoker=true'
  ),
  'supplier profile view is security_invoker'
);
select ok(
  (
    select coalesce(option = 'security_invoker=true', false)
    from pg_class relation
    cross join lateral unnest(coalesce(relation.reloptions, '{}'::text[])) option
    where relation.oid = 'public.supplier_economic_summary_read_model'::regclass
      and option = 'security_invoker=true'
  ),
  'supplier summary view is security_invoker'
);
select ok(
  not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'supplier_profile_read_model'
      and column_name in (
        'portal_password', 'vault_secret_id', 'secret', 'username'
      )
  ),
  'general profile exposes no credential material'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.redact_supplier_passwords_from_backups(uuid,uuid[],boolean)',
    'EXECUTE'
  ) and has_function_privilege(
    'authenticated',
    'public.redact_supplier_passwords_from_backups(uuid,uuid[],boolean)',
    'EXECUTE'
  ),
  'backup remediation is unavailable to anonymous clients and tenant-gated for authenticated users'
);

-- -------------------------------------------------------------------------
-- Tenant, authority, vocabulary, and compatibility fixtures
-- -------------------------------------------------------------------------

insert into public.tenants (id, shop_name) values
  ('a8082100-0000-4000-8000-000000000001', 'Supplier Foundation A'),
  ('a8082100-0000-4000-8000-000000000002', 'Supplier Foundation B');

update public.tenants
set timezone = case id
  when 'a8082100-0000-4000-8000-000000000001'::uuid
    then 'America/Santiago'
  else 'UTC'
end
where id in (
  'a8082100-0000-4000-8000-000000000001',
  'a8082100-0000-4000-8000-000000000002'
);

select is(
  public.tenant_business_date(
    'a8082100-0000-4000-8000-000000000001',
    '2026-08-09 02:30:00+00'::timestamptz
  ),
  '2026-08-08'::date,
  'America/Santiago owns the prior civil date across a UTC boundary'
);
select is(
  public.tenant_business_date(
    'a8082100-0000-4000-8000-000000000002',
    '2026-08-09 02:30:00+00'::timestamptz
  ),
  '2026-08-09'::date,
  'the same instant resolves independently in the configured tenant timezone'
);

select set_config(
  'app.supplier_foundation_invoice_rehydrate_tenant',
  'a8082100-0000-4000-8000-000000000001',
  true
);
select set_config(
  'request.jwt.claims',
  '{"role":"authenticated","sub":"a8082100-0000-4000-8000-000000000091"}',
  true
);
set local role authenticated;
select is(
  public.supplier_foundation_invoice_rehydrate_is_active(
    'a8082100-0000-4000-8000-000000000001'
  ),
  false,
  'authenticated clients cannot forge the transaction-local invoice restore guard'
);
reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select is(
  public.supplier_foundation_invoice_rehydrate_is_active(
    'a8082100-0000-4000-8000-000000000001'
  ),
  true,
  'canonical service-role restore context can activate its exact tenant guard'
);
select set_config(
  'app.supplier_foundation_invoice_rehydrate_tenant', '', true
);

update public.tenants
set timezone = 'Mars/Olympus'
where id = 'a8082100-0000-4000-8000-000000000001';
select throws_ok(
  $$select public.tenant_business_date(
    'a8082100-0000-4000-8000-000000000001'
  )$$,
  '22023',
  'Tenant timezone is invalid',
  'invalid tenant timezone fails closed instead of borrowing the session date'
);
update public.tenants
set timezone = 'America/Santiago'
where id = 'a8082100-0000-4000-8000-000000000001';
select is(
  public.tenant_business_date(
    'a8082100-0000-4000-8000-000000000001',
    '2026-08-09 02:30:00+00'::timestamptz
  ),
  '2026-08-08'::date,
  'rejected timezone writes preserve the last valid tenant business date'
);

create temporary table supplier_test_clock as
select public.tenant_business_date(
  'a8082100-0000-4000-8000-000000000001'
) as business_date;

select ok(
  not exists (
    select 1
    from public.job_roles role
    where role.tenant_id in (
      'a8082100-0000-4000-8000-000000000001',
      'a8082100-0000-4000-8000-000000000002'
    )
      and role.system_role in ('admin', 'manager')
      and not (
        role.default_permissions
          @> '{"can_manage_supplier_credentials":true}'::jsonb
      )
  ),
  'future tenant admin/manager role defaults receive credential authority'
);

select ok(
  not exists (
    select 1
    from public.supplier_role_definitions definition
    where definition.tenant_id in (
      'a8082100-0000-4000-8000-000000000001',
      'a8082100-0000-4000-8000-000000000002'
    )
      and definition.code = 'free_service_provider'
  ) and not exists (
    select 1
    from public.supplier_capability_definitions definition
    where definition.tenant_id in (
      'a8082100-0000-4000-8000-000000000001',
      'a8082100-0000-4000-8000-000000000002'
    )
      and definition.code = 'free_services'
  ),
  'free service is not seeded as a supplier role or capability'
);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  (
    'a8082100-0000-4000-8000-000000000091',
    'authenticated', 'authenticated', 'supplier-manager-a@example.invalid',
    '', now(),
    '{"account_type":"erp_staff","tenant_id":"a8082100-0000-4000-8000-000000000001"}'::jsonb,
    '{}'::jsonb, now(), now()
  ),
  (
    'a8082100-0000-4000-8000-000000000092',
    'authenticated', 'authenticated', 'supplier-cashier-a@example.invalid',
    '', now(),
    '{"account_type":"erp_staff","tenant_id":"a8082100-0000-4000-8000-000000000001"}'::jsonb,
    '{}'::jsonb, now(), now()
  ),
  (
    'a8082100-0000-4000-8000-000000000093',
    'authenticated', 'authenticated', 'supplier-manager-b@example.invalid',
    '', now(),
    '{"account_type":"erp_staff","tenant_id":"a8082100-0000-4000-8000-000000000002"}'::jsonb,
    '{}'::jsonb, now(), now()
  );

delete from public.user_profiles
where user_id in (
  'a8082100-0000-4000-8000-000000000091',
  'a8082100-0000-4000-8000-000000000092',
  'a8082100-0000-4000-8000-000000000093'
);

insert into public.user_profiles (
  user_id, tenant_id, role, permissions, is_active
) values
  (
    'a8082100-0000-4000-8000-000000000091',
    'a8082100-0000-4000-8000-000000000001',
    'admin',
    '{"manage_accounting":true,"edit_settings":true,"can_manage_supplier_credentials":true}'::jsonb,
    true
  ),
  (
    'a8082100-0000-4000-8000-000000000092',
    'a8082100-0000-4000-8000-000000000001',
    'cashier',
    '{"manage_users":true}'::jsonb,
    true
  ),
  (
    'a8082100-0000-4000-8000-000000000093',
    'a8082100-0000-4000-8000-000000000002',
    'manager',
    '{"manage_accounting":true,"edit_settings":true,"can_manage_supplier_credentials":true}'::jsonb,
    true
  );

insert into public.suppliers (
  id, tenant_id, name, legal_name, rut, website,
  portal_username, portal_password
) values
  (
    'a8082100-0001-4000-8000-000000000101',
    'a8082100-0000-4000-8000-000000000001',
    'Proveedor Base A', 'Proveedor Base A SpA', '76.123.456-7',
    'https://portal.example.test', 'legacy-user', 'legacy-test-secret'
  ),
  (
    'a8082100-0001-4000-8000-000000000102',
    'a8082100-0000-4000-8000-000000000002',
    'Proveedor Base B', 'Proveedor Base B SpA', null,
    null, null, null
  ),
  (
    'a8082100-0001-4000-8000-000000000103',
    'a8082100-0000-4000-8000-000000000001',
    'Proveedor URL legado', null, null,
    'https://user:password@example.test/path?token=redacted#fragment',
    'dirty-user', 'dirty-test-secret'
  ),
  (
    'a8082100-0001-4000-8000-000000000104',
    'a8082100-0000-4000-8000-000000000001',
    'Proveedor Inactivo', null, null,
    'https://inactive.example.test', 'inactive-user', 'inactive-secret'
  ),
  (
    'a8082100-0001-4000-8000-000000000105',
    'a8082100-0000-4000-8000-000000000001',
    'Proveedor Puente RUT A', null, '11.111.111-1',
    null, null, null
  ),
  (
    'a8082100-0001-4000-8000-000000000106',
    'a8082100-0000-4000-8000-000000000001',
    'Proveedor Puente RUT B', null, '22.222.222-2',
    null, null, null
  ),
  (
    'a8082100-0001-4000-8000-0000000001b7',
    'a8082100-0000-4000-8000-000000000001',
    'Proveedor Usuario Sin Clave', null, null,
    'https://example.test/login?tenant=legacy',
    'username-only', null
  ),
  (
    'a8082100-0001-4000-8000-0000000001b8',
    'a8082100-0000-4000-8000-000000000001',
    'Proveedor Usuario Origen Exacto', null, null,
    'https://username-only.example.test',
    'origin-username-only', null
  ),
  (
    'a8082100-0001-4000-8000-0000000001b9',
    'a8082100-0000-4000-8000-000000000001',
    'Proveedor Backfill Usuario', null, null,
    'https://example.test/path', null, null
  );

update public.suppliers
set is_active = false
where id = 'a8082100-0001-4000-8000-000000000104';

select is(
  (
    select party_id from public.suppliers
    where id = 'a8082100-0001-4000-8000-000000000101'
  ),
  'a8082100-0001-4000-8000-000000000101'::uuid,
  'legacy-compatible supplier keeps durable relationship id'
);
select is(
  (
    select normalized_value
    from public.external_party_identifiers
    where tenant_id = 'a8082100-0000-4000-8000-000000000001'
      and party_id = 'a8082100-0001-4000-8000-000000000101'
      and identifier_kind = 'tax_id'
  ),
  '761234567',
  'formatted Chilean tax identifier is normalized server-side'
);
select is(
  (
    select origin_url
    from public.supplier_credentials
    where supplier_id = 'a8082100-0001-4000-8000-000000000103'
      and credential_key = 'default'
  ),
  null::text,
  'unsafe legacy URL is never copied into credential metadata'
);
select ok(
  exists (
    select 1
    from public.supplier_data_quality_candidates candidate
    where candidate.supplier_id = 'a8082100-0001-4000-8000-000000000103'
      and candidate.issue_code = 'legacy_portal_origin_not_canonical'
      and candidate.status = 'pending'
      and candidate.metadata::text not ilike '%password%'
      and candidate.metadata::text not ilike '%token=%'
  ),
  'unsafe legacy URL creates a secret-free server validation incident'
);
select ok(
  (
    select credential.username = 'username-only'
      and credential.vault_secret_id is null
      and credential.origin_url is null
    from public.supplier_credentials credential
    where credential.supplier_id =
      'a8082100-0001-4000-8000-0000000001b7'
      and credential.credential_kind = 'portal_password'
      and credential.credential_key = 'default'
  ),
  'legacy username-only portal state becomes metadata without a fake Vault secret or unsafe origin'
);
select is(
  public.get_supplier_credential_status(
    'a8082100-0000-4000-8000-000000000001',
    'a8082100-0001-4000-8000-0000000001b7'
  )->'credentials'->0->>'has_secret',
  'false',
  'canonical credential status distinguishes username-only metadata from a stored secret'
);
select throws_ok(
  $$select public.get_supplier_credential_v2(
    'a8082100-0000-4000-8000-000000000001',
    'a8082100-0001-4000-8000-0000000001b7',
    'portal_password', 'default'
  )$$,
  'P0002',
  'Supplier credential not found',
  'credential reveal fails closed while metadata has no Vault secret'
);
select ok(
  exists (
    select 1
    from public.supplier_data_quality_candidates candidate
    where candidate.supplier_id =
      'a8082100-0001-4000-8000-0000000001b7'
      and candidate.issue_code = 'legacy_portal_origin_not_canonical'
      and candidate.status = 'pending'
  ),
  'username-only backfill opens the non-canonical-origin review issue'
);
select throws_ok(
  $$insert into public.supplier_credentials (
      tenant_id, supplier_id, credential_kind, credential_key,
      label, username, vault_secret_id
    ) values (
      'a8082100-0000-4000-8000-000000000001',
      'a8082100-0001-4000-8000-0000000001b7',
      'api_token', 'invalid_metadata_only',
      'Invalid', 'not-enough', null
    )$$,
  '23514',
  null,
  'metadata-only rows are rejected for non-portal credential kinds'
);
select throws_ok(
  $$insert into public.supplier_credentials (
      tenant_id, supplier_id, credential_kind, credential_key,
      label, username, vault_secret_id
    ) values (
      'a8082100-0000-4000-8000-000000000001',
      'a8082100-0001-4000-8000-0000000001b7',
      'portal_password', 'secondary',
      'Invalid', 'not-enough', null
    )$$,
  '23514',
  null,
  'metadata-only portal rows are rejected outside the canonical default key'
);
set local session_replication_role = replica;
update public.suppliers
set portal_username = 'backfill-username'
where id = 'a8082100-0001-4000-8000-0000000001b9';
set local session_replication_role = origin;
select is(
  public.backfill_supplier_username_only_credentials(),
  1,
  'username-only backfill copies a previously unbridged legacy row once'
);
select is(
  public.backfill_supplier_username_only_credentials(),
  0,
  'username-only backfill is idempotent on replay'
);
select ok(
  (
    select credential.username = 'backfill-username'
      and credential.vault_secret_id is null
      and credential.origin_url is null
    from public.supplier_credentials credential
    where credential.supplier_id =
      'a8082100-0001-4000-8000-0000000001b9'
      and credential.credential_kind = 'portal_password'
      and credential.credential_key = 'default'
  ) and exists (
    select 1
    from public.supplier_data_quality_candidates candidate
    where candidate.supplier_id =
      'a8082100-0001-4000-8000-0000000001b9'
      and candidate.issue_code = 'legacy_portal_origin_not_canonical'
      and candidate.status = 'pending'
  ),
  'backfill preserves username, rejects unsafe origin, and opens review'
);
select ok(
  (
    select lookup->>'match_status' = 'unique'
      and lookup->'match'->>'has_secret' = 'false'
      and lookup->'candidates'->0->>'has_secret' = 'false'
      and not (lookup->'match' ?| array['secret','username','vault_secret_id'])
    from (
      select public.find_supplier_credential_for_origin(
        'a8082100-0000-4000-8000-000000000001',
        'https://username-only.example.test',
        'portal_password'
      ) lookup
    ) result
  ),
  'exact-origin discovery publishes metadata-only state without exposing or claiming a secret'
);
select throws_ok(
  $$select public.get_supplier_credential_v2(
    'a8082100-0000-4000-8000-000000000001',
    'a8082100-0001-4000-8000-0000000001b8',
    'portal_password', 'default'
  )$$,
  'P0002',
  'Supplier credential not found',
  'exact-origin metadata-only discovery cannot be escalated into reveal'
);

update public.suppliers
set rut = '33.333.333-3'
where id = 'a8082100-0001-4000-8000-000000000105';
select is(
  (
    select normalized_value
    from public.external_party_identifiers
    where tenant_id = 'a8082100-0000-4000-8000-000000000001'
      and party_id = 'a8082100-0001-4000-8000-000000000105'
      and identifier_kind = 'tax_id'
      and valid_to is null
  ),
  '333333333',
  'legacy RUT update replaces the current canonical tax identifier'
);
select throws_ok(
  $$update public.suppliers
    set rut = '76.123.456-7'
    where id = 'a8082100-0001-4000-8000-000000000105'$$,
  '23505',
  'Tax identifier already belongs to another party',
  'legacy RUT bridge fails closed on cross-party collision'
);
select is(
  (
    select normalized_value
    from public.external_party_identifiers
    where tenant_id = 'a8082100-0000-4000-8000-000000000001'
      and party_id = 'a8082100-0001-4000-8000-000000000105'
      and identifier_kind = 'tax_id'
      and valid_to is null
  ),
  '333333333',
  'failed RUT collision leaves the canonical identifier unchanged'
);
update public.suppliers
set rut = null
where id = 'a8082100-0001-4000-8000-000000000105';
select is(
  (
    select count(*)
    from public.external_party_identifiers
    where tenant_id = 'a8082100-0000-4000-8000-000000000001'
      and party_id = 'a8082100-0001-4000-8000-000000000105'
      and identifier_kind = 'tax_id'
      and valid_to is null
  ),
  0::bigint,
  'legacy RUT clear closes or removes the current canonical identifier'
);

update public.external_party_identifiers
set valid_from = (select business_date from supplier_test_clock) - 10
where tenant_id = 'a8082100-0000-4000-8000-000000000001'
  and party_id = 'a8082100-0001-4000-8000-000000000106'
  and identifier_kind = 'tax_id'
  and normalized_value = '222222222'
  and valid_to is null;
update public.suppliers
set rut = '44.444.444-4'
where id = 'a8082100-0001-4000-8000-000000000106';
update public.suppliers
set rut = null
where id = 'a8082100-0001-4000-8000-000000000106';
update public.suppliers
set rut = '22.222.222-2'
where id = 'a8082100-0001-4000-8000-000000000106';
select is(
  (
    select count(*)
    from public.external_party_identifiers identifier
    where identifier.tenant_id = 'a8082100-0000-4000-8000-000000000001'
      and identifier.party_id = 'a8082100-0001-4000-8000-000000000106'
      and identifier.identifier_kind = 'tax_id'
      and identifier.normalized_value = '222222222'
  ),
  2::bigint,
  'reusing a historical RUT creates a new validity period instead of reopening the old row'
);
select ok(
  (
    select bool_and(not (
      daterange(
        left_period.valid_from,
        coalesce(left_period.valid_to, 'infinity'::date),
        '[]'
      ) && daterange(
        right_period.valid_from,
        coalesce(right_period.valid_to, 'infinity'::date),
        '[]'
      )
    ))
    from public.external_party_identifiers left_period
    join public.external_party_identifiers right_period
      on right_period.tenant_id = left_period.tenant_id
     and right_period.normalized_value = left_period.normalized_value
     and right_period.id > left_period.id
    where left_period.tenant_id = 'a8082100-0000-4000-8000-000000000001'
      and left_period.party_id = 'a8082100-0001-4000-8000-000000000106'
      and left_period.identifier_kind = 'tax_id'
      and left_period.normalized_value = '222222222'
  ),
  'historical RUT validity periods never overlap or invent continuity across a gap'
);

insert into public.business_sites (
  id, tenant_id, code, name, site_kind, is_active
) values
  (
    'a8082100-0002-4000-8000-000000000201',
    'a8082100-0000-4000-8000-000000000001',
    'LOCAL-1', 'Local 1', 'store', true
  ),
  (
    'a8082100-0002-4000-8000-000000000202',
    'a8082100-0000-4000-8000-000000000001',
    'CERRADO', 'Local cerrado', 'store', false
  );

insert into public.supplier_classification_candidates (
  id, tenant_id, supplier_id, source_kind, source_id, source_value,
  target_vocabulary, metadata
) values
  (
    'a8082100-0002-4000-8000-0000000002c1',
    'a8082100-0000-4000-8000-000000000001',
    'a8082100-0001-4000-8000-000000000101',
    'legacy_supplier_type',
    'a8082100-0001-4000-8000-000000000101',
    'legacy-bike-supplier',
    'role',
    '{"migration_source":"pgtap"}'::jsonb
  ),
  (
    'a8082100-0002-4000-8000-0000000002c2',
    'a8082100-0000-4000-8000-000000000002',
    'a8082100-0001-4000-8000-000000000102',
    'legacy_supplier_type',
    'a8082100-0001-4000-8000-000000000102',
    'legacy-other-tenant',
    'role',
    '{"migration_source":"pgtap"}'::jsonb
  ),
  (
    'a8082100-0002-4000-8000-0000000002c3',
    'a8082100-0000-4000-8000-000000000001',
    'a8082100-0001-4000-8000-000000000105',
    'legacy_supplier_type',
    'a8082100-0001-4000-8000-000000000105',
    'legacy-portal-capability',
    'capability',
    '{"migration_source":"pgtap"}'::jsonb
  ),
  (
    'a8082100-0002-4000-8000-0000000002c4',
    'a8082100-0000-4000-8000-000000000001',
    'a8082100-0001-4000-8000-000000000106',
    'legacy_supplier_type',
    'a8082100-0001-4000-8000-000000000106',
    'legacy-digital-tag',
    'tag',
    '{"migration_source":"pgtap"}'::jsonb
  ),
  (
    'a8082100-0002-4000-8000-0000000002c5',
    'a8082100-0000-4000-8000-000000000001',
    'a8082100-0001-4000-8000-000000000104',
    'legacy_supplier_type',
    'a8082100-0001-4000-8000-000000000104',
    'legacy-rejected-carrier',
    'role',
    '{"migration_source":"pgtap"}'::jsonb
  );

select set_config(
  'request.jwt.claims',
  '{"role":"authenticated","sub":"a8082100-0000-4000-8000-000000000092"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  'a8082100-0000-4000-8000-000000000092',
  true
);
set local role authenticated;
select throws_ok(
  $$select public.tenant_business_date(
    'a8082100-0000-4000-8000-000000000002'
  )$$,
  '42501',
  'Active tenant membership required',
  'tenant business date cannot probe another tenant timezone'
);
select throws_ok(
  $$insert into public.business_sites (
      id, tenant_id, code, name, site_kind, is_active
    ) values (
      'a8082100-0002-4000-8000-000000000203',
      'a8082100-0000-4000-8000-000000000001',
      'MEMBER-DENIED', 'Member denied', 'other', false
    )$$,
  '42501',
  null,
  'ordinary active tenant member cannot mutate shared business sites'
);
select throws_ok(
  $$update public.suppliers
    set party_id = 'a8082100-0001-4000-8000-000000000101'
    where id = 'a8082100-0001-4000-8000-000000000105'$$,
  '42501',
  null,
  'tenant member cannot bypass commands to forge a supplier party rebind'
);
reset role;

select set_config(
  'request.jwt.claims',
  '{"role":"authenticated","sub":"a8082100-0000-4000-8000-000000000091"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  'a8082100-0000-4000-8000-000000000091',
  true
);
set local role authenticated;
select lives_ok(
  $$insert into public.business_sites (
      id, tenant_id, code, name, site_kind, is_active
    ) values (
      'a8082100-0002-4000-8000-000000000204',
      'a8082100-0000-4000-8000-000000000001',
      'MANAGER-ALLOWED', 'Manager allowed', 'other', false
    )$$,
  'settings-authorized manager can mutate shared business sites'
);

create temporary table classification_definition_result (payload jsonb);
insert into classification_definition_result
select public.upsert_supplier_classification_definition_v2(
  'a8082100-0000-4000-8000-000000000001',
  'tag',
  '{"code":"preferred_partner","label":"Socio preferente","aliases":["preferente"],"metadata":{"source":"pgtap"}}'::jsonb,
  'a8082100-0200-4000-8000-000000000001',
  null
);
select ok(
  (
    select payload->>'action' = 'create'
      and payload->>'idempotent_replay' = 'false'
      and payload->'applied_definition'->>'code' = 'preferred_partner'
    from classification_definition_result
  ),
  'classification v2 creates tenant master data with an idempotent receipt'
);
select is(
  public.upsert_supplier_classification_definition_v2(
    'a8082100-0000-4000-8000-000000000001',
    'tag',
    '{"code":"preferred_partner","label":"Socio preferente","aliases":["preferente"],"metadata":{"source":"pgtap"}}'::jsonb,
    'a8082100-0200-4000-8000-000000000001',
    null
  )->>'idempotent_replay',
  'true',
  'lost-ack classification definition create replays its receipt'
);
select throws_ok(
  $$select public.upsert_supplier_classification_definition_v2(
    'a8082100-0000-4000-8000-000000000001',
    'tag',
    '{"code":"preferred_partner","label":"Payload distinto","metadata":{}}'::jsonb,
    'a8082100-0200-4000-8000-000000000001',
    null
  )$$,
  '23505',
  'Classification definition operation id was reused with different content',
  'classification operation id cannot be reused with another payload'
);
select throws_ok(
  $$select public.upsert_supplier_classification_definition_v2(
    'a8082100-0000-4000-8000-000000000001',
    'tag',
    '{"code":"preferred_partner","label":"Sin token","metadata":{}}'::jsonb,
    'a8082100-0200-4000-8000-000000000002',
    null
  )$$,
  '40001',
  'Classification definition changed concurrently',
  'classification definition update requires optimistic concurrency token'
);
create temporary table classification_definition_updated (payload jsonb);
insert into classification_definition_updated
select public.upsert_supplier_classification_definition_v2(
  'a8082100-0000-4000-8000-000000000001',
  'tag',
  '{"code":"preferred_partner","label":"Socio preferente actualizado","aliases":["preferente"],"metadata":{"source":"pgtap"}}'::jsonb,
  'a8082100-0200-4000-8000-000000000003',
  (
    select (payload->'applied_definition'->>'updated_at')::timestamptz
    from classification_definition_result
  )
);
select is(
  (select payload->>'action' from classification_definition_updated),
  'update',
  'classification definition update applies against the exact version'
);
select throws_ok(
  $$select public.upsert_supplier_classification_definition_v2(
    'a8082100-0000-4000-8000-000000000002',
    'tag',
    '{"code":"cross_tenant","label":"Cross tenant","metadata":{}}'::jsonb,
    'a8082100-0200-4000-8000-000000000004',
    null
  )$$,
  '42501',
  'Supplier classification authority required',
  'classification v2 rejects cross-tenant master-data mutation'
);
reset role;

select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select set_config('request.jwt.claim.sub', '', true);

-- -------------------------------------------------------------------------
-- Atomic identity/relationship command and server-owned attention
-- -------------------------------------------------------------------------

insert into public.supplier_relationship_roles (
  tenant_id, supplier_id, role_code, assignment_source, metadata
) values (
  'a8082100-0000-4000-8000-000000000001',
  'a8082100-0001-4000-8000-000000000101',
  'goods_vendor',
  'observed',
  '{"evidence":"legacy-bike-supplier"}'::jsonb
);

insert into public.supplier_relationship_capabilities (
  tenant_id, supplier_id, capability_code, assignment_source, metadata
) values (
  'a8082100-0000-4000-8000-000000000001',
  'a8082100-0001-4000-8000-000000000105',
  'credential_portal',
  'observed',
  '{"evidence":"legacy-portal-capability"}'::jsonb
);

insert into public.supplier_relationship_tags (
  tenant_id, supplier_id, tag_code, label, assignment_source, metadata
) values (
  'a8082100-0000-4000-8000-000000000001',
  'a8082100-0001-4000-8000-000000000106',
  'digital',
  'Digital',
  'observed',
  '{"evidence":"legacy-digital-tag"}'::jsonb
);

select is(
  (
    select valid_from
    from public.supplier_relationship_roles
    where tenant_id = 'a8082100-0000-4000-8000-000000000001'
      and supplier_id = 'a8082100-0001-4000-8000-000000000101'
      and role_code = 'goods_vendor'
  ),
  public.tenant_business_date(
    'a8082100-0000-4000-8000-000000000001'
  ),
  'omitted supplier assignment validity starts on the tenant business date'
);

create temporary table profile_before as
select updated_at
from public.suppliers
where id = 'a8082100-0001-4000-8000-000000000101';

select set_config(
  'request.jwt.claims',
  '{"role":"authenticated","sub":"a8082100-0000-4000-8000-000000000091"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  'a8082100-0000-4000-8000-000000000091',
  true
);

select is(
  (
    select status
    from public.supplier_classification_candidate_read_model
    where candidate_id = 'a8082100-0002-4000-8000-0000000002c1'
  ),
  'pending',
  'classification candidate queue publishes pending legacy mappings'
);
select ok(
  not (
    select relationship_roles @> '[{"code":"goods_vendor"}]'::jsonb
    from public.supplier_profile_read_model
    where supplier_id = 'a8082100-0001-4000-8000-000000000101'
  ),
  'observed evidence is excluded from the current editable profile projection'
);
create temporary table candidate_review_result (payload jsonb);
insert into candidate_review_result
select public.review_supplier_classification_candidate(
  'a8082100-0000-4000-8000-000000000001',
  'a8082100-0002-4000-8000-0000000002c1',
  'confirmed',
  'goods_vendor',
  'Verified by migration review'
);
select ok(
  (
    select payload->>'status' = 'confirmed'
      and payload->>'suggested_code' = 'goods_vendor'
      and payload->>'idempotent_replay' = 'false'
    from candidate_review_result
  ),
  'classification review confirms an active canonical definition'
);
select ok(
  (
    select payload->'applied_assignment'->>'assignment_source' = 'manual'
      and payload->'applied_assignment'->'metadata'
        @> '{"confirmed_from_assignment_source":"observed"}'::jsonb
    from candidate_review_result
  ),
  'candidate review is the atomic observed-to-manual promotion boundary'
);
select ok(
  exists (
    select 1
    from public.supplier_relationship_roles assignment
    where assignment.tenant_id = 'a8082100-0000-4000-8000-000000000001'
      and assignment.supplier_id = 'a8082100-0001-4000-8000-000000000101'
      and assignment.role_code = 'goods_vendor'
      and assignment.assignment_source = 'manual'
      and assignment.valid_to is null
      and assignment.metadata->>'classification_candidate_id'
        = 'a8082100-0002-4000-8000-0000000002c1'
  ),
  'candidate receipt and confirmed assignment retain a durable evidence link'
);
select is(
  public.review_supplier_classification_candidate(
    'a8082100-0000-4000-8000-000000000001',
    'a8082100-0002-4000-8000-0000000002c1',
    'confirmed',
    'goods_vendor',
    'Verified by migration review'
  )->>'idempotent_replay',
  'true',
  'same classification candidate review is an idempotent replay'
);
select throws_ok(
  $$select public.review_supplier_classification_candidate(
    'a8082100-0000-4000-8000-000000000001',
    'a8082100-0002-4000-8000-0000000002c1',
    'rejected',
    null,
    'Changed decision'
  )$$,
  '23514',
  'Supplier classification candidate was already reviewed',
  'a reviewed classification candidate cannot be changed by retry'
);
select is(
  (
    select suggested_label
    from public.supplier_classification_candidate_read_model
    where candidate_id = 'a8082100-0002-4000-8000-0000000002c1'
  ),
  'Proveedor de bienes',
  'classification queue resolves the confirmed canonical label server-side'
);
select is(
  public.review_supplier_classification_candidate(
    'a8082100-0000-4000-8000-000000000001',
    'a8082100-0002-4000-8000-0000000002c3',
    'confirmed',
    'credential_portal',
    'Verified portal capability'
  )->'applied_assignment'->>'assignment_source',
  'manual',
  'candidate review confirms an observed capability through the same boundary'
);
select is(
  public.review_supplier_classification_candidate(
    'a8082100-0000-4000-8000-000000000001',
    'a8082100-0002-4000-8000-0000000002c4',
    'confirmed',
    'digital',
    'Verified digital tag'
  )->'applied_assignment'->>'assignment_source',
  'manual',
  'candidate review confirms an observed tag through the same boundary'
);
select is(
  public.review_supplier_classification_candidate(
    'a8082100-0000-4000-8000-000000000001',
    'a8082100-0002-4000-8000-0000000002c5',
    'rejected',
    null,
    'Carrier inference rejected'
  )->>'status',
  'rejected',
  'rejected candidate records the decision without assigning a classification'
);
select ok(
  not exists (
    select 1
    from public.supplier_relationship_roles assignment
    where assignment.tenant_id = 'a8082100-0000-4000-8000-000000000001'
      and assignment.supplier_id = 'a8082100-0001-4000-8000-000000000104'
      and assignment.role_code = 'logistics_provider'
  ),
  'rejected classification candidate never creates a manual assignment'
);

create temporary table profile_result (payload jsonb);
insert into profile_result
select public.save_supplier_relationship_profile(
  'a8082100-0000-4000-8000-000000000001',
  'a8082100-0001-4000-8000-000000000101',
  (select updated_at from profile_before),
  jsonb_build_object(
    'operation_id', 'a8082100-0100-4000-8000-000000000001',
    'display_name', 'Proveedor Base A',
    'party_kind', 'organization',
    'tax_identifier', '76.123.456-7',
    'tax_country_code', 'CL',
    'website', 'https://portal.example.test',
    'party_metadata', jsonb_build_object('source', 'pgtap')
  ),
  '[{"code":"goods_vendor"},{"code":"service_provider"}]'::jsonb,
  '[{"code":"purchase_invoices"},{"code":"credential_portal"}]'::jsonb,
  '[{"code":"bike_industry"},{"code":"recurring"}]'::jsonb
);

select is(
  jsonb_array_length((select payload->'relationship_roles' from profile_result)),
  2,
  'profile command atomically returns multiple role assignments'
);
select is(
  (
    select (payload->>'effective_business_date')::date
    from profile_result
  ),
  public.tenant_business_date(
    'a8082100-0000-4000-8000-000000000001'
  ),
  'profile command returns the exact server-owned effective business date'
);
select ok(
  not exists (
    select 1
    from jsonb_array_elements(
      (select payload->'relationship_roles' from profile_result)
    ) assignment
    where nullif(assignment->>'id', '') is null
  ),
  'profile projection publishes real assignment ids'
);
select is(
  (
    select count(*)
    from public.external_party_identifiers
    where tenant_id = 'a8082100-0000-4000-8000-000000000001'
      and party_id = 'a8082100-0001-4000-8000-000000000101'
      and identifier_kind = 'tax_id'
  ),
  1::bigint,
  'profile save does not duplicate the normalized tax identifier'
);

select is(
  public.save_supplier_relationship_profile(
    'a8082100-0000-4000-8000-000000000001',
    'a8082100-0001-4000-8000-000000000101',
    (select updated_at from profile_before),
    jsonb_build_object(
      'operation_id', 'a8082100-0100-4000-8000-000000000001',
      'display_name', 'Proveedor Base A',
      'party_kind', 'organization',
      'tax_identifier', '76.123.456-7',
      'tax_country_code', 'CL',
      'website', 'https://portal.example.test',
      'party_metadata', jsonb_build_object('source', 'pgtap')
    ),
    '[{"code":"goods_vendor"},{"code":"service_provider"}]'::jsonb,
    '[{"code":"purchase_invoices"},{"code":"credential_portal"}]'::jsonb,
    '[{"code":"bike_industry"},{"code":"recurring"}]'::jsonb
  )->>'idempotent_replay',
  'true',
  'profile operation id replays without duplicating history'
);

select throws_ok(
  $$select public.save_supplier_relationship_profile(
    'a8082100-0000-4000-8000-000000000001',
    'a8082100-0001-4000-8000-000000000101',
    null,
    '{"operation_id":"a8082100-0100-4000-8000-000000000002","display_name":"Proveedor Base A"}'::jsonb,
    '[]'::jsonb, '[]'::jsonb, '[]'::jsonb
  )$$,
  '22023',
  'Expected supplier updated_at is required for update',
  'authenticated profile update cannot bypass optimistic concurrency'
);
select throws_ok(
  $$select public.save_supplier_relationship_profile(
    'a8082100-0000-4000-8000-000000000001',
    'a8082100-0001-4000-8000-000000000101',
    '2000-01-01 00:00:00+00'::timestamptz,
    '{"operation_id":"a8082100-0100-4000-8000-000000000003","display_name":"Proveedor Base A"}'::jsonb,
    '[]'::jsonb, '[]'::jsonb, '[]'::jsonb
  )$$,
  '40001',
  'Supplier profile changed concurrently',
  'stale profile update is rejected'
);
select throws_ok(
  $$select public.save_supplier_relationship_profile(
    'a8082100-0000-4000-8000-000000000001',
    'a8082100-0001-4000-8000-000000000102',
    now(),
    '{"operation_id":"a8082100-0100-4000-8000-000000000004","display_name":"Cross tenant"}'::jsonb,
    '[]'::jsonb, '[]'::jsonb, '[]'::jsonb
  )$$,
  'P0002',
  'Supplier not found in tenant',
  'profile command cannot cross tenant boundaries'
);
select throws_ok(
  $$select public.save_supplier_relationship_profile(
    'a8082100-0000-4000-8000-000000000001',
    'a8082100-0001-4000-8000-000000000101',
    (select updated_at from public.suppliers where id='a8082100-0001-4000-8000-000000000101'),
    '{"operation_id":"a8082100-0100-4000-8000-000000000005","display_name":"Proveedor Base A","party_metadata":{"nested":[{"credentialValue":"forbidden"}]}}'::jsonb,
    '[{"code":"goods_vendor"},{"code":"service_provider"}]'::jsonb,
    '[{"code":"purchase_invoices"},{"code":"credential_portal"}]'::jsonb,
    '[{"code":"bike_industry"},{"code":"recurring"}]'::jsonb
  )$$,
  '23514',
  null,
  'recursive metadata sanitizer blocks compact camelCase credential keys'
);

select lives_ok(
  $$select public.save_supplier_relationship_profile(
    'a8082100-0000-4000-8000-000000000001',
    'a8082100-0001-4000-8000-000000000103',
    (select updated_at from public.suppliers where id='a8082100-0001-4000-8000-000000000103'),
    jsonb_build_object(
      'operation_id','a8082100-0100-4000-8000-000000000006',
      'display_name','Proveedor URL legado',
      'website',(select website from public.suppliers where id='a8082100-0001-4000-8000-000000000103')
    ),
    '[]'::jsonb, '[]'::jsonb, '[{"code":"digital"}]'::jsonb
  )$$,
  'unchanged unsafe legacy website does not brick unrelated classification save'
);

create temporary table ocr_template_before as
select updated_at
from public.suppliers
where id = 'a8082100-0001-4000-8000-000000000101';
create temporary table ocr_template_result (payload jsonb);
insert into ocr_template_result
select public.update_supplier_ocr_template(
  'a8082100-0000-4000-8000-000000000001',
  'a8082100-0001-4000-8000-000000000101',
  (select updated_at from ocr_template_before),
  'a8082100-0110-4000-8000-000000000001',
  '{"enabled":true,"discount_parser":"anchoredTrailingNumeric"}'::jsonb
);
select ok(
  (
    select payload->>'idempotent_replay' = 'false'
      and payload->'ocr_template' =
        '{"enabled":true,"discount_parser":"anchoredTrailingNumeric"}'::jsonb
      and (payload->>'updated_at')::timestamptz >
        (select updated_at from ocr_template_before)
    from ocr_template_result
  ),
  'narrow OCR command applies and returns only canonical template state'
);
select is(
  public.update_supplier_ocr_template(
    'a8082100-0000-4000-8000-000000000001',
    'a8082100-0001-4000-8000-000000000101',
    (select updated_at from ocr_template_before),
    'a8082100-0110-4000-8000-000000000001',
    '{"enabled":true,"discount_parser":"anchoredTrailingNumeric"}'::jsonb
  )->>'idempotent_replay',
  'true',
  'lost-ack OCR update replays its durable receipt'
);
select throws_ok(
  $$select public.update_supplier_ocr_template(
    'a8082100-0000-4000-8000-000000000001',
    'a8082100-0001-4000-8000-000000000101',
    (select updated_at from ocr_template_before),
    'a8082100-0110-4000-8000-000000000001',
    '{"enabled":false,"discount_parser":"none"}'::jsonb
  )$$,
  '23505',
  'OCR template operation id was reused with different content',
  'OCR operation id cannot be reused with different content'
);
select throws_ok(
  $$select public.update_supplier_ocr_template(
    'a8082100-0000-4000-8000-000000000001',
    'a8082100-0001-4000-8000-000000000101',
    null,
    'a8082100-0110-4000-8000-000000000002',
    '{"enabled":false,"discount_parser":"none"}'::jsonb
  )$$,
  '22023',
  'Expected supplier updated_at is required for OCR template update',
  'authenticated OCR update requires optimistic concurrency'
);
select throws_ok(
  $$select public.update_supplier_ocr_template(
    'a8082100-0000-4000-8000-000000000001',
    'a8082100-0001-4000-8000-000000000101',
    (select updated_at from ocr_template_before),
    'a8082100-0110-4000-8000-000000000003',
    '{"enabled":false,"discount_parser":"none"}'::jsonb
  )$$,
  '40001',
  'Supplier changed concurrently',
  'stale OCR update cannot overwrite a newer supplier version'
);
select throws_ok(
  $$select public.update_supplier_ocr_template(
    'a8082100-0000-4000-8000-000000000001',
    'a8082100-0001-4000-8000-000000000102',
    now(),
    'a8082100-0110-4000-8000-000000000004',
    '{"enabled":false,"discount_parser":"none"}'::jsonb
  )$$,
  'P0002',
  'Supplier not found in tenant',
  'OCR command cannot cross tenant boundaries'
);
select throws_ok(
  $$select public.update_supplier_ocr_template(
    'a8082100-0000-4000-8000-000000000001',
    'a8082100-0001-4000-8000-000000000101',
    (select updated_at from public.suppliers
      where id='a8082100-0001-4000-8000-000000000101'),
    'a8082100-0110-4000-8000-000000000005',
    '{"enabled":true,"discount_parser":"none","extra":true}'::jsonb
  )$$,
  '22023',
  'OCR template requires only enabled and discount_parser',
  'OCR template rejects unknown fields'
);
select throws_ok(
  $$select public.update_supplier_ocr_template(
    'a8082100-0000-4000-8000-000000000001',
    'a8082100-0001-4000-8000-000000000101',
    (select updated_at from public.suppliers
      where id='a8082100-0001-4000-8000-000000000101'),
    'a8082100-0110-4000-8000-000000000006',
    '{"enabled":true,"discount_parser":"none","apiToken":"forbidden"}'::jsonb
  )$$,
  '22023',
  'OCR template must not contain sensitive keys',
  'OCR template rejects recursively sensitive keys before persistence'
);
select throws_ok(
  $$select public.update_supplier_ocr_template(
    'a8082100-0000-4000-8000-000000000001',
    'a8082100-0001-4000-8000-000000000101',
    (select updated_at from public.suppliers
      where id='a8082100-0001-4000-8000-000000000101'),
    'a8082100-0110-4000-8000-000000000007',
    '{"enabled":"yes","discount_parser":"floating"}'::jsonb
  )$$,
  '22023',
  'OCR template enabled and discount_parser are invalid',
  'OCR template rejects invalid boolean and parser enum values'
);

insert into public.supplier_relationship_roles (
  tenant_id, supplier_id, role_code, valid_from, valid_to,
  assignment_source
) values (
  'a8082100-0000-4000-8000-000000000001',
  'a8082100-0001-4000-8000-000000000101',
  'logistics_provider',
  (select business_date from supplier_test_clock) - 1,
  (select business_date from supplier_test_clock),
  'manual'
);
select ok(
  (
    select relationship_roles @> '[{"code":"logistics_provider"}]'::jsonb
    from public.supplier_profile_read_model
    where supplier_id = 'a8082100-0001-4000-8000-000000000101'
  ),
  'valid_to is inclusive on its final day'
);

select is(
  (
    select data_completeness_status
    from public.supplier_profile_read_model
    where supplier_id = 'a8082100-0001-4000-8000-000000000101'
  ),
  'known',
  'missing contact fields do not invent an incomplete-data warning'
);
select is(
  (
    select data_completeness_status
    from public.supplier_profile_read_model
    where supplier_id = 'a8082100-0001-4000-8000-000000000103'
  ),
  'partial',
  'pending server validation incident owns partial completeness'
);
select ok(
  (
    select validation_incidents @> '[{"code":"legacy_portal_origin_not_canonical","severity":"warning","scope_type":"credential","source":"domain_validation","status":"pending"}]'::jsonb
    from public.supplier_profile_read_model
    where supplier_id = 'a8082100-0001-4000-8000-000000000103'
  ),
  'profile publishes stable incident reason, scope, severity, source, and status'
);
select is(
  (
    select classification_status
    from public.supplier_profile_read_model
    where supplier_id = 'a8082100-0001-4000-8000-000000000101'
  ),
  'not_applicable',
  'no economic activity suppresses unclassified warning'
);
select is(
  (
    select count(*)
    from public.active_business_site_read_model
    where tenant_id = 'a8082100-0000-4000-8000-000000000001'
  ),
  1::bigint,
  'active site catalog excludes inactive sites'
);

-- -------------------------------------------------------------------------
-- Engagement and accounting version commands
-- -------------------------------------------------------------------------

create temporary table classification_before_engagement as
select
  jsonb_array_length(relationship_roles) as role_count,
  jsonb_array_length(relationship_capabilities) as capability_count
from public.supplier_profile_read_model
where supplier_id = 'a8082100-0001-4000-8000-000000000101';

create temporary table engagement_result (payload jsonb);
insert into engagement_result
select public.create_supplier_engagement(
  'a8082100-0000-4000-8000-000000000001',
  'a8082100-0001-4000-8000-000000000101',
  jsonb_build_object(
    'operation_id', 'a8082100-0200-4000-8000-000000000001',
    'site_id', 'a8082100-0002-4000-8000-000000000201',
    'engagement_kind', 'subscription',
    'code', 'PORTAL-MAIN',
    'name', 'Portal principal',
    'status', 'active',
    'starts_on', (select business_date from supplier_test_clock),
    'metadata', jsonb_build_object('owner', 'operations')
  ),
  jsonb_build_object(
    'effective_from', (select business_date from supplier_test_clock),
    'billing_cycle', 'free',
    'currency_code', 'CLP',
    'expected_amount', 0,
    'portal_url', 'https://portal.example.test/login',
    'terms', jsonb_build_object('plan', 'free')
  )
);

select is(
  (select payload->'applied_version'->>'billing_cycle' from engagement_result),
  'free',
  'engagement command creates a free initial version'
);
select throws_ok(
  $$select public.create_supplier_engagement(
    'a8082100-0000-4000-8000-000000000001',
    'a8082100-0001-4000-8000-000000000101',
    '{"operation_id":"a8082100-0200-4000-8000-0000000000d1","engagement_kind":"subscription","code":"PAST-DATE","name":"Past date","status":"active"}'::jsonb,
    jsonb_build_object(
      'effective_from',(select business_date - 1 from supplier_test_clock),
      'billing_cycle','free','terms','{}'::jsonb
    )
  )$$,
  '23514',
  'Engagement effective_from cannot precede tenant business date',
  'authenticated engagement creation cannot rewrite pre-business-date history'
);
select is(
  (
    select service_relationship_summary
    from public.supplier_profile_read_model
    where supplier_id = 'a8082100-0001-4000-8000-000000000101'
  ),
  'Portal principal · Local 1',
  'profile publishes active service relationship and site without client inference'
);
select is(
  public.create_supplier_engagement(
    'a8082100-0000-4000-8000-000000000001',
    'a8082100-0001-4000-8000-000000000101',
    jsonb_build_object(
      'operation_id', 'a8082100-0200-4000-8000-000000000001',
      'site_id', 'a8082100-0002-4000-8000-000000000201',
      'engagement_kind', 'subscription',
      'code', 'PORTAL-MAIN',
      'name', 'Portal principal',
      'status', 'active',
      'starts_on', (select business_date from supplier_test_clock),
      'metadata', jsonb_build_object('owner', 'operations')
    ),
    jsonb_build_object(
      'effective_from', (select business_date from supplier_test_clock),
      'billing_cycle', 'free',
      'currency_code', 'CLP',
      'expected_amount', 0,
      'portal_url', 'https://portal.example.test/login',
      'terms', jsonb_build_object('plan', 'free')
    )
  )->>'idempotent_replay',
  'true',
  'engagement create operation is idempotent'
);

create temporary table engagement_v2 (payload jsonb);
insert into engagement_v2
select public.append_supplier_engagement_version(
  'a8082100-0000-4000-8000-000000000001',
  ((select payload->'engagement'->>'id' from engagement_result))::uuid,
  (select business_date from supplier_test_clock) + 10,
  jsonb_build_object(
    'operation_id', 'a8082100-0200-4000-8000-000000000002',
    'billing_cycle', 'monthly',
    'currency_code', 'CLP',
    'expected_amount', 10000,
    'portal_url', 'https://portal.example.test/login',
    'terms', jsonb_build_object('plan', 'paid')
  )
);
select ok(
  (
    select
      jsonb_array_length(profile.relationship_roles) = before.role_count
      and jsonb_array_length(profile.relationship_capabilities)
        = before.capability_count
    from public.supplier_profile_read_model profile
    cross join classification_before_engagement before
    where profile.supplier_id = 'a8082100-0001-4000-8000-000000000101'
  ),
  'free-to-monthly engagement mutation does not change roles or capabilities'
);
create temporary table engagement_v3 (payload jsonb);
insert into engagement_v3
select public.append_supplier_engagement_version(
  'a8082100-0000-4000-8000-000000000001',
  ((select payload->'engagement'->>'id' from engagement_result))::uuid,
  (select business_date from supplier_test_clock) + 20,
  jsonb_build_object(
    'operation_id', 'a8082100-0200-4000-8000-000000000003',
    'billing_cycle', 'annual',
    'currency_code', 'CLP',
    'expected_amount', 100000,
    'portal_url', 'https://portal.example.test/login',
    'terms', jsonb_build_object('plan', 'annual')
  )
);
select ok(
  (
    select replay->'applied_version'->>'version_number' = '2'
      and replay->'current_version'->>'version_number' = '3'
    from (
      select public.append_supplier_engagement_version(
        'a8082100-0000-4000-8000-000000000001',
        ((select payload->'engagement'->>'id' from engagement_result))::uuid,
        (select business_date from supplier_test_clock) + 10,
        jsonb_build_object(
          'operation_id', 'a8082100-0200-4000-8000-000000000002',
          'billing_cycle', 'monthly',
          'currency_code', 'CLP',
          'expected_amount', 10000,
          'portal_url', 'https://portal.example.test/login',
          'terms', jsonb_build_object('plan', 'paid')
        )
      ) replay
    ) result
  ),
  'historical replay distinguishes applied from actual current version'
);
select throws_ok(
  $$select public.append_supplier_engagement_version(
    'a8082100-0000-4000-8000-000000000001',
    ((select payload->'engagement'->>'id' from engagement_result))::uuid,
    (select business_date - 1 from supplier_test_clock),
    '{"operation_id":"a8082100-0200-4000-8000-0000000000d2","billing_cycle":"free","terms":{}}'::jsonb
  )$$,
  '23514',
  'Engagement effective_from cannot precede tenant business date',
  'authenticated engagement append cannot backdate before the tenant business day'
);
select is(
  (
    select effective_to
    from public.supplier_engagement_versions
    where id = ((select payload->'applied_version'->>'id' from engagement_result))::uuid
  ),
  (select business_date from supplier_test_clock) + 9,
  'version close uses an inclusive final date'
);
select throws_ok(
  $$select public.update_supplier_engagement_shell(
    'a8082100-0000-4000-8000-000000000001',
    ((select payload->'engagement'->>'id' from engagement_result))::uuid,
    null,
    '{"name":"stale overwrite"}'::jsonb
  )$$,
  '22023',
  'Expected engagement updated_at is required for update',
  'engagement shell cannot bypass optimistic concurrency'
);
select throws_ok(
  $$select public.create_supplier_engagement(
    'a8082100-0000-4000-8000-000000000001',
    'a8082100-0001-4000-8000-000000000101',
    '{"operation_id":"a8082100-0200-4000-8000-000000000004","engagement_kind":"portal","code":"BAD-URL","name":"Bad URL","status":"active"}'::jsonb,
    jsonb_build_object(
      'effective_from', (select business_date from supplier_test_clock),
      'billing_cycle', 'free',
      'portal_url', 'https://user:pass@example.test/path?token=x'
    )
  )$$,
  '23514',
  null,
  'portal URL rejects userinfo and secret-bearing query strings'
);

create temporary table policy_result (payload jsonb);
insert into policy_result
select public.create_supplier_accounting_policy(
  'a8082100-0000-4000-8000-000000000001',
  'a8082100-0001-4000-8000-000000000101',
  jsonb_build_object(
    'operation_id', 'a8082100-0300-4000-8000-000000000001',
    'engagement_id', (select payload->'engagement'->>'id' from engagement_result),
    'code', 'DIGITAL-SERVICE',
    'name', 'Servicio digital',
    'status', 'active',
    'priority', 10,
    'allow_exact_autofill', false
  ),
  jsonb_build_object(
    'effective_from', (select business_date from supplier_test_clock),
    'operational_nature_code', 'digital_services',
    'tax_treatment', 'tax_included',
    'currency_code', 'CLP',
    'line_nature', 'service',
    'posture', jsonb_build_object('review', 'human')
  ),
  '[{"rule_kind":"description","operator":"contains","operand":{"text":"workspace"},"priority":10,"is_active":true}]'::jsonb
);

select is(
  (select payload->'applied_version'->>'operational_nature_code' from policy_result),
  'digital_services',
  'policy command owns canonical operational nature'
);
select throws_ok(
  $$select public.create_supplier_accounting_policy(
    'a8082100-0000-4000-8000-000000000001',
    'a8082100-0001-4000-8000-000000000101',
    '{"operation_id":"a8082100-0300-4000-8000-0000000000d1","code":"PAST-POLICY","name":"Past policy","status":"active"}'::jsonb,
    jsonb_build_object(
      'effective_from',(select business_date - 1 from supplier_test_clock),
      'operational_nature_code','digital_services','posture','{}'::jsonb
    ),
    '[]'::jsonb
  )$$,
  '23514',
  'Policy effective_from cannot precede tenant business date',
  'authenticated policy creation cannot rewrite pre-business-date history'
);
select is(
  jsonb_array_length((select payload->'rules' from policy_result)),
  1,
  'policy command inserts matching rules atomically'
);
select throws_ok(
  $$select public.update_supplier_accounting_policy_shell(
    'a8082100-0000-4000-8000-000000000001',
    ((select payload->'policy'->>'id' from policy_result))::uuid,
    null,
    '{"name":"stale overwrite"}'::jsonb
  )$$,
  '22023',
  'Expected policy updated_at is required for update',
  'policy shell cannot bypass optimistic concurrency'
);

create temporary table policy_v2 (payload jsonb);
insert into policy_v2
select public.append_supplier_accounting_policy_version(
  'a8082100-0000-4000-8000-000000000001',
  ((select payload->'policy'->>'id' from policy_result))::uuid,
  (select business_date from supplier_test_clock) + 10,
  jsonb_build_object(
    'operation_id', 'a8082100-0300-4000-8000-000000000002',
    'operational_nature_code', 'professional_services',
    'tax_treatment', 'tax_included',
    'currency_code', 'CLP',
    'line_nature', 'service',
    'posture', jsonb_build_object('review', 'human')
  ),
  '[{"rule_kind":"description","operator":"contains","operand":{"text":"consulting"},"priority":10,"is_active":true}]'::jsonb
);
select is(
  (
    select effective_to
    from public.supplier_accounting_policy_versions
    where id = ((select payload->'applied_version'->>'id' from policy_result))::uuid
  ),
  (select business_date from supplier_test_clock) + 9,
  'policy version history closes inclusively'
);
select throws_ok(
  $$select public.append_supplier_accounting_policy_version(
    'a8082100-0000-4000-8000-000000000001',
    ((select payload->'policy'->>'id' from policy_result))::uuid,
    (select business_date - 1 from supplier_test_clock),
    '{"operation_id":"a8082100-0300-4000-8000-0000000000d2","operational_nature_code":"digital_services","posture":{}}'::jsonb,
    '[]'::jsonb
  )$$,
  '23514',
  'Policy effective_from cannot precede tenant business date',
  'authenticated policy append cannot backdate before the tenant business day'
);

create temporary table accounting_rule_matrix_result (payload jsonb);
insert into accounting_rule_matrix_result
select public.insert_supplier_accounting_rules_internal(
  'a8082100-0000-4000-8000-000000000001',
  ((select payload->'applied_version'->>'id' from policy_v2))::uuid,
  jsonb_build_array(
    jsonb_build_object(
      'rule_kind','document_type','operator','equals',
      'operand',jsonb_build_object('document_type',' 33 '),'priority',0
    ),
    jsonb_build_object(
      'rule_kind','issuer_identifier','operator','equals',
      'operand',jsonb_build_object('identifier','76.123.456-7')
    ),
    jsonb_build_object(
      'rule_kind','description','operator','regex',
      'operand',jsonb_build_object('text','^consult')
    ),
    jsonb_build_object(
      'rule_kind','line_description','operator','prefix',
      'operand',jsonb_build_object('text','Servicio')
    ),
    jsonb_build_object(
      'rule_kind','engagement','operator','equals',
      'operand',jsonb_build_object(
        'engagement_id',(
          select payload->'engagement'->>'id' from engagement_result
        )
      )
    ),
    jsonb_build_object(
      'rule_kind','amount_range','operator','between',
      'operand',jsonb_build_object('min',-10,'max',0),'priority',10000
    ),
    jsonb_build_object(
      'rule_kind','manual','operator','present','operand','{}'::jsonb
    )
  )
);
select is(
  jsonb_array_length((select payload from accounting_rule_matrix_result)),
  7,
  'closed accounting-rule matrix accepts every supported canonical shape'
);
select ok(
  (
    select payload @> '[
      {"rule_kind":"document_type","operator":"equals","operand":{"document_type":"33"}},
      {"rule_kind":"issuer_identifier","operator":"equals","operand":{"identifier":"761234567"}},
      {"rule_kind":"amount_range","operator":"between","operand":{"min":-10,"max":0}},
      {"rule_kind":"manual","operator":"present","operand":{}}
    ]'::jsonb
    from accounting_rule_matrix_result
  ),
  'accounting-rule operands are canonicalized without changing valid numeric boundaries'
);
select throws_ok(
  $$select public.update_supplier_accounting_policy_shell(
    'a8082100-0000-4000-8000-000000000001',
    ((select payload->'policy'->>'id' from policy_result))::uuid,
    (
      select updated_at
      from public.supplier_accounting_policies
      where id = ((
        select payload->'policy'->>'id' from policy_result
      ))::uuid
    ),
    '{"allow_exact_autofill":true}'::jsonb
  )$$,
  '23514',
  'Manual accounting rules are incompatible with exact autofill',
  'policy shell cannot enable exact autofill over an existing manual gate'
);
select throws_ok(
  $$select public.insert_supplier_accounting_rules_internal(
    'a8082100-0000-4000-8000-000000000001',
    ((select payload->'applied_version'->>'id' from policy_v2))::uuid,
    '[{"rule_kind":"document_type","operator":"contains","operand":{"document_type":"33"}}]'::jsonb
  )$$,
  '22023',
  'Unsupported accounting rule kind and operator combination',
  'document type rejects a non-exact operator'
);
select throws_ok(
  $$select public.insert_supplier_accounting_rules_internal(
    'a8082100-0000-4000-8000-000000000001',
    ((select payload->'applied_version'->>'id' from policy_v2))::uuid,
    '[{"rule_kind":"description","operator":"contains","operand":{"text":"workspace","extra":true}}]'::jsonb
  )$$,
  '22023',
  'Text accounting rule requires only a nonblank text operand',
  'text rule rejects unknown operand fields'
);
select throws_ok(
  $$select public.insert_supplier_accounting_rules_internal(
    'a8082100-0000-4000-8000-000000000001',
    ((select payload->'applied_version'->>'id' from policy_v2))::uuid,
    '[{"rule_kind":"description","operator":"equals","operand":{"password":"forbidden"}}]'::jsonb
  )$$,
  '22023',
  'Accounting rule operand must be a secret-free object',
  'accounting rule rejects recursively sensitive operand keys'
);
select throws_ok(
  $$select public.insert_supplier_accounting_rules_internal(
    'a8082100-0000-4000-8000-000000000001',
    ((select payload->'applied_version'->>'id' from policy_v2))::uuid,
    '[{"rule_kind":"line_description","operator":"prefix","operand":{"text":"   "}}]'::jsonb
  )$$,
  '22023',
  'Text accounting rule requires only a nonblank text operand',
  'accounting rule rejects empty required text'
);
select throws_ok(
  $$select public.insert_supplier_accounting_rules_internal(
    'a8082100-0000-4000-8000-000000000001',
    ((select payload->'applied_version'->>'id' from policy_v2))::uuid,
    '[{"rule_kind":"description","operator":"regex","operand":{"text":"["}}]'::jsonb
  )$$,
  '22023',
  'Accounting rule regex is invalid',
  'regex rule validates syntax without claiming an evaluator exists'
);
select throws_ok(
  $$select public.insert_supplier_accounting_rules_internal(
    'a8082100-0000-4000-8000-000000000001',
    ((select payload->'applied_version'->>'id' from policy_v2))::uuid,
    '[{"rule_kind":"amount_range","operator":"between","operand":{"min":10,"max":9}}]'::jsonb
  )$$,
  '22023',
  'amount_range minimum cannot exceed maximum',
  'amount range rejects inverted bounds'
);
select throws_ok(
  $$select public.insert_supplier_accounting_rules_internal(
    'a8082100-0000-4000-8000-000000000001',
    ((select payload->'applied_version'->>'id' from policy_v2))::uuid,
    '[{"rule_kind":"engagement","operator":"equals","operand":{"engagement_id":"a8082100-0999-4000-8000-000000000999"}}]'::jsonb
  )$$,
  '23503',
  'Accounting rule engagement must belong to the policy supplier',
  'engagement rule rejects an unowned relationship context'
);
select throws_ok(
  $$select public.insert_supplier_accounting_rules_internal(
    'a8082100-0000-4000-8000-000000000001',
    ((select payload->'applied_version'->>'id' from policy_v2))::uuid,
    '[{"rule_kind":"manual","operator":"present","operand":{},"unexpected":true}]'::jsonb
  )$$,
  '22023',
  'Accounting rule contains unsupported fields',
  'accounting rule rejects unknown top-level fields'
);
select throws_ok(
  $$select public.create_supplier_accounting_policy(
    'a8082100-0000-4000-8000-000000000001',
    'a8082100-0001-4000-8000-000000000101',
    '{"operation_id":"a8082100-0300-4000-8000-0000000000a1","code":"AUTO-MANUAL","name":"Invalid autofill manual","status":"draft","allow_exact_autofill":true}'::jsonb,
    jsonb_build_object(
      'effective_from',public.tenant_business_date('a8082100-0000-4000-8000-000000000001'),
      'operational_nature_code','digital_services','posture','{}'::jsonb
    ),
    '[{"rule_kind":"manual","operator":"present","operand":{}}]'::jsonb
  )$$,
  '23514',
  'Manual accounting rules are incompatible with exact autofill',
  'exact autofill rejects any rule set that requires a human gate'
);

select throws_ok(
  $$select public.create_supplier_accounting_policy(
    'a8082100-0000-4000-8000-000000000001',
    'a8082100-0001-4000-8000-000000000102',
    jsonb_build_object(
      'operation_id','a8082100-0300-4000-8000-000000000003',
      'engagement_id',(select payload->'engagement'->>'id' from engagement_result),
      'code','CROSS','name','Cross supplier','status','active'
    ),
    jsonb_build_object(
      'effective_from',(select business_date from supplier_test_clock),
      'operational_nature_code','digital_services',
      'posture','{}'::jsonb
    ),
    '[]'::jsonb
  )$$,
  'P0002',
  'Supplier not found in tenant',
  'policy command rejects a supplier outside tenant before linking engagement'
);

create temporary table evidence_result (payload jsonb);
insert into evidence_result
select public.append_supplier_accounting_evidence(
  'a8082100-0000-4000-8000-000000000001',
  'a8082100-0001-4000-8000-000000000101',
  jsonb_build_object(
    'operation_id', 'a8082100-0300-4000-8000-000000000090',
    'policy_version_id', (select payload->'applied_version'->>'id' from policy_result),
    'rule_id', (select payload->'rules'->0->>'id' from policy_result),
    'source_type', 'manual',
    'source_id', 'a8082100-0300-4000-8000-000000000099',
    'decision', 'accepted',
    'operational_nature_code', 'digital_services',
    'rationale', 'Clasificación confirmada por pgTAP',
    'evidence', jsonb_build_object('fixture', true),
    'applied_by', 'a8082100-0000-4000-8000-000000000092',
    'applied_at', '2000-01-01T00:00:00Z'
  )
);
select is(
  ((select payload->>'applied_by' from evidence_result))::uuid,
  'a8082100-0000-4000-8000-000000000091'::uuid,
  'evidence RPC stamps actor instead of trusting payload'
);
select is(
  (select payload->>'operational_nature_label' from evidence_result),
  'Servicios digitales',
  'evidence snapshots canonical operational-nature label'
);
select ok(
  (select (payload->>'applied_at')::timestamptz > '2026-01-01'::timestamptz from evidence_result),
  'evidence RPC stamps server time'
);
select is(
  public.append_supplier_accounting_evidence(
    'a8082100-0000-4000-8000-000000000001',
    'a8082100-0001-4000-8000-000000000101',
    jsonb_build_object(
      'operation_id', 'a8082100-0300-4000-8000-000000000090',
      'policy_version_id', (select payload->'applied_version'->>'id' from policy_result),
      'rule_id', (select payload->'rules'->0->>'id' from policy_result),
      'source_type', 'manual',
      'source_id', 'a8082100-0300-4000-8000-000000000099',
      'decision', 'accepted',
      'operational_nature_code', 'digital_services',
      'rationale', 'Clasificación confirmada por pgTAP',
      'evidence', jsonb_build_object('fixture', true),
      'applied_by', 'a8082100-0000-4000-8000-000000000092',
      'applied_at', '2000-01-01T00:00:00Z'
    )
  )->>'idempotent_replay',
  'true',
  'evidence operation replay does not duplicate append-only history'
);
select throws_ok(
  $$select public.append_supplier_accounting_evidence(
    'a8082100-0000-4000-8000-000000000001',
    'a8082100-0001-4000-8000-000000000101',
    '{"operation_id":"a8082100-0300-4000-8000-000000000090","source_type":"manual","source_id":"a8082100-0300-4000-8000-000000000099","decision":"rejected","operational_nature_code":"digital_services"}'::jsonb
  )$$,
  '23505',
  'Accounting evidence operation id was reused with different content',
  'evidence operation id cannot be reused with different content'
);
select throws_ok(
  $$select public.append_supplier_accounting_evidence(
    'a8082100-0000-4000-8000-000000000001',
    'a8082100-0001-4000-8000-000000000101',
    '{"operation_id":"a8082100-0300-4000-8000-000000000091","source_type":"manual","source_id":"a8082100-0300-4000-8000-000000000098","decision":"auto_filled","operational_nature_code":"digital_services"}'::jsonb
  )$$,
  '22023',
  'Unsupported evidence decision',
  'human evidence command reserves auto_filled for a future evaluator'
);
select throws_ok(
  $$select public.append_supplier_accounting_evidence(
    'a8082100-0000-4000-8000-000000000001',
    'a8082100-0001-4000-8000-000000000103',
    jsonb_build_object(
      'operation_id','a8082100-0300-4000-8000-000000000092',
      'policy_version_id',(select payload->'applied_version'->>'id' from policy_result),
      'rule_id',(select payload->'rules'->0->>'id' from policy_result),
      'source_type','manual',
      'source_id','a8082100-0300-4000-8000-000000000097',
      'decision','accepted',
      'operational_nature_code','digital_services'
    )
  )$$,
  '23514',
  'Accounting policy version does not belong to supplier',
  'evidence validates supplier-policy-rule chain'
);

set local role authenticated;
select throws_ok(
  $$insert into public.supplier_accounting_evidence (
    tenant_id,supplier_id,source_type,source_id,decision,
    operational_nature_code,operational_nature_label,evidence,applied_by
  ) values (
    'a8082100-0000-4000-8000-000000000001',
    'a8082100-0001-4000-8000-000000000101',
    'manual','a8082100-0300-4000-8000-000000000096','accepted',
    'digital_services','forged','{}'::jsonb,
    'a8082100-0000-4000-8000-000000000092'
  )$$,
  '42501',
  null,
  'direct client evidence insert is denied'
);
select throws_ok(
  $$update public.supplier_engagement_versions
    set expected_amount=1
    where id=((select payload->'applied_version'->>'id' from engagement_result))::uuid$$,
  '42501',
  null,
  'client cannot mutate engagement history directly'
);
reset role;

-- -------------------------------------------------------------------------
-- Multi-account Vault credentials, exact-origin discovery, and audit
-- -------------------------------------------------------------------------

select public.upsert_supplier_credential_v2(
  'a8082100-0000-4000-8000-000000000001',
  'a8082100-0001-4000-8000-000000000105',
  'api_token', 'default',
  'a8082100-0400-4000-8000-0000000000b1',
  null, null, null, 'API principal', null,
  'api-token-only-secret', false, false
);
select set_config(
  'request.jwt.claims',
  '{"role":"authenticated","sub":"a8082100-0000-4000-8000-000000000091"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  'a8082100-0000-4000-8000-000000000091',
  true
);
set local role authenticated;
select ok(
  (
    select profile.has_credential_reference
      and not profile.has_portal_credential
    from public.supplier_profile_read_model profile
    where profile.supplier_id =
      'a8082100-0001-4000-8000-000000000105'
  ),
  'api-token-only supplier is visible as credential-backed without claiming a portal credential'
);
reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select set_config('request.jwt.claim.sub', '', true);

create temporary table username_only_promoted (payload jsonb);
insert into username_only_promoted
select public.upsert_supplier_credential_v2(
  'a8082100-0000-4000-8000-000000000001',
  'a8082100-0001-4000-8000-0000000001b7',
  'portal_password', 'default',
  'a8082100-0400-4000-8000-0000000000b2',
  (
    select updated_at
    from public.supplier_credentials
    where supplier_id = 'a8082100-0001-4000-8000-0000000001b7'
      and credential_kind = 'portal_password'
      and credential_key = 'default'
  ),
  null, null, 'Portal principal', 'username-only',
  'username-only-real-secret', false, false
);
select is(
  (select payload->>'has_secret' from username_only_promoted),
  'true',
  'v2 atomically attaches Vault when a metadata-only credential receives a real secret'
);
select is(
  public.get_supplier_credential_v2(
    'a8082100-0000-4000-8000-000000000001',
    'a8082100-0001-4000-8000-0000000001b7',
    'portal_password', 'default'
  )->>'secret',
  'username-only-real-secret',
  'promoted username-only credential reveals the exact newly stored secret'
);

update public.suppliers
set portal_password = null
where id = 'a8082100-0001-4000-8000-0000000001b7';
select ok(
  (
    select credential.username = 'username-only'
      and credential.vault_secret_id is null
    from public.supplier_credentials credential
    where credential.supplier_id =
      'a8082100-0001-4000-8000-0000000001b7'
      and credential.credential_kind = 'portal_password'
      and credential.credential_key = 'default'
  ),
  'legacy password removal retains username metadata and removes only the Vault secret'
);
select throws_ok(
  $$select public.get_supplier_credential_v2(
    'a8082100-0000-4000-8000-000000000001',
    'a8082100-0001-4000-8000-0000000001b7',
    'portal_password', 'default'
  )$$,
  'P0002',
  'Supplier credential not found',
  'reveal fails closed again after the legacy bridge removes the secret'
);
select ok(
  (
    select replay->>'idempotent_replay' = 'true'
      and replay->>'has_secret' = 'false'
      and replay->'applied_credential'->>'has_secret' = 'true'
      and replay->'current_credential'->>'has_secret' = 'false'
    from (
      select public.upsert_supplier_credential_v2(
        'a8082100-0000-4000-8000-000000000001',
        'a8082100-0001-4000-8000-0000000001b7',
        'portal_password', 'default',
        'a8082100-0400-4000-8000-0000000000b2',
        (
          select receipt.expected_updated_at
          from public.supplier_credential_command_receipts receipt
          where receipt.tenant_id =
            'a8082100-0000-4000-8000-000000000001'
            and receipt.operation_id =
              'a8082100-0400-4000-8000-0000000000b2'
        ),
        null, null, 'Portal principal', 'username-only',
        'username-only-real-secret', false, false
      ) replay
    ) result
  ),
  'upsert replay preserves the historical applied secret while publishing current metadata-only state'
);

update public.suppliers
set portal_username = 'username-only-b'
where id = 'a8082100-0001-4000-8000-0000000001b7';
update public.suppliers
set portal_username = 'username-only'
where id = 'a8082100-0001-4000-8000-0000000001b7';
select is(
  (
    select username
    from public.supplier_credentials
    where supplier_id = 'a8082100-0001-4000-8000-0000000001b7'
      and credential_kind = 'portal_password'
      and credential_key = 'default'
  ),
  'username-only',
  'legacy username-only A-to-B-to-A transitions preserve the exact newest metadata'
);

create temporary table username_only_deleted (payload jsonb);
insert into username_only_deleted
select public.delete_supplier_credential_v2(
  'a8082100-0000-4000-8000-000000000001',
  'a8082100-0001-4000-8000-0000000001b7',
  'portal_password', 'default',
  'a8082100-0400-4000-8000-0000000000b3',
  (
    select updated_at
    from public.supplier_credentials
    where supplier_id = 'a8082100-0001-4000-8000-0000000001b7'
      and credential_kind = 'portal_password'
      and credential_key = 'default'
  )
);
select is(
  (select payload->>'deleted' from username_only_deleted),
  'true',
  'v2 delete removes a metadata-only credential without requiring a Vault row'
);
update public.suppliers
set portal_username = 'username-only'
where id = 'a8082100-0001-4000-8000-0000000001b7';
select is(
  public.get_supplier_credential_status(
    'a8082100-0000-4000-8000-000000000001',
    'a8082100-0001-4000-8000-0000000001b7'
  )->'credentials'->0->>'has_secret',
  'false',
  'legacy bridge recreates an explicitly deleted username-only metadata row without a fake secret'
);
select ok(
  (
    select replay->>'idempotent_replay' = 'true'
      and replay->>'has_secret' = 'false'
      and replay->'current_credential'->>'has_secret' = 'false'
    from (
      select public.delete_supplier_credential_v2(
        'a8082100-0000-4000-8000-000000000001',
        'a8082100-0001-4000-8000-0000000001b7',
        'portal_password', 'default',
        'a8082100-0400-4000-8000-0000000000b3',
        ((
          select payload->'tombstone'->>'previous_updated_at'
          from username_only_deleted
        ))::timestamptz
      ) replay
    ) result
  ),
  'delete replay after username-only recreation reports the current metadata as secret-free'
);

update public.suppliers
set portal_username = 'legacy-aba-user',
    portal_password = 'legacy-aba-a'
where id = 'a8082100-0001-4000-8000-000000000106';
update public.suppliers
set portal_password = 'legacy-aba-b'
where id = 'a8082100-0001-4000-8000-000000000106';
update public.suppliers
set portal_password = 'legacy-aba-a'
where id = 'a8082100-0001-4000-8000-000000000106';
select is(
  public.get_supplier_credential_v2(
    'a8082100-0000-4000-8000-000000000001',
    'a8082100-0001-4000-8000-000000000106',
    'portal_password', 'default'
  )->>'secret',
  'legacy-aba-a',
  'legacy A-to-B-to-A transition restores the exact newest Vault generation'
);
select is(
  (
    select count(*)
    from public.supplier_credential_command_receipts receipt
    where receipt.supplier_id =
      'a8082100-0001-4000-8000-000000000106'
      and receipt.command_kind = 'upsert'
  ),
  3::bigint,
  'each actual legacy A-to-B-to-A transition owns a distinct upsert receipt'
);
update public.suppliers
set portal_username = null,
    portal_password = null
where id = 'a8082100-0001-4000-8000-000000000106';
update public.suppliers
set portal_username = 'legacy-recreated-user',
    portal_password = 'legacy-recreated-secret'
where id = 'a8082100-0001-4000-8000-000000000106';
update public.suppliers
set portal_username = null,
    portal_password = null
where id = 'a8082100-0001-4000-8000-000000000106';
select ok(
  not exists (
    select 1
    from public.supplier_credentials credential
    where credential.supplier_id =
      'a8082100-0001-4000-8000-000000000106'
      and credential.credential_kind = 'portal_password'
      and credential.credential_key = 'default'
  ),
  'legacy delete-recreate-delete leaves no stale Vault credential metadata'
);
select is(
  (
    select count(*)
    from public.supplier_credential_command_receipts receipt
    where receipt.supplier_id =
      'a8082100-0001-4000-8000-000000000106'
      and receipt.command_kind = 'delete'
  ),
  2::bigint,
  'each legacy delete generation owns a distinct durable tombstone'
);

select public.upsert_supplier_credential(
  'a8082100-0000-4000-8000-000000000001',
  'a8082100-0001-4000-8000-000000000105',
  'other', 'Legacy wrapper', 'wrapper-user', 'wrapper-a'
);
select public.upsert_supplier_credential(
  'a8082100-0000-4000-8000-000000000001',
  'a8082100-0001-4000-8000-000000000105',
  'other', 'Legacy wrapper', 'wrapper-user', 'wrapper-b'
);
select public.upsert_supplier_credential(
  'a8082100-0000-4000-8000-000000000001',
  'a8082100-0001-4000-8000-000000000105',
  'other', 'Legacy wrapper', 'wrapper-user', 'wrapper-a'
);
select is(
  public.get_supplier_credential(
    'a8082100-0000-4000-8000-000000000001',
    'a8082100-0001-4000-8000-000000000105',
    'other'
  )->>'secret',
  'wrapper-a',
  'obsolete wrapper A-to-B-to-A reaches the exact newest Vault generation'
);
select is(
  public.delete_supplier_credential(
    'a8082100-0000-4000-8000-000000000001',
    'a8082100-0001-4000-8000-000000000105',
    'other'
  ),
  true,
  'obsolete wrapper deletes its current generation'
);
select public.upsert_supplier_credential(
  'a8082100-0000-4000-8000-000000000001',
  'a8082100-0001-4000-8000-000000000105',
  'other', 'Legacy wrapper', 'wrapper-user', 'wrapper-recreated'
);
select is(
  public.delete_supplier_credential(
    'a8082100-0000-4000-8000-000000000001',
    'a8082100-0001-4000-8000-000000000105',
    'other'
  ),
  true,
  'obsolete wrapper delete after recreate does not replay an old tombstone'
);
select ok(
  not exists (
    select 1
    from public.supplier_credentials credential
    where credential.supplier_id =
      'a8082100-0001-4000-8000-000000000105'
      and credential.credential_kind = 'other'
      and credential.credential_key = 'default'
  ),
  'obsolete wrapper delete-recreate-delete leaves no stale credential'
);

select ok(
  public.supplier_credential_acl_cutover_ready_internal(),
  'credential cutover preflight accepts exact legacy, metadata, origin, and decrypted Vault parity'
);
create temporary table cutover_secret_snapshot as
select
  credential.id as credential_id,
  credential.vault_secret_id,
  credential.username,
  credential.origin_url,
  supplier.portal_password as secret_value,
  secret.name,
  secret.description
from public.suppliers supplier
join public.supplier_credentials credential
  on credential.tenant_id = supplier.tenant_id
 and credential.supplier_id = supplier.id
 and credential.credential_kind = 'portal_password'
 and credential.credential_key = 'default'
join vault.secrets secret
  on secret.id = credential.vault_secret_id
where supplier.id = 'a8082100-0001-4000-8000-000000000101';
select vault.update_secret(
  vault_secret_id,
  'cutover-mismatch',
  name,
  description
)
from cutover_secret_snapshot;
select is(
  public.supplier_credential_acl_cutover_ready_internal(),
  false,
  'credential cutover fails closed when decrypted Vault readback differs from the legacy copy'
);
select vault.update_secret(
  vault_secret_id,
  secret_value,
  name,
  description
)
from cutover_secret_snapshot;
select ok(
  public.supplier_credential_acl_cutover_ready_internal(),
  'credential cutover preflight recovers only after exact decrypted readback is restored'
);
set local session_replication_role = replica;
update public.supplier_credentials credential
set username = 'cutover-mismatched-user'
from cutover_secret_snapshot snapshot
where credential.id = snapshot.credential_id;
set local session_replication_role = origin;
select is(
  public.supplier_credential_acl_cutover_ready_internal(),
  false,
  'credential cutover fails closed when canonical username differs from the normalized legacy copy'
);
set local session_replication_role = replica;
update public.supplier_credentials credential
set username = snapshot.username
from cutover_secret_snapshot snapshot
where credential.id = snapshot.credential_id;
set local session_replication_role = origin;
select ok(
  public.supplier_credential_acl_cutover_ready_internal(),
  'credential cutover recovers after exact normalized username parity is restored'
);
set local session_replication_role = replica;
update public.supplier_credentials credential
set origin_url = 'https://cutover-mismatch.example.test'
from cutover_secret_snapshot snapshot
where credential.id = snapshot.credential_id;
set local session_replication_role = origin;
select is(
  public.supplier_credential_acl_cutover_ready_internal(),
  false,
  'credential cutover fails closed when canonical origin differs from the legacy website'
);
set local session_replication_role = replica;
update public.supplier_credentials credential
set origin_url = snapshot.origin_url
from cutover_secret_snapshot snapshot
where credential.id = snapshot.credential_id;
set local session_replication_role = origin;
select ok(
  public.supplier_credential_acl_cutover_ready_internal(),
  'credential cutover recovers after exact canonical-origin parity is restored'
);

create temporary table dirty_origin_repaired (payload jsonb);
insert into dirty_origin_repaired
select public.upsert_supplier_credential_v2(
  'a8082100-0000-4000-8000-000000000001',
  'a8082100-0001-4000-8000-000000000103',
  'portal_password', 'default',
  'a8082100-0400-4000-8000-0000000000a1',
  (
    select updated_at
    from public.supplier_credentials
    where supplier_id = 'a8082100-0001-4000-8000-000000000103'
      and credential_kind = 'portal_password'
      and credential_key = 'default'
  ),
  null, 'https://clean-origin.example.test', 'Portal corregido',
  'dirty-user', 'dirty-secret-rotated', false, false
);
select is(
  (
    select status
    from public.supplier_data_quality_candidates
    where supplier_id = 'a8082100-0001-4000-8000-000000000103'
      and issue_code = 'legacy_portal_origin_not_canonical'
  ),
  'resolved',
  'configuring an exact credential origin resolves the stale validation incident'
);
create temporary table dirty_origin_cleared (payload jsonb);
insert into dirty_origin_cleared
select public.upsert_supplier_credential_v2(
  'a8082100-0000-4000-8000-000000000001',
  'a8082100-0001-4000-8000-000000000103',
  'portal_password', 'default',
  'a8082100-0400-4000-8000-0000000000a2',
  ((select payload->>'updated_at' from dirty_origin_repaired))::timestamptz,
  null, null, 'Portal corregido', 'dirty-user',
  'dirty-secret-cleared-origin', false, true
);
select is(
  (
    select status
    from public.supplier_data_quality_candidates
    where supplier_id = 'a8082100-0001-4000-8000-000000000103'
      and issue_code = 'legacy_portal_origin_not_canonical'
  ),
  'pending',
  'clearing origin while the legacy URL remains unsafe reopens the incident'
);
select public.upsert_supplier_credential_v2(
  'a8082100-0000-4000-8000-000000000001',
  'a8082100-0001-4000-8000-000000000103',
  'portal_password', 'default',
  'a8082100-0400-4000-8000-0000000000a3',
  ((select payload->>'updated_at' from dirty_origin_cleared))::timestamptz,
  null, 'https://clean-origin.example.test', 'Portal corregido',
  'dirty-user', 'dirty-secret-final', false, false
);
select is(
  (
    select validation_issue_count
    from public.supplier_profile_read_model
    where supplier_id = 'a8082100-0001-4000-8000-000000000103'
  ),
  0::bigint,
  'repaired credential origin disappears from current profile attention'
);

select is(
  public.upsert_supplier_credential_v2(
    'a8082100-0000-4000-8000-000000000001',
    'a8082100-0001-4000-8000-000000000101',
    'portal_password', 'default',
    'a8082100-0400-4000-8000-000000000001',
    (
      select updated_at
      from public.supplier_credentials
      where supplier_id = 'a8082100-0001-4000-8000-000000000101'
        and credential_kind = 'portal_password'
        and credential_key = 'default'
    ),
    ((select payload->'engagement'->>'id' from engagement_result))::uuid,
    null, 'Portal principal', 'legacy-user', 'vault-default-secret',
    false, false
  )->>'credential_stored',
  'true',
  'v2 rotates default credential and attaches engagement'
);
select is(
  public.upsert_supplier_credential(
    'a8082100-0000-4000-8000-000000000001',
    'a8082100-0001-4000-8000-000000000101',
    'portal_password', 'Portal principal', 'legacy-rotated',
    'legacy-wrapper-secret'
  )->>'credential_stored',
  'true',
  'legacy wrapper remains compatible'
);
select ok(
  exists (
    select 1
    from public.supplier_credentials credential
    where credential.supplier_id = 'a8082100-0001-4000-8000-000000000101'
      and credential.credential_kind = 'portal_password'
      and credential.credential_key = 'default'
      and credential.origin_url = 'https://portal.example.test'
      and credential.engagement_id = ((
        select payload->'engagement'->>'id' from engagement_result
      ))::uuid
  ),
  'legacy rotation preserves v2 origin and engagement metadata'
);

select is(
  public.find_supplier_credential_for_origin(
    'a8082100-0000-4000-8000-000000000001',
    'https://PORTAL.example.test:443',
    'portal_password'
  )->>'match_status',
  'unique',
  'exact-origin lookup normalizes host case and default HTTPS port'
);
select is(
  (
    public.find_supplier_credential_for_origin(
      'a8082100-0000-4000-8000-000000000001',
      'https://portal.example.test',
      'portal_password'
    )->>'effective_business_date'
  )::date,
  public.tenant_business_date(
    'a8082100-0000-4000-8000-000000000001'
  ),
  'exact-origin credential binding publishes the date used for engagement validity'
);
select ok(
  not (
    public.find_supplier_credential_for_origin(
      'a8082100-0000-4000-8000-000000000001',
      'https://portal.example.test',
      'portal_password'
    )->'match'
  ) ?| array['secret','username','vault_secret_id'],
  'origin lookup returns neither secret nor username'
);
select is(
  public.find_supplier_credential_for_origin(
    'a8082100-0000-4000-8000-000000000001',
    'https://www.portal.example.test',
    'portal_password'
  )->>'match_status',
  'no_match',
  'www hostname is a distinct exact origin'
);

create temporary table port_credential_result (payload jsonb);
insert into port_credential_result
select public.upsert_supplier_credential_v2(
  'a8082100-0000-4000-8000-000000000001',
  'a8082100-0001-4000-8000-000000000101',
  'portal_password', 'port8443',
  'a8082100-0400-4000-8000-000000000002', null, null,
  'https://portal.example.test:8443', 'Puerto 8443', 'port-user',
  'port-secret', false, false
);
select is(
  public.upsert_supplier_credential_v2(
    'a8082100-0000-4000-8000-000000000001',
    'a8082100-0001-4000-8000-000000000101',
    'portal_password', 'port8443',
    'a8082100-0400-4000-8000-000000000002', null, null,
    'https://portal.example.test:8443', 'Puerto 8443', 'port-user',
    'port-secret', false, false
  )->>'idempotent_replay',
  'true',
  'lost-ack credential upsert replays without rotating twice'
);
select throws_ok(
  $$select public.upsert_supplier_credential_v2(
    'a8082100-0000-4000-8000-000000000001',
    'a8082100-0001-4000-8000-000000000101',
    'portal_password', 'port8443',
    'a8082100-0400-4000-8000-000000000002', null, null,
    'https://portal.example.test:8443', 'Puerto 8443', 'port-user',
    'different-secret', false, false
  )$$,
  '23505',
  'Supplier credential operation id was reused with different content',
  'credential operation id cannot be reused for another secret'
);
select throws_ok(
  $$select public.upsert_supplier_credential_v2(
    'a8082100-0000-4000-8000-000000000001',
    'a8082100-0001-4000-8000-000000000101',
    'portal_password', 'port8443',
    'a8082100-0400-4000-8000-000000000003', null, null,
    'https://portal.example.test:8443', 'Puerto 8443', 'port-user',
    'stale-secret', false, false
  )$$,
  '22023',
  'Expected credential updated_at is required for rotation',
  'credential rotation cannot omit optimistic concurrency token'
);
create temporary table port_credential_rotated (payload jsonb);
insert into port_credential_rotated
select public.upsert_supplier_credential_v2(
  'a8082100-0000-4000-8000-000000000001',
  'a8082100-0001-4000-8000-000000000101',
  'portal_password', 'port8443',
  'a8082100-0400-4000-8000-000000000006',
  ((select payload->>'updated_at' from port_credential_result))::timestamptz,
  null, null, 'Puerto 8443', 'port-user',
  'port-secret-rotated', false, false
);
select ok(
  (
    select (rotated.payload->>'updated_at')::timestamptz
      > (created.payload->>'updated_at')::timestamptz
    from port_credential_rotated rotated
    cross join port_credential_result created
  ),
  'credential updated_at increases strictly across same-transaction rotations'
);
select throws_ok(
  $$select public.upsert_supplier_credential_v2(
    'a8082100-0000-4000-8000-000000000001',
    'a8082100-0001-4000-8000-000000000101',
    'portal_password', 'port8443',
    'a8082100-0400-4000-8000-000000000007',
    ((select payload->>'updated_at' from port_credential_result))::timestamptz,
    null, null, 'Puerto 8443', 'port-user',
    'stale-rotation', false, false
  )$$,
  '40001',
  'Supplier credential changed concurrently',
  'stale credential rotation cannot overwrite a newer secret'
);
select is(
  (
    select count(*)
    from public.supplier_credential_access_events event
    where event.supplier_id = 'a8082100-0001-4000-8000-000000000101'
      and event.credential_key = 'port8443'
      and event.action in ('create', 'rotate')
  ),
  2::bigint,
  'credential retries and rejected races do not duplicate audit events'
);
select is(
  public.find_supplier_credential_for_origin(
    'a8082100-0000-4000-8000-000000000001',
    'https://portal.example.test:8443',
    'portal_password'
  )->'match'->>'credential_key',
  'port8443',
  'non-default port is part of exact origin identity'
);

select public.upsert_supplier_credential_v2(
  'a8082100-0000-4000-8000-000000000001',
  'a8082100-0001-4000-8000-000000000101',
  'portal_password', 'secondary',
  'a8082100-0400-4000-8000-000000000004', null,
  ((select payload->'engagement'->>'id' from engagement_result))::uuid,
  'https://portal.example.test', 'Portal secundario', 'secondary-user',
  'secondary-secret', false, false
);
select ok(
  (
    select lookup->>'match_status' = 'ambiguous'
      and (lookup->>'match_count')::integer = 2
      and lookup->'match' = 'null'::jsonb
    from (
      select public.find_supplier_credential_for_origin(
        'a8082100-0000-4000-8000-000000000001',
        'https://portal.example.test', 'portal_password'
      ) lookup
    ) candidate
  ),
  'multiple credential keys for one origin fail closed as ambiguous'
);
select is(
  public.find_supplier_credential_for_origin(
    'a8082100-0000-4000-8000-000000000001',
    'https://inactive.example.test', 'portal_password'
  )->>'match_status',
  'no_match',
  'inactive supplier credentials are excluded from browser discovery'
);

select public.upsert_supplier_credential_v2(
  'a8082100-0000-4000-8000-000000000001',
  'a8082100-0001-4000-8000-000000000101',
  'portal_password', 'engaged',
  'a8082100-0400-4000-8000-000000000005', null,
  ((select payload->'engagement'->>'id' from engagement_result))::uuid,
  'https://engaged.example.test', 'Cuenta ligada', 'engaged-user',
  'engaged-secret', false, false
);
select is(
  public.find_supplier_credential_for_origin(
    'a8082100-0000-4000-8000-000000000001',
    'https://engaged.example.test', 'portal_password'
  )->>'match_status',
  'unique',
  'active engagement with effective version is discoverable'
);

select public.update_supplier_engagement_shell(
  'a8082100-0000-4000-8000-000000000001',
  ((select payload->'engagement'->>'id' from engagement_result))::uuid,
  (
    select updated_at from public.supplier_engagements
    where id = ((select payload->'engagement'->>'id' from engagement_result))::uuid
  ),
  '{"status":"suspended"}'::jsonb
);
select is(
  public.find_supplier_credential_for_origin(
    'a8082100-0000-4000-8000-000000000001',
    'https://engaged.example.test', 'portal_password'
  )->>'match_status',
  'no_match',
  'suspended engagement credentials are excluded from discovery'
);
select public.update_supplier_engagement_shell(
  'a8082100-0000-4000-8000-000000000001',
  ((select payload->'engagement'->>'id' from engagement_result))::uuid,
  (
    select updated_at from public.supplier_engagements
    where id = ((select payload->'engagement'->>'id' from engagement_result))::uuid
  ),
  '{"status":"ended"}'::jsonb
);
select is(
  public.find_supplier_credential_for_origin(
    'a8082100-0000-4000-8000-000000000001',
    'https://engaged.example.test', 'portal_password'
  )->>'match_status',
  'no_match',
  'ended engagement credentials are excluded from discovery'
);

select is(
  public.get_supplier_credential_v2(
    'a8082100-0000-4000-8000-000000000001',
    'a8082100-0001-4000-8000-000000000101',
    'portal_password', 'port8443'
  )->>'secret',
  'port-secret-rotated',
  'authorized reveal targets exact supplier/kind/key'
);
select ok(
  (
    select array_agg(item->>'credential_key' order by ordinality)
      = array_agg(item->>'credential_key' order by item->>'credential_kind', item->>'credential_key')
    from jsonb_array_elements(
      public.get_supplier_credential_status(
        'a8082100-0000-4000-8000-000000000001',
        'a8082100-0001-4000-8000-000000000101'
      )->'credentials'
    ) with ordinality credential(item, ordinality)
  ),
  'credential status ordering is deterministic by kind and key'
);

select set_config(
  'request.jwt.claims',
  '{"role":"authenticated","sub":"a8082100-0000-4000-8000-000000000092"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  'a8082100-0000-4000-8000-000000000092',
  true
);
select throws_ok(
  $$select public.get_supplier_credential_v2(
    'a8082100-0000-4000-8000-000000000001',
    'a8082100-0001-4000-8000-000000000101',
    'portal_password','default'
  )$$,
  '42501',
  'Supplier credential authority required',
  'manage_users does not imply supplier secret reveal'
);
select throws_ok(
  $$select public.find_supplier_credential_for_origin(
    'a8082100-0000-4000-8000-000000000001',
    'https://portal.example.test','portal_password'
  )$$,
  '42501',
  'Supplier credential authority required',
  'origin metadata discovery also requires dedicated authority'
);

select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select set_config('request.jwt.claim.sub', '', true);
select ok(
  not exists (
    select 1
    from public.supplier_credential_access_events event
    where public.jsonb_contains_sensitive_key(event.metadata)
       or event.metadata::text ilike '%-secret%'
       or event.metadata::text ilike '%-user%'
       or event.metadata ? 'username'
  ),
  'credential audit metadata contains neither secrets nor usernames'
);
select ok(
  exists (
    select 1
    from public.supplier_credential_access_events event
    where event.supplier_id = 'a8082100-0001-4000-8000-000000000101'
      and event.credential_key = 'port8443'
      and event.action = 'reveal'
  ),
  'credential reveal is auditable'
);

-- -------------------------------------------------------------------------
-- Received documents, normalized lines, and exact economic projections
-- -------------------------------------------------------------------------

insert into public.products (
  id, tenant_id, name, sku, purchase_treatment
) values (
  'a8082100-0005-4000-8000-000000000501',
  'a8082100-0000-4000-8000-000000000001',
  'Cadena prueba', 'SUP-FOUND-CHAIN', 'inventory'
);

insert into public.payment_methods (
  id, tenant_id, code, name, account_id, default_tax_treatment
) values (
  'a8082100-0009-4000-8000-000000000901',
  'a8082100-0000-4000-8000-000000000001',
  'supplier_foundation_cash', 'Pago prueba proveedor',
  (
    select id from public.accounts
    where tenant_id = 'a8082100-0000-4000-8000-000000000001'
      and code = '1101'
    limit 1
  ),
  'no_tax'
);

insert into public.purchase_invoices (
  id, tenant_id, invoice_number, supplier_id, supplier_name,
  status, subtotal, tax, total, paid_amount, balance,
  tax_treatment, net_amount, discount_amount, additional_costs, items
) values
  (
    'a8082100-0006-4000-8000-000000000601',
    'a8082100-0000-4000-8000-000000000001',
    'PI-SUP-FOUND-001',
    'a8082100-0001-4000-8000-000000000101', 'Proveedor Base A',
    'draft', 100, 19, 113, 0, 113,
    'tax_included', 100, 10,
    '[{"label":"Flete documento","amount":5}]'::jsonb,
    jsonb_build_array(
      jsonb_build_object(
        'product_id', 'a8082100-0005-4000-8000-000000000501',
        'product_name', 'Cadena prueba',
        'product_sku', 'SUP-FOUND-CHAIN',
        'purchase_treatment', 'inventory',
        'quantity', 1, 'unit_cost', 80, 'discount', 0,
        'iva_rate', 0.19
      ),
      jsonb_build_object(
        'product_id', '', 'product_name', 'Flete sin producto',
        'quantity', 1, 'unit_cost', 20, 'discount', 0,
        'iva_rate', 0.19
      )
    )
  ),
  (
    'a8082100-0006-4000-8000-000000000602',
    'a8082100-0000-4000-8000-000000000001',
    'PI-SUP-FOUND-002',
    'a8082100-0001-4000-8000-000000000101', 'Proveedor Base A',
    'draft', 10, 0, 10, 0, 10,
    'no_tax', 10, 0, '[]'::jsonb,
    '[{"product_name":"Borrador","quantity":1,"unit_cost":10,"iva_rate":0}]'::jsonb
  ),
  (
    'a8082100-0006-4000-8000-000000000603',
    'a8082100-0000-4000-8000-000000000001',
    'PI-SUP-FOUND-003',
    'a8082100-0001-4000-8000-000000000103', 'Proveedor URL legado',
    'confirmed', 10, 0, 10, 0, 10,
    'no_tax', 10, 0, '[]'::jsonb,
    '[{"product_name":"Servicio sin clasificar","quantity":1,"unit_cost":10,"iva_rate":0}]'::jsonb
  );

select is(
  (
    select sum(line.total_amount)
    from public.purchase_invoice_lines line
    where line.purchase_invoice_id = 'a8082100-0006-4000-8000-000000000601'
  ),
  113::numeric,
  'normalized lines preserve exact document total with discount and extras'
);
select ok(
  (
    select array_agg(adjustment_kind order by adjustment_kind)
      @> array['additional_cost','document_reconciliation','global_discount']::text[]
    from public.purchase_invoice_lines
    where purchase_invoice_id = 'a8082100-0006-4000-8000-000000000601'
      and line_kind = 'adjustment'
  ),
  'discount, additional cost, and rounding residual remain explicit facts'
);
select is(
  (
    select source_line_index
    from public.purchase_invoice_lines
    where purchase_invoice_id = 'a8082100-0006-4000-8000-000000000601'
      and line_number = 1
  ),
  0,
  'legacy source ordinal remains zero-based and stable'
);
select is(
  (
    select classification_status
    from public.purchase_invoice_lines
    where purchase_invoice_id = 'a8082100-0006-4000-8000-000000000601'
      and source_line_index = 1
  ),
  'needs_review',
  'missing treatment is reviewable and never invented as inventory'
);

update public.purchase_invoices
set status = 'confirmed'
where id = 'a8082100-0006-4000-8000-000000000601';

update public.purchase_invoices
set items = jsonb_build_array(items->0),
    total = 90,
    discount_amount = 0,
    additional_costs = '[]'::jsonb
where id = 'a8082100-0006-4000-8000-000000000602';
select is(
  (
    select sum(total_amount)
    from public.purchase_invoice_lines
    where purchase_invoice_id = 'a8082100-0006-4000-8000-000000000602'
  ),
  90::numeric,
  'legacy line resync reconciles the changed exact document total'
);
select is(
  (
    select count(*)
    from public.purchase_invoice_lines
    where purchase_invoice_id = 'a8082100-0006-4000-8000-000000000602'
      and source_line_index is not null
  ),
  1::bigint,
  'shrinking legacy JSON removes stale normalized source ordinals'
);

delete from public.products
where id = 'a8082100-0005-4000-8000-000000000501';
select ok(
  exists (
    select 1
    from public.purchase_invoice_lines
    where tenant_id = 'a8082100-0000-4000-8000-000000000001'
      and purchase_invoice_id = 'a8082100-0006-4000-8000-000000000601'
      and source_line_index = 0
      and product_id is null
  ),
  'product deletion nulls only optional product FK and preserves tenant/line'
);

insert into public.received_tax_documents (
  id, tenant_id, issuer_party_id, supplier_id, purchase_invoice_id,
  document_type_code, normalized_folio, display_folio,
  issued_on, net_amount, tax_amount, total_amount, status, source
) values (
  'a8082100-0007-4000-8000-000000000701',
  'a8082100-0000-4000-8000-000000000001',
  'a8082100-0001-4000-8000-000000000101',
  'a8082100-0001-4000-8000-000000000101',
  'a8082100-0006-4000-8000-000000000601',
  '33', 'F-001', 'F-001',
  (select business_date from supplier_test_clock),
  100, 19, 119, 'linked', 'manual'
);
select is(
  (
    select received_tax_document_id
    from public.purchase_invoices
    where id = 'a8082100-0006-4000-8000-000000000601'
  ),
  'a8082100-0007-4000-8000-000000000701'::uuid,
  'link written from received document projects to purchase invoice'
);
update public.received_tax_documents
set purchase_invoice_id = null
where id = 'a8082100-0007-4000-8000-000000000701';
select is(
  (
    select received_tax_document_id
    from public.purchase_invoices
    where id = 'a8082100-0006-4000-8000-000000000601'
  ),
  null::uuid,
  'unlink written from received document clears inverse link'
);
update public.purchase_invoices
set received_tax_document_id = 'a8082100-0007-4000-8000-000000000701'
where id = 'a8082100-0006-4000-8000-000000000602';
select is(
  (
    select purchase_invoice_id
    from public.received_tax_documents
    where id = 'a8082100-0007-4000-8000-000000000701'
  ),
  'a8082100-0006-4000-8000-000000000602'::uuid,
  'link written from invoice projects to received document'
);
update public.purchase_invoices
set received_tax_document_id = null
where id = 'a8082100-0006-4000-8000-000000000602';

insert into public.received_tax_documents (
  id, tenant_id, issuer_party_id, supplier_id,
  document_type_code, normalized_folio, display_folio,
  issued_on, net_amount, tax_amount, total_amount, status, source
) values (
  'a8082100-0007-4000-8000-000000000702',
  'a8082100-0000-4000-8000-000000000001',
  'a8082100-0001-4000-8000-000000000101',
  'a8082100-0001-4000-8000-000000000101',
  '33', 'F-002', 'F-002',
  (select business_date from supplier_test_clock),
  10, 0, 10, 'captured', 'manual'
);
update public.received_tax_documents
set purchase_invoice_id = 'a8082100-0006-4000-8000-000000000601'
where id = 'a8082100-0007-4000-8000-000000000701';
update public.purchase_invoices
set received_tax_document_id = 'a8082100-0007-4000-8000-000000000702'
where id = 'a8082100-0006-4000-8000-000000000601';
select ok(
  (
    select purchase_invoice_id is null
    from public.received_tax_documents
    where id = 'a8082100-0007-4000-8000-000000000701'
  ) and (
    select purchase_invoice_id = 'a8082100-0006-4000-8000-000000000601'
    from public.received_tax_documents
    where id = 'a8082100-0007-4000-8000-000000000702'
  ),
  'relink atomically clears old inverse and installs new inverse'
);
delete from public.received_tax_documents
where id = 'a8082100-0007-4000-8000-000000000702';
select is(
  (
    select received_tax_document_id
    from public.purchase_invoices
    where id = 'a8082100-0006-4000-8000-000000000601'
  ),
  null::uuid,
  'received document delete nulls only invoice document FK'
);
select throws_ok(
  $$insert into public.received_tax_documents (
    tenant_id,issuer_party_id,supplier_id,
    document_type_code,normalized_folio,display_folio
  ) values (
    'a8082100-0000-4000-8000-000000000001',
    'a8082100-0001-4000-8000-000000000101',
    'a8082100-0001-4000-8000-000000000101',
    '33','f 001','f 001'
  )$$,
  '23505',
  null,
  'issuer + type + normalized folio is unique'
);
select throws_ok(
  $$insert into public.received_tax_documents (
    id,tenant_id,issuer_party_id,supplier_id,purchase_invoice_id,
    document_type_code,normalized_folio,display_folio
  ) values (
    'a8082100-0007-4000-8000-000000000703',
    'a8082100-0000-4000-8000-000000000001',
    'a8082100-0001-4000-8000-000000000103',
    null,
    'a8082100-0006-4000-8000-000000000601',
    '33','CROSS-ISSUER','CROSS-ISSUER'
  )$$,
  '23514',
  'Received document issuer does not match supplier party',
  'invoice inference runs before and cannot bypass issuer/supplier consistency'
);

insert into public.purchase_payments (
  id, tenant_id, invoice_id, payment_method_id, amount, reference
) values (
  'a8082100-0010-4000-8000-000000001001',
  'a8082100-0000-4000-8000-000000000001',
  'a8082100-0006-4000-8000-000000000601',
  'a8082100-0009-4000-8000-000000000901',
  40, 'Pago foundation'
);

set local session_replication_role = replica;
insert into public.expenses (
  id, tenant_id, expense_number, supplier_id, supplier_name,
  document_type, posting_status, payment_status,
  subtotal, tax_amount, total_amount, amount_paid, balance,
  approval_status, currency, payment_method_id
) values (
  'a8082100-0008-4000-8000-000000000801',
  'a8082100-0000-4000-8000-000000000001',
  'EX-SUP-FOUND-001',
  'a8082100-0001-4000-8000-000000000101', 'Proveedor Base A',
  'invoice', 'posted', 'paid', 50, 0, 50, 50, 0,
  'approved', 'CLP', 'a8082100-0009-4000-8000-000000000901'
);
set local session_replication_role = origin;

insert into public.inventory_accounting_operations (
  id, tenant_id, operation_key, source_channel, action,
  document_type, document_id, executor, context, outcome
) values (
  'a8082100-0012-4000-8000-000000001201',
  'a8082100-0000-4000-8000-000000000001',
  'foundation-credit', 'purchase_credit_note', 'create',
  'purchase_credit_note', 'a8082100-0012-4000-8000-000000001202',
  'test_fixture',
  '{"purchase_invoice_id":"a8082100-0006-4000-8000-000000000601"}'::jsonb,
  'completed'
), (
  'a8082100-0012-4000-8000-000000001203',
  'a8082100-0000-4000-8000-000000000001',
  'foundation-refund', 'purchase_supplier_refund', 'create',
  'purchase_supplier_refund', 'a8082100-0012-4000-8000-000000001204',
  'test_fixture',
  '{"purchase_invoice_id":"a8082100-0006-4000-8000-000000000601"}'::jsonb,
  'completed'
);

insert into public.journal_entries (
  id, tenant_id, entry_number, entry_date, description, type,
  source_module, source_reference, status, total_debit, total_credit,
  operation_id, source_document_type, source_document_id
) values
  (
    'a8082100-0012-4000-8000-000000001205',
    'a8082100-0000-4000-8000-000000000001',
    'JE-SUP-CREDIT', now(), 'Crédito foundation', 'credit_note',
    'purchase_credit_notes', 'a8082100-0012-4000-8000-000000001202',
    'posted', 20, 20,
    'a8082100-0012-4000-8000-000000001201',
    'purchase_credit_note', 'a8082100-0012-4000-8000-000000001202'
  ),
  (
    'a8082100-0012-4000-8000-000000001206',
    'a8082100-0000-4000-8000-000000000001',
    'JE-SUP-REFUND', now(), 'Reembolso foundation', 'refund',
    'purchase_supplier_refunds', 'a8082100-0012-4000-8000-000000001204',
    'posted', 5, 5,
    'a8082100-0012-4000-8000-000000001203',
    'purchase_supplier_refund', 'a8082100-0012-4000-8000-000000001204'
  );

insert into public.journal_lines (
  id, tenant_id, entry_id, account_id, account_code, account_name,
  description, debit_amount, credit_amount
) values
  (
    'a8082100-0012-4000-8000-000000001207',
    'a8082100-0000-4000-8000-000000000001',
    'a8082100-0012-4000-8000-000000001205',
    (select id from public.accounts where tenant_id='a8082100-0000-4000-8000-000000000001' and code='1101' limit 1),
    '1101','Caja','Contraparte crédito',20,0
  ),
  (
    'a8082100-0012-4000-8000-000000001208',
    'a8082100-0000-4000-8000-000000000001',
    'a8082100-0012-4000-8000-000000001206',
    (select id from public.accounts where tenant_id='a8082100-0000-4000-8000-000000000001' and code='1101' limit 1),
    '1101','Caja','Contraparte reembolso',5,0
  );

insert into public.purchase_credit_notes (
  id, tenant_id, purchase_invoice_id, credit_note_number,
  status, official_dte_status, issue_date, reason_code, reason,
  net_amount, tax_amount, total_amount, idempotency_key,
  operation_id, journal_entry_id
) values (
  'a8082100-0012-4000-8000-000000001202',
  'a8082100-0000-4000-8000-000000000001',
  'a8082100-0006-4000-8000-000000000601',
  'NCC-SUP-001', 'posted', 'internal', now(),
  'price_correction', 'Ajuste foundation', 20, 0, 20,
  'foundation-credit-note',
  'a8082100-0012-4000-8000-000000001201',
  'a8082100-0012-4000-8000-000000001205'
);

insert into public.purchase_supplier_refunds (
  id, tenant_id, purchase_invoice_id, purchase_credit_note_id,
  refund_number, status, refunded_at, payment_method_id, amount,
  reference, reason, idempotency_key, operation_id, journal_entry_id
) values (
  'a8082100-0012-4000-8000-000000001204',
  'a8082100-0000-4000-8000-000000000001',
  'a8082100-0006-4000-8000-000000000601',
  'a8082100-0012-4000-8000-000000001202',
  'RP-SUP-001', 'posted', now(),
  'a8082100-0009-4000-8000-000000000901', 5,
  'REF-SUP-001', 'Reembolso foundation', 'foundation-refund-row',
  'a8082100-0012-4000-8000-000000001203',
  'a8082100-0012-4000-8000-000000001206'
);

select public.recalculate_purchase_invoice_settlement(
  'a8082100-0006-4000-8000-000000000601'
);

select ok(
  (
    select gross_amount = 93
      and paid_amount = 35
      and balance_amount = 58
      and payment_count = 2
    from public.supplier_economic_read_model
    where event_type = 'purchase_invoice'
      and event_id = 'a8082100-0006-4000-8000-000000000601'
  ),
  'purchase projection uses payments minus refunds and total minus credits'
);
select ok(
  (
    select paid_amount = 50
      and balance_amount = 0
      and metadata->>'payment_ledger_coverage' = 'legacy_projection'
      and data_quality_status = 'needs_review'
    from public.supplier_economic_read_model
    where event_type = 'expense'
      and event_id = 'a8082100-0008-4000-8000-000000000801'
  ),
  'paid legacy expense without payment rows preserves truthful header settlement'
);
select is(
  (
    select expense_payment_ledger_gap_document_count
    from public.supplier_economic_summary_read_model
    where supplier_id = 'a8082100-0001-4000-8000-000000000101'
      and currency_code = 'CLP'
  ),
  1::bigint,
  'summary publishes incomplete legacy expense payment-ledger coverage'
);
select ok(
  not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'supplier_economic_summary_read_model'
      and column_name in (
        'total_gross_amount','total_paid_amount','total_balance_amount'
      )
  ),
  'summary never combines purchase and expense monetary universes'
);
select is(
  (
    select excluded_lifecycle_document_count
    from public.supplier_economic_summary_read_model
    where supplier_id = 'a8082100-0001-4000-8000-000000000101'
      and currency_code = 'CLP'
  ),
  1::bigint,
  'draft purchase remains timeline-only and is excluded from monetary summary'
);

update public.supplier_relationship_tags
set assignment_source = 'observed',
    updated_at = clock_timestamp()
where tenant_id = 'a8082100-0000-4000-8000-000000000001'
  and supplier_id = 'a8082100-0001-4000-8000-000000000103'
  and tag_code = 'digital'
  and valid_to is null;

select lives_ok(
  $$select public.save_supplier_relationship_profile(
    'a8082100-0000-4000-8000-000000000001',
    'a8082100-0001-4000-8000-000000000103',
    (
      select updated_at from public.suppliers
      where id = 'a8082100-0001-4000-8000-000000000103'
    ),
    '{"operation_id":"a8082100-0100-4000-8000-000000000007","display_name":"Proveedor URL legado renombrado"}'::jsonb,
    '[]'::jsonb,
    '[]'::jsonb,
    '[]'::jsonb
  )$$,
  'name-only profile save preserves unreviewed observed evidence'
);
select ok(
  exists (
    select 1
    from public.supplier_relationship_tags assignment
    where assignment.tenant_id = 'a8082100-0000-4000-8000-000000000001'
      and assignment.supplier_id = 'a8082100-0001-4000-8000-000000000103'
      and assignment.tag_code = 'digital'
      and assignment.assignment_source = 'observed'
      and assignment.valid_to is null
  ) and not (
    select relationship_tags @> '[{"code":"digital"}]'::jsonb
    from public.supplier_profile_read_model
    where supplier_id = 'a8082100-0001-4000-8000-000000000103'
  ),
  'observed tag remains audit-only after an unrelated profile save'
);
select throws_ok(
  $$select public.save_supplier_relationship_profile(
    'a8082100-0000-4000-8000-000000000001',
    'a8082100-0001-4000-8000-000000000103',
    (
      select updated_at from public.suppliers
      where id = 'a8082100-0001-4000-8000-000000000103'
    ),
    '{"operation_id":"a8082100-0100-4000-8000-000000000008","display_name":"Proveedor URL legado renombrado"}'::jsonb,
    '[]'::jsonb,
    '[]'::jsonb,
    '[{"code":"digital"}]'::jsonb
  )$$,
  '23514',
  'Observed supplier tag requires candidate review',
  'profile save cannot promote an observed tag by echoing its code'
);
insert into public.supplier_accounting_policies (
  id, tenant_id, supplier_id, code, name, status, operation_id,
  request_fingerprint
) values (
  'a8082100-0012-4000-8000-000000001201',
  'a8082100-0000-4000-8000-000000000001',
  'a8082100-0001-4000-8000-000000000103',
  'future-policy', 'Politica futura', 'active',
  'a8082100-0012-4000-8000-000000001211', 'pgtap-future-policy'
);
insert into public.supplier_accounting_policy_versions (
  id, tenant_id, policy_id, version_number, effective_from,
  operational_nature_code, operation_id, request_fingerprint
) values (
  'a8082100-0012-4000-8000-000000001202',
  'a8082100-0000-4000-8000-000000000001',
  'a8082100-0012-4000-8000-000000001201',
  1, (select business_date from supplier_test_clock) + 30,
  'digital_services',
  'a8082100-0012-4000-8000-000000001212', 'pgtap-future-version'
);
select is(
  (
    select classification_status
    from public.supplier_profile_read_model
    where supplier_id = 'a8082100-0001-4000-8000-000000000103'
  ),
  'unclassified',
  'activity plus only observed assignments owns Sin categoria confirmada status'
);
select is(
  (
    select accounting_policy_status
    from public.supplier_profile_read_model
    where supplier_id = 'a8082100-0001-4000-8000-000000000103'
  ),
  'missing_policy',
  'active policy with only a future version still owns Sin regla contable status'
);

-- -------------------------------------------------------------------------
-- Canonical journal counterparty and posted-only provenance
-- -------------------------------------------------------------------------

insert into public.journal_entries (
  id, tenant_id, entry_number, entry_date, description, type,
  source_module, source_reference, status, total_debit, total_credit,
  source_document_type, source_document_id
) values (
  'a8082100-0011-4000-8000-000000001101',
  'a8082100-0000-4000-8000-000000000001',
  'JE-SUP-FOUND-001', now(), 'Asiento factura proveedor', 'purchase',
  'purchase_invoices', 'PI-SUP-FOUND-002', 'draft', 10, 10,
  'purchase_invoice', 'a8082100-0006-4000-8000-000000000602'
);
insert into public.journal_lines (
  id, tenant_id, entry_id, account_id, account_code, account_name,
  description, debit_amount, credit_amount
) values
  (
    'a8082100-0011-4000-8000-000000001102',
    'a8082100-0000-4000-8000-000000000001',
    'a8082100-0011-4000-8000-000000001101',
    (select id from public.accounts where tenant_id='a8082100-0000-4000-8000-000000000001' and code='1101' limit 1),
    '1101','Caja','Línea contraparte',10,0
  ),
  (
    'a8082100-0011-4000-8000-000000001103',
    'a8082100-0000-4000-8000-000000000001',
    'a8082100-0011-4000-8000-000000001101',
    (select id from public.accounts where tenant_id='a8082100-0000-4000-8000-000000000001' and code='2101' limit 1),
    '2101','Cuentas por pagar','Línea contraparte',0,10
  );

select is(
  (
    select counterparty_party_id
    from public.journal_lines
    where id = 'a8082100-0011-4000-8000-000000001102'
  ),
  'a8082100-0001-4000-8000-000000000101'::uuid,
  'journal line derives canonical external-party counterparty'
);
select is(
  (
    select metadata->>'has_journal_provenance'
    from public.supplier_economic_read_model
    where event_type = 'purchase_invoice'
      and event_id = 'a8082100-0006-4000-8000-000000000602'
  ),
  'false',
  'draft source-linked journal does not inflate posted provenance'
);
select throws_ok(
  $$insert into public.journal_lines (
    tenant_id,entry_id,account_id,account_code,account_name,
    description,debit_amount,credit_amount,counterparty_party_id
  ) values (
    'a8082100-0000-4000-8000-000000000001',
    'a8082100-0011-4000-8000-000000001101',
    (select id from public.accounts where tenant_id='a8082100-0000-4000-8000-000000000001' and code='1101' limit 1),
    '1101','Caja','Contraparte forjada',1,0,
    'a8082100-0001-4000-8000-000000000103'
  )$$,
  '23514',
  'Journal line counterparty contradicts canonical source',
  'caller cannot forge counterparty against canonical provenance'
);
select throws_ok(
  $$update public.journal_entries
    set source_document_id='a8082100-0006-4000-8000-000000000603',
        source_reference='PI-SUP-FOUND-003'
    where id='a8082100-0011-4000-8000-000000001101'$$,
  '23514',
  'Journal provenance change contradicts existing counterparty lines',
  'source mutation cannot leave stale contradictory counterparties'
);
update public.journal_entries
set status = 'posted'
where id = 'a8082100-0011-4000-8000-000000001101';
select is(
  (
    select metadata->>'has_journal_provenance'
    from public.supplier_economic_read_model
    where event_type = 'purchase_invoice'
      and event_id = 'a8082100-0006-4000-8000-000000000602'
  ),
  'true',
  'posted source-linked journal counts as provenance'
);

-- -------------------------------------------------------------------------
-- Identifier namespaces, tenant RLS, backups, and final audit gates
-- -------------------------------------------------------------------------

insert into public.external_parties (
  id, tenant_id, party_kind, display_name
) values (
  'a8082100-0014-4000-8000-000000001401',
  'a8082100-0000-4000-8000-000000000001',
  'organization', 'Foreign tax identity'
);
insert into public.external_party_identifiers (
  tenant_id, party_id, identifier_kind, country_code, display_value
) values (
  'a8082100-0000-4000-8000-000000000001',
  'a8082100-0014-4000-8000-000000001401',
  'tax_id', 'US', '76.123.456-7'
), (
  'a8082100-0000-4000-8000-000000000001',
  'a8082100-0014-4000-8000-000000001401',
  'domain', null, 'Example.COM'
);
select is(
  (
    select normalized_value
    from public.external_party_identifiers
    where party_id = 'a8082100-0014-4000-8000-000000001401'
      and identifier_kind = 'domain'
  ),
  'example.com',
  'identifier trigger accepts display-only input and normalizes domain'
);
select ok(
  exists (
    select 1
    from public.external_party_identifiers
    where normalized_value = '761234567'
      and country_code = 'US'
  ) and exists (
    select 1
    from public.external_party_identifiers
    where normalized_value = '761234567'
      and country_code = 'CL'
  ),
  'tax identifier namespace includes country'
);
select throws_ok(
  $$insert into public.external_party_identifiers (
    tenant_id,party_id,identifier_kind,country_code,display_value
  ) values (
    'a8082100-0000-4000-8000-000000000001',
    'a8082100-0014-4000-8000-000000001401',
    'tax_id','CL','761234567'
  )$$,
  '23505',
  null,
  'same normalized tax id in same country/tenant cannot duplicate'
);

select set_config(
  'request.jwt.claims',
  '{"role":"authenticated","sub":"a8082100-0000-4000-8000-000000000091"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  'a8082100-0000-4000-8000-000000000091',
  true
);
set local role authenticated;
select is(
  (
    select count(*)
    from public.supplier_profile_read_model
    where tenant_id = 'a8082100-0000-4000-8000-000000000002'
  ),
  0::bigint,
  'security_invoker profile cannot cross tenant RLS'
);
select is(
  (
    select count(*)
    from public.active_business_site_read_model
    where tenant_id = 'a8082100-0000-4000-8000-000000000002'
  ),
  0::bigint,
  'active site catalog cannot cross tenant RLS'
);
select is(
  (
    select count(*)
    from public.supplier_classification_candidate_read_model
    where tenant_id = 'a8082100-0000-4000-8000-000000000002'
  ),
  0::bigint,
  'classification review queue cannot cross tenant RLS'
);
select is(
  (
    select count(*)
    from public.supplier_role_definitions
    where tenant_id = 'a8082100-0000-4000-8000-000000000002'
  ),
  0::bigint,
  'classification catalogs are tenant isolated'
);
reset role;

select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into public.database_backups (
  id, tenant_id, backup_name, backup_type, status, backup_data, summary
) values (
  'a8082100-0013-4000-8000-000000001301',
  'a8082100-0000-4000-8000-000000000001',
  'Backup legacy con secreto', 'manual', 'completed',
  jsonb_build_object('suppliers', jsonb_build_array(
    jsonb_build_object(
      'id','a8082100-0001-4000-8000-000000000101',
      'name','Nombre historico que no debe restaurarse',
      'portal_username','legacy-user',
      'portal_password','historical-backup-secret'
    ),
    jsonb_build_object(
      'id','a8082100-0001-4000-8000-000000000102',
      'name','Segundo proveedor conserva su posicion'
    )
  )),
  '{}'::jsonb
);
create temporary table supplier_backup_before_redaction as
select id, length(backup_data::text)::bigint as backup_size_bytes
from public.database_backups
where id = 'a8082100-0013-4000-8000-000000001301';
select ok(
  (
    select result->>'success' = 'false'
      and result->>'error_code' = 'supplier_foundation_restore_supplier_set_changed'
    from (
      select public.restore_backup_internal(
        'a8082100-0013-4000-8000-000000001301',
        'a8082100-0000-4000-8000-000000000001'
      ) result
    ) guarded_restore
  ),
  'foundation restore fails closed before a backup can change durable supplier IDs'
);
select is(
  (
    select display_name
    from public.external_parties
    where tenant_id = 'a8082100-0000-4000-8000-000000000001'
      and id = 'a8082100-0001-4000-8000-000000000101'
  ),
  'Proveedor Base A',
  'failed set-changing restore leaves canonical supplier identity untouched'
);

insert into public.tenants (id, shop_name) values (
  'a8082100-0000-4000-8000-000000000003',
  'Supplier Foundation Restore C'
);
insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  'a8082100-0000-4000-8000-000000000094',
  'authenticated', 'authenticated', 'supplier-admin-c@example.invalid',
  '', now(),
  '{"account_type":"erp_staff","tenant_id":"a8082100-0000-4000-8000-000000000003"}'::jsonb,
  '{}'::jsonb, now(), now()
);
delete from public.user_profiles
where user_id = 'a8082100-0000-4000-8000-000000000094';
insert into public.user_profiles (
  user_id, tenant_id, role, permissions, is_active
) values (
  'a8082100-0000-4000-8000-000000000094',
  'a8082100-0000-4000-8000-000000000003',
  'admin',
  '{"manage_accounting":true,"edit_settings":true,"can_manage_supplier_credentials":true}'::jsonb,
  true
);
-- The legacy payment-method seeder mutates request.jwt.claim.sub while creating
-- a tenant. Restore the service context before exercising backup boundaries.
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select set_config('request.jwt.claim.sub', '', true);
insert into public.suppliers (
  id, tenant_id, name, legal_name, rut, website,
  portal_username, portal_password
) values (
  'a8082100-0001-4000-8000-000000000107',
  'a8082100-0000-4000-8000-000000000003',
  'Proveedor Actual C', 'Proveedor Actual C SpA', '55.555.555-5',
  'https://restore.example.test', 'restore-user', 'restore-secret'
);
create temporary table restore_c_before as
select supplier.party_id, credential.vault_secret_id
from public.suppliers supplier
join public.supplier_credentials credential
  on credential.tenant_id = supplier.tenant_id
 and credential.supplier_id = supplier.id
 and credential.credential_kind = 'portal_password'
 and credential.credential_key = 'default'
where supplier.id = 'a8082100-0001-4000-8000-000000000107';
insert into public.supplier_relationship_tags (
  tenant_id, supplier_id, tag_code, label, valid_from, assignment_source
) values (
  'a8082100-0000-4000-8000-000000000003',
  'a8082100-0001-4000-8000-000000000107',
  'digital', 'Digital',
  (select business_date from supplier_test_clock), 'manual'
);
insert into public.products (
  id, tenant_id, name, sku, cost, purchase_treatment,
  inventory_qty, stock_quantity
) values (
  'a8082100-0005-4000-8000-000000000507',
  'a8082100-0000-4000-8000-000000000003',
  'Producto restore C', 'SUP-FOUND-RESTORE-C', 100, 'inventory',
  0, 0
);
insert into public.purchase_invoices (
  id, tenant_id, invoice_number, supplier_id, supplier_name,
  status, subtotal, tax, total, paid_amount, balance,
  tax_treatment, net_amount, discount_amount, additional_costs, items
) values (
  'a8082100-0006-4000-8000-000000000607',
  'a8082100-0000-4000-8000-000000000003',
  'PI-RESTORE-C-SNAPSHOT',
  'a8082100-0001-4000-8000-000000000107', 'Proveedor Actual C',
  'received', 200, 0, 200, 0, 200,
  'no_tax', 200, 0, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'product_id', 'a8082100-0005-4000-8000-000000000507',
    'product_name', 'Producto restore C',
    'product_sku', 'SUP-FOUND-RESTORE-C',
    'purchase_treatment', 'inventory',
    'quantity', 2, 'unit_cost', 100, 'discount', 0,
    'iva_rate', 0
  ))
);
create temporary table restore_c_snapshot as
select
  product.inventory_qty,
  product.stock_quantity,
  (
    select coalesce(
      jsonb_agg(to_jsonb(movement) order by movement.id),
      '[]'::jsonb
    )
    from public.stock_movements movement
    where movement.tenant_id = product.tenant_id
  ) as stock_movements,
  (
    select coalesce(
      jsonb_agg(to_jsonb(entry) order by entry.id),
      '[]'::jsonb
    )
    from public.journal_entries entry
    where entry.tenant_id = product.tenant_id
  ) as journal_entries,
  (
    select coalesce(
      jsonb_agg(to_jsonb(line) order by line.id),
      '[]'::jsonb
    )
    from public.journal_lines line
    where line.tenant_id = product.tenant_id
  ) as journal_lines
from public.products product
where product.id = 'a8082100-0005-4000-8000-000000000507';
create temporary table restore_c_backup (payload jsonb);
insert into restore_c_backup
select public.create_backup_internal(
  'a8082100-0000-4000-8000-000000000003',
  'Round trip foundation',
  'manual',
  'pgTAP same-set restore fixture'
);
select ok(
  (
    select backup.backup_size_bytes = length(backup.backup_data::text)
      and result.payload->>'size_mb' = round(
        (backup.backup_size_bytes / 1024.0 / 1024.0)::numeric,
        2
      )::text
      and not exists (
        select 1
        from jsonb_array_elements(
          case when jsonb_typeof(backup.backup_data->'suppliers') = 'array'
            then backup.backup_data->'suppliers'
            else '[]'::jsonb
          end
        ) supplier_item
        where supplier_item ?| array['portal_username', 'portal_password']
      )
    from restore_c_backup result
    join public.database_backups backup
      on backup.id = (result.payload->>'backup_id')::uuid
  ),
  'new backup wrapper returns the persisted sanitized size and no credential keys'
);
update public.database_backups backup
set backup_data = jsonb_set(
  backup.backup_data,
  '{suppliers}',
  (
    select jsonb_agg(
      item || jsonb_build_object(
        'name', 'Proveedor Historico C',
        'legal_name', 'Proveedor Historico C SpA',
        'rut', '66.666.666-6'
      )
    )
    from jsonb_array_elements(backup.backup_data->'suppliers') item
  ),
  false
)
where backup.id = ((
  select payload->>'backup_id' from restore_c_backup
))::uuid;

-- Create a materially different received invoice after the snapshot. Without
-- the internal trigger guard, the wrapper's placeholder/final UPDATE pair
-- would restore and consume inventory again and would recreate a journal under
-- the wrong placeholder reference.
update public.purchase_invoices
set invoice_number = 'PI-RESTORE-C-MUTATED',
    subtotal = 750,
    total = 750,
    net_amount = 750,
    balance = 750,
    items = jsonb_build_array(jsonb_build_object(
      'product_id', 'a8082100-0005-4000-8000-000000000507',
      'product_name', 'Producto restore C mutado',
      'product_sku', 'SUP-FOUND-RESTORE-C',
      'purchase_treatment', 'inventory',
      'quantity', 5, 'unit_cost', 150, 'discount', 0,
      'iva_rate', 0
    ))
where id = 'a8082100-0006-4000-8000-000000000607';
select ok(
  (
    select product.stock_quantity = 5
      and product.stock_quantity <> snapshot.stock_quantity
    from public.products product
    cross join restore_c_snapshot snapshot
    where product.id = 'a8082100-0005-4000-8000-000000000507'
  ),
  'restore regression begins from inventory state that differs from the backup'
);
create temporary table restore_c_result (payload jsonb);
grant select, insert on restore_c_result to authenticated;
grant select on restore_c_backup to authenticated;
select set_config(
  'request.jwt.claims',
  '{"role":"authenticated","sub":"a8082100-0000-4000-8000-000000000094"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  'a8082100-0000-4000-8000-000000000094',
  true
);
set local role authenticated;
insert into restore_c_result
select public.restore_backup(
  ((select payload->>'backup_id' from restore_c_backup))::uuid,
  'a8082100-0000-4000-8000-000000000003'
);
reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select set_config('request.jwt.claim.sub', '', true);
select ok(
  (
    select payload->>'success' = 'true'
      and payload->>'foundation_safe' = 'true'
      and payload->>'foundation_restore_mode' =
        'same_durable_identity_set'
      and payload->>'supplier_rows_restored_in_place' = '1'
    from restore_c_result
  ),
  'authenticated tenant admin restore completes through the foundation-aware in-place path'
);
select ok(
  (
    select backup.status = 'restored'
      and backup.restored_at is not null
    from public.database_backups backup
    where backup.id = ((
      select payload->>'backup_id' from restore_c_backup
    ))::uuid
  ),
  'successful wrapper restore marks the original durable backup as consumed'
);
select ok(
  (
    select supplier.name = 'Proveedor Historico C'
      and party.display_name = 'Proveedor Historico C'
      and supplier.rut = '66.666.666-6'
      and supplier.party_id = before.party_id
    from public.suppliers supplier
    join public.external_parties party
      on party.tenant_id = supplier.tenant_id
     and party.id = supplier.party_id
    cross join restore_c_before before
    where supplier.id = 'a8082100-0001-4000-8000-000000000107'
  ),
  'same-set restore rehydrates legacy supplier and canonical party without rebinding identity'
);
select ok(
  (
    select credential.vault_secret_id = before.vault_secret_id
      and exists (
        select 1
        from public.supplier_relationship_tags assignment
        where assignment.supplier_id = credential.supplier_id
          and assignment.tag_code = 'digital'
      )
    from public.supplier_credentials credential
    cross join restore_c_before before
    where credential.supplier_id = 'a8082100-0001-4000-8000-000000000107'
      and credential.credential_kind = 'portal_password'
      and credential.credential_key = 'default'
  ),
  'same-set restore preserves Vault credential and foundation classification history'
);
select ok(
  (
    select invoice.invoice_number = 'PI-RESTORE-C-SNAPSHOT'
      and invoice.status = 'received'
      and invoice.total = 200
      and invoice.items->0->>'quantity' = '2'
    from public.purchase_invoices invoice
    where invoice.id = 'a8082100-0006-4000-8000-000000000607'
  ),
  'same-set restore rehydrates the exact purchase-invoice snapshot instead of its placeholder identity'
);
select ok(
  (
    select product.inventory_qty = snapshot.inventory_qty
      and product.stock_quantity = snapshot.stock_quantity
    from public.products product
    cross join restore_c_snapshot snapshot
    where product.id = 'a8082100-0005-4000-8000-000000000507'
  ),
  'invoice restore leaves product stock exactly at the backup snapshot'
);
select is(
  (
    select coalesce(
      jsonb_agg(to_jsonb(movement) order by movement.id),
      '[]'::jsonb
    )
    from public.stock_movements movement
    where movement.tenant_id = 'a8082100-0000-4000-8000-000000000003'
  ),
  (select stock_movements from restore_c_snapshot),
  'invoice restore leaves stock-movement rows byte-for-byte at the backup snapshot'
);
select is(
  (
    select coalesce(
      jsonb_agg(to_jsonb(entry) order by entry.id),
      '[]'::jsonb
    )
    from public.journal_entries entry
    where entry.tenant_id = 'a8082100-0000-4000-8000-000000000003'
  ),
  (select journal_entries from restore_c_snapshot),
  'invoice restore leaves journal entries byte-for-byte at the backup snapshot'
);
select is(
  (
    select coalesce(
      jsonb_agg(to_jsonb(line) order by line.id),
      '[]'::jsonb
    )
    from public.journal_lines line
    where line.tenant_id = 'a8082100-0000-4000-8000-000000000003'
  ),
  (select journal_lines from restore_c_snapshot),
  'invoice restore leaves journal lines byte-for-byte at the backup snapshot'
);
select ok(
  (
    select count(*) = 1
      and max(line.quantity) = 2
      and max(line.total_amount) = 200
      and bool_and(line.product_id =
        'a8082100-0005-4000-8000-000000000507'::uuid)
    from public.purchase_invoice_lines line
    where line.purchase_invoice_id =
      'a8082100-0006-4000-8000-000000000607'
  ),
  'restore explicitly rebuilds normalized invoice lines without firing derived inventory or journal writers'
);

select ok(
  (public.get_supplier_foundation_reset_preflight(
    'a8082100-0000-4000-8000-000000000001'
  )->>'supported')::boolean is false,
  'supplier factory reset preflight fails closed when durable relationships exist'
);

insert into public.database_backups (
  id, tenant_id, backup_name, backup_type, status, backup_data, summary
) values
  (
    'a8082100-0013-4000-8000-000000001303',
    'a8082100-0000-4000-8000-000000000001',
    'Delete ACL A', 'manual', 'completed', '{}'::jsonb, '{}'::jsonb
  ),
  (
    'a8082100-0013-4000-8000-000000001304',
    'a8082100-0000-4000-8000-000000000002',
    'Delete ACL B', 'manual', 'completed', '{}'::jsonb, '{}'::jsonb
  );

select set_config(
  'request.jwt.claims',
  '{"role":"authenticated","sub":"a8082100-0000-4000-8000-000000000092"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  'a8082100-0000-4000-8000-000000000092',
  true
);
set local role authenticated;
select is(
  (
    select count(*)
    from public.database_backups
    where id = 'a8082100-0013-4000-8000-000000001301'
  ),
  0::bigint,
  'ordinary tenant member cannot raw-read broad backup payloads'
);
select throws_ok(
  $$select public.get_supplier_foundation_reset_preflight(
    'a8082100-0000-4000-8000-000000000001'
  )$$,
  '42501',
  'Supplier foundation reset preflight denied',
  'ordinary tenant member cannot inspect administrative reset blockers'
);
select throws_ok(
  $$select public.redact_supplier_passwords_from_backups(
    'a8082100-0000-4000-8000-000000000001', null, true
  )$$,
  '42501',
  'Backup access denied',
  'ordinary tenant member cannot inspect historical backup remediation targets'
);
with deleted as (
  delete from public.database_backups
  where id = 'a8082100-0013-4000-8000-000000001303'
  returning id
)
select is(
  (select count(*) from deleted),
  0::bigint,
  'ordinary tenant member cannot delete a tenant backup'
);
reset role;

select set_config(
  'request.jwt.claims',
  '{"role":"authenticated","sub":"a8082100-0000-4000-8000-000000000091"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  'a8082100-0000-4000-8000-000000000091',
  true
);
set local role authenticated;
select is(
  (
    select count(*)
    from public.database_backups
    where id = 'a8082100-0013-4000-8000-000000001301'
  ),
  1::bigint,
  'tenant admin can read its guarded backup inventory'
);
select ok(
  public.get_supplier_foundation_reset_preflight(
    'a8082100-0000-4000-8000-000000000001'
  )->>'error_code' = 'supplier_foundation_reset_requires_domain_operation',
  'tenant admin receives an actionable supplier reset error instead of false success'
);
select throws_ok(
  $$select public.get_supplier_foundation_reset_preflight(
    'a8082100-0000-4000-8000-000000000002'
  )$$,
  '42501',
  'Supplier foundation reset preflight denied',
  'supplier reset preflight rejects cross-tenant inspection'
);
select throws_ok(
  $$select public.redact_supplier_passwords_from_backups(
    'a8082100-0000-4000-8000-000000000002', null, true
  )$$,
  '42501',
  'Backup access denied',
  'tenant backup admin cannot inspect another tenant remediation targets'
);
with deleted as (
  delete from public.database_backups
  where id = 'a8082100-0013-4000-8000-000000001304'
  returning id
)
select is(
  (select count(*) from deleted),
  0::bigint,
  'tenant admin cannot delete another tenant backup'
);
with deleted as (
  delete from public.database_backups
  where id = 'a8082100-0013-4000-8000-000000001303'
  returning id
)
select is(
  (select count(*) from deleted),
  1::bigint,
  'tenant admin retains supported direct backup deletion through guarded RLS'
);
reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select set_config('request.jwt.claim.sub', '', true);

select ok(
  (
    select result->>'dry_run' = 'true'
      and result->>'candidate_backup_count' = '1'
      and result->>'nonnull_secret_value_count' = '1'
      and result->>'nonnull_sensitive_value_count' = '1'
      and result->>'redacted_backup_count' = '0'
    from (
      select public.redact_supplier_passwords_from_backups(
        'a8082100-0000-4000-8000-000000000001',
        array['a8082100-0013-4000-8000-000000001301'::uuid],
        true
      ) result
    ) dry_run
  ),
  'historical backup remediation is explicit dry-run by default'
);
select ok(
  (
    select (backup_data->'suppliers'->0) ? 'portal_password'
    from public.database_backups
    where id = 'a8082100-0013-4000-8000-000000001301'
  ),
  'dry-run does not silently rewrite backup history'
);
select is(
  public.redact_supplier_passwords_from_backups(
    'a8082100-0000-4000-8000-000000000001',
    array['a8082100-0013-4000-8000-000000001301'::uuid],
    false
  )->>'redacted_backup_count',
  '1',
  'authorized explicit remediation redacts selected backup in place'
);
select ok(
  exists (
    select 1
    from public.database_backups backup
    cross join supplier_backup_before_redaction before_redaction
    where backup.id = 'a8082100-0013-4000-8000-000000001301'
      and backup.backup_data->'suppliers'->0->>'id' =
        'a8082100-0001-4000-8000-000000000101'
      and backup.backup_data->'suppliers'->1->>'id' =
        'a8082100-0001-4000-8000-000000000102'
      and not ((backup.backup_data->'suppliers'->0) ? 'portal_password')
      and not ((backup.backup_data->'suppliers'->0) ? 'portal_username')
      and backup.backup_size_bytes = length(backup.backup_data::text)
      and backup.backup_size_bytes < before_redaction.backup_size_bytes
  ),
  'remediation preserves row and supplier order while refreshing sanitized size'
);
select ok(
  (
    select result->>'dry_run' = 'true'
      and result->>'candidate_backup_count' = '0'
      and result->>'nonnull_secret_value_count' = '0'
      and result->>'nonnull_sensitive_value_count' = '0'
      and result->>'redacted_backup_count' = '0'
    from (
      select public.redact_supplier_passwords_from_backups(
        'a8082100-0000-4000-8000-000000000001',
        array['a8082100-0013-4000-8000-000000001301'::uuid],
        true
      ) result
    ) post_remediation_readback
  ),
  'post-remediation readback reports zero remaining backup candidates'
);
create temporary table supplier_backup_after_redaction as
select backup_data, backup_size_bytes
from public.database_backups
where id = 'a8082100-0013-4000-8000-000000001301';
select ok(
  (
    select result->>'dry_run' = 'false'
      and result->>'candidate_backup_count' = '0'
      and result->>'nonnull_secret_value_count' = '0'
      and result->>'nonnull_sensitive_value_count' = '0'
      and result->>'redacted_backup_count' = '0'
      and exists (
        select 1
        from public.database_backups backup
        cross join supplier_backup_after_redaction after_redaction
        where backup.id = 'a8082100-0013-4000-8000-000000001301'
          and backup.backup_data = after_redaction.backup_data
          and backup.backup_size_bytes = after_redaction.backup_size_bytes
      )
    from (
      select public.redact_supplier_passwords_from_backups(
        'a8082100-0000-4000-8000-000000000001',
        array['a8082100-0013-4000-8000-000000001301'::uuid],
        false
      ) result
    ) idempotent_replay
  ),
  'historical backup remediation replay is an idempotent no-op'
);
select ok(
  not has_function_privilege(
    'service_role',
    'public.create_backup_legacy_unsafe_internal(uuid,text,text,text)',
    'EXECUTE'
  ) and has_function_privilege(
    'service_role',
    'public.create_backup_internal(uuid,text,text,text)',
    'EXECUTE'
  ),
  'only transactionally sanitizing backup owner is service executable'
);

create temporary table port_credential_deleted (payload jsonb);
insert into port_credential_deleted
select public.delete_supplier_credential_v2(
  'a8082100-0000-4000-8000-000000000001',
  'a8082100-0001-4000-8000-000000000101',
  'portal_password', 'port8443',
  'a8082100-0400-4000-8000-000000000008',
  ((select payload->>'updated_at' from port_credential_rotated))::timestamptz
);
select is(
  (select payload->>'deleted' from port_credential_deleted),
  'true',
  'keyed credential delete removes Vault secret and metadata atomically'
);
select is(
  public.delete_supplier_credential_v2(
    'a8082100-0000-4000-8000-000000000001',
    'a8082100-0001-4000-8000-000000000101',
    'portal_password', 'port8443',
    'a8082100-0400-4000-8000-000000000008',
    ((select payload->>'updated_at' from port_credential_rotated))::timestamptz
  )->>'idempotent_replay',
  'true',
  'lost-ack credential delete replays its durable tombstone'
);
select throws_ok(
  $$select public.delete_supplier_credential_v2(
    'a8082100-0000-4000-8000-000000000001',
    'a8082100-0001-4000-8000-000000000101',
    'portal_password', 'port8443',
    'a8082100-0400-4000-8000-000000000009',
    ((select payload->>'updated_at' from port_credential_rotated))::timestamptz
  )$$,
  '40001',
  'Supplier credential changed concurrently or was deleted',
  'new stale delete cannot act after the credential was removed'
);
select ok(
  exists (
    select 1
    from public.supplier_credential_access_events
    where supplier_id = 'a8082100-0001-4000-8000-000000000101'
      and credential_key = 'port8443'
      and action = 'delete'
  ),
  'credential delete keeps durable audit snapshot'
);
select is(
  (
    select count(*)
    from public.supplier_credential_access_events
    where supplier_id = 'a8082100-0001-4000-8000-000000000101'
      and credential_key = 'port8443'
      and action = 'delete'
  ),
  1::bigint,
  'delete replay and stale delete do not duplicate delete audit evidence'
);
select ok(
  exists (
    select 1
    from public.supplier_credential_command_receipts receipt
    where receipt.operation_id = 'a8082100-0400-4000-8000-000000000008'
      and receipt.command_kind = 'delete'
      and receipt.result->>'deleted' = 'true'
      and not (receipt.result::text ilike '%port-secret%')
  ),
  'credential delete receipt is a durable secret-free tombstone'
);

select * from finish();

rollback;
