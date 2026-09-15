-- Read-back: el escalón final exige palabra completa y admite tres letras.
select
  1 / (case when (
    select prosrc from pg_proc
    where proname = 'purchase_supplier_concentration_internal_v1'
  ) like '%like ''%% '' || token || '' %%''%' then 1 else 0 end) as palabra_completa,
  1 / (case when (
    select prosrc from pg_proc
    where proname = 'purchase_supplier_concentration_internal_v1'
  ) like '%length(token) >= 3%' then 1 else 0 end) as admite_aro,
  1 / (case when (
    select prosrc from pg_proc
    where proname = 'purchase_supplier_concentration_internal_v1'
  ) not like '%length(token) >= 4%' then 1 else 0 end) as sin_corte_viejo;
