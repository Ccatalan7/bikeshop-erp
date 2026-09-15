# Hidráulica: adjudicación de root antes de publicar

Sucesor de la propuesta inicial de Claude. Cambios reproducibles en
`compile_hydraulic_parts_root.py`, invocado obligatoriamente por el compilador
base. Tres plantillas, 24 definiciones, 31 usos y 37 casos; paquete preparado
con 16 definiciones nuevas, siete opciones, ocho compartidas preservadas.
No aplicado todavía. Ninguna asignación ni llenado autorizado por este paquete.

## Correcciones del ámbito

1. Largo suministrado y necesidad de corte independientes. Una manguera de
   2.000 mm puede requerir corte; se retira la fixture que prohibía eso. El
   interior no puede exceder el exterior, y cero no es cantidad desconocida.
2. Cada tramo tiene identidad/modelo. Se retiran los escalares de largo,
   diámetros, código de sistema, contenido genérico y conexiones paralelas.
   Su definición compartida permanece intacta; sólo el uso pasa a legacy.
3. Dos acoples de cáliper pueden venir en extremos A y B de una manguera.
   El rol maneta/cáliper no identifica el extremo físico. Unicidad por tramo,
   extremo físico y configuración; las alternativas de montaje siguen separadas.
   No se transforma un tramo suministrado en dos mangueras ya instaladas.
4. Diámetro y paso son cifras con unidades independientes. Se elimina el texto
   imperial que admitía esconder otro paso. Designación literal y dimensiones
   estructuradas son caminos exclusivos. Se registra adaptador y objetivo por
   extremo/configuración; preinstalado no significa adaptador final incluido.
5. Cada pieza de un kit conserva código, tipo, cantidad e interfaces propias.
   Sus aplicaciones enlazan la pieza por ID y conservan modelo/edición de
   manguera y destino. La clave distingue esas ediciones. No se hereda una
   medida o compatibilidad del kit entero. Una oliva no lleva largo de inserto.
6. Cada envase físico tiene una formulación. Marca y designación OEM son
   identidad para DOT y mineral por igual. Un envase no puede tener dos
   formulaciones; dos envases separados sí pueden contener líquidos distintos.
   Eso jamás autoriza mezclarlos. Volumen y cantidad también son por envase.
7. Grado DOT y base declarada se comprueban en la misma fila: DOT 5 mantiene
   base silicona; DOT 3/4/5.1 la clasificación no silicona. Mineral no puede
   declarar grado DOT. No se intenta identificar un líquido por color.
8. Se retira la afirmación «mineral no tiene norma». Las otras normas se
   conservan con su alcance, edición y enlace al líquido, sin convertir un
   método de ensayo en homologación. El grado DOT tiene una única celda dueña.
9. Las declaraciones por modelo de freno enlazan el envase concreto, con
   generación, circuito y apartado de fuente. No existe aprobación automática
   por marca. Una lista de adaptadores de una herramienta de purga no certifica
   la compatibilidad de ninguna botella.
10. `fluid_type` vivo tiene sólo Aceite Mineral, DOT 4 y DOT 5.1. El congelado
    proponía además DOT 5 y desconocido. El publicador rechazó esa diferencia;
    root conserva el dominio vivo. DOT 5 se describe en la nueva fila propia,
    sin modificar los otros consumidores del escalar compartido.

## Fuentes y límites exactos

- [Park BKM-1.2](https://www.parktool.com/en-us/product/hydraulic-brake-bleed-kit-mineral-bkm-1-2)
  y [BKD-1.2](https://www.parktool.com/en-us/product/hydraulic-brake-bleed-kit-dot-bkd-1-2),
  páginas abiertas: ámbitos mineral y DOT separados; no incluyen líquido.
  DB8 figura en el primero, SRAM en el segundo. La lista no es una tabla de
  aprobación de fluidos y no entra como tal en las fixtures.
- [SRAM DOT 5](https://support.sram.com/hc/en-us/articles/5927424375451-Can-I-use-DOT-5-in-my-SRAM-DOT-brakes),
  página abierta: exclusión de DOT 5 con silicona, dentro del contexto
  **frenos SRAM DOT**. No se extiende a todo SRAM ni a sus sistemas minerales.
- [FMVSS 116, eCFR](https://www.ecfr.gov/current/title-49/subtitle-B/chapter-V/part-571/subpart-B/section-571.116),
  texto del editor federal abierto, actualizado al 3 de septiembre de 2026:
  S5.1.14 y S5.2.2.1 distinguen las denominaciones con/sin base silicona.
  Sólo se usa la clasificación del líquido; no se imponen requisitos de
  vehículos motorizados a la bicicleta ni se certifica conformidad normativa.
- [ISO 9128:1987](https://www.iso.org/standard/16724.html), resumen oficial
  abierto de una edición histórica retirada: cita fluidos de base petróleo
  bajo ISO 7308. Prueba que la prohibición universal de normas minerales era
  injustificada; no prueba conformidad de una botella ni vigencia de aquella
  edición. El ejemplo ISO 7308 es de representación, no producto rellenado.
- [Jagwire, catálogo 2021](https://jagwire.com/files/general/2021_Jagwire_AM_Catalog_LowRes.pdf),
  texto OEM indexado de p.24: dos acoples de cáliper preinstalados, corte y
  adaptadores Quick-Fit separados. El PDF y las fichas actuales devolvieron
  error al abrirlos en esta ronda. Por eso la fixture conserva sólo ese texto,
  sin largo de catálogo ni asignación al SKU actual. Los 2.000 mm del arnés
  son sintéticos; no son un llenado de Sport ni Pro.
- [Shimano DM-MBBR001-04](https://si.shimano.com/en/pdfs/dm/MBBR001/DM-MBBR001-04-ENG.pdf),
  texto OEM abierto: exige inserto adecuado a la manguera; cortar y cambiar
  instalación tiene condiciones propias. La captura web no devolvió imagen y
  la descarga local dio 403. No se trasladan sus cifras tabulares a productos
  ni fixtures OEM: el 11,2 de la prueba de oliva es sintético.

## Verificación y alcance pendiente

El primer pase detectó seis fixtures que usaban JSON null para una celda
pendiente: null es una celda tipada inválida. Se corrigió el arnés para omitir
esas celdas, sin debilitar el parser. La ronda intermedia pasó 39 Dart; tras
agregar el caso de ediciones y preservar `fluid_type`, comprobar el log final
`.tmp/product-spec-catalog/hydraulic-parts-dart.log` y el publicador SQL en
`.tmp/db/hydraulic-parts-publication-tests.log` antes de aplicar.

Pendiente no es rechazado: faltantes requeridos siguen no bloqueantes. Las
claves compuestas sólo detectan conflicto cuando su identidad está resuelta;
no comparan alias ni reemplazan adjudicación documental. Los enlaces mantienen
el ámbito pero no verifican por sí solos que el fabricante apruebe ese modelo.
El motor no deduce de estos claims compatibilidad de un circuito real. El
consumidor y el aplicador de llenado deben resolver envase/pieza y modelo/edición
antes de usar una declaración; esta puerta global permanece abierta y el fill
sigue en cero. Tampoco hay prueba del renderizado de estas nuevas plantillas.

| Artefacto vigente | SHA-256 |
|---|---|
| Compilador base | `a666cd2a8565e795b38ac12eb22f3000cb8a0b1cfb76eac8c46bceeff73daa85` |
| Adjudicador root | `e355283ec74160dc613d981b2b64d200e36e81d169429262528bcf5537db9c6a` |
| Catálogo | `b0aa3e638341c4b07e3af245c3052a365aac06e033fff8ff60e00c4584d24115` |
| Casos | `e4cba4f02d1f9a5c66fed244d302e0e32c1c31970c78c0e0b5cc295d07b5cf7e` |
| Preimagen | `1670b9ef688a8c90879c1241e9390101ee632d3ab466b384a213ac8a8e080a3f` |
| Paquete | `d96fba1014f0322647d4a0741469e6aa4ef9ab9b62207ecb3e28c447d1b1c814` |
| Migración | `b268af0ad1dbc4f76bf3053b42e4e5dbcfa245c09833f980722de41c17eddd83` |
| Verificador | `5314b821aabd74dbe753621ce7d36ac9aeb47e70c7d46ab2a54e1b5dad922cd1` |


## Adjudicación final HY-A/HY-B — 7 de septiembre, 19:35 LA

HY-A encontró una ambigüedad real entre designación y normas cumplidas, pero su
caso DOT5.1 + cumplimiento DOT4 **no es una contradicción mecánica universal**.
La [ficha Motul, edición 01/22](https://azupim01.motul.com/media/motulData/DO/base/DOT_5.1_en_FR_motul_27400_20220113.pdf)
publica conjuntamente FMVSS116 DOT3/DOT4/DOT5.1 e ISO4925 clases 3/4/5.1 para
MOTUL DOT5.1. El texto OEM se abrió; no se toman cifras de su tabla de propiedades.
También se abrió la [ficha comercial 27400](https://www.motul.com/en-GB/products/27400),
que remite a esos usos. No se atribuye esa edición a una botella del inventario.

La fila del envase ahora separa **designación DOT comercial** de cuatro
cumplimientos declarados, tipados como booleanos sin valores por defecto.
DOT3/4/5.1 pueden coexistir para una base no silicona si lo publica el fabricante;
no se deducen del nombre. El cumplimiento DOT5 con silicona contradice esa base
y bloquea. Los otros estándares usan vocabulario propio (ISO/SAE/OEM/referencia
sin clasificar), con edición y alcance. El grado DOT ya no se introduce en la
celda de norma secundaria. Una referencia documental sin clasificar conserva
texto, sin interpretarlo como clasificación ni homologación.

HY-B: las ediciones de manguera/destino y del freno son ahora **requeridas**.
Cuando faltan hay incompletitud visible, aunque no bloqueo de guardado. No se
inventa una edición ni se sustituye por cero. Si una fuente no distingue año,
su alcance documental debe constar explícitamente; no es una regla para rellenar
campos vacíos. La unicidad sigue requiriendo la clave resuelta y no compara alias.

Sucesor final: **42 casos**, 24 definiciones, 31 usos. Cinco nuevos casos cubren
cumplimiento múltiple real, mezcla de bases incompatible, celda secundaria DOT
rechazada, otra norma documental conservada y edición ausente visible.
La revisión anterior corresponde a 37 casos y queda superada por esta adenda.

| Artefacto final | SHA-256 |
|---|---|
| Compilador base | `a666cd2a8565e795b38ac12eb22f3000cb8a0b1cfb76eac8c46bceeff73daa85` |
| Adjudicador root | `1f6f90d142caaeac28d8278a82b9399f4535785e625e9d8640ba9b748aa0fa3b` |
| Catálogo | `db035cb385f7d39a1f815c8331195c0939b251b846753fab7a6cb1b33e16a6d6` |
| Casos | `1e49f0a889a59cbfc119c3e6654c1e7e6b8abbb32731bc2a469aff4892c4a9e1` |
| Preimagen | `1670b9ef688a8c90879c1241e9390101ee632d3ab466b384a213ac8a8e080a3f` |
| Paquete | `9c6303e982e8dc008696b50dfd8c8b0cd0c995ddb4b7b2eeba3a3284c1f10092` |
| Migración | `6047e3f67fe812aad70bb1447b68b80db0bbe1909ec9cc77b8b4de553601e3f1` |
| Verificador | `08eea544afba0349997cf870284eba10af4e02c1663777227de9538f91bbb86e` |
