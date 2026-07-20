begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select no_plan();

select has_function(
  'public',
  'reconcile_conversation_context_projections',
  array[]::text[],
  'owner-only context projection reconciliation exists'
);
select has_table(
  'public',
  'messaging_context_projection_reconciliation_audit',
  'dangling scalar reconciliation retains append-only audit evidence'
);
select is(
  (
    select count(*)::integer
    from pg_constraint constraint_row
    where constraint_row.conrelid =
      'public.messaging_context_projection_reconciliation_audit'::regclass
      and constraint_row.contype = 'f'
  ),
  0,
  'audit UUID snapshots do not depend on later tenant or conversation survival'
);
select ok(
  (
    select relation.relrowsecurity and relation.relforcerowsecurity
    from pg_class relation
    where relation.oid =
      'public.messaging_context_projection_reconciliation_audit'::regclass
  ),
  'audit evidence forces row-level security even for its owner'
);
select ok(
  not exists (
    select 1
    from pg_policy policy
    where policy.polrelid =
      'public.messaging_context_projection_reconciliation_audit'::regclass
      and 0::oid = any(policy.polroles)
  ),
  'no audit policy applies to PUBLIC'
);
select ok(
  (
    select bool_and(
      policy.polroles = array[relation.relowner]::oid[]
    )
    from pg_policy policy
    join pg_class relation on relation.oid = policy.polrelid
    where policy.polrelid =
      'public.messaging_context_projection_reconciliation_audit'::regclass
      and policy.polname in (
        'messaging_context_projection_audit_owner_insert',
        'messaging_context_projection_audit_owner_read'
      )
  ),
  'owner audit policies target only the exact table owner role'
);
select ok(
  not has_table_privilege(
    'authenticated',
    'public.messaging_context_projection_reconciliation_audit',
    'SELECT'
  )
  and not has_table_privilege(
    'authenticated',
    'public.messaging_context_projection_reconciliation_audit',
    'INSERT'
  )
  and not has_table_privilege(
    'authenticated',
    'public.messaging_context_projection_reconciliation_audit',
    'UPDATE'
  )
  and not has_table_privilege(
    'authenticated',
    'public.messaging_context_projection_reconciliation_audit',
    'DELETE'
  ),
  'authenticated callers cannot inspect or mutate reconciliation evidence'
);
select ok(
  has_table_privilege(
    'service_role',
    'public.messaging_context_projection_reconciliation_audit',
    'SELECT'
  )
  and not has_table_privilege(
    'service_role',
    'public.messaging_context_projection_reconciliation_audit',
    'INSERT'
  )
  and not has_table_privilege(
    'service_role',
    'public.messaging_context_projection_reconciliation_audit',
    'UPDATE'
  )
  and not has_table_privilege(
    'service_role',
    'public.messaging_context_projection_reconciliation_audit',
    'DELETE'
  ),
  'service role can inspect but cannot forge or mutate reconciliation evidence'
);
select ok(
  not has_function_privilege(
    'service_role',
    'public.messaging_context_entity_exists_any_tenant(text,uuid)',
    'EXECUTE'
  ),
  'cross-tenant existence helper is not exposed as an enumeration RPC'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.set_config(text,text,boolean)',
    'EXECUTE'
  ),
  'authenticated callers cannot mint the owner reconciliation capability'
);
select has_trigger(
  'public',
  'conversations',
  'trg_conversations_context_projection_commit',
  'scalar projection has a commit-time invariant trigger'
);
select has_trigger(
  'public',
  'conversation_contexts',
  'trg_conversation_contexts_projection_commit',
  'primary ledger has a commit-time invariant trigger'
);
select ok(
  (
    select trigger.tgdeferrable and trigger.tginitdeferred
    from pg_trigger trigger
    where trigger.tgrelid = 'public.conversations'::regclass
      and trigger.tgname = 'trg_conversations_context_projection_commit'
  ),
  'scalar invariant is DEFERRABLE INITIALLY DEFERRED'
);
select ok(
  (
    select trigger.tgdeferrable and trigger.tginitdeferred
    from pg_trigger trigger
    where trigger.tgrelid = 'public.conversation_contexts'::regclass
      and trigger.tgname = 'trg_conversation_contexts_projection_commit'
  ),
  'ledger invariant is DEFERRABLE INITIALLY DEFERRED'
);
select ok(
  not has_function_privilege(
    'service_role',
    'public.reconcile_conversation_context_projections()',
    'EXECUTE'
  ),
  'service role cannot invoke the migration repair helper'
);
select results_eq(
  $$
    select
      procedure_row.oid::regprocedure::text,
      (
        count(expanded_acl.grantee) filter (
          where expanded_acl.grantee <> procedure_row.proowner
        )
      )::integer as non_owner_acl_entries
    from pg_proc procedure_row
    cross join lateral aclexplode(
      coalesce(
        procedure_row.proacl,
        acldefault('f', procedure_row.proowner)
      )
    ) expanded_acl
    where procedure_row.oid in (
      'public.enforce_messaging_context_projection_audit_immutable()'::regprocedure,
      'public.messaging_context_entity_exists_any_tenant(text,uuid)'::regprocedure,
      'public.assert_conversation_context_projection(uuid)'::regprocedure,
      'public.reconcile_conversation_context_projections()'::regprocedure,
      'public.enforce_conversation_context_projection_at_commit()'::regprocedure
    )
    group by procedure_row.oid
    order by procedure_row.oid::regprocedure::text
  $$,
  $$values
    ('assert_conversation_context_projection(uuid)'::text, 0::integer),
    ('enforce_conversation_context_projection_at_commit()'::text, 0::integer),
    ('enforce_messaging_context_projection_audit_immutable()'::text, 0::integer),
    ('messaging_context_entity_exists_any_tenant(text,uuid)'::text, 0::integer),
    ('reconcile_conversation_context_projections()'::text, 0::integer)
  $$,
  'all context projection helpers have zero PUBLIC or named non-owner ACL entries'
);

insert into public.tenants (id, shop_name) values
  (
    '9f192130-0000-4000-8000-000000000001',
    'Context Projection Contract Tenant'
  ),
  (
    '9f192130-0000-4000-8000-000000000002',
    'Cross Tenant Projection Contract Tenant'
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
) values (
  '9f192130-0000-4000-8000-000000000091',
  'authenticated',
  'authenticated',
  'context-projection-staff@example.invalid',
  '',
  now(),
  '{}'::jsonb,
  jsonb_build_object(
    'tenant_id',
    '9f192130-0000-4000-8000-000000000001'
  ),
  now(),
  now()
);

insert into public.user_profiles (
  user_id,
  tenant_id,
  role,
  permissions,
  is_active
) values (
  '9f192130-0000-4000-8000-000000000091',
  '9f192130-0000-4000-8000-000000000001',
  'admin',
  '{}'::jsonb,
  true
);

insert into public.customers (
  id,
  tenant_id,
  name,
  email,
  phone,
  is_active
) values
  (
    '9f192130-0000-4000-8000-000000000111',
    '9f192130-0000-4000-8000-000000000001',
    'Context Projection Customer A',
    'context-projection-a@example.invalid',
    '+56970000001',
    true
  ),
  (
    '9f192130-0000-4000-8000-000000000112',
    '9f192130-0000-4000-8000-000000000001',
    'Context Projection Customer B',
    'context-projection-b@example.invalid',
    '+56970000002',
    true
  ),
  (
    '9f192130-0000-4000-8000-000000000113',
    '9f192130-0000-4000-8000-000000000002',
    'Cross Tenant Projection Customer',
    'context-projection-cross-tenant@example.invalid',
    '+56970000003',
    true
  );

-- Build the four legacy shapes while only the new projection constraints and
-- the old scalar-synchronization trigger are disabled. Tenant and capability
-- guards remain active, so every synthetic context is otherwise valid.
alter table public.conversations
  disable trigger trg_conversations_context_projection_commit;
alter table public.conversation_contexts
  disable trigger trg_conversation_contexts_projection_commit;
alter table public.conversation_contexts
  disable trigger trg_conversation_context_counterparty_guard;

insert into public.conversations (
  id,
  tenant_id,
  type,
  channel,
  counterparty_type,
  status,
  created_by,
  context_type,
  context_id,
  updated_at
) values
  -- Existing primary must win over this stale complete scalar pair.
  (
    '9f192130-0000-4000-8000-000000000301',
    '9f192130-0000-4000-8000-000000000001',
    'support',
    'website_portal',
    'customer',
    'active',
    null,
    'customer',
    '9f192130-0000-4000-8000-000000000111',
    '2026-01-01 10:00:01+00'
  ),
  -- Exact non-primary history must be promoted without replacing its row.
  (
    '9f192130-0000-4000-8000-000000000302',
    '9f192130-0000-4000-8000-000000000001',
    'support',
    'website_portal',
    'customer',
    'active',
    null,
    'customer',
    '9f192130-0000-4000-8000-000000000111',
    '2026-01-01 10:00:02+00'
  ),
  -- Complete scalar without a ledger row appends one with no invented actor.
  (
    '9f192130-0000-4000-8000-000000000303',
    '9f192130-0000-4000-8000-000000000001',
    'support',
    'website_portal',
    'customer',
    'active',
    null,
    'customer',
    '9f192130-0000-4000-8000-000000000111',
    null
  ),
  -- Cleared scalar plus non-primary history remains intentionally cleared.
  (
    '9f192130-0000-4000-8000-000000000304',
    '9f192130-0000-4000-8000-000000000001',
    'support',
    'website_portal',
    'customer',
    'active',
    null,
    null,
    null,
    '2026-01-01 10:00:04+00'
  ),
  -- A scalar whose target was deleted is archived and cleared, never promoted.
  (
    '9f192130-0000-4000-8000-000000000307',
    '9f192130-0000-4000-8000-000000000001',
    'support',
    'website_portal',
    'customer',
    'active',
    null,
    'job',
    '9f192130-0000-4000-8000-000000000999',
    '2026-01-01 10:00:07+00'
  );

insert into public.conversation_contexts (
  id,
  conversation_id,
  context_type,
  context_id,
  is_primary,
  added_by,
  added_at,
  tenant_id
) values
  (
    '9f192130-0000-4000-8000-000000000401',
    '9f192130-0000-4000-8000-000000000301',
    'customer',
    '9f192130-0000-4000-8000-000000000112',
    true,
    '9f192130-0000-4000-8000-000000000091',
    '2026-01-01 09:00:01+00',
    '9f192130-0000-4000-8000-000000000001'
  ),
  (
    '9f192130-0000-4000-8000-000000000402',
    '9f192130-0000-4000-8000-000000000302',
    'customer',
    '9f192130-0000-4000-8000-000000000111',
    false,
    '9f192130-0000-4000-8000-000000000091',
    '2026-01-01 09:00:02+00',
    '9f192130-0000-4000-8000-000000000001'
  ),
  (
    '9f192130-0000-4000-8000-000000000404',
    '9f192130-0000-4000-8000-000000000304',
    'customer',
    '9f192130-0000-4000-8000-000000000112',
    false,
    '9f192130-0000-4000-8000-000000000091',
    '2026-01-01 09:00:04+00',
    '9f192130-0000-4000-8000-000000000001'
  );

alter table public.conversation_contexts
  enable trigger trg_conversation_context_counterparty_guard;
alter table public.conversation_contexts
  enable trigger trg_conversation_contexts_projection_commit;
alter table public.conversations
  enable trigger trg_conversations_context_projection_commit;

select is(
  public.reconcile_conversation_context_projections(),
  4,
  'reconciliation repairs three valid projections and one dangling scalar'
);

set constraints all immediate;
set constraints all deferred;

select is(
  (
    select conversation.context_id
    from public.conversations conversation
    where conversation.id = '9f192130-0000-4000-8000-000000000301'
  ),
  '9f192130-0000-4000-8000-000000000112'::uuid,
  'existing primary ledger row wins a complete scalar conflict'
);
select is(
  (
    select context_link.id
    from public.conversation_contexts context_link
    where context_link.conversation_id =
      '9f192130-0000-4000-8000-000000000302'
      and context_link.is_primary
  ),
  '9f192130-0000-4000-8000-000000000402'::uuid,
  'exact retained scalar row is promoted instead of replaced'
);
select is(
  (
    select context_link.added_by
    from public.conversation_contexts context_link
    where context_link.id = '9f192130-0000-4000-8000-000000000402'
  ),
  '9f192130-0000-4000-8000-000000000091'::uuid,
  'promotion preserves the original context actor'
);
select is(
  (
    select context_link.added_at
    from public.conversation_contexts context_link
    where context_link.id = '9f192130-0000-4000-8000-000000000402'
  ),
  '2026-01-01 09:00:02+00'::timestamptz,
  'promotion preserves the original context timestamp'
);
select is(
  (
    select context_link.added_by
    from public.conversation_contexts context_link
    where context_link.conversation_id =
      '9f192130-0000-4000-8000-000000000303'
      and context_link.is_primary
  ),
  null,
  'scalar-only repair appends a primary row without inventing an actor'
);
select is(
  (
    select count(*)::integer
    from public.conversation_contexts context_link
    where context_link.conversation_id =
      '9f192130-0000-4000-8000-000000000304'
      and context_link.is_primary
  ),
  0,
  'cleared scalar does not promote arbitrary non-primary history'
);
select is(
  (
    select conversation.context_type
    from public.conversations conversation
    where conversation.id = '9f192130-0000-4000-8000-000000000304'
  ),
  null,
  'cleared scalar remains cleared when only non-primary history exists'
);
select results_eq(
  $$
    select
      conversation.context_type,
      conversation.context_id,
      count(context_link.id)::integer
    from public.conversations conversation
    left join public.conversation_contexts context_link
      on context_link.conversation_id = conversation.id
     and context_link.is_primary
    where conversation.id = '9f192130-0000-4000-8000-000000000307'
    group by conversation.context_type, conversation.context_id
  $$,
  $$values (null::text, null::uuid, 0::integer)$$,
  'dangling scalar is cleared without fabricating a primary context row'
);
select is(
  (
    select count(*)::integer
    from public.messaging_context_projection_reconciliation_audit audit
    where audit.conversation_id =
      '9f192130-0000-4000-8000-000000000307'
      and audit.tenant_id = '9f192130-0000-4000-8000-000000000001'
      and audit.context_type = 'job'
      and audit.context_id = '9f192130-0000-4000-8000-000000000999'
      and audit.reason = 'scalar_context_target_missing'
      and audit.action = 'cleared_dangling_scalar'
      and audit.target_presence = 'missing_all_tenants'
      and audit.primary_count_snapshot = 0
      and audit.original_updated_at = '2026-01-01 10:00:07+00'
      and audit.migration_version = '20260719213000'
  ),
  1,
  'dangling repair retains the exact scalar and repair-decision snapshot'
);
select is(
  (
    select audit.evidence_fingerprint
    from public.messaging_context_projection_reconciliation_audit audit
    where audit.conversation_id =
      '9f192130-0000-4000-8000-000000000307'
  ),
  encode(extensions.digest(convert_to(concat_ws(
      '|',
      '20260719213000',
      '9f192130-0000-4000-8000-000000000001',
      '9f192130-0000-4000-8000-000000000307',
      'job',
      '9f192130-0000-4000-8000-000000000999',
      'scalar_context_target_missing',
      'cleared_dangling_scalar',
      'missing_all_tenants',
      '0'
    ), 'UTF8'), 'sha256'), 'hex'),
  'audit evidence uses the exact deterministic SHA-256 fingerprint'
);
select set_config(
  'test.context_projection.audit_recorded_at',
  (
    select audit.recorded_at::text
    from public.messaging_context_projection_reconciliation_audit audit
    where audit.conversation_id =
      '9f192130-0000-4000-8000-000000000307'
  ),
  true
);
set local role authenticated;
select throws_ok(
  $$select count(*)
    from public.messaging_context_projection_reconciliation_audit$$,
  '42501',
  'permission denied for table messaging_context_projection_reconciliation_audit',
  'authenticated caller cannot inspect dangling reconciliation evidence'
);
select throws_ok(
  $$select public.set_config(
      'app.messaging_context_projection_reconciliation',
      '20260719213000',
      true
    )$$,
  '42501',
  'permission denied for function set_config',
  'authenticated caller cannot mint the audit RLS capability'
);
select lives_ok(
  $$select pg_catalog.set_config(
      'app.messaging_context_projection_reconciliation',
      '20260719213000',
      true
    )$$,
  'authenticated caller may set a custom session GUC but gains no owner policy'
);
select throws_ok(
  $$insert into public.messaging_context_projection_reconciliation_audit (
      evidence_fingerprint,
      tenant_id,
      conversation_id,
      context_type,
      context_id,
      reason,
      action,
      target_presence,
      primary_count_snapshot,
      migration_version
    ) values (
      repeat('a', 64),
      '9f192130-0000-4000-8000-000000000001',
      '9f192130-0000-4000-8000-000000000307',
      'job',
      '9f192130-0000-4000-8000-000000000999',
      'scalar_context_target_missing',
      'cleared_dangling_scalar',
      'missing_all_tenants',
      0,
      '20260719213000'
    )$$,
  '42501',
  'permission denied for table messaging_context_projection_reconciliation_audit',
  'authenticated caller cannot satisfy owner policy by setting the raw GUC'
);
select pg_catalog.set_config(
  'app.messaging_context_projection_reconciliation',
  '',
  true
);
reset role;
set local role service_role;
select is(
  (
    select count(*)::integer
    from public.messaging_context_projection_reconciliation_audit audit
    where audit.conversation_id =
      '9f192130-0000-4000-8000-000000000307'
  ),
  1,
  'service role can inspect immutable dangling reconciliation evidence'
);
select throws_ok(
  $$insert into public.messaging_context_projection_reconciliation_audit (
      evidence_fingerprint,
      tenant_id,
      conversation_id,
      context_type,
      context_id,
      reason,
      action,
      target_presence,
      primary_count_snapshot,
      migration_version
    ) values (
      repeat('0', 64),
      '9f192130-0000-4000-8000-000000000001',
      '9f192130-0000-4000-8000-000000000307',
      'job',
      '9f192130-0000-4000-8000-000000000999',
      'scalar_context_target_missing',
      'cleared_dangling_scalar',
      'missing_all_tenants',
      0,
      '20260719213000'
    )$$,
  '42501',
  'permission denied for table messaging_context_projection_reconciliation_audit',
  'service role cannot forge reconciliation evidence'
);
reset role;
select results_eq(
  $$
    select conversation.id, conversation.updated_at
    from public.conversations conversation
    where conversation.id in (
      '9f192130-0000-4000-8000-000000000301',
      '9f192130-0000-4000-8000-000000000302',
      '9f192130-0000-4000-8000-000000000303',
      '9f192130-0000-4000-8000-000000000304',
      '9f192130-0000-4000-8000-000000000307'
    )
    order by conversation.id
  $$,
  $$values
    (
      '9f192130-0000-4000-8000-000000000301'::uuid,
      '2026-01-01 10:00:01+00'::timestamptz
    ),
    (
      '9f192130-0000-4000-8000-000000000302'::uuid,
      '2026-01-01 10:00:02+00'::timestamptz
    ),
    (
      '9f192130-0000-4000-8000-000000000303'::uuid,
      null::timestamptz
    ),
    (
      '9f192130-0000-4000-8000-000000000304'::uuid,
      '2026-01-01 10:00:04+00'::timestamptz
    ),
    (
      '9f192130-0000-4000-8000-000000000307'::uuid,
      '2026-01-01 10:00:07+00'::timestamptz
    )
  $$,
  'reconciliation preserves every conversation updated_at exactly'
);
select is(
  public.reconcile_conversation_context_projections(),
  0,
  'reapplying reconciliation to a valid graph is a no-op'
);
select is(
  (
    select count(*)::integer
    from public.messaging_context_projection_reconciliation_audit audit
    where audit.conversation_id =
      '9f192130-0000-4000-8000-000000000307'
  ),
  1,
  'reapplying reconciliation cannot duplicate dangling audit evidence'
);
select is(
  (
    select audit.recorded_at
    from public.messaging_context_projection_reconciliation_audit audit
    where audit.conversation_id =
      '9f192130-0000-4000-8000-000000000307'
  ),
  current_setting(
    'test.context_projection.audit_recorded_at'
  )::timestamptz,
  'reapplying reconciliation cannot rewrite the original audit timestamp'
);
select throws_ok(
  $$update public.messaging_context_projection_reconciliation_audit
    set reason = 'attempted_rewrite'
    where conversation_id =
      '9f192130-0000-4000-8000-000000000307'$$,
  '23514',
  'Messaging context projection reconciliation audit is immutable',
  'even the table owner cannot update reconciliation evidence'
);
select throws_ok(
  $$delete from public.messaging_context_projection_reconciliation_audit
    where conversation_id =
      '9f192130-0000-4000-8000-000000000307'$$,
  '23514',
  'Messaging context projection reconciliation audit is immutable',
  'even the table owner cannot delete reconciliation evidence'
);
select throws_ok(
  $$truncate table public.messaging_context_projection_reconciliation_audit$$,
  '23514',
  'Messaging context projection reconciliation audit is immutable',
  'even the table owner cannot truncate reconciliation evidence'
);
delete from public.conversations
where id = '9f192130-0000-4000-8000-000000000307';
set constraints all immediate;
set constraints all deferred;
select is(
  (
    select count(*)::integer
    from public.messaging_context_projection_reconciliation_audit audit
    where audit.conversation_id =
      '9f192130-0000-4000-8000-000000000307'
  ),
  1,
  'audit UUID snapshot survives deletion of the repaired conversation'
);

-- Capability incompatibility is a malformed relationship even when its target
-- is gone. Build that legacy shape without the modern guards, then prove the
-- repair aborts before it archives or mutates anything.
alter table public.conversations
  disable trigger trg_conversations_counterparty_guard;
alter table public.conversations
  disable trigger trg_conversations_context_projection_commit;
insert into public.conversations (
  id,
  tenant_id,
  type,
  channel,
  counterparty_type,
  status,
  created_by,
  context_type,
  context_id,
  updated_at
) values (
  '9f192130-0000-4000-8000-000000000308',
  '9f192130-0000-4000-8000-000000000001',
  'support',
  'website_portal',
  'customer',
  'active',
  null,
  'supplier',
  '9f192130-0000-4000-8000-000000000998',
  '2026-01-01 10:00:08+00'
);
alter table public.conversations
  enable trigger trg_conversations_context_projection_commit;
alter table public.conversations
  enable trigger trg_conversations_counterparty_guard;

select throws_ok(
  $$select public.reconcile_conversation_context_projections()$$,
  '23514',
  'Cannot reconcile a capability-incompatible scalar conversation context',
  'capability mismatch aborts even when the referenced target is missing'
);
select results_eq(
  $$
    select
      conversation.context_type,
      conversation.context_id,
      conversation.updated_at
    from public.conversations conversation
    where conversation.id = '9f192130-0000-4000-8000-000000000308'
  $$,
  $$values (
    'supplier'::text,
    '9f192130-0000-4000-8000-000000000998'::uuid,
    '2026-01-01 10:00:08+00'::timestamptz
  )$$,
  'failed capability reconciliation leaves the malformed scalar untouched'
);
select is(
  (
    select count(*)::integer
    from public.messaging_context_projection_reconciliation_audit audit
    where audit.conversation_id = '9f192130-0000-4000-8000-000000000308'
  ),
  0,
  'failed capability reconciliation emits no dangling-history audit'
);
update public.conversations
set context_type = null,
    context_id = null
where id = '9f192130-0000-4000-8000-000000000308';
set constraints all immediate;
set constraints all deferred;

-- An otherwise compatible context that resolves under another tenant is a
-- security defect, not deleted history. It must fail with no partial writes.
insert into public.conversations (
  id,
  tenant_id,
  type,
  channel,
  counterparty_type,
  status,
  created_by,
  context_type,
  context_id,
  updated_at
) values (
  '9f192130-0000-4000-8000-000000000309',
  '9f192130-0000-4000-8000-000000000001',
  'support',
  'website_portal',
  'customer',
  'active',
  null,
  'customer',
  '9f192130-0000-4000-8000-000000000113',
  '2026-01-01 10:00:09+00'
);

select throws_ok(
  $$select public.reconcile_conversation_context_projections()$$,
  '23514',
  'Cannot reconcile a cross-tenant scalar conversation context',
  'cross-tenant scalar reconciliation aborts instead of archiving the link'
);
select results_eq(
  $$
    select
      conversation.context_type,
      conversation.context_id,
      conversation.updated_at
    from public.conversations conversation
    where conversation.id = '9f192130-0000-4000-8000-000000000309'
  $$,
  $$values (
    'customer'::text,
    '9f192130-0000-4000-8000-000000000113'::uuid,
    '2026-01-01 10:00:09+00'::timestamptz
  )$$,
  'failed cross-tenant reconciliation leaves the scalar and timestamp untouched'
);
select is(
  (
    select count(*)::integer
    from public.messaging_context_projection_reconciliation_audit audit
    where audit.conversation_id = '9f192130-0000-4000-8000-000000000309'
  ),
  0,
  'failed cross-tenant reconciliation emits no audit or partial repair evidence'
);
update public.conversations
set context_type = null,
    context_id = null
where id = '9f192130-0000-4000-8000-000000000309';
set constraints all immediate;
set constraints all deferred;

insert into public.conversations (
  id,
  tenant_id,
  type,
  channel,
  counterparty_type,
  status,
  created_by
) values (
  '9f192130-0000-4000-8000-000000000305',
  '9f192130-0000-4000-8000-000000000001',
  'support',
  'website_portal',
  'customer',
  'active',
  null
);

select throws_ok(
  $$
    do $unilateral$
    begin
      update public.conversations
      set context_type = 'customer',
          context_id = '9f192130-0000-4000-8000-000000000111'
      where id = '9f192130-0000-4000-8000-000000000305';
      set constraints all immediate;
    end;
    $unilateral$
  $$,
  '23514',
  'Conversation context projection must match exactly one primary ledger row',
  'unilateral scalar write fails when deferred constraints are forced'
);
set constraints all deferred;

select throws_ok(
  $$
    do $partial$
    begin
      update public.conversations
      set context_type = 'customer',
          context_id = null
      where id = '9f192130-0000-4000-8000-000000000305';
      set constraints all immediate;
    end;
    $partial$
  $$,
  '23514',
  'Conversation context type and id must be set together',
  'partial scalar pair fails at the deferred invariant boundary'
);
set constraints all deferred;

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',
    '9f192130-0000-4000-8000-000000000091',
    'role',
    'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9f192130-0000-4000-8000-000000000091',
  true
);
set local role authenticated;
select lives_ok(
  $$
    do $atomic_context$
    begin
      perform public.set_conversation_primary_context(
        '9f192130-0000-4000-8000-000000000305',
        'customer',
        '9f192130-0000-4000-8000-000000000111'
      );
      set constraints all immediate;
      set constraints all deferred;
    end;
    $atomic_context$
  $$,
  'canonical primary-context RPC satisfies the commit-time invariant'
);
reset role;

insert into public.conversations (
  id,
  tenant_id,
  type,
  channel,
  counterparty_type,
  status,
  created_by,
  context_type,
  context_id
) values (
  '9f192130-0000-4000-8000-000000000306',
  '9f192130-0000-4000-8000-000000000001',
  'support',
  'website_portal',
  'customer',
  'active',
  null,
  'customer',
  '9f192130-0000-4000-8000-000000000111'
);
insert into public.conversation_contexts (
  conversation_id,
  context_type,
  context_id,
  is_primary,
  tenant_id
) values (
  '9f192130-0000-4000-8000-000000000306',
  'customer',
  '9f192130-0000-4000-8000-000000000111',
  true,
  '9f192130-0000-4000-8000-000000000001'
);
select lives_ok(
  $$
    do $cascade$
    begin
      delete from public.conversations
      where id = '9f192130-0000-4000-8000-000000000306';
      set constraints all immediate;
      set constraints all deferred;
    end;
    $cascade$
  $$,
  'conversation cascade delete leaves no deferred projection failure'
);

select is(
  (
    select count(*)::integer
    from public.conversations conversation
    where (conversation.context_type is null)
        is distinct from (conversation.context_id is null)
  ),
  0,
  'global invariant contains no partial scalar context pair'
);
select is(
  (
    select count(*)::integer
    from public.conversations conversation
    left join public.conversation_contexts primary_context
      on primary_context.conversation_id = conversation.id
     and primary_context.is_primary
    where (
      conversation.context_type is null
      and primary_context.id is not null
    )
    or (
      conversation.context_type is not null
      and (
        primary_context.id is null
        or primary_context.tenant_id is distinct from conversation.tenant_id
        or primary_context.context_type is distinct from conversation.context_type
        or primary_context.context_id is distinct from conversation.context_id
      )
    )
  ),
  0,
  'global invariant has exact scalar and primary ledger equivalence'
);

select * from finish();
rollback;
