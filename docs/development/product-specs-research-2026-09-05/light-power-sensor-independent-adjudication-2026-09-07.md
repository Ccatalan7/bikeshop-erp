# Revisión independiente de luces, alimentación y sensores — 2026-09-07

Dictamen congelado y no aplicado. La base es `cf8ebeb1e4e7dd32853b8618657a3f25e3f5428158702ef2e0adeb5b89978577` (105 plantillas/663 definiciones); propuesta Claude `0f3685983e76efc3aa605ad63ecba70051e5c3b4ef8ccc0dd03047391b7cae47`. El JSON homónimo contiene decisión por los 25 parches, reemplazos de esquemas completos y 14 casos corregidos. Root conserva la adjudicación final, integración y despliegue. No es una aprobación de compatibilidad ni un paquete de llenado.

## Resultado y defectos reproducidos

La separación de detalles por miembro/puerto es adecuada; el esquema necesita conservar el alcance de cada afirmación. Una URL no convierte una declaración general en compatibilidad de todos los modelos ni una fecha de consulta en revisión física.

- `Group Ride`: las alternativas antes/después de “Spec change” no son dos modos simultáneos de una unidad. El manual es una edición documental, no el identificador de su hardware. El ejemplo conserva el conflicto fuera de los valores canónicos hasta identificar variante. [Cateye, página exacta](https://www.cateye.com/intl/products/headlights/HL-EL088RC_TL-LD810/).
- La batería **3.7 V/800 mAh sí está en la tabla Viz300** del manual. La fila original citaba sólo web: se agrega el manual a sus fuentes. El mismo documento declara IPX4 bajo **JIS C0920**; el parche no puede forzar una etiqueta IEC ni convertir el literal IP en una lista arbitraria. [Manual Cateye, dos páginas](https://www.cateye.com/intl/support/manual/data/doc/TL-LD810_820_HP_ENG_v1.pdf).
- `unique_by` de nombres/revisión opcional deja pasar las dos filas conflictivas y omite duplicados sin revisión. `sensor_type+transport` rechaza perfiles/modelos diferentes; `port+protocol+minV` colisiona con rangos/condiciones diferentes. La corrección utiliza **row.id** y retira esas claves semánticas: el conflicto entre afirmaciones queda pendiente de alcance, no se anuncia resuelto por IDs.
- El enlace Garmin original es Specifications. Wireless Sensors remite a compatibilidad específica y cita funciones/series; la lista no prueba cada transporte por cada sensor. `supported=true` se acota a lo documentado; falta de modelo/perfil no aprueba cualquier dispositivo de ese tipo. Se agrega alcance requerido como completitud. [Wireless Sensors de Edge 540, v6](https://www8.garmin.com/manuals/webhelp/GUID-17DE938E-466A-4746-BDBF-7A6FC1B3A32C/EN-US/GUID-09801A97-361B-4675-AD3A-6ACE25854DB3.html).
- La ficha A2667 enumera tecnologías de carga globalmente. No respalda PPS/PIQ3 en C1 ni PIQ2 en A como filas concretas. Se conserva la declaración global y se retiran esas asignaciones del caso. La página no ofrece perfiles V/A de salida; su entrada de red no los sustituye. No se calcula máximo agregado, tensión, corriente ni potencia desde otras cifras. [Anker A2667](https://service.anker.com/product-description/a085g000004x2BVAAY?recordId=a085g000004x2BVAAY).
- Protocolo literal opcional, condiciones y rangos eléctricos evitan exigir un protocolo supuesto para una etiqueta V/A. Un máximo de tensión no es exclusivo de PPS. Perfil, puerto físico y reparto de potencia son niveles distintos. [USB-IF PD](https://www.usb.org/usb-charger-pd), [USB-IF 2019, perfiles y multiport](https://www.usb.org/sites/default/files/D2T2-1%20-%20USB%20Power%20Delivery.pdf).
- Los siete retiros contienen `prerequisites:null`, inválido para v2: se reemplaza por `[]`. En la fixture de contenido, `quantity:1` es un JSON number: filas integer requieren `"1"`. Son defectos de contrato, no incompatibilidad del objeto.
- El sucesor de `power_source` pierde la opción Otra y no representa alimentación externa no USB. Se amplía antes del retiro; una tensión de entrada no se guarda como tensión de batería. [Supernova MINI 2](https://supernova-lights.com/en/products/mini-2), [Sheldon, generadores](https://www.sheldonbrown.com/generators.html).

## Ajustes de alcance

Se conservan `modes_count`, `ports_count` y `lumens_claimed` como declaraciones. Ni contar filas ni tomar su máximo produce el total OEM. Tampoco más filas que el total prueba un conflicto si representan ensayos/condiciones del mismo elemento; primero debe resolverse identidad y alcance.

`computer_contents` describe únicamente contenido vendido. Un montaje de sensor compatible que no viene incluido pertenece a su declaración de compatibilidad, con modelo/alcance; no se fabrica un ítem incluido para retirar `sensor_mount`.

Conservar capacidad impresa es correcto. La explicación “no sabemos si 1 TB equivale a 1000 o 1024 GB” confunde conformidad de la etiqueta con unidad: con prefijos SI son 1000 GB. No se rellenan bytes reales ni espacio utilizable desde ese literal. [BIPM, prefijos SI](https://www.bipm.org/en/measurement-units/si-prefixes).

No encontré una fuente Park Tool específica necesaria para los cambios electrónicos propuestos; no se atribuyen a Park especificaciones Garmin/Anker/Cateye. Se conserva la jerarquía Sheldon/Park para fundamentos de bicicleta, con el OEM/estándar exacto para estas afirmaciones. No usé una página secundaria para cerrar un rating IP ni una tabla normativa exhaustiva; queda literal y no certificado.

## Decisión por parche

| Parche | Decisión | Corrección o alcance |
|---|---|---|
| LPS-L-retire-power_source | corregir | Retiro acotado a light aceptable sólo con sucesor representable, conservación legacy y consumidores adaptados; null no es lista de prerrequisitos válida. No migrar hechos automáticamente. |
| LPS-L-retire-charge_connector | corregir | Retiro acotado a light aceptable sólo con sucesor representable, conservación legacy y consumidores adaptados; null no es lista de prerrequisitos válida. No migrar hechos automáticamente. |
| LPS-L-retire-battery_capacity_mah | corregir | Retiro acotado a light aceptable sólo con sucesor representable, conservación legacy y consumidores adaptados; null no es lista de prerrequisitos válida. No migrar hechos automáticamente. |
| LPS-L-retire-light_mount_kind | corregir | Retiro acotado a light aceptable sólo con sucesor representable, conservación legacy y consumidores adaptados; null no es lista de prerrequisitos válida. No migrar hechos automáticamente. |
| LPS-L-retire-mount_diameter_min_mm | corregir | Retiro acotado a light aceptable sólo con sucesor representable, conservación legacy y consumidores adaptados; null no es lista de prerrequisitos válida. No migrar hechos automáticamente. |
| LPS-L-retire-mount_diameter_max_mm | corregir | Retiro acotado a light aceptable sólo con sucesor representable, conservación legacy y consumidores adaptados; null no es lista de prerrequisitos válida. No migrar hechos automáticamente. |
| LPS-L-retire-ip_rating | corregir | Retiro acotado a light aceptable sólo con sucesor representable, conservación legacy y consumidores adaptados; null no es lista de prerrequisitos válida. No migrar hechos automáticamente. |
| LPS-L-declared-total-modes_count | corregir | La separación entre declaración y detalle es correcta; alinear metadata y precisar alcance. count(filas)>declarado tampoco es automáticamente una contradicción si son condiciones/afirmaciones del mismo elemento. |
| LPS-L-label-modes_count | aceptar | Rótulo correcto. Normalizar el parche global con template=null; el rótulo no valida evidencia ni cambia unidades. |
| LPS-C-declared-total-ports_count | corregir | La separación entre declaración y detalle es correcta; alinear metadata y precisar alcance. count(filas)>declarado tampoco es automáticamente una contradicción si son condiciones/afirmaciones del mismo elemento. |
| LPS-C-label-ports_count | aceptar | Rótulo correcto. Normalizar el parche global con template=null; el rótulo no valida evidencia ni cambia unidades. |
| LPS-E-storage-label-owner | corregir | Conservar evidencia y literal es correcto. Corregir la explicación de unidades; el dato normalizado puede permanecer ausente sin convertir una unidad definida en ambigua. |
| LPS-E-storage-label-text | aceptar | Rótulo correcto. Normalizar el parche global con template=null; el rótulo no valida evidencia ni cambia unidades. |
| LPS-L-drop-mount-pair | aceptar | Necesario en el mismo conjunto de retiros; no dejar un par con extremos legacy. Normalizar a replace_template_coherence con preimagen present/value. |
| LPS-L-members-required | aceptar | Recordatorio de completitud por miembro; required_missing no bloquea un borrador. Esta regla no impone exactamente una fila ni composición front/rear. |
| LPS-L-modes-required | corregir | El cambio puede servir como recordatorio no bloqueante; su justificación original es falsa: no se retiran lumens_claimed/modes_count. No convertirlo en requisito físico de modos discretos para toda luz. |
| LPS-L-members-schema | corregir | Conservar IP como texto y norma literal separada; no forzar IEC. El rótulo humano no identifica un miembro físico: row.id permite dos luces de igual nombre. Ampliar alimentación antes del retiro escalar. |
| LPS-L-modes-schema | corregir | Revisión OEM física identificada es distinta de edición documental/fecha de consulta. Retirar unique_by de nombres; preservar condiciones. Alternativas de fuente del mismo Group Ride permanecen fuera de los valores canónicos hasta adjudicar variante. |
| LPS-L-link-labels | aceptar | Sólo presentación de row.id ya existente; la revisión se muestra únicamente si es revisión OEM identificada. Nunca poner retrievaldate en esa celda. |
| LPS-L-kit-roles | aceptar | Vocabulario de contenido, no compatibilidad ni declaración de que todos los kits incluyen esos objetos. computer/light members no se duplican por nombre; sólo una identidad de miembro enlazada permite probar doble conteo. |
| LPS-C-sensor-schema | corregir | Añadir transporte desconocido es honesto; unique_by tipo/transporte no respeta perfiles/modelos. Scope es requerido como completitud; supported se interpreta únicamente en ese alcance. Añadir montaje del sensor como fitment, no contenido vendido. |
| LPS-C-retire-sensor_mount | corregir | Retirar resumen ambiguo sin transformar sensores compatibles en incluidos. computer_contents para envase; montaje de un sensor compatible en su fila con alcance/modelo, o legacy pendiente. |
| LPS-E-protocol-scope | corregir | La declaración global sigue siendo necesaria: la fuente Anker no distribuye sus tecnologías por puerto. Conservar el escalar como afirmación de alcance de dispositivo; no igualarlo a detalle portuario. |
| LPS-E-link-labels | aceptar | Rótulo informativo; no infiere protocolos ni potencia. Referencia sigue siendo row.id y requiere normalización de op. |
| LPS-E-port-profiles | corregir | Fila por perfil/condición con identidad estable, protocolo literal opcional y magnitudes publicadas. Rango máximo no es exclusivo PPS; no deducir V/A/W ni capacidad agregada. Nuevos perfiles no cambian el esquema existente. |

## Gramática e integración

Los 25 `before` coinciden con la base congelada. El formato Claude no se consume directamente: falta `new_definitions`, algunas etiquetas llevan template no nulo, las operaciones de partes no son las operaciones del integrador, y el campo nuevo embebe definición/vínculo. Root normaliza a operaciones existentes con preimagen completa. `replace_unpublished_rows_schema`, agregado durante esta revisión, permite conservar claves/tipos/unidades de celdas existentes; IP permanece text. Sólo la definición nueva de perfiles cambia su protocolo propuesto de token a text.

`rows_schema_overrides` son reemplazos concretos para adjudicación de root, no nuevas claves del DSL. Los casos `competing_source_observations` y `capture_decision` son metadatos del dictamen, jamás celdas/spec_facts. El nuevo `product_spec_row_conditions.dart` apareció durante la revisión como trabajo local de root; no lo declaro publicado ni doy por cerradas sus paridades SQL/cliente. Los cambios aquí no dependen de él.

## Evidencia y gates

`25/25` preimágenes comprobadas. `31/31` asserts Flutter del probe temporal pasan: 16 reproducciones y casos de identidad, 1 validación de esquemas corregidos y los conjuntos de issues de las 14 fixtures corregidas con `validateProductSpecDraft`. La simulación en memoria también conserva válidos los contratos de las 105 plantillas y los gates de publicación en falso. No prueba la traducción final del protocolo de parches, una aplicación SQL ni validez OEM. El intento inicial mediante `/dev/stdin` no ejecutó Dart y no cuenta como prueba. Comando reproducible:

```sh
fvm flutter test --no-pub .tmp/product-spec-catalog/light-power-sensor-review-probe.dart --reporter expanded
```

Las 14 variantes corregidas se ejecutaron en la simulación semántica local; deben repetirse tras la traducción e integración final. Algunas faltas son pendientes no bloqueantes, y `prerequisite` es el código real de este validador, no `prerequisite_missing`. Eso no convierte en correctas las expectativas originales de Claude. El compilador reprodujo el rechazo de `prerequisites:null` (`NoneType object is not iterable`); el guard SQL exige array y el lector Dart coalesce null, por lo que sólo verificar UI habría omitido el defecto.

Gates abiertos: normalización del paquete; protección legacy y datos existentes; paridad final SQL/Dart; alcance/modelo/generación/condiciones y fuente; conflictos documentales; consumidores de búsqueda/comparación de filas; UI final; backup y aplicación con revisión antes de llenar. `origin=new` en un artefacto no acredita que no existan hechos en DB.

Cero comandos DB, cambios de implementación, runtime, mensajes a Claude, publicación o productos rellenados. El paquete de frenos y las adjudicaciones anteriores permanecieron congelados.
