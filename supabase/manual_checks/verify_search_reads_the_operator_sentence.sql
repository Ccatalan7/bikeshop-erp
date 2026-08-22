-- Read-back: el servidor traduce la frase del operador a predicados reales.
with t as (
  select tenant_id tid
  from public.product_categories
  where public.assistant_normalize_query_internal_v1(full_path)
    = 'componentes transmision motores'
  limit 1
), frase as (
  select public.assistant_infer_technical_predicates_internal_v1(
    t.tid, 'dame los motores de caja BSA con ancho de caja 68 y largo de eje 118'
  ) r from t
), medida as (
  select public.assistant_infer_technical_predicates_internal_v1(
    t.tid, 'necesito un motor con largo de eje 122.5'
  ) r from t
), ajena as (
  select public.assistant_infer_technical_predicates_internal_v1(
    t.tid, 'hola necesito ayuda con una boleta'
  ) r from t
), campos as (
  select array_agg(p.value ->> 'field' order by p.value ->> 'field') f,
    array_agg(p.value -> 'values' order by p.value ->> 'field')::text[] v
  from frase, jsonb_array_elements(frase.r -> 'predicates') p(value)
)
select
  -- Tres predicados, los tres campos que el operador nombró.
  1 / (case when (select f from campos)
    = array['bb_shell_standard', 'bb_shell_width_mm', 'spindle_length_mm']
    then 1 else 0 end) as tres_campos,
  -- Los números amarrados a su campo, no cruzados.
  1 / (case when (select v from campos)[2] = '[68]'
    and (select v from campos)[3] = '[118]' then 1 else 0 end) as numeros_correctos,
  -- «dame» y «los» no sobreviven como texto libre: matarían el resultado.
  1 / (case when (select r ->> 'residual' from frase) not like '%dame%'
    then 1 else 0 end) as sin_verbo_de_peticion,
  -- Un decimal se lee entero pese a que el normalizador borra el punto.
  1 / (case when (select r -> 'predicates' from medida)
    @> '[{"field":"spindle_length_mm","operator":"eq","values":[122.5]}]'::jsonb
    then 1 else 0 end) as decimal_intacto,
  -- Una frase ajena al catálogo no inventa filtros.
  1 / (case when jsonb_array_length(
    (select r -> 'predicates' from ajena)
  ) = 0 then 1 else 0 end) as sin_falsos_positivos;
