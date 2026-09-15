# Auditoría de fichas — 2026-09-05

**Estado global actualizado:** [auditoría de los 1.664 registros, backup legacy
y saneamiento](global-audit-and-sanitation-2026-09-06.md). Se revisaron nominalmente
los 1.605 productos físicos, sus asignaciones y las 136 definiciones actuales.
Las migraciones de infraestructura hasta `20260907026000` están desplegadas;
la propuesta ampliada de 105 plantillas pasó su ensayo SQL local y conserva
cerrados sus gates de publicación y llenado. La asignación definitiva por
producto y los restantes contratos mecánicos siguen en trabajo. No se han
aplicado lotes de llenado; primero se sanea el catálogo completo.

Continuación actual: [puertos y aplicabilidad 2600](port-cardinality-integration-2026-09-07.md), [cardinalidad 2500](cardinality-integration-2026-09-07.md), [contenido y fuentes](evidence-scopes-integration-2026-09-07.md), [consumidor de transmisión/frenos](consumer-scope-integration-2026-09-07.md) y [20 asignaciones adjudicadas](assigned-product-root-decisions-2026-09-07.md). El checkpoint integrado tiene 711 definiciones y 323 casos SQL, con 1.265 pruebas pgTAP y 515 comprobaciones Dart focalizadas; las 210 Python corresponden al checkpoint anterior. La [adjudicación de los 33 registros sin ficha](unmapped-33-root-adjudication-2026-09-07.md) está registrada: seis familias respaldadas, una con conflicto comercial, dos intervenciones documentadas y 24 identidades/clasificaciones pendientes. La alternativa de neumático sigue sin integrar. Catálogo y llenado siguen sin aplicar; se está ensayando el impacto de las plantillas sobre las observaciones reales antes de publicar bloques de saneamiento.

Infraestructura: [valores condicionados y producción 2400](row-values-integration-2026-09-07.md), [contacto y familias restantes](contact-and-remaining-nd-integration-2026-09-07.md), [condiciones por fila y concurrencia](row-condition-integration-2026-09-07.md), [simulación autenticada de investigación](research-simulator-integration-2026-09-07.md), [consumidor de ruedas](spoke-wheel-consumer-integration-2026-09-07.md), [luces/electrónica/sensores integrados](light-power-sensor-integration-2026-09-07.md).

Este archivo conserva la **fase inicial de investigación**. La implementación
autorizada después, la revisión de Claude, la migración aplicada y sus límites
están en [implementation-result.md](implementation-result.md). Las afirmaciones
de sólo lectura/no despliegue de abajo se refieren a esta auditoría inicial.

Continuación 2026-09-06: [cadenas y conectores, segunda entrega aplicada](chain-connector-implementation-2026-09-06.md),
[preparación del llenado por Codex y Claude](catalog-fill-execution-plan-2026-09-06.md).
Esta última incluye la auditoría global, el preparador de lotes, el esquema por
campo y una primera propuesta revisada, todavía sin aplicar a productos.

Sólo lectura de producción y una sonda pura de Dart. No se guardó el producto
de los screenshots, no se identificó su modelo, no se reinició Flutter y no
se usó la conversación visible de Claude como instrucciones.

Resultado de diseño: [contrato](../../architecture/product-technical-specifications-contract.md),
[conocimiento](../../architecture/bicycle-compatibility-knowledge.md),
[matriz](../../architecture/product-spec-family-matrix.md).

## Evidencia y límites

- Rama `smartpegas1.0`, HEAD inicial `71926a11`. Había cambios ajenos en OCR,
  temas y documentos. No se tocaron; no hubo commit/push/deploy.
- Preflight verificó el proyecto productivo `xzdvtzdqjeyqxnkqprtf` y acceso por
  wrapper. La sesión `payroll` estaba activa y se preservó.
- [templates.json](templates.json): 37 plantillas activas / 36 familias / 241
  campos. Los 22 campos con restricciones de opciones están en cuatro plantillas
  de pedalier. Los 30 campos con visibilidad incluyen una regla de llanta.
  El conteo es de campos con JSON no vacío, no número de predicados individuales.
- [coverage.json](coverage.json): 137 categorías activas Viñabike, 112 hojas,
  72 sin plantilla activa directa. Incluye servicios y accesorios simples:
  **no son 72 errores probados** ni 72 categorías que deban copiar la ficha de cadena.
- [leaves.json](leaves.json): rutas, mapeos directos y cantidad de filas de
  producto activas no servicio en cada hoja. No incluye nombres ni IDs de productos.
  La cobertura no afirma que todos sus atributos estén correctamente poblados.
- [manifest.json](manifest.json): hashes del código inspeccionado, salidas y
  funciones productivas; no sustituye una lectura actual al implementar.

## Sonda de la contradicción

```sh
fvm dart docs/development/product-specs-research-2026-09-05/resolver-probe.dart
```

Salida de referencia: [resolver-probe.jsonl](resolver-probe.jsonl).
El mapa combina los datos visibles en los screenshots, incluido 7,1 del
primero; no se afirma que todos estuvieran persistidos simultáneamente.

El resolvedor permite `6,7,8` con `11/128` y `7.1`, deja ambos campos de
ecosistemas sin restricción, bloquea el perfil en Campagnolo y ofrece anchos que
excluyen 7,1. Esto muestra una contradicción **entre decisiones del resolvedor**.
No ejecuta el formulario ni demuestra qué termina persistiendo su poda posterior.

## Puntos de código y servidor inspeccionados

| Owner | Hallazgo |
|---|---|
| `lib/modules/bikeshop/config/drivetrain_canonical_data.dart` | `_deriveChainSpeedOptionsFromOuterWidthMm` y `_buildAllowedChainSpeedOptions` usan bandas de medida; `_buildAllowedChainProfileOptions` conserva perfiles explícitos y permite categorías «Universal» |
| `lib/modules/inventory/pages/product_form_page.dart` | `_resolveSpecInference` poda valores por campo en una pasada y omite validación cuando el dominio permitido es vacío; `_saveProduct` guarda producto antes de invocar specs |
| `lib/modules/inventory/services/spec_engine_service.dart` | `SpecTemplateField` interpreta reglas; operador no conocido pasa; RPC serializa etiquetas; errores de lectura devuelven vacío/null |
| `lib/modules/inventory/utils/product_spec_persistence_utils.dart` | Sanitización especial de plataforma/indexación, no validación conjunta de ficha |
| `save_product_spec_facts_v1` productiva | Comando de hechos atómico con tenant y advisory lock; lista de definiciones del cliente y búsqueda por etiqueta; sin evaluación de `option_rules`/identidad/conjunto |
| Triggers observados | Espejo facts→product_specs; forma/cardinalidad de listas; invalidación de lectura por cambio de fuente; guardia de etiquetas amplias para plataforma/indexación |

La ausencia del evaluador conjunto se verificó en las funciones y triggers de
estas tablas, no mediante una escritura inválida contra producción. No se
declara una auditoría completa de permisos de todos los endpoints del sistema.

## Reproducir la lectura

Leer primero `docs/development/AGENT_DATABASE_CONTRACT.md`. Luego, una vez por
tarea, `just db-preflight`; la lectura equivalente está en [audit.sql](audit.sql):

```sh
scripts/db/query.sh production --file docs/development/product-specs-research-2026-09-05/audit.sql
```

Las capturas JSON se tomaron con las mismas consultas ejecutadas individualmente
por `query.sh --sql ... --format json`. No confundirlas con una migración,
ensayo de escritura, prueba UI ni certificación de compatibilidad mecánica.
La matriz de familias se verificó contra las 36 claves observadas.
