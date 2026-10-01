-- Read-only aggregate lookup for the eight legacy budget PDFs in messaging
-- receipts that the first asset inventory did not scan. No URL, object name,
-- message, user, phone, invoice number, or tenant ID is returned.
with pdfs as materialized (
  select o.name
  from storage.objects o
  where o.bucket_id = 'vinabike-assets'
    and split_part(o.name, '/', 1) = 'presupuestos'
), hits as (
  select 'messages.metadata' as source, p.name, m.tenant_id,
    m.external_status = 'accepted' as accepted
  from pdfs p
  join public.messages m
    on position(p.name in coalesce(m.metadata::text, '')) > 0
      or position(replace(p.name, ' ', '%20') in coalesce(m.metadata::text, '')) > 0
  union all
  select 'messages.content', p.name, m.tenant_id,
    m.external_status = 'accepted'
  from pdfs p
  join public.messages m
    on position(p.name in coalesce(m.content, '')) > 0
      or position(replace(p.name, ' ', '%20') in coalesce(m.content, '')) > 0
  union all
  select 'whatsapp_outbox.request', p.name, w.tenant_id,
    w.state = 'accepted'
  from pdfs p
  join public.whatsapp_outbox w
    on position(p.name in w.request::text) > 0
      or position(replace(p.name, ' ', '%20') in w.request::text) > 0
)
select source, count(distinct name) as pdf_objects,
  count(*) as matching_rows,
  count(distinct tenant_id) as tenants,
  count(*) filter (where accepted) as accepted_rows
from hits
group by source
union all
select 'no_match_in_these_receipts', count(*)::bigint, 0::bigint,
  0::bigint, 0::bigint
from pdfs p
where not exists (select 1 from hits h where h.name = p.name)
order by source;
