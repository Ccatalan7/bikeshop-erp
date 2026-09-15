# Revisión independiente · etiquetas de familia en filas — 2026-09-15

Ronda 219. Sólo lectura del delta; sin código, SQL, runtime ni candidatos.
Leídos: `services/spec_engine_service.dart` `ba72c3c5…` (`getFamilyLabels`,
`decodeFamilyLabels` :338-372), `pages/product_form_page.dart` `78d49627…`
(estado :393-395, carga :1320-1321, adopción :1378, invalidación :7874,
`_specRowTokenLabels` :7632-7639 y sus dos usos :7649, :8098),
`widgets/product_spec_rows_field.dart` `9b44a7f9…` (`tokenLabels` :29-46,
resumen :238-247, selector de token :363-403),
`test/unit/product_spec_family_labels_test.dart` `bdf490db…` y el caso nuevo de
`test/widget/product_spec_rows_field_test.dart` `bbab8fb0…` (:53-132).

**Ejecutado:** los dos archivos de prueba → **25 PASS** (reproducido, no
tomado del informe). Una sonda propia en
`.tmp/product-spec-catalog/family_label_gap_probe_test.dart` (gitignored).
Miré la captura `family-options-desktop.png` sólo para confirmar que en el
debug real el selector mostró nombres; no la usé para leer valores visuales.

## Dictamen

**Correcto en tenant, precedencia, claves persistidas, filtrado por
condiciones, conservación y autoridad.** Un defecto real de alcance (F1) y
una fragilidad de carga (F2), ambos con arreglo mínimo local. Sin bloqueo para
lo ya probado en AE0317 (todas las familias ofrecidas tenían nombre).

## Verificado sin hallazgo

- **Tenant y precedencia.** `getFamilyLabels` lee `spec_templates` activas
  con `tenant_id is null or = tenant`; `decodeFamilyLabels` rechaza cualquier
  fila de otro tenant o sin nombre (`FormatException`), ordena tenant propio
  primero y luego por `id` ascendente y toma el primer nombre por clave. Es
  exactamente la regla del resolutor de miembros del servidor
  (`get_product_spec_member_template_v1`: `is_active`, `tenant_id is null or =
  tenant`, `order by (tenant_id=tenant) desc nulls last, id limit 1`), así que
  el nombre mostrado corresponde a la plantilla que recibiría el perfil. El
  orden por `id` como texto coincide con el orden `uuid` del servidor para
  ids canónicos. Mapa inmutable.
- **Autoridad.** Los nombres se leen con `authority.tenantId` dentro de
  `_loadSpecTemplate`, antes de la re-verificación de usuario/tenant y del
  chequeo de época; se adoptan en el mismo `setState` que la plantilla y se
  anulan en `_invalidateSpecAuthority`. Un cambio de sesión no deja nombres
  del tenant anterior.
- **Claves persistidas.** `VbSearchableSelectOption(value: token, label:
  nombre)`; `_changeCell` guarda el token. Test de Root: el valor guardado es
  `{'family': 'helmet'}`, id y fuentes de la fila intactos, la otra fila igual
  byte a byte.
- **Filtrado por condiciones.** Las opciones se filtran primero por
  `allowed_values`, `scopedOptions` y `conditionalChoices` (:365-371) y sólo
  después se rotulan: `light` excluido por `allowed_options` no reaparece por
  tener nombre (test: sólo «Soporte de accesorio» y «Casco»).
- **Alcance del rótulo.** `_specRowTokenLabels` sólo rotula la columna
  `family` de tipo token; en ambos catálogos la única `rows_schema` con esa
  columna es `kit_members`. Presentación solamente: ningún consumidor de
  compatibilidad lee estos nombres.

## F1 — Una familia permitida sin plantilla activa desaparece del selector (defecto real)

- **Causa.** `options: choices.where((o) => labels == null ||
  labels.containsKey(o))` (:397-401) y, para un valor persistido sin nombre,
  `placeholder: 'Opción sin nombre disponible'` (:384-387) y la ayuda
  «Faltan nombres…» (:389-391); el resumen de la fila hace lo mismo (:243-247). Los nombres provienen sólo de plantillas
  **activas**, pero `kit_members.family` admite 105 familias por esquema y
  las condiciones de cada plantilla, no por existencia de una ficha activa.
  Una familia legítima cuya plantilla no esté activa (o no exista) queda
  **inseleccionable**, y si ya está guardada el operador no puede leer cuál es.
- **Demostración (sonda).** Fila guardada `family = pump`, nombres sólo para
  `accessory_mount`/`helmet`: opciones ofrecidas `[accessory_mount, helmet]`;
  valor conservado `pump` pero placeholder «Opción sin nombre disponible»,
  ayuda «Faltan nombres de opciones. Actualiza la ficha para recuperarlos.»,
  selector de fila «Familia técnica: Opción sin nombre disponible»; sin
  excepción y sin `errorText`. La ayuda además culpa a la ficha: actualizarla
  no crea nombres para una familia sin plantilla activa.
- **Alcance real hoy.** No lo puedo contar sin lectura productiva; la captura
  del debug muestra nombres para las primeras familias del selector y el
  test negativo de Root prueba que el token crudo ya no se muestra. Root puede
  contarlo con una lectura: familias de `allowed_values` de `kit_members` sin
  plantilla activa global ni del tenant.
- **Arreglo mínimo.** No ocultar: rotular la opción sin nombre con un texto
  explícito que conserve la clave (p. ej. `label: 'Familia sin ficha activa ·
  <clave>'`) tanto en las opciones (:397-401) como en el placeholder y el
  resumen, y quitar la ayuda «Actualiza la ficha…». Así el negativo de Root
  (nunca un token crudo a secas) se mantiene y la familia sigue siendo
  seleccionable y legible. Si la intención es que sólo se listen familias con
  ficha activa, eso es una regla de contrato (condición de fila), no de
  presentación, y debe declararse como tal.

## F2 — Un fallo al leer nombres impide cargar toda la ficha (fragilidad)

`getFamilyLabels` se espera dentro del `try` de `_loadSpecTemplate` (:1320);
cualquier error de red o `FormatException` del decodificador cae en el
`catch` genérico y fija `_specLoadError` («No se pudo cargar la ficha…»),
bloqueando el editor y el guardado por una consulta que sólo cambia
presentación. Además añade un viaje por cada carga, cambio de categoría o
reintento. **Mínimo:** capturar el fallo y seguir con `labels = null` (el
campo ya sabe mostrar tokens cuando `tokenLabels` no trae la columna), o
cargar los nombres una vez por sesión junto al preload.

## Notas menores

- `_specRowTokenLabels` ata el rótulo al nombre literal de columna `family`.
  Hoy sólo `kit_members` la tiene; si otra tabla la usara con tokens que no
  sean claves de plantilla, todas sus opciones quedarían ocultas por F1.
  Preferible atarlo a `member_profiles.collections[].family_column` de la
  colección o al id de la definición `kit_members`.
- Las pruebas no cubren el valor persistido sin nombre ni la opción ausente
  (la sonda de arriba lo hace); conviene añadirlo cuando se decida F1.

## Qué no toqué

Ningún archivo de Root, código, SQL ni runtime. Sólo este documento y la
sonda temporal en `.tmp/`.
