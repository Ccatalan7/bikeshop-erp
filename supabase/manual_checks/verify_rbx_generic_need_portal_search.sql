select
  1 / (case when exists (
    select 1
    from public.supplier_portal_probes probe
    join public.suppliers supplier on supplier.id = probe.supplier_id
    where supplier.name = 'RBX'
      and supplier.tenant_id = probe.tenant_id
      and probe.is_enabled
      and probe.need_search_url_template like '%{query}%'
      and probe.need_search_adapter->>'version' = '1'
      and probe.need_search_adapter->'generic_family_search' = 'true'::jsonb
      and probe.need_search_adapter#>>'{families,bottom_bracket,identity_family}'
        = 'bottom_bracket'
  ) then 1 else 0 end) as rbx_generic_need_search_enabled_without_losing_native_family;
