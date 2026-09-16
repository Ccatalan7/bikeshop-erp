# Matriz estructural de las 107 plantillas contra el contrato de familia — 2026-09-16

Tercera compuerta del llenado, parte estructural, hecha sólo de lectura por
`scripts/inventory/audit_family_contract_matrix.py` sobre la instantánea global de las 09:17Z, la
cobertura releída, la auditoría de definiciones con consumidores y
`catalog-fill-critical-fields.json`. Para cada plantilla activa lee lo que el contrato publicado
declara de lo que la [matriz de familias](../../architecture/product-spec-family-matrix.md) pide:
decisión inicial, campos dependientes, interfaces y discriminadores, condiciones de publicación,
fuentes exigidas y combinaciones prohibidas. Resultado completo en
[family-contract-matrix-2026-09-16.json](family-contract-matrix-2026-09-16.json). No juzga si las
decisiones declaradas son las mecánicamente correctas; una plantilla sin hallazgos no es una
familia lista para llenar. Ningún dato cambió. Llenado técnico persistido: 0.

## Cifras

| Medida | Valor |
|---|---|
| Plantillas activas | 107 (102 con productos; 19 con alguna observación) |
| Roles de campo publicados | 296 `primary`, 353 `measurement`, 293 `declaration`, 101 `contents`, 356 `legacy` |
| Fuentes exigidas (por campo) | 525 `oem_or_package`, 486 `package_or_label`, 220 `oem_spec`, 70 `name_reading_hint_only`, 49 `commercial_attribute`, 10 `oem_or_measurement`, 2 `workshop_measurement` |
| Combinaciones prohibidas | 70 plantillas con condiciones de fila, 17 con pares ordenados, 28 con coherencia de filas, 14 con perfiles de miembro |
| Sin hallazgo salvo «campos críticos» | 32 plantillas |

## Hallazgos

1. **68 plantillas son ciegas para el cliente y para el matcher.** Sus 609 campos activos tienen
   `is_customer_visible = false` e `is_filterable = false` en la definición, así que la ficha
   pública no mostraría nada que se llenara y el asistente, las necesidades de compra y el portal
   de proveedores no podrían usarlo como criterio. Cubren 620 productos; las de más de diez:
   herramientas de taller (45), pedales (34), guantes (33), candados (31), químicos (30), puños
   (28), tornillería (22), sillines (22), piezas menores de mando (20), luces (20), alimentos
   (19), cables (18), potencias (18), bombas (15), cierres de rueda (15), manillares (14), tijas
   (14), fundas (13), cascos (13), abrazaderas (12), portabidones (11), horquillas (11), racores
   (10) y cinta tubeless (10). Son las 68 plantillas nuevas de septiembre, que nacieron con los
   flags apagados, más los sucesores. Las 39 con algún campo visible cubren 974 productos y son,
   casi todas, las originales reemplazadas.
2. **Ocho plantillas no declaran una decisión inicial** (ni campo `primary` ni opciones
   gobernadas): `bottom_bracket`, `bottom_bracket_cup`, `cassette_spacer`, `tire_liner`,
   `tubeless_repair`, `drivetrain_kit`, `component_set` y `brake_shift_combined_control`. En los
   contenedores la decisión es la lista de miembros; en las piezas simples falta el selector que
   ordene el resto de campos.
3. **Tres campos obligatorios sin fuente exigida:** `brake_presentation` en las tres
   presentaciones de freno publicadas hoy (revisión 223). Es un selector comercial; le
   corresponde `commercial_attribute` o `package_or_label` en la próxima revisión de esas
   plantillas. El motor no bloquea por ello.
4. **Campos críticos definidos sólo para cadena y conector.** 105 plantillas no tienen lista de
   hechos críticos, así que la métrica de cobertura del llenado (identidad, presentación,
   técnico, evidencia de compatibilidad) no puede calcularse fuera de esas dos familias.
5. **Cinco plantillas sin productos:** `bicycle`, `fixed_cog`, `frame`, `hub_brake`, `wheel`.
6. **Ningún consumidor lee sólo claves `legacy` de una plantilla** cuando esa plantilla también
   tiene claves activas leídas; la pérdida de capacidad es por campo, no por familia entera.

## Estado por familia para elegir el primer lote

Las 32 sin hallazgo salvo campos críticos y con algún campo visible son las candidatas
estructurales: `bearing`, `bottom_bracket_axle`, `bottom_bracket_bearing`, `brake_caliper`,
`brake_lever`, `brake_pad`, `cassette`, `chain`, `chain_guide`, `chain_link`, `chainring`,
`crank_arm`, `crankset`, `derailleur_hanger`, `derailleur_pulley`, `freewheel`,
`front_derailleur`, `headset`, `hub`, `hub_axle`, `hub_small_part`, `rear_derailleur`, `rim`,
`rim_strip`, `rotor`, `seatpost_shim`, `shifter`, `spoke`, `tire`, `tube`, `tubeless_consumable`
y `tubeless_valve`. Entre ellas, las que ya tienen observaciones y productos (cámara 138/133,
neumático 118/113, rayo 58/48, pedalier 38/34, cadena 35/29, cassette 32/29, rueda libre
29/21, rotor 18/10) son donde el llenado encontraría más contradicciones que resolver; las que
tienen productos y ninguna observación (maza 52/2, llanta 44/6, cambio trasero 40/0, mando 36/0,
bielas 32/0, pastilla 53/13) son donde encontraría más vacío.

## Qué sigue

- **Flags de visibilidad y filtro**: propuesta concreta y no publicada en
  [definition-flags-proposal-2026-09-16.md](definition-flags-proposal-2026-09-16.md): 371
  definiciones (362 visibles, 305 filtrables, ningún apagado), regla «escalar y no evidencia»,
  con los ocho campos visibles hoy fuera de la regla listados sin cambio. La decisión de
  publicarla, recortarla o diferirla por familia es del dueño.
- **Campos críticos por familia**: hecho como borrador en
  [catalog-fill-critical-fields-derived-2026-09-16.json](catalog-fill-critical-fields-derived-2026-09-16.json)
  por `scripts/inventory/derive_critical_fields.py` (cadena y conector copiados del archivo
  revisado; las otras 105 familias derivadas del contrato: decisiones primarias y campos
  obligatorios como técnico, contenidos y presentaciones como presentación, campos de evidencia
  como evidencia de compatibilidad; mediana de tres campos técnicos por familia). Las siete
  familias sin campo técnico derivado son los contenedores y las tres presentaciones de freno,
  cuya técnica vive en los perfiles de miembro. Sigue sin revisar: no es criterio de cierre de
  ningún lote hasta que alguien lo lea familia por familia.
- **Decisión inicial** en las cinco piezas simples sin selector, en su próxima revisión.
- **Fuente exigida** para `brake_presentation`.
