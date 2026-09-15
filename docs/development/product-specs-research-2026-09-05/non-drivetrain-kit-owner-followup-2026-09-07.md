# kit_members: quién es dueño de qué — y qué impide activar las 12 familias

Revisión independiente, 2026-09-07. Corrige mi propio hallazgo **PUB-D01** de
`non-drivetrain-publication-readiness-2026-09-07.json`
(`ce9db0e8b79977da97f62171818cb18a8461713231eeaf14999db56507dda810`) antes de que lo integres.

Catálogo leído: `all-family-port-cardinality-integrated-2026-09-07.json`
(`16459826fee4c589cce37243afe4e159317212ddf1d47d6d6f1d76f9b3fadf15`).
Checkpoint leído: `release-checkpoint-2026-09-07.md`
(`cf49fb2b2b8116760550d8eeb4e6c7c196c2c2aee6a331e588f542106b92173a`).

Sólo lecturas de artefactos y código, y una búsqueda pública. Sin base de datos, sin runtime, sin
git, sin tocar catálogo, código compartido ni migraciones. Las cuatro compuertas siguen en `false`.

## 1. PUB-D01 se retira

Tenías razón en desconfiar. Mi hallazgo decía que admitir `family=light` fuera de la plantilla
`light` reabre el segundo dueño de los datos de la luz. Es falso, por cuatro razones que se
comprueban por separado.

**`kit_members` no tiene ninguna columna de especificación.** Sus seis columnas son `member_role`,
`family`, `quantity`, `position`, `identity_brand` e `identity_model`, bajo el rótulo «Componentes
incluidos». Declaran qué trae la caja, cuántos y en qué posición. No hay batería, ni modos, ni
lúmenes, ni norma, ni grado IP. Una tabla sin columnas de dato no puede ser dueña de un dato.

**El dueño real está identificado y es otro.** `light_member_configurations` —rótulo «Luces del
producto (una fila por luz)»— tiene tipo, capacidad y voltaje de batería, conector de carga, tipo y
diámetros de soporte, zona de montaje, grado y norma IP, y revisión. `light_mode_configurations`
enlaza a ella por `member_id` a través del link `light_member_link` del `row_coherence` de la
familia. Puestas al lado, sólo una de las dos tablas contiene especificaciones.

**Ninguna de las dos tiene consumidor.** `grep -rn "kit_members" lib` y
`grep -rn "light_member_configurations" lib` no devuelven nada. Sin lector no puede haber
transferencia de identidad, modos ni certificación: no hay a dónde transferirlos.

**El estrechamiento de `light` es local y tiene otro motivo.** `light` es la única de las 23
plantillas que usan `kit_members` con `row_conditions` sobre el campo: sus `allowed_options.family`
son las 105 claves menos `light`. Eso impide que una luz liste luces como contenido genérico cuando
sus miembros ya viven en `light_member_configurations` con su `member_id` — es desambiguación entre
dos tablas de la misma familia, no un invariante global. Ese motivo no existe en `lock` ni en
`rider_protection`, que no tienen dueño alternativo de miembros.

**Lo que no pude sostener.** Busqué además un producto real que el estrechamiento prohibiría en esas
dos familias, y no lo encontré con fuente primaria. El caso más cercano, el ABUS BORDO 6000C LED,
tiene un LED integrado que ilumina la ventana de la combinación — texto indexado, la página devuelve
403 a mi lectura — y eso es una función del candado, no una luz de bicicleta entregada en la caja.
Así que **no** sostengo que el estrechamiento sea dañino. Sostengo que es innecesario por el motivo
que yo di, que era lo que tenía que comprobar antes de escribirlo.

**No integres PUB-D01.** `family` se queda sin estrechar fuera de `light`.

## 2. Dónde sí podría haber una transferencia falsa (KIT-R01)

No es la familia: es el texto de identidad. `identity_brand` e `identity_model` nombran la identidad
de un producto sin id y sin `parent_set_id`.

La membresía real de este ERP es `parent_set_id`, con `set_type`, `component_label`,
`component_position` e `is_set`, y ésa sí tiene consumidores: `public_inventory_service`,
`shared/models/product`, `shared/services/inventory_service` y `smart_purchase_list_service`. Ahí
cada miembro es un producto del catálogo con su propia ficha y su propio dueño de especificaciones.

Un consumidor futuro que uniera marca y modelo de `kit_members` con el catálogo estaría inventando
una membresía que nadie declaró. Es exactamente la regla que ya está escrita: los nombres no se usan
como join.

**La corrección mínima es una nota, no un motor.** Un helper en `kit_members` que diga que la tabla
declara contenido y no es dueña de ninguna especificación; que un miembro que además es un producto
del catálogo se expresa por `parent_set_id`; y que `identity_brand` e `identity_model` son texto
declarativo que no se une al catálogo. No hace falta guardia mecánica hoy porque no hay lector que
guardar; la guardia va en el consumidor, cuando exista.

## 3. Un hallazgo que va en la dirección contraria (KIT-R02)

`family` es **requerida** y su vocabulario son las 105 claves de plantilla, **sin «Otro»**.
`member_role`, en cambio, sí ofrece `otro`. Un kit que trae algo cuya familia no está en la lista, o
que el operador todavía no determinó, no tiene forma de guardarse: la fila queda incompleta y no hay
token con que decir «aún no sé».

Es lo contrario de lo que yo había reportado: el vocabulario no está demasiado abierto, está
demasiado cerrado. Y como las opciones son las claves de plantilla, agregar una familia mañana
cambia este enum para las 23 plantillas que lo usan, incluidas las que se publiquen ahora.

No propongo el token todavía. No miré datos de producto y no sé con qué frecuencia aparece un
contenido indeterminado; lo dejo con su evidencia para que lo decidas contra la auditoría de
adopción que ya tienes.

## 4. Casos ejecutables

| id | tipo | plantilla | fila | esperado |
|---|---|---|---|---|
| KIT-P1 | positivo | `lock` | `family=light`, `quantity=1`, marca y modelo declarados | sin incidencia |
| KIT-P2 | positivo | `rider_protection` | `family=light`, `quantity=1`, `position=Trasero` | sin incidencia |
| KIT-N1 | negativo | `light` | `family=light` | `row_option` bloqueante (estrechamiento existente) |
| KIT-N2 | negativo | `lock` | `family=light` + `identity_brand/model` reales | sin incidencia hoy; lo que nunca debe ocurrir es que un consumidor una ese texto con el producto del catálogo |
| KIT-U1 | desconocido | `lock` | sin `family` | `row_incomplete` no bloqueante — ver KIT-R02 |
| KIT-U2 | desconocido | `lock` | ninguna fila; iluminación integrada de la ventana de combinación | correcto: una función no es un contenido |

KIT-U2 es la distinción que evita el kit inventado: el LED del BORDO 6000C es una función del
candado y no corresponde una fila de contenido.

## 5. ¿Hay impedimento estructural para activar las 12 plantillas?

**No lo hay.**

`spec_templates` tiene una sola columna de estado, `is_active boolean not null default true`. No hay
columna de publicación, ni dependencia entre plantillas, ni compuerta global en el esquema. Las
cuatro compuertas que usamos viven en el artefacto de propuesta, no en la base. La activación es por
fila y es **ortogonal al llenado**: activar una plantilla no autoriza escribir un solo hecho. Las 12
son `origin: new`, así que activarlas es crearlas, no reactivar algo con historia.

**Hay una consecuencia finita que conviene tener por escrito antes de activar.**
`products.spec_template_active_guard` es una columna generada siempre `true`, con clave foránea
compuesta `(spec_template_id, spec_template_active_guard) → spec_templates(id, is_active)`. Mientras
ninguna ficha esté ligada, activar y desactivar es libre; en cuanto un producto se liga, poner
`is_active` en `false` viola esa clave. Activar es barato; **desactivar después de ligar exige
desligar primero**. `category_tech_mappings` tiene la misma guarda para sus mapeos activos.

No comprobé en producción si alguna de las 12 claves ya existe como plantilla de sistema: no leí
base de datos. El índice único sobre `key` con `tenant_id` nulo lo haría fallar ruidosamente si
existiera.

## Cuentas

Defectos retirados 1 · hallazgos residuales 2 · casos ejecutables 6 · columnas de especificación en
`kit_members` 0 · consumidores de `kit_members` 0 · impedimentos estructurales para activar 0.

Compuertas sin cambio: `fill_allowed`, `compatibility_rules_integrated`,
`all_product_assignment_review_complete`, `all_family_domain_review_complete` — todas `false`.
