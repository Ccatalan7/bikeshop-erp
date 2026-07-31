begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

select plan(364);

select has_column(
  'public',
  'user_invitations',
  'token_hash',
  'invitations persist only a one-way token verifier'
);
select has_column(
  'public',
  'user_invitations',
  'token_issued_at',
  'invitation token rotation has an issuance timestamp'
);
select has_column(
  'public',
  'user_invitations',
  'accepted_user_id',
  'accepted invitations retain the Auth identity receipt'
);
select has_column(
  'public',
  'user_invitations',
  'accepted_at',
  'accepted invitations retain their acceptance timestamp'
);
select has_column(
  'public',
  'user_invitations',
  'consumed_token_hash',
  'accepted invitation retries use a one-way consumed-token receipt'
);
select is(
  (
    select constraint_row.confrelid::regclass::text
    from pg_constraint constraint_row
    where constraint_row.conrelid = 'public.employees'::regclass
      and constraint_row.conname = 'employees_user_id_fkey'
  ),
  'auth.users',
  'employee login identities reference Auth directly, not the legacy profile mirror'
);
select has_column(
  'public',
  'employee_portal_accounts',
  'password_reset_required_at',
  'worker reset gates retain the timestamp required for Auth audit proof'
);
select has_column(
  'public',
  'employee_portal_accounts',
  'password_credential_issued_at',
  'worker reset gates distinguish DB intent from completed Auth issuance'
);
select has_column(
  'public',
  'employee_portal_accounts',
  'password_reset_challenge_started_at',
  'worker reset completion is bound to a post-login server challenge'
);
select has_function(
  'public',
  'is_authoritative_worker_portal_identity',
  array['uuid', 'uuid', 'uuid'],
  'worker authority is verified against Auth metadata and DB links'
);
select has_function(
  'public',
  'lock_auth_membership_identities',
  array['uuid', 'uuid'],
  'cross-table Auth membership checks share one transaction lock'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.lock_auth_membership_identities(uuid,uuid)',
    'EXECUTE'
  ),
  'membership serialization is an internal trigger primitive'
);
select has_function(
  'public',
  'revoke_worker_portal_sessions',
  array['uuid', 'uuid'],
  'worker suspension and admin reset have a canonical session revoker'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.revoke_worker_portal_sessions(uuid,uuid)',
    'EXECUTE'
  ),
  'trusted worker lifecycle workflows can revoke worker sessions'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.revoke_worker_portal_sessions(uuid,uuid)',
    'EXECUTE'
  ),
  'browser clients cannot invoke worker session revocation'
);
select has_trigger(
  'public',
  'employee_portal_accounts',
  'trg_guard_worker_portal_identity',
  'worker portal links require one dedicated authoritative identity'
);
select has_trigger(
  'public',
  'user_profiles',
  'trg_guard_worker_profile_overlap',
  'active ERP profiles cannot overlap worker portal identities'
);
select has_trigger(
  'public',
  'employees',
  'trg_guard_worker_staff_employee_overlap',
  'ERP employee user links cannot overlap worker portal identities'
);
select has_function(
  'public',
  'deactivate_worker_portal_on_employee_exit',
  array[]::text[],
  'employee exit has one canonical worker credential shutdown'
);
select has_trigger(
  'public',
  'employees',
  'trg_deactivate_worker_portal_on_employee_exit',
  'employee exit atomically closes linked worker access'
);
select has_function(
  'public',
  'guard_linked_worker_employee_delete',
  array[]::text[],
  'linked employees are preserved until Auth cleanup is explicit'
);
select has_trigger(
  'public',
  'employees',
  'trg_guard_linked_worker_employee_delete',
  'physical employee deletion cannot orphan a worker Auth identity'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.deactivate_worker_portal_on_employee_exit()',
    'EXECUTE'
  ),
  'clients cannot invoke the employee-exit credential trigger directly'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.guard_linked_worker_employee_delete()',
    'EXECUTE'
  ),
  'clients cannot bypass the linked-employee deletion guard'
);
select ok(
  not has_table_privilege(
    'anon',
    'public.employee_portal_accounts',
    'SELECT'
  ),
  'anonymous callers cannot enumerate worker login identities'
);
select ok(
  not has_table_privilege(
    'anon',
    'public.employee_portal_accounts',
    'INSERT'
  ),
  'anonymous callers cannot create worker portal links'
);
select ok(
  not has_table_privilege(
    'anon',
    'public.employee_portal_accounts',
    'UPDATE'
  ),
  'anonymous callers cannot mutate worker portal links'
);
select ok(
  not has_table_privilege(
    'anon',
    'public.employee_portal_accounts',
    'DELETE'
  ),
  'anonymous callers cannot delete worker portal links'
);
select ok(
  not has_table_privilege(
    'authenticated',
    'public.employee_portal_accounts',
    'SELECT'
  ),
  'signed-in clients cannot enumerate worker login identities'
);
select ok(
  not has_table_privilege(
    'authenticated',
    'public.employee_portal_accounts',
    'INSERT'
  ),
  'signed-in clients cannot bypass the admin worker creation workflow'
);
select ok(
  not has_table_privilege(
    'authenticated',
    'public.employee_portal_accounts',
    'UPDATE'
  ),
  'signed-in clients cannot relink or reactivate worker identities'
);
select ok(
  not has_table_privilege(
    'authenticated',
    'public.employee_portal_accounts',
    'DELETE'
  ),
  'signed-in clients cannot delete worker portal identities'
);
select ok(
  has_table_privilege(
    'service_role',
    'public.employee_portal_accounts',
    'SELECT'
  ),
  'trusted server workflows can read worker portal links'
);
select ok(
  has_table_privilege(
    'service_role',
    'public.employee_portal_accounts',
    'INSERT'
  ),
  'trusted server workflows can create worker portal links'
);
select ok(
  has_table_privilege(
    'service_role',
    'public.employee_portal_accounts',
    'UPDATE'
  ),
  'trusted server workflows can update worker portal links'
);
select ok(
  has_table_privilege(
    'service_role',
    'public.employee_portal_accounts',
    'DELETE'
  ),
  'trusted server workflows can delete worker portal links'
);
select is(
  (
    select count(*)::integer
    from pg_policies policy
    where policy.schemaname = 'public'
      and policy.tablename = 'employee_portal_accounts'
  ),
  0,
  'worker portal table has no browser-facing RLS policy'
);
select is(
  (
    select string_agg(
      policy.policyname || ':' || policy.cmd || ':' || policy.roles::text,
      ','
      order by policy.policyname
    )
    from pg_policies policy
    where policy.schemaname = 'public'
      and policy.tablename = 'employees'
  ),
  'employees_insert_managers:INSERT:{authenticated},'
    || 'employees_read_authorized:SELECT:{authenticated},'
    || 'employees_update_managers:UPDATE:{authenticated}',
  'employee RLS limits reads and lifecycle writes to authorized identities'
);
select ok(
  not has_table_privilege('anon', 'public.employees', 'SELECT'),
  'anonymous callers cannot enumerate employees'
);
select ok(
  not has_table_privilege('anon', 'public.employees', 'UPDATE'),
  'anonymous callers cannot mutate employees'
);
select ok(
  not has_table_privilege('authenticated', 'public.employees', 'TRUNCATE'),
  'signed-in users never receive destructive employee table privileges'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.resolve_worker_login_internal(text,text)',
    'EXECUTE'
  ),
  'the unguarded worker resolver body is server-internal'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.get_my_worker_portal_context_internal()',
    'EXECUTE'
  ),
  'the unguarded worker context body is internal'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.begin_my_worker_password_reset_internal()',
    'EXECUTE'
  ),
  'the unguarded worker reset start body is internal'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.complete_my_worker_password_reset_internal()',
    'EXECUTE'
  ),
  'the unguarded worker reset completion body is internal'
);

select ok(
  (select relrowsecurity from pg_class where oid = 'public.tenants'::regclass),
  'tenants have RLS enabled'
);
select ok(
  (
    select relrowsecurity
    from pg_class
    where oid = 'public.reserved_subdomains'::regclass
  ),
  'reserved subdomains have RLS enabled'
);
select has_view(
  'public',
  'public_reserved_subdomains',
  'reserved subdomain lookup uses a bounded public view'
);
select ok(
  not has_table_privilege(
    'anon',
    'public.reserved_subdomains',
    'SELECT'
  ),
  'anonymous callers cannot read reserved-subdomain reasons or timestamps'
);
select ok(
  has_table_privilege(
    'anon',
    'public.public_reserved_subdomains',
    'SELECT'
  ),
  'anonymous signup can read the safe reserved-subdomain projection'
);
select is(
  (
    select string_agg(column_name, ',' order by ordinal_position)
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'public_reserved_subdomains'
  ),
  'subdomain',
  'the public reserved-subdomain view exposes only subdomain'
);
select ok(
  (
    select relrowsecurity
    from pg_class
    where oid = 'public.user_profiles'::regclass
  ),
  'staff profiles have RLS enabled'
);
select ok(
  (
    select relrowsecurity
    from pg_class
    where oid = 'public.user_invitations'::regclass
  ),
  'staff invitations have RLS enabled'
);
select has_view(
  'public',
  'public_tenant_directory',
  'public storefront routing uses a bounded tenant directory'
);
select ok(
  not has_table_privilege('anon', 'public.tenants', 'SELECT'),
  'anonymous clients cannot read the tenant authority table'
);
select ok(
  has_table_privilege(
    'anon',
    'public.public_tenant_directory',
    'SELECT'
  ),
  'anonymous storefront routing can read the safe tenant directory'
);
select ok(
  not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'public_tenant_directory'
      and column_name = 'owner_email'
  ),
  'the public tenant directory does not expose owner email'
);
select ok(
  not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'public_tenant_directory'
      and column_name = 'plan'
  ),
  'the public tenant directory does not expose subscription plan'
);
select is(
  (
    select string_agg(column_name, ',' order by ordinal_position)
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'public_tenant_directory'
  ),
  'id,shop_name,subdomain,is_active,logo_url,currency,timezone,custom_domain,created_at,updated_at',
  'the public tenant directory has only the documented safe projection'
);

select ok(
  position(
    'when count(*) = 1'
    in pg_get_functiondef('public.user_tenant_id()'::regprocedure)
  ) > 0,
  'ambiguous active staff memberships fail closed instead of using LIMIT 1'
);
select ok(
  not exists (
    select 1
    from auth.users auth_user
    where coalesce(auth_user.raw_user_meta_data, '{}'::jsonb)
      ?| array[
        'account_type',
        'tenant_id',
        'employee_id',
        'role',
        'permissions',
        'customer_id',
        'customer_tenant_id',
        'invitation_token'
      ]
  ),
  'migration strips authority-shaped user metadata from linked and orphan identities'
);
select has_index(
  'public',
  'user_invitations',
  'user_invitations_pending_token_hash_uidx',
  'pending invitation token hashes cannot be reused'
);
select has_index(
  'public',
  'user_invitations',
  'user_invitations_one_pending_email_per_tenant_uidx',
  'one tenant cannot create concurrent pending invitations for one email'
);
select ok(
  not exists (
    select 1
    from pg_constraint constraint_row
    where constraint_row.conrelid = 'public.user_invitations'::regclass
      and constraint_row.conname =
        'user_invitations_tenant_id_email_status_key'
  ),
  'accepted and expired invitation history is not globally unique by status'
);
select has_index(
  'public',
  'user_profiles',
  'user_profiles_one_active_tenant_per_user_uidx',
  'one Auth identity can have only one active ERP tenant profile'
);

select is(
  (
    select count(*)::integer
    from pg_policies
    where schemaname = 'public'
      and tablename = 'user_invitations'
  ),
  0,
  'invitation rows have no direct anon or authenticated policy'
);

select ok(
  not has_table_privilege(
    'anon',
    'public.user_invitations',
    'SELECT'
  ),
  'anonymous clients cannot list invitation rows'
);
select ok(
  not has_table_privilege(
    'authenticated',
    'public.user_invitations',
    'INSERT'
  ),
  'authenticated clients cannot create invitation rows directly'
);
select ok(
  not has_table_privilege(
    'authenticated',
    'public.user_profiles',
    'INSERT'
  ),
  'authenticated users cannot self-enrol in a tenant'
);
select ok(
  has_table_privilege(
    'authenticated',
    'public.user_profiles',
    'SELECT'
  ),
  'authenticated users can read profiles allowed by RLS'
);
select ok(
  not has_table_privilege('anon', 'public.tenants', 'INSERT'),
  'anonymous clients cannot create tenants directly'
);
select ok(
  not has_table_privilege('authenticated', 'public.tenants', 'DELETE'),
  'authenticated clients cannot delete tenants directly'
);
select ok(
  has_column_privilege(
    'authenticated',
    'public.tenants',
    'custom_domain',
    'UPDATE'
  ),
  'authenticated managers retain the bounded custom-domain update'
);
select ok(
  not has_column_privilege(
    'authenticated',
    'public.tenants',
    'owner_email',
    'UPDATE'
  ),
  'tenant owner identity cannot be rewritten from the client'
);

select has_function(
  'public',
  'rotate_user_invitation_token',
  array['uuid', 'uuid', 'text', 'timestamp with time zone'],
  'service invitation-token rotation RPC exists'
);
select has_function(
  'public',
  'lookup_user_invitation',
  array['text'],
  'public bearer-token invitation lookup RPC exists'
);
select has_function(
  'public',
  'get_tenant_users',
  array['uuid'],
  'tenant-scoped staff list RPC remains available'
);
select has_function(
  'public',
  'delete_tenant_user',
  array['uuid'],
  'legacy delete RPC remains as an owner-only disabled compatibility stub'
);
select has_function(
  'public',
  'accept_user_invitation',
  array['text'],
  'existing confirmed Auth users can accept invitations atomically'
);
select has_function(
  'public',
  'complete_my_worker_password_reset',
  array[]::text[],
  'worker password reset completion RPC exists without client-supplied proof'
);
select has_function(
  'public',
  'begin_my_worker_password_reset',
  array[]::text[],
  'worker reset challenge RPC exists without client-supplied timestamps'
);
select has_function(
  'public',
  'begin_worker_password_credential_issue',
  array['uuid', 'uuid'],
  'service reset issuance begins with an atomic DB version marker'
);
select has_function(
  'public',
  'finish_worker_password_credential_issue',
  array['uuid', 'uuid', 'timestamp with time zone'],
  'service reset issuance finishes through a compare-and-set marker'
);

select ok(
  has_function_privilege(
    'anon',
    'public.lookup_user_invitation(text)',
    'EXECUTE'
  ),
  'anonymous invitation pages can resolve a high-entropy bearer token'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.rotate_user_invitation_token(uuid,uuid,text,timestamp with time zone)',
    'EXECUTE'
  ),
  'anonymous clients cannot rotate invitation tokens'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.rotate_user_invitation_token(uuid,uuid,text,timestamp with time zone)',
    'EXECUTE'
  ),
  'authenticated clients cannot rotate invitation tokens directly'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.rotate_user_invitation_token(uuid,uuid,text,timestamp with time zone)',
    'EXECUTE'
  ),
  'the verified Edge service can rotate invitation tokens'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.accept_user_invitation(text)',
    'EXECUTE'
  ),
  'authenticated existing users can accept their bearer invitation'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.accept_user_invitation(text)',
    'EXECUTE'
  ),
  'anonymous callers cannot consume invitations through the existing-user RPC'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.get_tenant_users(uuid)',
    'EXECUTE'
  ),
  'anonymous clients cannot enumerate tenant staff'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.get_tenant_users(uuid)',
    'EXECUTE'
  ),
  'authenticated tenant members retain the staff list contract'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.delete_tenant_user(uuid)',
    'EXECUTE'
  ),
  'authenticated callers cannot invoke the legacy Auth deletion function'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.handle_new_user()',
    'EXECUTE'
  ),
  'the Auth provisioning trigger is owner-only'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.worker_portal_tenant_id()',
    'EXECUTE'
  ),
  'authenticated workers retain their tenant helper'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.worker_portal_tenant_id()',
    'EXECUTE'
  ),
  'anonymous callers cannot invoke worker tenant context'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.begin_my_worker_password_reset()',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.begin_my_worker_password_reset()',
    'EXECUTE'
  )
  and has_function_privilege(
    'authenticated',
    'public.complete_my_worker_password_reset()',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.complete_my_worker_password_reset()',
    'EXECUTE'
  ),
  'only authenticated workers can request audit-backed reset completion'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.get_my_worker_portal_context()',
    'EXECUTE'
  ),
  'authenticated workers retain their bounded context reader'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.resolve_worker_login(text,text)',
    'EXECUTE'
  ),
  'anonymous callers cannot enumerate worker login identities'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.resolve_worker_login(text,text)',
    'EXECUTE'
  )
  and has_function_privilege(
    'service_role',
    'public.resolve_worker_login(text,text)',
    'EXECUTE'
  ),
  'worker identity resolution is restricted to the constant-response Edge proxy'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.begin_worker_password_credential_issue(uuid,uuid)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.begin_worker_password_credential_issue(uuid,uuid)',
    'EXECUTE'
  )
  and has_function_privilege(
    'service_role',
    'public.begin_worker_password_credential_issue(uuid,uuid)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.finish_worker_password_credential_issue(uuid,uuid,timestamp with time zone)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.finish_worker_password_credential_issue(uuid,uuid,timestamp with time zone)',
    'EXECUTE'
  )
  and has_function_privilege(
    'service_role',
    'public.finish_worker_password_credential_issue(uuid,uuid,timestamp with time zone)',
    'EXECUTE'
  ),
  'only the trusted Admin Edge flow can mark credential issuance phases'
);
select is(
  (
    select array_to_string(routine.proconfig, ',')
    from pg_proc routine
    where routine.oid = 'public.handle_new_user()'::regprocedure
  ),
  'search_path=pg_catalog, public, extensions, pg_temp',
  'Auth provisioning has an immutable trusted search path'
);
select is(
  (
    select array_to_string(routine.proconfig, ',')
    from pg_proc routine
    where routine.oid =
      'public.rotate_user_invitation_token(uuid,uuid,text,timestamp with time zone)'::regprocedure
  ),
  'search_path=pg_catalog, public, pg_temp',
  'token rotation has an immutable trusted search path'
);
select is(
  (
    select array_to_string(routine.proconfig, ',')
    from pg_proc routine
    where routine.oid = 'public.worker_portal_tenant_id()'::regprocedure
  ),
  'search_path=pg_catalog, public, pg_temp',
  'worker tenant context has an immutable trusted search path'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.erp_actor_display_name(uuid,uuid)',
    'EXECUTE'
  ),
  'anonymous callers cannot mine Auth display information'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.erp_actor_display_name(uuid,uuid)',
    'EXECUTE'
  ),
  'authenticated callers cannot query arbitrary Auth display information'
);
select ok(
  (
    select relation.relrowsecurity and relation.relforcerowsecurity
    from pg_class relation
    where relation.oid =
      'public.payment_integrity_backfill_audit'::regclass
  ),
  'payment backfill evidence has forced RLS'
);
select ok(
  not has_table_privilege(
    'anon',
    'public.payment_integrity_backfill_audit',
    'SELECT'
  )
  and not has_table_privilege(
    'authenticated',
    'public.payment_integrity_backfill_audit',
    'SELECT'
  ),
  'payment backfill evidence is not client-readable'
);
select ok(
  not has_table_privilege(
    'anon',
    'public.payment_integrity_backfill_audit',
    'INSERT,UPDATE,DELETE,TRUNCATE'
  )
  and not has_table_privilege(
    'authenticated',
    'public.payment_integrity_backfill_audit',
    'INSERT,UPDATE,DELETE,TRUNCATE'
  ),
  'payment backfill evidence has no client mutation or truncate grant'
);
select ok(
  has_table_privilege(
    'service_role',
    'public.payment_integrity_backfill_audit',
    'SELECT,INSERT,UPDATE,DELETE,TRUNCATE'
  ),
  'trusted service operations retain payment backfill evidence access'
);
select ok(
  not has_table_privilege(
    'authenticated',
    'public.journal_lines',
    'TRUNCATE'
  )
  and not has_table_privilege(
    'authenticated',
    'public.journal_entries',
    'TRUNCATE'
  ),
  'authenticated callers cannot truncate accounting journals'
);
select ok(
  position(
    'from public.user_profiles'
    in pg_get_functiondef(
      'public.can_manage_tenant_accounting(uuid)'::regprocedure
    )
  ) > 0
  and position(
    'raw_user_meta_data'
    in pg_get_functiondef(
      'public.can_manage_tenant_accounting(uuid)'::regprocedure
    )
  ) = 0,
  'accounting authority comes from DB profiles rather than mutable JWT metadata'
);
select ok(
  not has_table_privilege(
    'authenticated',
    'public.bike_catalog',
    'INSERT,UPDATE,DELETE'
  )
  and has_table_privilege(
    'authenticated',
    'public.bike_catalog',
    'SELECT'
  ),
  'shared bike catalog is client-readable but service-only mutable'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.get_my_worker_attendances(timestamp with time zone,timestamp with time zone)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.get_my_worker_payroll_for_period(date,date)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.get_my_worker_shifts(timestamp with time zone,timestamp with time zone)',
    'EXECUTE'
  ),
  'anonymous callers cannot invoke worker-private readers'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.validate_shift_planning_tenant_consistency()',
    'EXECUTE'
  ),
  'worker planning tenant validator is trigger-only'
);
select ok(
  not exists (
    select 1
    from pg_proc routine
    join pg_namespace namespace
      on namespace.oid = routine.pronamespace
    where namespace.nspname = 'public'
      and routine.prosecdef is true
      and has_function_privilege('anon', routine.oid, 'EXECUTE')
      and routine.oid not in (
        'public.user_tenant_id()'::regprocedure,
        'public.is_tenant_active(uuid)'::regprocedure,
        'public.resolve_public_product_url_alias(uuid,text)'::regprocedure,
        'public.get_public_products(uuid,uuid[],uuid[],text,text,text,boolean,text,integer,integer)'::regprocedure,
        'public.search_public_products(text,uuid,integer)'::regprocedure,
        'public.get_public_featured_products(uuid,integer)'::regprocedure,
        'public.get_public_product_category_counts(uuid,text,boolean)'::regprocedure,
        'public.get_public_products_faceted_v1(uuid,uuid[],text,text,boolean,uuid[],numeric,numeric,text,integer,integer)'::regprocedure,
        'public.get_public_product_facets_v1(uuid,uuid[],text,text,boolean,uuid[],numeric,numeric)'::regprocedure,
        'public.get_public_product_technical_specs(uuid,uuid)'::regprocedure,
        'public.create_public_online_order_with_access(jsonb,jsonb)'::regprocedure,
        'public.get_public_online_order_by_access_token(text)'::regprocedure,
        'public.get_public_product_tax_classifications(uuid,uuid[])'::regprocedure,
        'public.quote_public_online_shipping(uuid,text,numeric,text)'::regprocedure,
        'public.get_public_store_data(uuid)'::regprocedure,
        'public.lookup_user_invitation(text)'::regprocedure
      )
  ),
  'anonymous SECURITY DEFINER execution is limited to the explicit public allowlist'
);
select ok(
  not exists (
    select 1
    from pg_proc routine
    join pg_namespace namespace
      on namespace.oid = routine.pronamespace
    where namespace.nspname = 'public'
      and routine.prosecdef is true
      and routine.prorettype = 'trigger'::regtype
      and (
        has_function_privilege('anon', routine.oid, 'EXECUTE')
        or has_function_privilege('authenticated', routine.oid, 'EXECUTE')
      )
  ),
  'SECURITY DEFINER trigger bodies are not directly client-executable'
);
select ok(
  not exists (
    select 1
    from pg_proc routine
    join pg_namespace namespace
      on namespace.oid = routine.pronamespace
    where namespace.nspname = 'public'
      and routine.prosecdef is true
      and (
        routine.proname like 'seed\_%' escape '\'
        or routine.proname = any (array[
          'create_backup_internal',
          'restore_backup_internal',
          'get_backup_summary_internal',
          'cleanup_old_backups_internal',
          'create_website_backup_internal',
          'restore_website_backup_internal',
          'run_due_backup_schedules'
        ])
      )
      and (
        has_function_privilege('anon', routine.oid, 'EXECUTE')
        or has_function_privilege('authenticated', routine.oid, 'EXECUTE')
      )
  ),
  'seed and backup SECURITY DEFINER routines are service-only'
);
select ok(
  not exists (
    select 1
    from pg_proc routine
    join pg_namespace namespace
      on namespace.oid = routine.pronamespace
    where namespace.nspname = 'public'
      and routine.prosecdef is true
      and routine.proname = any (array[
        'ensure_account_internal',
        'create_sales_payment_journal_entry',
        'delete_sales_payment_journal_entry',
        'delete_sales_invoice_journal_entry',
        'ensure_sales_invoice_journal_entry_internal',
        'delete_purchase_invoice_journal_entry',
        'recalculate_journal_entry_totals',
        'sync_journal_entry_totals_from_lines',
        'create_employee_advance_journal_entry',
        'create_employee_advance_allocation_journal_entry',
        'ensure_payroll_line_expense',
        'capture_posted_journal_supersession_evidence',
        'checkpoint_journal_entry_trace',
        'begin_invoice_inventory_accounting_trace',
        'complete_invoice_inventory_accounting_trace'
      ])
      and (
        has_function_privilege('anon', routine.oid, 'EXECUTE')
        or has_function_privilege('authenticated', routine.oid, 'EXECUTE')
      )
  ),
  'dangerous accounting SECURITY DEFINER mutators are service-only'
);
select ok(
  not exists (
    select 1
    from pg_namespace namespace
    cross join lateral aclexplode(
      coalesce(
        namespace.nspacl,
        acldefault('n', namespace.nspowner)
      )
    ) privilege
    where namespace.nspname = 'public'
      and privilege.privilege_type = 'CREATE'
      and privilege.grantee in (
        0,
        (select oid from pg_roles where rolname = 'anon'),
        (select oid from pg_roles where rolname = 'authenticated')
      )
  )
  and has_schema_privilege('anon', 'public', 'USAGE')
  and has_schema_privilege('authenticated', 'public', 'USAGE'),
  'API roles retain schema usage but cannot create public-schema objects'
);
select ok(
  not exists (
    select 1
    from pg_default_acl defaults
    cross join lateral aclexplode(
      coalesce(
        defaults.defaclacl,
        acldefault('f', defaults.defaclrole)
      )
    ) privilege
    where defaults.defaclnamespace = 'public'::regnamespace
      and defaults.defaclobjtype = 'f'
      and defaults.defaclrole = current_user::regrole
      and privilege.privilege_type = 'EXECUTE'
      and privilege.grantee in (
        0,
        (select oid from pg_roles where rolname = 'anon'),
        (select oid from pg_roles where rolname = 'authenticated')
      )
  ),
  'future application-owned public functions do not default to API-role execution'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.create_backup(uuid,text,text,text)',
    'EXECUTE'
  )
  and has_function_privilege(
    'authenticated',
    'public.restore_backup(uuid,uuid)',
    'EXECUTE'
  )
  and has_function_privilege(
    'authenticated',
    'public.get_backup_summary(uuid)',
    'EXECUTE'
  )
  and has_function_privilege(
    'authenticated',
    'public.cleanup_old_backups(uuid)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.create_backup_internal(uuid,text,text,text)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.restore_backup_internal(uuid,uuid)',
    'EXECUTE'
  ),
  'general backup client wrappers remain callable while internals are private'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.create_website_backup(text,text,boolean)',
    'EXECUTE'
  )
  and has_function_privilege(
    'authenticated',
    'public.restore_website_backup(uuid,boolean)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.create_website_backup_internal(text,text,boolean)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.restore_website_backup_internal(uuid,boolean)',
    'EXECUTE'
  ),
  'website backup client wrappers remain callable while internals are private'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.ensure_account(text,text,text,text,text,text)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.ensure_account(uuid,text,text,text,text,text,text)',
    'EXECUTE'
  )
  and has_function_privilege(
    'authenticated',
    'public.ensure_sales_invoice_journal_entry(uuid)',
    'EXECUTE'
  )
  and has_function_privilege(
    'authenticated',
    'public.generate_f29_from_accounting(uuid,integer,integer)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.ensure_sales_invoice_journal_entry_internal(uuid)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.generate_f29_from_accounting_internal(uuid,integer,integer)',
    'EXECUTE'
  ),
  'accounting client wrappers keep exact grants and internal bodies stay private'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.get_checked_in_employees()',
    'EXECUTE'
  )
  and has_function_privilege(
    'authenticated',
    'public.get_attendance_summary(uuid,date,date)',
    'EXECUTE'
  )
  and has_function_privilege(
    'authenticated',
    'public.get_employee_hours_summary(uuid,date,date)',
    'EXECUTE'
  )
  and has_function_privilege(
    'authenticated',
    'public.get_attendance_summary_for_period(date,date)',
    'EXECUTE'
  ),
  'Flutter attendance RPC signatures remain authenticated contracts'
);
select ok(
  not exists (
    select 1
    from unnest(array[
      'public.backfill_stock_at_receipt_for_received_items()'::regprocedure,
      'public.migrate_job_statuses()'::regprocedure,
      'public.notify_new_email(uuid,text,text,jsonb)'::regprocedure,
      'public.is_conversation_participant(uuid)'::regprocedure,
      'public.ensure_expense_category(uuid,text,text,uuid)'::regprocedure,
      'public.log_mechanic_job_timeline(uuid,text,text,text,text)'::regprocedure,
      'public.generate_expense_number()'::regprocedure,
      'public.get_account_balance(uuid,timestamptz,timestamptz)'::regprocedure,
      'public.get_balances_by_type(text,timestamptz,timestamptz)'::regprocedure,
      'public.get_balances_by_category(text,timestamptz,timestamptz)'::regprocedure,
      'public.get_cumulative_balance(uuid,timestamptz)'::regprocedure,
      'public.get_cumulative_balances_by_type(text,timestamptz)'::regprocedure,
      'public.get_expense_category_name_for_account(text,text)'::regprocedure,
      'public.is_auth_user_db_backed_tenant_owner(uuid,uuid)'::regprocedure,
      'public.save_bike_aggregate_internal(text,uuid,uuid,timestamptz,timestamptz,jsonb,jsonb)'::regprocedure,
      'public.get_bike_aggregate_internal(uuid)'::regprocedure,
      'public.get_bike_aggregate_save_operation_internal(text)'::regprocedure,
      'public.save_expense_aggregate_internal(text,uuid,timestamptz,jsonb)'::regprocedure,
      'public.get_expense_aggregate_save_operation_internal(text)'::regprocedure
    ]) signature
    where has_function_privilege(
      'authenticated',
      signature,
      'EXECUTE'
    )
      or has_function_privilege('anon', signature, 'EXECUTE')
      or not has_function_privilege('service_role', signature, 'EXECUTE')
  ),
  'legacy maintenance helpers are exact service-only contracts'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.generate_mechanic_job_number()',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.generate_mechanic_job_number()',
    'EXECUTE'
  )
  and has_function_privilege(
    'anon',
    'public.get_public_store_data(uuid)',
    'EXECUTE'
  )
  and has_function_privilege(
    'authenticated',
    'public.save_mercadopago_settings(text,text,boolean)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.save_mercadopago_settings(text,text,boolean)',
    'EXECUTE'
  )
  and has_function_privilege(
    'authenticated',
    'public.find_compatible_hubs(uuid,uuid,numeric,text)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.find_compatible_hubs(uuid,uuid,numeric,text)',
    'EXECUTE'
  )
  and has_function_privilege(
    'authenticated',
    'public.find_compatible_spokes(uuid,numeric,numeric)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.find_compatible_spokes(uuid,numeric,numeric)',
    'EXECUTE'
  ),
  'column defaults, storefront, and secret writer retain exact grants'
);
select ok(
  not exists (
    select 1
    from pg_proc routine
    join pg_namespace namespace
      on namespace.oid = routine.pronamespace
    where namespace.nspname = 'public'
      and routine.prosecdef is true
      and has_function_privilege(
        'authenticated',
        routine.oid,
        'EXECUTE'
      )
      and (
        lower(pg_get_functiondef(routine.oid)) like '%request.jwt%'
        or lower(pg_get_functiondef(routine.oid)) like '%auth.jwt()%'
      )
  ),
  'authenticated SECURITY DEFINER routines do not authorize from JWT payload claims'
);
select ok(
  not exists (
    select 1
    from pg_proc routine
    join pg_namespace namespace
      on namespace.oid = routine.pronamespace
    where namespace.nspname = 'public'
      and routine.prosecdef is true
      and has_function_privilege(
        'authenticated',
        routine.oid,
        'EXECUTE'
      )
      and lower(pg_get_functiondef(routine.oid)) ~
        $pattern$raw_user_meta_data\s*->>?\s*'(account_type|tenant_id|employee_id|role|permissions|customer_id|customer_tenant_id)'$pattern$
  ),
  'authenticated SECURITY DEFINER routines never derive authority from user metadata'
);
select is(
  (
    select array_to_string(routine.proargnames, ',')
    from pg_proc routine
    where routine.oid =
      'public.lookup_user_invitation(text)'::regprocedure
  ),
  'p_token,invitation_id,email,role,tenant_id,shop_name,expires_at',
  'invitation lookup exposes only the documented bounded fields'
);
select ok(
  not exists (
    select 1
    from pg_constraint constraint_record
    join pg_attribute attribute
      on attribute.attrelid = constraint_record.conrelid
     and attribute.attnum = constraint_record.conkey[1]
    where constraint_record.conrelid = 'public.customers'::regclass
      and constraint_record.contype = 'u'
      and array_length(constraint_record.conkey, 1) = 1
      and attribute.attname = 'email'
  ),
  'customer email is no longer globally unique across storefront tenants'
);
select has_index(
  'public',
  'customers',
  'customers_tenant_email_lower_uidx',
  'customer email identity is unique per tenant case-insensitively'
);
select has_index(
  'public',
  'customers',
  'customers_tenant_auth_user_uidx',
  'one Auth identity has at most one customer row per tenant'
);
select ok(
  not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'customers'
      and policyname = 'public_customers_insert_own'
  ),
  'public customer rows cannot be inserted directly by arbitrary tenant id'
);
select is(
  (
    select count(*)::integer
    from pg_policies
    where schemaname = 'public'
      and (
        tablename,
        policyname
      ) in (
        (
          'customer_addresses',
          'public_customer_addresses_select_own'
        ),
        (
          'customer_addresses',
          'public_customer_addresses_insert_own'
        ),
        (
          'customer_addresses',
          'public_customer_addresses_update_own'
        ),
        (
          'customer_addresses',
          'public_customer_addresses_delete_own'
        ),
        (
          'online_orders',
          'public_online_orders_select_authenticated'
        ),
        (
          'online_order_items',
          'public_online_order_items_select_authenticated'
        ),
        (
          'mechanic_jobs',
          'public_mechanic_jobs_select_own'
        ),
        (
          'bikes',
          'public_bikes_select_own'
        )
      )
      and (
        coalesce(qual, '') || coalesce(with_check, '')
      ) like '%is_active%'
      and (
        coalesce(qual, '') || coalesce(with_check, '')
      ) like '%tenant_id%'
  ),
  8,
  'all customer-owned child policies require active tenant-consistent membership'
);
select ok(
  not exists (
    select 1
    from pg_class relation
    where relation.oid = any (
      array[
        'public.customer_addresses'::regclass,
        'public.online_orders'::regclass,
        'public.online_order_items'::regclass,
        'public.mechanic_jobs'::regclass,
        'public.bikes'::regclass
      ]
    )
      and relation.relrowsecurity is false
  ),
  'RLS is enabled on every customer-owned child table'
);
select ok(
  not exists (
    with expected(tablename, policyname) as (
      values
        ('customer_addresses', 'customer_addresses_select'),
        ('customer_addresses', 'customer_addresses_insert'),
        ('customer_addresses', 'customer_addresses_update'),
        ('customer_addresses', 'customer_addresses_delete'),
        ('customer_addresses', 'public_customer_addresses_select_own'),
        ('customer_addresses', 'public_customer_addresses_insert_own'),
        ('customer_addresses', 'public_customer_addresses_update_own'),
        ('customer_addresses', 'public_customer_addresses_delete_own'),
        ('online_orders', 'online_orders_select'),
        ('online_orders', 'public_online_orders_select_authenticated'),
        ('online_order_items', 'online_order_items_select'),
        (
          'online_order_items',
          'public_online_order_items_select_authenticated'
        ),
        ('mechanic_jobs', 'mechanic_jobs_select'),
        ('mechanic_jobs', 'mechanic_jobs_insert'),
        ('mechanic_jobs', 'mechanic_jobs_update'),
        ('mechanic_jobs', 'mechanic_jobs_delete'),
        ('mechanic_jobs', 'public_mechanic_jobs_select_own'),
        ('bikes', 'bikes_select'),
        ('bikes', 'bikes_insert'),
        ('bikes', 'bikes_update'),
        ('bikes', 'bikes_delete'),
        ('bikes', 'public_bikes_select_own')
    ),
    actual as (
      select policy.tablename, policy.policyname
      from pg_policies policy
      where policy.schemaname = 'public'
        and policy.tablename in (
          'customer_addresses',
          'online_orders',
          'online_order_items',
          'mechanic_jobs',
          'bikes'
        )
    ),
    drift as (
      (select * from expected except select * from actual)
      union all
      (select * from actual except select * from expected)
    )
    select 1 from drift
  )
  and not exists (
    select 1
    from pg_policies policy
    where policy.schemaname = 'public'
      and policy.tablename in (
        'customer_addresses',
        'online_orders',
        'online_order_items',
        'mechanic_jobs',
        'bikes'
      )
      and policy.roles <> array['authenticated']::name[]
  ),
  'customer child RLS is rebuilt to the exact authenticated-only allowlist'
);
select has_trigger(
  'public',
  'customers',
  'trg_guard_customer_identity_update',
  'customer updates have an immutable identity and tenant guard'
);
select has_trigger(
  'public',
  'customer_addresses',
  'trg_guard_customer_address_identity_update',
  'customer address updates cannot move identity between memberships'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.guard_customer_identity_update()',
    'EXECUTE'
  ),
  'the customer identity guard is trigger-only'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.guard_customer_address_identity_update()',
    'EXECUTE'
  ),
  'the customer address identity guard is trigger-only'
);
select has_function(
  'public',
  'provision_current_public_store_customer',
  array['uuid'],
  'confirmed OAuth customers use a tenant-checked provisioning RPC'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.provision_current_public_store_customer(uuid)',
    'EXECUTE'
  ),
  'authenticated customers can invoke the provisioning contract'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.provision_current_public_store_customer(uuid)',
    'EXECUTE'
  ),
  'anonymous callers cannot provision customer identities'
);

-- Keep fixtures small by bypassing tenant bootstrap triggers only while the two
-- isolated tenant rows are created. Auth trigger behavior remains fully active.
set local session_replication_role = replica;

insert into public.tenants (
  id,
  shop_name,
  subdomain,
  owner_email,
  is_active
)
values
  (
    '9f260000-0000-4000-8000-000000000001',
    'Auth Boundary Tenant A',
    'auth-boundary-a',
    'owner-a@example.invalid',
    true
  ),
  (
    '9f260000-0000-4000-8000-000000000002',
    'Auth Boundary Tenant B',
    'auth-boundary-b',
    'owner-b@example.invalid',
    true
  );

insert into auth.users (
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
)
values (
  '9f260000-0000-4000-8000-000000000081',
  'authenticated',
  'authenticated',
  'changed-owner-a@example.invalid',
  '',
  now(),
  jsonb_build_object(
    'account_type', 'erp_owner',
    'tenant_id', '9f260000-0000-4000-8000-000000000001',
    'role', 'admin'
  ),
  '{}'::jsonb,
  now(),
  now()
);

insert into public.user_profiles (
  user_id,
  tenant_id,
  role,
  permissions,
  is_active
)
values (
  '9f260000-0000-4000-8000-000000000081',
  '9f260000-0000-4000-8000-000000000001',
  'admin',
  '{}'::jsonb,
  true
);

set local session_replication_role = origin;

select ok(
  public.is_auth_user_db_backed_tenant_owner(
    '9f260000-0000-4000-8000-000000000081',
    '9f260000-0000-4000-8000-000000000001'
  ),
  'an existing same-tenant owner claim survives an owner email change'
);
select ok(
  not public.is_auth_user_db_backed_tenant_owner(
    '9f260000-0000-4000-8000-000000000081',
    '9f260000-0000-4000-8000-000000000002'
  ),
  'an existing owner claim never transfers authority to another tenant'
);

insert into public.employees (
  id,
  tenant_id,
  employee_number,
  first_name,
  last_name,
  email,
  job_title,
  status
)
values
  (
    '9f260000-0000-4000-8000-000000000011',
    '9f260000-0000-4000-8000-000000000001',
    'AUTH-WORKER-001',
    'Worker',
    'Fixture',
    'worker-auth-boundary@example.invalid',
    'Mechanic',
    'active'
  ),
  (
    '9f260000-0000-4000-8000-000000000012',
    '9f260000-0000-4000-8000-000000000001',
    'AUTH-INVITED-002',
    'Invited',
    'Fixture',
    'invited-auth-boundary@example.invalid',
    'Mechanic',
    'active'
  );

update public.user_profiles
set role = 'cashier',
    permissions = '{}'::jsonb
where user_id = '9f260000-0000-4000-8000-000000000081';

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '9f260000-0000-4000-8000-000000000081',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9f260000-0000-4000-8000-000000000081',
  true
);

set local role authenticated;

update public.employees
set job_title = 'Unauthorized cashier mutation'
where id = '9f260000-0000-4000-8000-000000000011';

reset role;

select is(
  (
    select job_title
    from public.employees
    where id = '9f260000-0000-4000-8000-000000000011'
  ),
  'Mechanic',
  'cashier cannot mutate employee lifecycle data through direct REST'
);

update public.user_profiles
set role = 'admin'
where user_id = '9f260000-0000-4000-8000-000000000081';

set local role authenticated;

update public.employees
set job_title = 'Authorized manager mutation'
where id = '9f260000-0000-4000-8000-000000000011';

reset role;

select is(
  (
    select job_title
    from public.employees
    where id = '9f260000-0000-4000-8000-000000000011'
  ),
  'Authorized manager mutation',
  'DB-backed tenant admin retains employee lifecycle authority'
);

select throws_ok(
  $$
    insert into auth.users (
      id,
      aud,
      role,
      email,
      encrypted_password,
      email_confirmed_at,
      raw_app_meta_data,
      raw_user_meta_data,
      created_at,
      updated_at
    )
    values (
      '9f260000-0000-4000-8000-000000000090',
      'authenticated',
      'authenticated',
      'forged-worker-auth-boundary@example.invalid',
      '',
      now(),
      '{}'::jsonb,
      jsonb_build_object(
        'account_type', 'worker_portal',
        'tenant_id', '9f260000-0000-4000-8000-000000000001',
        'employee_id', '9f260000-0000-4000-8000-000000000011',
        'username', 'forged.worker'
      ),
      now(),
      now()
    )
  $$,
  'P0001',
  'Authoritative worker portal metadata is required',
  'publicly forged worker metadata fails closed without Admin app metadata'
);

insert into auth.users (
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
)
values (
  '9f260000-0000-4000-8000-000000000091',
  'authenticated',
  'authenticated',
  'worker-auth-boundary@example.invalid',
  '',
  now(),
  jsonb_build_object(
    'account_type', 'worker_portal',
    'tenant_id', '9f260000-0000-4000-8000-000000000001',
    'employee_id', '9f260000-0000-4000-8000-000000000011',
    'role', 'worker'
  ),
  jsonb_build_object(
    'account_type', 'worker_portal',
    'tenant_id', '9f260000-0000-4000-8000-000000000001',
    'employee_id', '9f260000-0000-4000-8000-000000000011',
    'username', 'worker.fixture'
  ),
  now(),
  now()
);

select is(
  (
    select count(*)::integer
    from public.user_profiles
    where user_id = '9f260000-0000-4000-8000-000000000091'
  ),
  0,
  'worker Auth creation does not create an ERP staff profile'
);
select is(
  (
    select raw_app_meta_data->>'account_type'
    from auth.users
    where id = '9f260000-0000-4000-8000-000000000091'
  ),
  'worker_portal',
  'worker identity receives immutable worker account metadata'
);
select ok(
  (
    select not (
      coalesce(raw_user_meta_data, '{}'::jsonb) ?| array[
        'account_type',
        'tenant_id',
        'employee_id',
        'role',
        'permissions'
      ]
    )
    from auth.users
    where id = '9f260000-0000-4000-8000-000000000091'
  ),
  'worker user metadata retains no authorization-shaped claims'
);
select is(
  (
    select count(*)::integer
    from public.tenants
    where lower(owner_email) =
      'worker-auth-boundary@example.invalid'
  ),
  0,
  'worker Auth creation never provisions a shadow tenant'
);

insert into public.employee_portal_accounts (
  tenant_id,
  employee_id,
  auth_user_id,
  username,
  login_email,
  is_active,
  must_reset_password,
  password_reset_required_at,
  password_credential_issued_at
)
values (
  '9f260000-0000-4000-8000-000000000001',
  '9f260000-0000-4000-8000-000000000011',
  '9f260000-0000-4000-8000-000000000091',
  'worker.fixture',
  'worker-login-auth-boundary@example.invalid',
  true,
  true,
  now() - interval '2 minutes',
  now() - interval '1 minute'
);

select ok(
  public.is_authoritative_worker_portal_identity(
    '9f260000-0000-4000-8000-000000000091',
    '9f260000-0000-4000-8000-000000000001',
    '9f260000-0000-4000-8000-000000000011'
  ),
  'dedicated worker Auth metadata and DB links form one authority'
);
select throws_ok(
  $$
    insert into public.user_profiles (
      user_id,
      tenant_id,
      role,
      permissions,
      is_active
    )
    values (
      '9f260000-0000-4000-8000-000000000091',
      '9f260000-0000-4000-8000-000000000002',
      'admin',
      '{}'::jsonb,
      true
    )
  $$,
  '42501',
  'Worker portal identity cannot be linked to an active ERP profile',
  'worker Auth cannot acquire a second ERP tenant through user_profiles'
);
select throws_ok(
  $$
    update public.employees
    set user_id = '9f260000-0000-4000-8000-000000000091'
    where id = '9f260000-0000-4000-8000-000000000011'
  $$,
  'P0001',
  'worker_access_conflict',
  'worker Auth cannot also become an ERP employee login'
);

set local role authenticated;

select throws_ok(
  $$ select count(*) from public.employee_portal_accounts $$,
  '42501',
  'permission denied for table employee_portal_accounts',
  'PostgREST-equivalent clients cannot enumerate worker login rows'
);

reset role;

update public.tenants
set shop_name = 'Shared Worker Shop',
    custom_domain = 'https://workers.example.invalid/'
where id in (
  '9f260000-0000-4000-8000-000000000001',
  '9f260000-0000-4000-8000-000000000002'
);

select is(
  (
    select count(*)::integer
    from public.resolve_worker_login(
      'auth-boundary-a',
      'worker.fixture'
    )
  ),
  1,
  'worker login resolver returns one row for an existing username'
);
select is(
  (
    select count(*)::integer
    from public.resolve_worker_login(
      'auth-boundary-a',
      'missing.worker'
    )
  ),
  0,
  'service-only worker resolver returns no identity for a missing username'
);
select is(
  (
    select login_email
    from public.resolve_worker_login(
      'auth-boundary-a',
      'worker.fixture'
    )
  ),
  'worker-login-auth-boundary@example.invalid',
  'worker login resolver preserves the real login address for authentication'
);
select is(
  (
    select count(*)::integer
    from public.resolve_worker_login(
      'auth-boundary-a',
      'missing.worker'
    )
  ),
  0,
  'the private resolver never synthesizes a distinguishable dummy domain'
);
select is(
  (
    select count(*)::integer
    from public.resolve_worker_login(
      'unknown-auth-boundary-tenant',
      'worker.fixture'
    )
  ),
  0,
  'worker resolver does not claim an invalid tenant context'
);
select is(
  (
    select count(*)::integer
    from public.resolve_worker_login(
      'Shared Worker Shop',
      'worker.fixture'
    )
  ),
  0,
  'worker resolver never treats a non-unique display shop name as authority'
);
select is(
  (
    select count(*)::integer
    from public.resolve_worker_login(
      'HTTPs://WORKERS.EXAMPLE.INVALID/',
      'worker.fixture'
    )
  ),
  0,
  'worker resolver fails closed for an ambiguous normalized custom domain'
);
select is(
  (
    select login_email
    from public.resolve_worker_login(
      '9f260000-0000-4000-8000-000000000001',
      'worker.fixture'
    )
  ),
  'worker-login-auth-boundary@example.invalid',
  'worker resolver accepts an exact active tenant UUID'
);

update auth.users
set raw_app_meta_data = jsonb_build_object(
      'account_type', 'erp_staff',
      'tenant_id', '9f260000-0000-4000-8000-000000000002',
      'role', 'admin'
    )
where id = '9f260000-0000-4000-8000-000000000091';

select ok(
  not public.is_authoritative_worker_portal_identity(
    '9f260000-0000-4000-8000-000000000091',
    '9f260000-0000-4000-8000-000000000001',
    '9f260000-0000-4000-8000-000000000011'
  ),
  'worker authority fails closed when Admin metadata drifts'
);
select is(
  (
    select count(*)::integer
    from public.resolve_worker_login(
      '9f260000-0000-4000-8000-000000000001',
      'worker.fixture'
    )
  ),
  0,
  'worker login resolver rejects a mixed ERP/worker identity'
);
select is(
  public.get_my_worker_portal_context(),
  null,
  'worker context rejects a mixed ERP/worker identity'
);
select throws_ok(
  $$ select public.begin_my_worker_password_reset() $$,
  '42501',
  'Authoritative worker identity required',
  'mixed ERP/worker identity cannot use the worker reset gate'
);

update auth.users
set raw_app_meta_data = jsonb_build_object(
      'account_type', 'worker_portal',
      'tenant_id', '9f260000-0000-4000-8000-000000000001',
      'employee_id', '9f260000-0000-4000-8000-000000000011',
      'role', 'worker'
    )
where id = '9f260000-0000-4000-8000-000000000091';

update public.tenants
set shop_name = case id
      when '9f260000-0000-4000-8000-000000000001'::uuid
        then 'Auth Boundary Tenant A'
      else 'Auth Boundary Tenant B'
    end,
    custom_domain = null
where id in (
  '9f260000-0000-4000-8000-000000000001',
  '9f260000-0000-4000-8000-000000000002'
);

create temp table auth_worker_credential_issue (
  required_at timestamp with time zone primary key
) on commit drop;

insert into auth_worker_credential_issue(required_at)
select public.begin_worker_password_credential_issue(
  (
    select id
    from public.employee_portal_accounts
    where auth_user_id = '9f260000-0000-4000-8000-000000000091'
  ),
  '9f260000-0000-4000-8000-000000000001'
);

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '9f260000-0000-4000-8000-000000000091',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9f260000-0000-4000-8000-000000000091',
  true
);

select is(
  public.worker_portal_tenant_id(),
  null,
  'worker tenant authority is blocked while password reset is required'
);
select throws_ok(
  $$ select public.begin_my_worker_password_reset() $$,
  '42501',
  'Active worker reset requirement not found',
  'old worker sessions cannot start a challenge before Auth issuance finishes'
);
select throws_ok(
  $$
    select public.finish_worker_password_credential_issue(
      (
        select id
        from public.employee_portal_accounts
        where auth_user_id =
          '9f260000-0000-4000-8000-000000000091'
      ),
      '9f260000-0000-4000-8000-000000000001',
      (
        select required_at + interval '1 second'
        from auth_worker_credential_issue
      )
    )
  $$,
  '40001',
  'Worker credential issuance state changed',
  'stale issuance completion cannot mark a newer reset attempt'
);
select ok(
  public.finish_worker_password_credential_issue(
    (
      select id
      from public.employee_portal_accounts
      where auth_user_id = '9f260000-0000-4000-8000-000000000091'
    ),
    '9f260000-0000-4000-8000-000000000001',
    (select required_at from auth_worker_credential_issue)
  ) > (select required_at from auth_worker_credential_issue),
  'matching post-Auth issuance marker completes the versioned handshake'
);
select is(
  (
    public.get_my_worker_portal_context()
      ->'account'
      ->>'mustResetPassword'
  )::boolean,
  true,
  'minimal worker context remains available to render the reset gate'
);
select ok(
  not (public.get_my_worker_portal_context() ? 'employee')
    and not (public.get_my_worker_portal_context() ? 'payroll')
    and not (public.get_my_worker_portal_context() ? 'planningRoles')
    and not (public.get_my_worker_portal_context() ? 'defaultShiftBlocks'),
  'required-reset context exposes no employee PII, payroll, or planning data'
);
select throws_ok(
  $$ select public.complete_my_worker_password_reset() $$,
  '42501',
  'Password reset challenge required',
  'worker cannot complete reset before starting a server challenge'
);

insert into auth.audit_log_entries (
  id,
  payload,
  created_at
)
values (
  '9f260000-0000-4000-8000-000000000061',
  jsonb_build_object(
    'actor_id', '9f260000-0000-4000-8000-000000000091',
    'action', 'user_updated_password'
  )::json,
  now()
);

select is(
  public.begin_my_worker_password_reset(),
  true,
  'worker starts a server-timestamped password reset challenge'
);

insert into auth.audit_log_entries (
  id,
  payload,
  created_at
)
values (
  '9f260000-0000-4000-8000-000000000063',
  jsonb_build_object(
    'actor_id', '00000000-0000-0000-0000-000000000000',
    'user_id', '9f260000-0000-4000-8000-000000000091',
    'action', 'user_updated_password'
  )::json,
  clock_timestamp() + interval '1 millisecond'
);

select throws_ok(
  $$ select public.complete_my_worker_password_reset() $$,
  '42501',
  'Verified password update required',
  'pre-challenge and Admin-targeted password audits cannot clear the gate'
);

insert into auth.audit_log_entries (
  id,
  payload,
  created_at
)
values (
  '9f260000-0000-4000-8000-000000000062',
  jsonb_build_object(
    'actor_id', '9f260000-0000-4000-8000-000000000091',
    'action', 'user_updated_password'
  )::json,
  clock_timestamp() + interval '1 millisecond'
);

select is(
  public.complete_my_worker_password_reset(),
  true,
  'worker reset completion accepts a subsequent Auth password audit'
);
select is(
  (
    select must_reset_password
    from public.employee_portal_accounts
    where auth_user_id = '9f260000-0000-4000-8000-000000000091'
  ),
  false,
  'verified password reset clears the worker gate'
);
select is(
  (
    select password_reset_challenge_started_at
    from public.employee_portal_accounts
    where auth_user_id = '9f260000-0000-4000-8000-000000000091'
  ),
  null,
  'verified password reset destroys the one-time challenge timestamp'
);
select is(
  public.worker_portal_tenant_id(),
  '9f260000-0000-4000-8000-000000000001'::uuid,
  'worker tenant authority becomes available after verified reset'
);

insert into auth.sessions (id, user_id, created_at, updated_at)
values (
  '9f260000-0000-4000-8000-000000000064',
  '9f260000-0000-4000-8000-000000000091',
  now(),
  now()
);

update public.employees
set status = 'inactive'
where id = '9f260000-0000-4000-8000-000000000011';

select ok(
  (
    select is_active is false
      and must_reset_password is true
      and password_credential_issued_at is null
    from public.employee_portal_accounts
    where auth_user_id = '9f260000-0000-4000-8000-000000000091'
  ),
  'employee exit closes the portal and restores the reset-required gate'
);
select is(
  (
    select count(*)::integer
    from auth.sessions
    where user_id = '9f260000-0000-4000-8000-000000000091'
  ),
  0,
  'employee exit revokes every live worker Auth session'
);

update public.employees
set status = 'active'
where id = '9f260000-0000-4000-8000-000000000011';

select is(
  (
    select is_active
    from public.employee_portal_accounts
    where auth_user_id = '9f260000-0000-4000-8000-000000000091'
  ),
  false,
  'reactivating employment alone never revives an old worker credential'
);
select throws_ok(
  $$
    delete from public.employees
    where id = '9f260000-0000-4000-8000-000000000011'
  $$,
  '42501',
  'employee_retirement_required',
  'physical employee deletion cannot leave Auth and sessions orphaned'
);

insert into auth.users (
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
)
values (
  '9f260000-0000-4000-8000-000000000092',
  'authenticated',
  'authenticated',
  'oauth-auth-boundary@example.invalid',
  '',
  now(),
  '{}'::jsonb,
  '{"provider": "google"}'::jsonb,
  now(),
  now()
);

select is(
  (
    select count(*)::integer
    from public.user_profiles
    where user_id = '9f260000-0000-4000-8000-000000000092'
  ),
  0,
  'OAuth identity without explicit shop intent remains unassigned'
);
select is(
  (
    select count(*)::integer
    from public.tenants
    where lower(owner_email) =
      'oauth-auth-boundary@example.invalid'
  ),
  0,
  'OAuth login does not silently create an ERP tenant'
);

insert into auth.users (
  id,
  aud,
  role,
  email,
  encrypted_password,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
)
values (
  '9f260000-0000-4000-8000-000000000086',
  'authenticated',
  'authenticated',
  'display-only-customer@example.invalid',
  '',
  '{}'::jsonb,
  '{"name": "Display Customer", "phone": "+56911111111"}'::jsonb,
  now(),
  now()
);

select is(
  (
    select count(*)::integer
    from public.tenants
    where lower(owner_email) = 'display-only-customer@example.invalid'
  ),
  0,
  'display-only customer signup cannot be mistaken for an ERP owner'
);
select is(
  (
    select count(*)::integer
    from public.customers
    where lower(email) = 'display-only-customer@example.invalid'
  ),
  0,
  'unconfirmed display-only signup does not create a customer row'
);

update auth.users
set email_confirmed_at = now()
where id = '9f260000-0000-4000-8000-000000000086';

select is(
  (
    select count(*)::integer
    from public.customers
    where lower(email) = 'display-only-customer@example.invalid'
  ),
  0,
  'email confirmation alone does not select a storefront tenant'
);

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '9f260000-0000-4000-8000-000000000086',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9f260000-0000-4000-8000-000000000086',
  true
);

select ok(
  public.provision_current_public_store_customer(
    '9f260000-0000-4000-8000-000000000001'
  ) is not null,
  'confirmed display-only identity provisions through the tenant RPC'
);
select is(
  (
    select count(*)::integer
    from public.customers
    where tenant_id = '9f260000-0000-4000-8000-000000000001'
      and auth_user_id = '9f260000-0000-4000-8000-000000000086'
  ),
  1,
  'display-only customer authority is persisted in the scoped customer row'
);
select ok(
  (
    select raw_user_meta_data ? 'name'
      and raw_user_meta_data ? 'phone'
      and not (
        raw_user_meta_data ?| array[
          'account_type',
          'tenant_id',
          'employee_id',
          'role',
          'permissions',
          'customer_id',
          'customer_tenant_id'
        ]
      )
    from auth.users
    where id = '9f260000-0000-4000-8000-000000000086'
  ),
  'customer Auth metadata retains only display fields'
);

insert into public.user_invitations (
  id,
  tenant_id,
  email,
  role,
  permissions,
  invited_by,
  status,
  expires_at,
  token_hash,
  token_issued_at
)
values (
  '9f260000-0000-4000-8000-000000000027',
  '9f260000-0000-4000-8000-000000000002',
  'display-only-customer@example.invalid',
  'cashier',
  '{"manage_users": false}'::jsonb,
  '9f260000-0000-4000-8000-000000000091',
  'pending',
  now() + interval '7 days',
  encode(
    extensions.digest(
      convert_to(
        'auth-boundary-customer-to-staff-token-v1',
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  ),
  now() - interval '2 minutes'
);

select is(
  public.accept_user_invitation(
    'auth-boundary-customer-to-staff-token-v1'
  ),
  true,
  'an existing confirmed customer can also accept a staff invitation'
);
select is(
  (
    select tenant_id
    from public.user_profiles
    where user_id = '9f260000-0000-4000-8000-000000000086'
      and is_active is true
  ),
  '9f260000-0000-4000-8000-000000000002'::uuid,
  'shared customer and staff identity receives only the invited ERP tenant'
);
select ok(
  (
    select raw_app_meta_data->>'account_type' = 'erp_staff'
      and (
        raw_app_meta_data->'customer_memberships'
          ->>'9f260000-0000-4000-8000-000000000001'
      ) is not null
    from auth.users
    where id = '9f260000-0000-4000-8000-000000000086'
  ),
  'staff acceptance preserves the existing tenant-scoped customer membership'
);

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '9f260000-0000-4000-8000-000000000092',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9f260000-0000-4000-8000-000000000092',
  true
);

create temp table auth_customer_contract_ids (
  customer_id uuid primary key
) on commit drop;

insert into auth_customer_contract_ids(customer_id)
values (
  (
    select public.provision_current_public_store_customer(
      '9f260000-0000-4000-8000-000000000001'
    )
  )
);

grant select on auth_customer_contract_ids to authenticated;

select ok(
  (select customer_id is not null from auth_customer_contract_ids),
  'confirmed OAuth identity provisions a storefront customer'
);
select is(
  (
    select count(*)::integer
    from public.customers customer
    where customer.tenant_id =
        '9f260000-0000-4000-8000-000000000001'
      and customer.auth_user_id =
        '9f260000-0000-4000-8000-000000000092'
  ),
  1,
  'OAuth provisioning creates one tenant-scoped customer row'
);
select is(
  public.provision_current_public_store_customer(
    '9f260000-0000-4000-8000-000000000001'
  ),
  (select customer_id from auth_customer_contract_ids),
  'OAuth customer provisioning is idempotent on callback retry'
);
select is(
  (
    select raw_app_meta_data->>'account_type'
    from auth.users
    where id = '9f260000-0000-4000-8000-000000000092'
  ),
  'public_store_customer',
  'customer authority metadata is set only by the server RPC'
);
select is(
  (
    select (
      raw_app_meta_data->'customer_memberships'
        ->>'9f260000-0000-4000-8000-000000000001'
    )::uuid
    from auth.users
    where id = '9f260000-0000-4000-8000-000000000092'
  ),
  (select customer_id from auth_customer_contract_ids),
  'customer app metadata preserves tenant-scoped membership'
);
select ok(
  (
    select not (
      coalesce(raw_user_meta_data, '{}'::jsonb) ?| array[
        'account_type',
        'tenant_id',
        'employee_id',
        'role',
        'permissions',
        'customer_id',
        'customer_tenant_id'
      ]
    )
    from auth.users
    where id = '9f260000-0000-4000-8000-000000000092'
  ),
  'customer user metadata retains display fields only'
);

set local role authenticated;

select throws_ok(
  $$
    insert into public.customers (
      tenant_id,
      auth_user_id,
      name,
      email
    )
    values (
      '9f260000-0000-4000-8000-000000000002',
      '9f260000-0000-4000-8000-000000000092',
      'Forged Customer',
      'oauth-auth-boundary@example.invalid'
    )
  $$,
  '42501',
  'new row violates row-level security policy for table "customers"',
  'customer cannot forge direct membership in another storefront'
);
select throws_ok(
  $$
    update public.customers
    set tenant_id = '9f260000-0000-4000-8000-000000000002'
    where tenant_id = '9f260000-0000-4000-8000-000000000001'
      and auth_user_id = '9f260000-0000-4000-8000-000000000092'
  $$,
  '42501',
  'Customer tenant and Auth identity are immutable',
  'customer self-service cannot move its identity to another tenant'
);
select throws_ok(
  $$
    update public.customers
    set auth_user_id = '9f260000-0000-4000-8000-000000000097'
    where tenant_id = '9f260000-0000-4000-8000-000000000001'
      and auth_user_id = '9f260000-0000-4000-8000-000000000092'
  $$,
  '42501',
  'Customer tenant and Auth identity are immutable',
  'customer self-service cannot transfer its row to another Auth user'
);
select throws_ok(
  $$
    update public.customers
    set email = 'forged-customer-email@example.invalid'
    where tenant_id = '9f260000-0000-4000-8000-000000000001'
      and auth_user_id = '9f260000-0000-4000-8000-000000000092'
  $$,
  '42501',
  'Customer self-service may update profile fields only',
  'customer self-service cannot replace the verified identity email'
);
select lives_ok(
  $$
    update public.customers
    set name = 'OAuth Customer Updated'
    where tenant_id = '9f260000-0000-4000-8000-000000000001'
      and auth_user_id = '9f260000-0000-4000-8000-000000000092'
  $$,
  'customer self-service can update an allowed display profile field'
);
select is(
  (
    select name
    from public.customers
    where tenant_id = '9f260000-0000-4000-8000-000000000001'
      and auth_user_id = '9f260000-0000-4000-8000-000000000092'
  ),
  'OAuth Customer Updated',
  'allowed customer display update is persisted'
);

reset role;

select ok(
  public.provision_current_public_store_customer(
    '9f260000-0000-4000-8000-000000000002'
  ) is not null,
  'one Auth identity can hold a separate active customer membership per tenant'
);

create temp table auth_active_customer_contract_ids (
  customer_id uuid primary key
) on commit drop;

insert into auth_active_customer_contract_ids(customer_id)
select customer.id
from public.customers customer
where customer.tenant_id = '9f260000-0000-4000-8000-000000000002'
  and customer.auth_user_id = '9f260000-0000-4000-8000-000000000092';

grant select on auth_active_customer_contract_ids to authenticated, anon;

set local session_replication_role = replica;

insert into public.customer_addresses (
  id,
  tenant_id,
  customer_id,
  label,
  recipient_name,
  phone,
  street_address,
  comuna,
  city,
  region
)
values
  (
    '9f260000-0000-4000-8000-000000000071',
    '9f260000-0000-4000-8000-000000000001',
    (
      select id
      from public.customers
      where tenant_id = '9f260000-0000-4000-8000-000000000001'
        and auth_user_id = '9f260000-0000-4000-8000-000000000092'
    ),
    'Suspended A',
    'Customer Fixture',
    '+56911111111',
    'Calle A',
    'Santiago',
    'Santiago',
    'Metropolitana'
  ),
  (
    '9f260000-0000-4000-8000-000000000072',
    '9f260000-0000-4000-8000-000000000002',
    (
      select id
      from public.customers
      where tenant_id = '9f260000-0000-4000-8000-000000000002'
        and auth_user_id = '9f260000-0000-4000-8000-000000000092'
    ),
    'Active B',
    'Customer Fixture',
    '+56922222222',
    'Calle B',
    'Santiago',
    'Santiago',
    'Metropolitana'
  );

insert into public.bikes (
  id,
  tenant_id,
  customer_id,
  brand,
  model
)
values
  (
    '9f260000-0000-4000-8000-000000000073',
    '9f260000-0000-4000-8000-000000000001',
    (
      select id
      from public.customers
      where tenant_id = '9f260000-0000-4000-8000-000000000001'
        and auth_user_id = '9f260000-0000-4000-8000-000000000092'
    ),
    'Suspended',
    'Bike A'
  ),
  (
    '9f260000-0000-4000-8000-000000000074',
    '9f260000-0000-4000-8000-000000000002',
    (
      select id
      from public.customers
      where tenant_id = '9f260000-0000-4000-8000-000000000002'
        and auth_user_id = '9f260000-0000-4000-8000-000000000092'
    ),
    'Active',
    'Bike B'
  );

insert into public.mechanic_jobs (
  id,
  tenant_id,
  job_number,
  customer_id,
  bike_id
)
values
  (
    '9f260000-0000-4000-8000-000000000075',
    '9f260000-0000-4000-8000-000000000001',
    'AUTH-SUSPENDED-JOB-A',
    (
      select id
      from public.customers
      where tenant_id = '9f260000-0000-4000-8000-000000000001'
        and auth_user_id = '9f260000-0000-4000-8000-000000000092'
    ),
    '9f260000-0000-4000-8000-000000000073'
  ),
  (
    '9f260000-0000-4000-8000-000000000076',
    '9f260000-0000-4000-8000-000000000002',
    'AUTH-ACTIVE-JOB-B',
    (
      select id
      from public.customers
      where tenant_id = '9f260000-0000-4000-8000-000000000002'
        and auth_user_id = '9f260000-0000-4000-8000-000000000092'
    ),
    '9f260000-0000-4000-8000-000000000074'
  );

insert into public.online_orders (
  id,
  tenant_id,
  order_number,
  customer_id,
  customer_email,
  customer_name
)
values
  (
    '9f260000-0000-4000-8000-000000000077',
    '9f260000-0000-4000-8000-000000000001',
    'AUTH-SUSPENDED-ORDER-A',
    (
      select id
      from public.customers
      where tenant_id = '9f260000-0000-4000-8000-000000000001'
        and auth_user_id = '9f260000-0000-4000-8000-000000000092'
    ),
    'oauth-auth-boundary@example.invalid',
    'Customer Fixture'
  ),
  (
    '9f260000-0000-4000-8000-000000000078',
    '9f260000-0000-4000-8000-000000000002',
    'AUTH-ACTIVE-ORDER-B',
    (
      select id
      from public.customers
      where tenant_id = '9f260000-0000-4000-8000-000000000002'
        and auth_user_id = '9f260000-0000-4000-8000-000000000092'
    ),
    'oauth-auth-boundary@example.invalid',
    'Customer Fixture'
  );

insert into public.online_order_items (
  id,
  tenant_id,
  order_id,
  product_name,
  quantity,
  unit_price,
  subtotal
)
values
  (
    '9f260000-0000-4000-8000-000000000079',
    '9f260000-0000-4000-8000-000000000001',
    '9f260000-0000-4000-8000-000000000077',
    'Suspended order item',
    1,
    1000,
    1000
  ),
  (
    '9f260000-0000-4000-8000-000000000080',
    '9f260000-0000-4000-8000-000000000002',
    '9f260000-0000-4000-8000-000000000078',
    'Active order item',
    1,
    1000,
    1000
  );

set local session_replication_role = origin;

set local role authenticated;

select throws_ok(
  $$
    update public.customer_addresses
    set tenant_id = '9f260000-0000-4000-8000-000000000002',
        customer_id = (
          select id
          from public.customers
          where tenant_id = '9f260000-0000-4000-8000-000000000002'
            and auth_user_id =
              '9f260000-0000-4000-8000-000000000092'
        )
    where id = '9f260000-0000-4000-8000-000000000071'
  $$,
  '42501',
  'Customer address identity is immutable',
  'customer cannot move an address between two memberships it owns'
);

reset role;

select set_config(
  'request.jwt.claims',
  jsonb_build_object('role', 'service_role')::text,
  true
);
select set_config('request.jwt.claim.sub', '', true);

update public.customers
set is_active = false
where tenant_id = '9f260000-0000-4000-8000-000000000001'
  and auth_user_id = '9f260000-0000-4000-8000-000000000092';

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '9f260000-0000-4000-8000-000000000092',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9f260000-0000-4000-8000-000000000092',
  true
);

set local role authenticated;

select ok(
  (select count(*) from public.customers
    where tenant_id = '9f260000-0000-4000-8000-000000000001') = 0
  and
  (select count(*) from public.customers
    where tenant_id = '9f260000-0000-4000-8000-000000000002') = 1,
  'suspension hides only the disabled tenant customer membership'
);
select ok(
  (select count(*) from public.customer_addresses
    where tenant_id = '9f260000-0000-4000-8000-000000000001') = 0
  and
  (select count(*) from public.customer_addresses
    where tenant_id = '9f260000-0000-4000-8000-000000000002') = 1,
  'suspension hides addresses while preserving another active membership'
);
select ok(
  (select count(*) from public.bikes
    where tenant_id = '9f260000-0000-4000-8000-000000000001') = 0
  and
  (select count(*) from public.bikes
    where tenant_id = '9f260000-0000-4000-8000-000000000002') = 1,
  'suspension hides bikes while preserving another active membership'
);
select ok(
  (select count(*) from public.mechanic_jobs
    where tenant_id = '9f260000-0000-4000-8000-000000000001') = 0
  and
  (select count(*) from public.mechanic_jobs
    where tenant_id = '9f260000-0000-4000-8000-000000000002') = 1,
  'suspension hides workshop jobs while preserving another active membership'
);
select ok(
  (select count(*) from public.online_orders
    where tenant_id = '9f260000-0000-4000-8000-000000000001') = 0
  and
  (select count(*) from public.online_orders
    where tenant_id = '9f260000-0000-4000-8000-000000000002') = 1,
  'suspension hides orders while preserving another active membership'
);
select ok(
  (select count(*) from public.online_order_items
    where tenant_id = '9f260000-0000-4000-8000-000000000001') = 0
  and
  (select count(*) from public.online_order_items
    where tenant_id = '9f260000-0000-4000-8000-000000000002') = 1,
  'suspension hides order items while preserving another active membership'
);
select throws_ok(
  $$
    select public.create_public_online_order_with_access(
      jsonb_build_object(
        'tenant_id', '9f260000-0000-4000-8000-000000000001',
        'customer_id',
          (select customer_id from auth_customer_contract_ids),
        'checkout_idempotency_key',
          'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
      ),
      '[]'::jsonb
    )
  $$,
  '42501',
  'Checkout customer membership is invalid or inactive',
  'public checkout rejects a suspended customer membership'
);
select throws_ok(
  $$
    select public.create_public_online_order_with_access(
      jsonb_build_object(
        'tenant_id', '9f260000-0000-4000-8000-000000000001',
        'checkout_idempotency_key', 'predictable-key'
      ),
      '[]'::jsonb
    )
  $$,
  '22023',
  'A random checkout idempotency key is required',
  'active tenant guest checkout passes the tenant guard'
);
select throws_ok(
  $$
    select public.create_public_online_order_with_access(
      jsonb_build_object(
        'tenant_id', '9f260000-0000-4000-8000-000000000002',
        'customer_id', (
          select id
          from public.customers
          where tenant_id = '9f260000-0000-4000-8000-000000000002'
            and auth_user_id =
              '9f260000-0000-4000-8000-000000000092'
        ),
        'checkout_idempotency_key', 'predictable-key'
      ),
      '[]'::jsonb
    )
  $$,
  '22023',
  'A random checkout idempotency key is required',
  'another active tenant customer passes both storefront guards'
);

reset role;

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '9f260000-0000-4000-8000-000000000091',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9f260000-0000-4000-8000-000000000091',
  true
);

set local role authenticated;

select throws_ok(
  $$
    select public.create_public_online_order_with_access(
      jsonb_build_object(
        'tenant_id', '9f260000-0000-4000-8000-000000000002',
        'customer_id',
          (select customer_id from auth_active_customer_contract_ids),
        'checkout_idempotency_key',
          'cccccccc-cccc-4ccc-8ccc-cccccccccccc'
      ),
      '[]'::jsonb
    )
  $$,
  '42501',
  'Checkout customer membership is invalid or inactive',
  'authenticated checkout cannot claim another users customer membership'
);

reset role;

select set_config('request.jwt.claims', '{"role":"anon"}', true);
select set_config('request.jwt.claim.sub', '', true);

set local role anon;

select throws_ok(
  $$
    select public.create_public_online_order_with_access(
      jsonb_build_object(
        'tenant_id', '9f260000-0000-4000-8000-000000000002',
        'customer_id',
          (select customer_id from auth_active_customer_contract_ids),
        'checkout_idempotency_key',
          'dddddddd-dddd-4ddd-8ddd-dddddddddddd'
      ),
      '[]'::jsonb
    )
  $$,
  '42501',
  'Checkout customer membership is invalid or inactive',
  'anonymous checkout cannot claim an authenticated customer membership'
);

reset role;

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '9f260000-0000-4000-8000-000000000092',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9f260000-0000-4000-8000-000000000092',
  true
);

set local role authenticated;

select is(
  (
    public.quote_public_online_shipping(
      '9f260000-0000-4000-8000-000000000002',
      'pickup',
      1,
      'CL'
    )->>'shipping_gross'
  )::numeric,
  0::numeric,
  'active storefront tenant retains the public pickup quote'
);
select lives_ok(
  $$
    update public.customers
    set name = 'Suspension bypass'
    where tenant_id = '9f260000-0000-4000-8000-000000000001'
  $$,
  'suspended customer profile update affects no hidden rows'
);
select lives_ok(
  $$
    update public.customer_addresses
    set label = 'Suspension bypass'
    where tenant_id = '9f260000-0000-4000-8000-000000000001'
  $$,
  'suspended customer address update affects no hidden rows'
);
select lives_ok(
  $$
    update public.customer_addresses
    set label = 'Active B updated'
    where tenant_id = '9f260000-0000-4000-8000-000000000002'
  $$,
  'another active customer membership retains address self-service'
);
select throws_ok(
  $$
    select public.provision_current_public_store_customer(
      '9f260000-0000-4000-8000-000000000001'
    )
  $$,
  '42501',
  'Customer membership is inactive',
  'provisioning retry cannot reactivate a suspended membership'
);

reset role;

select ok(
  (
    select name <> 'Suspension bypass'
    from public.customers
    where tenant_id = '9f260000-0000-4000-8000-000000000001'
      and auth_user_id = '9f260000-0000-4000-8000-000000000092'
  )
  and (
    select label = 'Suspended A'
    from public.customer_addresses
    where id = '9f260000-0000-4000-8000-000000000071'
  )
  and (
    select label = 'Active B updated'
    from public.customer_addresses
    where id = '9f260000-0000-4000-8000-000000000072'
  ),
  'suspension blocks mutation without damaging another tenant membership'
);

update public.tenants
set is_active = false
where id = '9f260000-0000-4000-8000-000000000002';

set local role authenticated;

select ok(
  (select count(*) from public.customers
    where tenant_id = '9f260000-0000-4000-8000-000000000002') = 0
  and
  (select count(*) from public.customer_addresses
    where tenant_id = '9f260000-0000-4000-8000-000000000002') = 0
  and
  (select count(*) from public.bikes
    where tenant_id = '9f260000-0000-4000-8000-000000000002') = 0
  and
  (select count(*) from public.mechanic_jobs
    where tenant_id = '9f260000-0000-4000-8000-000000000002') = 0
  and
  (select count(*) from public.online_orders
    where tenant_id = '9f260000-0000-4000-8000-000000000002') = 0
  and
  (select count(*) from public.online_order_items
    where tenant_id = '9f260000-0000-4000-8000-000000000002') = 0,
  'an inactive tenant hides every customer-owned parent and child row'
);
select lives_ok(
  $$
    update public.customer_addresses
    set label = 'Inactive tenant bypass'
    where id = '9f260000-0000-4000-8000-000000000072'
  $$,
  'an inactive tenant customer update affects no hidden address'
);

reset role;

select is(
  (
    select label
    from public.customer_addresses
    where id = '9f260000-0000-4000-8000-000000000072'
  ),
  'Active B updated',
  'the inactive tenant address remains unchanged after the hidden update'
);

select throws_ok(
  $$
    select public.provision_current_public_store_customer(
      '9f260000-0000-4000-8000-000000000002'
    )
  $$,
  '42501',
  'Storefront tenant is invalid or inactive',
  'customer provisioning rejects an inactive storefront'
);
select throws_ok(
  $$
    select public.create_public_online_order_with_access(
      jsonb_build_object(
        'tenant_id', '9f260000-0000-4000-8000-000000000002',
        'checkout_idempotency_key',
          'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
      ),
      '[]'::jsonb
    )
  $$,
  '42501',
  'Storefront tenant is invalid or inactive',
  'public checkout rejects an inactive storefront before order creation'
);
select throws_ok(
  $$
    select public.quote_public_online_shipping(
      '9f260000-0000-4000-8000-000000000002',
      'pickup',
      1,
      'CL'
    )
  $$,
  '42501',
  'Storefront tenant is invalid or inactive',
  'public shipping quote rejects an inactive storefront'
);

update public.tenants
set is_active = true
where id = '9f260000-0000-4000-8000-000000000002';

insert into auth.users (
  id,
  aud,
  role,
  email,
  encrypted_password,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
)
values (
  '9f260000-0000-4000-8000-000000000099',
  'authenticated',
  'authenticated',
  'customer-owner-confusion@example.invalid',
  '',
  jsonb_build_object(
    'shop_name', 'Forged Customer Owner Shop',
    'subdomain', 'forged-customer-owner-shop'
  ),
  jsonb_build_object(
    'account_type', 'public_store_customer',
    'shop_name', 'Forged Customer Owner Shop',
    'subdomain', 'forged-customer-owner-shop'
  ),
  now(),
  now()
);

select ok(
  (
    select not (
      coalesce(raw_user_meta_data, '{}'::jsonb)
        ?| array['account_type', 'shop_name', 'subdomain']
    )
    and not (
      coalesce(raw_app_meta_data, '{}'::jsonb)
        ?| array['account_type', 'shop_name', 'subdomain']
    )
    from auth.users
    where id = '9f260000-0000-4000-8000-000000000099'
  ),
  'customer signup strips owner intent from both Auth metadata stores'
);

update auth.users
set email_confirmed_at = now()
where id = '9f260000-0000-4000-8000-000000000099';

select ok(
  not exists (
    select 1
    from public.tenants tenant
    where lower(tenant.owner_email) =
      'customer-owner-confusion@example.invalid'
  )
  and not exists (
    select 1
    from public.user_profiles profile
    where profile.user_id = '9f260000-0000-4000-8000-000000000099'
  ),
  'confirming a customer signup with forged shop intent creates no ERP tenant'
);

insert into auth.users (
  id,
  aud,
  role,
  email,
  encrypted_password,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
)
values (
  '9f260000-0000-4000-8000-000000000097',
  'authenticated',
  'authenticated',
  'unconfirmed-customer@example.invalid',
  '',
  '{}'::jsonb,
  '{}'::jsonb,
  now(),
  now()
);

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '9f260000-0000-4000-8000-000000000097',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9f260000-0000-4000-8000-000000000097',
  true
);

select throws_ok(
  $$
    select public.provision_current_public_store_customer(
      '9f260000-0000-4000-8000-000000000001'
    )
  $$,
  '42501',
  'A confirmed Auth email is required',
  'unconfirmed email cannot provision a storefront customer'
);

select throws_ok(
  $$
    insert into auth.users (
      id, aud, role, email, encrypted_password,
      email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
      created_at, updated_at
    )
    values (
      '9f260000-0000-4000-8000-000000000095',
      'authenticated',
      'authenticated',
      'owner-without-shop@example.invalid',
      '',
      now(),
      '{}'::jsonb,
      '{"account_type": "erp_owner"}'::jsonb,
      now(),
      now()
    )
  $$,
  'P0001',
  'A shop name is required to create an ERP tenant',
  'explicit owner signup cannot create a nameless tenant'
);
select throws_ok(
  $$
    insert into auth.users (
      id, aud, role, email, encrypted_password,
      email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
      created_at, updated_at
    )
    values (
      '9f260000-0000-4000-8000-000000000096',
      'authenticated',
      'authenticated',
      'owner-short-shop@example.invalid',
      '',
      now(),
      '{}'::jsonb,
      '{"shop_name": "x"}'::jsonb,
      now(),
      now()
    )
  $$,
  'P0001',
  'ERP shop name must contain 3 to 120 safe characters',
  'public owner signup rejects garbage business names'
);

insert into auth.users (
  id,
  aud,
  role,
  email,
  encrypted_password,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
)
values (
  '9f260000-0000-4000-8000-000000000089',
  'authenticated',
  'authenticated',
  'deferred-owner@example.invalid',
  '',
  '{}'::jsonb,
  jsonb_build_object(
    'account_type', 'erp_owner',
    'shop_name', 'Deferred Owner Shop',
    'subdomain', 'deferred-owner-shop',
    'tenant_id', '9f260000-0000-4000-8000-000000000002',
    'role', 'admin'
  ),
  now(),
  now()
);

select is(
  (
    select count(*)::integer
    from public.tenants
    where lower(owner_email) = 'deferred-owner@example.invalid'
  ),
  0,
  'unconfirmed owner signup cannot create a tenant or reserve a subdomain'
);
select ok(
  (
    select not (
      coalesce(raw_user_meta_data, '{}'::jsonb) ?| array[
        'account_type',
        'tenant_id',
        'employee_id',
        'role',
        'permissions',
        'invitation_token'
      ]
    )
    from auth.users
    where id = '9f260000-0000-4000-8000-000000000089'
  ),
  'unconfirmed owner intent stores display data without authority claims'
);

update auth.users
set email_confirmed_at = now()
where id = '9f260000-0000-4000-8000-000000000089';

select is(
  (
    select count(*)::integer
    from public.user_profiles profile
    join public.tenants tenant
      on tenant.id = profile.tenant_id
    where profile.user_id = '9f260000-0000-4000-8000-000000000089'
      and profile.is_active is true
      and profile.role = 'admin'
      and lower(tenant.owner_email) = 'deferred-owner@example.invalid'
  ),
  1,
  'owner tenant and admin profile are created only after email confirmation'
);
select ok(
  (
    select raw_app_meta_data->>'account_type' = 'erp_owner'
      and raw_app_meta_data->>'role' = 'admin'
      and nullif(raw_app_meta_data->>'tenant_id', '') is not null
    from auth.users
    where id = '9f260000-0000-4000-8000-000000000089'
  ),
  'confirmed owner authority is written only to server-controlled app metadata'
);

insert into public.user_invitations (
  id,
  tenant_id,
  email,
  role,
  permissions,
  invited_by,
  employee_id,
  metadata,
  status,
  expires_at,
  token_hash,
  token_issued_at
)
values (
  '9f260000-0000-4000-8000-000000000021',
  '9f260000-0000-4000-8000-000000000001',
  'invited-auth-boundary@example.invalid',
  'mechanic',
  '{"manage_users": false}'::jsonb,
  '9f260000-0000-4000-8000-000000000091',
  '9f260000-0000-4000-8000-000000000012',
  '{"name": "Invited Fixture"}'::jsonb,
  'pending',
  now() + interval '7 days',
  encode(
    extensions.digest(
      convert_to(
        'auth-boundary-invitation-token-v1-1234567890',
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  ),
  now() - interval '2 minutes'
);

select is(
  (
    select invitation_id
    from public.lookup_user_invitation(
      'auth-boundary-invitation-token-v1-1234567890'
    )
  ),
  '9f260000-0000-4000-8000-000000000021'::uuid,
  'the clear bearer token resolves its pending invitation'
);
select is(
  (
    select count(*)::integer
    from public.lookup_user_invitation(
      'auth-boundary-wrong-token-value-1234567890'
    )
  ),
  0,
  'an incorrect bearer token discloses no invitation'
);
select is(
  public.rotate_user_invitation_token(
    '9f260000-0000-4000-8000-000000000021',
    '9f260000-0000-4000-8000-000000000001',
    encode(
      extensions.digest(
        convert_to(
          'auth-boundary-invitation-token-v2-1234567890',
          'UTF8'
        ),
        'sha256'
      ),
      'hex'
    ),
    now() + interval '7 days'
  ),
  true,
  'the trusted service can rotate a pending invitation token'
);
select is(
  public.rotate_user_invitation_token(
    '9f260000-0000-4000-8000-000000000021',
    '9f260000-0000-4000-8000-000000000001',
    encode(
      extensions.digest(
        convert_to(
          'auth-boundary-invitation-token-v2-1234567890',
          'UTF8'
        ),
        'sha256'
      ),
      'hex'
    ),
    now() + interval '7 days'
  ),
  true,
  'retrying the same invitation token is idempotent inside the cooldown'
);
select throws_ok(
  $$
    select public.rotate_user_invitation_token(
      '9f260000-0000-4000-8000-000000000021',
      '9f260000-0000-4000-8000-000000000001',
      encode(
        extensions.digest(
          convert_to(
            'auth-boundary-invitation-token-v3-1234567890',
            'UTF8'
          ),
          'sha256'
        ),
        'hex'
      ),
      now() + interval '7 days'
    )
  $$,
  '55000',
  'Invitation token rotation is rate limited',
  'a different resend token is rate-limited for 60 seconds'
);
select is(
  (
    select count(*)::integer
    from public.lookup_user_invitation(
      'auth-boundary-invitation-token-v1-1234567890'
    )
  ),
  0,
  'rotation invalidates the previous clear token'
);
select is(
  (
    select invitation_id
    from public.lookup_user_invitation(
      'auth-boundary-invitation-token-v2-1234567890'
    )
  ),
  '9f260000-0000-4000-8000-000000000021'::uuid,
  'rotation activates only the replacement clear token'
);

insert into auth.users (
  id,
  aud,
  role,
  email,
  encrypted_password,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
)
values (
  '9f260000-0000-4000-8000-000000000093',
  'authenticated',
  'authenticated',
  'invited-auth-boundary@example.invalid',
  '',
  '{}'::jsonb,
  jsonb_build_object(
    'account_type', 'staff_invitation',
    'invitation_token',
      'auth-boundary-invitation-token-v2-1234567890'
  ),
  now(),
  now()
);

select is(
  (
    select count(*)::integer
    from public.user_profiles
    where user_id = '9f260000-0000-4000-8000-000000000093'
  ),
  0,
  'unconfirmed invited signup does not activate an ERP membership'
);
select is(
  (
    select status
    from public.user_invitations
    where id = '9f260000-0000-4000-8000-000000000021'
  ),
  'pending',
  'unconfirmed invited signup does not consume the bearer invitation'
);
select ok(
  (
    select not (
      coalesce(raw_user_meta_data, '{}'::jsonb) ? 'invitation_token'
    )
    from auth.users
    where id = '9f260000-0000-4000-8000-000000000093'
  ),
  'clear invitation token is removed from Auth metadata immediately'
);
select ok(
  (
    select raw_app_meta_data->>'pending_invitation_token_hash'
      ~ '^[0-9a-f]{64}$'
    from auth.users
    where id = '9f260000-0000-4000-8000-000000000093'
  ),
  'unconfirmed staff intent retains only a one-way server-owned verifier'
);
select is(
  (
    select email_confirmed_at
    from auth.users
    where id = '9f260000-0000-4000-8000-000000000093'
  ),
  null,
  'invited signup remains unconfirmed until Auth proves mailbox ownership'
);

update auth.users
set email_confirmed_at = now()
where id = '9f260000-0000-4000-8000-000000000093';

select is(
  (
    select count(*)::integer
    from public.user_profiles
    where user_id = '9f260000-0000-4000-8000-000000000093'
  ),
  1,
  'mailbox confirmation atomically activates validated invited staff'
);
select is(
  (
    select status
    from public.user_invitations
    where id = '9f260000-0000-4000-8000-000000000021'
  ),
  'accepted',
  'confirmation atomically consumes the durable invitation intent'
);
select ok(
  (
    select not (
      coalesce(raw_app_meta_data, '{}'::jsonb)
        ? 'pending_invitation_token_hash'
    )
    from auth.users
    where id = '9f260000-0000-4000-8000-000000000093'
  ),
  'accepted staff identity no longer retains a pending verifier'
);

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '9f260000-0000-4000-8000-000000000093',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9f260000-0000-4000-8000-000000000093',
  true
);

select is(
  public.accept_user_invitation(
    'auth-boundary-invitation-token-v2-1234567890'
  ),
  true,
  'post-confirmation bearer replay is idempotent for the accepted identity'
);

select is(
  (
    select tenant_id
    from public.user_profiles
    where user_id = '9f260000-0000-4000-8000-000000000093'
  ),
  '9f260000-0000-4000-8000-000000000001'::uuid,
  'invitation acceptance binds the staff profile to the invited tenant'
);
select is(
  (
    select role
    from public.user_profiles
    where user_id = '9f260000-0000-4000-8000-000000000093'
  ),
  'mechanic',
  'invitation acceptance preserves the server-side invited role'
);
select is(
  (
    select employee_id
    from public.user_profiles
    where user_id = '9f260000-0000-4000-8000-000000000093'
  ),
  '9f260000-0000-4000-8000-000000000012'::uuid,
  'invitation acceptance records the employee link on the profile'
);
select is(
  (
    select status
    from public.user_invitations
    where id = '9f260000-0000-4000-8000-000000000021'
  ),
  'accepted',
  'invitation acceptance is durably receipted'
);
select is(
  (
    select token_hash
    from public.user_invitations
    where id = '9f260000-0000-4000-8000-000000000021'
  ),
  null,
  'the token verifier is destroyed after acceptance'
);
select is(
  (
    select accepted_user_id
    from public.user_invitations
    where id = '9f260000-0000-4000-8000-000000000021'
  ),
  '9f260000-0000-4000-8000-000000000093'::uuid,
  'the invitation receipt identifies the accepted Auth user'
);
select is(
  (
    select user_id
    from public.employees
    where id = '9f260000-0000-4000-8000-000000000012'
  ),
  '9f260000-0000-4000-8000-000000000093'::uuid,
  'employee linkage is committed atomically with invitation acceptance'
);
select ok(
  (
    select email_confirmed_at is not null
    from auth.users
    where id = '9f260000-0000-4000-8000-000000000093'
  ),
  'invitation acceptance occurs only after mailbox confirmation'
);
select ok(
  (
    select not (
      coalesce(raw_user_meta_data, '{}'::jsonb) ?| array[
        'account_type',
        'tenant_id',
        'employee_id',
        'role',
        'permissions',
        'invitation_token'
      ]
    )
    from auth.users
    where id = '9f260000-0000-4000-8000-000000000093'
  ),
  'new invited staff retains no authority in user-editable metadata'
);

insert into auth.users (
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
)
values (
  '9f260000-0000-4000-8000-000000000094',
  'authenticated',
  'authenticated',
  'replay-auth-boundary@example.invalid',
  '',
  now(),
  '{}'::jsonb,
  '{"provider": "email"}'::jsonb,
  now(),
  now()
);

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '9f260000-0000-4000-8000-000000000094',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9f260000-0000-4000-8000-000000000094',
  true
);

select throws_ok(
  $$
    select public.accept_user_invitation(
      'auth-boundary-invitation-token-v2-1234567890'
    )
  $$,
  '42501',
  'Invalid or unavailable invitation',
  'an accepted invitation token cannot be replayed by another identity'
);
select ok(
  (
    select not (
      coalesce(raw_user_meta_data, '{}'::jsonb) ? 'invitation_token'
    )
    from auth.users
    where id = '9f260000-0000-4000-8000-000000000094'
  ),
  'replay attempt leaves no clear bearer token in Auth metadata'
);

insert into public.user_invitations (
  id,
  tenant_id,
  email,
  role,
  permissions,
  invited_by,
  status,
  expires_at,
  token_hash,
  token_issued_at
)
values (
  '9f260000-0000-4000-8000-000000000025',
  '9f260000-0000-4000-8000-000000000001',
  'rotated-before-confirm@example.invalid',
  'cashier',
  '{"manage_users": false}'::jsonb,
  '9f260000-0000-4000-8000-000000000091',
  'pending',
  now() + interval '7 days',
  encode(
    extensions.digest(
      convert_to(
        'auth-boundary-rotated-before-confirm-token-v1',
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  ),
  now() - interval '2 minutes'
);

insert into auth.users (
  id,
  aud,
  role,
  email,
  encrypted_password,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
)
values (
  '9f260000-0000-4000-8000-000000000087',
  'authenticated',
  'authenticated',
  'rotated-before-confirm@example.invalid',
  '',
  '{}'::jsonb,
  jsonb_build_object(
    'account_type', 'staff_invitation',
    'invitation_token',
      'auth-boundary-rotated-before-confirm-token-v1'
  ),
  now(),
  now()
);

update public.user_invitations
set token_hash = encode(
      extensions.digest(
        convert_to(
          'auth-boundary-rotated-before-confirm-token-v2',
          'UTF8'
        ),
        'sha256'
      ),
      'hex'
    ),
    token_issued_at = clock_timestamp()
where id = '9f260000-0000-4000-8000-000000000025';

select lives_ok(
  $$
    update auth.users
    set email_confirmed_at = now()
    where id = '9f260000-0000-4000-8000-000000000087'
  $$,
  'mailbox confirmation survives invitation rotation'
);
select is(
  (
    select count(*)::integer
    from public.user_profiles
    where user_id = '9f260000-0000-4000-8000-000000000087'
  ),
  0,
  'rotated pre-confirmation intent leaves the identity unassigned'
);
select ok(
  (
    select email_confirmed_at is not null
      and not (
        coalesce(raw_app_meta_data, '{}'::jsonb)
          ? 'pending_invitation_token_hash'
      )
    from auth.users
    where id = '9f260000-0000-4000-8000-000000000087'
  ),
  'rotated intent confirmation clears the stale verifier'
);
select is(
  (
    select status
    from public.user_invitations
    where id = '9f260000-0000-4000-8000-000000000025'
  ),
  'pending',
  'rotated invitation remains available for explicit existing-user acceptance'
);

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '9f260000-0000-4000-8000-000000000087',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9f260000-0000-4000-8000-000000000087',
  true
);

select is(
  public.accept_user_invitation(
    'auth-boundary-rotated-before-confirm-token-v2'
  ),
  true,
  'confirmed identity can explicitly accept the rotated invitation'
);
select is(
  (
    select tenant_id
    from public.user_profiles
    where user_id = '9f260000-0000-4000-8000-000000000087'
      and is_active is true
  ),
  '9f260000-0000-4000-8000-000000000001'::uuid,
  'rotated invitation acceptance binds only its server-side tenant'
);

insert into public.user_invitations (
  id,
  tenant_id,
  email,
  role,
  permissions,
  invited_by,
  status,
  expires_at,
  token_hash,
  token_issued_at
)
values (
  '9f260000-0000-4000-8000-000000000026',
  '9f260000-0000-4000-8000-000000000002',
  'expired-before-confirm@example.invalid',
  'cashier',
  '{"manage_users": false}'::jsonb,
  '9f260000-0000-4000-8000-000000000091',
  'pending',
  now() + interval '7 days',
  encode(
    extensions.digest(
      convert_to(
        'auth-boundary-expired-before-confirm-token-v1',
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  ),
  now() - interval '2 minutes'
);

insert into auth.users (
  id,
  aud,
  role,
  email,
  encrypted_password,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
)
values (
  '9f260000-0000-4000-8000-000000000088',
  'authenticated',
  'authenticated',
  'expired-before-confirm@example.invalid',
  '',
  '{}'::jsonb,
  jsonb_build_object(
    'account_type', 'staff_invitation',
    'invitation_token',
      'auth-boundary-expired-before-confirm-token-v1'
  ),
  now(),
  now()
);

update public.user_invitations
set expires_at = now() - interval '1 second'
where id = '9f260000-0000-4000-8000-000000000026';

select lives_ok(
  $$
    update auth.users
    set email_confirmed_at = now()
    where id = '9f260000-0000-4000-8000-000000000088'
  $$,
  'mailbox confirmation survives invitation expiry'
);
select ok(
  (
    select email_confirmed_at is not null
      and not (
        coalesce(raw_app_meta_data, '{}'::jsonb)
          ? 'pending_invitation_token_hash'
      )
    from auth.users
    where id = '9f260000-0000-4000-8000-000000000088'
  ),
  'expired intent confirms the mailbox and clears stale authority'
);
select is(
  (
    select count(*)::integer
    from public.user_profiles
    where user_id = '9f260000-0000-4000-8000-000000000088'
  ),
  0,
  'expired invitation is neither consumed nor activated on confirmation'
);

insert into auth.users (
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
)
values (
  '9f260000-0000-4000-8000-000000000098',
  'authenticated',
  'authenticated',
  'existing-invite@example.invalid',
  '',
  now(),
  '{}'::jsonb,
  '{"provider": "google"}'::jsonb,
  now(),
  now()
);

insert into public.user_invitations (
  id,
  tenant_id,
  email,
  role,
  permissions,
  invited_by,
  metadata,
  status,
  expires_at,
  token_hash,
  token_issued_at
)
values (
  '9f260000-0000-4000-8000-000000000022',
  '9f260000-0000-4000-8000-000000000002',
  'existing-invite@example.invalid',
  'cashier',
  '{"manage_users": false}'::jsonb,
  '9f260000-0000-4000-8000-000000000091',
  '{"name": "Existing Invite Fixture"}'::jsonb,
  'pending',
  now() + interval '7 days',
  encode(
    extensions.digest(
      convert_to(
        'auth-boundary-existing-invitation-token-v1',
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  ),
  now() - interval '2 minutes'
);

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '9f260000-0000-4000-8000-000000000092',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9f260000-0000-4000-8000-000000000092',
  true
);

select throws_ok(
  $$
    select public.accept_user_invitation(
      'auth-boundary-existing-invitation-token-v1'
    )
  $$,
  '42501',
  'Invalid or unavailable invitation',
  'a confirmed user cannot consume an invitation issued to another email'
);

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '9f260000-0000-4000-8000-000000000098',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9f260000-0000-4000-8000-000000000098',
  true
);

select is(
  public.accept_user_invitation(
    'auth-boundary-existing-invitation-token-v1'
  ),
  true,
  'a confirmed existing Auth user accepts the matching bearer invitation'
);
select is(
  (
    select tenant_id
    from public.user_profiles
    where user_id = '9f260000-0000-4000-8000-000000000098'
      and is_active is true
  ),
  '9f260000-0000-4000-8000-000000000002'::uuid,
  'existing-user acceptance creates the invited tenant profile'
);
select is(
  (
    select role
    from public.user_profiles
    where user_id = '9f260000-0000-4000-8000-000000000098'
      and is_active is true
  ),
  'cashier',
  'existing-user acceptance preserves the server-side invited role'
);
select is(
  (
    select accepted_user_id
    from public.user_invitations
    where id = '9f260000-0000-4000-8000-000000000022'
      and status = 'accepted'
  ),
  '9f260000-0000-4000-8000-000000000098'::uuid,
  'existing-user acceptance records the Auth identity receipt'
);
select is(
  public.accept_user_invitation(
    'auth-boundary-existing-invitation-token-v1'
  ),
  true,
  'retrying an already accepted existing-user token is idempotent'
);
select is(
  (
    select raw_app_meta_data->>'tenant_id'
    from auth.users
    where id = '9f260000-0000-4000-8000-000000000098'
  ),
  '9f260000-0000-4000-8000-000000000002',
  'existing-user acceptance stamps authoritative tenant metadata'
);
select is(
  (
    select raw_app_meta_data->>'role'
    from auth.users
    where id = '9f260000-0000-4000-8000-000000000098'
  ),
  'cashier',
  'existing-user acceptance stamps authoritative role metadata'
);
select ok(
  (
    select not (
      coalesce(raw_user_meta_data, '{}'::jsonb) ?| array[
        'account_type',
        'tenant_id',
        'employee_id',
        'role',
        'permissions',
        'invitation_token'
      ]
    )
    from auth.users
    where id = '9f260000-0000-4000-8000-000000000098'
  ),
  'existing-user acceptance removes user-editable authority claims'
);

insert into public.user_invitations (
  id,
  tenant_id,
  email,
  role,
  permissions,
  invited_by,
  status,
  expires_at,
  token_hash,
  token_issued_at
)
values (
  '9f260000-0000-4000-8000-000000000023',
  '9f260000-0000-4000-8000-000000000002',
  'existing-invite@example.invalid',
  'admin',
  '{"manage_users": true}'::jsonb,
  '9f260000-0000-4000-8000-000000000091',
  'pending',
  now() + interval '7 days',
  encode(
    extensions.digest(
      convert_to(
        'auth-boundary-existing-same-tenant-token-v2',
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  ),
  now() - interval '2 minutes'
);

select throws_ok(
  $$ select public.accept_user_invitation(
    'auth-boundary-existing-same-tenant-token-v2'
  ) $$,
  'P0001',
  'active_staff_email_requires_direct_link',
  'a new same-tenant invitation cannot silently change active staff authority'
);
select ok(
  (
    select role = 'cashier'
      and permissions = '{"manage_users": false}'::jsonb
    from public.user_profiles
    where user_id = '9f260000-0000-4000-8000-000000000098'
      and is_active is true
  ),
  'rejected same-tenant invitation preserves the existing role and permissions'
);
select ok(
  (
    select status = 'pending'
      and accepted_user_id is null
      and token_hash is not null
    from public.user_invitations
    where id = '9f260000-0000-4000-8000-000000000023'
  ),
  'rejected same-tenant invitation remains pending for explicit resolution'
);

insert into public.user_invitations (
  id,
  tenant_id,
  email,
  role,
  permissions,
  invited_by,
  status,
  expires_at,
  token_hash,
  token_issued_at
)
values (
  '9f260000-0000-4000-8000-000000000024',
  '9f260000-0000-4000-8000-000000000001',
  'existing-invite@example.invalid',
  'admin',
  '{"manage_users": true}'::jsonb,
  '9f260000-0000-4000-8000-000000000091',
  'pending',
  now() + interval '7 days',
  encode(
    extensions.digest(
      convert_to(
        'auth-boundary-existing-cross-tenant-token-v3',
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  ),
  now() - interval '2 minutes'
);

select throws_ok(
  $$
    select public.accept_user_invitation(
      'auth-boundary-existing-cross-tenant-token-v3'
    )
  $$,
  'P0001',
  'identity_unavailable',
  'an existing active ERP identity cannot acquire a second tenant'
);
select is(
  (
    select count(*)::integer
    from public.user_profiles
    where user_id = '9f260000-0000-4000-8000-000000000098'
      and is_active is true
  ),
  1,
  'cross-tenant invitation rejection preserves one active ERP profile'
);

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '9f260000-0000-4000-8000-000000000093',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9f260000-0000-4000-8000-000000000093',
  true
);

select throws_ok(
  $$
    select *
    from public.get_tenant_users(
      '9f260000-0000-4000-8000-000000000001'
    )
  $$,
  '42501',
  'Not authorized for this tenant',
  'ordinary active staff cannot enumerate coworker identities'
);

update public.user_profiles
set role = 'manager',
    permissions = coalesce(permissions, '{}'::jsonb)
      || '{"manage_users": true}'::jsonb
where user_id = '9f260000-0000-4000-8000-000000000093'
  and tenant_id = '9f260000-0000-4000-8000-000000000001';

select is(
  (
    select count(*)::integer
    from public.get_tenant_users(
      '9f260000-0000-4000-8000-000000000001'
    )
    where id = '9f260000-0000-4000-8000-000000000093'
  ),
  1,
  'DB-authorized tenant managers can list staff in their tenant'
);
select throws_ok(
  $$
    select *
    from public.get_tenant_users(
      '9f260000-0000-4000-8000-000000000002'
    )
  $$,
  '42501',
  'Not authorized for this tenant',
  'staff listing fails closed across tenant boundaries'
);

update public.user_profiles
set role = 'mechanic',
    permissions = coalesce(permissions, '{}'::jsonb)
      || '{"manage_users": false}'::jsonb
where user_id = '9f260000-0000-4000-8000-000000000093'
  and tenant_id = '9f260000-0000-4000-8000-000000000001';

update auth.users
set email_confirmed_at = now()
where id = '9f260000-0000-4000-8000-000000000093';

select ok(
  public.provision_current_public_store_customer(
    '9f260000-0000-4000-8000-000000000002'
  ) is not null,
  'confirmed ERP staff can also provision a low-privilege storefront customer'
);
select is(
  (
    select count(*)::integer
    from public.customers customer
    where customer.tenant_id =
        '9f260000-0000-4000-8000-000000000002'
      and customer.auth_user_id =
        '9f260000-0000-4000-8000-000000000093'
  ),
  1,
  'shared staff/customer identity is authorized by the tenant customer row'
);
select is(
  (
    select raw_app_meta_data->>'account_type'
    from auth.users
    where id = '9f260000-0000-4000-8000-000000000093'
  ),
  'erp_staff',
  'customer provisioning never replaces authoritative staff account type'
);
select is(
  (
    select raw_app_meta_data->>'tenant_id'
    from auth.users
    where id = '9f260000-0000-4000-8000-000000000093'
  ),
  '9f260000-0000-4000-8000-000000000001',
  'customer provisioning never replaces the authoritative ERP tenant'
);
select is(
  (
    select raw_app_meta_data->>'role'
    from auth.users
    where id = '9f260000-0000-4000-8000-000000000093'
  ),
  'mechanic',
  'customer provisioning never replaces the authoritative ERP role'
);
select ok(
  (
    select (
      raw_app_meta_data->'customer_memberships'
        ->>'9f260000-0000-4000-8000-000000000002'
    )::uuid = (
      select customer.id
      from public.customers customer
      where customer.tenant_id =
          '9f260000-0000-4000-8000-000000000002'
        and customer.auth_user_id =
          '9f260000-0000-4000-8000-000000000093'
    )
    from auth.users
    where id = '9f260000-0000-4000-8000-000000000093'
  ),
  'shared workforce identity synchronizes its tenant customer membership'
);
select is(
  (
    select tenant_id
    from public.user_profiles
    where user_id = '9f260000-0000-4000-8000-000000000093'
      and is_active is true
  ),
  '9f260000-0000-4000-8000-000000000001'::uuid,
  'shared customer provisioning does not alter ERP profile membership'
);

insert into public.accounts (
  id,
  tenant_id,
  code,
  name,
  type,
  category
)
values
  (
    '9f260000-0000-4000-8000-000000000051',
    '9f260000-0000-4000-8000-000000000001',
    'AUTH-A',
    'Auth boundary account A',
    'asset',
    'currentAsset'
  ),
  (
    '9f260000-0000-4000-8000-000000000052',
    '9f260000-0000-4000-8000-000000000002',
    'AUTH-B',
    'Auth boundary account B',
    'asset',
    'currentAsset'
  );

insert into public.journal_entries (
  id,
  tenant_id,
  entry_number,
  description,
  type
)
values
  (
    '9f260000-0000-4000-8000-000000000031',
    '9f260000-0000-4000-8000-000000000001',
    'AUTH-JE-A',
    'Auth boundary journal tenant A',
    'manual'
  ),
  (
    '9f260000-0000-4000-8000-000000000032',
    '9f260000-0000-4000-8000-000000000002',
    'AUTH-JE-B',
    'Auth boundary journal tenant B',
    'manual'
  );

insert into public.journal_lines (
  id,
  tenant_id,
  entry_id,
  account_id,
  account_code,
  account_name,
  debit_amount
)
values
  (
    '9f260000-0000-4000-8000-000000000041',
    '9f260000-0000-4000-8000-000000000001',
    '9f260000-0000-4000-8000-000000000031',
    '9f260000-0000-4000-8000-000000000051',
    'AUTH-A',
    'Auth boundary account A',
    1
  ),
  (
    '9f260000-0000-4000-8000-000000000042',
    '9f260000-0000-4000-8000-000000000002',
    '9f260000-0000-4000-8000-000000000032',
    '9f260000-0000-4000-8000-000000000052',
    'AUTH-B',
    'Auth boundary account B',
    1
  );

update auth.users
set raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb)
      || jsonb_build_object(
        'tenant_id', '9f260000-0000-4000-8000-000000000002',
        'role', 'admin'
      )
where id = '9f260000-0000-4000-8000-000000000093';

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '9f260000-0000-4000-8000-000000000093',
    'role', 'authenticated',
    'user_metadata', jsonb_build_object(
      'tenant_id', '9f260000-0000-4000-8000-000000000002',
      'role', 'admin'
    )
  )::text,
  true
);

set local role authenticated;

select is(
  (select count(*)::integer from public.journal_entries),
  1,
  'mechanic sees journal entries only in the DB-backed active tenant'
);
select lives_ok(
  $$
    delete from public.journal_entries
    where id = '9f260000-0000-4000-8000-000000000031'
  $$,
  'forged admin user metadata cannot delete an own-tenant journal entry'
);
select lives_ok(
  $$
    delete from public.journal_entries
    where id = '9f260000-0000-4000-8000-000000000032'
  $$,
  'forged tenant metadata cannot delete a cross-tenant journal entry'
);
select is(
  (select count(*)::integer from public.journal_lines),
  1,
  'mechanic sees journal lines only in the DB-backed active tenant'
);
select lives_ok(
  $$
    delete from public.journal_lines
    where id in (
      '9f260000-0000-4000-8000-000000000041',
      '9f260000-0000-4000-8000-000000000042'
    )
  $$,
  'forged JWT metadata cannot delete own-tenant or cross-tenant journal lines'
);
select throws_ok(
  $$
    insert into public.bike_catalog (
      brand,
      model_name,
      model_year,
      data_source
    )
    values (
      'Auth Boundary Brand',
      'Forged Manager Model',
      2026,
      'manual'
    )
  $$,
  '42501',
  'permission denied for table bike_catalog',
  'forged admin metadata cannot mutate the shared bicycle catalog'
);

select throws_ok(
  $$
    insert into public.user_profiles (
      user_id,
      tenant_id,
      role,
      permissions
    )
    values (
      '9f260000-0000-4000-8000-000000000093',
      '9f260000-0000-4000-8000-000000000002',
      'admin',
      '{"manage_users": true}'::jsonb
    )
  $$,
  '42501',
  'permission denied for table user_profiles',
  'an authenticated user cannot self-escalate into another tenant'
);

reset role;

select is(
  (
    select count(*)::integer
    from public.journal_entries
    where id in (
      '9f260000-0000-4000-8000-000000000031',
      '9f260000-0000-4000-8000-000000000032'
    )
  ),
  2,
  'both tenant journal entries survive unauthorized delete attempts'
);
select is(
  (
    select count(*)::integer
    from public.journal_lines
    where id in (
      '9f260000-0000-4000-8000-000000000041',
      '9f260000-0000-4000-8000-000000000042'
    )
  ),
  2,
  'both tenant journal lines survive unauthorized delete attempts'
);

-- Runtime regression fixtures for privileged wrappers, storefront projection,
-- HR isolation, messaging, and suspended-tenant behavior.
set local session_replication_role = replica;

insert into auth.users (
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
)
values (
  '9f260000-0000-4000-8000-000000000082',
  'authenticated',
  'authenticated',
  'settings-manager-a@example.invalid',
  '',
  now(),
  jsonb_build_object(
    'account_type', 'erp_staff',
    'tenant_id', '9f260000-0000-4000-8000-000000000001',
    'role', 'manager'
  ),
  '{}'::jsonb,
  now(),
  now()
);

insert into public.user_profiles (
  user_id,
  tenant_id,
  role,
  permissions,
  is_active
)
values (
  '9f260000-0000-4000-8000-000000000082',
  '9f260000-0000-4000-8000-000000000001',
  'manager',
  '{"edit_settings": true}'::jsonb,
  true
);

insert into public.employees (
  id,
  tenant_id,
  employee_number,
  first_name,
  last_name,
  email,
  job_title,
  status
)
values (
  '9f26a100-0000-4000-8000-000000000013',
  '9f260000-0000-4000-8000-000000000002',
  'AUTH-HR-B-013',
  'Tenant B',
  'Employee',
  'tenant-b-employee@example.invalid',
  'Mechanic',
  'active'
);

insert into public.attendances (
  id,
  tenant_id,
  employee_id,
  check_in,
  check_out,
  worked_hours,
  status
)
values
  (
    '9f26a100-0000-4000-8000-000000000014',
    '9f260000-0000-4000-8000-000000000001',
    '9f260000-0000-4000-8000-000000000011',
    now() - interval '1 hour',
    null,
    null,
    'ongoing'
  ),
  (
    '9f26a100-0000-4000-8000-000000000015',
    '9f260000-0000-4000-8000-000000000002',
    '9f26a100-0000-4000-8000-000000000013',
    now() - interval '2 hours',
    null,
    null,
    'ongoing'
  ),
  (
    '9f26a100-0000-4000-8000-000000000016',
    '9f260000-0000-4000-8000-000000000001',
    '9f260000-0000-4000-8000-000000000011',
    date_trunc('day', now()) - interval '1 day' + interval '9 hours',
    date_trunc('day', now()) - interval '1 day' + interval '17 hours',
    8,
    'completed'
  ),
  (
    '9f26a100-0000-4000-8000-000000000017',
    '9f260000-0000-4000-8000-000000000002',
    '9f26a100-0000-4000-8000-000000000013',
    date_trunc('day', now()) - interval '1 day' + interval '9 hours',
    date_trunc('day', now()) - interval '1 day' + interval '18 hours',
    9,
    'completed'
  );

insert into public.sales_invoices (
  id,
  tenant_id,
  invoice_number,
  customer_name,
  status
)
values
  (
    '9f26a100-0000-4000-8000-000000000041',
    '9f260000-0000-4000-8000-000000000001',
    'AUTH-PRIV-INVOICE-A',
    'Tenant A invoice fixture',
    'draft'
  ),
  (
    '9f26a100-0000-4000-8000-000000000042',
    '9f260000-0000-4000-8000-000000000002',
    'AUTH-PRIV-INVOICE-B',
    'Tenant B invoice fixture',
    'draft'
  );

insert into public.database_backups (
  id,
  tenant_id,
  backup_name,
  backup_type,
  status,
  backup_data
)
values (
  '9f26a100-0000-4000-8000-000000000052',
  '9f260000-0000-4000-8000-000000000002',
  'Auth cross-tenant backup B',
  'manual',
  'completed',
  '{}'::jsonb
);

insert into public.website_backups (
  id,
  tenant_id,
  name,
  blocks_snapshot,
  settings_snapshot,
  pages_snapshot
)
values (
  '9f26a100-0000-4000-8000-000000000053',
  '9f260000-0000-4000-8000-000000000002',
  'Auth cross-tenant website backup B',
  '[]'::jsonb,
  '{}'::jsonb,
  '[]'::jsonb
);

insert into public.website_pages (
  id,
  tenant_id,
  slug,
  title,
  is_published,
  is_home
)
values
  (
    '9f26a100-0000-4000-8000-000000000021',
    '9f260000-0000-4000-8000-000000000001',
    'auth-public-home-a',
    'Auth public home A',
    true,
    true
  ),
  (
    '9f26a100-0000-4000-8000-000000000022',
    '9f260000-0000-4000-8000-000000000001',
    'auth-public-draft-a',
    'Auth public draft A',
    false,
    false
  ),
  (
    '9f26a100-0000-4000-8000-000000000023',
    '9f260000-0000-4000-8000-000000000002',
    'auth-public-home-b',
    'Auth public home B',
    true,
    true
  );

insert into public.website_blocks (
  id,
  tenant_id,
  page_id,
  block_type,
  block_data,
  is_visible,
  order_index
)
values
  (
    '9f26a100-0000-4000-8000-000000000024',
    '9f260000-0000-4000-8000-000000000001',
    '9f26a100-0000-4000-8000-000000000021',
    'hero',
    '{"marker":"visible-a"}'::jsonb,
    true,
    1
  ),
  (
    '9f26a100-0000-4000-8000-000000000025',
    '9f260000-0000-4000-8000-000000000001',
    '9f26a100-0000-4000-8000-000000000021',
    'hero',
    '{"marker":"hidden-a"}'::jsonb,
    false,
    2
  ),
  (
    '9f26a100-0000-4000-8000-000000000026',
    '9f260000-0000-4000-8000-000000000002',
    '9f26a100-0000-4000-8000-000000000023',
    'hero',
    '{"marker":"visible-b"}'::jsonb,
    true,
    1
  );

insert into public.website_settings (tenant_id, key, value, description)
values
  (
    '9f260000-0000-4000-8000-000000000001',
    'public_banner_text',
    'safe-a',
    'safe public test value'
  ),
  (
    '9f260000-0000-4000-8000-000000000002',
    'public_banner_text',
    'safe-b',
    'cross-tenant safe value'
  ),
  (
    '9f260000-0000-4000-8000-000000000001',
    'google_places_api_key',
    'google-secret-a',
    'secret test value'
  ),
  (
    '9f260000-0000-4000-8000-000000000001',
    'mercadopago_access_token',
    'mp-secret-old',
    'secret test value'
  ),
  (
    '9f260000-0000-4000-8000-000000000001',
    'mercadopago_webhook_secret',
    'webhook-secret-a',
    'secret test value'
  );

insert into public.conversations (
  id,
  tenant_id,
  type,
  channel,
  title,
  created_by,
  counterparty_type
)
values (
  '9f26a100-0000-4000-8000-000000000031',
  '9f260000-0000-4000-8000-000000000001',
  'internal',
  'internal',
  'Auth tenant activity fixture',
  '9f260000-0000-4000-8000-000000000093',
  'internal'
);

insert into public.conversation_participants (
  conversation_id,
  user_id,
  tenant_id,
  role
)
values (
  '9f26a100-0000-4000-8000-000000000031',
  '9f260000-0000-4000-8000-000000000093',
  '9f260000-0000-4000-8000-000000000001',
  'admin'
);

set local session_replication_role = origin;

-- A regular mechanic cannot use privileged wrappers, but retains the direct
-- mechanic-job insert contract that depends on the generated-number function.
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '9f260000-0000-4000-8000-000000000093',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9f260000-0000-4000-8000-000000000093',
  true
);

set local role authenticated;

select throws_ok(
  $$
    select public.create_backup(
      '9f260000-0000-4000-8000-000000000002',
      'Unauthorized cross-tenant backup'
    )
  $$,
  '42501',
  'Backup access denied',
  'ordinary staff cannot create a backup for another tenant'
);
select throws_ok(
  $$ select public.create_website_backup('Unauthorized website backup') $$,
  '42501',
  'Website backup access denied',
  'ordinary staff cannot create website backups'
);
select throws_ok(
  $$
    select public.ensure_account(
      'AUTH-DENIED',
      'Unauthorized account',
      'asset',
      'currentAsset',
      null,
      null
    )
  $$,
  '42501',
  'Accounting access denied',
  'ordinary staff cannot create chart-of-account records'
);
select throws_ok(
  $$
    select public.ensure_sales_invoice_journal_entry(
      '9f26a100-0000-4000-8000-000000000041'
    )
  $$,
  '42501',
  'Accounting access denied',
  'ordinary staff cannot create an invoice journal'
);
select throws_ok(
  $$
    select public.generate_f29_from_accounting(
      '9f260000-0000-4000-8000-000000000002',
      2026,
      7
    )
  $$,
  '42501',
  'Accounting access denied',
  'ordinary staff cannot generate another tenant F29'
);
select throws_ok(
  $$ select * from public.get_checked_in_employees() $$,
  '42501',
  'Attendance access denied',
  'ordinary staff cannot inspect the tenant-wide check-in roster'
);
select throws_ok(
  $$
    select *
    from public.get_attendance_summary(
      '9f26a100-0000-4000-8000-000000000013',
      current_date - 7,
      current_date
    )
  $$,
  '42501',
  'Attendance access denied',
  'attendance summary rejects a cross-tenant employee'
);
select throws_ok(
  $$
    select public.get_employee_hours_summary(
      '9f26a100-0000-4000-8000-000000000013',
      current_date - 7,
      current_date
    )
  $$,
  '42501',
  'Attendance access denied',
  'hours summary rejects a cross-tenant employee'
);
select throws_ok(
  $$
    select *
    from public.get_attendance_summary_for_period(
      current_date - 7,
      current_date
    )
  $$,
  '42501',
  'Attendance access denied',
  'ordinary staff cannot aggregate the tenant-wide attendance period'
);
select lives_ok(
  $$
    insert into public.mechanic_jobs (
      id,
      tenant_id,
      customer_id,
      bike_id,
      notes
    )
    values (
      '9f26a100-0000-4000-8000-000000000061',
      '9f260000-0000-4000-8000-000000000001',
      (
        select id
        from public.customers
        where tenant_id = '9f260000-0000-4000-8000-000000000001'
          and auth_user_id =
            '9f260000-0000-4000-8000-000000000092'
      ),
      '9f260000-0000-4000-8000-000000000073',
      'Authenticated generated-number contract'
    )
  $$,
  'authenticated mechanic insert can execute the job-number default'
);
select ok(
  (
    select job_number is not null and btrim(job_number) <> ''
    from public.mechanic_jobs
    where id = '9f26a100-0000-4000-8000-000000000061'
  ),
  'the direct mechanic insert receives a generated job number'
);
select ok(
  public.messaging_is_staff_in_tenant(
    '9f260000-0000-4000-8000-000000000001'
  )
  and public.messaging_user_belongs_to_tenant(
    '9f260000-0000-4000-8000-000000000093',
    '9f260000-0000-4000-8000-000000000001'
  )
  and public.messaging_is_conversation_participant(
    '9f26a100-0000-4000-8000-000000000031'
  )
  and public.messaging_can_access_conversation(
    '9f26a100-0000-4000-8000-000000000031'
  )
  and public.messaging_can_read_conversation_messages(
    '9f26a100-0000-4000-8000-000000000031'
  )
  and public.messaging_can_manage_conversation(
    '9f26a100-0000-4000-8000-000000000031'
  ),
  'messaging helpers retain active same-tenant participant access'
);
select lives_ok(
  $$
    update public.website_settings
    set value = 'low-privilege-overwrite'
    where tenant_id = '9f260000-0000-4000-8000-000000000001'
      and key = 'mercadopago_access_token'
  $$,
  'low-privilege direct secret update affects no protected row'
);
select throws_ok(
  $$
    insert into public.website_settings (tenant_id, key, value)
    values (
      '9f260000-0000-4000-8000-000000000001',
      'low_privilege_setting',
      'forbidden'
    )
  $$,
  '42501',
  'new row violates row-level security policy for table "website_settings"',
  'low-privilege staff cannot insert even a non-sensitive setting'
);

reset role;

select is(
  (
    select value
    from public.website_settings
    where tenant_id = '9f260000-0000-4000-8000-000000000001'
      and key = 'mercadopago_access_token'
  ),
  'mp-secret-old',
  'the low-privilege secret overwrite did not change stored credentials'
);

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '9f260000-0000-4000-8000-000000000082',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9f260000-0000-4000-8000-000000000082',
  true
);

set local role authenticated;

select ok(
  public.can_edit_tenant_settings(
    '9f260000-0000-4000-8000-000000000001'
  )
  and not public.can_manage_tenant_backups(
    '9f260000-0000-4000-8000-000000000001'
  ),
  'settings managers cannot inherit destructive backup authority'
);
select throws_ok(
  $$
    select public.create_backup(
      '9f260000-0000-4000-8000-000000000001',
      'Manager must not create backup'
    )
  $$,
  '42501',
  'Backup access denied',
  'settings managers cannot create own-tenant database backups'
);

reset role;

-- A DB-backed administrator can use exact own-tenant wrappers, while every
-- caller-supplied or backup-derived cross-tenant path fails closed.
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '9f260000-0000-4000-8000-000000000081',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9f260000-0000-4000-8000-000000000081',
  true
);

set local role authenticated;

select ok(
  public.can_manage_tenant_backups(
    '9f260000-0000-4000-8000-000000000001'
  ),
  'active DB-backed admin retains destructive backup authority'
);
select lives_ok(
  $$
    select public.create_backup(
      '9f260000-0000-4000-8000-000000000001',
      'Auth authorized backup A'
    )
  $$,
  'authorized admin can create an own-tenant database backup'
);
select lives_ok(
  $$
    select public.get_backup_summary(
      (
        select id
        from public.database_backups
        where tenant_id = '9f260000-0000-4000-8000-000000000001'
          and backup_name = 'Auth authorized backup A'
        order by created_at desc
        limit 1
      )
    )
  $$,
  'authorized admin can read an own-tenant backup summary'
);
select throws_ok(
  $$
    select public.get_backup_summary(
      '9f26a100-0000-4000-8000-000000000052'
    )
  $$,
  '42501',
  'Backup access denied',
  'authorized admin cannot read another tenant backup summary'
);
select lives_ok(
  $$
    select public.cleanup_old_backups(
      '9f260000-0000-4000-8000-000000000001'
    )
  $$,
  'authorized admin can run own-tenant backup retention'
);
select lives_ok(
  $$
    select public.create_website_backup(
      'Auth authorized website backup A',
      'pgTAP fixture',
      false
    )
  $$,
  'authorized admin can create an own-tenant website backup'
);
select lives_ok(
  $$
    select public.restore_website_backup(
      (
        select id
        from public.website_backups
        where tenant_id = '9f260000-0000-4000-8000-000000000001'
          and name = 'Auth authorized website backup A'
        order by created_at desc
        limit 1
      ),
      false
    )
  $$,
  'authorized admin can restore an own-tenant website backup'
);
select throws_ok(
  $$
    select public.restore_website_backup(
      '9f26a100-0000-4000-8000-000000000053',
      false
    )
  $$,
  '42501',
  'Website backup access denied',
  'authorized admin cannot restore another tenant website backup'
);
select lives_ok(
  $$
    select public.ensure_account(
      'AUTH-ADMIN-ASSET',
      'Authorized admin account',
      'asset',
      'currentAsset',
      'pgTAP fixture',
      null
    )
  $$,
  'authorized admin can ensure an own-tenant account'
);
select lives_ok(
  $$
    select public.ensure_sales_invoice_journal_entry(
      '9f26a100-0000-4000-8000-000000000041'
    )
  $$,
  'authorized admin can ensure an own-tenant invoice journal'
);
select throws_ok(
  $$
    select public.ensure_sales_invoice_journal_entry(
      '9f26a100-0000-4000-8000-000000000042'
    )
  $$,
  '42501',
  'Accounting access denied',
  'authorized admin cannot journal another tenant invoice'
);
select lives_ok(
  $$
    select public.generate_f29_from_accounting(
      '9f260000-0000-4000-8000-000000000001',
      2026,
      7
    )
  $$,
  'authorized admin can generate an own-tenant F29 projection'
);
select throws_ok(
  $$
    select public.generate_f29_from_accounting(
      '9f260000-0000-4000-8000-000000000002',
      2026,
      7
    )
  $$,
  '42501',
  'Accounting access denied',
  'authorized admin cannot generate another tenant F29 projection'
);
select throws_ok(
  $$
    insert into public.website_settings (tenant_id, key, value)
    values (
      '9f260000-0000-4000-8000-000000000001',
      'mercadopago_access_token',
      'direct-upsert-must-fail'
    )
    on conflict (tenant_id, key) do update
    set value = excluded.value
  $$,
  '42501',
  'new row violates row-level security policy for table "website_settings"',
  'authorized direct upsert cannot require SELECT visibility of a secret'
);
select lives_ok(
  $$
    select public.save_mercadopago_settings(
      'mp-public-new',
      'mp-secret-new',
      true
    )
  $$,
  'authorized secret writer atomically replaces all MercadoPago settings'
);
select lives_ok(
  $$
    insert into public.website_settings (tenant_id, key, value)
    values (
      '9f260000-0000-4000-8000-000000000001',
      'authorized_safe_setting',
      'safe-admin-value'
    )
  $$,
  'authorized admin can insert a non-sensitive own-tenant setting'
);
select throws_ok(
  $$
    select public.save_mercadopago_settings(
      repeat('x', 513),
      'valid-token',
      false
    )
  $$,
  '22023',
  'Invalid MercadoPago settings',
  'MercadoPago writer rejects oversized credentials atomically'
);

reset role;

select ok(
  (
    select value = 'mp-public-new'
    from public.website_settings
    where tenant_id = '9f260000-0000-4000-8000-000000000001'
      and key = 'mercadopago_public_key'
  )
  and (
    select value = 'mp-secret-new'
    from public.website_settings
    where tenant_id = '9f260000-0000-4000-8000-000000000001'
      and key = 'mercadopago_access_token'
  )
  and (
    select value = 'true'
    from public.website_settings
    where tenant_id = '9f260000-0000-4000-8000-000000000001'
      and key = 'mercadopago_test_mode'
  ),
  'MercadoPago writer commits the exact three same-tenant values together'
);

select set_config('request.jwt.claims', '{"role":"anon"}', true);
select set_config('request.jwt.claim.sub', '', true);

set local role anon;

select ok(
  (
    public.get_public_store_data(
      '9f260000-0000-4000-8000-000000000001'
    )::jsonb -> 'settings' ->> 'public_banner_text'
  ) = 'safe-a'
  and not (
    public.get_public_store_data(
      '9f260000-0000-4000-8000-000000000001'
    )::jsonb -> 'settings'
    ?| array[
      'google_places_api_key',
      'mercadopago_access_token',
      'mercadopago_webhook_secret'
    ]
  ),
  'public store data exposes the safe key and none of the three real secrets'
);
select ok(
  (
    public.get_public_store_data(
      '9f260000-0000-4000-8000-000000000001'
    )::jsonb ->> 'home_page_id'
  )::uuid = '9f26a100-0000-4000-8000-000000000021'
  and jsonb_array_length(
    public.get_public_store_data(
      '9f260000-0000-4000-8000-000000000001'
    )::jsonb -> 'blocks'
  ) = 1
  and (
    public.get_public_store_data(
      '9f260000-0000-4000-8000-000000000001'
    )::jsonb #>> '{blocks,0,block_data,marker}'
  ) = 'visible-a',
  'public store data returns only the published home and visible same-tenant block'
);
select ok(
  not exists (
    select 1
    from public.website_settings
    where public.website_setting_is_sensitive(key)
  ),
  'anonymous direct website settings reads contain no sensitive rows'
);

reset role;

-- Suspension invalidates every DB-backed authority surface immediately.
update public.tenants
set is_active = false
where id = '9f260000-0000-4000-8000-000000000001';

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '9f260000-0000-4000-8000-000000000081',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9f260000-0000-4000-8000-000000000081',
  true
);

set local role authenticated;

select throws_ok(
  $$
    select public.save_mercadopago_settings(
      'inactive-public',
      'inactive-secret',
      false
    )
  $$,
  '42501',
  'Website settings access denied',
  'suspended tenant cannot mutate MercadoPago secrets'
);
select throws_ok(
  $$
    insert into public.website_settings (tenant_id, key, value)
    values (
      '9f260000-0000-4000-8000-000000000001',
      'inactive_safe_setting',
      'forbidden'
    )
  $$,
  '42501',
  'new row violates row-level security policy for table "website_settings"',
  'suspended tenant cannot insert a safe setting'
);
select throws_ok(
  $$
    select public.create_backup(
      '9f260000-0000-4000-8000-000000000001',
      'Inactive tenant backup'
    )
  $$,
  '42501',
  'Backup access denied',
  'suspended tenant cannot create a database backup'
);

reset role;

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '9f260000-0000-4000-8000-000000000093',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9f260000-0000-4000-8000-000000000093',
  true
);

set local role authenticated;

select ok(
  not public.messaging_is_staff_in_tenant(
    '9f260000-0000-4000-8000-000000000001'
  )
  and not public.messaging_user_belongs_to_tenant(
    '9f260000-0000-4000-8000-000000000093',
    '9f260000-0000-4000-8000-000000000001'
  )
  and not public.has_active_official_document_staff_access(
    '9f260000-0000-4000-8000-000000000001'
  )
  and not public.messaging_is_conversation_participant(
    '9f26a100-0000-4000-8000-000000000031'
  )
  and not public.messaging_can_access_conversation(
    '9f26a100-0000-4000-8000-000000000031'
  )
  and not public.messaging_can_read_conversation_messages(
    '9f26a100-0000-4000-8000-000000000031'
  )
  and not public.messaging_can_manage_conversation(
    '9f26a100-0000-4000-8000-000000000031'
  ),
  'suspension invalidates messaging, membership, and document helpers together'
);
select throws_ok(
  $$
    select public.save_bike_aggregate(
      'inactive-bike-save',
      '9f26a100-0000-4000-8000-000000000071',
      '9f26a100-0000-4000-8000-000000000072',
      null,
      null,
      '{}'::jsonb,
      null
    )
  $$,
  '42501',
  'Tenant aggregate access denied',
  'suspended tenant cannot enter the atomic bike save body'
);
select throws_ok(
  $$
    select public.get_bike_aggregate(
      '9f26a100-0000-4000-8000-000000000071'
    )
  $$,
  '42501',
  'Tenant aggregate access denied',
  'suspended tenant cannot read a bike aggregate'
);
select throws_ok(
  $$
    select public.get_bike_aggregate_save_operation(
      'inactive-bike-receipt'
    )
  $$,
  '42501',
  'Tenant aggregate access denied',
  'suspended tenant cannot read a bike idempotency receipt'
);
select throws_ok(
  $$
    select public.save_expense_aggregate(
      'inactive-expense-save',
      '9f26a100-0000-4000-8000-000000000073',
      now(),
      '{}'::jsonb
    )
  $$,
  '42501',
  'Tenant aggregate access denied',
  'suspended tenant cannot enter the atomic expense save body'
);
select throws_ok(
  $$
    select public.get_expense_aggregate_save_operation(
      'inactive-expense-receipt'
    )
  $$,
  '42501',
  'Tenant aggregate access denied',
  'suspended tenant cannot read an expense idempotency receipt'
);

-- These helpers are trigger-internal and intentionally have no authenticated
-- EXECUTE grant. Invoke as the migration owner while preserving the caller JWT
-- to test their inactive-tenant guard rather than their ACL boundary.
reset role;

select throws_ok(
  $$
    select public.assert_sales_payment_access(
      '9f260000-0000-4000-8000-000000000001'
    )
  $$,
  '42501',
  'Payment tenant is inactive or unavailable',
  'sales payment access rejects a suspended tenant'
);
select throws_ok(
  $$
    select public.assert_purchase_payment_access(
      '9f260000-0000-4000-8000-000000000001'
    )
  $$,
  '42501',
  'Purchase payment tenant is inactive or unavailable',
  'purchase payment access rejects a suspended tenant'
);

reset role;

select set_config('request.jwt.claims', '{"role":"anon"}', true);
select set_config('request.jwt.claim.sub', '', true);

set local role anon;

select is(
  public.get_public_store_data(
    '9f260000-0000-4000-8000-000000000001'
  )::jsonb,
  jsonb_build_object(
    'settings', '{}'::jsonb,
    'blocks', '[]'::jsonb,
    'home_page_id', null
  ),
  'inactive storefront returns a uniform empty public payload'
);

reset role;

update public.tenants
set is_active = true
where id = '9f260000-0000-4000-8000-000000000001';

set local role anon;

select throws_ok(
  $$ select count(*) from public.user_invitations $$,
  '42501',
  'permission denied for table user_invitations',
  'PostgREST-equivalent anonymous invitation enumeration is rejected'
);
select throws_ok(
  $$
    insert into public.tenants (shop_name, subdomain)
    values ('Unauthorized Tenant', 'unauthorized-tenant')
  $$,
  '42501',
  'permission denied for table tenants',
  'PostgREST-equivalent anonymous tenant creation is rejected'
);

reset role;

select is(
  (
    select count(*)::integer
    from public.lookup_user_invitation(
      'auth-boundary-invitation-token-v2-1234567890'
    )
  ),
  0,
  'an accepted token is no longer resolvable'
);

select * from finish();

rollback;
