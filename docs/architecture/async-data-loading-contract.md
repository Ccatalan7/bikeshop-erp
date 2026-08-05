# Contrato de cargas asíncronas, caché y reconciliación

**Estado:** contrato arquitectónico transversal  
**Vigente desde:** 2026-08-04  
**Primer consumidor acotado comprobado:** Gestión de Trabajos (`/taller/pegas`)

## 1. Problema que resuelve

Una lista real puede necesitar datos por varias razones legítimas al mismo
tiempo: montaje inicial, precarga posterior al login, retorno desde un editor,
refresh manual, reanudación de la app, cambio de filtros, notificación de un
servicio o reconciliación realtime. La concurrencia en sí no es el defecto.

El defecto aparece cuando esas cargas no tienen un propietario que decida:

- qué identidad de usuario y tenant autoriza el resultado;
- qué consulta o conjunto de filtros representa;
- cuál carga vigente puede publicar datos, apagar el spinner o mostrar error;
- qué eventos se aplican como deltas quirúrgicos y cuáles exigen una lectura
  completa;
- qué resultado quedó obsoleto porque otra intención lo reemplazó.

Sin ese contrato, una respuesta antigua puede llegar última y sobrescribir una
tabla más nueva, una cancelación interna puede aparecer como banner de error y
varios triggers pueden repetir la misma consulta sin aportar frescura.

## 2. Vocabulario canónico

- **Read model:** proyección que consume una superficie: lista, mapa de filas,
  resumen, calendario o detalle compuesto.
- **Load owner:** único coordinador que decide qué carga puede publicar en ese
  read model. Puede vivir en la página, provider o servicio, pero no en los
  tres simultáneamente.
- **Authority scope:** identidad mínima que autoriza datos, normalmente
  `userId + tenantId`, más la generación de autenticación vigente.
- **Request key:** identidad semántica de la consulta: autoridad, filtros,
  orden, paginación, inclusión de eliminados y cualquier modo que cambie el
  resultado.
- **Generation/ticket:** número monotónico capturado antes del primer `await`.
  Una intención posterior invalida los tickets anteriores.
- **Carga completa:** lectura que recompone el read model desde sus fuentes.
- **Actualización quirúrgica:** inserción, reemplazo o eliminación puntual a
  partir de un evento autoritativo, sin volver a consultar toda la colección.
- **Resultado obsoleto:** éxito o error de una generación, authority scope o
  request key que ya no posee la pantalla.

## 3. Contrato no negociable

1. **Un read model tiene un solo load owner.** Los triggers solicitan trabajo al
   owner; no escriben la lista, el spinner o el error por caminos paralelos.
2. **Cada carga captura autoridad, request key y ticket antes del primer
   `await`.** La validación sólo al iniciar no basta: se vuelve a verificar
   antes de publicar.
3. **La última intención elegible gana.** Sólo el ticket vigente puede reemplazar
   datos, publicar vacío, apagar su loading state o mostrar un error.
4. **Éxito y error obsoletos son silenciosos.** No pintan datos, no vacían la
   pantalla, no apagan el spinner de una carga nueva y no muestran snackbars.
5. **Un cambio de authority scope es cancelación, no error operativo.**
   `AuthorityScopeChangedException` protege el aislamiento entre usuarios y
   tenants. Debe cortar la publicación y terminar el loading que todavía le
   pertenezca; nunca debe convertirse en banner rojo ni relajarse mediante un
   retry con autoridad dudosa.
6. **Los fallos genuinos del ticket vigente siguen visibles.** Timeout, error de
   red, contrato inválido o fallo de backend no se clasifican como cancelación
   para esconderlos.
7. **`dispose` invalida todo ticket vivo.** Una respuesta que llega después de
   cerrar la superficie ya no posee estado.
8. **La caché acelera el primer frame; no concede autoridad.** Sólo puede
   mostrarse si pertenece al mismo scope y request key y conserva la frescura
   exigida por la superficie. Una lectura fresca puede reconciliarla en segundo
   plano.
9. **Cache y realtime pueden coexistir.** Realtime actualiza la proyección/cache
   autoritativa mediante deltas. No se reemplaza automáticamente por un refetch
   completo, ni se declara que todo dato realtime sea incompatible con caché.
10. **Las mutaciones locales y realtime preservan actualizaciones quirúrgicas.**
    Insertar, modificar o eliminar una fila conocida debe fusionar esa fila y
    mantener selección, filtros, scroll y edición. La carga completa es el
    fallback cuando falta contexto o el evento no permite reconciliar con
    seguridad.
11. **Coalescer no es lo mismo que decidir ownership.** Un servicio puede
    compartir el mismo `Future` para requests con igual authority scope y
    request key. La superficie igualmente necesita ticket para impedir que una
    intención posterior sea sobrescrita.
12. **No usar polling de `_isLoading` como control general de concurrencia.** Un
    bucle de `Future.delayed(50ms)` espera, pero no identifica quién puede
    publicar, no distingue filtros, no cancela resultados obsoletos y puede
    transferir errores entre intenciones distintas.
13. **`forceRefresh` también tiene key y owner.** No puede saltarse el contrato
    ni compartir ciegamente un request con una consulta de otra forma.
14. **No se crea una abstracción global a partir de un único caso.** Primero se
    prueban dos o tres consumidores con las mismas invariantes; después se
    extrae el coordinador compartido más pequeño que represente evidencia real.
15. **`dispose` no notifica sincrónicamente a un provider ancestro.** Flutter
    finaliza el árbol con los elementos bloqueados; llamar `notifyListeners()`
    desde el `dispose` de un descendiente puede corromper el frame completo con
    `widget tree was locked` y luego `_dependents.isEmpty`. La limpieza visible
    se publica después del frame y lleva identidad del owner, de modo que una
    superficie que sale tampoco pueda borrar el contexto que una superficie
    nueva publicó antes del callback. La regresión mínima desmonta el publisher
    real bajo el provider y prueba tanto ausencia de excepción como protección
    contra un clear obsoleto.

## 4. Flujo de referencia

```text
Trigger
  -> Load owner captura authority + request key + ticket
  -> puede pintar cache elegible
  -> inicia o comparte la lectura exacta
  -> valida authority + key + ticket después de cada frontera async
  -> sólo el owner vigente publica datos/loading/error
  -> realtime y mutaciones siguen fusionando deltas quirúrgicos
```

La forma mínima en una superficie stateful es:

```dart
final ticket = coordinator.start(authority: authority, key: requestKey);

try {
  final value = await repository.load(requestKey);
  if (!ticket.isCurrent || !mounted) return;
  setState(() {
    model = value;
    loading = false;
  });
} on AuthorityScopeChangedException {
  if (!ticket.isCurrent || !mounted) return;
  setState(() => loading = false);
} catch (error) {
  if (!ticket.isCurrent || !mounted) return;
  setState(() => loading = false);
  surfaceCurrentError(error);
}
```

Este ejemplo expresa ownership, no obliga a copiar una clase local. Si el
servicio ya usa `AuthorityScopedLoad<T>`, su lease protege la caché del servicio
y el ticket de la superficie protege qué intención visible puede adoptar el
resultado. Son fronteras complementarias.

## 5. Matriz de triggers obligatoria

Cada read model debe inventariar, como mínimo:

| Trigger | ¿Carga completa? | ¿Puede compartir request? | ¿Conserva UI? |
|---|---:|---:|---:|
| Primer montaje sin caché | Sí | Sólo misma key/scope | N/A |
| Primer montaje con caché fresca | Background o no | Sólo misma key/scope | Sí |
| Refresh explícito | Sí | No, salvo refresh idéntico deliberado | Sí |
| Cambio de filtros/página | Sí o derivación local | Sólo key idéntica | Sí |
| Retorno de create/edit | Sólo si el comando no devolvió delta suficiente | Key exacta | Sí |
| Realtime insert/update/delete | No por defecto; delta quirúrgico | N/A | Sí |
| `notifyListeners` del servicio | Repintar caché; full load sólo sin proyección | N/A | Sí |
| Cambio de usuario/tenant | Invalidar y recargar con scope nuevo | Nunca cruza scope | No mezcla datos |
| Resume/reconnect | Reconciliación según frescura | Key exacta | Sí |

Dos triggers pueden coincidir sin ser dos bugs. Lo que se audita es si ambos
terminan ejecutando la misma lectura innecesaria y, sobre todo, si ambos creen
ser dueños del mismo estado.

## 6. Implementación comprobada: Gestión de Trabajos

El incidente observado mostraba `Error: ERP authority scope changed during
load` después de actualizaciones/refrescos. La causa no era Supabase Realtime ni
el guardarraíl de autoridad. `PegasTablePage` tenía varios triggers de carga
completa, ningún owner entre ellos y un `catch (e)` genérico que presentaba una
cancelación interna como error del operador.

El cierre acotado vive en:

- `lib/modules/bikeshop/services/workshop_jobs_load_coordinator.dart`
- `lib/modules/bikeshop/pages/pegas_table_page.dart`
- `test/unit/workshop_jobs_load_coordinator_test.dart`

Comportamiento vigente:

- cada `_loadData` obtiene un ticket monotónico;
- sólo la carga más reciente puede reemplazar tabla, loading o error;
- éxito y error de una carga anterior se descartan;
- `AuthorityScopeChangedException` del ticket actual termina su spinner sin
  banner ni rethrow;
- un error real del ticket actual conserva el contrato de superficie/rethrow;
- `dispose` invalida respuestas pendientes;
- la caché fresca sigue dando primer frame instantáneo;
- `_onBikeshopServiceChanged` conserva la ruta quirúrgica
  `_refreshFromCache` y sólo cae a `_loadData` cuando no existe cache;
- `_surgicalUpdateJob` y `_surgicalRemoveJob` siguen siendo dueños de los
  deltas realtime; no se sustituyeron por recargas completas.

Esto protege el flujo multiusuario: un cambio de trabajos hecho desde otro
cliente llega por el canal tenant-scoped, actualiza la fila/cache y repinta la
tabla sin reiniciar toda la colección. Las proyecciones derivadas que no tienen
evento suficiente todavía pueden requerir una reconciliación acotada; eso debe
documentarse por consumidor, no ocultarse bajo un reload universal.

El cierre actual prueba ownership entre cargas completas y conserva el camino
realtime que ya existía. No pretende certificar por sí solo toda la futura
adopción app-wide. En particular, cualquier cambio posterior que mezcle un
snapshot completo con deltas realtime simultáneos debe añadir la regresión de
interleaving del apartado 9 antes de ampliar o extraer el coordinador.

## 7. Antipatrones que una revisión debe rechazar

- dos `initState`/listener/post-frame callbacks que llaman la misma carga sin
  owner;
- `_isLoading` usado a la vez como indicador visual y mutex;
- esperar con polling hasta que otro request termine y adoptar cualquier cache;
- un `catch (e)` que muestra toda excepción, incluidas cancelaciones tipadas;
- `notifyListeners -> fetch completo` cuando el servicio ya fusionó el delta;
- limpiar la lista antes de cada refresh y degradar trabajo continuo;
- cache global sin `userId + tenantId + request key`;
- un retry que vuelve a ejecutar con tenant o filtros recalculados a mitad de la
  misma operación;
- una respuesta vieja que puede apagar el spinner de la respuesta nueva;
- refetch completo después de cada update “por seguridad”, destruyendo las
  actualizaciones quirúrgicas y aumentando latencia/carga.

## 8. Ruta incremental para toda la aplicación

La adopción es un refinamiento gradual, no un refactor global de una vez.

### Fase A — Inventario y riesgo

Para cada lista/read model, registrar:

- owner actual y todos sus triggers;
- authority scope y request key reales;
- cache, TTL, preload e invalidaciones;
- canales realtime y calidad de sus payloads;
- mutaciones locales y deltas disponibles;
- spinner, vacío y error owners;
- consultas duplicadas observadas y costo aproximado;
- riesgo de negocio: dinero/stock, frecuencia y exposición multiusuario.

Priorizar primero superficies de alta frecuencia y colaboración: Inventario,
Ventas/POS, Compras/Recepción, Clientes/CRM, RR.HH. y demás mesas operativas. La
prioridad concreta se decide con evidencia, no por orden de carpetas.

### Fase B — Corrección por consumidor

1. Centralizar los triggers detrás de un owner local.
2. Definir authority scope y request key completas.
3. Añadir ticket/latest-eligible-wins y manejo tipado de cancelaciones.
4. Preservar cache-first y deltas realtime existentes.
5. Eliminar sólo las cargas duplicadas demostradas.
6. Añadir pruebas adversariales y smoke real antes de migrar el siguiente.

### Fase C — Extracción compartida

Después de dos o tres consumidores verdes, comparar invariantes y extraer sólo
lo común: ticket/generation, clasificación de cancelación, ownership de
loading/error y, si aplica, coalescing por key. Las reglas de merge, filtros y
dominio permanecen en sus owners específicos.

### Fase D — Observabilidad y presupuesto

Agregar telemetría de desarrollo o métricas de bajo ruido para:

- requests iniciados, compartidos, superseded y publicados;
- latencia cache-first versus reconciliada;
- número de full fetches por navegación/refresh;
- errores genuinos versus cancelaciones de autoridad;
- eventos realtime aplicados quirúrgicamente versus fallback completo.

La optimización se considera efectiva cuando reduce lecturas y latencia sin
perder frescura, aislamiento, errores reales ni actualizaciones multiusuario.

## 9. Regresiones mínimas por consumidor

1. Respuesta A empieza, B empieza, A termina última: sólo B publica.
2. A falla después de B: A no muestra error ni cambia loading.
3. B falla de verdad: B sí muestra el error previsto.
4. Cambia authority scope durante la lectura: no se filtran datos y no aparece
   el texto interno como banner.
5. La superficie se dispone con request vivo: no hay escritura posterior.
6. Dos requests con igual key pueden coalescer; keys distintas no se mezclan.
7. `forceRefresh` no adopta por accidente una respuesta cacheada anterior.
8. Realtime update/insert/delete modifica sólo las filas correspondientes y
   conserva filtros, selección y scroll.
9. Realtime durante una carga completa se reconcilia determinísticamente; el
   resultado final no revierte el delta más nuevo.
10. Cache elegible da primer frame; cache de otro scope/key nunca aparece.
11. Sólo el ticket vigente apaga el spinner.
12. Un refresh repetido no duplica banners ni deja la tabla vacía.

## 10. Relación con el refinamiento de módulos

Toda ronda regulada por
`docs/architecture/APP_REFINEMENT_MASTER_PLAN.md` debe auditar el read model
además de sus mutaciones. El mapa mínimo es:

```text
Trigger -> Load owner -> Authority/request key -> Read -> Commit -> Reconcile
```

El objetivo no es introducir coordinadores por reflejo. Es demostrar que cada
superficie posee una sola verdad visible, conserva el trabajo del usuario y se
mantiene fresca frente a otros clientes sin carreras ni lecturas redundantes.
