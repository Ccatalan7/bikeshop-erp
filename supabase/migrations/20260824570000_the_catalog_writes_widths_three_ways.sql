-- El catálogo escribe el ancho de tres formas, no una.
--
-- La primera pasada dejó 112 de 134 cámaras con ancho. Las 22 que faltaban no
-- eran nombres pobres: eran tres convenciones que no había considerado.
--
--   1. **Fracción**: «CAMARA 24 X 1.3/8» es 1‑3/8 de pulgada = 1.375, no «1,3 a
--      8». Y «12 1/2 X 2.1/4» es 2¼". Es la notación de todo el catálogo
--      chileno para las medidas viejas de aro.
--   2. **Ancho único**: «700X28C» y «ARO 29 X 1.95C» declaran UN ancho, no un
--      rango. Se guarda mínimo = máximo: es el único ancho que el nombre dice, y
--      guardarlo es mejor que dejar la cámara sin medida.
--   3. **El signo `×`**: «20×1.5/2.5» usa U+00D7, no la letra X. Perdía el
--      nombre completo.
--
-- Con eso el ancho pasa de 112 a 126 de 134.
--
-- La fracción se resuelve ANTES del rango, pero sólo si es una fracción de
-- verdad —numerador menor que denominador y denominador potencia de dos—. Sin
-- ese guarda, «1.5/2.5» se leía como 1 + 5/2 = 3.5.
--
-- Nada se sobrescribe: sólo se llenan las cámaras que quedaron sin ancho.

begin;

create temporary table tube_width_pass2 on commit drop as
with camaras as (
  select id, name,
    upper(translate(name, 'ÁÉÍÓÚÜÑáéíóúüñ×', 'AEIOUUNaeiouunX')) n
  from public.products
  where tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
    and is_active and (name ilike 'camara%' or name ilike 'cámara%')
), p as (
  select id, name,
    (n ~ '\y700\y|700\s*X') es_ruta,
    (regexp_match(n, 'X\s*([0-9])\.([0-9])\s*/\s*([0-9])\y'))[1]::numeric fr_ent,
    (regexp_match(n, 'X\s*([0-9])\.([0-9])\s*/\s*([0-9])\y'))[2]::numeric fr_num,
    (regexp_match(n, 'X\s*([0-9])\.([0-9])\s*/\s*([0-9])\y'))[3]::numeric fr_den,
    -- El rango, ahora también cuando no hay X delante: «Aro 24 1.95/2.125».
    replace((regexp_match(n,
      '(?:X|ARO\s*[0-9.,]+)\s*([0-9]+(?:[.,][0-9]+)?)\s*C?\s*(?:/|-|–|\sA\s)\s*([0-9]+(?:[.,][0-9]+)?)'))[1],
      ',', '.')::numeric rmin,
    replace((regexp_match(n,
      '(?:X|ARO\s*[0-9.,]+)\s*([0-9]+(?:[.,][0-9]+)?)\s*C?\s*(?:/|-|–|\sA\s)\s*([0-9]+(?:[.,][0-9]+)?)'))[2],
      ',', '.')::numeric rmax,
    replace((regexp_match(n, 'X\s*([0-9]+[.,][0-9]+|[0-9]{2})\s*C?\s*(?:$|[^0-9/.,-])'))[1],
      ',', '.')::numeric unico
  from camaras
)
select id, name, es_ruta,
  coalesce(case when fr_num < fr_den and fr_den in (2,4,8,16)
                then fr_ent + fr_num/fr_den end, rmin, unico) wmin,
  coalesce(case when fr_num < fr_den and fr_den in (2,4,8,16)
                then fr_ent + fr_num/fr_den end, rmax, unico) wmax
from p;

insert into public.spec_facts (
  tenant_id, subject_type, subject_id, spec_definition_id,
  value_number, source, confirmed
)
select '5443b130-cc28-45af-a420-cd500b288890', 'product', t.id, definition.id,
  s.valor, 'supplier_text', false
from tube_width_pass2 t
cross join lateral (values
  ('tube_width_min_in', case when not t.es_ruta then t.wmin end),
  ('tube_width_max_in', case when not t.es_ruta then t.wmax end),
  ('tube_width_min_mm', case when t.es_ruta then t.wmin end),
  ('tube_width_max_mm', case when t.es_ruta then t.wmax end)
) as s(key, valor)
join public.spec_definitions definition
  on definition.tenant_id is null and definition.key = s.key
where s.valor is not null
  and t.wmax >= t.wmin
  and case when t.es_ruta then t.wmin >= 10 and t.wmax <= 120
           else t.wmin >= 0.5 and t.wmax <= 3.5 end
  and not exists (
    select 1 from public.spec_facts existente
    where existente.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
      and existente.subject_type = 'product'
      and existente.subject_id = t.id
      and existente.spec_definition_id = definition.id
  );

commit;
