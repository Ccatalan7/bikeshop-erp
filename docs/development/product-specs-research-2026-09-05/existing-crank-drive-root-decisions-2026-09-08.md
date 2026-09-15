# Bielas y platos: adjudicación local de las tres originales

`compile_existing_crank_drive_root.py` conserva la propuesta de Claude como
entrada y corrige las fugas de dueño en brazos y platos vendidos como juego.
**No activado ni llenado.** 56 definiciones, 70 usos, 36 definiciones nuevas y
29 cambios de metadatos. Las 20 definiciones publicadas conservan identidad,
tipo, unidad, dominio y reglas; el retiro sólo cambia el uso a legacy.

## Decisiones

- Una interfaz de eje y una compatibilidad pertenecen al brazo indicado del
  par. El enlace resuelve un miembro real; un miembro ajeno bloquea. El par
  sólo admite dos brazos, y no hereda una interfaz global.
- El selector publicado de eje no tiene término para ciertos brazos de motor.
  Se conserva en legacy y su sucesor exige sistema dueño, geometría, designación
  exacta y fuente. «Motor central» no implica cuadradillo o estriado. Una
  geometría estriada no admite un estándar de cuadradillo; la ausencia del
  estándar documentado queda pendiente, no se deduce de la marca.
- Cada plato de un juego es dueño de sus desplazamientos, emparejados OEM y
  declaraciones. Se impide atribuir una cota o montaje global al juego. Cada
  fila de contenido admite designación del montaje y cadena documentada.
- La construcción admite semiejes solidarios con unión central. La cantidad de
  piezas no se usa como prohibición mecánica universal. Las fuentes de la
  propuesta —[Park Tool](https://www.parktool.com/en-us/blog/repair-help/how-to-remove-and-install-a-crank),
  [Sheldon](https://www.sheldonbrown.com/bbtaper.html),
  [Shimano C-449](https://productinfo.shimano.com/en/compatibility/C-449) y
  [FC-M8000](https://dassets.shimano.com/content/dam/global/cg1SHICCycling/final/ev/ev/EV-FC-M8000-3849B.pdf)—
  siguen vinculadas a su lectura concreta. La tabla C-449 se guarda por
  combinación de pedalier, eje y línea; no se universaliza una longitud de eje.

## Ejecución previa al cierre H1–H5 (8 de septiembre)

57 pruebas Dart: tres plantillas y 54 casos. Los 54 casos SQL pasaron con
avance, repetición exacta y rollback, comparando metadatos completos y
preservación de productos. Dos alias SQL (`field_constraint`) se fijaron tras
observar el resultado, sin modificar dueño ni gravedad. El caso heredado de
estándar de cuadradillo se convirtió en prueba de preservación legacy y se
añadió la prohibición equivalente en la nueva fila de interfaz.

Captura autenticada de 50 productos, sin errores ni escrituras: 27 volantes,
siete brazos y 16 platos. Adopción con el catálogo adjudicado: cero bloqueantes,
cero observaciones activas fuera de proyección y los 50 pendientes de datos.
No certifica montajes ni demuestra aplicación en producción.

Catálogo `453a58522b67e30fe747e5233947f4c29da9dcf9a3a58a257086d2e152975b02`;
casos `2901d85577509376d482e1476ba809f20644bcaa6d1dc39779168dd7be26a728`;
preimagen `2b23e1fe107fe30790e2a12b0b8f96dac23302541e43b353fc2c6bc6adcd942d`.
Publicador: `compile_existing_crank_drive_publication.py`.

Evidencia privada: `.tmp/db/existing-crank-drive-candidate/forward-replay-and-cases.log`,
`.tmp/product-spec-catalog/existing-crank-drive-root-tests.log`,
`existing-crank-drive-adoption-20260908.json` y manifiesto
`existing-crank-drive-snapshots-20260908/manifest-20260908T192801482593Z.json`.

## Handoff histórico anterior al mensaje 192

Claude recibió la revisión independiente en el mensaje 189 del chat
«Diagnóstico fichas técnicas Viñabike»; Code, Opus 5, repositorio correcto,
sin subagentes/workflows. Root conserva SQL/publicador/adopción. El catálogo
queda congelado mientras se revisa; sólo cambiaron alias SQL y la pendencia
obsoleta del selector de eje en los casos. Hay que adjudicar su respuesta,
integrar las referencias OEM con identidad exacta, comprobar el editor y
distribuir el cliente antes de activar. El perfil tipado por miembro de kit
sigue pendiente en el bloque de cadenas; estos brazos/platos no lo sustituyen.

### Revisión recibida y propiedad actual — 19:42 UTC

Claude entregó H1–H5 en el mensaje190 y reprodujo57Dart/20definiciones
inmutables. Detectó required_when desalineado con aplicabilidad, largo opcional
en brazos del par, falta de construcción del sistema por brazo, plataformas
globales aún activas y vocabularios de interfaz de eje distintos entre brazo
y volante. No se consideran cerrados. En el mensaje191 se le transfirió
**propiedad exclusiva temporal** de `compile_existing_crank_drive_root.py`
y sus dos salidas adjudicadas para implementar los cinco cierres. No tocar esos
archivos mientras corre. SQL/publicadores y documentos globales siguen con Root.
El catálogo integrado es un checkpoint congelado anterior a ese delta.

## Integración vigente — 14 de septiembre

Claude cerró H1–H5 y devolvió los archivos en el mensaje 192, visible al retomar
el chat. Root inspeccionó el compilador y reensambló las 37 familias con el
delta. Las 20 definiciones publicadas conservan su cuerpo exacto; las uniones
nuevas comparten una definición neutra entre volante y brazo, más la variante
por miembro. El largo es obligatorio en cada brazo del par, la construcción
se declara por brazo, los selectores globales quedan legacy y el montaje de
plato se exige únicamente donde aplica.

Los 69 casos de este paquete pasaron dentro de las **599 pruebas Dart y 562
casos SQL integrados**. SQL ejecutó avance, repetición exacta y rollback con
preservación de datos. La revisión de Claude había ejecutado además diez
mutantes acotados; ese ensayo sigue siendo evidencia de su revisión, no una
corrida nueva de Root.

Catálogo `b477332c223b3d667a0a2542701fca8697802d5bee5c98f703e05588448b5458`;
casos `f5dbf16cd23ccab9283b8f42778b4a2ded82ed4752e60c091e94216a376f8da4`;
preimagen productiva renovada
`e74791e3bd5809d37902b5b920b4c03d67c0df53e2b24275fee1b8728e325afe`.
El publicador vuelve a exigir estos hashes y continúa fuera de migraciones
desplegables. Propiedad de compilador, salidas, publicador e integración: Root.
La adopción renovada usa 51 capturas autenticadas actuales: 28 volantes, siete
brazos y 16 platos, sin bloqueantes, sin observaciones activas fuera de
proyección y todos pendientes de datos. Se ejecutó dentro del ensayo conjunto
de 868 productos de las 37 familias. Sigue pendiente
cerrar relaciones OEM, editor/consumidores y distribución antes de activar.
