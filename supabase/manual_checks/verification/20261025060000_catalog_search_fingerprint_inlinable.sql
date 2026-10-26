-- Read-back of 20261025060000_catalog_search_fingerprint_inlinable.sql (plain
-- SQL, no transaction control: it runs through the read-only hosted wrapper).

select
  p.provolatile = 's' as stable,
  p.proconfig is null as without_set,
  not has_function_privilege('anon', p.oid, 'execute') as closed_to_anon
from pg_proc p
where p.oid = 'public.catalog_search_source_md5_v1(public.products)'::regprocedure;

-- Inlinable, and the same fingerprint: the documents built before still
-- match (a product edited this minute may wait for the next refresh).
select 1 / (
  case when (
      select p.provolatile = 's' and p.proconfig is null
      from pg_proc p
      where p.oid = 'public.catalog_search_source_md5_v1(public.products)'::regprocedure
    )
    and (
      select count(d.product_id)::numeric / nullif(count(*), 0)
      from public.products p
      left join public.catalog_search_documents d
        on d.tenant_id = p.tenant_id and d.product_id = p.id
       and d.version = 1 and d.source_md5 = public.catalog_search_source_md5_v1(p)
      where p.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
        and p.is_active
        and coalesce(p.is_published, false)
        and coalesce(p.show_on_website, false)
    ) >= 0.99
  then 1 else 0 end
) as afirma_la_huella_se_incrusta_y_calza;
