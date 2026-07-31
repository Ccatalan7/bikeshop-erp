-- Bounded, tenant-authorized payroll audit read models.
-- Deployment status: NOT DEPLOYED. Production deployment only through the
-- owner-authorized checkpoint in docs/development/PAYROLL_COMPLETION_PLAN.md.
-- Atomicity: this file runs as one explicit transaction; a mid-file failure
-- rolls back every change (no CONCURRENTLY/VACUUM/enum-value statements).
--
-- The employee advance ledger derives allocation totals from the immutable
-- allocation rows and keeps voided advances visible without counting them as
-- active delivered money. Payroll history remains a header-only projection;
-- selecting one voucher must use the existing exact voucher hydrate path.

begin;

create index if not exists
  idx_employee_advances_tenant_employee_paid_cursor
  on public.employee_advances(
    tenant_id,
    employee_id,
    paid_at desc,
    id desc
  );

create index if not exists
  idx_payroll_vouchers_tenant_history_cursor
  on public.payroll_vouchers(
    tenant_id,
    period_end desc,
    id desc
  )
  where status in ('paid', 'voided');

drop function if exists public.get_employee_advance_ledger_page_v1(
  uuid,
  integer,
  timestamp with time zone,
  uuid
);

create or replace function public.get_employee_advance_ledger_page_v1(
  p_employee_id uuid,
  p_page_size integer default 25,
  p_cursor_paid_at timestamp with time zone default null,
  p_cursor_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  tenant_id_value uuid := public.erp_member_tenant_id();
begin
  if tenant_id_value is null
     or not public.can_manage_tenant_payroll(tenant_id_value) then
    raise exception 'Payroll access denied'
      using errcode = '42501';
  end if;

  if p_employee_id is null
     or not exists (
       select 1
       from public.employees employee
       where employee.id = p_employee_id
         and employee.tenant_id = tenant_id_value
     ) then
    -- Do not reveal whether an employee exists in another tenant.
    raise exception 'Payroll access denied'
      using errcode = '42501';
  end if;

  if p_page_size is null or p_page_size < 1 or p_page_size > 100 then
    raise exception 'Payroll page size must be between 1 and 100'
      using errcode = '22023';
  end if;

  if (p_cursor_paid_at is null) <> (p_cursor_id is null) then
    raise exception 'Employee advance cursor requires paid_at and id'
      using errcode = '22023';
  end if;

  if p_cursor_id is not null
     and not exists (
       select 1
       from public.employee_advances advance
       where advance.id = p_cursor_id
         and advance.tenant_id = tenant_id_value
         and advance.employee_id = p_employee_id
         and advance.paid_at = p_cursor_paid_at
     ) then
    raise exception 'Invalid employee advance cursor'
      using errcode = '22023';
  end if;

  return (
    with allocation_projection as (
      select
        allocation.advance_id,
        coalesce(sum(allocation.amount), 0)::numeric as applied_amount,
        jsonb_agg(
          jsonb_build_object(
            'id', allocation.id,
            'amount', allocation.amount,
            'applied_at', allocation.applied_at,
            'notes', allocation.notes,
            'created_at', allocation.created_at,
            'actor', jsonb_build_object(
              'id', allocation.created_by,
              'name', public.erp_actor_display_name(
                allocation.created_by,
                tenant_id_value
              )
            ),
            'voucher', jsonb_build_object(
              'id', voucher.id,
              'voucher_number', voucher.voucher_number,
              'period_start', voucher.period_start,
              'period_end', voucher.period_end,
              'period_label', voucher.period_label,
              'status', voucher.status
            ),
            'voucher_line', jsonb_build_object(
              'id', voucher_line.id,
              'employee_name', voucher_line.employee_name,
              'total_amount', voucher_line.total_amount
            ),
            'evidence', jsonb_strip_nulls(
              jsonb_build_object(
                'source',
                  case
                    when statement_allocation.id is not null
                      then 'statement_reconciliation'
                    when money_operation.id is not null
                      then 'manual'
                    else 'legacy'
                  end,
                'operation_id', money_operation.id,
                'operation_key', money_operation.operation_key,
                'statement_allocation_id', statement_allocation.id,
                'statement_import_id', statement_allocation.import_id,
                'statement_decision_id', statement_allocation.decision_id
              )
            )
          )
          order by allocation.applied_at, allocation.id
        ) as allocations
      from public.employee_advance_allocations allocation
      join public.employee_advances advance
        on advance.id = allocation.advance_id
       and advance.tenant_id = allocation.tenant_id
      join public.payroll_voucher_lines voucher_line
        on voucher_line.id = allocation.voucher_line_id
       and voucher_line.tenant_id = allocation.tenant_id
      join public.payroll_vouchers voucher
        on voucher.id = voucher_line.voucher_id
       and voucher.tenant_id = voucher_line.tenant_id
      left join public.payroll_money_operation_movements operation_movement
        on operation_movement.advance_allocation_id = allocation.id
       and operation_movement.tenant_id = allocation.tenant_id
      left join public.payroll_money_operations money_operation
        on money_operation.id = operation_movement.operation_id
       and money_operation.tenant_id = operation_movement.tenant_id
      left join public.payroll_statement_allocations statement_allocation
        on statement_allocation.employee_advance_allocation_id = allocation.id
       and statement_allocation.tenant_id = allocation.tenant_id
      where advance.tenant_id = tenant_id_value
        and advance.employee_id = p_employee_id
      group by allocation.advance_id
    ),
    ledger as (
      select
        advance.id,
        advance.employee_id,
        advance.amount,
        coalesce(
          allocation_projection.applied_amount,
          0
        )::numeric as applied_amount,
        case
          when advance.status = 'voided' then 0::numeric
          else greatest(
            advance.amount
              - coalesce(allocation_projection.applied_amount, 0),
            0
          )::numeric
        end as balance_amount,
        advance.payment_method_id,
        payment_method.code::text as payment_method_code,
        payment_method.name::text as payment_method_name,
        advance.payment_account_id,
        payment_account.code::text as payment_account_code,
        payment_account.name::text as payment_account_name,
        advance.paid_at,
        advance.reference::text,
        advance.notes::text,
        advance.status::text,
        advance.created_by,
        public.erp_actor_display_name(
          advance.created_by,
          tenant_id_value
        ) as created_by_name,
        advance.created_at,
        advance.updated_at,
        funding_operation.id as funding_operation_id,
        funding_operation.operation_key::text as funding_operation_key,
        funding_operation.created_at as funding_operation_created_at,
        coalesce(
          allocation_projection.allocations,
          '[]'::jsonb
        ) as allocations
      from public.employee_advances advance
      left join allocation_projection
        on allocation_projection.advance_id = advance.id
      left join public.payment_methods payment_method
        on payment_method.id = advance.payment_method_id
       and payment_method.tenant_id = advance.tenant_id
      left join public.accounts payment_account
        on payment_account.id = advance.payment_account_id
       and payment_account.tenant_id = advance.tenant_id
      left join lateral (
        select
          operation.id,
          operation.operation_key,
          operation.created_at
        from public.payroll_money_operations operation
        where operation.tenant_id = advance.tenant_id
          and operation.employee_advance_id = advance.id
          and operation.operation_type = 'employee_advance'
        order by operation.created_at, operation.id
        limit 1
      ) funding_operation on true
      where advance.tenant_id = tenant_id_value
        and advance.employee_id = p_employee_id
    ),
    totals as (
      select
        coalesce(
          sum(amount) filter (where status <> 'voided'),
          0
        )::numeric as delivered_amount,
        coalesce(
          sum(applied_amount) filter (where status <> 'voided'),
          0
        )::numeric as applied_amount,
        coalesce(
          sum(balance_amount) filter (where status <> 'voided'),
          0
        )::numeric as balance_amount,
        count(*)::integer as record_count
      from ledger
    ),
    candidates as (
      select
        ledger.*,
        row_number() over (
          order by ledger.paid_at desc, ledger.id desc
        ) as page_row_number
      from ledger
      where p_cursor_id is null
         or (ledger.paid_at, ledger.id)
              < (p_cursor_paid_at, p_cursor_id)
      order by ledger.paid_at desc, ledger.id desc
      limit p_page_size + 1
    ),
    visible as (
      select *
      from candidates
      where page_row_number <= p_page_size
    ),
    page_state as (
      select count(*) > p_page_size as has_more
      from candidates
    )
    select jsonb_build_object(
      'contract_version', 1,
      'employee_id', p_employee_id,
      'totals', jsonb_build_object(
        'delivered_amount', totals.delivered_amount,
        'applied_amount', totals.applied_amount,
        'balance_amount', totals.balance_amount,
        'record_count', totals.record_count
      ),
      'items', coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'id', visible.id,
              'employee_id', visible.employee_id,
              'amount', visible.amount,
              'applied_amount', visible.applied_amount,
              'balance_amount', visible.balance_amount,
              'paid_at', visible.paid_at,
              'status', visible.status,
              'payment_method', jsonb_build_object(
                'id', visible.payment_method_id,
                'code', visible.payment_method_code,
                'name', visible.payment_method_name
              ),
              'payment_account',
                case
                  when visible.payment_account_id is null then null
                  else jsonb_build_object(
                    'id', visible.payment_account_id,
                    'code', visible.payment_account_code,
                    'name', visible.payment_account_name
                  )
                end,
              'reference', visible.reference,
              'notes', visible.notes,
              'actor', jsonb_build_object(
                'id', visible.created_by,
                'name', visible.created_by_name
              ),
              'funding_evidence', jsonb_strip_nulls(
                jsonb_build_object(
                  'source',
                    case
                      when visible.funding_operation_id is null
                        then 'legacy'
                      else 'manual'
                    end,
                  'operation_id', visible.funding_operation_id,
                  'operation_key', visible.funding_operation_key,
                  'recorded_at', visible.funding_operation_created_at
                )
              ),
              'created_at', visible.created_at,
              'updated_at', visible.updated_at,
              'allocations', visible.allocations
            )
            order by visible.paid_at desc, visible.id desc
          )
          from visible
        ),
        '[]'::jsonb
      ),
      'has_more', page_state.has_more,
      'next_cursor',
        case
          when page_state.has_more then (
            select jsonb_build_object(
              'paid_at', visible.paid_at,
              'id', visible.id
            )
            from visible
            order by visible.paid_at asc, visible.id asc
            limit 1
          )
          else null
        end
    )
    from totals
    cross join page_state
  );
end;
$$;

comment on function public.get_employee_advance_ledger_page_v1(
  uuid,
  integer,
  timestamp with time zone,
  uuid
) is
  'Tenant/payroll-authorized employee advance ledger with allocation-derived totals, audit evidence and a validated paid_at/id keyset cursor.';

revoke all on function public.get_employee_advance_ledger_page_v1(
  uuid,
  integer,
  timestamp with time zone,
  uuid
) from public, anon, authenticated, service_role;
grant execute on function public.get_employee_advance_ledger_page_v1(
  uuid,
  integer,
  timestamp with time zone,
  uuid
) to authenticated;

drop function if exists public.get_payroll_history_page_v1(
  integer,
  date,
  uuid
);

create or replace function public.get_payroll_history_page_v1(
  p_page_size integer default 25,
  p_cursor_period_end date default null,
  p_cursor_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  tenant_id_value uuid := public.erp_member_tenant_id();
begin
  if tenant_id_value is null
     or not public.can_manage_tenant_payroll(tenant_id_value) then
    raise exception 'Payroll access denied'
      using errcode = '42501';
  end if;

  if p_page_size is null or p_page_size < 1 or p_page_size > 100 then
    raise exception 'Payroll page size must be between 1 and 100'
      using errcode = '22023';
  end if;

  if (p_cursor_period_end is null) <> (p_cursor_id is null) then
    raise exception 'Payroll history cursor requires period_end and id'
      using errcode = '22023';
  end if;

  if p_cursor_id is not null
     and not exists (
       select 1
       from public.payroll_vouchers voucher
       where voucher.id = p_cursor_id
         and voucher.tenant_id = tenant_id_value
         and voucher.period_end = p_cursor_period_end
         and voucher.status in ('paid', 'voided')
     ) then
    raise exception 'Invalid payroll history cursor'
      using errcode = '22023';
  end if;

  return (
    with candidates as (
      select
        voucher.id,
        voucher.voucher_number,
        voucher.period_start,
        voucher.period_end,
        voucher.period_label,
        voucher.total_hours,
        voucher.total_amount,
        voucher.employee_count,
        voucher.status,
        voucher.paid_at,
        voucher.paid_by,
        public.erp_actor_display_name(
          voucher.paid_by,
          tenant_id_value
        ) as paid_by_name,
        voucher.notes,
        voucher.created_by,
        public.erp_actor_display_name(
          voucher.created_by,
          tenant_id_value
        ) as created_by_name,
        voucher.created_at,
        voucher.updated_at,
        voucher.reconciliation_version,
        row_number() over (
          order by voucher.period_end desc, voucher.id desc
        ) as page_row_number
      from public.payroll_vouchers voucher
      where voucher.tenant_id = tenant_id_value
        and voucher.status in ('paid', 'voided')
        and (
          p_cursor_id is null
          or (voucher.period_end, voucher.id)
               < (p_cursor_period_end, p_cursor_id)
        )
      order by voucher.period_end desc, voucher.id desc
      limit p_page_size + 1
    ),
    visible as (
      select *
      from candidates
      where page_row_number <= p_page_size
    ),
    page_state as (
      select count(*) > p_page_size as has_more
      from candidates
    )
    select jsonb_build_object(
      'contract_version', 1,
      'items', coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'id', visible.id,
              'voucher_number', visible.voucher_number,
              'period_start', visible.period_start,
              'period_end', visible.period_end,
              'period_label', visible.period_label,
              'total_hours', visible.total_hours,
              'total_amount', visible.total_amount,
              'employee_count', visible.employee_count,
              'status', visible.status,
              'paid_at', visible.paid_at,
              'paid_by', jsonb_build_object(
                'id', visible.paid_by,
                'name', visible.paid_by_name
              ),
              'notes', visible.notes,
              'created_by', jsonb_build_object(
                'id', visible.created_by,
                'name', visible.created_by_name
              ),
              'created_at', visible.created_at,
              'updated_at', visible.updated_at,
              'reconciliation_version',
                visible.reconciliation_version
            )
            order by visible.period_end desc, visible.id desc
          )
          from visible
        ),
        '[]'::jsonb
      ),
      'has_more', page_state.has_more,
      'next_cursor',
        case
          when page_state.has_more then (
            select jsonb_build_object(
              'period_end', visible.period_end,
              'id', visible.id
            )
            from visible
            order by visible.period_end asc, visible.id asc
            limit 1
          )
          else null
        end
    )
    from page_state
  );
end;
$$;

comment on function public.get_payroll_history_page_v1(
  integer,
  date,
  uuid
) is
  'Tenant/payroll-authorized paid/voided payroll header page with a validated period_end/id keyset cursor; voucher detail is intentionally excluded.';

revoke all on function public.get_payroll_history_page_v1(
  integer,
  date,
  uuid
) from public, anon, authenticated, service_role;
grant execute on function public.get_payroll_history_page_v1(
  integer,
  date,
  uuid
) to authenticated;

commit;
