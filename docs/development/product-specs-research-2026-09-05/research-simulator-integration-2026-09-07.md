# Simulación autenticada del llenado

2300 aplicada y verificada en producción a las `2026-09-07T12:41:44Z`.
No existe un comando
de aplicación en este paquete y no se escribió ningún producto. Las puertas de
saneamiento global y publicación del catálogo ampliado siguen cerradas.

`get_product_spec_research_snapshot_v1` reúne la identidad guardada, el editor
exacto v2, todos los hechos del producto —también huérfanos y con alcance—,
IDs y posiciones de opciones, fuentes/lecturas y biblioteca de referencias en
una sola instantánea MVCC. El actor y tenant vienen de la sesión real. Las
cantidades escalares se transportan como texto decimal; el JSON original de
auditoría se conserva como `value_json_text` para no perder números históricos.

El SHA del estado combina producto, editor completo y huellas de producto,
observaciones, plantilla y referencias. Las huellas de hechos incluyen sus
definiciones, opciones y lecturas, incluso cuando ya no están en la plantilla.
La huella de producto cubre también comerciales y stock, sin exponer esos
campos como objetivos de la propuesta. Las huellas detectan cambios; no son
firmas del fabricante ni permisos de aplicación.

`preview_product_spec_research_v1` vuelve a comprobar esa preimagen y evalúa el
candidato con el validador canónico del servidor. La identidad sólo permite
marca, modelo, MPN y GTIN. Los hechos deben pertenecer por ID a la plantilla
activa; los campos retirados no se convierten en objetivos del llenado. Los
tipos se comprueban antes del evaluador de requisitos: `unknown` no es un
número, un objeto no es texto y `false` no es cero. Una referencia se valida
por IDs antes de convertirla a etiquetas y sus datos derivados pasan el mismo
control de tipos. Ni un borrador válido ni una respuesta del simulador aprueban
compatibilidad mecánica.

Una propuesta de filas es un **upsert por ID estable**. Conserva filas, celdas y
fuentes omitidas; añade filas nuevas y une fuentes sin borrar las anteriores.
La tabla resultante completa pasa el esquema y las condiciones del servidor.
Si cambiar una celda deja otra incompatible, ambas quedan visibles y la
simulación lo informa. No se utiliza el nombre de una fila como identidad.
Un borrado o una corrección que retire evidencia requiere un comando de
saneamiento distinto, con revisión explícita; no es un relleno.

## Propuesta v2 y preparación

`catalog-fill-proposal-v2.schema.json` conserva v1 sin modificar. V2 incorpora
tenant y preimagen autenticada, huellas por observación, números exactos y
configuraciones por fila. `current.value` conserva el antes completo;
`proposed` contiene el cambio escalar/lista o el delta de filas por ID. La
revisión independiente se liga al SHA-256 de JSON UTF-8 con claves ordenadas,
separadores compactos y sin el miembro `review`. Convertir una propuesta v1
exige una revisión nueva, aunque el valor investigado no cambie.

`scripts/inventory/simulate_product_spec_research.py` valida el esquema, IDs
únicos, referencias a evidencia, archivos y hashes, unidades y preimágenes.
Rechaza JSON con miembros duplicados y números no finitos. Una propuesta de
referencia debe enumerar todos sus efectos y no enviarlos como observaciones
manuales. Un nombre leído necesita su recibo canónico; una observación de
investigación sigue pendiente del writer de procedencia correspondiente.

Se usa `jsonschema[format-nongpl]==4.26.0` en el entorno aislado de `uv`, con
`Draft202012Validator` y comprobador de formatos explícito, según la
[documentación del validador](https://python-jsonschema.readthedocs.io/en/stable/validate/).
El transporte conserva su allowlist de lecturas: no tiene writer, SQL, refresh
de sesión ni un flag `--apply`. Guarda recibos locales con modo 0600 y creación
exclusiva, para no reemplazar una simulación previa. La simulación autenticada
incluye la instantánea anterior completa disponible por este lector.

```bash
uv run --script scripts/inventory/simulate_product_spec_research.py --proposal PROPUESTA_V2.json --snapshot INSTANTANEA.json --output PREFLIGHT_NUEVO.json
uv run --script scripts/inventory/simulate_product_spec_research.py --proposal PROPUESTA_V2.json --output SIMULACION_NUEVA.json
```

La primera forma sólo comprueba preparación local. La segunda usa la sesión
real del Debug, verifica el actor y llama únicamente a los dos RPC de lectura.
Una revisión declarada en JSON se informa como consistente con su hash; no
sustituye la revisión independiente efectivamente recibida ni abre las puertas
globales. El aplicador futuro necesita su propia frontera autenticada,
procedencia de investigación, recibos/idempotencia, revisión bajo lock y
comparación completa posterior. El guardado agregado existente reemplaza
hechos omitidos: **no se le debe enviar este delta como ficha completa**.

## Defectos reproducidos durante la revisión

RS1 permitió tipos inválidos que el validador de borradores trataba como
desconocidos. RS2 proyectaba campos ajenos/retirados de una referencia por clave.
RS3 no invalidaba la huella al cambiar la opción de un hecho huérfano. Los tres
tienen correcciones y probes antes/después; no eran escrituras de producción.
Se corrigió además la sustitución de tablas completas para conservar los datos
omitidos durante un fill.

RS4 es preexistente: una referencia global corrupta podía proyectar la etiqueta
de una opción privada mediante el getter v2, aunque SELECT autenticado no
permitía leerla. El nuevo snapshot heredaba ese defecto. El forward endurece
ambos lectores v1/v2 mediante una comprobación común de IDs globales y opciones
del mismo endpoint antes de proyectar etiquetas. V1 conserva su formato
numérico anterior. La revisión independiente cerró las reproducciones con
71/71 aserciones, incluido merge con dependiente ahora no aplicable. Dictamen
`product-spec-research-snapshot-independent-review-2026-09-07.md`, SHA
`59cc97476152720b25d18af871b8b78e024ae37c18a9610b1d305607bc80a02b`.

## Validación y estado aplicado

- SQL 2300 SHA `132e10acbbdba0ce66d4ecec27a486b3f22004855f32ac899f1adab26f9960a0`.
- Verificador SHA `2c81e62965ae8e3600c92d1b55c28f20aefcd143bb2dce6a712643e8ba83c11b`.
- Guardia de preimagen rechaza cambios no revisados de cuerpo, propietario,
  ACL, volatilidad o search path en los seis nombres. Reaplicación local pasa.
- 73 pruebas Python (26 del simulador), 36 SQL propias y 71 independientes.
  La suite SQL completa después de congelar pasa 874 pruebas en 19 archivos.
- Receipt `.tmp/db/migration-receipts/20260907023000.receipt`: APPLIED,
  verificación e historial registrados. Preservación de observaciones,
  lecturas, opciones, plantillas, asignaciones e identidad coincide con legacy.
- Sesión auténtica del Debug: 38 productos por snapshot, incluidos huérfanos
  y sin plantilla; 35 familias por ambos getters v1/v2; cero errores.
  Artefacto `authenticated-research-snapshot-verification.json` en `.tmp/product-spec-catalog`.

Primera propuesta v2:
`catalog-fill-first-proposal-cl573r-v2.json`, hash canónico sin review
`52707bedc888650c53a19fcf702c0afe5a48a50fedb3a860c674bcf40a43ea0c`.
La evidencia del nombre guardado se archivó desde el snapshot autenticado y
mantiene alcance nominal. La fuente OEM conserva su archivo y fecha original.
Simulación auténtica: cero issues, los seis hechos derivados coinciden y
`model=CL573R` es sólo propuesto. `valid_draft=true`,
`mechanical_approval=false`, `apply_authorized=false`, `writes=0`.
Artefacto `cl573r-authenticated-research-simulation-v2-archived.json`.

Los tres pendientes reales son nueva revisión independiente de esta propuesta,
saneamiento global y aplicador autenticado de sólo ficha. Este despliegue no
los cambia ni modifica un producto.
