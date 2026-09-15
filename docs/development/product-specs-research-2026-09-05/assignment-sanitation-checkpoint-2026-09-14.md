# Saneamiento de asignaciones: checkpoint del 14 de septiembre

**720 asignaciones aplicadas**, cada una con preimagen revisada, recibo
persistido y lectura posterior autenticada que verifica conservación de datos.
**Llenado técnico: 0. Reemplazos originales publicados: 1 (kit, ver su adjudicación).**

| Tanda | Productos | Familias |
|---|---:|---:|
| assignment-slice-20260914 | 54 | 3 |
| assignment-accessories-20260914 | 149 | 19 |
| assignment-components-20260914 | 140 | 17 |
| assignment-consumables-20260914 | 79 | 11 |
| assignment-uncategorized-20260914 | 91 | 27 |
| assignment-tools-parts-20260914 | 83 | 19 |
| assignment-original-parts-20260915 | 108 | 32 |
| assignment-image-reviewed-20260915 | 10 | 8 |
| assignment-resolved-types-20260915 | 3 | 3 |
| assignment-existing-tube-20260915 | 1 | 1 |
| assignment-component-sets-20260915 | 2 | 1 |

Conteo fresco a `2026-09-15T04:02:47.158497+00:00`: 1.588 registros marcados como
producto/no servicio con ficha efectiva y 26 sin ella; 59 marcados como
servicio. El indicador aún incluye algunos registros no materiales mal
clasificados. Los costos, trabajos, notas de crédito y nombres ambiguos se
mantienen para adjudicación; no se fuerzan a una familia técnica.

## Decisiones de clase

- Candados, luces y cintas se confirmaron por nombre y categoría.
- La categoría Mochilas contiene dos bolsos de bicicleta y una mochila personal.
- Se excluyeron guantes de nitrilo de taller y un guante de moto.
- Los ejes pasantes se asignaron a retención de rueda; quedaron pendientes
  los nombres ambiguos de ejes de maza.
- Un adaptador rotor–maza se separó de tres adaptadores de cáliper.
- Dos adaptadores de potencia quedaron inicialmente pendientes; la séptima
  tanda confirmó que `stem_kind` publicado incluye adaptadores quill → ahead.
- El catálogo publicado confirma la cobertura de noodles en piezas de cable,
  agujas de asiento en collarines y separadores de dirección/pedalier.
- Fundas y cables interiores se distinguieron individualmente en la categoría
  mixta. Las conexiones hidráulicas, químicos y protecciones se asignaron por
  objeto; no se afirmó ajuste, composición, uso aprobado, talla ni medidas.

- De 92 objetos sin categoría revisados, 91 recibieron ficha explícita y
  conservaron la categoría vacía. Una bicicleta a escala recibió artículo de
  regalo y 19 bebidas recibieron alimento/bebida, sin inferir composición.
  El juego de tres bloqueos PO02409001058 se retuvo entonces porque el nombre
  no distinguía todas sus piezas ni si incluía retención de asiento.

- La ficha publicada de herramientas ya contempla EPP (guantes de taller),
  botella aplicadora y repuesto de herramienta. El guante de nitrilo se resolvió
  allí, sin usar la ficha de guante de ciclista. El inflador de pie se separó de
  las herramientas en la misma categoría comercial. Los pernos, arandelas y
  postizas recibieron su clase sin afirmar rosca, medida ni ajuste.

- La séptima tanda asignó 108 piezas en 32 familias, incluidos 19 ejes internos
  de maza, cadenas, cambios, llantas, rayos, rodamientos, frenos y cinco conjuntos
  comerciales de transmisión. Los cubre-mochilas y adhesivos/parches se
  contrastaron con las clases admitidas por sus fichas publicadas. No se
  inferieron componentes del kit, medidas, edición OEM ni compatibilidad.

- La octava tanda resolvió diez clases con fotografías ya vinculadas al catálogo:
  limpiador mecánico de platos, funda de bicicleta, cubiertas tubulares de
  manillar, lubricante, resorte de aguja, extractor, portabidón, freno hidráulico
  completo y dos ejes con conos/contratuercas. No se completaron medidas ni
  compatibilidades desde la imagen. Persisten conflictos de identidad: la funda
  dice BEST en el título y Vision en su envase; el freno dice delantero en el
  título y RIGHT/REAR en la imagen. Esos campos siguen sin rellenar.
  La foto del juego PO02409001058 muestra dos bloqueos de rueda y uno corto
  de asiento: quedó pendiente de una ficha para conjuntos mixtos.

- La novena tanda resolvió el guante de moto (`rider_glove` declara Moto),
  el neumático sólido (`tire` contempla Sólido / sin aire; la foto no muestra
  una rueda completa) y la biela de una pieza (`crankset` contempla Americano).
  Tres lecturas y recibos verificados a las 02:44 UTC; hechos vacíos intactos.

- La undécima tanda asignó PO02409001058 y NNV71 a `component_set`, después
  de publicar su ficha de conjunto con datos por pieza. Dos lecturas autenticadas
  y dos recibos verifican que no cambiaron hechos, perfiles ni campos comerciales.
  No se rellenaron las piezas a partir del nombre o fotografía.

**Adjudicación de los 26 restantes:** nueve identifican operaciones, costos o
nota de crédito y no requieren ficha de componente; no se cambiaron sus flags
contables ni se sumaron como asignaciones. Diecisiete siguen necesitando resolución:
identidad, conjunto mixto o hueco de arquitectura. La cámara antes retenida por
inferencias públicas ya fue asignada con el filtro publicado.
[Decisiones por registro](remaining-assignment-adjudication-2026-09-15.json).

## Evidencia y alcance

Se reutilizó `assign_product_spec_template_v1` y el mismo preparador validado:
73 casos de RPC, cuatro de SQL generado y ocho de preparación. No se repitió
esa batería sin cambios; las tandas posteriores añadieron la comprobación real
de conservación, autenticación, recibos y lectura para cada producto.
La revisión final de estas asignaciones fue de Root. Las revisiones de Claude
215 (nueve opt-ins), 216 (consumidor de cámaras) y 217/218 (propiedad del kit)
tienen alcance separado. Los nueve opt-ins ya están aplicados y verificados;
no se presenta esa aprobación como revisión de las asignaciones.

Se conservaron todos los campos del producto excepto asignación/revisión/fecha,
y todas las observaciones, referencias vinculadas e historial. El respaldo accesible
formato 2 se verificó antes de aplicar la primera tanda; las preimágenes y
los recibos registran el estado exacto anterior/posterior por operación.
Ante una respuesta incierta, recuperar el mismo operation_key antes de repetir.
Una reversión debe respetar cambios legítimos posteriores.

**Corrección del verificador, 15-09:** `snapshot.references` contiene el
catálogo de referencias disponibles para la familia efectiva, no referencias
vinculadas al producto. Una cadena recién asignada expone cinco referencias
existentes aunque su `spec_reference_id` siga nulo. La primera comparación
literal falló por ese cambio de lectura, sin detectar cambio de datos. El
verificador corregido afirma el vínculo nulo en producto/editor, observaciones
e historial intactos y opciones iguales a `get_product_spec_references_v2`
para la familia. Las 108 lecturas pasan y sus 108 recibos se comprobaron por
operación, actor, producto, plantilla, revisión, motivo y hechos vacíos.

Evidencia privada en `.tmp/product-spec-catalog/<tanda>/`: propuesta, revisión
de Root con hashes, SQL exacto, COMMIT de cada grupo, `application-readback.json`,
`receipts-and-counts.json` y snapshots `after/`.
Muestra real de la app: cinta AE0165, candado 7290001284315, luz AE0317 y guante
2000000283074 abrieron su ficha correcta y datos pendientes; no se guardó
ninguna edición desde la app. Las muestras no sustituyen las lecturas individuales de cada tanda.
La sesión Debug sufrió cambios de navegación durante la ronda; el log contiene
recargas externas. No atribuir esos cambios a las asignaciones ni reportar
capturas de Dashboard/lista como si fueran pruebas de un editor.

## Caso con observaciones: cámara Chaoyang, todavía sin asignar

La captura autenticada de 6927116185398 confirmó siete observaciones antiguas,
todas sin confirmar: dos inferidas (material y presencia de sellante), cinco
desde texto de proveedor. La sonda de lectura contra la plantilla `tube` v6
proyecta las siete, sin campos externos ni incidencias estructurales. Ese verde
no acredita material o contenido. Se conserva la preimagen y se mantiene este
caso fuera de las tandas vacías; antes de activarlo hay que comprobar cómo
consumen los lectores la procedencia no confirmada. Evidencia privada en
`.tmp/product-spec-catalog/assignment-existing-tube-20260914/`. Sin escritura.

Actualización de la cámara, 15-09: la revisión 216 comprobó cautela en taller,
pero la lectura viva confirmó que el producto está publicado y visible en web.
Asignarlo expondría material y sellante inferidos. El filtro público está en
prueba/revisión; se conserva este caso sin asignar hasta cerrar esa salida.

## Cámara con observaciones: asignación cerrada 15-09 03:30 UTC

6927116185398 recibe `tube` v6 mediante el escritor existente, sin debilitar el
preparador para productos vacíos. Comando separado con snapshot exacto, revisión
0→1, actor/tenant, contrato y cuerpos de funciones fijados. Recibo persistido
`spec-assignment-36910f7a-42b0-53d1-a8be-161a5d4d1613` verificado. Observaciones
(7), lecturas, procedencia, confirmación, datos comerciales y referencias
conservados; ninguna observación nueva. La web anónima devuelve cinco campos
de proveedor y omite material/sellante inferidos gracias a `20260915034000`.

Los contextos reales antes/después alimentan 14 pruebas del consumidor de taller
con bicicletas sintéticas: antes no hay veredicto, después sólo precaución;
ninguna combinación se anuncia compatible. No equivale a compatibilidad física
confirmada. Evidencia privada `.tmp/product-spec-catalog/assignment-existing-tube-20260915/`.
Los párrafos anteriores sobre su retención describen el estado previo a este cierre.
