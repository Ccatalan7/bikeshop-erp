-- Read-only aggregate: after URL fields were removed from messaging metadata,
-- the display filename may still identify a sent budget. A filename match is
-- a lead only: it is not proof that the public object's bytes were delivered.
-- Returns no object path, filename, invoice number, message, or tenant ID.
with pdfs as materialized (
  select o.name,
    substring(o.name from '^presupuestos/presupuesto_(.*)_[0-9]{13}\.pdf$')
      as invoice_number
  from storage.objects o
  where o.bucket_id = 'vinabike-assets'
    and split_part(o.name, '/', 1) = 'presupuestos'
), matches as (
  select 'messages.filename' as source, p.name, m.tenant_id,
    m.external_status = 'accepted' as accepted
  from pdfs p
  join public.messages m
    on p.invoice_number is not null
   and lower(coalesce(m.metadata->>'document_filename',
     m.metadata->>'documentFilename', m.metadata->>'filename', '')) =
     lower('Presupuesto_' || p.invoice_number || '.pdf')
  union all
  select 'messaging_attachments.original_filename', p.name, a.tenant_id,
    a.status = 'attached'
  from pdfs p
  join public.messaging_attachments a
    on p.invoice_number is not null
   and lower(a.original_filename) =
     lower('Presupuesto_' || p.invoice_number || '.pdf')
)
select source, count(distinct name) as pdf_objects,
  count(*) as matching_rows, count(distinct tenant_id) as tenants,
  count(*) filter (where accepted) as accepted_or_attached_rows
from matches
group by source
union all
select 'no_filename_match', count(*)::bigint, 0::bigint, 0::bigint, 0::bigint
from pdfs p
where not exists (select 1 from matches m where m.name = p.name)
order by source;
