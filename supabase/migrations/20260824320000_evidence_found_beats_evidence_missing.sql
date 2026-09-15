-- Lo que sí se estableció gana sobre lo que no se sabe.
--
-- Medido en la app real con «Cámaras 29 con válvula Schrader»:
--
--   CAMARA 29 X 1.75/2.35 V/AMERICANA → wheel_size: identity_fallback
--                                        valve_type: unresolved
--   CAMARA 26 X 2.30/2.50             → wheel_size: unresolved
--                                        valve_type: unresolved
--
-- Las dos terminaban en `unverified`, así que la cámara que **dice 29 en su
-- propio nombre** se presentaba igual que una de 26. El paso «Stock interno»
-- ofrecía 124 alternativas indistinguibles donde el operador quería ver 25.
--
-- La causa: cualquier criterio `unresolved` ganaba sobre uno ya establecido por
-- identidad. Un criterio que no se sabe borraba la evidencia del que sí calzó,
-- que es el mismo defecto que ya se corrigió en el ranking de proveedores.
--
-- Y el dato de fondo lo explica: de 128 cámaras activas, sólo **4** tienen
-- ficha técnica poblada. Exigir la ficha para reconocer una medida deja fuera
-- al 97% del catálogo real, y el nombre del producto es la única evidencia que
-- existe para el resto.
--
-- Nueva escalera, de la más estricta a la más laxa:
--
--   conflict     la ficha contradice el criterio — se excluye, sin cambios
--   strong       TODO se verificó contra la ficha
--   weak         algo se estableció y nada contradice — «coincide por nombre»
--   unverified   no se pudo establecer NADA
--
-- `weak` y `unverified` ya existen y ya tienen su rótulo en la interfaz, así
-- que ninguna app instalada ve un estado que no conozca.

begin;

create or replace function public.supply_need_match_state_internal_v1(
  p_detail jsonb,
  p_predicate_count integer
)
returns text
language sql
immutable
parallel safe
set search_path = pg_catalog, pg_temp
as $$
  select case
    when coalesce(p_predicate_count, 0) = 0 then 'no_criteria'
    -- La ficha contradice el criterio: eso no se muestra en ninguna parte.
    when exists (
      select 1 from jsonb_array_elements(coalesce(p_detail, '[]'::jsonb)) entry(value)
      where entry.value ->> 'source' = 'conflict'
    ) then 'conflict'
    -- Todo verificado contra la ficha.
    when not exists (
      select 1 from jsonb_array_elements(coalesce(p_detail, '[]'::jsonb)) entry(value)
      where entry.value ->> 'source' <> 'product_spec'
    ) then 'strong'
    -- Algo se estableció —por ficha o por el nombre curado— y nada contradice.
    -- Ese producto NO es indistinguible de uno del que no se sabe nada.
    when exists (
      select 1 from jsonb_array_elements(coalesce(p_detail, '[]'::jsonb)) entry(value)
      where entry.value ->> 'source' in ('product_spec', 'identity_fallback')
    ) then 'weak'
    else 'unverified'
  end
$$;

commit;
