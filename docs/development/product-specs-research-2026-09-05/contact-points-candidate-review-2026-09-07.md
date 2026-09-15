# Revisión del candidato y de la publicación de puntos de contacto

2026-09-07. Revisión independiente, sin editar nada ajeno. Sólo lecturas de artefactos, código y
fuentes públicas; sin base de datos, runtime, git ni subagentes.

Versión corregida: raíz señaló dos atribuciones mías indebidas, marcadas abajo como **Corrección 1** y
**Corrección 2**. Las citas literales quedan acotadas a un máximo de 25 palabras por fuente; el resto
es resumen con la fuente nombrada.

| artefacto | SHA-256 |
|---|---|
| `compile_contact_points_catalog.py` | `c9f49021832ac83a82280a7992378644ec89af01fe0c4f7c1e7801dd02e153fc` |
| `contact-points-catalog-2026-09-07.json` | `1a10d6e52e4b50ae2da80dc2590cd0c510a639884edb8e46d0c7c81b1c0dc40a` |
| `contact-points-cases-2026-09-07.json` | `6695414854f1f025653d99d3d2a9ba35cd4a3ab1b01578f4f64a5b3af0e0d1dc` |
| `contact-points-publication-packet-2026-09-07.json` | `15bd2b80878ef1020fc1b408736b83d3d24a6fb14c4c47d78b31953f38cffde5` |
| `contact-points-publication-preimage-2026-09-07.json` | `5e12173a2fb34f0aa2ed69c2bcfb74f8a9fb368ad352022a94b9c142ac40ccae` |
| `20260907235000_contact_point_spec_templates.sql` | `6992d0facc1856df75df556ed1f54e017b88e0eaa3e26047799260a1bad85e89` |
| verificador homónimo | `1b892fa4b21ebb0f90f000b5c92870eeaa1c584cc310433945277fc62c6243da` |

Los siete coinciden con los que recalculé. 10 plantillas, 109 definiciones, 133 usos, 75 casos.

# Dictamen: **aplicar**

El candidato resuelve bien lo que yo formulé mal y arregla un defecto que se me pasó. La publicación
está limpia y es la misma máquina ya aplicada dos veces.

## 1. CP-1: lo rechazo como lo formulé

**El eje ya estaba declarado, y yo no lo miré.** `grip_inner_diameter_mm` se llama «Diámetro interior
medido del puño» con `semantic_role: measurement`, y `grip_bar_nominal_diameter_mm` «Diámetro nominal
de manubrio previsto» con `semantic_role: compatibility`. Revisé `roles` —donde ambos son
`measurement`— y las condiciones, y no leí ni las etiquetas ni `semantic_roles`, que son los dos
lugares donde estaba dicho. Escribí «nada dice cuál es cuál» sin mirar dónde se dice.

**El salto a que deben coincidir no lo sostiene ninguna fuente, y mi caso negativo lo colaba.** Park
Tool describe la retención de un puño deslizante como «friction fit or interference fit», con el puño
estirado sobre el manubrio, y la del lock-on por collarín; su artículo no pone en relación el calibre
interior con el diámetro del manubrio. Mi «negativo» —22,2 nominal con 31,8 interior, «aceptado»—
presuponía una relación numérica que ninguna fuente establece: era el mínimo mecánico que yo mismo
decía no estar proponiendo.

**El fabricante nombra el eje de compatibilidad, y es el nominal del manubrio.** El manual GP1 de
Ergon condiciona la compatibilidad a que el manubrio esté certificado para el par indicado y cumpla el
«standard external diameter of 22.2mm», y advierte que las tolerancias de fabricación pueden dificultar
el calzado. La interfaz es el diámetro exterior nominal del manubrio; el calibre propio del puño no se
pone en relación con nada.

> **Corrección 1.** En la versión anterior escribí que
> `cp_grip_different_measured_and_nominal` —22,2 nominal con 21,9 medido— «es precisamente el ajuste
> por interferencia que describe Park Tool». Es falso y raíz tiene razón: ese caso es una **fixture
> sintética de representación** (lleva `kind: "synthetic_representation"` y `source_urls: []`), y Park
> Tool no publica esas cifras ni tolerancia alguna. Lo que el caso demuestra es que la representación
> admite una medición distinta del nominal sin incidencia; **no** que ese par de números sea un ajuste
> mecánico confirmado. Atribuir cifras a una fuente que no las da es exactamente lo que no debo hacer.

Lo que sobrevive de CP-1 es sólo lo que ya implementaste: una medición interior sin zona ni condición
no es reproducible. El prerrequisito no bloqueante `grip_measurement_reference` y los dos helpers
—que dicen explícitamente que el interior no se iguala al nominal por fórmula y que el nominal no se
obtiene midiendo el puño— lo cierran y dejan la no-relación escrita donde el operador la lee. Lo
acepto como resolución completa.

## 2. CP-2: acepto tu caracterización

Es limpieza declarativa, no un fallo mecánico reparado. Los tres retirados quedaron uniformes
—`pedal.pedal_thread`, `grip.grip_clamp_torque_nm` y `seatpost.dropper_actuation`, todos `legacy` con
`allowed_when` y `required_when` en `never`— y el `required_when: always` que hacía leer
`pedal_thread` como obligatorio ya no está.

Una precisión para el próximo lector, no una objeción: ese `never` es documentación, no la aplicación.
La retirada efectiva es `role: legacy`, como quedó verificado en DL-5.

## 3. El defecto del torque es real, y era mío

Llamé «bien fundado» a `grip_clamp_torque_nm` **citando esa misma página de ODI**. Comprobé que ODI
publica un par de apriete; no comprobé si la forma publicada cabía en la forma del campo. Es el mismo
error que vengo señalando en otros: verificar que el dato existe y no que la representación lo admite.

ODI publica, para las mordazas lock jaw v2.1, «40-45 in-lbs (4.5-5.0 Nm)». Un escalar no guarda un
rango ni dos unidades publicadas. Y 40 in-lb son 4,519 N·m y 45 in-lb son 5,084: ODI redondeó cada
extremo por separado, así que las dos filas son **dos lecturas**, no una convertida dos veces.

## 4. Ergon GP1: confirmado de forma independiente

El PDF no se dejó leer por la herramienta de fetch, así que descomprimí sus flujos localmente y leí el
texto. El manual publica el par como «5 Nm (3.7 ft-lb)» en inglés, y sólo «5 Nm» en las secciones
alemana y francesa. Tu cita es correcta. Y 5 N·m son 3,688 ft-lb: los 3,7 son el redondeo **del propio
fabricante**, que es justo por qué registrar ambos es leer, y convertirlos nosotros no lo sería.

El mismo manual declara además una fuerza de extracción de «70 N (16 lbf)» contra la norma DIN EN
14766: un tercer par de unidades publicadas en un solo documento. Eso respalda que la forma de tabla
es la general de este dominio y no un parche para puños.

## 5. La tabla nueva es correcta y ejecutable

`grip_clamp_torque_specifications` tiene los tres modos **excluyentes de verdad** —`allowed_when` y
`required_when` por columna, el patrón de `wheel_size_declarations`—, `ordered_pairs
[["minimum","maximum"]]`, `unit` requerida sobre {Nm, in-lb, ft-lb} —que cubre las dos fuentes—,
`configuration` requerida y `unique_by: None`, de modo que dos filas de la misma magnitud en unidades
distintas son legítimas. Es exactamente la forma de ODI y la del GP1.

Los casos lo comprueban: rango invertido da `row_shape` bloqueante; «Par nominal» con `value` y
`minimum` a la vez da `row_field_applicability` bloqueante; unidad ausente da `row_incomplete` no
bloqueante; y las dos filas de ODI y las dos del GP1 pasan sin incidencia.

## 6. Los dos ejes de longitud siguen separados, pero no por lo que yo dije

El manual GP1 publica dos cosas distintas: la zona recta mínima que el puño exige en el manubrio, y el
contenido del paquete con el largo de cada puño. Para la variante Rohloff/Nexus ambas son 128 y 93.

> **Corrección 2.** Escribí que en la variante Standard «difieren» —contenido 128/128 frente a 128
> requeridos— y que ésa era la razón de mantener los campos separados. Es falso: los 128 requeridos
> son **por lado**, así que en Standard las dos magnitudes valen 128 en ambos lados y no hay
> discrepancia alguna. Los ejes se conservan porque **significan cosas distintas** —lo que trae la
> caja frente a lo que el manubrio debe ofrecer—, no por una diferencia numérica que no existe.

Con esa corrección, tu caso GP1 sigue siendo fiel a la fuente: conserva los largos por lado junto al
nuevo dueño del torque, y las dos magnitudes se registran cada una en su campo.

## 7. Un punto que conviene mantener a la vista

`cp_grip_attachment_unknown` lleva `expected_issue_subset` con `prerequisite` y
`expected_sql_issue_subset` con `field_applicability` no bloqueante **para el mismo estado**. Es
correcto: en Dart una aplicabilidad `unknown` emite `prerequisite` con `blocking: false`, y el lado SQL
la nombra distinto. Lo tienes parametrizado, así que no es un hallazgo; lo que vale la pena que quede
escrito es que **cualquier consumidor que discrimine por `code` tiene que tratar un
`field_applicability` no bloqueante y un `prerequisite` como el mismo estado desconocido**.

## 8. La publicación

**La misma máquina, sin variantes.** Quitando la cabecera de dos líneas y el documento incrustado,
**las tres migraciones —222000, 233000 y 235000— son idénticas entre sí**, y los verificadores
también. La lógica que ya revisaste y aplicaste dos veces viaja verbatim: igualdad JSONB por claves
administradas, huella de las cuatro tablas, pin del motor y comprobación de homónimos. Y los dos
bloques aplicados siguen byte a byte como los hasheé antes de aplicarse.

**Las diez compartidas se leen y nunca se escriben.** 99 nuevas + 10 compartidas = 109, igual que el
candidato, sin solapamiento de claves y con **cero filas de opción apuntando a una compartida**.
`pedal_thread` entra como compartida histórica, y es correcto que la plantilla la siga incluyendo: un
campo `legacy` necesita su definición y su fila de campo para que el valor retirado se muestre en sólo
lectura.

Comprobé lo que podía fallar en el read-back y no falla: los `allowed_values` de las diez coinciden
exactamente entre la preimagen de producción y el catálogo candidato, y las diez listas de opciones
vienen **ordenadas por id** —que es el orden con que el verificador las compara— y el paquete las
conserva idénticas a la preimagen. Preimagen capturada a las 23:36:12Z, con cero colisiones de
plantilla.

**Integridad de los 356 registros:** cero campos hacia definición o plantilla desconocida, cero ids de
campo u opción repetidos, cero pares (plantilla, definición) o (definición, código) repetidos, cero
códigos fuera de forma, los 356 globales, y cero colisiones de clave con los bloques de 12 y 14.

**Sin cambios:** las diez entran con `is_active: true`, así que sigue valiendo lo de siempre —la
recuperación por desactivación es libre sólo hasta la primera ligadura—, y las compuertas del paquete
están en `false`: `product_writes`, `fill_allowed`, `mechanical_approval`.

Que el verificador de producción fallara antes de aplicar es lo esperado: afirma metadatos que aún no
existen.
