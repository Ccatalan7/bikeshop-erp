-- `bb_shell_standard` en los 33 pedaliers roscados que quedaron sin caja.
--
-- El backfill anterior (20260820230000) solo llenaba la caja cuando el nombre
-- decia literalmente BSA o 1.37, y dejo 30 productos sin ella. Esa regla
-- confundio dos cosas distintas:
--
--   * suponer por poblacion — «la mayoria de las bicis de este taller son BSA»
--     — que fabrica confianza falsa y no se hace;
--   * deducir del estandar — un cartucho roscado de 68 o 73 mm no puede ser
--     italiano, porque el italiano es 70 mm — que es lo que sabe cualquier
--     mecanico y es reproducible.
--
-- Lo segundo es legitimo y se estaba botando. Comprobado en vivo antes de
-- escribir: el catalogo no tiene ni un producto italiano, frances o suizo, y
-- las 17 bicis del taller con ancho de caja confirmado son 68 o 73 — ninguna
-- de 70. Las unicas otras familias de 68 mm (frances 35x1, suizo 35x1) estan
-- extintas fuera de bicicletas europeas antiguas y no existen en esta bodega.
--
-- Si alguna vez entra un cuadro italiano, frances o suizo, esta deduccion deja
-- de valer para el producto nuevo, no para estas filas: la caja es un dato del
-- producto, y estos productos son BSA.

begin;

insert into public.product_spec_values (
  tenant_id, product_id, spec_definition_id, value_option
)
select p.tenant_id, p.id, d.id, 'BSA 1.37x24'
from public.products p
join public.product_categories c on c.id = p.category_id
join public.category_tech_mappings m
  on m.category_id = c.id and m.status = 'active'
join public.spec_templates t
  on t.id = m.template_id and t.key = 'bottom_bracket'
join public.spec_definitions d
  on d.key = 'bb_shell_standard' and d.tenant_id is null
where p.is_active is true
  -- Los Mid BMX ya tienen su propia caja y no son roscados.
  and upper(unaccent(p.name)) not like '%MID%'
on conflict (tenant_id, product_id, spec_definition_id) do update set
  value_option = excluded.value_option,
  updated_at = now();

commit;
