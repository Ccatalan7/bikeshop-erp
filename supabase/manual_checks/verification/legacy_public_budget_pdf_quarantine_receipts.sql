-- Read-only aggregate: check whether the messaging migration preserved one
-- of these public PDFs by its versioned source-path hash. No path/hash/byte
-- or business row is returned; absence here is not proof of no delivery.
with pdfs as (
  select o.name
  from storage.objects o
  where o.bucket_id = 'vinabike-assets'
    and split_part(o.name, '/', 1) = 'presupuestos'
), receipts as (
  select p.name, r.source_path_sha256 is not null as has_receipt,
    r.deleted_from_public_at is not null as marked_deleted,
    q.name is not null as quarantine_object_exists
  from pdfs p
  left join public.messaging_legacy_orphan_quarantine_receipts r
    on r.source_path_sha256 = encode(extensions.digest(
      convert_to('vinabike-public-orphan-path-v1:' || p.name, 'UTF8'),
      'sha256'), 'hex')
  left join storage.objects q
    on q.bucket_id = r.quarantine_bucket and q.name = r.quarantine_path
)
select count(*) as public_pdfs,
  count(*) filter (where has_receipt) as with_quarantine_receipt,
  count(*) filter (where quarantine_object_exists) as with_private_copy,
  count(*) filter (where marked_deleted) as marked_public_deleted
from receipts;
