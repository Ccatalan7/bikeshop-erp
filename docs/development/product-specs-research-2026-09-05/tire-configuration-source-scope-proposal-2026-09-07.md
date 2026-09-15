# Configuraciones de llanta: qué identifica una fila y cómo conviven dos fuentes

Claude, revisor independiente de representación · 2026-09-07

Propuesta local y acotada. No adjudica, no asigna, no llena y no publica. No toca compilador, catálogo, código, pruebas de root, base de datos ni runtime. El contrato local de cardinalidad es de otro revisor y no se toca aquí. Ninguna cifra se atribuye a otro SKU y no se convierte entre bar y psi.

## Sobre qué se construyó

| Artefacto | SHA-256 | Verificado |
|---|---|---|
| all-family-wss-residual-integrated-2026-09-07.json | `00041bb82cbddec1278a4d310d26747601518356abce5af4138da9bab7aa4b06` | sí |
| all-family-wss-residual-cases-integrated-2026-09-07.json (287 casos) | `da0b43e638820fce0fafcf93b53431c96d4be174e4bc180038e20e2d5ab851d9` | sí |

Confirmé en esta base que R6 está integrado tal cual —la compuerta hookless sobre `pressure_unit` y `rim_internal_width_max_mm`—, que `tire_max_pressure_psi` quedó en `legacy` y que los tres campos de rodamiento existen. Las preimágenes salen de aquí.

## La pregunta, respondida

**¿tire_rim_configurations representa configuraciones físicas o declaraciones documentales, y cuál es la identidad estable de una fila?**

Declaraciones sobre una configuración física. La identidad estable es perfil, método y documento; la unidad no entra en la identidad porque cruzaría el ancho.

### F1 · ¿La tabla representa configuraciones físicas o declaraciones documentales?

**Declaraciones, con una configuración física por sujeto.**

De las siete columnas, sólo dos describen algo físico: el perfil del lecho de la llanta y el método de montaje. Park las ancla en una norma —el lecho con gancho que agarra el talón, y las tolerancias ETRTO— y Sheldon Brown fija que el calce lo decide el diámetro de asiento. Las otras cinco son cifras publicadas. Sheldon lo dice sin rodeos sobre el ancho: es «a general guideline» y su propia tabla «may err a bit on the side of caution». Un número que admite prudencia editorial no es una cota física; es lo que un documento declara. La tabla, entonces, es documental y su rótulo actual —«Límites generales de montaje»— la hace parecer física.

### F2 · ¿Por qué la clave actual es el defecto que encontraste?

**Porque identifica la fila por el sujeto y no por quién lo declara.**

unique_by(perfil, método) dice que esta variante tiene a lo más una fila por configuración. Eso vuelve indistinguibles dos cosas que no lo son: un documento que se contradice a sí mismo, que es un error, y dos documentos que declaran lo mismo o cosas distintas, que es el estado normal de la evidencia. Hoy el motor rechaza las dos por igual.

### F3 · ¿Cuál es el contraejemplo verificable?

**Los dos documentos de Continental para el GP 5000 S TR 28-622.**

Leí hoy los dos. El de us/en tabula «700 x 28c» y el de products/b2c tabula «28-622»; ambos declaran 5.0 bar, 72 psi y 23 mm para montaje sin gancho, y el segundo omite la frase sobre que hooked y hookless pueden diferir. Son dos documentos legítimos del mismo fabricante sobre la misma configuración física. Con la clave actual sólo uno entra y el otro se rechaza por identidad repetida.

### F4 · ¿Qué rompería la clave que propongo?

**Un documento que declare dos juegos de límites para una misma configuración.**

La clave (perfil, método, documento) es estable mientras cada documento declare a lo más un juego de límites por configuración. La forma que la rompería es un documento que diferencie el máximo por sub-rango de ancho dentro del mismo perfil y método, por ejemplo 5.0 bar hasta 21 mm y 4.5 bar hasta 25 mm en la misma fila de la tabla. Busqué esa forma hoy en Continental y en Schwalbe y no la encontré: Continental publica un solo ancho máximo y una sola presión por medida, y Schwalbe publica un mínimo y un máximo por medida sin condicionarlos al aro. Si esa forma aparece, la clave rechazaría la segunda declaración legítima y habría que agregar el sub-rango a la identidad. Lo dejo dicho antes de que ocurra, no lo doy por imposible.

### F5 · ¿Qué se pierde al cambiar la clave?

**La detección de duplicados en filas sin documento. Es un costo real.**

unique_by salta la fila entera si le falta cualquier clave del grupo, y la comparación es por igualdad cruda de la celda. Con el documento en la clave, dos filas sin documento dejan de compararse entre sí. Dos de tus casos congelados dependen de eso hoy y dejan de bloquear: están listados con su corrección. El pendiente por documento es lo único que empuja a completarlo; no hay bloqueo que lo fuerce.

### F6 · ¿Cómo se conservan las dos unidades sin cruces?

**Dentro de la fila, no como filas nuevas.**

Si la unidad entrara en la identidad, la misma configuración tendría dos filas y el ancho máximo quedaría escrito dos veces, con dos dueños y sin ninguna regla que los compare: las condiciones de fila gobiernan una celda dentro de su fila y nunca comparan filas. Por eso la segunda cifra impresa va en dos columnas nuevas de la misma fila. El ancho conserva un solo dueño.

### F7 · ¿Por qué no reutilizar source_url como identidad?

**Porque excluye el envase y no distingue ediciones.**

La columna existente es de tipo url, así que no puede recibir «envase del producto, lote 2024», y Continental dice justamente que el máximo general está en el envase. Además una misma dirección sirve ediciones distintas a lo largo del tiempo, que es exactamente el caso que hay que separar. La identidad necesita un texto de documento y edición. Su debilidad, dicha: el motor compara ese texto por igualdad cruda, así que dos maneras de escribir el mismo documento son dos documentos para él.

### F8 · ¿Cuál es el mínimo compatible con el motor actual?

**Exactamente estos tres parches, y no más.**

El compilador sólo deja extender un esquema ya revisado: no puedo quitar ni retipar columnas, así que max_pressure y pressure_unit se quedan como están y R6 sigue en pie sin tocarlo. Evalué separar la tabla en dos —configuración física y declaraciones— unidas por row_coherence: representa mejor los dos granos, pero exige un campo nuevo, un enlace y que el operador cree primero la configuración. No lo propongo como mínimo; lo dejo nombrado por si prefieres pagarlo.

## Fundamento

| Id | Fuente | Qué demuestra |
|---|---|---|
| S-SHELDON-SIZING | Sheldon Brown, Tire Sizing Systems | El calce físico lo decide el diámetro de asiento del talón: «Generally, if this number matches, the tire will fit onto the rim; if it doesn't match, the tire won't fit». En cambio el ancho es una guía y no una cota física: «A general guideline is that the tire width should be between 1.45/2.0 x the inner rim width», y sobre la tabla de combinaciones seguras advierte «This chart may err a bit on the side of caution. Many cyclists use slightly wider tires with no problem». |
| S-PARK-TUBELESS | Park Tool, Tubeless Tire Compatibility | El lecho de la llanta es una realidad física: «A tubeless ready rim will have a sidewall with a hooked design, which helps catch and hold the bead». Y el sistema descansa en una norma, no en un documento comercial: «tubeless tire systems rely on rim and tire manufacturers making equipment to tolerances outlined in the ETRTO standards». |
| S-CONTI-US | Continental, Hookless vs. Hooked Rims (us/en) | GP 5000 S TR «700 x 28c»: «5.0 \| 72» y 23 mm. Añade que el máximo «may differ between hooked and hookless applications». |
| S-CONTI-B2C | Continental, Hookless vs. Hooked Rims (products/b2c) | El mismo fabricante, otro documento: designa las medidas en ETRTO —«28-622»— y declara las mismas cifras, «5.0 \| 72» y 23 mm. Su frase sobre el envase omite el «and may differ» que sí trae el documento us/en. |
| S-SCHWALBE-MPLUS | Schwalbe, Marathon Plus 11100769 | «max. Bar: 6 Bar max. Psi: 85 PSI» para la misma cubierta. 6 bar convertidos dan 87 psi: las dos cifras impresas no se derivan una de la otra. |

## Los tres parches

| Id | Operación | Objetivo |
|---|---|---|
| TCSS-01-row-identity-includes-the-document | `replace_unpublished_rows_schema` | definición `tire_rim_configurations` |
| TCSS-02-alt-unit-and-document-conditions | `replace_template_coherence` | `tire` / `row_conditions` |
| TCSS-03-helper-states-the-grain | `replace_field_contract` | `tire` / `tire_rim_configurations` |

### TCSS-01-row-identity-includes-the-document

Añade tres columnas al final y cambia la clave de identidad de (perfil, método) a (perfil, método, documento). Ninguna columna existente cambia de clave, tipo ni unidad, y ordered_pairs queda igual: el compilador rechaza cualquier otra cosa sobre un esquema ya revisado.

*No se afirma* que la clave sea segura en general. Es estable mientras cada documento declare a lo más un juego de límites por configuración. Ver F4 para la forma que la rompería y F5 para el hueco que abre.

### TCSS-02-alt-unit-and-document-conditions

La segunda unidad gobierna la segunda cifra igual que la primera gobierna a la primera, y el documento se pide siempre. Las tres entradas de R6 se conservan palabra por palabra: no se toca la compuerta hookless ni el par unidad/presión ya integrados.

*No se afirma* que la segunda unidad tenga que ser distinta de la primera. Una condición compara una celda contra literales, nunca contra otra celda, así que si alguien repite bar en las dos el motor no lo ve.

### TCSS-03-helper-states-the-grain

Deja escrito en el formulario qué es una fila, para que la identidad no haya que deducirla.

*No se afirma* que el rótulo del campo cambie; sigue siendo el que integraste.

La adjudicación necesita declarar el bucket que el campo hoy no tiene:

```json
{
  "patch_id": "TCSS-03-helper-states-the-grain",
  "decision": "aceptar",
  "reason": "…",
  "before_extensions": {
    "helpers": {
      "present": false,
      "value": null
    }
  }
}
```

`replace_unpublished_rows_schema` exige `template: null`: apunta a la definición, no a la plantilla. Las tres columnas nuevas van al final porque el compilador compara las existentes posición por posición y rechaza cualquier cambio de clave, tipo o unidad.

### El esquema resultante

| Columna | Tipo | Requerida | Nueva |
|---|---|---|---|
| rim_bead_profile | token | sí | — |
| mounting_method | token | sí | — |
| rim_internal_width_min_mm | decimal | no | — |
| rim_internal_width_max_mm | decimal | no | — |
| max_pressure | decimal | no | — |
| pressure_unit | token | no | — |
| source_url | url | no | — |
| source_document | text | no | sí |
| max_pressure_alt | decimal | no | sí |
| pressure_unit_alt | token | no | sí |

`unique_by` pasa de `[[rim_bead_profile, mounting_method]]` a `[[rim_bead_profile, mounting_method, source_document]]`. `ordered_pairs` no se toca.

## El costo, medido

No cambio la clave sin decir qué se pierde. Corrí los dos casos congelados que hoy dependen del bloqueo por identidad, con el catálogo ya parchado:

| Caso congelado | Hoy | Tras el parche | Con el documento escrito |
|---|---|---|---|
| `wss_tire_same_variant_profile_method_twice` | bloquea `row_shape` | deja de bloquear | vuelve a bloquear |
| `wss_SF6` | bloquea `row_shape` | deja de bloquear | vuelve a bloquear |

La causa es la semántica de `unique_by`: salta la fila entera si le falta cualquier clave del grupo. La corrección es de una celda por fila y la medí: escribiendo el mismo documento en las dos filas, los dos casos vuelven a bloquear. Los otros diez casos `tire` no cambian de veredicto y sólo ganan un pendiente no bloqueante por documento.

## Ensayo local

Los tres parches pasan por `apply_reviewed_field_addendum` con `validate_contract` en verde y `publication_gates` sin cambios. Las diez fixturas y los dos casos congelados corrieron contra `validateProductSpecDraft` con el catálogo parchado; `observed_in_local_trial` es la salida literal del motor. Cero discrepancias. La sonda vivió en un archivo temporal que ya borré.

## Fixturas

| Id | Tipo | Qué fija |
|---|---|---|
| tcss_two_continental_documents_same_configuration | válido | El contraejemplo verificable. Los dos documentos de Continental declaran la misma configuración del GP 5000 S TR 28-622 con las mismas cifras: 5.0 bar, 72 psi y 23 m… |
| tcss_same_document_declaring_twice_still_blocks | contradictorio | La clave sigue teniendo dientes donde importa: un mismo documento no puede declarar dos veces la misma configuración. Las cifras de la segunda fila son sintéticas y … |
| tcss_undocumented_rows_escape_the_duplicate_check | known_gap_regression | El costo, medido y no supuesto. unique_by salta la fila entera si le falta cualquier clave del grupo, así que dos filas sin documento dejan de compararse y este caso… |
| tcss_both_printed_units_in_one_row | válido | Las dos cifras impresas de la misma presión en una sola fila, sin conversión. El ancho máximo aparece una sola vez: no hay cruce entre unidades. |
| tcss_alt_value_without_its_unit_is_pending | desconocido | La segunda cifra sin su unidad queda con requisitos por confirmar, igual que la primera. |
| tcss_alt_unit_without_value_is_pending | desconocido | Elegida la segunda unidad, su cifra es exigible y su falta queda pendiente. |
| tcss_row_without_document_is_pending | desconocido | El documento se pide siempre, por fila y por columna, y su falta no bloquea. |
| tcss_documentary_conflict_between_editions_is_preserved | synthetic_documentary_conflict | El conflicto que no se resuelve solo: dos ediciones declaran anchos y presiones distintos para la misma configuración física. Las dos filas se conservan, ninguna que… |
| tcss_hookless_completeness_from_r6_survives | desconocido | Regresión de R6: la compuerta hookless que integraste sigue pidiendo ancho y unidad. |
| tcss_reversed_width_range_still_blocks | contradictorio | ordered_pairs sobrevive al cambio de esquema: un rango invertido sigue siendo imposible. |

## Lo que no propongo

Separar la tabla en dos —configuración física y declaraciones, unidas por `row_coherence`— representa mejor los dos granos y dejaría que también el ancho difiera entre documentos sin duplicarse. No lo propongo como mínimo porque exige un campo nuevo, un enlace y que el operador cree antes la configuración, y el motor actual no lo necesita para resolver el defecto que encontraste. Queda nombrado por si prefieres pagarlo.

Una observación sin parche: con la tabla de máximos generales ya adjudicada, el rótulo de esta seguirá diciendo «Límites generales de montaje» al lado de «Máximos generales declarados». Se confunden al leerlos juntos. No lo cambio porque no hace falta para nada de lo anterior.

## Lo que esto no resuelve

- Dos filas sin documento no se comparan entre sí. El pendiente es lo único que empuja a completarlo.
- El motor compara el texto del documento por igualdad cruda: dos maneras de escribirlo son dos documentos para él.
- La segunda unidad no está obligada a ser distinta de la primera; una condición nunca compara dos celdas.
- Un conflicto entre ediciones se conserva entero y ninguna regla dice cuál rige. Es lo pedido, y significa que el desempate es humano.

## Compuertas

Publicación, llenado, asignación y aprobación mecánica siguen en `false`. Ninguna familia queda certificada.
