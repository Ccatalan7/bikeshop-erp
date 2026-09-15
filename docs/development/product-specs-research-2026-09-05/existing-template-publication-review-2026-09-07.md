# Infraestructura de actualización de las 37: revisión independiente

2026-09-07. Revisión acotada y sólo lectura del publicador de plantillas
existentes. No edité ningún archivo de root, no toqué git, runtime ni base
productiva. Corrí regresiones locales en un arnés propio, dentro de
transacciones que terminan en `rollback`, y **sin escribir sobre los logs de
root**: mi salida vive en el scratchpad de la sesión.

**Veredicto: la infraestructura sirve para lo que dice servir.** Los tres hashes
coinciden, la aritmética de revisión es correcta y la comprobé de forma nativa,
y el empalme con el publicador probado conserva todas sus protecciones. Hay **un
defecto concreto** que arreglaría antes de usarla con las 37, y dos anotaciones
menores.

## Lo que verifiqué

- **Los tres hashes** de root: coinciden los tres.
- **La preimagen de las 37**: SHA `0a21d85a…b2a6`, igual al declarado. 37
  plantillas, 280 usos, 150 definiciones compartidas capturadas, capturada
  03:50:11Z.
- **Once regresiones SQL locales con rollback**: las siete de root, replicadas
  en un arnés mío, más cuatro que su suite no cubre. Las once pasan.
- **Ocho sondas de rechazo** sobre el compilador y una novena sobre el alcance
  de varias plantillas.
- **El disparador nativo de revisión**, leído en
  `20260906070000_product_spec_contract.sql:889-916`, y contrastado con la
  aritmética del paquete.

## La aritmética de revisión es correcta, y lo comprobé contra el disparador

El paquete predice `revisión_anterior + 1 si cambió el contrato + 1 por cada
campo modificado o nuevo`. Leído el disparador, eso es exactamente lo que
produce la base:

- `spec_templates` BEFORE UPDATE sube uno **sólo** si cambian `form_contract`,
  `is_active` o `technical_family`; si no, conserva. La migración actualiza
  únicamente `form_contract`, así que aporta uno y sólo cuando de verdad cambió.
- `spec_template_fields` AFTER INSERT/UPDATE/DELETE sube uno por fila. Los
  parches se emiten sólo donde alguna columna editable difiere, así que un campo
  intacto no recibe `UPDATE` y no aporta revisión.
- Las opciones nuevas se insertan **antes** que los campos nuevos, así que su
  disparador no encuentra todavía ningún campo que apunte a esa definición y no
  suma una revisión espuria. El orden importa y está bien puesto.

No me quedé en el razonamiento. Añadí dos casos propios: uno afirma dentro de la
transacción que la `contract_version` publicada es **exactamente** la que el
paquete predijo, y otro que un replay exacto **no** la mueve. Los dos pasan. Es
además lo que hace significativa la aserción de replay del propio publicador,
porque `assertion_sql` compara las claves presentes en el registro deseado y
`contract_version` es una de ellas: una predicción equivocada convertiría el
segundo pase en «preimage drift» en vez de en un retorno silencioso.

## El empalme conserva las protecciones del publicador probado

La migración se arma cortando el publicador de metadata nueva y reinyectando el
cuerpo. Comprobé sobre el SQL generado que sobreviven: aislamiento `repeatable
read`, `lock table` sobre las cuatro tablas de metadata, el pin del motor
`ac0738d5…1721`, y la huella de negocio de cuatro tablas —`spec_facts` entera,
`product_spec_references` entera, `category_tech_mappings` entera y `products`
por `(id, spec_revision, spec_template_id, spec_reference_id)`—, tanto como
precondición como postcondición.

Esa elección de columnas en `products` está bien hecha y conviene decirlo: coge
justo lo que ata un producto a su plantilla y a su revisión, así que detecta un
binding nuevo o una revisión movida sin romperse porque alguien cambió un precio
durante la ventana.

El SQL generado **no contiene ningún `DELETE`** y escribe sólo en las cuatro
tablas de metadata. Ninguna observación puede perderse por esta vía.

## Rechazos: qué se niega, comprobado

| Sonda | Resultado |
|---|---|
| definición compartida con unidad editada | *Shared definition must remain unchanged* |
| definición viva re-declarada como `new` con otro id | *Shared definition must remain unchanged* |
| `technical_family` distinta | *Template identity, family and activation are immutable* |
| conjunto de familias que no calza | *Explicit existing-template scope required* |
| casos de otro catálogo | *Cases must belong to the exact reviewed catalogue* |
| sin adjudicación | *Domain adjudication must be explicit* |
| definición sobrante en el catálogo | *Only definitions used by the reviewed templates belong here* |
| campo existente eliminado del candidato | *Retire existing fields explicitly; never remove observations* |

La segunda fila es la que implementa «si el origen histórico dice `new` pero
está vivo, se reutiliza sin tocar»: el publicador no lo normaliza, lo **rechaza**,
que es lo correcto porque la reutilización es una decisión de quien adjudica.

Y las cuatro regresiones locales que añadí a las siete de root:

| Caso propio | Resultado |
|---|---|
| la revisión publicada es la predicha | pasa |
| un replay exacto no mueve la revisión | pasa |
| un campo **añadido** por otro entre preimagen y publicación | *preimage drift* |
| un campo **borrado** por otro entre preimagen y publicación | *preimage drift* |

Las dos últimas importan con 863 bindings efectivos y me parecían el hueco más
probable; no lo son. De paso quedó a la vista que existe un índice único sobre
`(template_id, spec_definition_id)`, que es justamente lo que hace segura la
clave con que el compilador empareja campo viejo y campo deseado.

## El defecto concreto: nombre, descripción, etiquetas y activación se descartan en silencio

`desired_templates` reconstruye cada fila desde la preimagen y le pega **sólo**
`form_contract`, y después reemplaza entero `records['spec_templates']`. El
efecto medido: un candidato que propone otro `name`, otra `description`, otros
`default_tags` o `is_active` distinto **compila verde, publica verde y no cambia
nada de eso**, sin una sola señal.

Lo comprobé: candidato con `name='Nombre nuevo'` → el paquete sale con el nombre
viejo, sin aviso. `key` y `technical_family` sí se comparan y se rechazan; estas
cuatro columnas no se aplican **ni** se rechazan.

Con 37 plantillas existentes en revisión, donde es muy probable que alguna quiera
un rótulo mejor, eso es divergencia silenciosa entre lo revisado y lo publicado:
alguien aprueba un candidato leyendo un nombre que nunca va a existir.

**Mi recomendación es rechazar, no aplicar**, y por una razón del disparador: un
`UPDATE` de `name` **no** sube la revisión, porque el disparador sólo mira
`form_contract`, `is_active` y `technical_family`. Aplicar nombres cambiaría lo
que el operador ve sin invalidar ningún editor abierto. Una comparación explícita
que falle con un mensaje propio cuesta cuatro líneas y deja la decisión donde
está el resto: en la adjudicación.

## Dos anotaciones menores

- **Un mensaje que puede desorientar.** Si el campo eliminado deja su definición
  sin ningún uso dentro del alcance, salta antes *Ambiguous or out-of-scope
  shared definition* en vez de *Retire existing fields explicitly*. Las dos
  cierran, así que no hay riesgo; pero el mensaje manda a mirar el alcance de la
  compartida cuando el problema es un campo que desapareció. Con dos plantillas
  que comparten la definición —la forma real de las 37, donde 53 definiciones se
  usan en más de una— sí sale el mensaje específico, y lo comprobé.
- **La preimagen captura 150 compartidas y las 37 usan 128.** Las 22 restantes
  se capturan por clave porque el candidato las propone y ya existen vivas
  (`axle_type`, `hub_old_mm`, `bead_seat_diameter_mm`, `pack_quantity`…). Es el
  comportamiento correcto y es lo que permite que el rechazo de arriba funcione,
  pero conviene tenerlo escrito: **la preimagen no es «lo que usan las 37», es
  «lo que usan más lo que el candidato pretende usar»**, y esa diferencia de 22
  es exactamente el terreno donde un `origin: new` histórico se estrella contra
  una definición viva.

## Efectos sobre las compartidas

Ninguno, por construcción, y verificado: las siete propiedades de cada
definición reutilizada se comparan en el compilador y otra vez dentro de la
transacción; sus opciones se comparan completas; una opción con `tenant_id` o
inactiva aborta. El publicador **nunca** emite `UPDATE` sobre `spec_definitions`.
El único camino para cambiar una compartida sigue siendo no usar este publicador.

Con 53 de las 128 definiciones usadas por más de una plantilla, esa rigidez es la
propiedad que hace segura una actualización familia por familia: un retiro es
local al contrato y la definición sigue intacta para las demás.

## Lo que esta infraestructura no prueba

Coincido con el readiness y lo subrayo porque es donde un verde engaña: siete
pruebas de compilador y siete regresiones SQL no adjudican nada. No dicen que las
37 propuestas sean correctas, ni que una familia esté mecánicamente bien
resuelta, ni que una compartida viva deba conservar sus valores. Prueban que el
transporte no pierde identidad, no borra observaciones, no toca compartidas y no
miente sobre la revisión. La adjudicación por familia sigue entera por delante.

## Hashes verificados

| Archivo | SHA-256 | |
|---|---|---|
| `scripts/inventory/compile_existing_spec_publication.py` | `47a69120e605546e389e24b4b7d733a93b1fb0affce78ac1a13489cdb08de95e` | coincide |
| `scripts/inventory/test_existing_spec_publication.py` | `8ea50a9fbd33f2f7d64514977e2586deca83ea4e0ec4a21847cd70d94f60762e` | coincide |
| `test/scripts/test_existing_spec_publication.py` | `38bba8f44c560cf7cd5a5a0fe49ed8575a07bce0507eb62b0370268cb8c743a1` | coincide |
| `.tmp/db/existing-37-candidate-preimage.json` | `0a21d85a1539c330e661e0c5c1aa2fde0bbf29ddad67a452a018ed767d08b2a6` | coincide |
