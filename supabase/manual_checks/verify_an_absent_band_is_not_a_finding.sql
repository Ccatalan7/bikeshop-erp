-- Read-back: sin ninguna banda derivada, la mezcla viaja nula.
select
  1 / (case when (
    select prosrc from pg_proc
    where proname = 'assistant_rank_purchase_suppliers_v1'
  ) like '%when gama_alta + gama_media + gama_economica = 0 then null%'
    then 1 else 0 end) as mezcla_vacia_se_calla,
  1 / (case when (
    select prosrc from pg_proc
    where proname = 'assistant_rank_purchase_suppliers_v1'
  ) like '%sin banda %' then 1 else 0 end) as salvedad_se_conserva;
