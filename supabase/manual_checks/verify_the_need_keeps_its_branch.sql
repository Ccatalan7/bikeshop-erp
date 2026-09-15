-- Read-back: la necesidad deduce su rama cuando el modelo no la trae, y la
-- referencia explícita sigue mandando cuando existe.
select
  1 / (case when (
    select prosrc from pg_proc where proname = 'create_supply_need_batch_v2'
  ) like '%supply_need_category_for_phrase_internal_v1%' then 1 else 0 end)
    as deduce_la_rama,
  1 / (case when (
    select prosrc from pg_proc where proname = 'create_supply_need_batch_v2'
  ) like '%coalesce(%nullif(v_item ->> ''categoryId'', '''')::uuid,%'
    then 1 else 0 end) as la_explicita_manda,
  -- v3 delega en v2: si dejara de hacerlo, el arreglo no llegaría al módulo.
  1 / (case when (
    select prosrc from pg_proc where proname = 'create_supply_need_batch_v3'
  ) like '%create_supply_need_batch_v2%' then 1 else 0 end) as v3_delega;
