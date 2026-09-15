# Frenos originales: revisión de Codex en curso

Siete plantillas candidatas, no publicadas. Claude entregó 80 pruebas Dart y
26 mutantes; ese resultado no cierra la validez mecánica ni la adopción.
Codex tomó ownership de los cuatro archivos y añadió el callback obligatorio
`compile_existing_brakes_root.py`. La entrega anterior y sus hashes se
conservan en `existing-brakes-readiness-2026-09-07.md`.

## Fuentes verificadas de nuevo

- [Park, rotores](https://www.parktool.com/en-us/blog/repair-help/disc-brake-rotor-removal-installation)
  está disponible. Distingue interfaz rotor/maza y la herramienta de lockring,
  y remite al fabricante para límites de desgaste. Los ejemplos históricos
  de marca no se convierten en límites universales de modelos actuales.
- [Park, pastillas](https://www.parktool.com/en-int/blog/repair-help/disc-brake-pad-removal-installation)
  está disponible. Exige el límite del fabricante y reconoce el interior
  hidráulico del TRP High Road aunque su entrada sea un cable. No se infieren
  dimensiones de sus fotos. Adivinar tres slugs que dieron 404 no demostraba
  que faltaba esta fuente: se encontró por búsqueda y se abrió.
- [Sheldon, frenos de disco](https://www.sheldonbrown.com/disc-brakes.html):
  separa desgaste/medición actual de especificación del rotor, y advierte que
  límites de rotor y pastilla corresponden a sus fabricantes. Su ejemplo de
  medición con calibre requiere compensar la concavidad; no se convierte en
  prohibición absoluta de esa herramienta.
- [TRP, documentos técnicos](https://trpcycling.com/pages/technical-documents)
  enlaza el [manual HY/RD–HY/RD FM](https://cdn.shopify.com/s/files/1/0840/7783/8623/files/HR2.0-HYRD.HYRD-FM-160602_1.pdf?v=1706909403).
  La prosa de la página 2 sí prescribe aceite mineral TRP/Tektro. La página de
  venta no lo mostraba; eso no permitía afirmar que TRP no lo publicaba. El
  [boletín 071713 HYRD Rev B](https://cdn.shopify.com/s/files/1/0840/7783/8623/files/TRP-HYRD-Technical-Bulletin-English-Rev-B.pdf?v=1706908535)
  identifica la conversión en el cáliper y sus condiciones de funcionamiento.
  Se conserva el alcance de esos documentos; no se atribuyen todas sus
  compatibilidades a cualquier revisión o presentación de la marca.
- [SRAM DB-DB8-A1](https://www.sram.com/en/sram/models/db-db8-a1) prescribe
  Maxima Mineral Oil. Esto contradice cualquier atajo SRAM=DOT y demuestra
  por qué una clase mineral sola tampoco identifica el producto aprobado.

## Correcciones implementadas en el callback

Una URL o un apartado no identifica un circuito físico, puerto o extremo.
Se eliminan de esas claves. Las recetas de montaje reciben identificador de
configuración: un mismo diámetro puede tener montajes diferentes, pero un
montaje no recibe dos respuestas cambiando su fuente. Las aprobaciones de
fluido distinguen modelo/edición y producto; dos productos explícitamente
aprobados son dos relaciones, no una duplicación del sistema. Falta de producto
mineral específico queda pendiente.

Un selector condicional se exige sólo cuando es aplicable. La etiqueta literal
de un compuesto puede registrarse antes de conocer su clase; no se obliga a
inventar esa clasificación para conservar evidencia del fabricante. Una
restricción explícita de pastillas tampoco se deduce del metal de la pista.

Se retiran dos definiciones nuevas que nunca se publicaron: espesor medido de
una pieza usada y su método. El propietario es la inspección física; el contrato
canónico ya distingue ese estado de la especificación de todas las unidades del
SKU. Las dos fixtures correspondientes permanecen íntegras en
`out_of_catalog_inspection_cases`, fuera de los casos de catálogo, y no se las
cuenta como cobertura de las fichas. El nominal y límite OEM siguen separados;
el campo ambiguo ya publicado continúa como legacy. Esta corrección no cambia
ninguna inspección de taller ni crea una herramienta nueva de medición.

El candidato actual contiene 7 plantillas, 58 definiciones, 126 usos y 84
casos de catálogo; 91 comprobaciones Dart verdes. Las dos fixtures de inspección
retiradas no se incluyen en ese total. Evidencia
`.tmp/product-spec-catalog/existing-brakes-root-tests.log`.

## Cierre local de posición, inclusión y preimagen — 2026-09-08

Las configuraciones declaran por separado si incluyen maneta, cáliper,
manguera, rotor y adaptador. Las propiedades de cada pieza requieren su propia
inclusión; la delantera no habilita datos traseros. Pistones, forma/retención de
pastilla y alcance de maneta pasan del escalar del conjunto a su miembro.
[MAGURA MT Trail Sport](https://magura.com/product/mt-trail-sport/) declara
cuatro pistones delante y dos detrás: el caso conserva esa diferencia sin
atribuir otros detalles a una posición por deducción. Un cáliper suelto no
puede declarar que el puerto de purga pertenece a una maneta.

`tool_size_mm` se retira de la ficha activa del rotor, con su lectura legacy
intacta. Park atribuye la herramienta al tornillo/lockring y a su interfaz;
«Centerlock + T25» sin fijación identificada no es un ejemplo de compatibilidad
válida. Los casos anteriores se renombran y se conservan como pruebas de
retención legacy, con su ID previo, sin convertir el texto en una especificación
del rotor. Esto no resuelve aún las fijaciones de los otros conjuntos.

La captura de producción de 2026-09-08T07:33:37.747133+00:00 detectó cuatro
definiciones compartidas que el preimage original, anterior a mando combinado,
no conocía. El publicador rechazó correctamente cambiar
`brake_fluid_approvals`. Se conserva esa definición íntegra y el bloque usa una
nueva, `brake_model_fluid_approvals`, para el alcance estricto de modelo/edición.
La entrada compartida está fijada en
`existing-brakes-shared-live-input-2026-09-08.json`; no se vuelve a tratar su
`origin: new` histórico como permiso para cambiarla.

`compile_existing_brakes_publication.py` prepara 28 definiciones nuevas,
30 compartidas intactas y 69 patches de metadata. La actualización local,
repetición exacta y los 84 casos SQL pasan con rollback. El orden de los dos
errores de rango y el código de duplicado de puerto se cotejan explícitamente;
no se desactivó una restricción para igualar resultados. Evidencia:
`.tmp/db/existing-brakes-candidate-run.log` y
`.tmp/db/existing-brakes-forward-candidate/forward-replay-and-cases.log`.

Huellas del catálogo `a3c9c6c17151a3433ff8792718e827f6376ebda64b04ce760f56754179171ee4`,
casos `391091f349b05ab2ff9cade412ddd9c6caead047b776aced722a0baef5449d7e`,
preimagen `f92157c1e80df72711eb0c9e971e913407cd28b127ae452905961c621abdf52a`.
La captura cuenta 124 productos efectivos en estas siete plantillas. Se
capturaron sus 124 preimágenes autenticadas, sin errores ni escrituras, y se
ensayaron contra el catálogo exacto anterior: cero conflictos bloqueantes,
cero observaciones activas sin proyección y 21 observaciones legacy retenidas.
Los 124 productos tienen datos pendientes: ese resultado no prueba que sus
fichas estén completas ni que se haya certificado un montaje. Se usaron
preimágenes individuales, no una transacción global. Evidencia privada:
`.tmp/product-spec-catalog/existing-brakes-snapshots-20260908/manifest-20260908T082227344027Z.json`
y `.tmp/product-spec-catalog/existing-brakes-adoption-20260908.json`.

## Revisión todavía abierta

Faltan adjudicar las ramas restantes: duplicación de contenido entre
`kit_members` y configuración; identidad de modelo repetida entre configuración
y conexión; fluido por circuito; purga de conjuntos y su miembro concreto;
fijaciones de otros conjuntos. La medida de una pieza usada ya fue retirada
del candidato de catálogo.
La mera existencia de un enlace de fila no demuestra su tipo o inclusión.
No se declara terminado el bloque por corregir sus tres primeros defectos.
También faltan revisión independiente, actualización del ensayo de adopción si
cambia el candidato, runtime y distribución del
cliente antes de activar originales. Ningún producto fue llenado.
