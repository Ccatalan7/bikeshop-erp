# Consumidor de criterios: revisión independiente

2026-09-07. Revisión sólo lectura de los cuatro archivos. No los edité. Las
sondas que escribí viven fuera del árbol, en el scratchpad de la sesión.

**La corrección es correcta y aguanta.** Probé las cinco afirmaciones del
handoff y las cinco se sostienen. Pero encontré **un defecto aparte, y de los
que importan ahora**: no está en lo que corregiste, está en cómo el editor
siembra sus borradores, y lo va a disparar justamente la publicación de las 37
que estás preparando.

## El defecto: una plantilla que gana un campo revienta el editor

`_seed()` corre en `initState` y en `didUpdateWidget` **sólo** si cambian
`template?.id` o `criteria`
([supply_need_refinement_editor.dart:245](lib/modules/purchases/widgets/supply_need_refinement_editor.dart:245)).
Después, dos rutas leen el borrador con `!`:

- al dibujar cada criterio, `_drafts[definition.key]!`
  ([:682](lib/modules/purchases/widgets/supply_need_refinement_editor.dart:682));
- al recolectar predicados, `_drafts[definition.key]!`
  ([:1077](lib/modules/purchases/widgets/supply_need_refinement_editor.dart:1077)).

El conjunto de campos puede crecer **sin que cambie el id**. Es exactamente lo
que hace el publicador de plantillas existentes: conserva identidad e ids,
agrega campos y sube `contract_version`. Un editor que reciba la plantilla
refrescada, con los mismos criterios, no re-siembra, y el campo nuevo no tiene
borrador.

Lo reproduje con una sonda de widget —misma plantilla, mismo id, un campo más—:

```
Null check operator used on a null value
```

No es hipotético y no depende de una carrera: basta que la plantilla se
refresque en memoria mientras el editor está montado. Con las cinco de
rodamiento/motor subiendo de 2→19 y 9→29 revisiones, y **24 filas de campo
nuevas** sólo en ese bloque, esto se va a encontrar solo.

`contract_version` no participa de la condición de re-siembra, y ése es el dato
que la base ya mueve en cada cambio real.

**Dos arreglos posibles, y prefiero el segundo.** Comparar también el conjunto de
claves —o `contract_version`— en `didUpdateWidget` cierra este caso. Sembrar el
borrador de forma perezosa en los dos puntos de lectura (`putIfAbsent`) cierra
**la clase entera**, porque deja de depender de cuándo corrió la siembra. Es tu
archivo; no lo toqué.

Ninguna de las dos pruebas nombradas cubre una plantilla actualizada en su sitio:
las 27 que corrí de esos dos archivos pasan, y pasan igual con el defecto
presente.

## Lo que verifiqué de la corrección, y se sostiene

**Sólo igualdad escalar unívoca alimenta condiciones.** `gt`, `gte`, `lt`,
`lte`, `neq`, `between` e `in` quedan fuera por la guardia de operador y
cardinalidad, y `multi_select` se excluye por tipo. Además cada valor se valida
contra su `dataType` y, en un select, contra las opciones vivas de la definición.

**Busqué dos caminos por los que un valor exacto falso podría entrar igual, y
ninguno es alcanzable.**

- `effectiveSupplyNeedCriteria` hace `predicate.values.single`, que lanzaría si
  el extractor emitiera un predicado con dos valores. Fui a los dos únicos sitios
  que construyen esos predicados
  ([supplier_need_portal_search.dart:2059 y :2160](lib/shared/services/supplier_need_portal_search.dart:2059)):
  **siempre** `operator: 'eq'` con exactamente un valor. No lanza.
- En la fusión, `operadorDe[campo]` se sobrescribe por fuente mientras los
  valores se juntan en un conjunto, así que dos fuentes que dijeran el mismo
  número con operadores distintos producirían un predicado con el operador de la
  última. Sería un `eq` convertido en umbral. **No es alcanzable por la misma
  razón**: el extractor sólo emite `eq`. Lo dejo escrito porque la guardia que lo
  impide está en otro archivo, y si algún día ese extractor aprende a leer
  «mayor a 2,0», el defecto aparece aquí sin que nada en este archivo cambie.

**Las ausencias no satisfacen reglas negativas ni de presencia.** El evaluador
devuelve `unknown` antes de llegar a `eq`/`neq`/`in` cuando el valor no se
conoce, así que una ausencia no puede cumplir un `neq`. `is_set` y `not_set` sí
deciden con la ausencia, pero nunca se llegan a evaluar sin su entrada: tanto
`supplyNeedCriterionOptionsOf` como `supplyNeedCriterionFieldsOf` exigen que
**todas** las dependencias de la regla estén en los valores conocidos, y
`specConditionDependencies` reporta el campo de una regla de presencia y recorre
`all` y `any`. Sonda: con el campo gobernante desconocido, una regla `neq` no
estrecha ninguna opción; con el gobernante decidido, sí.

**Aplicabilidad v2 y las dos restricciones de opciones se comparten de verdad.**
`applicabilityDependencies` es la unión de las dependencias de `visibility_rules`
y de `allowed_when`, y `applicabilityFor` evalúa exactamente esas dos y las
combina por el peor caso. El conjunto de dependencias cubre todo lo que la
evaluación lee: no hay una rama que se evalúe con entradas que nadie declaró.

**Los criterios ocultos se conservan, y también los retirados.**
`carryForwardUnexpressedPredicates` arrastra cualquier predicado vigente cuyo
campo no sea expresable y que no venga ya dibujado. Sonda directa: sobrevive.
Y probé el caso que este proyecto va a producir en serie —**retirar** un campo—:
el criterio guardado sobre un campo que pasa a `legacy` se conserva al guardar,
el editor no se rompe, y ese campo deja de alimentar prerrequisitos. Las tres
cosas correctas a la vez.

**El valor viejo de un campo que dejó de aplicar se descarta.** El bucle de punto
fijo de `supplyNeedExactPrerequisiteValues` quita el hijo cuando el padre cambió,
y termina. Sonda: `parent=B` con `child=C` heredado deja sólo `parent`.

## Diferencia entre criterio y observación

El código la nombra bien —«prerequisite inputs, not product facts»— y la
mantiene donde importa: lo pedido nunca se afirma como propiedad del producto, y
un criterio ausente no declara que el producto carezca de esa propiedad.

Dos lugares donde la línea es fina y conviene que estén dichos, no porque estén
mal sino porque son decisiones:

- **Una inferencia puede esconder un campo.** `effectiveSupplyNeedCriteria`
  deriva predicados del texto de la petición, esos predicados entran como
  entradas de prerrequisito, y con ellas un campo puede volverse inaplicable y
  desaparecer del formulario. Sonda: con `wheel_size` derivado en 700, el campo
  que sólo aplica a 26 deja de ofrecerse. El servicio documenta que la derivación
  se muestra para que el operador la vea y la cambie; lo que no se ve es **la
  consecuencia**: que un campo dejó de estar por una lectura del texto y no por
  una decisión. No pido cambiarlo; pido que quede declarado.
- **Las restricciones de opciones son del producto y limitan al comprador.**
  `supplyNeedCriterionOptionsOf` usa `constraintRules`, que dicen qué puede
  declarar un producto, para acotar qué puede **pedir** el operador. Es lo que
  pediste explícitamente y es conservador, porque toda regla sin entradas
  conocidas se descarta antes de evaluarse. Queda anotado como lo que es: el
  comprador no puede pedir una combinación que el catálogo no debería contener.

Y una nota menor, para que nadie lo «arregle» después:
`supplyNeedCriterionFieldsOf` acepta `multi_select` como campo de criterio, pero
`supplyNeedExactPrerequisiteValues` lo salta siempre. Es correcto —un conjunto no
es una respuesta unívoca— y significa que un criterio multi-select nunca puede
gobernar a otro campo.

## Pruebas

Corrí las dos nombradas: **27 verdes**. No amplié la batería del motor: no hay
cambio que lo justifique. Mis seis sondas independientes: cinco confirman la
corrección, una reproduce el fallo del editor.

## Hashes revisados

| Archivo | SHA-256 |
|---|---|
| `lib/modules/purchases/services/supply_need_effective_criteria.dart` | `6b2c15150a21a8ed…` |
| `lib/modules/purchases/widgets/supply_need_refinement_editor.dart` | `2987930e479824fd…` |
| `test/unit/supply_need_prerequisite_values_test.dart` | `faba150bf1bbd47b…` |
| `test/widget/supply_need_editor_test.dart` | `d7abfeb344d9bdc5…` |

Sin base, sin git, sin runtime, sin publicación. No edité ninguno de los cuatro.
