-- Read-back de `20260831220000_paging_counts_the_reviewed_set`.

-- 1. La paginación de la resolución v1 cuenta lo revisado, con respaldo para un
--    bundle anterior que todavía no publique `reviewed`.
select 1 / (
  case when pg_get_functiondef(oid) like '%''counts'' ->> ''reviewed''%'
       then 1 else 0 end
) as la_pagina_cuenta_lo_revisado
from pg_proc where proname = 'get_supply_need_stock_resolution_v1';

-- 2. El camino de candidatos revalida ANTES de buscar el candidato: una
--    necesidad sin candidatos debe decir su causa real, no «no encontrado».
-- Se compara contra la BÚSQUEDA del candidato, no contra la primera aparición
-- del nombre: la primera es la declaración del `rowtype`, que va arriba de todo
-- y hacía pasar la comprobación por el motivo equivocado.
select 1 / (
  case when position('supply_need_choice_is_checked_internal_v1' in prosrc)
            < position('from public.purchase_candidate_metrics_v1' in prosrc)
       then 1 else 0 end
) as la_causa_real_se_dice_primero
from pg_proc where proname = 'prepare_purchase_plan_line_v1';

-- 3. **Sobre la necesidad real de pastillas**: paginar de a uno sigue diciendo
--    que hay más mientras queden filas revisadas por entregar.
with r as (
  select public.supply_need_stock_bundle_internal_v1(
    '5443b130-cc28-45af-a420-cd500b288890'::uuid,
    'b9484ed6-52d8-45cb-8b50-540caabf1d4e'::uuid, 400) as b
)
select 1 / (
  case when (r.b #>> '{counts,reviewed}')::int
            > (r.b #>> '{counts,eligible}')::int
        and jsonb_array_length(r.b -> 'orderedItems')
            = (r.b #>> '{counts,reviewed}')::int
       then 1 else 0 end
) as lo_entregado_es_lo_revisado
from r;
