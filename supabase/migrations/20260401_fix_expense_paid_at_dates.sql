-- Fix expense timestamp defaults for historical expenses.
-- Includes retroactive backfill for existing affected rows.
-- Source of truth updated in supabase/sql/core_schema.sql.

create or replace function public.prepare_expense_record()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_posting text := lower(coalesce(NEW.posting_status, 'draft'));
  v_payment text := lower(coalesce(NEW.payment_status, 'pending'));
begin
  if TG_OP = 'INSERT' then
    if coalesce(NEW.expense_number, '') = '' then
      NEW.expense_number := public.generate_expense_number();
    end if;
    NEW.created_at := coalesce(NEW.created_at, now());
    if v_posting = 'posted' then
      NEW.posted_at := coalesce(NEW.posted_at, NEW.issue_date, now());
    end if;
    if v_payment = 'paid' then
      NEW.paid_at := coalesce(NEW.paid_at, NEW.issue_date, now());
    end if;
  elsif TG_OP = 'UPDATE' then
    if v_posting = 'posted' and lower(coalesce(OLD.posting_status, 'draft')) <> 'posted' then
      NEW.posted_at := coalesce(NEW.posted_at, NEW.issue_date, now());
    elsif v_posting <> 'posted' then
      NEW.posted_at := null;
    end if;

    if v_payment = 'paid' and lower(coalesce(OLD.payment_status, 'pending')) <> 'paid' then
      NEW.paid_at := coalesce(NEW.paid_at, NEW.issue_date, now());
    elsif v_payment <> 'paid' then
      NEW.paid_at := null;
    end if;
  end if;

  NEW.updated_at := now();
  return NEW;
end;
$$;

create or replace function public.recalculate_expense_totals(p_expense_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_expense record;
  v_subtotal numeric(14,2) := 0;
  v_tax numeric(14,2) := 0;
  v_total numeric(14,2) := 0;
  v_paid numeric(14,2) := 0;
  v_latest_payment_date timestamp with time zone;
  v_payment_method_count integer := 0;
  v_payment_account_count integer := 0;
  v_single_payment_method_id uuid;
  v_single_payment_account_id uuid;
  v_category_id uuid;
  v_line_account_id uuid;
  v_line_account_code text;
  v_line_account_name text;
  v_category_name text;
  v_category_desc text;
  v_prev_payment text;
  v_new_payment text;
begin
  if p_expense_id is null then
    return;
  end if;

    select e.id,
      e.tenant_id,
      e.category_id,
         e.issue_date,
         lower(coalesce(e.payment_status, 'pending')) as payment_status,
         lower(coalesce(e.posting_status, 'draft')) as posting_status,
         e.paid_at,
         e.payment_method_id,
      e.payment_account_id,
         e.amount_paid as current_amount_paid,
         e.balance as current_balance
    into v_expense
    from public.expenses e
   where e.id = p_expense_id
   for update;

  if not found then
    return;
  end if;

  select
      coalesce(sum(subtotal), 0),
      coalesce(sum(tax_amount), 0),
      coalesce(sum(total), 0)
    into v_subtotal, v_tax, v_total
    from public.expense_lines
   where expense_id = p_expense_id;

  select coalesce(sum(amount), 0)
    into v_paid
    from public.expense_payments
   where expense_id = p_expense_id;

  select max(payment_date)
    into v_latest_payment_date
    from public.expense_payments
   where expense_id = p_expense_id
     and coalesce(amount, 0) > 0;

  if v_paid > 0 then
    select
      count(distinct ep.payment_method_id),
      (array_agg(distinct ep.payment_method_id))[1]
      into v_payment_method_count, v_single_payment_method_id
      from public.expense_payments ep
     where ep.expense_id = p_expense_id
       and coalesce(ep.amount, 0) > 0
       and ep.payment_method_id is not null;

    select
      count(distinct ep.payment_account_id),
      (array_agg(distinct ep.payment_account_id))[1]
      into v_payment_account_count, v_single_payment_account_id
      from public.expense_payments ep
     where ep.expense_id = p_expense_id
       and coalesce(ep.amount, 0) > 0
       and ep.payment_account_id is not null;
  end if;

  v_prev_payment := v_expense.payment_status;

  v_category_id := v_expense.category_id;
  if v_category_id is null then
    select el.account_id,
           el.account_code,
           el.account_name
      into v_line_account_id,
           v_line_account_code,
           v_line_account_name
      from public.expense_lines el
     where el.expense_id = p_expense_id
     order by el.line_index asc, el.created_at asc
     limit 1;

    if v_line_account_id is not null then
      v_category_name := public.get_expense_category_name_for_account(
        v_line_account_code,
        v_line_account_name
      );
      v_category_desc := coalesce(v_line_account_name, v_category_name);

      v_category_id := public.ensure_expense_category(
        v_expense.tenant_id,
        v_category_name,
        v_category_desc,
        v_line_account_id
      );
    end if;
  end if;

  if v_prev_payment = 'paid'
     and v_expense.payment_method_id is not null
     and v_paid = 0
     and v_total > 0 then
    v_new_payment := 'paid';
    v_paid := v_total;
  elsif v_total = 0 then
    v_new_payment := v_prev_payment;
  elsif v_paid <= 0 then
    if v_prev_payment = 'scheduled' then
      v_new_payment := 'scheduled';
    else
      v_new_payment := 'pending';
    end if;
  elsif v_paid + 0.01 < v_total then
    v_new_payment := 'partial';
  else
    v_new_payment := 'paid';
  end if;

  update public.expenses
     set subtotal = v_subtotal,
         tax_amount = v_tax,
         total_amount = v_total,
         amount_paid = v_paid,
         balance = greatest(v_total - v_paid, 0),
         category_id = coalesce(category_id, v_category_id),
         payment_method_id = case
           when v_payment_method_count = 1 and v_expense.payment_method_id is null
             then v_single_payment_method_id
           else payment_method_id
         end,
         payment_account_id = case
           when v_payment_account_count = 1 and v_expense.payment_account_id is null
             then v_single_payment_account_id
           else payment_account_id
         end,
         payment_status = case
           when v_expense.posting_status = 'void' then payment_status
           when v_prev_payment = 'void' then 'void'
           else v_new_payment
         end,
         paid_at = case
           when v_expense.posting_status <> 'void'
             and v_total > 0
             and v_paid + 0.01 >= v_total then coalesce(v_latest_payment_date, paid_at, v_expense.issue_date, now())
           when v_new_payment <> 'paid' then null
           else paid_at
         end,
         updated_at = now()
   where id = p_expense_id;
end;
$$;

do $$
declare
  v_fixed_count integer := 0;
begin
  with payment_rollup as (
    select
      e.id,
      max(ep.payment_date) filter (where coalesce(ep.amount, 0) > 0) as latest_payment_date,
      count(ep.id) filter (where coalesce(ep.amount, 0) > 0) as payment_count
    from public.expenses e
    left join public.expense_payments ep
      on ep.expense_id = e.id
    where lower(coalesce(e.payment_status, 'pending')) = 'paid'
      and lower(coalesce(e.posting_status, 'draft')) <> 'void'
    group by e.id
  ), targets as (
    select
      e.id,
      case
        when pr.payment_count > 0 then pr.latest_payment_date
        when pr.payment_count = 0
          and e.issue_date is not null
          and (
            e.paid_at is null
            or (
              e.paid_at is not null
              and e.created_at is not null
              and e.created_at::date = e.paid_at::date
              and e.issue_date::date <> e.paid_at::date
            )
          ) then e.issue_date
        else null
      end as corrected_paid_at,
      case
        when pr.payment_count = 0
          and e.issue_date is not null
          and (
            e.posted_at is null
            or (
              e.posted_at is not null
              and e.created_at is not null
              and e.created_at::date = e.posted_at::date
              and e.issue_date::date <> e.posted_at::date
            )
          ) then e.issue_date
        else null
      end as corrected_posted_at
    from public.expenses e
    join payment_rollup pr on pr.id = e.id
  )
  update public.expenses e
     set paid_at = coalesce(t.corrected_paid_at, e.paid_at),
         posted_at = coalesce(t.corrected_posted_at, e.posted_at),
         updated_at = now()
    from targets t
   where e.id = t.id
     and (
       t.corrected_paid_at is distinct from e.paid_at
       or t.corrected_posted_at is distinct from e.posted_at
     );

  get diagnostics v_fixed_count = row_count;
  raise notice 'Backfilled % expense rows with corrected paid_at/posted_at', v_fixed_count;
end $$;