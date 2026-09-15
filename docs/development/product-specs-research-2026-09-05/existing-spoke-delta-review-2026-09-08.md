# Revisión del delta de rayos (sólo lectura) — 2026-09-08

Revisión independiente del **delta** del candidato de rayos, no del candidato
anterior. Sólo se señalan defectos vigentes en los archivos con estos hashes.
No edité ningún archivo de Root; sólo escribí este documento.

| archivo | sha256 verificado |
|---|---|
| `existing-spoke-catalog-2026-09-08.json` | `4a10cf01…c62beb7e` |
| `existing-spoke-cases-2026-09-08.json` | `e5e58296…59b53b7457` |

Corrí: los 30 casos del paquete más su prueba de metadatos (**31 verdes**), la
auditoría de adopción y cuatro sondas mínimas con fixtures de scratchpad contra
el catálogo de Root sin modificarlo. **No verifiqué la parte SQL** (avance,
repetición y rollback): esta ronda es sin SQL, así que esas 30 corridas quedan
fuera de mi dictamen.

## Dictamen

**El delta corrige lo señalado.** Los tres bloqueos y las cuatro precisiones
están implementados y son observables. No encontré ningún bloqueo nuevo: no hay
ningún producto documentado por las fuentes del propio paquete que hoy no se
pueda escribir. Queda **un defecto de menor severidad** —una inversión entre lo
exigido y lo opcional en las cotas de rosca— que produce un pendiente
permanente, no un bloqueo, y tiene arreglo de una línea.

## 1. Hechos mecánicos: las siete correcciones, verificadas

Cada fila se comprobó ejecutando el contrato, no leyéndolo.

| corrección | cómo quedó | evidencia |
|---|---|---|
| B1 · fuente de fila | las dos tablas llevan `source_document` (texto, obligatorio) y `source_url` (`url`, opcional) | `sp_identified_package_without_public_url` y `sp_package_content_without_public_url` pasan sin URL; `sp_a_url_is_still_a_url` mantiene el tipo honesto |
| B2 · sección elíptica | token `Elíptica / ovalada` **y** su compuerta | `width_mm`/`thickness_mm` usan `in [Plana / aero, Elíptica / ovalada]` en `allowed_when` **y** en `required_when`; `sp_elliptical_wire_is_not_forced_to_be_flat` escribe 1,8 × 1,2 bajo su propio nombre |
| B3 · ángulo de codo | campo propio, `positive` con `max 180`, sin mínimo | 95° y 100° pasan en dos casos distintos; Straight Pull lo tiene **prohibido** |
| P1 · nominal vs mayor | dos campos separados, ambos con unidad `mm` | un caso escribe nominal 2,0 y mayor 2,3 en la misma ficha |
| P2 · largo de rosca | campo propio con `mm` | el helper prohíbe explícitamente generalizar 9,5 mm a todos los rayos |
| P3 · clase de agujero de maza | declaración de texto | el helper la define como transcripción OEM, no estándar universal |
| P5 · procedencia | el largo y la designación del anclaje ganaron prerrequisito de evidencia | visible en la adopción: `prerequisite:spoke_length_mm` en los 48 |

La compuerta B2 es la parte que suele quedar a medias —añadir el token sin
tocar la condición— y aquí **no** quedó a medias: las dos direcciones de la
compuerta se actualizaron.

Comprobaciones de integridad, todas limpias: **ninguna** de las cinco
definiciones publicadas fue alterada (comparadas campo a campo contra la
preimagen de revisión); los cuatro campos numéricos nuevos llevan su unidad;
las dos columnas de fuente tienen rótulos que las distinguen; y el
`catalogue_sha256` declarado en los casos coincide con el catálogo.

Adopción reproducida sobre el ensayo actual: **48 evaluados, 0 bloqueantes, 19
observaciones legacy** (15 del calibre viejo y 4 del anclaje viejo), **ninguna
observación activa sin proyectar** y 48 con datos pendientes. La auditoría cita
el mismo SHA del catálogo. Los números de Root son exactos.

## 2. Defecto vigente

### D-1. Lo que la fuente citada publica es opcional; lo que no publica es obligatorio

`spoke_thread_standard` (designación OEM, texto libre) es **obligatorio**
siempre que haya rosca. `spoke_thread_nominal_mm` —la cota que la propia página
citada por el paquete imprime por modelo— es **`required: never`**. Lo mismo
para el largo de rosca y el diámetro mayor.

Consecuencia medida: transcribir fielmente la fila OEM que el paquete cita,
con evidencia, anclaje, ángulo, calibre, clase de agujero, secciones, nominal y
largo de rosca completos, **deja igualmente un pendiente** sobre el único campo
de rosca que esa página no imprime.

| sonda (mínima) | resultado |
|---|---|
| fila OEM transcrita entera, sin designación | `required_missing:spoke_thread_standard` |
| la misma fila con la designación añadida | sin observaciones |

No es un bloqueo y no impide publicar. Es una asimetría: el dato disponible es
opcional y el que hay que ir a buscar es el exigido. El arreglo cabe en el
vocabulario existente —dejar la designación en `required: never`, como sus tres
compañeras de rosca, o exigirla sólo cuando el nominal esté ausente— y es
decisión de producto, no de motor. **No afirmo que ninguna otra marca publique
esa designación**: sólo constato qué imprime la página que este paquete cita.

## 3. Limitaciones conocidas, no defectos

1. **El token «Desconocido / sin confirmar» del anclaje sigue siendo idéntico a
   la celda vacía.** Medido: elegirlo y no elegir nada producen exactamente
   `required_missing:spoke_head_interface`. Es conducta del motor compartido
   (`spec_rule_evaluator.dart:5-13`), no del paquete, y Root ya decidió
   conservar la opción. Sólo pido que la readiness no lo cuente como capacidad:
   la ficha sigue sin distinguir «no lo llené» de «el fabricante no lo declara».
2. **`Otro anclaje OEM` es un cajón, y por eso admite el ángulo de codo.** La
   compuerta permite el ángulo para `J-Bend` y `Otro anclaje OEM`, y prohíbe
   para `Straight Pull`. Un anclaje tipo T-Head —que el mismo catálogo OEM
   lista como tercera opción en otras familias— cae en el cajón y podría
   declarar un codo que no tiene. Es permisivo, nunca exigido, así que no puede
   producir un bloqueo falso; discriminarlo pediría un cuarto token, que no
   propongo por dos filas.
3. **Las designaciones siguen siendo texto libre** —rosca, anclaje OEM, clase de
   agujero—, así que dos fichas del mismo rayo escritas distinto no se comparan.
   Es el precio aceptado de no cerrar un dominio por marca, y la readiness lo
   dice.

## 4. Integración pendiente

Los dos casos pendientes del paquete siguen siendo los correctos y ninguno se
presenta como verde: el cruce rayo–maza–niple–llanta necesita modelos y
condiciones documentadas, y la identidad `STD14`/`STD14C` con su anclaje
necesita investigación de producto. El segundo ya recoge que la página leída
nombra J-Bend, que era el punto que faltaba.

## 5. Fuentes abiertas de primera mano en esta ronda

- Sheldon Brown / John Allen, *Wheelbuilding* — `https://www.sheldonbrown.com/wheelbuild.html`
- Park Tool, *Spoke Wrench Selection* — `https://www.parktool.com/en-us/blog/repair-help/spoke-wrench-tool-selection`
- cnSPOKE, catálogo v24, pliego 14 (páginas impresas 26–27), leído en el PDF y
  confirmado con el render de la página.
