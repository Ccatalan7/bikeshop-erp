# Piñonería: revisión de Root, candidato todavía no aceptado

La revisión conserva la separación física cassette/rueda libre/piñón fijo y
los enlaces de fila propuestos por Claude. Sus pruebas de representación no
cierran la relación con la identidad del producto ni una aprobación de montaje.
No hay activación, asignación o llenado de este bloque.

## Un producto de ocho velocidades no se convierte en 56

La [ficha de Shimano CS-HG50-8](https://bike.shimano.com/en-NA/products/components/pdp.P-CS-HG50-8.html)
declara un cassette de ocho velocidades y distintas combinaciones disponibles.
Root abrió la página y leyó esa prosa. La existencia de varias variantes de un
modelo no las convierte en el contenido de una unidad comercial. El cambio de
`sprocket_count` a «Piñones documentados en la ficha» y los valores 16/56 para
sumar alternativas se rechazan: estaban adaptando el significado del producto
a la limitación del contador del motor.

Se acepta que haga falta cardinalidad por grupo, referida al ID de una fila
destino y a su columna de total. Ese contrato debe ser una alternativa explícita
al total escalar; no conserva un `total_field` con un significado cambiado.
Ni el contador ni la referencia confirman que todas las variantes de un modelo
pertenezcan al SKU que se está editando. El catálogo de variantes/modelos y la
selección de la variante concreta deben permanecer distinguibles.

También se rechaza `source_scope` como parte de la identidad de configuración:
cambiar de apartado de un manual no crea otra combinación física. La misma
regla ya corrigió puertos, circuitos y rodamientos.

## Una explicación libre no puede levantar una incompatibilidad

La propuesta P-2 dejaría pasar cualquier discrepancia con sólo rellenar
`conditions`. Eso no cumple la petición del dueño: conserva la posibilidad de
cruces imposibles acompañados por una frase. Igualdad de dos etiquetas tampoco
demuestra el montaje completo. La comparación de interfaces y los requisitos
de adaptadores deben referirse a relaciones dirigidas verificadas y versionadas,
con los parámetros del montaje comprobados; la fuente y el comentario dan
trazabilidad, no una excepción ejecutable a la validación.

El caso positivo XD sobre XDR que aporta Claude requiere su separador concreto,
no sólo un comentario. Un caso negativo actual evita depender de una suposición
por marca: [SRAM distingue expresamente XS-797/XD de XS-797S/XD SLIM](https://support.sram.com/hc/en-us/articles/46508211430043-What-is-the-new-XD-SLIM-driver-body-standard-How-is-it-similar-to-the-HG-SLIM-standard)
y niega el cruce entre ambos. Root abrió y leyó esa afirmación. Una justificación
libre no puede habilitarlo; XD SLIM tampoco debe caer silenciosamente en XD.
Cambiar el cuerpo de una maza por otro es una intervención diferente del montaje
del cassette sobre el cuerpo actual.

[Park Tool](https://www.parktool.com/en-us/blog/repair-help/determining-cassette-freewheel-type)
describe los dos sistemas de fijación y advierte que extractores parecidos no
son intercambiables. [Sheldon Brown](https://www.sheldonbrown.com/k7.html)
separa combinaciones, espaciadores y excepciones de cuerpos concretos. Sus
generalizaciones históricas sobre 7–11 velocidades no se promueven a reglas
universales modernas; se contrastan con modelo y edición OEM.

La siguiente corrección es de estos propietarios y prerrequisitos. P-2 queda
rechazada como autorización por texto libre; no se implementa en el motor para
hacer pasar sus fixtures. P-1 queda pendiente de integración genérica revisada,
con casos que conserven el número de velocidades del producto.

## Segunda revisión de Root: el dueño del catálogo no cambia por separar tablas

La corrección de Claude recupera el número de coronas del SKU, elimina
`source_scope` de la llave y retira la justificación libre. Son correcciones
aceptadas. P-2′ es una propuesta pendiente, no una garantía de montaje ya activa.
Debe aprovechar la semántica de alternativas/exclusiones de
`ProductSpecRelation` y sus fuentes antes de duplicar otro evaluador. Un
parámetro desconocido y uno contradicho son estados diferentes; no deben
compartir un error que diga «falta» para ambos.

Queda un problema de propietario: `cog_configurations` y
`cog_configuration_teeth` están propuestos como facts de cada producto para
guardar **todas** las variantes del modelo. Que estén en tablas diferentes de
`cog_sequence` no los convierte en catálogo de referencias. El contrato
canónico §4.1 distingue explícitamente referencias OEM del inventario tenant.
Para cassette/rueda libre, las alternativas del modelo pertenecen a ese
catálogo; sólo la variante resuelta y su procedencia llegan a la ficha del SKU.
No se deben activar esas dos definiciones como campos del producto para
resolver esta carencia. Esto no impide configuraciones de montaje realmente
admitidas por el mismo SKU ni conjuntos de varias piezas incluidas.

La capacidad genérica P-1 ya tiene un
[candidato V3 local con pruebas Dart y SQL](grouped-cardinality-engine-candidate-2026-09-08.md).
No exige incorporar el catálogo completo del modelo a los facts del producto.
Los casos de variantes pueden demostrar el motor como fixtures de referencia,
sin legitimarlos como ubicación productiva. Pendientes: integración/revisión
del motor y corregir ese dueño en el candidato de piñonería.

## Tercera revisión — 2026-09-08: reutilizar también la evaluación existente

El candidato `21b3b278…329fd15b` retira las dos tablas de alternativas de
los facts del SKU y conserva las siete variantes OEM en `oem_variant_reference`,
marcado `is_product_fact: false`. Se acepta esa corrección de dueño; no habilita
activación. El candidato genérico P-1 queda local y no es requisito de estas
cuatro familias. No se publica una extensión porque ya se haya invertido en ella.

La afirmación posterior de que «ProductSpecRelation no tiene evaluador» es
incorrecta. `ProductSpecRelation.evaluate` ya existe, junto con pruebas
`product_spec_relation_test.dart` y su pareja SQL
`spec_relation_assess_internal_v1`, definida en la migración 20260906180000.
Evalúan condiciones tipadas, alternativas OR y exclusiones prioritarias,
y conservan el estado desconocido. El uso actual del resumen en
`product_spec_contract.dart` no demuestra que falte esa implementación.
Lo pendiente es integrar relaciones versionadas de fuentes verificadas con la
configuración concreta y el validador de la ficha, sin inventar otro evaluador.

Hay una distinción adicional: no satisfacer una alternativa no exhaustiva
produce `outside_declared_scope`, no prueba incompatibilidad mecánica. Para
rechazar un parámetro de una receta elegida se debe identificar esa receta y
su requisito obligatorio. No se cambia la semántica general para convertir
cualquier falta de cobertura positiva en conflicto. Las exclusiones OEM
explícitas siguen bloqueando y un comentario nunca las levanta. Esta revisión
separa integración faltante de motor inexistente antes de abrir más código.
