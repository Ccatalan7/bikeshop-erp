-- Llenar la ficha de los 113 neumáticos leyendo su nombre.
--
-- Hoy 0 de 113 tienen ficha. Es la SEGUNDA categoría del catálogo y la
-- contraparte natural de las cámaras: sin ella, «qué cámara le sirve a este
-- neumático» sólo se puede contestar desde el lado de la cámara, y «qué
-- neumático 29 tengo» no se puede contestar por ficha en absoluto.
--
-- La infraestructura ya existía —plantilla `tire` con seis campos y la
-- categoría `Neumáticos` mapeada a la familia `tire`, ambas activas—: lo único
-- que faltaba era leer los nombres, que sí traen los datos.
--
-- **La regla es la misma que en las cámaras: sólo se escribe lo que el nombre
-- dice.** Todo entra con `confirmed = false` y **nunca se sobrescribe** un
-- hecho existente, porque lo que ya está pudo confirmarlo una persona.
--
-- Un neumático tiene UN ancho, no un rango: `26X2.20` es 2,20″ y punto. Ésa es
-- la diferencia estructural con la cámara, que cubre una banda.
--
-- ## Lo que NO se deduce, y por qué
--
-- En las cámaras el silencio autorizó dos deducciones (sellante y material)
-- porque dos señales independientes coincidían sin un solo desacuerdo. Acá se
-- evaluó lo mismo para el talón y **se rechazó**:
--
--   * plegable (kevlar): 9 neumáticos, promedio $33.327, mínimo $19.990
--   * alambre declarado: 20 neumáticos, promedio $23.973
--   * no lo dice:        84 neumáticos, promedio $15.660, **máximo $39.990**
--
-- El promedio separa clarísimo, pero los techos se solapan: hay silenciosos de
-- $39.990, por encima del plegable más barato. Ese solape es exactamente el
-- desacuerdo que en las cámaras no existía, así que escribir «alambre» en los
-- 84 marcaría mal a unos cuantos. Vacío es mejor que equivocado, y una ficha
-- inventada es peor que ninguna porque nadie vuelve a revisarla.
--
-- Igual para `tire_tubeless_ready`: se escriben los 3 que lo declaran y ninguno
-- más. `tire_etrto` no se escribe: casi ningún nombre lo trae.
--
-- ## Las trampas del parseo, encontradas corriendo el ensayo en seco
--
-- Cada una devolvía un valor plausible y equivocado, que es la peor clase:
--
--   1. **La X no se busca suelta.** «BMX 20x2.25» y «HARTEX 26 X 2.10» tienen
--      una X dentro de la palabra, y el ancho salía 20 y 26 —el aro—. El par
--      aro×ancho se lee en UNA sola coincidencia.
--   2. **Un nombre puede traer dos notaciones.** «700x32 = 28x1 5/8 x 1 1/4»:
--      la fracción de la segunda le ganaba a la primera y el neumático de
--      32 mm quedaba con 1,625″. La fracción sólo vale si es del MISMO aro que
--      el par.
--   3. **La fracción se escribe de tres formas**: `1-3/8`, `1 3/8` y también
--      `1"3/8`, con la comilla de pulgada como separador. Se resuelve sólo si
--      es fracción de verdad —numerador < denominador, denominador potencia de
--      dos—, si no `1.5/2.5` se leería como 3,5.
--   4. **«24 X 2 125» no se adivina.** Es 2,125 sin el punto, pero también
--      podría ser el ancho 2 y un código 125. Queda sin ancho: cuando un valor
--      no se puede resolver la salida correcta es no escribirlo.
--
-- Read-back esperado (`verify_tire_specs_filled.sql`): 113 con aro, 112 con
-- ancho (86 en pulgadas, 26 en mm), 29 con talón, 3 tubeless, 0 confirmados,
-- 0 hechos sin valor y 0 anchos fuera de rango.

begin;

create temporary table tire_parse on commit drop as
with neumaticos as (
  select p.id, p.name,
    upper(translate(p.name, 'ÁÉÍÓÚÜÑáéíóúüñ', 'AEIOUUNaeiouun')) n
  from public.products p
  join public.product_categories c on c.id = p.category_id
  where p.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
    and p.is_active and c.name = 'Neumáticos'
), parsed as (
  select id, name, n,
    -- Trampa 1: el par va junto, nunca la X suelta.
    regexp_match(n,
      '\y(700|650|[0-9]{2}(?:[.,][0-9])?)\s*\.?\s*[X×]\s*([0-9]+(?:[.,][0-9]+)?)'
    ) par,
    -- Trampas 2 y 3: la fracción trae su propio aro para poder compararlo, y
    -- admite guion, espacio, punto y comilla como separador.
    regexp_match(n,
      '\y(700|650|[0-9]{2}(?:[.,][0-9])?)\s*\.?\s*[X×]\s*([0-9])\s*[-.\s''"”]\s*([0-9])\s*/\s*([0-9]{1,2})\y'
    ) frac,
    case when n ~ '\yKEVLAR\y|PLEGABLE|FOLDING' then 'talon_plegable'
         when n ~ '\yALAMBRE\y|\yWIRE\y' then 'talon_de_alambre'
         else null end talon,
    (n ~ 'TUBELESS|\yTLR\y|\yTR\y') tubeless,
    -- Trampa 4: el decimal sin punto es ambiguo y no se resuelve.
    (n ~ '\y(?:700|650|[0-9]{2}(?:[.,][0-9])?)\s*\.?\s*[X×]\s*[0-9]\s+[0-9]{2,3}\y'
     and n !~ '/') ancho_ambiguo
  from neumaticos
)
select id, name, talon, tubeless,
  case par[1]
    when '700' then 'v_700c' when '650' then 'v_650b' when '28' then 'v_700c'
    when '12' then 'v_12' when '16' then 'v_16' when '20' then 'v_20'
    when '24' then 'v_24' when '26' then 'v_26' when '29' then 'v_29'
    when '27.5' then 'v_27_5' when '27,5' then 'v_27_5'
    else null end rueda_code,
  case
    when ancho_ambiguo then null
    when frac is not null and frac[1] = par[1]
         and frac[3]::numeric < frac[4]::numeric and frac[4]::int in (2,4,8,16)
      then frac[2]::numeric + frac[3]::numeric / frac[4]::numeric
    else replace(par[2], ',', '.')::numeric
  end ancho,
  -- Un ancho escrito en fracción está en pulgadas aunque el aro sea de ruta:
  -- «28 X 1.5/8» dice pulgadas, y convertirlo a milímetros sería escribir un
  -- valor que el nombre no da.
  (frac is not null and frac[1] = par[1]) ancho_en_pulgadas,
  (par[1] in ('700','650','28')) es_ruta
from parsed;

-- 1. Las selecciones: el hecho va sin escalar y su valor es una fila en
--    `spec_fact_values`, que es como el motor guarda una selección. Escribir
--    `value_text` acá dejaría el hecho sin valor.
with objetivo as (
  select t.id product_id, s.key, s.code
  from tire_parse t
  cross join lateral (values
    ('wheel_size', t.rueda_code),
    ('tire_bead_type', t.talon)
  ) as s(key, code)
  where s.code is not null
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

-- 2. El ancho: un número, en la unidad que el nombre usa. Los topes descartan
--    basura de parseo antes de que llegue a la ficha.
insert into public.spec_facts (
  tenant_id, subject_type, subject_id, spec_definition_id,
  value_number, source, confirmed
)
select '5443b130-cc28-45af-a420-cd500b288890', 'product', t.id, definition.id,
  s.valor, 'supplier_text', false
from tire_parse t
cross join lateral (values
  ('tire_width_in', case when not t.es_ruta or t.ancho_en_pulgadas then t.ancho end),
  ('tire_width_mm', case when t.es_ruta and not t.ancho_en_pulgadas then t.ancho end)
) as s(key, valor)
join public.spec_definitions definition
  on definition.tenant_id is null and definition.key = s.key
where t.rueda_code is not null and s.valor is not null
  and case when s.key = 'tire_width_mm' then s.valor >= 15 and s.valor <= 90
           else s.valor >= 0.7 and s.valor <= 5.0 end
  and not exists (
    select 1 from public.spec_facts existente
    where existente.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
      and existente.subject_type = 'product'
      and existente.subject_id = t.id
      and existente.spec_definition_id = definition.id
  );

-- 3. Tubeless ready: sólo los que lo declaran. Ver la nota de arriba sobre por
--    qué acá el silencio NO es evidencia.
insert into public.spec_facts (
  tenant_id, subject_type, subject_id, spec_definition_id,
  value_boolean, source, confirmed
)
select '5443b130-cc28-45af-a420-cd500b288890', 'product', t.id, definition.id,
  true, 'supplier_text', false
from tire_parse t
join public.spec_definitions definition
  on definition.tenant_id is null and definition.key = 'tire_tubeless_ready'
where t.tubeless
  and not exists (
    select 1 from public.spec_facts existente
    where existente.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
      and existente.subject_type = 'product'
      and existente.subject_id = t.id
      and existente.spec_definition_id = definition.id
  );

commit;
