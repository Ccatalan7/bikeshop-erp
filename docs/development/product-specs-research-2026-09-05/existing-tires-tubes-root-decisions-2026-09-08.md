# Neumáticos y cámaras: primera revisión de Root

Candidato de Claude `019fae87…7cd51d71`; 42 pruebas locales y 20 mutantes no
constituyen aprobación de las relaciones mecánicas. Las cinco familias siguen
sin activar. Root no toma aún sus cuatro archivos: Claude corrige esta ronda.

## R-1: dosis y cantidad vendida tienen dueños diferentes

Se rechaza `recommended_dose_ml <= sealant_volume_ml`. Una aplicación puede
requerir dos envases; el catálogo de un frasco de 60 ml no contradice una dosis
documentada de 120 ml. El aprovisionamiento calcula unidades necesarias.
La dosis además depende de la aplicación que describa la fuente, no sólo del
SKU del sellante. Retirar esa desigualdad, conservar las lecturas anteriores y
dar a las dosis su alcance de aplicación. Un caso que bloquea 120/60 certifica
la regla equivocada, aunque mate un mutante.

## R-2: perfil y método no identifican una configuración de llanta

`unique_by: [rim_bead_profile, mounting_method]` es demasiado grueso: dos modelos
de llanta o dos alcances documentados pueden compartir perfil y método, con
anchos o límites distintos. La fuente no es una identidad física; tampoco lo
son sólo «hookless» y «tubeless». La fila debe identificar su modelo/edición o
alcance normativo realmente declarado, mantener sus parámetros juntos y evitar
duplicar ese mismo alcance mediante otra URL. No declarar incompatible una
segunda configuración válida porque comparte una clasificación genérica.

## R-3: una observación de taller no es una declaración general del SKU

«Montaje verificado en el taller» no entra como una opción equivalente a la
declaración OEM en `claim_basis`. El contrato canónico distingue inspección de
unidad/bicicleta de facts del producto. Conservar la observación en su dueño;
no habilitar por ella la compatibilidad de todas las unidades del SKU. Cambiar
la etiqueta de la procedencia no cambia ese alcance.

## R-4: los límites atribuidos al motor necesitan adjudicación previa

- L-2 no exige modificar `kit_members` global: una definición nueva y acotada,
  con retiro legacy de la anterior para estas fichas, está autorizada en el
  encargo. La llave debe distinguir piezas realmente diferentes y detectar
  repetición del mismo miembro documentado, no usar su URL como identidad.
- El desconocido literal de `valve_type` merece una corrección de semántica o
  un sucesor acotado. Abrir permisos para que un mutante sea observable no es
  razón de producto para cambiar la aplicabilidad. Las pruebas verifican la
  regla decidida por el dominio; no deciden la regla para conseguir 20/20.
- L-1 y L-3 deben distinguir presión máxima declarada del neumático, límite
  del sistema/modelo y presión real de uso. Una cifra alta en la primera no
  prueba un montaje inflado por encima de la segunda. Las fuentes Zipp/ENVE
  deben conservar su modelo/edición y alcance; no se convierten en un techo
  global inferido de la palabra hookless. Diferentes autoridades o unidades
  tampoco son automáticamente datos contradictorios. Fuera de su alcance,
  el resultado queda pendiente de una relación verificada, no «compatible».

Las carencias aceptadas deben tener casos pendientes con el resultado requerido,
separados de los casos que prueban corrección. Un cruce conocido sin validación
no se cuenta como caso correcto por afirmar `expected_blocking: []`.

## Reutilización verificada

`ProductSpecRelation.evaluate` y `spec_relation_assess_internal_v1` ya existen.
La revisión de piñonería anterior no los había encontrado. Se debe reutilizar
su evaluación OR/AND, exclusiones y estado desconocido; integrar su resultado
con la ficha es trabajo distinto de escribir otro motor. Una alternativa no
exhaustiva que no coincide no prueba incompatibilidad física.

Fuentes del bloque: [Sheldon](https://www.sheldonbrown.com/tire-sizing.html),
[Park](https://www.parktool.com/en-us/blog/repair-help/tubeless-tire-compatibility),
[Zipp](https://www.sram.com/en/zipp/campaigns/hookless-tire-compatibility) y
[ENVE](https://enve.com/blogs/journal/hookless-rim-technology-101).
Root abrió las cuatro páginas el 8 de septiembre. Zipp redirigió a su versión
alemana: distingue presión mínima exigida por el neumático, máxima del sistema
y comprobación de compatibilidad por fabricante/modelo. Un neumático ausente
de la lista requiere consultar al fabricante; no equivale a una exclusión.
ENVE describe 120 psi como presión de ensayo de retención de un neumático de
28 mm para su aprobación, no como presión de uso autorizada. Park no garantiza
interoperabilidad sólo por el rótulo tubeless. Sheldon identifica BSD y advierte
que la anchura inflada varía con la llanta; sus pautas generales no reemplazan
las declaraciones modernas de un modelo. Estas distinciones se conservan en
el alcance de los campos y no se convierten en constantes globales nuevas.

## Segunda revisión: aún hay dos falsos veredictos

La ronda 2 resolvió parte de R-1 a R-4, pero mantiene una exclusión de Schrader
por núcleo desmontable y un caso pendiente que declara incompatible lo que no
aparece en la lista. Ambos se devolvieron a Claude antes de aceptar el bloque.
[Park VC-1](https://www.parktool.com/en-us/product/valve-core-tool-vc-1) documenta
núcleos Schrader y Presta desmontables; además, no todos los Presta lo son.
Zipp distingue ausencia de lista de prohibición, como quedó registrado arriba.
Un selector de tipo no debe fabricar el estado del núcleo y una lista abierta
no debe fabricar una exclusión. Los verdes anteriores no cierran esos cruces.

## Integración de Root después de la ronda 3

Las exclusiones falsas de Schrader y no-listado fueron corregidas. Root tomó los
cuatro archivos del candidato; Claude revisa rayos en un archivo independiente.
No hay edición simultánea del mismo bloque.

Persistían tres problemas concretos, corregidos antes de preparar el publicador:

- `application_scope = MTB tubeless` no identifica una dosis. [Stan's](https://stans.com/pages/sealant-refresh-reminder)
  distingue 29 × 2,3 y 29 × 2,5, con 118 y 148 ml respectivamente. La llave ahora
  incluye medida y condiciones de la aplicación; cambiar su URL no crea otra.
- La familia del componente del kit no puede ser otro selector libre que
  permita declarar simultáneamente sellante y herramienta. La tabla nueva
  conserva identidad, rol, cantidad y fuente; la familia la determina la
  identidad del catálogo. Una segunda etiqueta de rol no duplica la misma pieza.
- La exclusión de presión de Zipp aún carecía de alcance en sus predicados.
  Ahora identifica el sistema documentado. No aplica a otra marca ni a un sistema
  desconocido. Se retiró la supuesta aprobación de cualquier llanta con gancho:
  esa clasificación sola no aprueba un neumático. El mínimo y máximo de una misma
  declaración/unidad se ordenan; no se compara automáticamente con otra fila
  de otro sistema.

Resultado local de Root: 55 pruebas del candidato y ocho declaraciones
evaluadas por el `ProductSpecRelation.evaluate` real; las mismas ocho pasan
`spec_relation_assess_internal_v1` en PostgreSQL. Ya no es un trazado a mano ni
una copia del evaluador. Estos ocho casos siguen marcados pendientes de
**integración de referencia/editor**, no de evaluación de la declaración.
Son ejemplos de alcance, no referencias OEM registradas ni aprobación del
montaje completo. El analizador del auditor nuevo no informa incidencias.

Preimagen fresca del 8 de septiembre, `09:08:53.755921Z`: las 19 definiciones
compartidas coinciden sin modificar. Hay 264 productos ligados: 113 neumáticos,
137 cámaras, tres fondos de llanta, tres consumibles y ocho válvulas tubeless.
Los 264 productos se evaluaron: cero bloqueantes, 808 observaciones legacy
preservadas, ninguna activa sin proyectar y todos pendientes de información.
Los 50 casos SQL del formulario pasan con avance/repetición exacta y ROLLBACK;
no se confunden con la prueba de ocho relaciones. Las diferencias de códigos
SQL (`field_constraint`, `prerequisite_missing`) conservan campo y severidad.

Evidencia privada: `.tmp/product-spec-catalog/existing-tires-tubes-adoption-20260908.json`,
manifest `existing-tires-tubes-snapshots-20260908/manifest-20260908T091222949341Z.json`
y `.tmp/db/existing-tires-tubes-forward-candidate/forward-replay-and-cases.log`.

El campo publicado `tire_tubeless_ready` aún requiere adjudicación de su alcance
frente a `tire_bead_type`. [TUFO](https://www.tufo.com/en/tubular/) describe sus
tubulares con capa estanca, reparación con su sellante y montaje pegado: usar
sellante o no tener una cámara separada no aprueba montaje clincher tubeless.
No se inventa una equivalencia ni se presenta esa compuerta como verificada.
