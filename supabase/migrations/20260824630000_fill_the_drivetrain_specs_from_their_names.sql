-- Llenar la ficha de la transmisión —cadenas, cassettes y piñones— leyendo sus
-- nombres. 88 productos, 1 con ficha.
--
-- Es la tercera tanda del mismo procedimiento (cámaras, neumáticos, rayos), y
-- la que cubre la pregunta más común del mesón después de la medida de rueda:
-- **«¿tienes cadena de 9 velocidades?»**, «¿un piñón 11-34?». Sin
-- `chain_speeds` y `drivetrain_speeds` cargados, esa pregunta sólo se puede
-- contestar comparando la frase con el nombre, y el catálogo escribe la misma
-- velocidad de ocho formas: `6VEL`, `8 VEL.`, `9VEL.`, `12V.`, `10v`, `10S`,
-- `7-SPEED`, `7 Velocidades`.
--
-- Misma regla de siempre: **sólo lo que el nombre dice**, `confirmed = false`,
-- y nunca se sobrescribe un hecho existente.
--
-- ## Las trampas, encontradas en el ensayo en seco
--
--   1. **Los códigos de modelo están llenos de dígitos.** `CN-HG40`,
--      `CS-M4100`, `HV410`, `PG1230`, `Z8.3`, `X10`. Ninguno es una velocidad.
--      El número sólo cuenta si va **pegado a su unidad** (`V`, `VEL`,
--      `VELOCIDADES`, `SPEED`, `S`, `DV`), y así `CS-HG200-7, 7-SPEED` entrega
--      7 mientras `CS-M4100` no entrega nada.
--   2. **Un piñón puede traer la secuencia completa de coronas**:
--      `12-14-16-18-21-26-32`. Un patrón de rango simple leería «12-14» y
--      declararía un piñón 12-14, que no existe. La secuencia se lee aparte y
--      se toman el primero y el último.
--   3. **El ancho de cadena es una fracción, no un rango.** `1/2 X 3/32` no es
--      «1 a 2» ni «3 a 32»: es el paso por el ancho, y el ancho es lo que
--      distingue una cadena de piñón único (`1/8`) de una de 6-8 (`3/32`) y de
--      una de 9-12 (`11/128`).
--   4. **`Cadena Kmc X9 1/2" X11/28"` tiene el ancho mal escrito** —dice 11/28
--      donde el estándar es 11/128— y por eso no recibe ancho. Corregirlo sería
--      inventar; el nombre está malo y eso se ve en la ficha vacía.
--
-- ## Lo que no se deduce
--
-- Un ancho `1/8` implica piñón único y un `11/128` implica 9 o más, pero eso es
-- una **banda**, no un valor, y el precedente ya está fijado en las cámaras:
-- para deducir hacen falta dos señales independientes que coincidan sin
-- desacuerdo. Se escriben las velocidades que el nombre declara y ninguna más.
--
-- Los piñones de corona única —`PIÑON 15T FIJO`, `16 DTS`, `18T LIBRE`— no
-- tienen velocidades ni rango, y así quedan: son una corona, no un cassette.
--
-- Read-back esperado (`verify_drivetrain_specs_filled.sql`): cadenas 18 con
-- velocidades, 16 con ancho, 6 con eslabones; cassettes 29 con velocidades y 28
-- con rango; piñones 20 con velocidades y 16 con rango. 0 confirmados, 0 hechos
-- sin valor, 0 rangos invertidos.

begin;

create temporary table drivetrain_parse on commit drop as
with piezas as (
  select p.id, p.name, c.name categoria,
    upper(translate(p.name, 'ÁÉÍÓÚÜÑáéíóúüñ', 'AEIOUUNaeiouun')) n
  from public.products p
  join public.product_categories c on c.id = p.category_id
  where p.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
    and p.is_active and c.name in ('Cadenas','Cassette','Piñones')
), parsed as (
  select id, name, categoria, n,
    -- Trampa 1: el número sólo vale pegado a su unidad.
    (regexp_match(n,
      '\y([0-9]{1,2})\s*[-]?\s*(?:V\y|VEL\y|VEL\.|VELOCIDADES?\y|SPEED\y|DV\y|S\y)'
    ))[1]::int velocidades,
    -- Trampa 2: la secuencia completa se lee entera, no por su primer par.
    regexp_match(n, '\y([0-9]{2})(?:\s*-\s*[0-9]{2}){2,}\s*-\s*([0-9]{2})\y') secuencia,
    regexp_match(n, '\y([0-9]{2})\s*[-/]\s*([0-9]{2})\s*T?\y') rango,
    -- Trampa 3: el ancho es una fracción. Se prueba de más específico a menos
    -- para que `11/128` no lo gane `1/8`.
    case when n ~ '11\s*/\s*128' then 'v_11_128'
         when n ~ '3\s*/\s*32' then 'v_3_32'
         when n ~ '1\s*/\s*8' then 'v_1_8'
         else null end ancho_cadena,
    (regexp_match(n, '\y([0-9]{3})\s*(?:L\y|LINKS?\y|E\y)'))[1]::int eslabones
  from piezas
)
select id, name, categoria, velocidades, ancho_cadena, eslabones,
  coalesce(secuencia[1], rango[1])::int chico,
  coalesce(secuencia[2], rango[2])::int grande
from parsed;

-- 1. Las selecciones. `chain_speeds` y `drivetrain_speeds` son `multi_select`:
--    su valor vive igual en `spec_fact_values`, con su posición.
with objetivo as (
  select d.id product_id, v.key, v.code
  from drivetrain_parse d
  cross join lateral (values
    ('chain_speeds',
      case when d.categoria = 'Cadenas' and d.velocidades is not null
           then 'v_' || d.velocidades::text end),
    ('drivetrain_speeds',
      case when d.categoria in ('Cassette','Piñones') and d.velocidades is not null
           then 'v_' || d.velocidades::text end),
    ('chain_width_family',
      case when d.categoria = 'Cadenas' then d.ancho_cadena end)
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

-- 2. Los números: rango de coronas y cantidad de eslabones, cada uno dentro de
--    su rango físico. Una corona de piñón va de 9 a 18 dientes por abajo y de
--    21 a 60 por arriba; una cadena trae entre 100 y 140 eslabones.
insert into public.spec_facts (
  tenant_id, subject_type, subject_id, spec_definition_id,
  value_number, source, confirmed
)
select '5443b130-cc28-45af-a420-cd500b288890', 'product', d.id, definition.id,
  s.valor, 'supplier_text', false
from drivetrain_parse d
cross join lateral (values
  ('smallest_cog_teeth',
    case when d.categoria in ('Cassette','Piñones')
          and d.chico between 9 and 18 and d.grande between 21 and 60
         then d.chico end),
  ('largest_cog_teeth',
    case when d.categoria in ('Cassette','Piñones')
          and d.chico between 9 and 18 and d.grande between 21 and 60
         then d.grande end),
  ('link_count',
    case when d.categoria = 'Cadenas' and d.eslabones between 100 and 140
         then d.eslabones end)
) as s(key, valor)
join public.spec_definitions definition
  on definition.tenant_id is null and definition.key = s.key
where s.valor is not null
  and not exists (
    select 1 from public.spec_facts existente
    where existente.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
      and existente.subject_type = 'product'
      and existente.subject_id = d.id
      and existente.spec_definition_id = definition.id
  );

commit;
