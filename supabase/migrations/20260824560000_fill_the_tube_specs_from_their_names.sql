-- Llenar la ficha de las 134 cámaras leyendo su nombre.
--
-- Hoy 4 de 134 tienen ficha: 3%. Los nombres sí traen los datos —«CAMARA 29 X
-- 1.75/2.35 V/AMERICANA 48mm»— y lo único que faltaba era leerlos.
--
-- **La regla: sólo se escribe lo que el nombre dice.** Vacío es mejor que
-- equivocado, y una ficha inventada es peor que ninguna porque nadie vuelve a
-- revisarla. Todo entra con `confirmed = false`, así que ninguna parece
-- verificada por un mecánico, y **nunca se sobrescribe un hecho existente**:
-- lo que ya está pudo confirmarlo una persona.
--
-- El vocabulario de `source` distingue exactamente lo que hay que distinguir:
--
--   * `supplier_text` — leído del nombre del proveedor. Rueda, válvula, ancho,
--     largo, y el sellante cuando el nombre lo declara.
--   * `inferred` — deducido. El material de las que no lo dicen (butilo) y el
--     «sin sellante» de las que no lo mencionan.
--
-- Por qué el sellante se puede deducir y el largo de válvula no: **una cámara
-- con líquido siempre se vende diciéndolo** —es lo que justifica el precio—, así
-- que el silencio es evidencia. En cambio una cámara tiene un largo de válvula
-- exista o no en su nombre, así que ahí el silencio sólo dice que nadie lo
-- escribió. Corroborado: 8 lo declaran en el nombre, la categoría
-- «Cámaras Anti-Pinchazo» tiene 4, y esas 4 están entre las 8. Cero desacuerdo.
--
-- Un producto que no entrega NINGUNA medida no recibe ficha: «Cámara nueva +
-- servicio de cambio» es un servicio, no una cámara.

begin;

-- El vocabulario primero: 33 mm y 52 mm existen en el catálogo real y no
-- estaban en la lista. Sin esto, cinco cámaras perderían su largo en silencio.
insert into public.spec_definition_values (
  tenant_id, spec_definition_id, code, label, sort_order, is_active
)
select null, definition.id, entry.code, entry.label, entry.sort_order, true
from public.spec_definitions definition
cross join (values ('v_33', '33', 5), ('v_52', '52', 45)) as entry(code, label, sort_order)
where definition.key = 'valve_length_mm'
  and not exists (
    select 1 from public.spec_definition_values existing
    where existing.spec_definition_id = definition.id
      and existing.code = entry.code
  );

update public.spec_definitions
set allowed_values = '["33", "35", "40", "44", "48", "52", "60", "80"]'::jsonb,
    updated_at = now()
where tenant_id is null and key = 'valve_length_mm';

create temporary table tube_parse on commit drop as
with camaras as (
  select id, name,
    upper(translate(name, 'ÁÉÍÓÚÜÑáéíóúüñ', 'AEIOUUNaeiouun')) n
  from public.products
  where tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
    and is_active and (name ilike 'camara%' or name ilike 'cámara%')
), parsed as (
  select id, name,
    case
      when n ~ '\y700\y|700\s*X' then '700c'
      when n ~ '\y650\s?B\y' then '650b'
      else coalesce(
        (regexp_match(n, '([0-9]{2}(?:[.,][0-9])?)\s*X\s*[0-9]'))[1],
        (regexp_match(n, 'ARO\s*([0-9]{2}(?:[.,][0-9])?)'))[1],
        -- «26''», «24"», «28"»: la marca de pulgada.
        (regexp_match(n, '([0-9]{2})\s*(?:''''|"|”)'))[1],
        (regexp_match(n, '\y(12|16|20|24|26|28|29)\s+[0-9]\s*/\s*[0-9]'))[1])
    end rueda,
    -- El rango va DESPUÉS de la X: en «12 1/2 X ...» ese 1/2 es la medida de
    -- rueda, no el ancho. Y así se esquivan los códigos ETRTO entre paréntesis.
    replace((regexp_match(n,
      'X\s*([0-9]+(?:[.,][0-9]+)?)\s*(?:/|-|–|\sA\s)\s*([0-9]+(?:[.,][0-9]+)?)'))[1],
      ',', '.')::numeric wmin,
    replace((regexp_match(n,
      'X\s*([0-9]+(?:[.,][0-9]+)?)\s*(?:/|-|–|\sA\s)\s*([0-9]+(?:[.,][0-9]+)?)'))[2],
      ',', '.')::numeric wmax,
    case
      -- Nomenclatura Maxxis: FV = French (Presta), SV = Schrader, L = Long.
      when n ~ 'FRANCESA|PRESTA|\yL?FV\y|\yL?FV[0-9]|\yL?FV[A-Z]|\yF\s*/\s*V\y|\yV\s*[/.]?\s*F\y'
        then 'presta'
      -- `AUTO(?!SELLANTE)`: «Autosellante» no dice nada de la válvula. Y el
      -- `\y` ANTES de la V es obligatorio: sin él, «cámara nueVA» se leía como
      -- Schrader y un servicio terminaba con ficha de producto.
      when n ~ 'AMERICANA|SCHRADER|AUTO(?!SELLANTE)|\yL?SV\y|\yL?SV[0-9]|\yVA\y|\yAV\y|\yA\s*/\s*V\y|\yV\s*[/.]?\s*A\y'
        then 'schrader'
      when n ~ 'DUNLOP|INGLESA' then 'dunlop'
      else null
    end valvula,
    (regexp_match(n, '([0-9]{2,3})\s*MM?\y'))[1]::int largo,
    n ~ 'LIQUIDO|SLIME|AUTOSELLANTE|ANTI.?PINCHAZO|IMPINCHABLE|FLAT ATTACK|SELLANTE'
      sellante,
    case when n ~ '\yTPU\y' then 'tpu'
         when n ~ 'LATEX' then 'latex'
         else 'butyl' end material,
    n ~ 'BUTYL|BUTILO|\yTPU\y|LATEX' material_declarado
  from camaras
)
select *,
  -- 28" es 700c: el mismo aro de 622 mm con otro nombre.
  case rueda
    when '700c' then 'v_700c' when '650b' then 'v_650b' when '28' then 'v_700c'
    when '12' then 'v_12' when '16' then 'v_16' when '20' then 'v_20'
    when '24' then 'v_24' when '26' then 'v_26' when '29' then 'v_29'
    when '27.5' then 'v_27_5' when '27,5' then 'v_27_5'
    else null end rueda_code,
  (rueda in ('700c', '650b', '28')) es_ruta,
  (rueda is not null or valvula is not null or wmin is not null) es_camara
from parsed;

-- 1. Las selecciones: el hecho va sin escalar y su valor es una fila en
--    `spec_fact_values`, que es como el motor guarda una selección.
with objetivo as (
  select t.id product_id, s.key, s.code, s.source
  from tube_parse t
  cross join lateral (values
    ('wheel_size', t.rueda_code, 'supplier_text'),
    ('valve_type', t.valvula, 'supplier_text'),
    ('valve_length_mm', 'v_' || t.largo::text, 'supplier_text'),
    ('tube_material', t.material,
      case when t.material_declarado then 'supplier_text' else 'inferred' end)
  ) as s(key, code, source)
  where t.es_camara and s.code is not null and s.code <> 'v_'
), resuelto as (
  select objetivo.product_id, definition.id definition_id,
    valor.id value_id, objetivo.source
  from objetivo
  join public.spec_definitions definition
    on definition.tenant_id is null and definition.key = objetivo.key
  join public.spec_definition_values valor
    on valor.spec_definition_id = definition.id
   and valor.code = objetivo.code
   and valor.is_active
  where not exists (
    -- Nunca se sobrescribe: lo que ya está pudo confirmarlo una persona.
    select 1 from public.spec_facts existente
    where existente.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
      and existente.subject_type = 'product'
      and existente.subject_id = objetivo.product_id
      and existente.spec_definition_id = definition.id
  )
), insertado as (
  insert into public.spec_facts (
    tenant_id, subject_type, subject_id, spec_definition_id, source, confirmed
  )
  select '5443b130-cc28-45af-a420-cd500b288890', 'product',
    resuelto.product_id, resuelto.definition_id, resuelto.source, false
  from resuelto
  returning id, subject_id, spec_definition_id
)
insert into public.spec_fact_values (fact_id, value_id, position)
select insertado.id, resuelto.value_id, 0
from insertado
join resuelto on resuelto.product_id = insertado.subject_id
             and resuelto.definition_id = insertado.spec_definition_id;

-- 2. Los anchos: números, con su unidad según el aro. Los topes descartan
--    basura de parseo —un «2.1/4» que en realidad era una fracción de aro.
insert into public.spec_facts (
  tenant_id, subject_type, subject_id, spec_definition_id,
  value_number, source, confirmed
)
select '5443b130-cc28-45af-a420-cd500b288890', 'product', t.id, definition.id,
  s.valor, 'supplier_text', false
from tube_parse t
cross join lateral (values
  ('tube_width_min_in', case when not t.es_ruta then t.wmin end),
  ('tube_width_max_in', case when not t.es_ruta then t.wmax end),
  ('tube_width_min_mm', case when t.es_ruta then t.wmin end),
  ('tube_width_max_mm', case when t.es_ruta then t.wmax end)
) as s(key, valor)
join public.spec_definitions definition
  on definition.tenant_id is null and definition.key = s.key
where t.es_camara and s.valor is not null
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

-- 3. El sellante: booleano. `true` sale del nombre; `false` es la deducción que
--    el silencio autoriza, y por eso viaja como `inferred`.
insert into public.spec_facts (
  tenant_id, subject_type, subject_id, spec_definition_id,
  value_boolean, source, confirmed
)
select '5443b130-cc28-45af-a420-cd500b288890', 'product', t.id, definition.id,
  t.sellante,
  case when t.sellante then 'supplier_text' else 'inferred' end, false
from tube_parse t
join public.spec_definitions definition
  on definition.tenant_id is null and definition.key = 'tube_has_sealant'
where t.es_camara
  and not exists (
    select 1 from public.spec_facts existente
    where existente.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
      and existente.subject_type = 'product'
      and existente.subject_id = t.id
      and existente.spec_definition_id = definition.id
  );

commit;
