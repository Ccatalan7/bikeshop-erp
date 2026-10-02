# Registro del wiki de compatibilidad

Una línea por operación, la más nueva arriba: `fecha — operación — qué cambió`.
Operaciones: **ingesta**, **consulta archivada**, **revisión** (lint), **corrección**.

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
