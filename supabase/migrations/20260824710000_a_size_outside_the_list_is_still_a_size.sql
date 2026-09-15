-- Una medida fuera de la lista sigue siendo una medida.
--
-- Dos cámaras quedaron sin `wheel_size` porque su aro no está en el vocabulario:
-- «Camara Para Carretilla 3.50 X 8» (aro 8, de carretilla) y «Camara 12 1/2 X
-- 1.75x 2 1/4» (aro 12½, de niño). El parseo de nombres no las tomó y quedaron
-- con la válvula cargada y la rueda vacía.
--
-- El efecto no es cosmético: la elegibilidad incluye lo que **no contradice**
-- los criterios —regla correcta cuando la ficha está vacía—, así que una cámara
-- sin medida de rueda aparecía como alternativa para una necesidad de 27.5". El
-- operador veía una cámara de CARRETILLA entre las opciones de su bicicleta.
--
-- Dejarlas vacías «porque su medida no está en la lista» es confundir «no lo
-- sé» con «no aplica». El vocabulario ya tiene `Otra` justamente para esto: un
-- aro 8 no es 27.5, y decirlo es lo que las saca de la comparación.
--
-- «Cámara nueva + servicio de cambio» se queda sin ficha a propósito: es un
-- servicio, no un producto.

begin;

with objetivo as (
  select p.id product_id,
    case
      when p.name ilike '%12 1/2%' then 'v_12'
      else 'otra'
    end code
  from public.products p
  where p.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
    and p.is_active
    and (p.name ilike 'camara%' or p.name ilike 'cámara%')
    and (p.name ilike '%12 1/2%' or p.name ilike '%carretilla%')
    and not exists (
      select 1 from public.spec_facts existente
      join public.spec_definitions definicion
        on definicion.id = existente.spec_definition_id
      where existente.subject_id = p.id and definicion.key = 'wheel_size'
    )
), insertado as (
  insert into public.spec_facts (
    tenant_id, subject_type, subject_id, spec_definition_id, source, confirmed
  )
  select '5443b130-cc28-45af-a420-cd500b288890', 'product',
    objetivo.product_id, definicion.id, 'supplier_text', false
  from objetivo
  join public.spec_definitions definicion
    on definicion.tenant_id is null and definicion.key = 'wheel_size'
  returning id, subject_id
)
insert into public.spec_fact_values (fact_id, value_id, position)
select insertado.id, valor.id, 0
from insertado
join objetivo on objetivo.product_id = insertado.subject_id
join public.spec_definitions definicion
  on definicion.tenant_id is null and definicion.key = 'wheel_size'
join public.spec_definition_values valor
  on valor.spec_definition_id = definicion.id
 and valor.code = objetivo.code
 and valor.is_active;

commit;
