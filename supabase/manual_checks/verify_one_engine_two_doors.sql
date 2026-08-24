-- Read-back: un solo motor, dos puertas, y el motor no queda expuesto.
select
  1 / (case when (
    select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'purchase_supplier_concentration_internal_v1'
  ) = 1 then 1 else 0 end) as motor_unico,
  1 / (case when not has_function_privilege('authenticated',
    'public.purchase_supplier_concentration_internal_v1(uuid,text,text,text,integer)',
    'execute') then 1 else 0 end) as motor_no_expuesto,
  -- Las dos puertas delegan: si alguna volviera a traer el análisis adentro,
  -- quedarían dos verdades que se separan en el primer arreglo.
  1 / (case when (
    select prosrc from pg_proc
    where proname = 'assistant_rank_purchase_suppliers_v1'
  ) like '%purchase_supplier_concentration_internal_v1%' then 1 else 0 end)
    as puerta_ia_delega,
  1 / (case when (
    select prosrc from pg_proc
    where proname = 'rank_purchase_suppliers_v1'
  ) like '%purchase_supplier_concentration_internal_v1%' then 1 else 0 end)
    as puerta_modulo_delega,
  -- La puerta del módulo NO exige la capacidad del asistente: un operador de
  -- compras no tiene por qué tenerla.
  1 / (case when (
    select prosrc from pg_proc
    where proname = 'rank_purchase_suppliers_v1'
  ) not like '%assistant_require_capability%' then 1 else 0 end)
    as modulo_sin_capacidad_de_ia,
  1 / (case when has_function_privilege('authenticated',
    'public.rank_purchase_suppliers_v1(text,text,text,integer)',
    'execute') then 1 else 0 end) as modulo_ejecuta;
