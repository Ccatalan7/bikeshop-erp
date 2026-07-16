-- Deployment status: DEPLOYED to production project
-- xzdvtzdqjeyqxnkqprtf on 2026-07-16; verified with zero incomplete trace
-- roots and unchanged stock, payment, and journal totals.
-- Purpose:
--   Preserve the canonical inventory/accounting trace identity across nested
--   invoice/payment triggers and multi-row statements. PostgreSQL queues
--   AFTER-row triggers until every BEFORE-row trigger in the statement has
--   run, so one transaction-local "current operation" value is insufficient.
--
--   Each traced row now owns a transaction-local context frame. UPDATE/DELETE
--   push before the canonical begin trigger and reactivate before business
--   AFTER triggers. INSERT starts entirely in the earliest AFTER-trigger block
--   so ON CONFLICT DO NOTHING creates no orphan frame/root and ON CONFLICT DO
--   UPDATE creates only the UPDATE root. Every path restores its real parent
--   after canonical completion.
--
--   The historical repair at the end closes exactly three QA roots from
--   transaction 832950 only when every immutable identity/snapshot/graph
--   fingerprint still matches. It never replays inventory or accounting.
--   Misattached journal checkpoints remain append-only evidence and receive
--   explicit reconciliation warnings instead of mutation or deletion.
--
-- Forward recovery:
--   Do not remove the frame triggers while the trace kernel uses transaction-
--   local GUCs. A future replacement should pass an explicit operation id
--   through every command. Historical warning checkpoints are immutable.

begin;

create or replace function public.current_inventory_accounting_trace_context()
returns jsonb
language sql
volatile
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'operation_id', nullif(current_setting('app.inventory_operation_id', true), ''),
    'source_document_type', nullif(current_setting('app.inventory_source_document_type', true), ''),
    'source_document_id', nullif(current_setting('app.inventory_source_document_id', true), ''),
    'source_channel', nullif(current_setting('app.inventory_source_channel', true), '')
  );
$$;

revoke all on function public.current_inventory_accounting_trace_context()
  from public, anon, authenticated, service_role;

create or replace function public.set_inventory_accounting_trace_context(
  p_context jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform set_config(
    'app.inventory_operation_id',
    coalesce(p_context->>'operation_id', ''),
    true
  );
  perform set_config(
    'app.inventory_source_document_type',
    coalesce(p_context->>'source_document_type', ''),
    true
  );
  perform set_config(
    'app.inventory_source_document_id',
    coalesce(p_context->>'source_document_id', ''),
    true
  );
  perform set_config(
    'app.inventory_source_channel',
    coalesce(p_context->>'source_channel', ''),
    true
  );
end;
$$;

revoke all on function public.set_inventory_accounting_trace_context(jsonb)
  from public, anon, authenticated, service_role;

create or replace function public.push_inventory_accounting_trace_context_frame()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_stack jsonb;
  v_row jsonb;
  v_current_context jsonb;
  v_parent_context jsonb;
  v_sibling_parent jsonb;
  v_frame_id uuid := gen_random_uuid();
  v_table text := TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME;
  v_tenant_id uuid;
  v_document_id uuid;
begin
  begin
    v_stack := coalesce(
      nullif(current_setting('app.inventory_trace_context_stack', true), ''),
      '[]'
    )::jsonb;
  exception
    when others then
      raise exception 'Canonical trace context stack is not valid JSON'
        using errcode = 'data_exception';
  end;

  if jsonb_typeof(v_stack) <> 'array' then
    raise exception 'Canonical trace context stack must be a JSON array'
      using errcode = 'data_exception';
  end if;

  -- Keep the JSON queue's O(n) row matching bounded. Ordinary INSERT never
  -- accumulates sibling frames because it begins in AFTER. This ceiling only
  -- affects an exceptional UPDATE/DELETE statement touching more than 512
  -- traced invoice/payment rows in one transaction nesting level; such a bulk
  -- rewrite must be chunked so audit identity remains reviewable.
  if jsonb_array_length(v_stack) >= 512 then
    raise exception 'Canonical trace context frame limit (512) exceeded; chunk the invoice/payment update'
      using errcode = 'program_limit_exceeded';
  end if;

  v_row := case when TG_OP = 'DELETE' then to_jsonb(OLD) else to_jsonb(NEW) end;
  v_tenant_id := nullif(v_row->>'tenant_id', '')::uuid;
  v_document_id := nullif(v_row->>'id', '')::uuid;
  if v_tenant_id is null or v_document_id is null then
    raise exception 'Canonical trace context frame requires tenant_id and document id';
  end if;

  v_current_context := public.current_inventory_accounting_trace_context();
  v_parent_context := v_current_context;

  -- BEFORE triggers for every row run before any AFTER-row trigger in a
  -- multi-row statement. A previous unresolved frame at the same table and
  -- trigger depth is therefore a sibling, not this row's parent.
  select frame->'parent_context'
    into v_sibling_parent
    from jsonb_array_elements(v_stack) with ordinality queued(frame, position)
   where frame->>'table' = v_table
     and (frame->>'trigger_depth')::integer = pg_trigger_depth()
     and frame->>'transaction_id' = txid_current()::text
     and frame->>'state' in ('awaiting_capture', 'queued', 'active')
   order by position desc
   limit 1;

  if found then
    v_parent_context := coalesce(v_sibling_parent, '{}'::jsonb);
  end if;

  v_stack := v_stack || jsonb_build_array(jsonb_build_object(
    'frame_id', v_frame_id,
    'table', v_table,
    'trigger_operation', lower(TG_OP),
    'tenant_id', v_tenant_id,
    'document_id', v_document_id,
    'trigger_depth', pg_trigger_depth(),
    'transaction_id', txid_current()::text,
    'state', 'awaiting_capture',
    'parent_context', v_parent_context
  ));

  perform set_config('app.inventory_trace_context_stack', v_stack::text, true);
  perform set_config('app.inventory_trace_capture_frame_id', v_frame_id::text, true);
  perform public.set_inventory_accounting_trace_context(v_parent_context);
  return case when TG_OP = 'DELETE' then OLD else NEW end;
end;
$$;

revoke all on function public.push_inventory_accounting_trace_context_frame()
  from public, anon, authenticated, service_role;

create or replace function public.capture_inventory_accounting_trace_context_frame()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_stack jsonb;
  v_frame_id text;
  v_index integer;
  v_frame jsonb;
  v_row jsonb;
begin
  v_stack := coalesce(
    nullif(current_setting('app.inventory_trace_context_stack', true), ''),
    '[]'
  )::jsonb;
  v_frame_id := nullif(
    current_setting('app.inventory_trace_capture_frame_id', true),
    ''
  );
  v_row := case when TG_OP = 'DELETE' then to_jsonb(OLD) else to_jsonb(NEW) end;

  select (position - 1)::integer, frame
    into v_index, v_frame
    from jsonb_array_elements(v_stack) with ordinality queued(frame, position)
   where frame->>'frame_id' = v_frame_id
   limit 1;

  if v_index is null
     or v_frame->>'state' <> 'awaiting_capture'
     or v_frame->>'table' <> TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME
     or v_frame->>'trigger_operation' <> lower(TG_OP)
     or v_frame->>'tenant_id' <> v_row->>'tenant_id'
     or v_frame->>'document_id' <> v_row->>'id'
     or (v_frame->>'trigger_depth')::integer <> pg_trigger_depth() then
    raise exception 'Canonical trace context capture frame mismatch for %.% % %',
      TG_TABLE_SCHEMA, TG_TABLE_NAME, TG_OP, v_row->>'id'
      using errcode = 'data_exception';
  end if;

  v_frame := v_frame || jsonb_build_object(
    'state', 'queued',
    'child_context', public.current_inventory_accounting_trace_context()
  );
  v_stack := jsonb_set(v_stack, array[v_index::text], v_frame, false);
  perform set_config('app.inventory_trace_context_stack', v_stack::text, true);
  perform set_config('app.inventory_trace_capture_frame_id', '', true);
  return case when TG_OP = 'DELETE' then OLD else NEW end;
end;
$$;

revoke all on function public.capture_inventory_accounting_trace_context_frame()
  from public, anon, authenticated, service_role;

create or replace function public.activate_inventory_accounting_trace_context_frame()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_stack jsonb;
  v_index integer;
  v_frame jsonb;
  v_row jsonb;
  v_expected_document_type text;
  v_child_operation public.inventory_accounting_operations%rowtype;
  v_reused_parent boolean := false;
begin
  v_stack := coalesce(
    nullif(current_setting('app.inventory_trace_context_stack', true), ''),
    '[]'
  )::jsonb;
  v_row := case when TG_OP = 'DELETE' then to_jsonb(OLD) else to_jsonb(NEW) end;

  select (position - 1)::integer, frame
    into v_index, v_frame
    from jsonb_array_elements(v_stack) with ordinality queued(frame, position)
   where frame->>'state' = 'queued'
     and frame->>'table' = TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME
     and frame->>'trigger_operation' = lower(TG_OP)
     and frame->>'tenant_id' = v_row->>'tenant_id'
     and frame->>'document_id' = v_row->>'id'
     and (frame->>'trigger_depth')::integer = pg_trigger_depth()
     and frame->>'transaction_id' = txid_current()::text
   order by position
   limit 1;

  if v_index is null then
    raise exception 'Canonical trace context activation frame missing for %.% % %',
      TG_TABLE_SCHEMA, TG_TABLE_NAME, TG_OP, v_row->>'id'
      using errcode = 'data_exception';
  end if;

  v_expected_document_type := case TG_TABLE_NAME
    when 'sales_invoices' then 'sales_invoice'
    when 'purchase_invoices' then 'purchase_invoice'
    when 'sales_payments' then 'sales_payment'
    when 'purchase_payments' then 'purchase_payment'
    else null
  end;
  v_reused_parent := TG_TABLE_NAME in ('sales_invoices', 'purchase_invoices')
    and pg_trigger_depth() > 1
    and v_frame->'child_context'->>'operation_id' is not distinct from
          v_frame->'parent_context'->>'operation_id';

  -- Payment completion historically trusted the current GUC without checking
  -- its row identity. Validate every newly-created child before exposing it to
  -- business AFTER triggers; a future context regression now aborts the whole
  -- DML instead of completing or checkpointing the wrong operation.
  if not v_reused_parent then
    if v_expected_document_type is null
       or nullif(v_frame->'child_context'->>'operation_id', '') is null then
      raise exception 'Canonical trace child context missing for %.% % %',
        TG_TABLE_SCHEMA, TG_TABLE_NAME, TG_OP, v_row->>'id'
        using errcode = 'data_exception';
    end if;

    select *
      into v_child_operation
      from public.inventory_accounting_operations operation
     where operation.id = (v_frame->'child_context'->>'operation_id')::uuid;

    if not found
       or v_child_operation.tenant_id::text is distinct from v_row->>'tenant_id'
       or v_child_operation.document_type is distinct from v_expected_document_type
       or v_child_operation.document_id::text is distinct from v_row->>'id'
       or v_child_operation.action is distinct from lower(TG_OP)
       or v_child_operation.outcome is distinct from 'started'
       or v_child_operation.context->>'table'
            is distinct from TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME then
      raise exception 'Canonical trace child identity mismatch for %.% % %',
        TG_TABLE_SCHEMA, TG_TABLE_NAME, TG_OP, v_row->>'id'
        using errcode = 'data_exception';
    end if;
  end if;

  v_frame := v_frame || jsonb_build_object('state', 'active');
  v_stack := jsonb_set(v_stack, array[v_index::text], v_frame, false);
  perform set_config('app.inventory_trace_context_stack', v_stack::text, true);
  perform public.set_inventory_accounting_trace_context(v_frame->'child_context');
  return case when TG_OP = 'DELETE' then OLD else NEW end;
end;
$$;

revoke all on function public.activate_inventory_accounting_trace_context_frame()
  from public, anon, authenticated, service_role;

create or replace function public.restore_inventory_accounting_trace_context_frame()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_stack jsonb;
  v_index integer;
  v_frame jsonb;
  v_row jsonb;
  v_deferred_nested_invoice boolean := false;
begin
  v_stack := coalesce(
    nullif(current_setting('app.inventory_trace_context_stack', true), ''),
    '[]'
  )::jsonb;
  v_row := case when TG_OP = 'DELETE' then to_jsonb(OLD) else to_jsonb(NEW) end;

  select (position - 1)::integer, frame
    into v_index, v_frame
    from jsonb_array_elements(v_stack) with ordinality queued(frame, position)
   where frame->>'state' = 'active'
     and frame->>'table' = TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME
     and frame->>'trigger_operation' = lower(TG_OP)
     and frame->>'tenant_id' = v_row->>'tenant_id'
     and frame->>'document_id' = v_row->>'id'
     and (frame->>'trigger_depth')::integer = pg_trigger_depth()
     and frame->>'transaction_id' = txid_current()::text
   order by position desc
   limit 1;

  if v_index is null then
    raise exception 'Canonical trace context restore frame missing for %.% % %',
      TG_TABLE_SCHEMA, TG_TABLE_NAME, TG_OP, v_row->>'id'
      using errcode = 'data_exception';
  end if;

  -- Covered-warranty lifecycle commands intentionally perform invoice-owned
  -- stock/journal writers after a nested invoice UPDATE returns, then complete
  -- and clear that nested invoice root themselves. Preserve that pre-existing
  -- contract when begin created a new nested invoice root with no active
  -- parent. Reused parent contexts still restore normally.
  if pg_trigger_depth() > 1
     and TG_TABLE_NAME in ('sales_invoices', 'purchase_invoices')
     and v_frame->'child_context'->>'operation_id' is distinct from
           v_frame->'parent_context'->>'operation_id'
     and nullif(v_frame->'child_context'->>'operation_id', '') is not null then
    select exists (
      select 1
        from public.inventory_accounting_operations operation
       where operation.id = (v_frame->'child_context'->>'operation_id')::uuid
         and operation.tenant_id = (v_frame->>'tenant_id')::uuid
         and operation.document_id = (v_frame->>'document_id')::uuid
         and operation.document_type = case TG_TABLE_NAME
           when 'sales_invoices' then 'sales_invoice'
           else 'purchase_invoice'
         end
         and operation.outcome = 'started'
    ) into v_deferred_nested_invoice;
  end if;

  perform public.set_inventory_accounting_trace_context(
    case
      when v_deferred_nested_invoice then v_frame->'child_context'
      else v_frame->'parent_context'
    end
  );
  v_stack := v_stack - v_index;
  perform set_config('app.inventory_trace_context_stack', v_stack::text, true);
  return case when TG_OP = 'DELETE' then OLD else NEW end;
end;
$$;

revoke all on function public.restore_inventory_accounting_trace_context_frame()
  from public, anon, authenticated, service_role;

-- Trigger ordering is part of the contract. PostgreSQL orders triggers with
-- the same timing/event alphabetically.
do $$
declare
  v_table regclass;
  v_suffix text;
begin
  foreach v_table in array array[
    'public.sales_invoices'::regclass,
    'public.purchase_invoices'::regclass,
    'public.sales_payments'::regclass,
    'public.purchase_payments'::regclass
  ] loop
    v_suffix := replace(v_table::text, 'public.', '');

    execute format('drop trigger if exists %I on %s',
      'zy_inventory_trace_push_' || v_suffix, v_table);
    execute format(
      'create trigger %I before update or delete on %s for each row execute function public.push_inventory_accounting_trace_context_frame()',
      'zy_inventory_trace_push_' || v_suffix, v_table
    );

    execute format('drop trigger if exists %I on %s',
      'zza_inventory_trace_capture_' || v_suffix, v_table);
    execute format(
      'create trigger %I before update or delete on %s for each row execute function public.capture_inventory_accounting_trace_context_frame()',
      'zza_inventory_trace_capture_' || v_suffix, v_table
    );

    -- INSERT tracing must not run in BEFORE: ON CONFLICT DO NOTHING has no
    -- matching AFTER INSERT, and DO UPDATE would otherwise create both insert
    -- and update roots. These three triggers run first in the successful
    -- INSERT AFTER chain, before activation and all business effects.
    execute format('drop trigger if exists %I on %s',
      'a0_inventory_trace_push_insert_' || v_suffix, v_table);
    execute format(
      'create trigger %I after insert on %s for each row execute function public.push_inventory_accounting_trace_context_frame()',
      'a0_inventory_trace_push_insert_' || v_suffix, v_table
    );

    execute format('drop trigger if exists %I on %s',
      'a1_inventory_trace_begin_insert_' || v_suffix, v_table);
    execute format(
      'create trigger %I after insert on %s for each row execute function public.%I()',
      'a1_inventory_trace_begin_insert_' || v_suffix,
      v_table,
      case
        when v_suffix in ('sales_invoices', 'purchase_invoices')
          then 'begin_invoice_inventory_accounting_trace'
        else 'begin_invoice_payment_trace'
      end
    );

    execute format('drop trigger if exists %I on %s',
      'a2_inventory_trace_capture_insert_' || v_suffix, v_table);
    execute format(
      'create trigger %I after insert on %s for each row execute function public.capture_inventory_accounting_trace_context_frame()',
      'a2_inventory_trace_capture_insert_' || v_suffix, v_table
    );

    execute format('drop trigger if exists %I on %s',
      'aa_inventory_trace_activate_' || v_suffix, v_table);
    execute format(
      'create trigger %I after insert or update or delete on %s for each row execute function public.activate_inventory_accounting_trace_context_frame()',
      'aa_inventory_trace_activate_' || v_suffix, v_table
    );

    execute format('drop trigger if exists %I on %s',
      'zzzz_inventory_trace_restore_' || v_suffix, v_table);
    execute format(
      'create trigger %I after insert or update or delete on %s for each row execute function public.restore_inventory_accounting_trace_context_frame()',
      'zzzz_inventory_trace_restore_' || v_suffix, v_table
    );
  end loop;
end;
$$;

-- The historical begin triggers remain canonical for UPDATE/DELETE only.
-- Successful INSERT uses the a1 AFTER trigger above.
drop trigger if exists zz_inventory_trace_begin_sales_invoice
  on public.sales_invoices;
create trigger zz_inventory_trace_begin_sales_invoice
  before update or delete on public.sales_invoices
  for each row execute function public.begin_invoice_inventory_accounting_trace();

drop trigger if exists zz_inventory_trace_begin_purchase_invoice
  on public.purchase_invoices;
create trigger zz_inventory_trace_begin_purchase_invoice
  before update or delete on public.purchase_invoices
  for each row execute function public.begin_invoice_inventory_accounting_trace();

drop trigger if exists zz_inventory_trace_begin_sales_payment
  on public.sales_payments;
create trigger zz_inventory_trace_begin_sales_payment
  before update or delete on public.sales_payments
  for each row execute function public.begin_invoice_payment_trace();

drop trigger if exists zz_inventory_trace_begin_purchase_payment
  on public.purchase_payments;
create trigger zz_inventory_trace_begin_purchase_payment
  before update or delete on public.purchase_payments
  for each row execute function public.begin_invoice_payment_trace();

-- -------------------------------------------------------------------------
-- Strictly guarded append-only repair for QA transaction 832950.
-- -------------------------------------------------------------------------

-- All-or-none, read-only gate. No repair loop below may start if only a subset
-- of the three QA roots exists, if outcomes are mixed, or if any frozen root /
-- completed sibling identity has drifted. Fresh databases have none and pass
-- inertly; a replayed repair must have all three completed roots plus evidence.
do $$
declare
  v_present integer;
  v_started integer;
  v_completed integer;
  v_expected_matches integer;
  v_sibling_matches integer;
  v_repaired integer;
begin
  select
    count(*)::integer,
    count(*) filter (where outcome = 'started')::integer,
    count(*) filter (where outcome = 'completed')::integer
    into v_present, v_started, v_completed
    from public.inventory_accounting_operations
   where id in (
     '7970e3f0-1716-4aaf-a577-f40319037f20'::uuid,
     'dbb8711b-1f6d-4ce2-9954-7fceb7553eea'::uuid,
     'e3b6e284-7ac2-4a2d-a4f3-3fbede41b60e'::uuid
   );

  if v_present = 0 then
    return;
  end if;
  if v_present <> 3 or not (
    (v_started = 3 and v_completed = 0)
    or (v_started = 0 and v_completed = 3)
  ) then
    raise exception 'QA trace repair requires all three roots in one uniform started/completed state';
  end if;

  with expected(
    root_id, operation_key, invoice_id, old_status, before_hash, after_hash
  ) as (
    values
      (
        '7970e3f0-1716-4aaf-a577-f40319037f20'::uuid,
        'sales_invoice:a4bcd142-73d0-4cb9-9654-8617992ad887:update:08e9765c-2bbc-438e-b0aa-71e30d55bd34'::text,
        'a4bcd142-73d0-4cb9-9654-8617992ad887'::uuid,
        'paid'::text,
        '0d0495431b5a32291d783c645427c6af'::text,
        '9504deab381af3b3082095a0872adcc7'::text
      ),
      (
        'dbb8711b-1f6d-4ce2-9954-7fceb7553eea'::uuid,
        'sales_invoice:bfe72331-3bd3-491f-8a2a-0f09add92e23:update:9792dfb2-438d-4f26-9ca2-1aa1d4447990'::text,
        'bfe72331-3bd3-491f-8a2a-0f09add92e23'::uuid,
        'draft'::text,
        'a6f661ea2f3d6d1bef4955edc685c9e5'::text,
        '18988d272d3ff40c3610a814b5099f8b'::text
      ),
      (
        'e3b6e284-7ac2-4a2d-a4f3-3fbede41b60e'::uuid,
        'sales_invoice:f28607ef-19a5-4ec1-8df1-bef01635fd66:update:e1a59b66-e516-4169-9e63-f82ded6ac746'::text,
        'f28607ef-19a5-4ec1-8df1-bef01635fd66'::uuid,
        'draft'::text,
        'e8a05563d04913222f93fd6ec90f9e08'::text,
        '19672f3c9fde674f2aa775c86a75ea87'::text
      )
  )
  select count(*)::integer
    into v_expected_matches
    from expected
    join public.inventory_accounting_operations operation
      on operation.id = expected.root_id
   where operation.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'::uuid
     and operation.operation_key = expected.operation_key
     and operation.source_channel = 'mechanic_job'
     and operation.action = 'update'
     and operation.document_type = 'sales_invoice'
     and operation.document_id = expected.invoice_id
     and operation.actor_id is null
     and operation.executor = 'database_trigger'
     and operation.old_status = expected.old_status
     and operation.new_status = 'cancelled'
     and md5(operation.before_snapshot::text) = expected.before_hash
     and md5(operation.after_snapshot::text) = expected.after_hash
     and operation.context->>'table' = 'public.sales_invoices'
     and operation.context->>'trigger_depth' = '1'
     and operation.context->>'transaction_id' = '832950'
     and operation.context->>'before_hash' = expected.before_hash
     and operation.context->>'after_hash' = expected.after_hash
     and operation.error_code is null
     and operation.error_message is null;

  if v_expected_matches <> 3 then
    raise exception 'QA trace repair all-or-none root identity preflight failed';
  end if;

  with expected(sibling_id, sibling_key, invoice_id, sibling_hash) as (
    values
      (
        '1cd0a33c-e2ec-4c03-8172-fe2f10f9a580'::uuid,
        'sales_invoice:a4bcd142-73d0-4cb9-9654-8617992ad887:update:4b6b3469-33a8-4ce8-b8c5-b22c0f13e125'::text,
        'a4bcd142-73d0-4cb9-9654-8617992ad887'::uuid,
        '81bae5f4b2d4a51cca873944427ca466'::text
      ),
      (
        'cb8797ac-3fee-40bd-9f7f-599c85236ce9'::uuid,
        'sales_invoice:bfe72331-3bd3-491f-8a2a-0f09add92e23:update:7daba47b-a4ad-4804-8aca-d4411a8c95ee'::text,
        'bfe72331-3bd3-491f-8a2a-0f09add92e23'::uuid,
        '18988d272d3ff40c3610a814b5099f8b'::text
      ),
      (
        '4535ab22-35e5-44a5-a438-9e7dea9e0ccd'::uuid,
        'sales_invoice:f28607ef-19a5-4ec1-8df1-bef01635fd66:update:c949f971-e64c-48e1-95b9-646fe59a6118'::text,
        'f28607ef-19a5-4ec1-8df1-bef01635fd66'::uuid,
        '19672f3c9fde674f2aa775c86a75ea87'::text
      )
  )
  select count(*)::integer
    into v_sibling_matches
    from expected
    join public.inventory_accounting_operations sibling
      on sibling.id = expected.sibling_id
   where sibling.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'::uuid
     and sibling.operation_key = expected.sibling_key
     and sibling.source_channel = 'mechanic_job'
     and sibling.action = 'update'
     and sibling.document_type = 'sales_invoice'
     and sibling.document_id = expected.invoice_id
     and sibling.old_status = 'cancelled'
     and sibling.new_status = 'cancelled'
     and sibling.outcome = 'completed'
     and md5(sibling.before_snapshot::text) = expected.sibling_hash
     and md5(sibling.after_snapshot::text) = expected.sibling_hash
     and sibling.context->>'table' = 'public.sales_invoices'
     and sibling.context->>'trigger_depth' = '2'
     and sibling.context->>'transaction_id' = '832950';

  if v_sibling_matches <> 3 then
    raise exception 'QA trace repair all-or-none completed-sibling preflight failed';
  end if;

  if v_completed = 3 then
    select count(distinct operation.id)::integer
      into v_repaired
      from public.inventory_accounting_operations operation
     where operation.id in (
       '7970e3f0-1716-4aaf-a577-f40319037f20'::uuid,
       'dbb8711b-1f6d-4ce2-9954-7fceb7553eea'::uuid,
       'e3b6e284-7ac2-4a2d-a4f3-3fbede41b60e'::uuid
     )
       and exists (
         select 1
           from public.inventory_accounting_checkpoints checkpoint
          where checkpoint.operation_id = operation.id
            and checkpoint.phase = 'completed'
            and checkpoint.payload->>'repair'
                  = 'close_nested_trace_context_root_832950'
            and checkpoint.payload->>'business_effects_replayed' = 'false'
       );
    if v_repaired <> 3 then
      raise exception 'QA trace repair replay found completed roots without all repair receipts';
    end if;
  end if;
end;
$$;

do $$
declare
  v_case jsonb;
  v_operation public.inventory_accounting_operations%rowtype;
  v_checkpoint_ids bigint[];
  v_warning_payload jsonb;
  v_tenant_id constant uuid := '5443b130-cc28-45af-a420-cd500b288890';
  v_original_operation_id constant uuid := '1a958e9b-3524-4d74-94a7-f9d453f848a7';
  v_true_fv00884_cancel_root constant uuid := '7970e3f0-1716-4aaf-a577-f40319037f20';
  v_crossed_journal_id constant uuid := '0eb856e7-53f8-4689-9d97-39eefe911989';
begin
  for v_case in
    select value
      from jsonb_array_elements($cases$[
        {
          "root_id":"7970e3f0-1716-4aaf-a577-f40319037f20",
          "operation_key":"sales_invoice:a4bcd142-73d0-4cb9-9654-8617992ad887:update:08e9765c-2bbc-438e-b0aa-71e30d55bd34",
          "invoice_id":"a4bcd142-73d0-4cb9-9654-8617992ad887",
          "invoice_number":"FV-00884",
          "job_id":"6ecdd845-1f69-400e-a447-971cfe994798",
          "job_number":"PG-00467",
          "old_status":"paid",
          "total":3000,
          "paid_amount":0,
          "balance":3000,
          "before_hash":"0d0495431b5a32291d783c645427c6af",
          "after_hash":"9504deab381af3b3082095a0872adcc7",
          "checkpoint_ids":[3785,3786],
          "sibling_id":"1cd0a33c-e2ec-4c03-8172-fe2f10f9a580",
          "sibling_key":"sales_invoice:a4bcd142-73d0-4cb9-9654-8617992ad887:update:4b6b3469-33a8-4ce8-b8c5-b22c0f13e125",
          "sibling_hash":"81bae5f4b2d4a51cca873944427ca466"
        },
        {
          "root_id":"dbb8711b-1f6d-4ce2-9954-7fceb7553eea",
          "operation_key":"sales_invoice:bfe72331-3bd3-491f-8a2a-0f09add92e23:update:9792dfb2-438d-4f26-9ca2-1aa1d4447990",
          "invoice_id":"bfe72331-3bd3-491f-8a2a-0f09add92e23",
          "invoice_number":"FV-00886",
          "job_id":"ee7dbd97-5d1d-4e4b-99f6-edcec5e11293",
          "job_number":"PG-00469",
          "old_status":"draft",
          "total":0,
          "paid_amount":0,
          "balance":0,
          "before_hash":"a6f661ea2f3d6d1bef4955edc685c9e5",
          "after_hash":"18988d272d3ff40c3610a814b5099f8b",
          "checkpoint_ids":[3787,3788],
          "sibling_id":"cb8797ac-3fee-40bd-9f7f-599c85236ce9",
          "sibling_key":"sales_invoice:bfe72331-3bd3-491f-8a2a-0f09add92e23:update:7daba47b-a4ad-4804-8aca-d4411a8c95ee",
          "sibling_hash":"18988d272d3ff40c3610a814b5099f8b"
        },
        {
          "root_id":"e3b6e284-7ac2-4a2d-a4f3-3fbede41b60e",
          "operation_key":"sales_invoice:f28607ef-19a5-4ec1-8df1-bef01635fd66:update:e1a59b66-e516-4169-9e63-f82ded6ac746",
          "invoice_id":"f28607ef-19a5-4ec1-8df1-bef01635fd66",
          "invoice_number":"FV-00887",
          "job_id":"b7f427d7-e56b-4c2d-b143-d13549996c67",
          "job_number":"PG-00470",
          "old_status":"draft",
          "total":22000,
          "paid_amount":0,
          "balance":22000,
          "before_hash":"e8a05563d04913222f93fd6ec90f9e08",
          "after_hash":"19672f3c9fde674f2aa775c86a75ea87",
          "checkpoint_ids":[3789,3790,3791,3792],
          "sibling_id":"4535ab22-35e5-44a5-a438-9e7dea9e0ccd",
          "sibling_key":"sales_invoice:f28607ef-19a5-4ec1-8df1-bef01635fd66:update:c949f971-e64c-48e1-95b9-646fe59a6118",
          "sibling_hash":"19672f3c9fde674f2aa775c86a75ea87",
          "crossed_checkpoint_ids":[3791,3792,3793]
        }
      ]$cases$::jsonb)
  loop
    select * into v_operation
      from public.inventory_accounting_operations operation
     where operation.id = (v_case->>'root_id')::uuid;

    -- Local/fresh databases do not contain production QA evidence.
    if not found then
      continue;
    end if;

    if v_operation.outcome = 'completed' then
      if not exists (
        select 1
          from public.inventory_accounting_checkpoints checkpoint
         where checkpoint.operation_id = v_operation.id
           and checkpoint.phase = 'invariants_verified'
           and checkpoint.outcome = 'warning'
           and checkpoint.payload->>'repair'
                 = 'close_nested_trace_context_root_832950'
      ) or not exists (
        select 1
          from public.inventory_accounting_checkpoints checkpoint
         where checkpoint.operation_id = v_operation.id
           and checkpoint.phase = 'completed'
           and checkpoint.payload->>'repair'
                 = 'close_nested_trace_context_root_832950'
           and checkpoint.payload->>'business_effects_replayed' = 'false'
      ) then
        raise exception 'Completed QA trace % lacks canonical repair evidence', v_operation.id;
      end if;
      if v_operation.id = 'e3b6e284-7ac2-4a2d-a4f3-3fbede41b60e'::uuid
         and (
           not exists (
             select 1
               from public.inventory_accounting_checkpoints checkpoint
              where checkpoint.operation_id = v_original_operation_id
                and checkpoint.phase = 'invariants_verified'
                and checkpoint.outcome = 'warning'
                and checkpoint.payload->>'repair'
                      = 'reconcile_cross_attached_trace_832950'
           )
           or not exists (
             select 1
               from public.inventory_accounting_checkpoints checkpoint
              where checkpoint.operation_id = v_true_fv00884_cancel_root
                and checkpoint.phase = 'invariants_verified'
                and checkpoint.outcome = 'warning'
                and checkpoint.payload->>'repair'
                      = 'reconcile_cross_attached_trace_832950'
                and checkpoint.payload->>'misattached_operation_id'
                      = v_operation.id::text
           )
         ) then
        raise exception 'Completed QA trace % lacks cross-reconciliation evidence',
          v_operation.id;
      end if;
      continue;
    end if;

    if v_operation.outcome <> 'started'
       or v_operation.tenant_id is distinct from v_tenant_id
       or v_operation.operation_key is distinct from v_case->>'operation_key'
       or v_operation.source_channel is distinct from 'mechanic_job'
       or v_operation.action is distinct from 'update'
       or v_operation.document_type is distinct from 'sales_invoice'
       or v_operation.document_id is distinct from (v_case->>'invoice_id')::uuid
       or v_operation.actor_id is not null
       or v_operation.executor is distinct from 'database_trigger'
       or v_operation.old_status is distinct from v_case->>'old_status'
       or v_operation.new_status is distinct from 'cancelled'
       or v_operation.before_snapshot is null
       or v_operation.after_snapshot is null
       or md5(v_operation.before_snapshot::text) is distinct from v_case->>'before_hash'
       or md5(v_operation.after_snapshot::text) is distinct from v_case->>'after_hash'
       or v_operation.context->>'table' is distinct from 'public.sales_invoices'
       or v_operation.context->>'trigger_depth' is distinct from '1'
       or v_operation.context->>'transaction_id' is distinct from '832950'
       or v_operation.context->>'before_hash' is distinct from v_case->>'before_hash'
       or v_operation.context->>'after_hash' is distinct from v_case->>'after_hash'
       or v_operation.error_code is not null
       or v_operation.error_message is not null
       or v_operation.completed_at is not null then
      raise exception 'QA trace repair preflight failed: root % identity changed', v_operation.id;
    end if;

    if not exists (
      select 1
        from public.sales_invoices invoice
       where invoice.id = (v_case->>'invoice_id')::uuid
         and invoice.tenant_id = v_tenant_id
         and invoice.invoice_number = v_case->>'invoice_number'
         and lower(invoice.status) = 'cancelled'
         and coalesce(invoice.total, 0) = (v_case->>'total')::numeric
         and coalesce(invoice.paid_amount, 0) = (v_case->>'paid_amount')::numeric
         and coalesce(invoice.balance, 0) = (v_case->>'balance')::numeric
    ) or not exists (
      select 1
        from public.mechanic_jobs job
       where job.id = (v_case->>'job_id')::uuid
         and job.tenant_id = v_tenant_id
         and job.job_number = v_case->>'job_number'
         and job.invoice_id = (v_case->>'invoice_id')::uuid
         and job.deleted_at is not null
    ) then
      raise exception 'QA trace repair preflight failed: source graph changed for %', v_operation.id;
    end if;

    if not exists (
      select 1
        from public.inventory_accounting_operations sibling
       where sibling.id = (v_case->>'sibling_id')::uuid
         and sibling.tenant_id = v_tenant_id
         and sibling.operation_key = v_case->>'sibling_key'
         and sibling.source_channel = 'mechanic_job'
         and sibling.action = 'update'
         and sibling.document_type = 'sales_invoice'
         and sibling.document_id = (v_case->>'invoice_id')::uuid
         and sibling.actor_id is null
         and sibling.executor = 'database_trigger'
         and sibling.old_status = 'cancelled'
         and sibling.new_status = 'cancelled'
         and sibling.outcome = 'completed'
         and md5(sibling.before_snapshot::text) = v_case->>'sibling_hash'
         and md5(sibling.after_snapshot::text) = v_case->>'sibling_hash'
         and sibling.context->>'table' = 'public.sales_invoices'
         and sibling.context->>'trigger_depth' = '2'
         and sibling.context->>'transaction_id' = '832950'
         and sibling.context->>'before_hash' = v_case->>'sibling_hash'
         and sibling.context->>'after_hash' = v_case->>'sibling_hash'
         and exists (
           select 1
             from public.inventory_accounting_checkpoints checkpoint
            where checkpoint.operation_id = sibling.id
              and checkpoint.phase = 'completed'
              and checkpoint.outcome = 'completed'
         )
         and not exists (
           select 1 from public.stock_movements movement
            where movement.operation_id = sibling.id
         )
         and not exists (
           select 1 from public.stock_adjustments adjustment
            where adjustment.operation_id = sibling.id
         )
         and not exists (
           select 1 from public.journal_entries entry
            where entry.operation_id = sibling.id
         )
    ) then
      raise exception 'QA trace repair preflight failed: sibling evidence changed for %', v_operation.id;
    end if;

    select array_agg(checkpoint.id order by checkpoint.id)
      into v_checkpoint_ids
      from public.inventory_accounting_checkpoints checkpoint
     where checkpoint.operation_id = v_operation.id;

    if v_checkpoint_ids is distinct from array(
      select value::text::bigint
        from jsonb_array_elements(v_case->'checkpoint_ids')
    ) then
      raise exception 'QA trace repair preflight failed: checkpoint set changed for %', v_operation.id;
    end if;

    if not exists (
      select 1
        from public.inventory_accounting_checkpoints checkpoint
       where checkpoint.operation_id = v_operation.id
         and checkpoint.phase = 'accepted'
         and checkpoint.outcome = 'started'
         and checkpoint.entity_type = 'sales_invoice'
         and checkpoint.entity_id = v_operation.document_id
         and checkpoint.payload = jsonb_build_object(
           'action', 'update',
           'old_status', v_case->>'old_status',
           'new_status', 'cancelled'
         )
    ) or not exists (
      select 1
        from public.inventory_accounting_checkpoints checkpoint
       where checkpoint.operation_id = v_operation.id
         and checkpoint.phase = 'source_snapshotted'
         and checkpoint.outcome = 'completed'
         and checkpoint.entity_type = 'sales_invoice'
         and checkpoint.entity_id = v_operation.document_id
         and checkpoint.payload = jsonb_build_object(
           'before', v_operation.before_snapshot,
           'after', v_operation.after_snapshot
         )
    ) or exists (
      select 1 from public.stock_movements movement
       where movement.operation_id = v_operation.id
    ) or exists (
      select 1 from public.stock_adjustments adjustment
       where adjustment.operation_id = v_operation.id
    ) or exists (
      select 1 from public.journal_entries entry
       where entry.operation_id = v_operation.id
    ) then
      raise exception 'QA trace repair preflight failed: root evidence changed for %', v_operation.id;
    end if;

    v_warning_payload := jsonb_build_object(
      'repair', 'close_nested_trace_context_root_832950',
      'transaction_id', '832950',
      'cause', 'transaction_local_trace_context_was_overwritten_by_nested_or_sibling_row',
      'immutable_evidence_preserved', true,
      'business_effects_replayed', false,
      'invoice_id', v_operation.document_id,
      'invoice_number', v_case->>'invoice_number'
    );

    if v_operation.id = 'e3b6e284-7ac2-4a2d-a4f3-3fbede41b60e'::uuid then
      if not exists (
        select 1
          from public.inventory_accounting_checkpoints checkpoint
         where checkpoint.id in (3791, 3792)
           and checkpoint.operation_id = v_operation.id
           and checkpoint.phase = 'journal_reversed'
           and checkpoint.outcome = 'completed'
           and checkpoint.entity_type = 'journal_entry'
           and checkpoint.entity_id = v_crossed_journal_id
           and coalesce(
             checkpoint.payload->>'source_reference',
             checkpoint.payload#>>'{header,source_reference}',
             checkpoint.payload#>>'{deleted_snapshot,source_reference}'
           ) = 'FV-00884'
           and coalesce(
             checkpoint.payload->>'entry_number',
             checkpoint.payload#>>'{header,entry_number}',
             checkpoint.payload#>>'{deleted_snapshot,entry_number}'
           ) = 'AC-02140'
        having count(*) = 2
      ) or not exists (
        select 1
          from public.inventory_accounting_operations original
         where original.id = v_original_operation_id
           and original.tenant_id = v_tenant_id
           and original.document_type = 'sales_invoice'
           and original.document_id = 'a4bcd142-73d0-4cb9-9654-8617992ad887'::uuid
           and original.outcome = 'completed'
      ) or not exists (
        select 1
          from public.inventory_accounting_checkpoints checkpoint
         where checkpoint.id = 3793
           and checkpoint.operation_id = v_original_operation_id
           and checkpoint.phase = 'journal_reversed'
           and checkpoint.outcome = 'completed'
           and checkpoint.entity_type = 'journal_entry'
           and checkpoint.entity_id = v_crossed_journal_id
           and checkpoint.payload->>'entry_number' = 'AC-02140'
           and checkpoint.payload->>'reversed_by_operation_id' = v_operation.id::text
      ) or not exists (
        select 1
          from public.inventory_accounting_operations true_root
         where true_root.id = v_true_fv00884_cancel_root
           and true_root.tenant_id = v_tenant_id
           and true_root.document_type = 'sales_invoice'
           and true_root.document_id = 'a4bcd142-73d0-4cb9-9654-8617992ad887'::uuid
           and true_root.outcome = 'completed'
           and exists (
             select 1
               from public.inventory_accounting_checkpoints checkpoint
              where checkpoint.operation_id = true_root.id
                and checkpoint.phase = 'completed'
                and checkpoint.payload->>'repair'
                      = 'close_nested_trace_context_root_832950'
                and checkpoint.payload->>'business_effects_replayed' = 'false'
           )
      ) then
        raise exception 'QA trace repair preflight failed: crossed immutable evidence changed';
      end if;

      v_warning_payload := v_warning_payload || jsonb_build_object(
        'immutable_cross_attached_evidence', true,
        'crossed_checkpoint_ids', v_case->'crossed_checkpoint_ids',
        'actual_source_document_type', 'sales_invoice',
        'actual_source_document_id', 'a4bcd142-73d0-4cb9-9654-8617992ad887',
        'actual_source_reference', 'FV-00884',
        'actual_journal_entry_id', v_crossed_journal_id,
        'actual_journal_entry_number', 'AC-02140',
        'original_posting_operation_id', v_original_operation_id,
        'true_cancellation_operation_id', v_true_fv00884_cancel_root
      );

      if not exists (
        select 1
          from public.inventory_accounting_checkpoints checkpoint
         where checkpoint.operation_id = v_true_fv00884_cancel_root
           and checkpoint.phase = 'invariants_verified'
           and checkpoint.outcome = 'warning'
           and checkpoint.payload->>'repair'
                 = 'reconcile_cross_attached_trace_832950'
           and checkpoint.payload->>'misattached_operation_id'
                 = v_operation.id::text
      ) then
        perform public.append_inventory_accounting_checkpoint(
          v_true_fv00884_cancel_root,
          'invariants_verified',
          'warning',
          'journal_entry',
          v_crossed_journal_id,
          jsonb_build_object(
            'repair', 'reconcile_cross_attached_trace_832950',
            'transaction_id', '832950',
            'immutable_cross_attached_evidence', true,
            'crossed_checkpoint_ids', v_case->'crossed_checkpoint_ids',
            'actual_source_document_type', 'sales_invoice',
            'actual_source_document_id', 'a4bcd142-73d0-4cb9-9654-8617992ad887',
            'actual_source_reference', 'FV-00884',
            'actual_journal_entry_number', 'AC-02140',
            'original_posting_operation_id', v_original_operation_id,
            'misattached_operation_id', v_operation.id,
            'business_effects_replayed', false
          )
        );
      end if;

      if not exists (
        select 1
          from public.inventory_accounting_checkpoints checkpoint
         where checkpoint.operation_id = v_original_operation_id
           and checkpoint.phase = 'invariants_verified'
           and checkpoint.outcome = 'warning'
           and checkpoint.payload->>'repair'
                 = 'reconcile_cross_attached_trace_832950'
      ) then
        perform public.append_inventory_accounting_checkpoint(
          v_original_operation_id,
          'invariants_verified',
          'warning',
          'journal_entry',
          v_crossed_journal_id,
          jsonb_build_object(
            'repair', 'reconcile_cross_attached_trace_832950',
            'transaction_id', '832950',
            'immutable_cross_attached_evidence', true,
            'crossed_checkpoint_ids', v_case->'crossed_checkpoint_ids',
            'actual_source_document_type', 'sales_invoice',
            'actual_source_document_id', 'a4bcd142-73d0-4cb9-9654-8617992ad887',
            'actual_source_reference', 'FV-00884',
            'actual_journal_entry_number', 'AC-02140',
            'misattached_operation_id', v_operation.id,
            'true_cancellation_operation_id', v_true_fv00884_cancel_root,
            'business_effects_replayed', false
          )
        );
      end if;
    end if;

    perform public.append_inventory_accounting_checkpoint(
      v_operation.id,
      'invariants_verified',
      'warning',
      'sales_invoice',
      v_operation.document_id,
      v_warning_payload
    );

    perform public.complete_inventory_accounting_operation(
      v_operation.id,
      v_tenant_id,
      jsonb_build_object(
        'repair', 'close_nested_trace_context_root_832950',
        'transaction_id', '832950',
        'evidence', 'strict_identity_snapshot_graph_and_checkpoint_preflight',
        'business_effects_replayed', false
      )
    );

    if not exists (
      select 1
        from public.inventory_accounting_operations operation
       where operation.id = v_operation.id
         and operation.outcome = 'completed'
         and operation.completed_at is not null
    ) then
      raise exception 'QA trace repair failed to complete root %', v_operation.id;
    end if;
  end loop;
end;
$$;

commit;
