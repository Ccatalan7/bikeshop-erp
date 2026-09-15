# Ruedas, dirección, rodamientos y suspensión — integración local

El paquete de Claude y su autorrevisión se integraron con correcciones de raíz.
Son reglas de representación de la ficha de una variante física, todavía sin
publicación del catálogo, asignación o llenado de productos. La
[revisión independiente](wss-root-corrections-independent-review-2026-09-07.md)
verificó los nueve cambios de raíz. Sus residuales necesitan adjudicación:
no se acepta automáticamente como ley física una comparación entre dos
máximos independientes de envolvente ni entre cotas con datum no confirmado.
No se certifica ninguna familia como completa.

## Decisiones mecánicas contrastadas

- Continental publica un **máximo** de ancho interno para cada neumático y
  montaje; no es un mínimo. La 28-622 y la 30-622 se representan en fichas
  diferentes. Se retiraron mínimos y presiones no sustentados de los fixtures.
  La presión de una configuración tiene un valor y su unidad declarada, en
  lugar de dos máximos bar/psi que podrían contradecirse. La envolvente es
  general para este SKU; límites de un aro concreto requieren una relación.
  [Fuente OEM](https://www.continental-tires.com/us/en/tire-knowledge/hookless-vs-hooked-rims/).
- **MAX no excluye contacto angular ni implica ausencia de canal de llenado.**
  Enduro 7001 1ZS MAX es un contraejemplo concreto. La construcción interna y
  los sellos conservan el literal OEM; la retención con jaula o complemento
  completo se declara en otro eje. No se infiere compatibilidad desde MAX.
  [7001 1ZS MAX](https://cycling.endurobearings.com/products/7001-1zs-max).
- Los biseles que asientan un cartucho de dirección son distintos del ángulo
  de contacto entre bolas y pistas. Los ángulos de apoyo dependen de la
  construcción de cartucho y de los biseles explícitamente presentes; bolsas
  de bolas y canastillos no reciben requisitos de ángulos de cartucho.
  Un cartucho puede ser abierto, blindado o sellado. Los valores antiguos se
  conservan, sin reinterpretarlos. [Park Tool](https://www.parktool.com/en-us/blog/repair-help/headset-standards).
- Los extremos del amortiguador se identifican como **cuerpo y vástago**;
  superior/inferior depende del cuadro. El selector escalar sin extremo queda
  legacy. La presencia de diferentes extremos en una página de modelo no
  aprueba el producto cartesiano de todas sus variantes. Se retiraron medidas
  de herrajes no sustentadas de los ejemplos.
  [RockShox](https://www.sram.com/en/service/models/rs-dlx-rlr-a1),
  [FOX](https://tech.ridefox.com/bike/parts-drawings/2954/dhx-part-information).
- Un alojamiento del cuadro no es la cazoleta EC/ZS seleccionada; se describe
  por su geometría de alojamiento. La rosca de espiga tampoco comparte el eje
  IS/ZS/EC. La horquilla declara su construcción de una o dos coronas antes
  del rango de altura total entre coronas; aire/muelle no decide ese rango.
  Las cifras de una FOX 40 concreta no se extrapolan a todas las horquillas.
  [FOX 40 2013](https://tech.ridefox.com/fox_tech_center/owners_manuals/013/Content/Forks/40/40withDMS_Installation.html).
- Se rechazó cambiar el rótulo de diámetro de rosca de rayo por diámetro de
  alambre: FG2.3 y alambre de 2 mm son magnitudes distintas. El estándar de
  rosca sigue siendo literal, sin convertir calibre automáticamente.
  [Sapim, catálogo 2018](https://www.sapim.be/sites/default/files/Sapim%20brochure%202018%20def%20A5%202018-Taiwanese%20LR.pdf).

El consumidor de mazas, aros y rayos tiene su propio
[resultado y límites](spoke-wheel-consumer-integration-2026-09-07.md): 57
pruebas, sin recarga de estos cambios en la sesión nativa todavía.

## Artefactos y prueba

`scripts/inventory/normalize_wss_review.py` reproduce 49 parches adjudicados,
18 definiciones nuevas y 35 casos nuevos desde fuentes congeladas. El
compilador `compile_product_spec_wss_addendum.py` verifica sus hashes y
encadena la base de condiciones c12204e4. Resultado: **105 plantillas,
699 definiciones (571 nuevas), 54 campos de filas y 1.205 usos**.

| Artefacto | SHA-256 |
|---|---|
| all-family-wss-integrated-2026-09-07.json | `6ed9cdf73ae5d9fc0aa2284bb4691f4f1eca958c2762c5ea1e7076c5f9358b18` |
| all-family-wss-cases-integrated-2026-09-07.json | `949cecf52744fb03bacf19d93198868381d85e7dde8bce3978078cf8a27441d8` |
| wss-root-decisions-2026-09-07.json | `9afde6ed983b76e0eea953461d71a10c5a8125e2f5b4a5bcc7957b0d3c297799` |
| wss-normalized-patches-2026-09-07.json | `f825e68f72fd84e31506f2eb1cbc97dbcf11d0f5079ec9e9e086be768e1cb8aa` |

El ensayo SQL pasó los guards diferidos de las 105 plantillas y los **167
casos de representación**, verificó conservación de hechos/identidad y
terminó en ROLLBACK. Log: `.tmp/db/spec-all-family-wss-trial.log`.
Las **276 comprobaciones Dart** pasaron sobre los mismos metadatos ejecutables;
el hash posterior sólo corrige trazabilidad de adjudicación. Log:
`.tmp/product-spec-catalog/all-family-wss-integrated-dart.log`.
La ampliación del integrador tiene **76 pruebas Python**; tres nuevas prueban
que la modificación de dominio numérico sólo opera sobre definiciones nuevas,
con preimagen exacta y límites válidos. No puede cambiar identidad, tipo o unidad.

Dos correcciones del ensayo no son cambios del motor: los enteros dentro de
filas se transportan como cadenas decimales exactas; y la aserción JSONB de
subconjunto necesita paréntesis alrededor de ambos operandos. Para tres casos
se fijaron por separado los códigos SQL/Dart existentes: SQL central envuelve
ciertas violaciones sin enlace en `field_constraint`, Dart usa `row_shape` o
`range`. Se conservan las aserciones exactas de campo y bloqueo; no se omiten
errores para hacer pasar el caso.

Quedan relaciones OEM y controles entre fila/escalar o entre configuraciones;
no se deducen montajes por igualdad de medida. Los gates globales siguen en
falso, y las 54 estructuras nuevas aún necesitan el cierre semántico global.
