-- Read-back: el resolvedor existe, no está expuesto, y conserva los cuatro
-- escalones. La rama NUNCA se suelta.
select
  1 / (case when exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'purchase_query_products_internal_v1'
  ) then 1 else 0 end) as existe,
  1 / (case when not has_function_privilege('authenticated',
    'public.purchase_query_products_internal_v1(uuid,text,boolean)', 'execute')
    then 1 else 0 end) as no_expuesto,
  1 / (case when (
    select prosrc from pg_proc
    where proname = 'purchase_query_products_internal_v1'
  ) like '%for v_attempt in 1..4 loop%' then 1 else 0 end) as cuatro_escalones,
  1 / (case when (
    select prosrc from pg_proc
    where proname = 'purchase_query_products_internal_v1'
  ) not like '%v_inferred_categories := null%' then 1 else 0 end)
    as la_rama_no_se_suelta;
