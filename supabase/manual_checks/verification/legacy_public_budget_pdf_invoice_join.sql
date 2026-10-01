-- Read-only aggregate ownership lead for legacy PDFs created by the old
-- chat-window path `presupuestos/presupuesto_<invoice_number>_<epoch_ms>.pdf`.
-- No object name, invoice number, invoice row, tenant ID, URL or byte returns.
with pdfs as (
  select
    substring(
      o.name from '^presupuestos/presupuesto_(.*)_[0-9]{13}\.pdf$'
    ) as invoice_number
  from storage.objects o
  where o.bucket_id = 'vinabike-assets'
    and split_part(o.name, '/', 1) = 'presupuestos'
), resolved as (
  select
    p.invoice_number is not null as matches_legacy_path,
    coalesce(i.invoice_rows, 0) as invoice_rows,
    coalesce(i.tenants, 0) as tenants
  from pdfs p
  left join lateral (
    select count(*) as invoice_rows, count(distinct si.tenant_id) as tenants
    from public.sales_invoices si
    where si.invoice_number = p.invoice_number
  ) i on true
)
select
  count(*) as pdf_objects,
  count(*) filter (where matches_legacy_path) as legacy_path_shape,
  count(*) filter (where not matches_legacy_path) as other_path_shape,
  count(*) filter (where invoice_rows = 1 and tenants = 1)
    as unique_invoice_tenant,
  count(*) filter (where invoice_rows > 1 or tenants > 1)
    as ambiguous_invoice,
  count(*) filter (where invoice_rows = 0) as no_current_invoice_match
from resolved;
