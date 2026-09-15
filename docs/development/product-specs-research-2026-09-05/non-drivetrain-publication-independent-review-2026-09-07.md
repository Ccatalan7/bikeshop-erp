# Revisión independiente del despliegue de las 12 familias

2026-09-07. Revisor: Claude. Alcance: `scripts/inventory/compile_non_drivetrain_publication.py`,
`scripts/inventory/test_non_drivetrain_publication.py`,
`supabase/migrations/20260907027000_non_drivetrain_spec_templates.sql` y
`supabase/manual_checks/verification/20260907027000_non_drivetrain_spec_templates.sql`, contra
`non-drivetrain-publication-packet-2026-09-07.json`.

Sólo lecturas. No corrí base de datos, ni runtime, ni git. No rehice las 12 revisiones de familia.
Los números de línea del compilador pueden haberse movido: lo estás editando mientras reviso — vi
`generate_verifier(packet, cases)` con firma nueva —, así que nombro también el constructo.

Paquete `8de63d4b1f356e34…` · catálogo `16459826fee4c589…` · migración `6fee42d6ff828ed7…` ·
verificador `1e82388cbe47ca3b…` · compilador `fb526e7974ada9b7…` · pruebas `ede27172d62fe9b2…`
(prefijos de SHA-256; el compilador y las pruebas cambiaron en disco durante la revisión).

## Dictamen

Desplegable **después de ND-1 y ND-2**. ND-5 y ND-6 son una línea cada uno y conviene hacerlos en la
misma ronda. ND-3, ND-4 y ND-7 quedan registrados y no bloquean.

El insert es seguro en lo que más importaba: no escribe productos, no toca la definición compartida,
respeta el aislamiento por tenant y falla cerrado. Los dos defectos accionables están en la
**evidencia**, no en la escritura: el readback afirma más de lo que puede probar.

## ND-1 · `@>` es contención, no igualdad: `exact_metadata` no prueba exactitud

**Dónde.** Compilador `assertion_sql` (`not (to_jsonb(actual) @> wanted)`, ~línea 145) y
`generate_migration` (`if not (actual @> wanted) then raise exception`, ~línea 169). En los archivos
generados: migración líneas 36, 45, 54, 63 (deriva) y 74, 78, 82, 86 (readback); verificador líneas
5, 9, 13, 17. El verificador comparte `assertion_sql`, así que meterlo dentro de
`publish_and_replay` no cierra esto.

**Causa.** La contención jsonb tolera lo añadido: `X @> '[]'` es cierto para *cualquier* arreglo,
`X @> '{...}'` admite claves extra, y un arreglo contenedor admite elementos extra. Y el paquete cae
justo en el peor caso, medido sobre los 423 registros:

- `visibility_rules`, `option_rules`, `constraint_rules`: **132 de 132 vacíos** en cada uno.
- `allowed_values` y `validation_rules`: **60 de 93 vacíos**.

**Consecuencia.** Después de publicar, agregar una regla de visibilidad, una regla de opción, una
restricción, un valor permitido o una regla numérica a cualquiera de esas filas deja
`exact_metadata = 1`. Dentro del bucle es peor que un falso verde: la fila se considera ya publicada
y se **salta en silencio**. `reject_later_edit` no discrimina, porque cambia un `label` — un cambio
de valor, que la contención sí detecta; ninguna prueba cubre una edición *aditiva*.

Que ya usaras `is distinct from` para `reused_definitions` (migración 93-97) muestra que la
distinción está clara donde la quisiste exacta. Comprobación en una línea si quieres verla:
`select ('[{"a":1}]'::jsonb @> '[]'::jsonb), ('{"a":1,"b":2}'::jsonb @> '{"a":1}'::jsonb);` — ambas
ciertas.

**Corrección mínima, sin tocar el paquete.** Sustituir ambas comparaciones por igualdad restringida a
las columnas administradas:

```
(select jsonb_object_agg(e.key,e.value) from jsonb_each(to_jsonb(actual)) e
 where wanted ? e.key) is distinct from wanted
```

Deja fuera `created_at`/`updated_at` y vuelve exactas las 10/7/7/10 columnas publicadas. Es seguro
para el replay: verifiqué que **el conjunto de claves de cada registro es exactamente su tupla de
`TABLES`** en las cuatro tablas, así que no hay columna administrada ausente que haga fallar la
igualdad. Y agrega una regresión que discrimine: una edición aditiva —un valor permitido de más, o
una regla de visibilidad— debe hacer fallar el replay.

## ND-2 · La cabecera promete «sin default de categoría» y nada lo mide

**Dónde.** Migración línea 3 («No product, category default, fact, reference or compatibility
approval write») frente a `nd_publication_before`, líneas 12-15 (compilador ~187-190).

**Causa.** La instantánea cubre `spec_facts`, `products(id, spec_revision, spec_template_id,
spec_reference_id)` y `product_spec_references`. Los defaults de categoría viven en
`category_tech_mappings`, que además es la otra tabla con `spec_template_active_guard` — es decir,
la vecina directa de lo que esta migración sí toca. La promesa está afirmada, no medida.

**Corrección.** Un cuarto md5 sobre `category_tech_mappings` en el par antes/después.

## ND-3 · Qué prueba de verdad la guardia de productos (precisión, no defecto)

Con `begin isolation level repeatable read`, la lectura previa (líneas 12-15) y la posterior (99-102)
salen del **mismo snapshot**. Sólo pueden diferir por escrituras **de esta misma transacción**.

Eso es exactamente la guardia correcta para el riesgo real —un disparador o una columna generada que
alcance productos o hechos al insertar plantillas— y hay que conservarla. Pero no puede detectar una
sesión concurrente, y nunca dará falsa alarma por ello. El nombre
`product_observations_and_identity_unchanged` se lee como la afirmación amplia; lo que sostiene es la
estrecha, que es la que importa.

## ND-4 · La identidad de una opción se deriva del texto que el esquema declara libre

**Dónde.** Compilador líneas 89-93: `id = uuid5(NAMESPACE_URL, 'vinabike:spec-option:' +
definition_id + ':' + option)` y `code = 'catalog_' + md5(option)`.

**Causa.** El comentario de `spec_definition_values` dice que `code` «es la identidad estable y nunca
cambia; `label` es lo que se muestra y cambia libre. Todo lo que guarde un hecho referencia el
código, nunca la etiqueta». Aquí ambos, id y code, se derivan de la etiqueta.

**Consecuencia.** Corregir mañana una etiqueta de opción regenera id y código. En el replay la fila
vieja ya no está en el paquete, la comprobación de opciones extra (migración 90-92) divide por cero y
aborta — **falla cerrado, que es lo correcto** —, pero cuando existan hechos, el hecho apunta al
código viejo y el paquete quiere uno nuevo. Hoy no rompe nada: 186 opciones, cero duplicados dentro
de una definición, cero ids repetidos, cero hechos, y los 186 códigos cumplen
`spec_definition_values_code_shape` con 40 de los 64 caracteres.

**Corrección.** Derivar el código de un slug estable revisado una vez y guardado en el catálogo, no
de la etiqueta; o como mínimo dejar escrito en el paquete que una corrección de etiqueta se resuelve
con una migración que preserve el código, nunca con un recompilado.

## ND-5 · La nota de recuperación sólo es ejecutable mientras no haya producto ligado

**Dónde.** Migración líneas 4-5 («deactivate only these new templates… Never erase later product
edits») y `is_active: True` en las 12 plantillas (compilador ~línea 97).

**Causa.** `products.spec_template_active_guard` es generada siempre `true` con clave foránea
compuesta a `spec_templates(id, is_active)`. Tras la primera ligadura, poner `is_active=false` viola
esa clave: el rollback exige desligar productos primero, que es precisamente la edición de producto
que la nota promete no tocar.

**Corrección.** Una de dos. O declarar la ventana («reversible sin escrituras de producto sólo hasta
la primera ligadura»), o publicar con `is_active=false` y encenderlas como paso aparte de una línea
al empezar el ensayo — lo que además separa «los metadatos existen» de «se pueden asignar», que es el
objetivo declarado.

## ND-6 · La preimagen es una entrada no fijada y fuera del repositorio

**Dónde.** Compilador línea 19 (`.tmp/db/spec-nd-publication-preimage-resumed.json`), frente a
`CATALOG_SHA` que sí se afirma (líneas 52-53); la preimagen sólo se hashea hacia el paquete
(`preimage_sha256`, ~línea 109) sin valor esperado. `/.tmp/` está ignorado (`.gitignore:17`).

**Causa.** La evidencia de colisión en la que confía el compilador (`preimage['template_collisions']`,
~línea 56) viene de un archivo que no está congelado ni versionado. La migración no se puede
regenerar ni auditar desde un checkout limpio, y una preimagen rancia pasaría en silencio.

**Corrección.** Un `PREIMAGE_SHA` afirmado igual que `CATALOG_SHA`, y una copia de la preimagen en el
directorio de investigación. Tu readback de producción de las 22:06Z es la evidencia de que el hecho
hoy es cierto; lo que falta es poder reproducirlo.

## ND-7 · 93 definiciones entran con `is_filterable=false` y `sort_order=0`

El insert nombra 10 columnas; el resto toma el default del esquema. `description` queda NULL, y ahí
no se pierde nada revisado: comprobé que las 93 definiciones del catálogo sólo traen
`allowed_values, data_type, id, key, label, origin, unit, used_by, validation_rules` — no hay
descripción que dejar fuera. El orden de los campos sí se publica, en
`spec_template_fields.sort_order`.

Lo que queda decidido por omisión es `is_filterable=false` en las 93: ninguna de estas medidas será
filtrable, incluidas la certificación de casco y los alérgenos. Es coherente con «cero defaults» y es
reversible, pero conviene que sea una decisión y no un default.

## Comprobado y correcto

Lo digo para ahorrarte la ronda:

- **`references` como alias sin `AS`** (migración línea 15) es válido. Lo marqué y lo verifiqué:
  `kwlist.h` clasifica `REFERENCES` como `BARE_LABEL` en PG 14 y PG 18, y `supabase/config.toml:36`
  fija `major_version = 17`.
- El conjunto de claves de cada registro **es exactamente** su tupla de columnas (93/186/12/132), así
  que `jsonb_populate_record` nunca escribe un NULL sobre un default.
- La comprobación de colisión corre **después** de `lock table … share row exclusive` y bajo un
  snapshot posterior al lock: no hay ventana entre comprobar e insertar.
- `spec_template_fields` tiene `unique(template_id, spec_definition_id)` y el uuid5 se deriva de ese
  mismo par: id y clave única en biyección, replay estable. Cero ids repetidos en las cuatro tablas.
- `--max-rows 0` desactiva el tope y la ruta de lectura envuelve en sólo-lectura con timeout de 30 s,
  así que una división por cero en el verificador sale con código distinto de cero y
  `deploy_migration.sh` se detiene **antes** de estampar.
- Tenant uniforme en los 423 registros; ninguna fila cruza de tenant.
- `spec_evidence_source` aparece sólo en `reused_definitions`, comparada con `is distinct from` y con
  su lista completa de opciones: se lee y nunca se escribe.
- Las compuertas del paquete siguen en `false`: `product_writes`, `fill_allowed`,
  `mechanical_approval`.

## Sobre la ausencia de producto ligado

No la interpreto como asignación futura resuelta. Lo único que sostengo es lo de ND-5: **mientras** no
haya ninguna ligadura, la desactivación no necesita escrituras de producto. Cuál sea la asignación
correcta de cada producto a cada plantilla no lo toca esta revisión ni lo decide esta migración.

---

# Dictamen delta — correcciones y alcance global

Segunda pasada, 2026-09-07, sobre el diff de las correcciones y el alcance global de referencias.
No repetí la auditoría. Sólo lecturas; sin base de datos, sin runtime, sin git.

Candidato revisado: `non-drivetrain-publication-packet-2026-09-07.json` —
`313d7fe64ce9fba020fe0fff807caf03edf0d03edeb9f5b17fdac61bc9978906`.
Recalculé y **coinciden** con lo que reportaste: migración
`169aa2ec8e934a46b235bc162cc05d415759baf086b7a1332cb30169ba397186`, verificador
`e0c0b96839819946ebc07ec32c12aacb7f14afb1fa734b6e7bd3e9dcdf1e53e8`, preimagen
`dcd23323fa221cab3cc073c4cc64eabeced3d12da8b56ff37adec18f6a503292`. Casos
`778b5205bf7b659fc15c641c2669429059fb2dd4e361a67f209feeb8789fe513`. El `20260907027000` ya no existe.

**Dictamen: aplicar.** ND-1, ND-2 y ND-6 cerrados; ND-7 resuelto mejor de lo que propuse. La
corrección a metadatos globales es necesaria, no expansión de alcance, y está bien acotada. Queda
ND-5 como decisión tuya y ND-4 agravado por RLS. Dos consecuencias nuevas que conviene dejar escritas
antes de que existan hechos y referencias: Δ3 y Δ4.

## Lo que quedó cerrado

**ND-1.** `(select jsonb_object_agg(k,actual->k) from jsonb_object_keys(wanted) k) is distinct from
wanted` compara exactamente las claves presentes en `wanted`, anidadas incluidas, en las tres
posiciones: bucle (migración 40, 50, 60, 70), readback (82, 87, 92, 97) y verificador (6, 11, 16, 21).
Si una clave faltara en `actual`, el agregado da `null` y la comparación marca deriva: falla cerrado.
La regresión aditiva es la que faltaba.

**ND-2.** Fingerprint de `category_tech_mappings` en la misma transacción, líneas 17 y 114. La
cabecera ya no promete nada que no mida.

**ND-6.** `PREIMAGE_SHA` fijado (compilador línea 22) y afirmado (línea 61), con la preimagen movida a
artefacto congelado. Reproducible desde un checkout limpio.

**ND-7, mejor que mi propuesta.** En vez de documentar el default, las listas de insert ahora nombran
las columnas antes implícitas: `description, is_filterable, is_required_by_default,
is_mechanic_visible, group_name, sort_order` en definiciones, `description, default_tags` en
plantillas, `default_value_json, helper_text` en campos. Los valores siguen siendo los mismos
—`is_filterable` false en las 93— pero ahora están declarados y no heredados. Verifiqué que el
conjunto de claves de cada registro sigue coincidiendo **exactamente** con su lista ampliada
(16/7/9/12 columnas sobre 93/186/12/132 registros, cero faltantes, cero sobrantes), así que ampliar
las listas no reabrió el riesgo de escribir NULL sobre un default.

**ND-3 sigue igual y sigue siendo correcta.** Con la cuarta tabla, las dos lecturas siguen saliendo
del mismo snapshot: prueban que *esta* transacción no escribió en `spec_facts`, `products`,
`product_spec_references` ni `category_tech_mappings` —disparadores incluidos—, que es lo que
importa; no dicen nada sobre sesiones concurrentes, y no pueden dar falsa alarma.

## Δ1 · El alcance global es la corrección correcta, y no amplía el modelo

Confirmé tu hallazgo leyendo `spec_reference_global_scope_internal_v1`
(`20260907023000_product_spec_research_snapshot.sql:45-69`). Exige dos cosas: que **toda** clave de
`fact_values` resuelva a una definición con `tenant_id is null` —si no, 42501, «La referencia global
usa una definición no disponible»— y que **todo** `value_id` de un select sea una opción con
`o.tenant_id is null and o.is_active`. El paquete entrega 93/93 definiciones globales, 186/186
opciones globales y 186/186 activas.

Lo que hace decisiva la corrección es **dónde** habría fallado: el guard se invoca desde
`get_product_spec_references_v1` (línea 78), en la **lectura**. Con las definiciones ligadas al
tenant, la primera referencia OEM de una de estas familias no habría sido rechazada al escribirse:
habría roto el listado de referencias de esa familia entera, para todos los tenants.

Y no es una ampliación del modelo de compartición. La preimagen congelada lo dice sin ambigüedad:
`global_templates: 37`, `tenant_templates: 0`. Este tenant no tiene **ninguna** plantilla propia; todo
el vocabulario existente ya es global. Publicar estas 12 como globales las alinea con el único modelo
en uso en vez de abrir una superficie nueva. `idx_spec_templates_family … where tenant_id is null`
confirma que global es la forma prevista para una plantilla de sistema.

## Δ2 · Ninguna familia existente puede romperse por esta publicación

El guard inspecciona sólo los `fact_values` de las referencias **de la familia que se lee**. Esta
publicación no agrega ningún `fact_values` ni ninguna referencia, y las 12 familias nuevas todavía no
tienen ninguna. Ninguna ruta de lectura de otra familia cambia.

Tampoco hay riesgo de que una definición de otro tenant con la misma clave ensombrezca a la nueva: el
motor resuelve definiciones **a través de los campos de la plantilla**, acotado a un `template_id`
(por ejemplo 2500:366, 2200:394, 2000:299), nunca por clave suelta. El único join por clave sin
acotar que existe es `20260824550000:112`, una migración de datos de una sola vez sobre seis claves
`tube_*` fijas, ninguna de ellas entre las 93.

## Δ3 · Consecuencia nueva del alcance global: legibles por todos, editables por nadie

RLS en las cuatro tablas permite `select` sobre `tenant_id is null` a cualquier tenant, pero
`insert/update/delete` exigen `tenant_id = user_tenant_id()`. De modo que estas 423 filas quedan
**legibles por todo tenant y no editables por ninguno** desde la aplicación: sólo por `service_role`.

Dos consecuencias. Las 12 plantillas quedan visibles —y ligables, porque `products.spec_template_id`
no filtra por tenant— para cualquier otro tenant de la instancia; con 37 plantillas ya globales y cero
propias, eso es el modelo preexistente y no una exposición nueva, pero es lo que conviene confirmar
que es lo querido. Y corregir una etiqueta más adelante pasa a ser sólo por migración, lo que agrava
ND-4: el `code` y el id de opción se derivan de la etiqueta, así que esa corrección cambia la
identidad que el propio comentario de la tabla promete estable.

## Δ4 · Desactivar una opción rompe la lectura de la familia

`spec_reference_global_scope_internal_v1` exige `o.is_active` en cada opción citada. Retirar
vocabulario poniendo `is_active=false` es el gesto natural, y aquí, en cuanto una referencia OEM cite
una de las 186 opciones, deja de ser una retirada suave: pasa a ser un 42501 en la lectura de toda la
familia. Vale escribirlo ahora, mientras no hay hechos ni referencias, y no descubrirlo después.

## Comprobado y correcto en este delta

- El pin del motor apunta a **la única** definición del validador:
  `spec_validate_draft_internal_v1(uuid,jsonb,text,text,text,text)` tiene cuatro parámetros con
  default, así que la llamada de dos argumentos de los 37 drafts es esa misma función y el pin cubre
  lo que los drafts ejercitan. Si la firma no existiera, `to_regprocedure` da NULL, el md5 da NULL y
  el guard levanta: falla cerrado. Es más estricto que el patrón de 2300/2500, que acepta hash viejo o
  nuevo — apropiado para una publicación de una sola vez.
- Los 37 drafts son de sólo lectura: una CTE que llama una función `stable`, sin objetos temporales,
  así que sobreviven al envoltorio de sólo lectura de `query.sh`. El conjunto bloqueante se afirma con
  `=` (exacto) y sólo la expectativa no bloqueante usa `@>` (subconjunto), que es lo que «subset» debe
  significar; un `blocking` ausente se trata como bloqueante.
- El inventario 1664→1665 no perturba la guardia: la migración no escribe productos, y ambas huellas
  salen del mismo snapshot, de modo que un producto creado fuera está en las dos o en ninguna.
