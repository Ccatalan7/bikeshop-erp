select
  1 / (case when exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'supplier_portal_probes'
      and column_name = 'need_search_adapter'
      and data_type = 'jsonb'
  ) then 1 else 0 end) as adapter_column_exists,
  1 / (case when exists (
    select 1
    from public.supplier_portal_probes probe
    join public.suppliers supplier on supplier.id = probe.supplier_id
    where supplier.name = 'RBX'
      and probe.is_enabled
      and probe.need_search_adapter->>'version' = '1'
      and probe.need_search_adapter#>>'{families,bottom_bracket,identity_family}'
        = 'bottom_bracket'
      and jsonb_array_length(
        probe.need_search_adapter#>'{families,bottom_bracket,navigation}'
      ) = 2
      and probe.need_search_adapter#>>'{result_schema,columns,code,0}'
        = 'Código'
  ) then 1 else 0 end) as rbx_adapter_is_configured,
  1 / (case when has_function_privilege(
    'authenticated',
    'public.record_supplier_need_portal_search_v1(uuid,uuid,text,text,text,jsonb,jsonb)',
    'execute'
  ) then 1 else 0 end) as guarded_write_is_executable,
  1 / (case when not has_table_privilege(
    'authenticated', 'public.supplier_need_portal_searches', 'insert'
  ) then 1 else 0 end) as direct_insert_stays_revoked;
