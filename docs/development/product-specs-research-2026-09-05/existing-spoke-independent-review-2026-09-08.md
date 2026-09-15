# Rayos: revisión independiente de Claude, 2026-09-08

Resumen público redactado por Root después de recibir la revisión de Claude.
El informe completo se conserva, sin alteraciones, en
`.tmp/product-spec-catalog/existing-spoke-independent-review-original-20260908.md`.
Se omiten los nombres/medidas de productos concretos de la tienda y sus fixtures
privadas. Este resumen conserva las objeciones, no sustituye la adjudicación.

SHA-256 del informe original: `3ecbccbd4788df83d9a5449aaa672ba9096ca360af00d4458c90bf0e477d05d8`.
Catálogo revisado: `2084d354415d74b7185c4701e97230da9be5b61482ee27a141f3bf83a6b112c3`.
Casos revisados: `1e227acbc8b5350288786f4fdb36b5c2c15902b60a416a9a853a2c0d801ae43e`.

## Objeciones reproducidas por Claude

- **B-1, evidencia de envase:** las dos tablas sólo ofrecían una URL requerida.
  Escribir allí la identificación del envase bloqueaba, mientras que dejarla
  vacía sólo quedaba pendiente. Necesitan un documento identificable que no
  requiera publicación en la web.
- **B-2, sección elíptica:** el dominio ofrecía redonda, plana/aero y otra; la
  combinación otra + ancho/espesor estaba prohibida. Sheldon distingue secciones
  elípticas y planas, por lo que falta expresar ambas sin renombrar la forma real.
- **B-3, codo:** cnSPOKE v24, páginas 26–27, publica ángulos distintos por modelo.
  El candidato carecía de destino específico para esa cota de anclaje.
- **P-1/P-2, extremo roscado:** faltan el nominal OEM de ese extremo y el largo
  roscado T. La cota nominal ØT no debe copiarse como diámetro mayor medido.
- **P-3, declaración de maza:** el fabricante publica clases de agujero/anclaje.
  Preservarlas no equivale a aprobar una maza concreta.
- **P-4, desconocido:** para decidir compatibilidad, el token desconocido y la
  falta de valor permanecen pendientes. No afirmar por ello una distinción
  entre ausencia de investigación y ausencia explícita en una fuente.
- **P-5, procedencia:** largo y referencia OEM del anclaje también necesitan
  trazabilidad. Un rótulo histórico de la tienda puede tener procedencia
  interna; no debe promoverse silenciosamente a lectura verificada del fabricante.

Claude confirmó que calibre y herramienta no son equivalentes, que las
secciones por posición conservan geometrías diferentes y que la rosca laminada
no se mide como el alambre. Reprodujo los 19 casos (20 pruebas con metadatos)
y verificó 48 productos evaluados, cero bloqueantes y 19 observaciones legacy
conservadas. Nada de esto certifica el montaje rayo–maza–niple–llanta.

## Fuentes consultadas y límites de la revisión

[Sheldon / Allen](https://www.sheldonbrown.com/wheelbuild.html),
[Park Tool](https://www.parktool.com/en-us/blog/repair-help/spoke-wrench-tool-selection)
y [cnSPOKE v24](https://cnspoke.com/wp-content/uploads/cnSPOKE_Catalogue_v24_web.pdf).
El render del PDF permitió ver una columna angular perdida por el extractor.
Las cifras de peso se refieren al largo indicado; el gráfico no proporciona
una tensión universal de montaje.

La afirmación del informe original de que no existe PDF público para otras
marcas no está demostrada por una investigación completa y Root no la acepta.
Tampoco se acepta que URL deba convertirse en texto libre: la solución conserva
URL como URL y añade identificación del documento/envase por separado.
El vínculo por fila sólo identifica otra fila de esta ficha; el vínculo a una
pieza de catálogo y el veredicto sobre una combinación concreta siguen pendientes.
