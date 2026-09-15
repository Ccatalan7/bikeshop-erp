# Revisión independiente del candidato de dirección (sólo lectura) — 2026-09-08

No edité ningún archivo de Root; sólo escribí este documento.

| archivo | sha256 verificado |
|---|---|
| `existing-headset-catalog-2026-09-08.json` | `afc09b1f…9293295e` |

Corrí: los 17 casos del paquete más su prueba de metadatos (**18 verdes**), la
auditoría de adopción y cuatro sondas mínimas con fixtures de scratchpad contra
el catálogo de Root sin modificarlo. **No verifiqué la parte SQL** (avance,
repetición y 17 casos con rollback): esta ronda es sin SQL.

## Dictamen

**El reparto por extremo está bien resuelto y sostenido por las fuentes.** La
propiedad superior/inferior, la separación cartucho / bolas sueltas / canastillo,
el tratamiento del SHIS como código nominal y la separación de los dos biseles
resisten la comprobación contra Park y Sheldon.

Encontré **un defecto vigente** —la geometría anular admite una transcripción
**invertida**, no sólo la igualdad que Root ya declaró pendiente— y **un punto a
adjudicar**: una ficha de extremo superior puede declarar que incluye pista de
corona, que las dos fuentes sitúan en el extremo inferior.

## 1. Lo que verifiqué y sostiene

Comprobado ejecutando el contrato y leyendo las fuentes, no por lectura del
código.

1. **El código se escribe superior | inferior, y el superior va primero.** Park
   lo documenta y Sheldon lo repite: la primera mitad describe la dirección
   superior y la segunda la inferior. Separar `headset_upper_shis` y
   `headset_lower_shis` es exactamente eso, y las tablas de rodamiento y las
   alturas instaladas siguen el mismo corte.
2. **Existen estándares de sólo un extremo.** Park lista combinaciones con
   `N/A` en el superior (por ejemplo los códigos IS de 1-1/4", 1-3/8" y 1-1/2",
   y variantes ZS y EC grandes). El token `Inferior` no es un adorno: hay
   producto real que sólo es extremo inferior, y el paquete lo prohíbe declarar
   datos del otro extremo. Cuatro casos lo fijan y los cuatro pasan.
3. **El SHIS es un código, no una medida.** Park lo dice literalmente al
   explicar el diámetro del tubo: son milímetros enteros que hay que tratar como
   código y no como medida exacta —el mismo texto muestra que un código «29»
   corresponde a un diámetro real de 29,8 mm—. El helper del paquete afirma eso
   y no convierte el código en cota.
4. **El código no determina la construcción del rodamiento, y por eso la
   compuerta correcta es la columna `construction`, no el SHIS.** Sheldon es
   explícito: el código no indica que se puedan mezclar piezas dentro de un
   extremo, y da el ejemplo de un conjunto con cartucho y otro con cazoleta y
   cono. Su propia tabla lo confirma: un mismo código admite «retén/bolas
   sueltas o cartucho». El paquete acierta al colgar la geometría de la
   construcción declarada.
5. **Los biseles gated en cartucho están respaldados por lo que pude leer.**
   Park atribuye la convención de ángulo de contacto —36° obsoleto, 45° actual—
   al sistema integrado con **cartucho**, y Sheldon anota el contacto angular en
   las filas integradas de su tabla. Con las dos fuentes leídas, permitir la
   geometría de asiento sólo para cartucho es defendible. **No afirmo que
   ninguna fuente publique ángulos de pista para un juego de cazoleta y cono**;
   si aparece una, esta compuerta necesitará el mismo tratamiento que recibió la
   sección elíptica en rayos.
6. **Bolas sueltas y cuerpo de cartucho no se mezclan.** Una fila de bolas
   admite cantidad y diámetro de bola y tiene prohibido el diámetro exterior de
   cartucho; y al revés. Dos casos del paquete lo fijan como bloqueo.
7. **Los dos biseles siguen separados y sin orden entre ellos.** Es coherente
   con la adjudicación previa de rodamientos y con el contrato padre, que
   prohíbe ordenar entre sí el bisel de una pieza y su ángulo interno de
   rodadura. Ausencia de `ordered_pairs` sobre los ángulos es correcta, no un
   olvido.
8. **Retirar los selectores viejos no pierde información.** El diámetro del tubo
   de horquilla vive dentro del propio código SHIS —es el número que va después
   de la barra—, así que el selector de tubo queda cubierto por el sucesor. Y el
   token «Tapered» del selector de estándar nunca fue un tipo de dirección: una
   horquilla cónica se expresa como **dos códigos distintos**, superior e
   inferior, como muestran las combinaciones mixtas de Park. Retirarlo corrige
   una confusión, no borra un dato.
9. **Integridad y números.** Las seis definiciones publicadas se reutilizan sin
   una sola diferencia de `id`, `label`, tipo, unidad, dominio ni reglas.
   Adopción reproducida: **15 evaluadas, 0 bloqueantes, 4 observaciones legacy**
   (2 del estándar viejo y 2 del tubo viejo), **ninguna observación activa sin
   proyectar**, 15 con datos pendientes; la auditoría cita el mismo SHA del
   catálogo.

## 2. Defecto vigente

### H-1. La geometría anular admite una transcripción invertida, no sólo la igualdad

Root declara pendiente la geometría **estricta** entre diámetro interior y
exterior, y advierte con razón que el motor de pares ordenados admite igualdad.
Ese pendiente sigue siendo correcto y no lo discuto.

Lo que falta es la otra mitad: **el par ordenado no está declarado en absoluto**.
Las dos tablas de rodamiento no llevan `ordered_pairs`, así que hoy no se
rechaza ni siquiera una fila con el interior **mayor** que el exterior, que es
el error de transcripción habitual y que el motor sí sabe detectar.

Reproducción mínima, contra el catálogo de Root sin modificarlo:

| sonda | resultado |
|---|---|
| fila superior de cartucho con interior **41** y exterior **30** | **pasa sin observación** |
| la misma fila con interior 41 y exterior 41 | pasa (es el pendiente ya declarado) |
| la misma fila con interior 30 y exterior 41,8 | pasa |

Hay un agravante concreto: `bearing_inner_diameter_mm` y
`bearing_outer_diameter_mm` son **uno de los cuatro pares heredados que el motor
trae cableados** (`product_spec_coherence.dart:267-274`), pero ese par sólo se
activa cuando ambas claves son **campos escalares activos de tipo número**. Aquí
viven como columnas dentro de una tabla, de modo que la protección que existe
para la versión escalar de esos mismos dos nombres **se pierde en silencio** al
moverlos a filas.

**Corrección propuesta, sin motor nuevo y sin tocar al dueño compartido:**
declarar en el `rows_schema` de las dos tablas

```json
"ordered_pairs": [["bearing_inner_diameter_mm", "bearing_outer_diameter_mm"]]
```

El esquema de filas ya admite `ordered_pairs` sobre dos columnas `decimal`
(`product_spec_rows.dart:15-60`) y lo evalúa por fila como bloqueo
(`product_spec_rows.dart:107-113`); el mismo paquete lo usa ya en otra familia
de rangos. Eso captura la inversión **y deja intacto el pendiente**: la igualdad
`interior = exterior` seguiría pasando, así que **no queda resuelta** y sigue
necesitando la adjudicación con el dueño de rodamientos. No propongo otra
familia de motor ni un evaluador nuevo.

## 3. Punto a adjudicar

### H-2. Un extremo superior puede declarar que incluye pista de corona

`crown_race_included` es booleano **obligatorio siempre** y no depende del
alcance; `headset_supplied_crown_race_reference` cuelga sólo de él. Por eso una
ficha declarada `Superior` puede afirmar que incluye pista de corona y dar su
referencia, sin ninguna observación.

| sonda | resultado |
|---|---|
| alcance `Superior` + `crown_race_included: true` + referencia | **pasa sin observación** |

Las dos fuentes sitúan esa pieza en el extremo inferior. Sheldon la enumera como
la cuarta pista del conjunto, prensada en la base del tubo de horquilla justo
sobre la corona; Park la introduce dentro de la nomenclatura del **stack
inferior** y le dedica su tabla de códigos de pista de corona, separada de la
sección del stack superior. Sheldon añade que incluso en un juego integrado,
cuyos cartuchos entran a presión ligera, la pista de corona va prensada.

No lo declaro defecto cerrado porque hay un caso comercial imaginable —un kit de
extremo superior que empaqueta además una pista de corona—, y ese caso no tiene
hoy un token propio de alcance. La adjudicación es de producto: o se condiciona
`crown_race_included` a `Inferior`/`Completa` con la misma forma de compuerta que
ya usan los demás campos por extremo, o se documenta que el contenido del envase
es independiente del alcance declarado. Lo que no debería quedar es implícito.

## 4. Limitaciones conocidas, no defectos

1. **`Desconocido / sin confirmar` es idéntico a la celda vacía** —tanto en
   `headset_part_scope` como en las columnas `construction` y `seat_geometry`—
   porque el motor compartido lo lee como ausencia. No pide cambio aquí; sí
   conviene no contarlo como capacidad de expresar «el fabricante no lo declara».
2. **El SHIS es texto libre**, así que `ZS44/28.6` y `ZS44 / 28.6` no se
   comparan. Es coherente con no cerrar un dominio de códigos por marca, y el
   propio paquete deja la relación OEM/modelo como pendiente.
3. **Una tabla por extremo admite una sola fila**, porque `position` tiene un
   único token y es la llave de unicidad. Es correcto para un extremo de
   dirección y conviene que quede escrito, porque no es evidente al leer el
   esquema.

## 5. Integración pendiente

Los dos pendientes declarados por el paquete son los correctos y ninguno se
presenta como prueba superada: la integración de referencias OEM/modelo con las
interfaces SHIS, y la geometría anular **estricta**, que necesita al dueño
compartido de rodamientos. H-1 no sustituye al segundo: lo reduce.

## 6. Fuentes abiertas de primera mano en esta ronda

- Park Tool, *Standardized Headset Identification System* —
  `https://www.parktool.com/en-us/blog/repair-help/standardized-headset-identification-system`
- Sheldon Brown / John Allen, *Servicing Bicycle Headsets* —
  `https://www.sheldonbrown.com/headsets.html`
