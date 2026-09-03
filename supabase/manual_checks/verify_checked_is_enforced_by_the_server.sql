-- Read-back de `20260831210000_checked_is_enforced_by_the_server`.

-- 1. La confirmación exige lista positiva, no la compuerta vacía de `conflict`.
select 1 / (
  case when pg_get_functiondef(oid) like
         '%not in (''strong'', ''weak'', ''no_criteria'')%'
       then 1 else 0 end
) as confirmar_exige_comprobado
from pg_proc where proname = 'confirm_supply_need_family_choice_v1';

-- 2. Los dos caminos del plan revalidan la identidad vigente.
select 1 / (
  case when count(*) = 2 then 1 else 0 end
) as los_dos_caminos_del_plan_revalidan
from pg_proc
where proname in ('prepare_purchase_plan_line_v1', 'prepare_purchase_plan_product_v1')
  and pg_get_functiondef(oid) like '%supply_need_choice_is_checked_internal_v1%';

-- 3. El replay idempotente sigue **antes** de la revalidación en las tres:
--    reintentar una escritura ya hecha no puede fallar por una regla nueva.
select 1 / (
  case when count(*) = 3 then 1 else 0 end
) as el_recibo_manda_antes_que_la_regla
from pg_proc
where proname in (
    'confirm_supply_need_family_choice_v1',
    'prepare_purchase_plan_line_v1',
    'prepare_purchase_plan_product_v1')
  and position('operation_key = v_operation_key' in pg_get_functiondef(oid)) > 0
  and position('operation_key = v_operation_key' in pg_get_functiondef(oid))
      < position('comprobado contra los criterios' in
          replace(pg_get_functiondef(oid),
                  'supply_need_choice_is_checked_internal_v1',
                  'comprobado contra los criterios'));

-- 4. El ayudante existe, es estable y no queda expuesto a cualquiera.
select 1 / (
  case when count(*) = 1 then 1 else 0 end
) as el_ayudante_es_estable_y_definido
from pg_proc
where proname = 'supply_need_choice_is_checked_internal_v1'
  and provolatile = 's' and prosecdef is true;

-- 5. **Sobre datos reales**: el producto que la pantalla ya no ofrece tampoco
--    lo acepta el servidor, y uno comprobado sí. Se usa la necesidad real de
--    pastillas, donde 47 de 49 filas están sin verificar.
with alcance as (
  select n.id as need_id, n.tenant_id,
    public.supply_need_eligible_products_internal_v1(n.tenant_id, n.id) as r
  from public.supply_needs n
  where n.id = 'b9484ed6-52d8-45cb-8b50-540caabf1d4e'
), filas as (
  select a.tenant_id, a.need_id,
    (i.value ->> 'productId')::uuid as product_id,
    i.value ->> 'matchState' as estado
  from alcance a, jsonb_array_elements(a.r -> 'items') i(value)
)
select 1 / (
  case when count(*) filter (
    where public.supply_need_choice_is_checked_internal_v1(
            tenant_id, need_id, product_id) is distinct from estado
  ) = 0 and count(*) filter (where estado = 'unverified') > 0
       then 1 else 0 end
) as el_estado_vigente_es_el_que_juzga
from filas;
