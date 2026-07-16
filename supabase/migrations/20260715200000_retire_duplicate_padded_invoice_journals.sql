-- Deployment status: DEPLOYED to production project xzdvtzdqjeyqxnkqprtf
-- on 2026-07-15. Seven duplicate headers (CLP 138,093 per side) were removed
-- from the live ledger after seven full immutable snapshots were captured;
-- two deleted-source orphan journals remain manual review.
-- Seven legacy invoice journals used an extra zero in their display reference
-- and survived later journal recreation. Each source invoice now has exactly
-- one UUID-owned journal with the same accounting effect. Delete only the
-- proven duplicate headers; the existing before-delete trigger preserves the
-- complete header and line snapshots in journal_supersession_evidence.
begin;

select set_config(
  'app.journal_supersession_reason',
  'duplicate_legacy_padded_invoice_journal_replaced_by_uuid_owner',
  true
);

with proven_duplicate(orphan_entry_id, invoice_id, orphan_reference) as (
  values
    ('49c176cd-4413-478b-af42-0394cf3bac9c'::uuid,
     'b37f70b9-2177-49bd-8f96-b949cced0dc3'::uuid, 'FV-000358'::text),
    ('ed379158-ea59-4132-8164-44d4fe7fa238'::uuid,
     'b3ffcccf-46b0-45a6-9f01-683a12eb313e'::uuid, 'FV-000359'::text),
    ('87869a5d-dab3-4d40-af34-e670ca4a50e1'::uuid,
     'c51a359d-9408-477c-96d2-2164f63b01a9'::uuid, 'FV-000362'::text),
    ('90b87330-7bcc-400a-9b19-3623d6f22f2c'::uuid,
     'a0f9a9d2-fe2f-4c7d-b62b-047c17e8c0c2'::uuid, 'FV-000363'::text),
    ('4e4da7cf-a7c8-4e88-9868-97116db29d01'::uuid,
     'c4f377f4-9848-44a4-9549-6fce7183676d'::uuid, 'FV-000364'::text),
    ('c37dba89-4200-450e-b90d-eeaea6eaec7f'::uuid,
     '82330e0f-9408-46a5-a95c-8979c9b2b058'::uuid, 'FV-000368'::text),
    ('a4106793-c765-486e-84a0-c64440e3e006'::uuid,
     'eda3aade-59da-4fbc-92e8-6bfdcc4a4ed6'::uuid, 'FV-000369'::text)
), eligible as (
  select duplicate.orphan_entry_id
  from proven_duplicate duplicate
  join public.journal_entries orphan
    on orphan.id = duplicate.orphan_entry_id
   and orphan.source_module = 'sales_invoices'
   and orphan.source_document_id is null
   and orphan.source_reference = duplicate.orphan_reference
   and lower(coalesce(orphan.status, '')) = 'posted'
  join public.sales_invoices invoice
    on invoice.id = duplicate.invoice_id
   and invoice.tenant_id = orphan.tenant_id
   and regexp_replace(invoice.invoice_number, '^FV-0*', '', 'i')
       = regexp_replace(duplicate.orphan_reference, '^FV-0*', '', 'i')
  where exists (
    select 1
    from public.journal_entries owner
    where owner.tenant_id = orphan.tenant_id
      and owner.source_module = 'sales_invoices'
      and owner.source_document_id = invoice.id
      and lower(coalesce(owner.status, '')) = 'posted'
  )
)
delete from public.journal_entries entry
using eligible
where entry.id = eligible.orphan_entry_id;

commit;
