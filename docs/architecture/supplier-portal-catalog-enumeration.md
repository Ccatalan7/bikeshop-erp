# Enumerar el catálogo de un proveedor, y decir cuánto se miró

Documento dueño de cómo el ERP descubre candidatos en el portal de un
proveedor. El calce técnico lo sigue gobernando
[`product-identity-matching-contract.md`](product-identity-matching-contract.md);
acá vive lo que ocurre **antes** de calzar.

## La regla

> **El buscador de un proveedor es un índice, no una autoridad.** Sirve para
> encontrar dónde vive una familia; nunca para acotar cuánto existe.

Y su consecuencia operativa:

> **Una afirmación sobre una fila necesita esa fila. Una afirmación sobre el
> conjunto —«no lo tiene», «éstas son las opciones»— necesita el conjunto.**

## Qué salió mal (2026-08-28)

La necesidad era «Cámaras aro 700 para reposición del taller». El ERP preguntó
`camara 700` en el buscador por palabra de RBX y mostró 10 opciones. El dueño
entró a mano por `NEUMATICOS Y CAMARAS` → `CAMARAS RUTA` y encontró **19
productos en 3 páginas**.

No fue un defecto de calce. Fueron cuatro defectos de descubrimiento, y
cualquiera de ellos bastaba:

| Defecto | Efecto |
|---|---|
| El camino genérico fijaba `navigation: []` | Ninguna familia sin configurar podía usar la taxonomía del portal |
| `paginaabsoluta=1` fijo, sin recorrido | El techo real era **una página**, no las 40 filas del tope |
| Se cortaba con `possibleCount > 0` | La consulta ancha (`camara`) nunca llegaba a correr |
| Nada reportaba completitud | `status: completed` con 10 filas se leía como «el portal tiene 10» |

El cuarto es el que hace daño: **un número chico rotulado como parcial es
honesto; un número chico presentado como completo es el defecto**. La ruta
manual del dueño, corrida por el código anterior, habría devuelto 9 de 19 con
la misma cara de completa.

## Cómo funciona ahora

### Tres etapas, tres contratos

| Etapa | Optimiza | Red |
|---|---|---|
| Interpretación (NL → necesidad) | fidelidad al operador | servidor |
| **Descubrimiento** (necesidad → filas) | **recall**, más la cobertura alcanzada | portal |
| Calce (filas → veredicto) | precisión, eliminate-then-rank | ninguna |

Un predicado técnico (`wheel_size = 700c`) **no puede** cambiar qué se mira;
sólo qué califica después. Hay una prueba que lo fija comparando el ranking de
nodos con y sin el predicado.

### La ruta de catálogo es dato

`need_search_adapter.catalog_route` dice cómo pedir «nodo N, página P», y
`taxonomy_discovery` dice dónde leer los selectores nativos. No hay rama por
hostname ni tabla `tube → 13/171` escrita a mano: la taxonomía **se descubre**,
se cachea con TTL y lleva huella para detectar deriva.

Al elegir nodo se enumeran **hasta 3 hermanos plausibles** (`CAMARAS RUTA`,
`CAMARAS MTB`, `CAMARAS BMX`) y el matcher elimina. Elegir uno por corazonada
es cómo desaparece una opción real. El rótulo del **padre desempata pero nunca
califica**: sin esa regla, `NEUMATICOS RUTA` entra a una búsqueda de cámaras
porque cuelga de `NEUMATICOS Y CAMARAS`.

### Cuándo se termina

Se cierra un nodo con **página corta, página vacía, o página sin códigos
nuevos**. Nunca con el enlace «Siguiente»: RBX lo dibuja también en la página 4,
que viene vacía. Los presupuestos (`max_nodes`, `max_pages`, `max_rows`,
reloj de pared) son dato del adaptador.

**Una tabla que existe y no calza no es una página vacía.** Si hay tablas y
ningún encabezado calzó, eso es deriva del parser; leerlo como «el nodo se
acabó» cerraría la enumeración declarando cobertura completa sobre cero filas.

### Cobertura, separada del estado

`status` dice **cómo terminó la corrida**; `coverage` dice **qué alcanzó a
ver**. Fusionarlos fue el defecto original, así que la base los guarda en
columnas distintas y tiene un CHECK: `complete = true` exige
`limit = 'enumerated'`.

| Causa de parcialidad | Filas | Por qué |
|---|---|---|
| Tope propio (`max_pages`, `max_rows`, reloj, `max_nodes`, ciclo, tope de payload) | se usan, con reserva | se vieron y se parsearon bien; no mirar la página 4 no vuelve falsa una coincidencia probada |
| Invariante rota (sesión, deriva, encoding, transporte) | sólo evidencia | no se puede distinguir «el portal mostró menos» de «dejamos de ver», y las **ausencias** dejan de significar nada |

`No lo tiene` sólo aparece con cobertura completa. Sin ella, `No apareció`.

**Omitido por tope y contradicho no son lo mismo, y el encabezado no puede
sumarlos.** Una fila contradicha se miró y se rechazó con evidencia; una
omitida por el tope de guardado no se juzgó nunca. Con 200 enumeradas, 120
guardadas y 100 relevantes, restar `200 − 100` diría «100 contradicen la
ficha» sobre 80 productos que nadie llegó a comparar. El panel dice las dos
cosas por separado:

- descartadas = `filas guardadas − relevantes`;
- omitidas = `rowsUnique − rowsPersisted`, rotuladas «sin evaluar por el tope
  de guardado».

Cuando no hay truncamiento no se inventa ninguna de las dos, y la cobertura
sigue diciendo «completa» si lo es.

### El caché de taxonomía es del servidor, y hay que hacerlo cumplir

`supplier_portal_probes` concede DML completo a `anon` y `authenticated`, y su
política es `for all` acotada sólo por tenant. Medido en producción el
2026-08-28:

| grantee | privilegios |
|---|---|
| `anon` | DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE |
| `authenticated` | DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE |

Es decir: **cualquier usuario del tenant podía escribir el caché por PostgREST
sin pasar por el recibo**, incluida una fecha futura que apagaría el
redescubrimiento para siempre. Un `revoke update` a secas no sirve —el
privilegio de columna no recorta un UPDATE ya concedido a nivel de tabla— y
revocarlo entero cambiaría la postura de una tabla de configuración que este
cambio no vino a tocar.

Se protegen **sólo las dos columnas nuevas**, con un disparador
`security invoker`. Dentro de una función `security definer` el `current_user`
es su dueño, así que el recibo pasa y la escritura directa del rol del API no.
Si el caché no cambia, el disparador ni opina: las ediciones de configuración
de siempre siguen funcionando.

El disparador **no puede ser `security definer`**: su `current_user` pasaría a
ser su propio dueño y se auto-aprobaría siempre. Hay una aserción para eso, en
pgTAP y en el read-back.

**El caché se invalida cuando cambia lo que lo produjo.** Una taxonomía la
leyó un proveedor concreto por una ruta concreta: si cambian `tenant_id`,
`supplier_id`, el origen del portal (`search_url_template`,
`need_search_url_template`) o el `need_search_adapter` que dice dónde leerla y
cómo recorrerla, el disparador la borra en el mismo UPDATE. **Se invalida, no
se bloquea**: cambiar la configuración es legítimo; lo que no puede pasar es
que un caché vigente se herede por otro proveedor o por otra ruta. Una edición
inocua —una nota, el límite de término— no lo toca.

**La hora del descubrimiento es del servidor de punta a punta.** El recibo
ignora el `discoveredAt` que venga y estampa `now()` en la columna y dentro del
jsonb; el cliente lee el TTL de la columna y, si viene nula, trata la taxonomía
como vencida. Creerle al payload es lo que permitiría fechar el caché en el
futuro.

### Una lectura sabe a qué pregunta contestó

**La antigüedad que importa no es la del reloj.** Una lectura de hace dos
minutos contra la ficha anterior es más vieja, para esta pregunta, que una de
ayer contra la ficha vigente. Por eso cada recibo del portal se estampa —del
lado del servidor, en la misma transacción que lo inserta— con:

| Dato | Quién lo pone |
|---|---|
| `need_version_at_search` | el servidor, leyendo la fila |
| `interpretation_revision_no` | el servidor, leyendo la revisión vigente |
| `interpretation_category_id` | ídem |
| `interpretation_technical_family` | ídem — **la categoría sola no es el alcance**: la familia decide qué nodos se enumeran |

La regla de pantalla queda trivial: revisión igual ⇒ vigente; distinta ⇒
`Ficha anterior`, y la lista se rotula «revisadas con la ficha anterior». Un
recibo anterior a este contrato, sin revisiones, **falla cerrado**: no se puede
demostrar que sea vigente.

Y la ausencia gana su segunda condición: `canAssertAbsence` exige cobertura
completa **y** revisión vigente. Recorrer entero el catálogo de la ficha
anterior no autoriza a decir «no lo tiene» sobre la ficha nueva.

Volver a evaluar sí responde la pregunta nueva —las filas crudas son las
mismas, el veredicto es el de la ficha vigente— y no toca la marca de tiempo ni
la cobertura: no se pretende una segunda visita que no ocurrió.

### Topes: cliente y recibo, o ninguno

El tope de filas vive en `need_search_adapter.result_cap` y el RPC valida
**contra ese mismo número**. Subir uno sin el otro produce una enumeración
correcta que muere en el `insert` con `22023`, con el portal ya consultado.

### El CHECK del adaptador dice lo mismo que el cliente

La base aceptaba adaptadores que el cliente descarta. Dos formas del mismo
error:

| Config aceptada por el CHECK viejo | Qué hacía el cliente |
|---|---|
| `{"version":"1"}` (o `{}`) | pasaba por `NULL` en un CHECK, que **pasa** |
| `{"version":"1","families":{}}` | `FormatException` → capacidad apagada **en silencio** |

Un portal «configurado» que no busca nada es peor que uno sin configurar,
porque nadie va a ir a mirar por qué. El CHECK vigente exige un adaptador v1
con **al menos una capacidad realmente declarada**: `families` o `categories`
como objeto **no vacío**, o `generic_family_search` como el booleano `true`
—una cadena `"true"` no cuenta—. Cada término va con `coalesce(..., false)`:
sin eso una clave ausente da `NULL` y el CHECK se vuelve fail-open.

`jsonb_object_length` no existe en PostgreSQL 17.6 —comprobado contra
`pg_proc`—; el equivalente es comparar con `'{}'::jsonb`.

**Lo que un CHECK no puede validar:** que cada familia traiga su
`identity_family` y sus `search_terms`. Recorrer las claves necesita
`jsonb_each`, y una función que devuelve conjuntos no está permitida en un
CHECK. Una familia presente pero mal formada sigue apagando la capacidad del
lado del cliente; cerrarlo requeriría moverlo al disparador.

### Una navegación por proveedor, TODAS por la misma cola

El portal es ASP legacy con estado por sesión y las consultas comparten cookie:
dos recorridos en paralelo se pisan y ninguno se entera. Ninguno falla; los dos
mienten.

Por eso la cola —`SupplierPortalNavigationQueue`— es **una sola para la
consulta exacta por SKU y para la enumeración por necesidad**. Tenerla sólo en
la segunda dejaba abierta exactamente la carrera que pretendía cerrar. Es FIFO
porque cada llamada publica su turno antes de esperar el anterior, y
**reentrante**: si un cuerpo que ya tiene el turno vuelve a pedir el mismo
proveedor, corre en línea. Sin esa guardia, «serializar todo» se convierte en
un abrazo mortal la primera vez que alguien componga dos operaciones.

La cola vive fuera del runner para poder probarse sin navegador, y es
compartida por construcción: el módulo crea un runner nuevo por operación, así
que una cola por instancia no serializaría nada.

## Trampas verificadas del portal de RBX

- `tamanopagina` **se ignora**: el portal sirve 9 pase lo que pase. Declarar 27
  haría que la primera página de 9 se leyera como página corta y cerrara el
  nodo con un tercio del catálogo.
- La ruta es **request-driven**, verificado con control negativo (otra
  clasificación cambió las filas; volver reprodujo las mismas). No depende de
  `Session` stale.
- `Content-Type` **sin charset** sobre IIS 8.5, con bytes Windows-1252. Si el
  navegador adivina UTF-8, `Código`/`Descripción` llegan rotos y **ningún**
  alias de columna calza: página perfectamente dibujada, cero filas leídas.

  **Qué hace el runtime con eso, exactamente:** nada de decodificar. La app
  navega y lee el DOM ya decodificado por el WebView; no vuelve a pedir la
  página ni toca los bytes. Lo único implementado es **detectar** el destrozo
  —`[ÃÂ][-¿]` o `�`, comprobado en la sonda y otra vez
  en Dart sobre el `bodySample`— y **fallar cerrado**: `coverage.limit =
  encoding`, sin filas accionables. No hay refetch con Windows-1252 ni ningún
  otro fallback de codificación.

  Windows-1252 aparece explícitamente **sólo en las pruebas**, donde las
  fixtures se guardan en esos bytes y se decodifican con `latin1` para
  demostrar que leerlas como UTF-8 rompe el parser. No confundir la fixture con
  el runtime.
- El nodo `CAMARAS RUTA` contiene **dos neumáticos mal clasificados** (12010,
  17570). Un nodo mal clasificado del proveedor no reclasifica nada: caen por
  contradicción de familia, aunque su medida (700) sí calce.

### Prueba real del contrato en producción (2026-08-28)

Con la necesidad general **«Cámaras aro 700 para reposición del taller»** —sin
SKU ni producto confirmado— la app descubrió y guardó 13 nodos de taxonomía.
El plan encontró 6 nodos plausibles de cámaras y, por el presupuesto declarado
de `max_nodes = 3`, recorrió 3 nodos en 5 páginas: 35 filas únicas observadas y
35 guardadas. El matcher dejó **17 exactas, 1 por confirmar y 17
contradictorias**. La pantalla mostró por eso 18 opciones relevantes, no 35,
y rotuló explícitamente la cobertura como parcial por `max_nodes`.

Ese resultado fija dos invariantes de UX: «relevante» incluye una fila que aún
necesita confirmación, mientras que el contador «exactos» no; y terminar bien
la corrida no autoriza a presentar cobertura completa cuando quedaron nodos
sin recorrer. La sesión autenticada existente de RBX sobrevivió al recorrido:
descubrir la taxonomía y paginar no exigió volver a iniciar sesión.

## Un tamaño viene pegado a otra medida

El catálogo no escribe `700c`: escribe `CAMARA 700X28/38C V/AUTO 48MM`. Medido
sobre las 19 filas reales del nodo, el matcher observaba **cero** hechos:
enumerar el catálogo completo sólo cambiaba 10 filas «por revisar» por 19.

El tamaño se lee sólo **en contexto dimensional** — `700x28`, `26x1.75`,
`700c`, `29"` —. Un número suelto no es una medida: en esa misma fila el 48 es
el largo de la válvula. Dos tamaños distintos en una fila dejan el campo sin
afirmar. Es convención de la industria, no regla de RBX ni de las cámaras.

Con eso, las 19 filas se reparten en 10 exactas, 7 eliminadas por medida y 2
por familia.

## RBX no puede recuperar su sesión sola, y eso es correcto (2026-08-30)

`portal.rburgos.cl` publica su ingreso por **HTTPS** pero su formulario legacy
**envía por HTTP**. El preflight de
`20260829020000_supplier_portal_session_recovery` se niega —por contrato— a
revelar o mandar el secreto en claro, así que
`recoverSupplierPortalSession` devuelve `interactionRequired` **siempre** para
este portal. No es un «todavía no»: es un «acá no puede ser sin una persona».

El costo de no distinguirlo: el runner sólo miraba `result.submitted`, seguía
enumerando y terminaba intentando guardar un recibo vacío. Con el gateway
degradado eso costó **125 s de spinner** —medido el 2026-08-30— para acabar en
sesión vencida igual. Ahora `interactionRequired` corta la corrida al instante,
no se escribe recibo, y la superficie dice la verdad: «RBX necesita que inicies
sesión en su portal. Te abro su ingreso.»

**La frase importa.** «No se pudo recuperar automáticamente» sugiere un
reintento que nunca va a funcionar en este portal.

## Un 504 que nunca llega a la base (2026-08-30)

Con el proyecto reiniciado y el pool limpio —`0 active`, PostgREST avanzando de
179 a 185 llamadas en 13 s— un POST de **1,8 kB** al recibo tardó **125.236 ms**
en morir con `504 upstream request timeout`, y
`pg_stat_statements` registró **cero** llamadas a esa función. O sea la
sentencia nunca llegó a Postgres.

Antes del reinicio el cuadro era distinto y peor: PostgREST con 21 conexiones y
**el contador congelado en 272.838** —no completaba nada—, y el error real
detrás de cada `504` era `PGRST003: Timed out acquiring connection from
connection pool`.

Dos aprendizajes que costaron rondas:

- **El clasificador de errores buscaba `timeout` y el mensaje dice `Timed
  out`.** Nunca coincidía, así que el reintento jamás corría: por fuera se veía
  como «el segundo intento también falla».
- **Un reintento `unawaited` sin identidad se apila.** Cada fallo lanzaba otra
  cadena; ocho búsquedas dejaron ocho cadenas pidiendo conexiones a la vez y
  fueron ellas las que llenaron el pool. Hoy hay **una sola por
  necesidad+proveedor**: una corrida nueva reemplaza a la pendiente, el cierre
  borra sólo el `operationKey` que terminó, y si quedó otro se traspasa.

## Qué sigue faltando

- **La sonda JS no tiene prueba automatizada de DOM**: no hay jsdom en el
  repositorio y no se agregó una dependencia para esto. El parser se prueba
  hoy sólo por el camino Dart y por el smoke real.
- **Las fixtures se derivaron de los hechos reportados por la captura, no son
  la captura**. Ver `test/fixtures/supplier_portal/README.md`. Una fixture
  escrita por quien escribe el parser prueba consistencia interna, no realidad.
- **`anon` conserva DELETE / INSERT / UPDATE / TRUNCATE sobre
  `supplier_portal_probes`** y sobre el resto del esquema por un `grant`
  general anterior. Este cambio sólo blindó las dos columnas que estrenó; la
  postura de permisos de la tabla —y que un rol anónimo pueda truncarla— es un
  hallazgo aparte, más ancho que esta tarea, y necesita una decisión del dueño.
- **El CHECK no valida la forma interna de cada familia** (`identity_family`,
  `search_terms`): recorrer claves necesita `jsonb_each` y un CHECK no admite
  funciones que devuelven conjuntos. Una familia presente pero mal formada
  sigue apagando la capacidad en el cliente sin que la base lo note. Cerrarlo
  significa promover esa validación al disparador.
- El disparador **bloquea también a `service_role`** para las dos columnas del
  caché: no es miembro del dueño de la tabla. Ningún consumidor lo usa contra
  esta tabla y el error nombra el recibo, pero es una decisión, no un
  accidente.

## Cómo se prueba lo que no se puede probar con datos vivos

`supabase/tests/supplier_catalog_enumeration_coverage.sql` **siembra su propio
tenant, usuario, proveedor, portal y necesidad**, y después se pone el rol
`authenticated` para intentar la escritura forjada. Antes afirmaba sobre la
fila real de RBX: en local, con cero filas en la tabla, no probaba nada.

La afirmación sobre la fila sembrada vive en
`supabase/manual_checks/verify_supplier_catalog_enumeration_coverage.sql`, que
es donde esa pregunta tiene sentido — y ese archivo **falla antes del apply**
(cada aserción divide por cero cuando no se cumple), porque un read-back que
sale con código 0 contra una base sin migrar no es un read-back.
