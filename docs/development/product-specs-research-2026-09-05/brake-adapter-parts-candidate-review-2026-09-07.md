# Frenos y adaptadores — dictamen final (2026-09-07)

Revisión independiente del sucesor de root, que reemplaza mi candidato inicial.
No edité candidatos, motor, migración ni base; no corrí el publicador SQL. Sondas
propias en el scratchpad contra el catálogo sin modificar.

**Veredicto: publicable. Ningún bloqueo.** Las nueve decisiones se sostienen,
medidas una por una, y dos de ellas corrigen errores míos.

## Integridad

Los **nueve** SHA-256 recomputados coinciden exactamente con los declarados,
incluidos compilador base `de969062…496f`, adjudicador `7dc9ddda…8c69`,
publicador `61fb3ce7…bb06`, migración `0a635869…cc6b` y verificador
`0c3eef4c…80c9`.

El adjudicador es **obligatorio en los dos sentidos**:
`from compile_brake_adapter_parts_root import review_brake_parts` es import de
nivel superior y `review_brake_parts(...)` se llama en la línea 286. No hay ruta
que produzca artefactos sin pasarlo.

**46 pruebas Dart: las corrí yo, pasan**, con RCF38 y RCF39 dentro. Aritmética
del paquete: 19 definiciones nuevas + 6 reutilizadas = 25; 33 opciones; 4
plantillas; 28 usos. Superficie de escritura sólo sobre las cuatro tablas de
metadatos y pin `ac0738d5c2039412b603dc71adc41721`.

Delta contra el congelado: 4 definiciones añadidas y 3 modificadas
—`brake_adapter_fitments`, `brake_part_kind`, `rotor_adapter_fitments`—, **las
tres de una sola familia**. Comprobado byte a byte que `bolts_included` (3
familias), `thread` (3), `compatible_brake_models` (5), `brake_actuation` (5),
`material` (27) y `pack_quantity` (19) siguen idénticas.

## Quince sondas adversariales

| Sonda | Resultado |
|---|---|
| Centerlock conservando la rosca de su anillo | limpio |
| Centerlock usando la celda de rosca de maza | **bloquea** `row_field_applicability` |
| ruta de rosca especificada usando la celda de maza | limpio |
| función «Tipo de fijación» cargando un desplazamiento | **bloquea** |
| desplazamiento sin su datum | `row_required_missing` no bloqueante |
| seis pernos de entrada y de salida, con límite de rotor y contexto | limpio |
| misma configuración resuelta con estados opuestos | **bloquea** `row_shape` |
| configuración distinta con estado opuesto | limpio — se conserva |
| resorte declarado roscado | **bloquea** `row_value_conflict` |
| bolsa de tornillería descompuesta en tornillo y clip | limpio |
| OLD como interfaz propia junto a una rosca de eje | limpio |
| fila de OLD cargando un paso | **bloquea** |
| interfaz apuntando a una configuración inexistente | **bloquea** `row_reference_unresolved` |
| freno de maza de rodillo con actuación hidráulica | limpio — sin prohibición universal |
| contrapedal declarado de cable | **bloquea** |

Las quince acertaron. Verifiqué además la decisión 3 por lectura directa del
esquema: `quantity` lleva `{"positive": true}` en las dos tablas de piezas, y
`thread_diameter_in` es **decimal**, no texto, así que un paso no puede
esconderse dentro de una etiqueta de diámetro.

## Las dos correcciones son mías

**El `thread_owner` que propuse era el instrumento equivocado.** Yo intenté
resolver la ambigüedad de `hub_thread_spec` con una columna que dijera de quién
era la rosca. La adjudicación hace lo correcto: **dos celdas distintas**, porque
son dos puertos distintos, con la de maza restringida a la ruta roscada y la del
anillo disponible también en sistemas de estrías. RCF39 mueve su dato conocido a
la celda del anillo y conserva su resultado; RCF38 mantiene la rosca de maza sin
resolver y su faltante visible. Es más simple que mi propuesta y dice más.

**Puse enlaces de Park como fuente de fixtures sintéticas.** Park respalda los
nombres IS/Post/Flat y nada más; usar su URL como `source_url` de una
configuración inventada la hacía parecer aprobada por Park. Comprobado: **no
queda ninguna URL de Park en el archivo de casos**. Es el mismo desliz que
cometí con Park en las filas de líquido, y van dos.

## Riesgos reales que quedan, y ninguno bloquea

- **`brake_adapter_included_hardware` no tiene clave compuesta.** Es defendible
  —dos tornillos iguales en una bolsa no son una contradicción— pero significa
  que dos herrajes idénticos con largos distintos conviven sin señal. Distinto
  de las tres tablas que sí la llevan, y conviene que sea una decisión y no un
  descuido.
- **`edition` sigue opcional en las dos tablas de aplicación**, mientras que en
  hidráulica se volvió requerida por HY-B. La consecuencia es la misma que allí:
  la clave compuesta de estas tablas no incluye la edición, así que aquí no
  debilita la unicidad, pero dos ediciones distintas del mismo modelo tampoco se
  distinguen por sí solas.
- **`configuration` e `interface` son textos libres** dentro de las claves. La
  unicidad exige identidad resuelta y no compara alias, como el propio documento
  declara; «Trasero» y «trasero» son dos configuraciones.

## Lo que no verifiqué

No corrí los 42 casos SQL ni las cinco regresiones del publicador, ni consulté
preimagen viva, respaldo, verificador antes/después o estado de aplicación:
siguen en tu lista de pendientes y son tuyos.

De las fuentes citadas sólo puedo dar fe de dos, y por lecturas mías previas:
Park sobre los tres estándares de montaje, y Sheldon sobre el contrapedal como
maza trasera con brazo de reacción sujeto. **No abrí el PDF de Shimano
DM-MDBR001-05** —`si.shimano.com` me devolvió 403 en las dos rutas que probé en
mi ronda— ni la ficha de Wolf Tooth Boostinator, cuyo dominio me entregó sólo
navegación las dos veces que lo intenté. La exclusión textual de SM-RT86/SM-RT76
y el contexto del Boostinator provienen de tu lectura declarada, no de la mía, y
lo digo para que no se lea como verificación independiente. Lo que sí verifiqué
es que el esquema **puede** representar ambas cosas sin deducir nada: la
exclusión como estado, y la entrada y salida de seis pernos sin inventar un
desplazamiento.

Nada de esto es aprobación mecánica. El esquema representa estas declaraciones y
se niega a contradecirse dentro de una fila resuelta; que un adaptador concreto
sirva a un cuadro concreto sigue siendo afirmación del fabricante, y el fill
sigue en cero.
