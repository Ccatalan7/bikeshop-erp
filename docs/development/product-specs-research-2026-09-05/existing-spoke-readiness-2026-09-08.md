# Rayos: candidato con posiciones físicas y contenido identificado

**Publicado el 2026-09-16** como `20260916040000_spoke_successor.sql` sobre 58 productos; ver [spoke-successor-adjudication-2026-09-16.md](spoke-successor-adjudication-2026-09-16.md). Lo que sigue es el estado del candidato al 2026-09-08.

Estado: una plantilla original, 20 definiciones, 31 casos y la comprobación de
metadatos Dart pasan localmente. No aplicada. Ni investigación de identidad ni
llenado de productos ejecutados por este compilador. Los 48 productos ligados
se capturaron por API autenticada, sin errores ni escrituras. Ensayo de adopción:
48 evaluados, cero bloqueantes, 19 observaciones legacy preservadas, ninguna
observación activa sin proyectar y los 48 pendientes de información. No son
48 productos rellenados ni mecánicamente certificados.

PostgreSQL local pasó avance, repetición exacta y los 31 casos con ROLLBACK.
Dos códigos de error SQL son `field_constraint` donde Dart informa `row_shape`
o `integer`; se explicitan en las fixtures, sin cambiar el bloqueo ni el campo.
La [revisión independiente del candidato anterior](existing-spoke-independent-review-2026-09-08.md)
detectó tres carencias: exigencia de URL incluso cuando existe un documento o
envase, ausencia de sección elíptica y ausencia de cotas del anclaje. El candidato
actual las corrige. La [revisión del delta](existing-spoke-delta-review-2026-09-08.md)
confirmó las siete correcciones sin bloqueos nuevos. Su observación menor D1
también se corrigió: una ficha OEM que publica nominal y largo sin designación
de rosca no obliga a inventar esa designación. La aplicabilidad y la fuente
permanecen; el montaje sigue requiriendo evidencia. Pasan 32 pruebas Dart.
La [revisión final de D1](final-dimensional-delta-review-2026-09-08.md)
confirmó esa corrección y la conservación de aplicabilidad y procedencia.
La revisión no demostró ausencia de fuentes públicas para las otras marcas:
esa afirmación no se utiliza para cerrar investigación ni devolverla al dueño.

## Decisiones y fuentes verificadas

[Park, selección de llave de niple](https://www.parktool.com/en-us/blog/repair-help/spoke-wrench-tool-selection)
separa el calibre del radio de la medida de llave y distingue formas/zonas de
acceso de la herramienta. Por ello, la ficha de rayos no deduce la herramienta
del calibre ni duplica la especificación de una pieza incluida sin identidad.
La fila de contenido identifica el niple; su familia conserva sus interfaces.

[Sheldon / Allen, Wheelbuilding](https://www.sheldonbrown.com/wheelbuild.html)
separa las secciones del alambre y la rosca laminada; también advierte sobre
convenciones de calibre. El sucesor retira como legacy el selector que mezclaba
etiquetas y secuencias, conserva la designación literal y da posición y forma
a cada sección de esta variante. La forma abre diámetro redondo o ancho/espesor
plano o elíptico; ninguna transforma una lectura en compatibilidad con una maza.
La sección elíptica conserva su identidad y no se reclasifica como plana.

Se leyó visualmente [cnSPOKE v24](https://cnspoke.com/wp-content/uploads/cnSPOKE_Catalogue_v24_web.pdf),
pliego PDF 14, páginas impresas 26–27. La tabla identifica STD14C y otras
variantes, distingue material, geometría y peso referido a largo de 260 mm.
El gráfico de carga no se convierte en tensión recomendada de montaje. La
columna ØT se conserva como diámetro nominal OEM, separado del diámetro mayor
medido. Se añadieron largo de rosca y ángulo del codo documentados; no se fija
el ángulo en 90 grados. Tampoco se identifica automáticamente un producto llamado STD14
como STD14C, ni se aplica su ficha J-Bend a un producto Straight Pull.

La forma física es de este SKU: no se incorporan los largos y modelos de toda
la tabla OEM. El número 144 de un envase es contenido; no es modelo ni largo.
Niples de repuesto adicionales son posibles: no se fuerza igualdad de cantidades.

## Conservación y dependencias

Las cinco definiciones ya publicadas y sus IDs se mantienen intactos. El antiguo
calibre y el anclaje de dos opciones siguen presentes como legacy, sin conversión
silenciosa. El nuevo anclaje admite desconocido y otra referencia OEM.
Declarar ausencia de rosca prohíbe datos de esa rosca; declarar ausencia de niples
prohíbe su contenido. Falta de confirmación conserva esos datos como pendientes.

Las secciones se individualizan por posición desde maza a niple, con zona y
fuente. Un mismo puesto no admite dos filas contradictorias. Las cantidades y
dimensiones de fila usan el transporte decimal exacto en texto del motor.
La fuente de fila admite documento/envase/referencia identificable; la URL
opcional sigue tipada como URL. Largo, designación, cotas de rosca y anclaje
dependen de procedencia. La clase de agujero de maza es una declaración OEM,
no una aprobación universal de una maza a partir del diámetro.

## Límites abiertos

El cruce rayo–maza–niple–llanta requiere modelos y condiciones documentadas.
La plantilla no certifica ese conjunto sólo porque el diámetro o largo coincida.
La integración de relaciones OEM y el alcance exacto de las dimensiones todavía
requieren cierre. No se añaden constantes universales de paso, tolerancias,
ángulo, par ni tensión. Una aprobación independiente y la distribución del
cliente siguen pendientes antes de activar esta original.

Evidencia privada: `.tmp/product-spec-catalog/existing-spoke-final-delta-tests.log` y
`existing-spoke-snapshots-20260908/manifest-20260908T085828952693Z.json` dentro de
ese directorio. La preimagen actual de publicación está en
`existing-spoke-review-preimage-2026-09-08.json`, SHA-256
`4d62f70e114ea85457a1f4d29e8120dbef86edd418374dffe7fb7ca25ddaab3c`.
Ensayo actualizado: `.tmp/product-spec-catalog/existing-spoke-final-delta-adoption-20260908.json`.
SQL: `.tmp/db/existing-spoke-final-delta-candidate/forward-replay-and-cases.log`.
Catálogo SHA-256 `4a604b432a05f598dc3d1233880c111e4714fed986a6823b71a3292142f2353f`;
casos `c3e3668e8d9124d72cb35a8c96c262238e9857ae9c78e4bf6b59649e565e5c4d`.
