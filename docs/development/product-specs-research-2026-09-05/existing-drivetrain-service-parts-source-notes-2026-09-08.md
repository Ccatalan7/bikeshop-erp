# Patillas, roldanas y guías: entrada de revisión, no candidato terminado

Preimagen de sólo lectura a `2026-09-08T10:18:08.850472Z`, SHA-256
`84cbb1c31d076cd27faa29663243f209f85a784abede0abcb4b656f21607cb3c`.
Son tres plantillas, diez definiciones publicadas alcanzadas por la consulta y
33 asignaciones efectivas: 23 patillas, siete roldanas y tres guías. Los modelos
estructurados de esos registros están vacíos, pero varios títulos contienen
códigos identificables: no se declara que la identidad sea irrecuperable.
Los registros individuales están en
`.tmp/product-spec-catalog/remaining-original-product-scope-20260908.json`,
bajo `scope.products`, con clave `technical_family`, no `template_key`.

La base congelada es `all-family-port-cardinality-integrated-2026-09-07.json`
y sus casos, sin modificarlos. Esta entrada no autoriza asignaciones, llenado,
escrituras de productos ni publicación de plantillas.

## Diferencias de dominio que debe resolver el candidato

**Patilla.** El código del producto, la unión al cuadro y la unión al cambio
son propiedades distintas. [SRAM, UDH y Full Mount](https://www.sram.com/en/learn/understanding-udh-and-full-mount)
distingue el cuadro que acepta UDH de la patilla instalada: el cambio Full
Mount reemplaza esa patilla. Un selector que mezcla UDH y la rosca del cambio
no puede expresar ambos extremos correctamente. La tabla de cuadros también
debe aceptar una declaración de interfaz/estándar documentado cuando la fuente
no enumera modelos; no se inventa un nombre de cuadro para satisfacer una celda.

[Wheels Mfg #25](https://wheelsmfg.com/products/derailleur-hanger-25) y
[#70](https://wheelsmfg.com/products/derailleur-hanger-70) usan un perno M8 pero
mantienen códigos y listas de compatibilidad diferentes. El perno no sustituye
la identidad ni el calce de la patilla. El selector del fabricante pide
marca/modelo/variante/año; algunas declaraciones publicadas omiten el año y eso
no autoriza inventarlo. La base propone un segundo código de modelo dentro de
la ficha: revisar su relación con el dueño canónico de identidad, conservando
las observaciones ya publicadas.

Entre las 23 asignaciones a patilla hay tres títulos de extensores. Deben
contrastarse con la cola de asignaciones existente y la evidencia del producto
para proponer `derailleur_hanger_extender`; no son tres reasignaciones ya
ejecutadas ni tres identificaciones mecánicas concluidas.

**Roldana.** La base combina «Par» con un único número de dientes y un único
apoyo. Las ocurrencias físicas necesitan identidad propia, posición declarada,
dimensiones y fuente. No convertir «par» en una guía y una tensión por inferencia:
puede haber dos piezas iguales o repuestos. El dominio de apoyo mezcla material
cerámico y construcción; la «familia de ancho» mezcla velocidades y perfil
narrow-wide. Separarlos sin inventar una correspondencia universal por velocidades.

[Park Tool](https://www.parktool.com/en-us/blog/repair-help/how-a-rear-derailleur-works)
distingue función de guía y tensión. El manual
[Shimano DM-RARD011-00](https://si.shimano.com/en/pdfs/dm/RARD011/DM-RARD011-00-ENG.pdf)
corresponde a **RD-R7100** (portada) y su página 23 indica respetar las flechas
de giro al sustituir ambas roldanas. No se extrapola una orientación, par o
perfil de dientes a todas las roldanas ni al inventario genérico.

**Guía.** La línea de cadena instalada, el recorrido de ajuste y las opciones
de montaje no son la misma medida. [OneUp Bash Guide ISCG05 V2](https://www.oneupcomponents.com/products/bashguide-v2-iscg05)
declara 7,5 mm de ajuste; eso no significa línea de cadena de 7,5 mm. Incluye
piezas de protección distintas; las
[instrucciones V2](https://eu.oneupcomponents.com/blogs/bashguides-chainguides/bashguard-chainguide-install-instructions)
separan 28–30T, 32–34T y 36T y señalan cuál viene instalada. La capacidad
28–36T no convierte todas las placas en intercambiables para cualquier plato.
El montaje ISCG05 tampoco certifica todo cuadro que tenga esos anclajes: la
ficha contiene exclusiones por modelo/generación y configuración.

Los títulos de las tres guías sugieren variantes de montaje, abrazadera y
bashguard. Investigar qué contiene cada SKU antes de convertir una lista de
opciones de una publicación comercial en configuraciones de la misma pieza.
Conservar documentos/envase y URL tipada opcional; distinguir componentes
incluidos, configuraciones de montaje y declaraciones de compatibilidad.
