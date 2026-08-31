-- ¿La corrida del portal quedó registrada de verdad?
--
-- Es la comprobación que cierra el bloque: no basta con que la lectura se vea
-- en pantalla —eso ya pasaba— sino que quede **persistida con su clave de
-- operación**, para que un reintento no la duplique y una caída no la pierda.
--
-- Falla antes de que exista una corrida con clave: cada aserción divide por
-- cero cuando no se cumple.

-- 1. Hay al menos una lectura guardada con clave de operación.
select 1 / (
  case when count(*) >= 1 then 1 else 0 end
) as hay_corrida_con_clave
from public.supplier_need_portal_searches
where operation_key is not null;

-- 2. La más reciente con clave: qué es y qué trajo.
select
  s.name as proveedor,
  left(n.original_description, 34) as necesidad,
  r.checked_at,
  r.status,
  jsonb_array_length(r.results) as filas,
  (
    select count(*) from jsonb_array_elements(r.results) m
    where m ->> 'matchState' = 'exact'
  ) as exactas,
  (
    select count(*) from jsonb_array_elements(r.results) m
    where m ->> 'matchState' = 'conflict'
  ) as contradichas,
  r.coverage ->> 'method' as metodo,
  left(r.operation_key, 24) || '…' as clave
from public.supplier_need_portal_searches r
join public.suppliers s on s.id = r.supplier_id
left join public.supply_needs n on n.id = r.supply_need_id
where r.operation_key is not null
order by r.checked_at desc
limit 3;

-- 3. **Ninguna clave se guardó dos veces.** Es el punto de todo el bloque: un
--    reintento sobre un resultado desconocido no puede duplicar el recibo.
select 1 / (
  case when count(*) = 0 then 1 else 0 end
) as ninguna_clave_duplicada
from (
  select tenant_id, operation_key
  from public.supplier_need_portal_searches
  where operation_key is not null
  group by 1, 2
  having count(*) > 1
) duplicadas;

-- 4. Y la huella de la petición viaja con el recibo, que es lo que permite
--    distinguir un reintento de una reutilización indebida de la clave.
select 1 / (
  case when count(*) = 0 then 1 else 0 end
) as toda_clave_trae_su_peticion
from public.supplier_need_portal_searches
where operation_key is not null
  and operation_request is null;
