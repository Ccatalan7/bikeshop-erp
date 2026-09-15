# Conteo por configuración V3: revisión independiente, sólo lectura

Revisión de Claude sobre el candidato genérico P-1. **No edité el motor, ni
frenos, ni rodamientos, ni el aplicador. No corrí SQL, ni producción,
migraciones, fill, git ni runtime.** Corrí Python y Dart con logs propios, y
construí mis propias fixturas fuera del repositorio.

## Las seis huellas coinciden

Recalculé las seis del candidato antes de leer nada. Las seis coinciden byte a
byte con las declaradas, incluidas `product_spec_coherence.dart`
(`05baf5b3…70a749`), `product_spec_row_cardinality_metadata.py`
(`89a3a669…78a7e4c`) y el SQL candidato (`b3264ecb…bec12c458`).

## Lo que reproduje

```
python -m unittest test_product_spec_grouped_cardinality.py   → Ran 19 tests — OK
python -m unittest test_product_spec_row_cardinality_metadata → Ran 30 tests — OK
flutter test product_spec_coherence_boundary_test.dart \
             product_spec_contract_test.dart                  → +42: All tests passed!
```

No asumo que eso cubra lo que falta: lo que sigue son contraejemplos que
construí yo, con un catálogo V3 sintético propio corrido por el arnés
parametrizado (`--dart-define=SPEC_CATALOG_INPUT/CASES` sobre archivos del
scratchpad, sin agregar ni tocar un archivo del repositorio).

## Contraejemplos que busqué y **no** encontraron defecto

Los pongo primero porque son la parte cara de la revisión, y porque tres de
ellos eran mi hipótesis principal.

1. **Fila hija huérfana.** Mi sospecha: el conteo es
   `rows.where((r) => r.values[group.column] == parent.id)`, así que una fila
   sin celda de vínculo no cae en ningún grupo, y con la columna de vínculo
   **no** obligatoria en el esquema una ficha podría cuadrar dos grupos de dos y
   llevar dos filas de más sin señal. **Falso.** V3 agregó la rama exacta
   (`product_spec_coherence.dart:341-350`): con un vínculo agrupado, una fila
   cuyo valor no es conocido emite `row_reference_pending` con su `rowId` y su
   columna. Lo verifiqué con dos huérfanas: la incidencia aparece sobre la
   colección hija, **el conjunto bloqueante queda vacío**, y el padre no recibe
   nada. Es la conducta que el documento declara.
2. **Celda de vínculo en blanco.** Un `''` no se convierte en huérfana
   silenciosa: el parser de filas la rechaza y sale `row_shape` bloqueante.
3. **Un ID real llamado `unknown`.** El tercer conjunto de la condición
   (`!(target?.rows.any((r) => r.id == value) ?? false)`) existe justo para
   esto. Un padre con id `unknown` y una hija que lo nombra **resuelven por
   identidad** y no producen incidencia. Verificado.
4. **Total del padre ausente** → `row_cardinality_pending` no bloqueante, nunca
   conflicto. Verificado.
5. **Una configuración corta y otra larga** producen dos incidencias distintas,
   cada una con el `rowId` de su padre: un `row_cardinality_conflict` bloqueante
   y un `row_cardinality_pending` no bloqueante en la misma ficha. Verificado.
6. **Ciclo por vínculos mutuos.** Un padre que enlaza a la hija mientras la hija
   agrupa por el padre: **los dos lados lo rechazan**. Dart lanza
   `FormatException: Los vínculos y requisitos forman un ciclo` y el compilador
   Python `cyclic applicability ['catalogue_items','variant_catalogue']`.
   Mismo veredicto, mensajes distintos.
7. **Asimetría `max` entre Python y Dart.** El validador Python comprueba el
   `max` de la columna padre (tipo y `min<=max`); la rama agrupada de Dart sólo
   comprueba `min`. **No es divergencia**: el parser de columnas
   (`product_spec_rows.dart:180-190`) ya rechaza un `max` no numérico y un
   dominio invertido antes de que la coherencia se construya.
8. **Edición de la definición padre.** Sospeché que quitar o retipar
   `total_column` dejara una cardinalidad agrupada colgando, porque el guard de
   publicación es un trigger sobre `spec_templates`. **Falso**:
   `spec_definition_template_rules_guard` corre para **cada plantilla
   consumidora** y `spec_template_rules_validate_internal_v1` llama a
   `spec_coherence_metadata_internal_v1`, que es justamente la función que este
   candidato reescribe. La protección se hereda sin que el candidato tenga que
   redefinir el validador.

## G-1 · Dos versiones del mismo trigger conviven, y una de ellas apaga esta protección

El hallazgo del punto 8 depende por completo de la cláusula `WHEN` del trigger
`spec_definition_template_rules_guard`. En el repositorio hay **dos stanzas que
lo crean**, con cláusulas distintas:

- `supabase/migrations/20260906200000_product_spec_field_conditions.sql:232`
  → `when (key, data_type, allowed_values)` — **sin `validation_rules`**.
- `supabase/migrations/20260907020000_product_spec_row_coherence.sql:751-752`
  → añade `validation_rules` y `unit`.

Hoy gana la segunda por orden de migración, y por eso una edición del
`rows_schema` del padre revalida las plantillas consumidoras. Pero
`rows_schema` **vive dentro de `validation_rules`**: si una migración futura
copia la stanza antigua —que sigue en el árbol y es la que aparece primero al
buscar el trigger— la cláusula se estrecha en silencio y la cardinalidad
agrupada deja de protegerse contra una edición de su columna de total.

Ninguna prueba lo notaría: las 78 SQL ejercitan las **funciones**, y la
cláusula `WHEN` es del trigger, no de la función.

**Severidad: baja, pero es una trampa de mantenimiento con un precedente en el
mismo archivo.** Sugerencia barata: afirmar la cláusula vigente en una prueba
—`select pg_get_triggerdef(oid)` y comprobar que menciona `validation_rules`— o
retirar la stanza antigua para que no haya dos plantillas del mismo trigger.

## G-2 · `collection_field` se pierde al fusionar la incidencia

`ProductSpecCoherenceIssue` lleva `collectionField`, y el bloque de fusión de
`product_spec_contract.dart` lo usa bien: las dos supresiones consultan
`{issue.field, issue.collectionField}`, así que una colección inaplicable ya no
pide documentación y una contradicción conserva su error de aplicabilidad. Eso
está correcto y lo verifiqué leyendo.

Pero la incidencia que sale hacia el consumidor se construye así:

```dart
final entry = ProductSpecIssue(issue.code, issue.field, issue.message,
    blocking: issue.blocking, rowId: issue.rowId, columnKey: issue.column);
```

`ProductSpecIssue` no tiene campo para la colección y `collectionField` no
viaja. Con **dos colecciones agrupadas contra el mismo padre** —que la metadata
permite: `collections` sólo impide dos cardinalidades sobre el *mismo* `field`—
las dos emiten `row_cardinality_pending` sobre el mismo padre, el mismo `rowId`
y la misma columna, y el consumidor no puede distinguirlas ni saber cuál tabla
documentar.

**Severidad: baja, y es de presentación, no de validación.** Ninguna incidencia
se pierde ni se inventa; lo que se pierde es a qué colección se refiere.

## G-3 · La metadata agrupada no exige que la columna de vínculo sea obligatoria

No es un defecto del motor —la rama de huérfanas del punto 1 cubre el caso— pero
sí un borde que conviene decir antes de integrar, porque se combina con algo ya
conocido en este proyecto.

Ni `validate_row_cardinalities` (Python) ni la construcción Dart exigen que
`link.column` esté marcada `required` en el esquema hijo. Cuando no lo está:

- la fila huérfana queda `row_reference_pending`, **no bloqueante**;
- no entra en ningún grupo, así que los totales de todos los padres pueden
  cuadrar mientras la ficha lleva filas de más;
- y si esa misma columna forma parte de un `unique_by`, la llave se **salta**
  para las filas que la omiten (`product_spec_rows.dart:118-120`), de modo que
  dos huérfanas idénticas tampoco se detectan como duplicado.

Nada de eso es incorrecto por separado: un dueño sin documentar es evidencia
incompleta, no una contradicción, y ésa es la línea que el motor sostiene en
todas partes. Lo que sugiero no es cambiar el motor, sino **exigirlo en la
plantilla**: una plantilla que declara conteo agrupado debería declarar su
columna de vínculo `required`. Si se quiere en el motor, el sitio natural es
`validate_row_cardinalities`, que ya tiene el esquema hijo a mano.

## Metadata: lo que sí queda cerrado

- La forma agrupada es **excluyente** de la escalar en cada entrada: los
  conjuntos de claves esperados son disjuntos y `set(item) != expected` rechaza
  cualquier mezcla, en Python y en Dart.
- La forma agrupada **exige `version: 3`**; V2 la rechaza. Y `version` 4 sigue
  rechazándose en las dos implementaciones.
- El vínculo del grupo debe pertenecer a la propia colección
  (`link['field'] != source` → error), así que no se puede agrupar por el
  vínculo de otra tabla.
- La columna de total debe ser `integer` con `min` explícito y no negativo. Una
  columna `positive: true` sin `min` **se rechaza**: es la trampa que ya me
  costó una ronda en piñonería y aquí está cerrada.
- Una colección no puede llevar dos cardinalidades, y los ids de cardinalidad
  comparten espacio con los de vínculo, así que no pueden colisionar.
- El guard de publicación normaliza el vínculo resuelto dentro de la
  cardinalidad (`(c-'id'-'group_by') || {'group': l-'id'-'label_columns'}`), de
  modo que renombrar un vínculo **y** su referencia a la vez es un no-op, pero
  cambiar `total_column` no lo es. El `left join` por `group_by` no multiplica
  filas para las cardinalidades escalares, y el padre agrupado llega a
  `endpoints` por la unión de vínculos aunque `total_field` sea nulo.

## Alcance y lo que no afirmo

No corrí SQL: las 78 pruebas del evaluador/validador, la conservación bajo rol
authenticated y las regresiones anteriores con rollback quedan como evidencia de
root. Tampoco verifiqué esta extensión en la app real, que el propio documento
deja como pendiente. Mis fixturas son sintéticas y no prueban ninguna relación
OEM. Nada de esto habilita activación, asignaciones ni llenado.
