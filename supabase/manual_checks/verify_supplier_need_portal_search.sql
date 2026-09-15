select
  supplier.name,
  probe.is_enabled,
  probe.need_search_term_limit,
  probe.need_search_url_template
from public.supplier_portal_probes probe
join public.suppliers supplier on supplier.id = probe.supplier_id
where supplier.name = 'RBX';

select
  1 / (case when exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'supplier_portal_probes'
      and column_name = 'need_search_url_template'
  ) then 1 else 0 end) as probe_admite_busqueda_de_necesidad,
  1 / (case when to_regclass('public.supplier_need_portal_searches') is not null
    then 1 else 0 end) as historial_existe,
  1 / (case when to_regprocedure(
    'public.record_supplier_need_portal_search_v1(uuid,uuid,text,text,text,jsonb,jsonb)'
  ) is not null then 1 else 0 end) as escritura_guardada_existe,
  1 / (case when to_regprocedure(
    'public.supplier_last_need_portal_search_v1(uuid,uuid)'
  ) is not null then 1 else 0 end) as lectura_guardada_existe,
  1 / (case when exists (
    select 1
    from public.supplier_portal_probes probe
    join public.suppliers supplier on supplier.id = probe.supplier_id
    where supplier.name = 'RBX'
      and probe.is_enabled
      and probe.need_search_term_limit = 15
      and probe.need_search_url_template like '%cat_pal_sf.asp%'
      and probe.need_search_url_template like '%{query}%'
  ) then 1 else 0 end) as rbx_busca_por_palabra;
