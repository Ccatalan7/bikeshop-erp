begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select set_config('app.inventory_operation_id', '', true);
select set_config('app.inventory_source_document_type', '', true);
select set_config('app.inventory_source_document_id', '', true);
select set_config('app.inventory_source_channel', '', true);
select set_config('app.inventory_trace_context_stack', '[]', true);

select plan(17);

insert into public.tenants (id, shop_name)
values (
  '99716000-0000-4000-8000-000000000001',
  'Nested Invoice Trace Context Test'
);

select set_config('request.jwt.claim.sub', '', true);

create temp table selected_payment_method on commit drop as
select id
from public.payment_methods
where tenant_id = '99716000-0000-4000-8000-000000000001'
order by created_at, id
limit 1;

insert into public.sales_invoices (
  id,
  tenant_id,
  invoice_number,
  customer_name,
  source,
  status,
  subtotal,
  net_amount,
  iva_amount,
  total,
  paid_amount,
  balance,
  tax_treatment,
  items
)
values (
  '99716000-0000-4000-8000-000000000002',
  '99716000-0000-4000-8000-000000000001',
  'FV-NESTED-TRACE-001',
  'Nested Trace Customer',
  'mechanic_job',
  'confirmed',
  1000,
  1000,
  0,
  1000,
  0,
  1000,
  'no_tax',
  '[]'::jsonb
);

insert into public.sales_payments (
  id,
  tenant_id,
  invoice_id,
  payment_method_id,
  amount,
  tax_treatment,
  net_amount,
  iva_amount,
  idempotency_key,
  date
)
select
  payment.id,
  '99716000-0000-4000-8000-000000000001',
  '99716000-0000-4000-8000-000000000002',
  method.id,
  payment.amount,
  'no_tax',
  payment.amount,
  0,
  payment.idempotency_key,
  now() + payment.offset_value
from selected_payment_method method
cross join (
  values
    (
      '99716000-0000-4000-8000-000000000003'::uuid,
      400::numeric,
      'nested-trace-payment-1'::text,
      interval '0 seconds'
    ),
    (
      '99716000-0000-4000-8000-000000000004'::uuid,
      600::numeric,
      'nested-trace-payment-2'::text,
      interval '1 second'
    )
) payment(id, amount, idempotency_key, offset_value);

select results_eq(
  $$
    select status, paid_amount, balance
    from public.sales_invoices
    where id = '99716000-0000-4000-8000-000000000002'
  $$,
  $$values ('paid'::text, 1000::numeric, 0::numeric)$$,
  'two active payments fully settle the invoice before cancellation'
);

create temp table trace_operations_before_cancel on commit drop as
select id
from public.inventory_accounting_operations
where tenant_id = '99716000-0000-4000-8000-000000000001';

-- This single invoice update performs one multi-row soft-delete of both
-- payments. Each payment trigger recalculates the invoice again, exercising
-- nested invoice/payment trace contexts inside the outer invoice trace.
update public.sales_invoices
set status = 'cancelled'
where id = '99716000-0000-4000-8000-000000000002';

create temp table cancellation_trace_operations on commit drop as
select operation.*
from public.inventory_accounting_operations operation
where operation.tenant_id = '99716000-0000-4000-8000-000000000001'
  and not exists (
    select 1
    from trace_operations_before_cancel baseline
    where baseline.id = operation.id
  );

select results_eq(
  $$
    select status, paid_amount, balance
    from public.sales_invoices
    where id = '99716000-0000-4000-8000-000000000002'
  $$,
  $$values ('cancelled'::text, 0::numeric, 1000::numeric)$$,
  'cancelling the invoice clears the payment total and preserves cancelled status'
);

select is(
  (
    select count(*)::integer
    from public.sales_payments
    where invoice_id = '99716000-0000-4000-8000-000000000002'
      and deleted_at is not null
  ),
  2,
  'invoice cancellation soft-deletes both payments in the same trigger update'
);

select is(
  (select count(*)::integer from cancellation_trace_operations),
  3,
  'cancellation creates exactly one invoice root and two payment roots'
);

select results_eq(
  $$
    select document_type, action, count(*)::integer
    from cancellation_trace_operations
    group by document_type, action
    order by document_type, action
  $$,
  $$
    values
      ('sales_invoice'::text, 'update'::text, 1),
      ('sales_payment'::text, 'update'::text, 2)
  $$,
  'the three roots retain their exact invoice/payment action identities'
);

select is(
  (
    select count(*)::integer
    from cancellation_trace_operations
    where outcome = 'completed'
      and completed_at is not null
  ),
  3,
  'all cancellation roots reach completed outcome'
);

select is(
  (
    select count(*)::integer
    from cancellation_trace_operations
    where outcome = 'started'
  ),
  0,
  'no outer or child cancellation root remains started'
);

select ok(
  exists (
    select 1
    from cancellation_trace_operations operation
    where operation.document_type = 'sales_invoice'
      and operation.document_id = '99716000-0000-4000-8000-000000000002'
      and operation.old_status = 'paid'
      and operation.new_status = 'cancelled'
      and operation.context->>'table' = 'public.sales_invoices'
      and operation.context->>'trigger_depth' = '1'
      and operation.outcome = 'completed'
  ),
  'the outer invoice root keeps the paid-to-cancelled depth-one identity'
);

select is(
  (
    select count(*)::integer
    from cancellation_trace_operations
    where document_type = 'sales_invoice'
      and coalesce((context->>'trigger_depth')::integer, 0) > 1
  ),
  0,
  'payment recalculations do not create nested sales-invoice roots'
);

select is(
  (
    select count(*)::integer
    from cancellation_trace_operations operation
    where (
      select count(distinct checkpoint.phase)
      from public.inventory_accounting_checkpoints checkpoint
      where checkpoint.operation_id = operation.id
        and checkpoint.phase in (
          'accepted',
          'source_snapshotted',
          'invariants_verified',
          'completed'
        )
    ) = 4
  ),
  3,
  'every invoice and payment root owns the full canonical checkpoint lifecycle'
);

select is(
  (
    select count(*)::integer
    from public.inventory_accounting_checkpoints checkpoint
    join cancellation_trace_operations operation
      on operation.id = checkpoint.operation_id
    where checkpoint.phase = 'journal_reversed'
  ),
  6,
  'each invoice/payment journal reversal has trace and immutable snapshot checkpoints'
);

select ok(
  not exists (
    select 1
    from public.inventory_accounting_checkpoints checkpoint
    join cancellation_trace_operations operation
      on operation.id = checkpoint.operation_id
    where checkpoint.phase = 'journal_reversed'
      and (
        (
          operation.document_type = 'sales_invoice'
          and (
            coalesce(
              checkpoint.payload->>'source_module',
              checkpoint.payload#>>'{header,source_module}',
              checkpoint.payload#>>'{deleted_snapshot,source_module}'
            ) is distinct from 'sales_invoices'
            or coalesce(
              checkpoint.payload->>'source_reference',
              checkpoint.payload#>>'{header,source_reference}',
              checkpoint.payload#>>'{deleted_snapshot,source_reference}'
            )
                 is distinct from 'FV-NESTED-TRACE-001'
          )
        )
        or (
          operation.document_type = 'sales_payment'
          and (
            coalesce(
              checkpoint.payload->>'source_module',
              checkpoint.payload#>>'{header,source_module}',
              checkpoint.payload#>>'{deleted_snapshot,source_module}'
            ) is distinct from 'sales_payments'
            or coalesce(
              checkpoint.payload->>'source_reference',
              checkpoint.payload#>>'{header,source_reference}',
              checkpoint.payload#>>'{deleted_snapshot,source_reference}'
            )
                 is distinct from operation.document_id::text
          )
        )
      )
  ),
  'journal reversal checkpoints never cross from one invoice or payment root to another'
);

select ok(
  not exists (
    select 1
    from cancellation_trace_operations operation
    where operation.document_type = 'sales_payment'
      and not exists (
        select 1
        from public.inventory_accounting_checkpoints checkpoint
        where checkpoint.operation_id = operation.id
          and checkpoint.phase = 'completed'
          and checkpoint.payload->>'payment_id' = operation.document_id::text
          and checkpoint.payload->>'invoice_id'
                = '99716000-0000-4000-8000-000000000002'
      )
  ),
  'each child completion payload stays bound to its own payment and parent invoice'
);

select is(
  nullif(current_setting('app.inventory_operation_id', true), ''),
  null::text,
  'the current canonical operation context is empty after the outer row finishes'
);

select ok(
  nullif(current_setting('app.inventory_source_document_type', true), '') is null
  and nullif(current_setting('app.inventory_source_document_id', true), '') is null
  and nullif(current_setting('app.inventory_source_channel', true), '') is null,
  'all source-document trace context values are restored to empty'
);

select is(
  coalesce(
    nullif(current_setting('app.inventory_trace_context_stack', true), '')::jsonb,
    '[]'::jsonb
  ),
  '[]'::jsonb,
  'the nested trace context stack is empty after the cancellation statement'
);

select is(
  (
    select count(*)::integer
    from public.inventory_accounting_operations
    where tenant_id = '99716000-0000-4000-8000-000000000001'
      and outcome = 'started'
  ),
  0,
  'the complete fixture leaves no latent started trace for the tenant'
);

select * from finish();

rollback;
