-- Llenar la ficha de los 48 rayos leyendo su nombre.
--
-- Hoy 2 de 48 tienen ficha. Un rayo es el caso más puro de la cadena de
-- lenguaje natural: **la pregunta del taller es literalmente una medida**
-- —«¿tengo rayos de 264?»— y sin `spoke_length_mm` cargado esa pregunta sólo
-- se puede contestar comparando la frase contra el nombre, que falla en cuanto
-- el catálogo escribe la medida de otra forma. Y la escribe de cinco maneras.
--
-- Misma regla que en cámaras y neumáticos: **sólo se escribe lo que el nombre
-- dice**, todo con `confirmed = false` y sin sobrescribir nunca un hecho
-- existente.
--
-- ## Las cinco formas de escribir el largo, y la trampa del nipple
--
--   `290MM` · `273MM X 14G` · `185MM×14G` · `265X14G` (calibre pegado, sin
--   borde de palabra) · `14x275mm` (calibre y largo al revés)
--
-- Y once rayos —casi uno de cada cuatro— **están medidos en centímetros con
-- coma decimal**: «Rayos 25,7 Cms» son 257 mm. Pasar cm a mm es cambiar la
-- unidad de un valor que el nombre sí da, no inferirlo; sin esta conversión
-- esos once quedaban sin largo y el ensayo en seco los mostró como el hueco
-- más grande.
--
-- **La trampa: el nipple también se escribe en milímetros.** «RAYO 185MM PL
-- NEGRO (16MM)», «RAYO 260 MM.C/NIPLES 16 MM», «RAYOS 225 mm (2.0mm) 14G
-- Nipple 16mm» traen dos y hasta tres números con MM. No se resuelve por
-- posición ni por paréntesis, que varían: se resuelve por **rango físico**, que
-- es lo único que no depende de cómo esté escrito. Un rayo mide entre 150 y
-- 310 mm; un nipple, entre 12 y 16; el grosor del alambre, 2.0. Los rangos no
-- se tocan, así que el filtro los separa sin adivinar.
--
-- ## Lo que NO se escribe
--
-- El calibre lo declaran 15 y la curva 4. En las cámaras el silencio autorizó
-- deducir porque dos señales independientes coincidían sin desacuerdo; acá no
-- hay segunda señal y la muestra de curva son cuatro filas. 14G es el estándar
-- y J-Bend también, pero «lo más común» no es evidencia sobre ESTE producto.
-- Se escriben los que lo dicen y ninguno más.
--
-- Read-back esperado (`verify_spoke_specs_filled.sql`): 48 con largo entre 180
-- y 305, 15 con calibre, 4 con curva, 0 confirmados, 0 hechos sin valor y 0
-- largos fuera de rango.

begin;

create temporary table spoke_parse on commit drop as
with rayos as (
  select p.id, p.name,
    upper(translate(p.name, 'ÁÉÍÓÚÜÑáéíóúüñ', 'AEIOUUNaeiouun')) n
  from public.products p
  join public.product_categories c on c.id = p.category_id
  where p.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
    and p.is_active and c.name = 'Rayos'
), candidatos as (
  select r.id, m[1]::numeric largo
  from rayos r
  cross join lateral regexp_matches(r.n, '([0-9]{2,3})\s*MM', 'g') m
  union all
  -- `265X14G`: el largo va antes de la X y el calibre pegado después.
  select r.id, m[1]::numeric
  from rayos r
  cross join lateral regexp_matches(r.n, '([0-9]{3})\s*[X×]\s*1[0-9]\s*G?\y', 'g') m
  union all
  -- `14x275mm`: el par va al revés.
  select r.id, m[2]::numeric
  from rayos r
  cross join lateral regexp_matches(r.n, '\y1[0-9]\s*[X×]\s*([0-9]{3})', 'g') m
  union all
  -- `25,7 Cms` = 257 mm.
  select r.id, replace(m[1], ',', '.')::numeric * 10
  from rayos r
  cross join lateral regexp_matches(r.n, '([0-9]{2}[.,][0-9])\s*CMS?\y', 'g') m
), largo as (
  -- El rango físico es lo que separa el rayo del nipple y del grosor.
  select id, min(largo) largo
  from candidatos where largo between 150 and 310
  group by id
)
select r.id, r.name, l.largo,
  case when r.n ~ '14\s*/\s*15\s*G?\y' then 'v_14_15g'
       when r.n ~ '[^0-9]13\s*G\y' then 'v_13g'
       when r.n ~ '[^0-9]14\s*G\y|STD\s*14\y|[^0-9]14\s*[X×]\s*[0-9]{3}' then 'v_14g'
       when r.n ~ '2\.0\s*/\s*1\.8' then 'v_2_0_1_8'
       else null end calibre,
  case when r.n ~ 'STRAIGHT\s*PULL' then 'straight_pull'
       when r.n ~ 'J.?BEND' then 'j_bend'
       else null end curva
from rayos r left join largo l on l.id = r.id;

-- 1. Las selecciones viven en `spec_fact_values`, no en las columnas escalares.
with objetivo as (
  select s.id product_id, v.key, v.code
  from spoke_parse s
  cross join lateral (values
    ('spoke_gauge', s.calibre),
    ('spoke_bend_type', s.curva)
  ) as v(key, code)
  where v.code is not null
), resuelto as (
  select objetivo.product_id, definition.id definition_id, valor.id value_id
  from objetivo
  join public.spec_definitions definition
    on definition.tenant_id is null and definition.key = objetivo.key
  join public.spec_definition_values valor
    on valor.spec_definition_id = definition.id
   and valor.code = objetivo.code
   and valor.is_active
  where not exists (
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
    resuelto.product_id, resuelto.definition_id, 'supplier_text', false
  from resuelto
  returning id, subject_id, spec_definition_id
)
insert into public.spec_fact_values (fact_id, value_id, position)
select insertado.id, resuelto.value_id, 0
from insertado
join resuelto on resuelto.product_id = insertado.subject_id
             and resuelto.definition_id = insertado.spec_definition_id;

-- 2. El largo: un número en milímetros, dentro del rango físico de un rayo.
insert into public.spec_facts (
  tenant_id, subject_type, subject_id, spec_definition_id,
  value_number, source, confirmed
)
select '5443b130-cc28-45af-a420-cd500b288890', 'product', s.id, definition.id,
  s.largo, 'supplier_text', false
from spoke_parse s
join public.spec_definitions definition
  on definition.tenant_id is null and definition.key = 'spoke_length_mm'
where s.largo is not null and s.largo between 150 and 310
  and not exists (
    select 1 from public.spec_facts existente
    where existente.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
      and existente.subject_type = 'product'
      and existente.subject_id = s.id
      and existente.spec_definition_id = definition.id
  );

commit;
