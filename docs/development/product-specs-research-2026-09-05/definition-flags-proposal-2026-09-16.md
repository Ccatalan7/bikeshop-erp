# Propuesta de flags de visibilidad y filtro para los campos ciegos — 2026-09-16

**Publicada tal cual el 2026-09-16** como `20260916150000_definition_visibility_flags.sql`; ver
[definition-flags-publication-2026-09-16.md](definition-flags-publication-2026-09-16.md).

La matriz estructural del mismo día encontró 68 plantillas sin ningún campo visible al
cliente ni filtrable (620 productos, 609 campos activos). Esta propuesta convierte ese vacío en
una lista concreta por definición, calculada por `scripts/inventory/propose_definition_flags.py`
sobre la instantánea global de las 09:17Z y guardada en
[definition-flags-proposal-2026-09-16.json](definition-flags-proposal-2026-09-16.json). **No
está publicada**: qué ve un cliente en la tienda y qué puede pedir el asistente es una decisión
de producto. Ningún dato cambió. Llenado técnico persistido: 0.

## La regla

- Visible al cliente: campo activo (no `legacy`) de tipo escalar (número, booleano, texto,
  opción única o múltiple) cuyo rol semántico no sea `evidence`.
- Filtrable: visible y de tipo opción única, opción múltiple, número o booleano.
- Interno: campos de evidencia y filas (`json`), porque ningún consumidor pinta filas todavía.
- Nunca se propone apagar un flag que una adjudicación de familia ya encendió: los campos
  visibles hoy que quedan fuera de la regla se listan aparte, sin cambio.

## Cifras

| Medida | Valor |
|---|---|
| Definiciones con uso activo en alguna plantilla | 725 |
| Cambios propuestos | 371 definiciones: 362 pasan a visibles, 305 a filtrables; 0 apagados |
| Por tipo | 146 números, 108 opciones únicas, 66 textos, 44 booleanos, 7 opciones múltiples |
| Por rol semántico | 115 `compatibility`, 106 `intrinsic`, 69 `measurement`, 47 `declaration`, 37 `contents`, 2 `identity`, 1 `primary` |
| Plantillas tocadas | 90 (las que más: manillar 20, horquilla 19, tornillería 17, alimentos 16, electrónica 15, puños 15, pata de cabra 14, pedales 14, tija 14) |
| Fuera de la regla pero visibles hoy (sin cambio) | 8: `bearing_size_code`, `hanger_model_code`, `lever_control_mount_oem_code`, `lever_mount_oem_interface`, `pad_shape_code`, `rim_etrto`, `tire_etrto` (textos filtrables adjudicados) y `seatpost_shim_mount_instructions` (evidencia visible) |

## Qué implica publicarla

- Es un cambio de metadata sobre `spec_definitions` (dos booleanos por definición), sin tocar
  plantillas ni hechos; `product_spec_definition_revision` avanza la versión de cada plantilla
  que usa la definición, como en la migración de dominios numéricos de septiembre.
- Efecto inmediato en producción: la ficha pública mostraría los valores que ya existan en esos
  campos (hoy casi ninguno: 19 familias con observaciones) y el asistente, las necesidades y el
  portal de proveedores podrían usarlos como criterio. El matcher exige `is_filterable`, así que
  sin esto ningún llenado de esas 68 familias sería consultable.
- Lo que no cambia: la compatibilidad de taller sigue leyendo sus claves antiguas hasta que se
  migre familia por familia.

## Decisión pendiente

Publicar la lista tal cual, recortarla (por ejemplo sólo `compatibility`, `intrinsic` y
`measurement`, que son 290 de las 371) o dejarla para cuando exista el primer lote de llenado
de cada familia. Si se publica, va por el mismo camino de siempre: preimagen fresca, delta
exacto de IDs, migración con guardas, verificador que falla antes, lectura posterior por
familia y registro.
