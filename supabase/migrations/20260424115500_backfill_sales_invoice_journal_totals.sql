-- Backfill sales-invoice journal header totals from balanced journal lines.
--
-- The line rows are the canonical accounting detail. Existing sales invoice
-- headers were missing cost-of-goods lines in total_debit/total_credit, while
-- the line entries themselves were balanced.

begin;

with line_totals as (
  select
    jl.entry_id,
    coalesce(sum(coalesce(jl.debit_amount, 0)), 0)::numeric(14, 2)
      as total_debit,
    coalesce(sum(coalesce(jl.credit_amount, 0)), 0)::numeric(14, 2)
      as total_credit
  from public.journal_lines jl
  group by jl.entry_id
)
update public.journal_entries je
   set total_debit = lt.total_debit,
       total_credit = lt.total_credit,
       updated_at = now()
  from line_totals lt
 where je.id = lt.entry_id
   and je.source_module = 'sales_invoices'
   and (
      abs(coalesce(je.total_debit, 0) - lt.total_debit) > 0.009
      or abs(coalesce(je.total_credit, 0) - lt.total_credit) > 0.009
    );

commit;
