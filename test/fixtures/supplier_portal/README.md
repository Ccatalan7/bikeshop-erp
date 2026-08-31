# Fixtures del catálogo de un portal de proveedor

`rbx_camaras_ruta_pageN.html` reproduce la **forma** de una enumeración por
taxonomía en RBX (`Clasificacion2=171`, `CAMARAS RUTA`): el encabezado verbatim
capturado, el precio impreso por un `<script>` dentro de la propia celda, el
paginador que sigue dibujando «Siguiente» en una página vacía, y el reparto
9 / 9 / 1 / 0 con 19 códigos únicos.

**Los bytes son Windows-1252, a propósito y sin declarar `charset`** — es la
condición real del portal (IIS 8.5, `Content-Type` sin charset). Leer estos
archivos como UTF-8 produce mojibake y ningún alias de columna calza; ése es
justamente el defecto que hay que poder detectar.

## Qué son y qué no son

Estos archivos se **derivaron de los hechos reportados por la captura
autenticada** (encabezado, tamaño de página, conteos, los dos neumáticos mal
clasificados 12010 y 17570). **No son la captura misma**, y por eso no prueban
que el parser lea el HTML real de RBX: una fixture escrita por quien escribe el
parser sólo prueba consistencia interna.

Sustituir por el HTML real sanitizado —sin cookies, sin usuario, sin nombre de
cuenta— en cuanto esté disponible, conservando la codificación original.
