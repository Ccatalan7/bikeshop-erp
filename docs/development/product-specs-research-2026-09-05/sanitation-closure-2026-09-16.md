# Cierre del saneamiento y apertura del llenado — 2026-09-16

Decisión de Claude, como único propietario técnico, bajo la instrucción del dueño del mismo día:
decidir todo con el negocio como criterio, sin pedirle aprobaciones. El objetivo del negocio es
vender; una ficha técnica llena y visible vende porque el cliente encuentra el producto en la
tienda y el taller y el asistente pueden recomendarlo. Mantener el llenado en cero indefinidamente
no protege nada que las compuertas del aplicador no protejan ya por producto.

## Base de la decisión

| Artefacto | Qué prueba | SHA-256 |
|---|---|---|
| `global-coverage-summary-2026-09-16.json` (auditoría global releída a las 09:17Z) | 1.594 físicos con plantilla, 20 sin ella y ya adjudicados, cero bloqueantes, 461 con observaciones, un hecho fuera de plantilla | `bcd6d2af0d44687314c7713a11e60ef89d75cc5d707ff49302fefd5f2d687e20` |
| Este documento | La decisión, sus límites y las reglas de cada lote | su propio sha256 se registra en la readiness al insertarla |

El sha256 de este documento se calcula después de escribirlo y queda en
`product_spec_research_readiness.review_sha256` y en `progress-measurement-2026-09-08.json`;
el registrador recalcula ambos hashes sobre los archivos antes de registrar cualquier aplicación.

Lo que ya estaba cerrado antes de decidir: 105 de 105 plantillas planificadas publicadas;
724 asignaciones reparadas con recibo; 37 reemplazos originales activos; aplicador publicado y
probado; registrador revisado; flags de visibilidad publicados (100 de 107 plantillas con campo
visible); definiciones con consumidores y matriz por familia auditadas.

## Lo que sigue abierto y por qué no bloquea

- La compatibilidad de taller lee 44 claves retiradas. No bloquea: un producto llenado con
  claves nuevas no produce un veredicto falso, sólo cautela; la migración del consumidor se
  hace familia por familia y cada lote nombra si su familia ya está migrada.
- 20 productos sin ficha por identidad insuficiente y un resorte asignado como freno de llanta.
  No bloquean: no entran en ningún lote hasta resolver su identidad.
- Campos críticos derivados sin revisar. No bloquean: el cierre de un lote se mide por hechos
  con evidencia y por lectura posterior, no por ese borrador.

## Reglas de cada lote (condiciones de la readiness)

1. Un producto por aplicación, con preimagen fresca capturada como el actor autenticado real
   (`7bb76d88…`, administrador del tenant Viñabike) y comparada en el momento de aplicar.
2. Identidad antes que medidas: marca, modelo y edición resueltos con fuente; sin edición no se
   copian eslabones, tallas, colores ni contenidos de una variante parecida.
3. Cada hecho con evidencia archivada y su sha256; procedencia real (`catalog` para referencia,
   `research` para investigación); ningún hecho confirmado por mecánico se pisa sin conflicto
   resuelto por escrito.
4. Revisión por un agente distinto del investigador: hoy, una sesión de Claude distinta de la que
   investigó (`claude-peer`), con contexto fresco, que lee la propuesta y la evidencia sin el
   razonamiento del investigador. Es más débil que un modelo de otro proveedor y queda dicho.
5. Simulación sin escritura, registro con SQL guardado y recibo, aplicación con recibo, lectura
   posterior completa del producto y de sus observaciones no tocadas.
6. Lotes pequeños y por familia, empezando por las de fuentes fuertes (cadena y conector,
   cassette, neumático, cámara, rotor). Un lote se detiene al primer recibo inconsistente o al
   primer `40001` no explicado.
7. Ningún flag comercial, precio, stock ni documento se toca desde el llenado.

Llenado técnico persistido en el momento de esta decisión: 0.
