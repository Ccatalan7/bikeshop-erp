-- Preguntas vivas de «Configurar» para refrescar
-- test/fixtures/bike_workshop/live_service_questions_<fecha>.json, que es lo
-- que compara test/unit/service_question_contract_test.dart. Lectura; se corre
-- con scripts/db/query.sh production --file <este archivo> --format csv.
-- Los perfiles y preguntas son plantillas globales (tenant_id null); el taller
-- se acota por sus mapeos activos.
with t as (
  select tenant_id from public.products where sku = 'NNV53' limit 1
),
p as (
  select distinct sp.id, sp.name, sp.service_family
  from public.service_profiles sp
  join public.service_product_profile_mappings m
    on m.service_profile_id = sp.id
   and m.status = 'active'
   and m.tenant_id = (select tenant_id from t)
)
select coalesce(json_agg(json_build_object(
  'profile', p.name,
  'family', p.service_family,
  'key', q.key,
  'type', q.question_type,
  'required', q.is_required,
  'options', (
    select coalesce(json_agg(o->>'value'), '[]'::json)
    from json_array_elements(q.options_json::json) o
  )
) order by p.name, q.sort_order), '[]'::json)::text as rows
from p
join public.service_profile_questions_resolved_v1 q
  on q.service_profile_id = p.id;
