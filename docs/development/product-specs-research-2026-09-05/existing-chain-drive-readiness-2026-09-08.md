# Cadenas, conectores y kits: sucesor local

El compilador `compile_existing_chain_drive_catalog.py` conserva la entrega
aplicada de cadenas/conectores y las 27 definiciones compartidas. Propone 11
definiciones nuevas, 52 usos y 41 cambios de metadatos en tres plantillas.
Ninguna se ha activado con este sucesor; no hay llenado ni reasignaciones.

## Cambios y fuentes comprobadas

Se retiran los selectores generales de ecosistemas/plataformas de la captura
de cadenas. Una aplicación conserva juntas su fuente, sistema o modelo,
generación, tipo de transmisión, piñones y condiciones. Las marchas internas
no ocupan el campo de piñones. La lista histórica de velocidades conserva su
significado descriptivo y la regla ya aplicada de 1/8 + desviador moderno;
no se usa para generar cruces entre marcas o aplicaciones.
[Park Tool](https://www.parktool.com/en-us/blog/repair-help/chain-compatibility)
explica esas diferencias y la necesidad de considerar también platos y
geometría de la cadena. Sus medidas orientativas no se convierten en límites.

El peso tiene su base de medición y fuente. La ficha de
[KMC X8 BX08NP114](https://www.kmcchain.eu/products/x8-silver) distingue 114
eslabones suministrados de la masa declarada por 110. El dato de pesaje no
rellena la longitud vendida. Los cierres rápidos incluidos tienen cantidad de
cierres completos; declarar que no se incluyen vuelve inaplicable su contenido.

El conector apunta a cadenas concretas, con alternativa por sistema cuando ése
es el alcance publicado. [KMC CL573R](https://www.kmcchain.com/en/product/connector-missing-link-cl573r-8s-7s-6s-speed)
documenta destinos específicos. [SM-CN900-11](https://bike.shimano.com/en-AU/products/components/pdp.P-SM-CN900-11.html)
admite LINKGLIDE/HG 11: su clase no equivale a contar los piñones de la bicicleta.
Se conserva la prohibición aplicada de reutilizar un pasador de unión, con
[Sheldon](https://www.sheldonbrown.com/chains.html) como fuente. El máximo de
usos sólo aplica si la fuente declara reutilización; nunca se infiere de un
conector incluido o de una silueta.

Los kits retiran medidas globales de sus piezas. Cada miembro conserva
identidad, interfaz y declaraciones enlazadas a su fila. Una interfaz puede
tener varios extremos; un ID ajeno bloquea. Los miembros no presuponen cadena,
cassette o mando. El único título del inventario es una pista para revisar la
asignación, no prueba de contenido ni autorización de mudarlo de familia.

## Comprobación y límites

- 37 pruebas Dart (tres plantillas y 34 casos) pasaron tras la revisión.
- Los 34 casos SQL pasaron con avance, repetición exacta y rollback; no se
  modificaron productos, referencias o mapeos. El verificador compara metadatos
  completos y preservación, no sólo conteos.
- Tres relaciones se ejecutaron en el evaluador Dart existente. La exclusión
  [Eagle Drivetrain PowerLock → cadena T-Type](https://support.sram.com/hc/en-us/articles/26180202731931-Can-I-use-an-Eagle-Drivetrain-PowerLock-on-my-Eagle-Transmission-Chain)
  conserva su dirección; falta cadena = desconocido, no autorización. Este
  ensayo no acredita integración de referencias, SQL de relaciones ni taller.
- Captura autenticada de 41 productos: 31 cadenas, nueve conectores y un kit.
  Adopción: cero bloqueantes, una observación legacy preservada, cero activas
  sin proyección; los 41 siguen pendientes de datos. Cero escrituras.

La [revisión independiente](chain-drive-independent-review-2026-09-08.md)
reprodujo la primera matriz y detectó cuatro puntos. F1, F3 y F4 están
corregidos: las tablas de kit exigen evidencia de la presentación, la lista
descriptiva de velocidades no exige escoger una modalidad única y los casos
incluyen miembros completos con rol. Un caso comprueba que ambas aplicaciones
(externa/interna) no generan esa pendencia; otro comprueba la evidencia del kit.
La adopción se repitió con este delta y conserva 41 evaluados, cero bloqueantes,
una observación legacy y 41 pendientes.

F2 permanece abierto y bloquea dar por terminada la ficha de kits: falta el
perfil técnico tipado por miembro. Sus medidas no deben volver como escalares
del kit ni como números con unidad libre; deberán reutilizar la ficha de la
familia del componente y su identidad/referencia, verificando el dueño del
miembro. Las tablas actuales sí guardan sus interfaces y declaraciones, pero
no sustituyen ese perfil. No se ha llenado ni activado el kit.

La integración OEM/cliente sigue abierta. Las
declaraciones nuevas no pueden añadirse a una referencia antigua que no las
documenta: se necesitan referencias revisadas con identidad/fuentes y versión
propias. Una prueba de representación sin esa referencia no valida hechos
mecánicos inventados. El saneamiento global precede al llenado.

Catálogo SHA-256:
`ab1e52a97a73ea1530d48845b7b470871f35ec7898687bbbcda71e4d80dcd1f5`.
Casos: `987ec6c10317ea76e1702cd660c18dcc347e4ed97a1faaafc7523801a09dd653`.
Preimagen final: `7a1fdb10197ec113d062d5dda761c60429cff1238d4db027d0985e91fb08cbab`.

Evidencia privada: `.tmp/db/existing-chain-drive-candidate/forward-replay-and-cases.log`,
`.tmp/product-spec-catalog/existing-chain-drive-tests.log`,
`existing-chain-drive-relations.log`, `existing-chain-drive-adoption-20260908-review.json`
y `existing-chain-drive-snapshots-20260908/manifest-20260908T184627599557Z.json`.
Los alias SQL `field_constraint` para las restricciones heredadas y el entero
se fijaron después de observar resultado, dueño y gravedad. Las fallas de
formato de estas filas usan `row_shape` en ambos motores; no se generaliza el
alias de otro candidato por parecido del mensaje.
