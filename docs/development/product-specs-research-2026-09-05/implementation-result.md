# Fichas técnicas: base implementada — 2026-09-06

**Siguiente bloque:** aplicar los requisitos revisados a los 48 campos de filas y cerrar los contratos mecánicos pendientes. [2200, condiciones por fila](row-condition-integration-2026-09-07.md), está aplicado/verificado; catálogo local de 105 plantillas/681 definiciones/84 casos, sin publicación ni llenado.

**Continuidad actual (2026-09-07):** este documento describe la
primera entrega. Las migraciones posteriores hasta `20260907022000` están
aplicadas y verificadas; el catálogo ampliado sigue en ensayo local y el
llenado está en **0 productos**. El estado autoritativo del trabajo global,
backup y pendientes está en
[global-audit-and-sanitation-2026-09-06.md](global-audit-and-sanitation-2026-09-06.md).
Las 37 plantillas activas no equivalen a todas las familias saneadas; tampoco
las 105 propuestas compiladas equivalen a cobertura mecánica aprobada.
El [lector numérico exacto](exact-numeric-transport-checkpoint-2026-09-07.md)
ya tiene prueba de base, sesión autenticada y entrada real en la app; los
addenda ND de Claude siguen en revisión e integración.

La ficha ahora parte de la identidad y distingue datos manuales, propiedades de
una referencia exacta y declaraciones documentadas. Los requisitos gobiernan la
captura; una contradicción explícita bloquea el guardado completo, mientras que
la información faltante sigue siendo pendiente. Se adoptó la simplificación de
Claude y se corrigieron sus cinco hallazgos de implementación. Ver
[plan](implementation-plan.md) y [revisión/resoluciones](claude-implementation-review.md).

## Alcance entregado

- Base común para las **37 plantillas activas / 36 familias**: roles, etiquetas,
  requisitos tipados de tres estados, reglas revisables, fuente y versión. Las
  reglas históricas de opciones son orientativas hasta su revisión; los tipos,
  vocabularios, visibilidad explícita y referencias se validan en servidor.
- Identidad marca/modelo/MPN y catálogo de ediciones inmutables. El selector
  ofrece referencias de la marca y modelo confirmados. Datos derivados y claims
  se leen con fuente; elegir una variante no sustituye el modelo.
- Borradores conservados al cambiar requisitos, referencia o actualizar datos.
  Cargas por categoría/usuario tienen generación; una respuesta vieja o fallida
  no vacía la ficha. Las tres respuestas booleanas son Sin dato / Sí / No.
- `save_product_with_specs_v1` guarda identidad y hechos en una transacción;
  incluye la ruta de juegos, revisión de plantilla/producto, control de timestamp
  y recibo idempotente. Inventario físico mantiene su comando propio. El RPC
  legado y escritores directos quedan sujetos a invariantes diferidas por tenant.
- `spec_facts` y valores normalizados siguen siendo la autoridad. Hechos sin
  cambio conservan procedencia y lecturas al guardar datos comerciales.
- Taller consume el contexto común con claims delimitados. Se retiró para
  cadenas la inferencia ancho→velocidades; conteos coincidentes solos no producen
  aprobación de montaje. Una eGlide conserva cautela LINKGLIDE si falta plataforma
  de la bici. Un producto sin plantilla no recibe un conflicto inventado.
- La proyección pública respeta publicación, retira campos heredados y fuente
  privada, conserva hechos incompletos conocidos y omite los campos con conflicto
  bloqueante. No se modificaron observaciones de bicicletas instaladas.

## Cobertura mecánica concreta

| Edición cargada | Datos y alcance respaldados |
|---|---|
| KMC X8 EU Silver/Grey, BX08NG114 | 114 eslabones, 6/7/8, 3/32, pasador 7,3 mm, MissingLink incluido; todos los sistemas 6/7/8 según [la ficha europea](https://www.kmcchain.eu/products/x8-silver-grey). No se mezclan presentaciones US/EU. |
| KMC eGlide US Silver, CN11245 | 126 eslabones, 9/10/11, 11/128, pasador 5,4 mm; sólo LINKGLIDE según [KMC](https://kmcchain.us/products/eglide). Conector no confirmado. |
| KMC X11 US Nickel/Black, CN11665 | 118 eslabones, 11, 11/128, Shimano/SRAM/Campagnolo según [KMC](https://kmcchain.us/products/x11). Ancho sobre pasador y conector no inventados. |

Fuentes base exigidas por el dueño:
[Park Tool, Chain Compatibility](https://www.parktool.com/en-us/blog/repair-help/chain-compatibility)
y [Sheldon Brown, Speeds](https://www.sheldonbrown.com/speeds.html); investigación
por familia en la [base K01–K30](../../architecture/bicycle-compatibility-knowledge.md).
Las fixtures reproducibles están en [reference-fixtures.json](reference-fixtures.json).

El producto abierto resultó ser **HV408** en su nombre, con el modelo estructurado
vacío. No se encontró documentación OEM exacta suficiente en esta ronda. Se
confirmó HV408 sólo en el borrador de prueba, sin vincularle X8 ni guardarlo. El
caso manual 6/7/8 + 11/128 + 7,1 pide verificar modelo/envase; no es una prueba de
imposibilidad física. Elegir la referencia X8 hace explícitos los conflictos con
3/32 y 7,3. Esto demuestra el contrato de referencia, no que HV408 sea X8.

## Verificación

| Evidencia | Resultado y límite |
|---|---|
| Dart/Flutter de ficha, reglas, compatibilidad, booleanos y retorno | **56 pasan**; [log](evidence/flutter-tests.log). Booleanos: 390/768/1280 × claro/oscuro, sin convertir null en false. |
| Integraciones heredadas de persistencia y juegos | **8 pasan**; [log](evidence/existing-integration-tests.log). |
| PostgreSQL local | **95 pasan**, 55 del contrato y 40 del agregado de juegos; [log](evidence/database-tests.log). Tipos/UUID, tenant, referencias, revisiones, rollback completo, idempotencia, publicación incompleta y conservación de fuentes. Fixtures dentro de transacciones revertidas. |
| `fvm dart analyze lib test` | Sin errores; avisos existentes fuera de los archivos cambiados. Análisis de archivos propios repetido después de los últimos ajustes, sin errores ni warnings. No se afirma que el repositorio completo esté libre de lints. |
| Sesión real | `screen payroll`, PID 90499, conservada con hot reload. Editor existente a 1821×912, 834×922 y 390×812. La ventana volvió a 1821×944. |
| Flujo real | Actualizar conserva HV408 y selecciones 6/7/8, 11/128, 7,1. Seleccionar X8 deriva datos con fuente sin borrar conflictos manuales. Cambiar modelo deja visible la referencia incompatible. Retirarla elimina sólo sus datos automáticos; las elecciones manuales siguen. |

Frames revisados: [escritorio manual](evidence/manual-desktop.png),
[referencia en conflicto](evidence/reference-conflict-desktop.png),
[tablet](evidence/manual-tablet.png),
[identidad compacta](evidence/manual-compact-identity.png) y
[booleanos compactos](evidence/manual-compact-booleans.png).
El frame de conflicto usa X8 temporalmente en el borrador para probar el vínculo;
se restauraron HV408, MPN vacío y ninguna referencia al terminar. **No se pulsó
Guardar ni se ajustó stock.** Los controles de requisitos se tocaron por identidad.

## Estado productivo

Migración **`20260906070000_product_spec_contract.sql` aplicada** y registrada;
verificación UTC **2026-09-06T06:59:30Z**. [Recibo](evidence/migration.receipt).
SHA-256 de migración:
`007450b4bcd89b36b1afc6cc55b000c99a6c42c1828537abd8500929e1ae5d4d`.
[Read-back](readback.sql), SHA-256:
`2e0983a7a3b790347952e7b581ac06f2469b3e1bb4f03d26f52994484f81616b`.
Los hashes se verificaron después de los últimos cambios de cliente; la migración
aplicada no se editó después del despliegue.

El read-back verificó definiciones de funciones, ACL, referencias, versiones,
guardas diferidas y registro. La lectura posterior devuelve 37 plantillas,
36 familias, tres referencias y **cero comandos nuevos de guardado de producto**
([conteos](evidence/production-counts.json)). No hubo backfill de fichas existentes.
Las restricciones del servidor ya alcanzan a clientes instalados; el nuevo
editor está en el código local y la sesión debug, no en una release distribuida.

Checkout compartido `smartpegas1.0`, HEAD base
`71926a11cb47edec16dd798e8e92048d301c1630`. Se preservaron cambios ajenos de OCR,
temas y documentación. No hubo commit, push ni publicación de binarios.

## Límites y siguiente cobertura

1. La base transversal está entregada; **no está completo el catálogo mecánico
   de todas las familias**. Las dependencias nuevas específicas se concentran
   en cadenas/conectores. La [matriz](../../architecture/product-spec-family-matrix.md)
   delimita la investigación y reglas necesarias para las demás; no se sembró
   una lista de prohibiciones sin manuales exactos.
2. Faltan fuentes exactas para HV408 y para los modelos de otras familias. Las
   categorías sin plantilla no se asignaron por analogía. Los claims de catálogo
   son inmutables y revisables en datos; no se agregó un editor administrativo de
   referencias/reglas ni una biblioteca completa de adaptadores y montajes.
3. Las pruebas visuales de la ficha completa fueron en macOS a tres anchos, en
   tema claro. Claro/oscuro de los booleanos está cubierto por widgets. No se
   probó iOS Simulator, teclado móvil ni cada entrada embebida de compras/ventas.
   Los owners y contratos compartidos están registrados, sin afirmar esos clics.
4. No se ensayó un guardado de producto contra producción. La integridad de
   escritura se probó localmente y las definiciones/ACL se verificaron en la
   producción real. Cambios en identidades productivas pueden revelar conflictos
   anteriores y exigir revisión explícita; no hay corrección masiva automática.
5. El trigger diferido todavía evalúa por fila modificada. Conserva integridad,
   pero falta medir el costo de agregados grandes y optimizar sin abrir bypasses.

## Aprendizaje de la sesión preservada

La primera recarga dejó objetos anteriores sin campos de constructor nuevos y
sin listeners añadidos a `initState`. La primera actualización perdió selecciones
de prueba **no guardadas**; los datos persistidos quedaron intactos. Se corrigieron
lecturas compatibles, hidratación de metadatos, captura del borrador anterior y
reconexión idempotente de listeners. Las pruebas posteriores de refresco y de
vincular/retirar referencia conservaron las respuestas manuales. La causa y el
costo están en [AGENT_MACOS_APP_CONTROL.md](../AGENT_MACOS_APP_CONTROL.md).
