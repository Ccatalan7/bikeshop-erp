-- Deployment status: DEPLOYED to production project xzdvtzdqjeyqxnkqprtf
-- on 2026-07-15. Batch workshop-financial-20260715-v1 repaired 166 job
-- mirrors, 94 payment tax mirrors and 7 deterministic invoice journals; one
-- ambiguous zero-total invoice remains legacy_unresolved. Stock, cash and
-- invoice fingerprints were unchanged. Deployed SQL SHA-256 before annotation:
-- 3fd10a67bf5d462721a985f27a4b0e93e666659103d0c1dbd3fcdba1b6d6816c
-- Explicit, batch-keyed repair for deterministic workshop financial mirrors
-- and proven sales-invoice journal gaps. Ambiguous legacy accounting remains
-- recorded as legacy_unresolved and is never guessed by this command.
begin;

create table if not exists public.workshop_financial_backfill_runs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  batch_key text not null,
  status text not null default 'running'
    check (status in ('running', 'completed')),
  started_at timestamptz not null default clock_timestamp(),
  completed_at timestamptz,
  summary jsonb not null default '{}'::jsonb,
  unique (tenant_id, batch_key)
);

create table if not exists public.workshop_financial_backfill_rows (
  id uuid primary key default gen_random_uuid(),
  run_id uuid not null
    references public.workshop_financial_backfill_runs(id) on delete cascade,
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  job_id uuid,
  invoice_id uuid,
  payment_id uuid,
  entity_type text not null check (
    entity_type in (
      'mechanic_job',
      'sales_payment',
      'sales_invoice_journal',
      'legacy_unresolved'
    )
  ),
  changed_fields text[] not null default '{}',
  before_data jsonb not null,
  after_data jsonb not null,
  created_at timestamptz not null default clock_timestamp()
);

create index if not exists idx_workshop_financial_backfill_rows_run
  on public.workshop_financial_backfill_rows(run_id, created_at, id);

alter table public.workshop_financial_backfill_runs enable row level security;
alter table public.workshop_financial_backfill_rows enable row level security;

drop policy if exists workshop_financial_backfill_runs_select
  on public.workshop_financial_backfill_runs;
create policy workshop_financial_backfill_runs_select
  on public.workshop_financial_backfill_runs
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

drop policy if exists workshop_financial_backfill_rows_select
  on public.workshop_financial_backfill_rows;
create policy workshop_financial_backfill_rows_select
  on public.workshop_financial_backfill_rows
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

revoke all on public.workshop_financial_backfill_runs,
              public.workshop_financial_backfill_rows
  from public, anon, authenticated, service_role;
grant select on public.workshop_financial_backfill_runs,
                public.workshop_financial_backfill_rows
  to authenticated;

comment on table public.workshop_financial_backfill_runs is
  'Batch receipts for explicit deterministic workshop financial mirror and invoice journal repair.';
comment on table public.workshop_financial_backfill_rows is
  'Before/after evidence for every changed row plus unchanged legacy_unresolved accounting cases.';

-- Reference/notes/tax-mirror-only payment edits do not change cash settlement.
-- Avoid deleting and recreating an otherwise correct historical payment JE.
create or replace function public.handle_sales_payment_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if TG_OP = 'INSERT' then
    perform public.recalculate_sales_invoice_payments(NEW.invoice_id);
    perform public.create_sales_payment_journal_entry(NEW);
    return NEW;
  elsif TG_OP = 'UPDATE' then
    if NEW.tenant_id is not distinct from OLD.tenant_id
       and NEW.invoice_id is not distinct from OLD.invoice_id
       and NEW.payment_method_id is not distinct from OLD.payment_method_id
       and NEW.amount is not distinct from OLD.amount
       and NEW.date is not distinct from OLD.date
       and NEW.deleted_at is not distinct from OLD.deleted_at then
      return NEW;
    end if;

    if NEW.invoice_id is distinct from OLD.invoice_id then
      perform public.recalculate_sales_invoice_payments(OLD.invoice_id);
    end if;
    perform public.delete_sales_payment_journal_entry(OLD.id);
    perform public.recalculate_sales_invoice_payments(NEW.invoice_id);
    perform public.create_sales_payment_journal_entry(NEW);
    return NEW;
  elsif TG_OP = 'DELETE' then
    perform public.delete_sales_payment_journal_entry(OLD.id);
    perform public.recalculate_sales_invoice_payments(OLD.invoice_id);
    return OLD;
  end if;
  return null;
end;
$$;

revoke all on function public.handle_sales_payment_change()
  from public, anon, authenticated, service_role;

drop view if exists public.workshop_financial_backfill_preview;
create view public.workshop_financial_backfill_preview
with (security_invoker = true)
as
select
  job.tenant_id,
  job.id as job_id,
  job.job_number,
  invoice.id as invoice_id,
  invoice.invoice_number,
  invoice.status as invoice_status,
  invoice.total as invoice_total,
  invoice.tax_treatment as invoice_tax_treatment,
  invoice.net_amount as invoice_net_amount,
  invoice.iva_amount as invoice_iva_amount,
  payment_stats.active_payment_count,
  payment_stats.active_payment_sum,
  payment_stats.tax_mismatch_count as payment_tax_mismatch_count,
  invoice_journal.journal_count as invoice_journal_count,
  invoice_journal.ar_debit,
  invoice_journal.sales_credit,
  invoice_journal.total_debit,
  invoice_journal.total_credit,
  job_journal.journal_count as job_journal_count,
  job.tax_treatment is distinct from invoice.tax_treatment
    or public.clp_round(job.tax_amount)
         is distinct from public.clp_round(invoice.iva_amount)
    or public.clp_round(job.total_cost)
         is distinct from public.clp_round(invoice.total)
    or job.is_paid is distinct from (
      lower(invoice.status) in ('paid', 'pagado', 'pagada')
    ) as job_financial_mirror_mismatch,
  lower(invoice.status) in ('paid', 'pagado', 'pagada')
    and public.clp_round(invoice.total) > 0
    and payment_stats.active_payment_sum = public.clp_round(invoice.total)
    and job_journal.journal_count = 0
    and invoice_journal.journal_count <= 1
    and (
      invoice_journal.journal_count = 0
      or invoice_journal.ar_debit <> public.clp_round(invoice.total)
      or invoice_journal.sales_credit <> public.clp_round(invoice.total)
      or invoice_journal.total_debit <> invoice_journal.total_credit
    ) as journal_repair_eligible,
  lower(invoice.status) in ('paid', 'pagado', 'pagada')
    and (
      invoice_journal.journal_count = 0
      or invoice_journal.ar_debit <> public.clp_round(invoice.total)
      or invoice_journal.sales_credit <> public.clp_round(invoice.total)
      or invoice_journal.total_debit <> invoice_journal.total_credit
    )
    and not (
      public.clp_round(invoice.total) > 0
      and payment_stats.active_payment_sum = public.clp_round(invoice.total)
      and job_journal.journal_count = 0
      and invoice_journal.journal_count <= 1
    ) as journal_requires_manual_review
from public.mechanic_jobs job
join public.sales_invoices invoice
  on invoice.id = job.invoice_id
 and invoice.tenant_id = job.tenant_id
left join lateral (
  select
    count(*)::integer as active_payment_count,
    public.clp_round(coalesce(sum(payment.amount), 0)) as active_payment_sum,
    count(*) filter (
      where payment.tax_treatment is distinct from invoice.tax_treatment
         or public.clp_round(payment.net_amount) is distinct from case
           when invoice.tax_treatment = 'tax_included'
             then public.clp_round(payment.amount / 1.19)
           else public.clp_round(payment.amount)
         end
         or public.clp_round(payment.iva_amount) is distinct from case
           when invoice.tax_treatment = 'tax_included'
             then public.clp_round(payment.amount)
                    - public.clp_round(payment.amount / 1.19)
           else 0
         end
    )::integer as tax_mismatch_count
  from public.sales_payments payment
  where payment.invoice_id = invoice.id
    and payment.tenant_id = invoice.tenant_id
    and payment.deleted_at is null
) payment_stats on true
left join lateral (
  select
    count(distinct entry.id)::integer as journal_count,
    public.clp_round(coalesce(sum(line.debit_amount)
      filter (where line.account_code = '1130'), 0)) as ar_debit,
    public.clp_round(coalesce(sum(line.credit_amount)
      filter (where line.account_code in ('4100', '4101', '2150', '2110')), 0))
      as sales_credit,
    public.clp_round(coalesce(sum(line.debit_amount), 0)) as total_debit,
    public.clp_round(coalesce(sum(line.credit_amount), 0)) as total_credit
  from public.journal_entries entry
  left join public.journal_lines line
    on line.entry_id = entry.id
   and line.tenant_id = entry.tenant_id
  where entry.tenant_id = invoice.tenant_id
    and entry.source_module = 'sales_invoices'
    and entry.source_reference in (invoice.id::text, invoice.invoice_number)
) invoice_journal on true
left join lateral (
  select count(*)::integer as journal_count
  from public.journal_entries entry
  where entry.tenant_id = job.tenant_id
    and entry.source_module = 'mechanic_jobs'
    and entry.source_reference in (job.id::text, job.job_number)
) job_journal on true;

grant select on public.workshop_financial_backfill_preview to authenticated;

create or replace function public.apply_workshop_financial_backfill(
  p_tenant_id uuid,
  p_batch_key text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_run public.workshop_financial_backfill_runs%rowtype;
  v_key text := btrim(coalesce(p_batch_key, ''));
  v_job record;
  v_payment record;
  v_invoice public.sales_invoices%rowtype;
  v_preview record;
  v_before jsonb;
  v_after jsonb;
  v_payment_journal_before jsonb;
  v_payment_journal_after jsonb;
  v_summary jsonb;
  v_changed_jobs integer := 0;
  v_changed_payments integer := 0;
  v_repaired_journals integer := 0;
  v_manual_review integer := 0;
  v_stock_fingerprint_before text;
  v_stock_fingerprint_after text;
  v_payment_financial_fingerprint_before text;
  v_payment_financial_fingerprint_after text;
  v_invoice_fingerprint_before text;
  v_invoice_fingerprint_after text;
begin
  if p_tenant_id is null or not exists (
    select 1 from public.tenants where id = p_tenant_id
  ) then
    raise exception 'A valid tenant is required for workshop financial backfill.';
  end if;
  if v_key = '' or length(v_key) > 128 then
    raise exception 'Backfill batch key is required and must be at most 128 characters.';
  end if;
  if auth.uid() is not null then
    raise exception 'Historical workshop financial repair is database-admin only'
      using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(p_tenant_id::text || ':workshop-financial:' || v_key, 0)
  );

  select * into v_run
  from public.workshop_financial_backfill_runs
  where tenant_id = p_tenant_id and batch_key = v_key;

  if found and v_run.status = 'completed' then
    return v_run.summary || jsonb_build_object('replayed', true);
  elsif found then
    raise exception 'Backfill batch is already running.';
  end if;

  insert into public.workshop_financial_backfill_runs(tenant_id, batch_key)
  values (p_tenant_id, v_key)
  returning * into v_run;

  select md5(coalesce(string_agg(
    jsonb_build_object(
      'id', movement.id,
      'product_id', movement.product_id,
      'quantity', movement.quantity,
      'reference', movement.reference,
      'date', movement.date,
      'stock_before', movement.stock_before,
      'stock_after', movement.stock_after
    )::text,
    '|' order by movement.id
  ), ''))
  into v_stock_fingerprint_before
  from public.stock_movements movement
  where movement.tenant_id = p_tenant_id;

  select md5(coalesce(string_agg(
    jsonb_build_object(
      'id', payment.id,
      'invoice_id', payment.invoice_id,
      'method', payment.payment_method_id,
      'amount', payment.amount,
      'date', payment.date,
      'deleted_at', payment.deleted_at
    )::text,
    '|' order by payment.id
  ), ''))
  into v_payment_financial_fingerprint_before
  from public.sales_payments payment
  where payment.tenant_id = p_tenant_id;

  select md5(coalesce(string_agg(
    jsonb_build_object(
      'id', invoice.id,
      'status', invoice.status,
      'tax_treatment', invoice.tax_treatment,
      'subtotal', invoice.subtotal,
      'net_amount', invoice.net_amount,
      'iva_amount', invoice.iva_amount,
      'total', invoice.total,
      'paid_amount', invoice.paid_amount,
      'balance', invoice.balance,
      'items', invoice.items
    )::text,
    '|' order by invoice.id
  ), ''))
  into v_invoice_fingerprint_before
  from public.sales_invoices invoice
  where invoice.tenant_id = p_tenant_id;

  for v_job in
    select
      job.id as job_id,
      job.invoice_id,
      to_jsonb(job) as before_data,
      invoice.tax_treatment,
      invoice.iva_amount,
      invoice.total,
      lower(invoice.status) in ('paid', 'pagado', 'pagada') as is_paid
    from public.mechanic_jobs job
    join public.sales_invoices invoice
      on invoice.id = job.invoice_id
     and invoice.tenant_id = job.tenant_id
    where job.tenant_id = p_tenant_id
      and (
        job.tax_treatment is distinct from invoice.tax_treatment
        or public.clp_round(job.tax_amount)
             is distinct from public.clp_round(invoice.iva_amount)
        or public.clp_round(job.total_cost)
             is distinct from public.clp_round(invoice.total)
        or job.is_paid is distinct from (
          lower(invoice.status) in ('paid', 'pagado', 'pagada')
        )
      )
  loop
    perform set_config('app.syncing_invoice_to_job', 'true', true);
    update public.mechanic_jobs
    set tax_treatment = v_job.tax_treatment,
        tax_amount = v_job.iva_amount,
        total_cost = v_job.total,
        is_invoiced = true,
        is_paid = v_job.is_paid,
        updated_at = clock_timestamp()
    where id = v_job.job_id and tenant_id = p_tenant_id;
    perform set_config('app.syncing_invoice_to_job', '', true);

    insert into public.workshop_financial_backfill_rows(
      run_id, tenant_id, job_id, invoice_id, entity_type,
      changed_fields, before_data, after_data
    )
    select
      v_run.id, p_tenant_id, v_job.job_id, v_job.invoice_id, 'mechanic_job',
      array['tax_treatment', 'tax_amount', 'total_cost', 'is_invoiced', 'is_paid'],
      v_job.before_data, to_jsonb(job)
    from public.mechanic_jobs job where job.id = v_job.job_id;
    v_changed_jobs := v_changed_jobs + 1;
  end loop;

  for v_payment in
    select
      payment.id as payment_id,
      payment.invoice_id,
      job.id as job_id,
      to_jsonb(payment) as before_data,
      invoice.tax_treatment,
      case when invoice.tax_treatment = 'tax_included'
        then public.clp_round(payment.amount / 1.19)
        else public.clp_round(payment.amount)
      end as expected_net,
      case when invoice.tax_treatment = 'tax_included'
        then public.clp_round(payment.amount)
               - public.clp_round(payment.amount / 1.19)
        else 0
      end as expected_iva
    from public.sales_payments payment
    join public.sales_invoices invoice
      on invoice.id = payment.invoice_id
     and invoice.tenant_id = payment.tenant_id
    join public.mechanic_jobs job
      on job.invoice_id = invoice.id
     and job.tenant_id = invoice.tenant_id
    where payment.tenant_id = p_tenant_id
      and payment.deleted_at is null
      and (
        payment.tax_treatment is distinct from invoice.tax_treatment
        or public.clp_round(payment.net_amount) is distinct from case
          when invoice.tax_treatment = 'tax_included'
            then public.clp_round(payment.amount / 1.19)
          else public.clp_round(payment.amount)
        end
        or public.clp_round(payment.iva_amount) is distinct from case
          when invoice.tax_treatment = 'tax_included'
            then public.clp_round(payment.amount)
                   - public.clp_round(payment.amount / 1.19)
          else 0
        end
      )
  loop
    select coalesce(jsonb_agg(to_jsonb(entry) order by entry.id), '[]'::jsonb)
    into v_payment_journal_before
    from public.journal_entries entry
    where entry.tenant_id = p_tenant_id
      and entry.source_module = 'sales_payments'
      and entry.source_reference = v_payment.payment_id::text;

    update public.sales_payments
    set tax_treatment = v_payment.tax_treatment,
        net_amount = v_payment.expected_net,
        iva_amount = v_payment.expected_iva
    where id = v_payment.payment_id and tenant_id = p_tenant_id;

    select coalesce(jsonb_agg(to_jsonb(entry) order by entry.id), '[]'::jsonb)
    into v_payment_journal_after
    from public.journal_entries entry
    where entry.tenant_id = p_tenant_id
      and entry.source_module = 'sales_payments'
      and entry.source_reference = v_payment.payment_id::text;

    if v_payment_journal_after is distinct from v_payment_journal_before then
      raise exception 'Payment journal changed during metadata-only repair for %.',
        v_payment.payment_id;
    end if;

    insert into public.workshop_financial_backfill_rows(
      run_id, tenant_id, job_id, invoice_id, payment_id, entity_type,
      changed_fields, before_data, after_data
    )
    select
      v_run.id, p_tenant_id, v_payment.job_id, v_payment.invoice_id,
      v_payment.payment_id, 'sales_payment',
      array['tax_treatment', 'net_amount', 'iva_amount'],
      v_payment.before_data, to_jsonb(payment)
    from public.sales_payments payment where payment.id = v_payment.payment_id;
    v_changed_payments := v_changed_payments + 1;
  end loop;

  for v_preview in
    select *
    from public.workshop_financial_backfill_preview preview
    where preview.tenant_id = p_tenant_id
      and preview.journal_repair_eligible
    order by preview.invoice_number
  loop
    select coalesce(jsonb_agg(
      jsonb_build_object(
        'entry', to_jsonb(entry),
        'lines', coalesce((
          select jsonb_agg(to_jsonb(line) order by line.id)
          from public.journal_lines line
          where line.entry_id = entry.id and line.tenant_id = entry.tenant_id
        ), '[]'::jsonb)
      ) order by entry.id
    ), '[]'::jsonb)
    into v_before
    from public.journal_entries entry
    where entry.tenant_id = p_tenant_id
      and entry.source_module = 'sales_invoices'
      and entry.source_reference in (
        v_preview.invoice_id::text,
        v_preview.invoice_number
      );

    delete from public.journal_entries entry
    where entry.tenant_id = p_tenant_id
      and entry.source_module = 'sales_invoices'
      and entry.source_reference in (
        v_preview.invoice_id::text,
        v_preview.invoice_number
      );

    select * into v_invoice
    from public.sales_invoices
    where id = v_preview.invoice_id and tenant_id = p_tenant_id;
    perform public.create_sales_invoice_journal_entry(v_invoice);

    select coalesce(jsonb_agg(
      jsonb_build_object(
        'entry', to_jsonb(entry),
        'lines', coalesce((
          select jsonb_agg(to_jsonb(line) order by line.id)
          from public.journal_lines line
          where line.entry_id = entry.id and line.tenant_id = entry.tenant_id
        ), '[]'::jsonb)
      ) order by entry.id
    ), '[]'::jsonb)
    into v_after
    from public.journal_entries entry
    where entry.tenant_id = p_tenant_id
      and entry.source_module = 'sales_invoices'
      and entry.source_reference in (
        v_preview.invoice_id::text,
        v_preview.invoice_number
      );

    if jsonb_array_length(v_after) <> 1 then
      raise exception 'Invoice journal repair did not produce exactly one entry for %.',
        v_preview.invoice_number;
    end if;

    insert into public.workshop_financial_backfill_rows(
      run_id, tenant_id, job_id, invoice_id, entity_type,
      changed_fields, before_data, after_data
    ) values (
      v_run.id, p_tenant_id, v_preview.job_id, v_preview.invoice_id,
      'sales_invoice_journal', array['journal_entry', 'journal_lines'],
      v_before, v_after
    );
    v_repaired_journals := v_repaired_journals + 1;
  end loop;

  for v_preview in
    select *
    from public.workshop_financial_backfill_preview preview
    where preview.tenant_id = p_tenant_id
      and preview.journal_requires_manual_review
    order by preview.invoice_number
  loop
    v_before := jsonb_build_object(
      'invoice_number', v_preview.invoice_number,
      'invoice_status', v_preview.invoice_status,
      'invoice_total', v_preview.invoice_total,
      'active_payment_count', v_preview.active_payment_count,
      'active_payment_sum', v_preview.active_payment_sum,
      'invoice_journal_count', v_preview.invoice_journal_count,
      'job_journal_count', v_preview.job_journal_count,
      'ar_debit', v_preview.ar_debit,
      'sales_credit', v_preview.sales_credit,
      'reason', 'legacy_unresolved'
    );
    insert into public.workshop_financial_backfill_rows(
      run_id, tenant_id, job_id, invoice_id, entity_type,
      changed_fields, before_data, after_data
    ) values (
      v_run.id, p_tenant_id, v_preview.job_id, v_preview.invoice_id,
      'legacy_unresolved', '{}', v_before, v_before
    );
    v_manual_review := v_manual_review + 1;
  end loop;

  select md5(coalesce(string_agg(
    jsonb_build_object(
      'id', movement.id,
      'product_id', movement.product_id,
      'quantity', movement.quantity,
      'reference', movement.reference,
      'date', movement.date,
      'stock_before', movement.stock_before,
      'stock_after', movement.stock_after
    )::text,
    '|' order by movement.id
  ), ''))
  into v_stock_fingerprint_after
  from public.stock_movements movement
  where movement.tenant_id = p_tenant_id;

  select md5(coalesce(string_agg(
    jsonb_build_object(
      'id', payment.id,
      'invoice_id', payment.invoice_id,
      'method', payment.payment_method_id,
      'amount', payment.amount,
      'date', payment.date,
      'deleted_at', payment.deleted_at
    )::text,
    '|' order by payment.id
  ), ''))
  into v_payment_financial_fingerprint_after
  from public.sales_payments payment
  where payment.tenant_id = p_tenant_id;

  select md5(coalesce(string_agg(
    jsonb_build_object(
      'id', invoice.id,
      'status', invoice.status,
      'tax_treatment', invoice.tax_treatment,
      'subtotal', invoice.subtotal,
      'net_amount', invoice.net_amount,
      'iva_amount', invoice.iva_amount,
      'total', invoice.total,
      'paid_amount', invoice.paid_amount,
      'balance', invoice.balance,
      'items', invoice.items
    )::text,
    '|' order by invoice.id
  ), ''))
  into v_invoice_fingerprint_after
  from public.sales_invoices invoice
  where invoice.tenant_id = p_tenant_id;

  if v_stock_fingerprint_after is distinct from v_stock_fingerprint_before then
    raise exception 'Workshop financial backfill changed stock evidence.';
  end if;
  if v_payment_financial_fingerprint_after
       is distinct from v_payment_financial_fingerprint_before then
    raise exception 'Workshop financial backfill changed cash settlement.';
  end if;
  if v_invoice_fingerprint_after is distinct from v_invoice_fingerprint_before then
    raise exception 'Workshop financial backfill changed invoice financial truth.';
  end if;

  v_summary := jsonb_build_object(
    'run_id', v_run.id,
    'tenant_id', p_tenant_id,
    'batch_key', v_key,
    'changed_jobs', v_changed_jobs,
    'changed_payments', v_changed_payments,
    'repaired_invoice_journals', v_repaired_journals,
    'legacy_unresolved', v_manual_review,
    'stock_unchanged', true,
    'cash_settlement_unchanged', true,
    'invoice_truth_unchanged', true,
    'replayed', false
  );

  update public.workshop_financial_backfill_runs
  set status = 'completed',
      completed_at = clock_timestamp(),
      summary = v_summary
  where id = v_run.id;

  return v_summary;
exception
  when others then
    perform set_config('app.syncing_invoice_to_job', '', true);
    raise;
end;
$$;

revoke all on function public.apply_workshop_financial_backfill(uuid, text)
  from public, anon, authenticated, service_role;

comment on function public.apply_workshop_financial_backfill(uuid, text) is
  'Database-admin-only explicit repair. Mirrors invoice truth, preserves cash and stock fingerprints, repairs only fully paid deterministic invoice journals, and records ambiguous legacy rows unchanged.';

commit;
