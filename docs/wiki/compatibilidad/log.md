# Registro del wiki de compatibilidad

Una línea por operación, la más nueva arriba: `fecha — operación — qué cambió`.
Operaciones: **ingesta**, **consulta archivada**, **revisión** (lint), **corrección**.

- 2026-10-23 — corrección — [ruedas y neumáticos](paginas/ruedas-y-neumaticos.md):
  la tienda pública ofrece las cámaras que calzan con un neumático (mismo BSD,
  ancho dentro del rango de la cámara) y los neumáticos de una cámara.
- 2026-10-02 — corrección — la prueba de contrato encontró lo que el wiki no
  nombraba: 6 campos de la bici que el motor lee (`drivetrainPlatform`,
  `drivetrainPlatformFamily`, `shiftActuationFamily`, `largestCogTeeth`,
  `rearLargestCogTeeth`, `chainWidthFamily`) y 2 familias (fondo de llanta y kit
  de transmisión). Agregados al mapa, cadenas, cambios y ruedas. Nacen el hook
  `compat_wiki_router.py` y la prueba `compatibility_wiki_contract_test.dart`.
- 2026-10-02 — consulta archivada — probando el wiki con bicis reales: la bici
  guarda en `drivetrainSpeeds` las marchas totales (21 en 3×7) y el motor saca los
  piñones de `drivetrainConfig`; y `shimano_hg` no distingue el núcleo de 7 del de
  8-10 (un cassette de 7 queda *con condiciones*). Anotado en cadenas, cambios,
  núcleos y el mapa.
- 2026-10-02 — creación — el dueño pidió el wiki con Sheldon Brown y Park Tool
  como fuentes principales y una investigación a fondo de Bike Matrix. Se
  escribieron 22 páginas, 4 fichas de fuente, el esquema (README), la skill
  `.claude/skills/compatibilidad/` y el lint
  `scripts/knowledge/lint_compat_wiki.py`. Lecturas de producción usadas: 902
  definiciones de ficha; 480 bicis del taller, 473 sin año; 1.635 productos
  activos, 5 con EAN válido y ninguno con código de fabricante.
- 2026-10-02 — ingesta — Sheldon Brown: 15 páginas (crib sheets de neumáticos,
  espaciado, pedalier roscado y press-fit, BCD, manubrio, dirección; speeds, k7,
  mezcla de marcas, cadenas, cables, pedales, tire sizing).
- 2026-10-02 — ingesta — Park Tool: normas de pedalier y dirección, cadenas,
  cassette/rueda libre, neumáticos y tubeless, rotores, líquidos, fundas.
- 2026-10-02 — ingesta — Bike Matrix: sitio, FAQ, documentación del SDK, eventos,
  estados de la etiqueta, blog, repositorio de ejemplos y dos análisis de
  terceros.
- 2026-10-02 — mantenimiento — dirección y cockpit en la ficha de la bici
  (20261002170000): siete claves, filas sin rueda con décimas, la regla del tipo
  para la zona de mandos y `assessCockpitCompatibility`; datos reales: ninguna
  dirección del inventario dice su SHIS.
- 2026-10-02 — mantenimiento — la potencia sale de la relación de la ficha: con
  laina, una de 31,8 aprieta un manubrio de 25,4, y la regla «tiene que
  calzar» bloqueaba terminar ese trabajo. La revisa sólo la matriz de la app.
- 2026-10-24 — nueva página — [palabras del taller chileno](paginas/palabras-del-taller.md):
  cada parte como se pide en Chile, contada en los pedidos de los clientes del
  taller (motor 21 contra pedalier 1, piola 14 contra cable 0, patines 5
  contra zapatas 0). El dueño: «not a fucking single soul calls the bottom
  bracket that way, many people just say motor». El buscador del catálogo la
  usa como datos (`catalog_search_terms`).
- 2026-10-24 — [Palabras del taller](paginas/palabras-del-taller.md): la tienda
  agrega palabras desde «Búsquedas» del ERP, con lo que la gente buscó y no
  encontró; los grupos tienen nombre con tildes (`20261024080000`).
- 2026-10-25 — «Disco» solo es el rotor y «cassette 7v» lo dice también quien
  tiene piñón con rosca; el buscador descarta lo que contradice la medida
  pedida ([palabras del taller](paginas/palabras-del-taller.md)).
