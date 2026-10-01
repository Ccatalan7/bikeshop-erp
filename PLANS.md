# Plan de cierre del Master Schema

Actualizado: 2026-09-30. Estado: **ABIERTO**.

## Resultado que quiere el dueño

El empleado atiende una bicicleta, guarda su diagnóstico, encarga el trabajo,
usa servicios y repuestos que calzan, adjunta archivos y termina el trabajo.
La ficha y el historial reflejan lo ejecutado sin volver a pedir datos conocidos.
El cliente recibe información clara. Los respaldos permiten recuperar datos y
los archivos privados conservan su dueño y sus vínculos. La matriz de
compatibilidad y su backbone conservan sus siete criterios de cierre.

**Última instrucción del dueño, 2026-09-30:** mantener el plan completo y
terminar lo ya empezado, incluidos C2/C3. Su reclamo por la ampliación y la
demora pedía una explicación; Codex lo interpretó mal como cancelación.
Se revoca esa detención. La corrección vigente es integrar resultados y cerrar
el trabajo, sin cadenas de auditorías/prototipos que lo dejen a medias.

`BIKE_WORKSHOP_MASTER_SCHEMA.md` conserva el contrato de arquitectura y la
evidencia detallada. Este plan controla su ejecución: se lee al comenzar cada
ronda, al retomar después de una interrupción y antes de asignar trabajo a Claude.
Un nuevo heartbeat no revoca la última corrección directa del dueño.

## Entregables y condición de cierre

| ID | Entregable | Termina cuando | Estado actual |
| --- | --- | --- | --- |
| C1 | Recorrido usable del taller | Guardar, encargar, corregir un cierre bloqueado, subir/abrir/retirar archivos y finalizar funcionan en los consumidores canónicos, con evidencia real de escritorio y teléfono, claro/oscuro. | Recorridos completos web105836 y Android095345 aceptados, readbacks/retirada=1, 30/32 frames. Visor oscuro y guardar móvil corregidos. Cliente local; entrega depende de C5. |
| C2 | Recuperación completa | Un motor integrado recupera el alcance del taller, conserva las relaciones y aísla efectos de stock, contabilidad y mensajes; las negativas explican qué impide recuperar. | Backend completo APPLIED/verificado: captura71 tablas, graph24/24, merge10/10, task_graph18/18 y carreras busy. App real18/18 filas; recuperación trabajo/recibo2/2 y foto privada con original404. Cliente pareado local, publicación en C5. |
| C3 | Privacidad de archivos heredados | Los archivos tienen dueño y recibo de copia, y sus vínculos siguen abriendo desde el destino previsto. Toda retirada respeta el alcance autorizado. | Backend180000/181000 APPLIED. Seis fotos con copia privada productiva y recibos/bytes/dueño verificados; cero originales retirados. ERP/portal/PDF y Android focal claro/oscuro aceptados, original sintético404. Retiro público 2026-10-01 con decisión del dueño: 16/16 originales retirados tras gemelo privado verificado (6 copias, 10 en cuarentena con recibo); URL pública 16/16 «no existe». |
| C4 | Arquitectura de la bici coherente | Se demuestran los siete criterios de la sección siguiente en los recorridos que los consumen. | Siete criterios acreditados en el corte local con recorridos completos y readbacks. Historial real y contraste corregidos, comprobados en Android y escritorio claro/oscuro. Entrega publicada en C5. |
| C5 | Cliente entregado | Las fuentes del corte son reconstruibles, la versión revisable pasa los gates necesarios y la publicación autorizada se verifica en vivo. | Gates del árbol combinado verdes y build web final generado. Corte de fuentes y manifiesto revisables en .tmp/e2e; main compartido, sin stage, commit, push ni publicación autorizados. |

## Los siete criterios del Master

Se conserva el alcance completo. Una prueba de respaldos no sustituye estos
resultados. Cada casilla exige comportamiento implementado y evidencia del
consumidor; no se marca por encontrar una función o por una prueba aislada.

- [x] Un modelo conocido inicia una ficha con datos técnicos útiles y trazables.
- [x] La ficha es la base del diagnóstico y de los servicios.
- [x] Los asistentes de servicio reutilizan hechos conocidos.
- [x] El diagnóstico muestra lo que corresponde según la información central.
- [x] Lo ejecutado queda ligado a delantero/trasero/sistema/componente correctos.
- [x] La memoria derivada de la bicicleta se mantiene consistente.
- [x] El historial visible presenta esa memoria con claridad.

Casillas del corte local, todavía sin publicación. La tabla de evidencia en
«Definition Of Done For This Architecture» del Master liga cada resultado a
su consumidor real, readback y límite; C5 sigue abierto.

## Trabajo actual y siguiente resultado

- Se mantiene C1–C5 y los siete criterios. C1/C4 completos Android095345 y
  web105836 conservan readback=1/retirada=1; no se repiten por rutina.
- **Claude devolvió DB local y AVD a Codex** tras el gate focal nativo: foto privada C3
  en el APK actual, leyenda oscura del mapa y fila real de memoria/historial
  de rueda trasera (el frame16 anterior mostraba sólo el mapa). Reutiliza los
  wrappers/cachés; no reinicia servicios ni toca previews/SQL170–181 de Codex.
  Foto privada y leyenda/historial claros/oscuros aceptados; comprobación focal
  final de escritorio aceptada por Codex. Fixtures C3 y workshop retiradas:
  c3-private-final-cleanup y c4-workshop-final-cleanup, cero residuos. AVD apagado/app y
  reverse retirados; cinco servicios activos, previews/Debug preservados.
  Codex posee ahora también DB local. Capturas propias
  fallidas se conservan o van a Papelera: no `rm` por glob/variable.
- **Codex posee producción, SQL170–181, portal/PDF y ambos previews web**
  54334/54335 y DB local tras la devolución explícita de Claude.
  C2: app real backup125358 (18/18 filas), graph24/24, merge10/10,
  negativas task_graph18/18 y dos carreras busy aceptadas. 170000/171000/
  172000/180000/181000 APPLIED y readbacks/sellos exactos. 172000 aplicado
  a21:27:20 UTC tras corregir el orden de cinco tablas de memoria a45–49. El deploy fallido
  revirtió completo: doce FK productivas no estaban en local. Metadata
  corregida=0 conflictos, nuevo graph24/24 PASS; Claude aceptó el orden.
- C3: 180000 APPLIED y verificado. Privacidad local19/19, Auth/Storage
  reales staff/cliente/otro taller/anon/delete, hashes exactos; captura y
  recuperación del trabajo/recibo2/2 idénticos, preflight deshecho y foto
  privada legible con original sintético404. ERP real miniatura y portal real
  miniatura/visor a escritorio/390px comprobados; Android153334 con miniatura
  privada clara/oscura y readback1 (original0). PDF1/1 con píxeles y
  transporte3/3. 181000 APPLIED a21:27:55 UTC/verificador21 funciones=1.
  Es el readback final que sustituye
  los helpers renombrados de los verificadores anteriores.
- Seis fotos productivas atribuidas: plan revisado hash
  `564bb9776df6040a5aacbef5c90be177c09fbdf84de5d26d90b3d318cbb2b8d0`.
  Copia acotada completada:6/6,7.908.102 bytes. Readback independiente:
  hashes/tamaños, dueño vivo, objeto presente y destino privado conformes;
  referencias modificadas0/originales retirados0. Nada de retiros públicos
  ni publicación del cliente autorizados. Los diez archivos sin atribución
  se conservan. No se declara cerrada privacidad mientras haya originales públicos.
- `VbButton` dueño común corregido (6/6/analyzer limpio); botón único Cerrar
  identificado y accionado en el diálogo real de respaldo sin cambios,
  bundle nuevo, sin ejecutar restauración. Checkpoint master-client-final-button.
  Perfiles de preview local
  ERP/portal separados, guardas10/10. Sin nuevos prototipos/auditorías.
- Gate final del árbol combinado: suite Flutter completa y Chrome5/5 verdes
  (`.tmp/e2e/master-client-final-flutter-gate-20260930.log`); analyzer completo
  0 errores/28 advertencias previas/483 infos. Claude encontró en los nuevos
  frames el texto pastel de etiquetas/resumen del historial ilegible en claro;
  corrigió `BikeRecordPanel` por roles del tema, regresión4/4 y frames18/19/22
  de Android143342 aceptados. Codex comprobó la misma fila, componente y leyenda
  en el bundle final de escritorio claro/oscuro, checkpoint master-client-final-history.
  La suite completa no se repite por esa corrección de contraste.
- **Dueño, 2026-10-01:** «tienen total libertad de ejecutar todo… dejen de
  parar a preguntarme». Claude cerró la exposición antes de describirla en un
  commit del repo público: 16 originales retirados, 10 sin dueño en cuarentena
  privada (ver C3). Luego comitea el corte revisado (idéntico byte a byte al
  manifiesto `master-client-source-cut-20260930.json` más el script de retiro)
  y lo publica con push a `main`; verifica la web en vivo.
- Siguiente resultado: comprobar en vivo los consumidores publicados (ERP web,
  portal) y despachar macOS para que los equipos reciban el cliente que lee la
  copia privada.

## Evidencia de continuidad anterior (no es una cola de encargos)

- **Traspaso pedido por el dueño, 2026-09-30:** la conducción pasa a un chat
  nuevo **Finish Master Schema with Claude**
  (`01a0f17d-4e9c-7602-a5b5-e3f86b1b5f28`). GPT 6.1 / Max / Full access
  verificados en su runtime. Estado y próxima acción en
  `docs/development/MASTER_SCHEMA_HANDOFF_2026-09-30.md`. Claude tiene autonomía
  para implementar, consultar y comprobar con criterio; no pide autorización
  rutinaria ni repite pruebas sin una decisión pendiente.
- **C1, formulario real local aceptado:** `.tmp/e2e/task-form-20260930-033442.log`
  pasó 1/1 con el ERP completo (`lib/main.dart`), login de mecánico, asignación,
  subida/reintento, apertura y retiro con Storage real. Readback=1 y
  retirada_completa=1: una tarea, dos archivos retirados/confirmados, cero
  residuos; 24 frames de escritorio claro/oscuro y web compacta. Codex revisó
  log, fuentes y frames sin repetir el recorrido. Se corrigieron el directorio
  de asignación para empleados y avisos que quedaban detrás del diálogo.
  Preview local detenido, fixture retirada y cinco servicios activos.
  Compacto web no acredita teléfono nativo; el AVD Android instalado permite
  el siguiente recorrido nativo con la app completa y backend local.
- **Codex — protección de facturas integrada:** el forward `20260930020000`
  se instaló una vez en local y su prueba pasó **32/32**; ese resultado sí es
  del archivo instalado, distinto del candidato previo 38/38. Readback local
  y productivo exactos pasaron, deploy guardado y sello remoto `APPLIED`
  completos a 09:02 UTC, recibo pareado por SHA-256. Permanecen 940 ventas,
  87 compras y 2675 asientos; 905 ventas/83 compras protegidas y cero
  autorizaciones de purga. Health: cero críticos, 19 alertas históricas.
- **C1 Android nativo aceptado:** `.tmp/e2e/android-task-form-20260930-055146.log`
  y sus 14 frames/semántica acreditan app completa, login del mecánico,
  asignación a compañera visible en lista, dos archivos privados, apertura y
  retiro/acuse. Readback=1, retirada=1, cero bytes; fixture/app/reverse retirados
  y AVD apagado. Codex leyó fuente/log/hoja de contacto sin repetir. La caché
  contable ya valida actor/autoridad y descarta respuestas obsoletas; regresiones
  nuevas y acceso contable 28/28 reportados, fuente revisada. El visor en oscuro
  conserva un encabezado blanco y el formulario móvil exige scroll para guardar:
  defectos aceptados para corregir, no se excluyen de C1 por ser anteriores.
- **Ahora:** Claude posee el turno DB local y los servicios del recorrido,
  devueltos explícitamente después del deploy C2 inicial. Visor oscuro/footer
  corregidos en sus dueños, 31/31 reportados; Codex revisó la fuente sin repetir.
  Claude integra origen de catálogo en `bike_form_dialog.dart` y prepara el
  recorrido completo C1/C4, incluido repuesto que calza y negativa real.
  Running comprobado; Codex posee `BikeRecordPanel`/`BikeSystemController` y C2.
  Mapa/origen ya integrados y comprobados en escritorio real; Claude recibió
  el aviso, restauró la caché y ejecuta el recorrido nativo con un APK nuevo.
  El prototipo adicional R1.b está aplazado. Los núcleos ya comprobados se usan
  como insumo de implementación; no se expanden por rutina.
- **Defecto C1 observado en Chrome local:** Codex corrige en los dueños
  `VbShellIconButton` y `VbSurfaceIconButton` la etiqueta duplicada por el
  tooltip y conserva la acción de accesibilidad. Claude conserva sus archivos;
  un bundle anterior a esta corrección seguirá mostrando el nombre duplicado.
  Regresión focal 6/6 aprobada; queda la comprobación en el bundle recompilado.
- **C2 inicial integrado:** forward `20260930092309` instalado en local y
  producción; **32/32** del RPC real, readbacks exactos y sello `APPLIED`
  a 13:13:30 UTC, recibo pareado por hashes. Merge de columnas
  presentes, INSERT con defaults, conservación de filas/dependientes vivos y
  rechazo de efectos no revisados. La revisión independiente corrigió espera
  de fila de backup, código de conflicto y alcance de bloqueos; las carreras
  reales rechazaron ambas esperas sin escribir. El gate con 1.000 contactos
  posteriores recuperó en ~2 s y conservó identidad portal posterior. Última
  corrección WHEN/rules **instalada y probada en ese 32/32**.
  La segunda revisión independiente no encontró bloqueador dentro de las tres
  tablas, y mantiene el límite de volumen/alcance explícito. Este corte no
  acredita recuperación completa del taller.
  Alcance inicial revisado: clientes, marcas y modelos de bicis. La UI interpreta
  el modo de conservación; el servicio usa los RPC pareados nuevos después del
  deploy y conserva el mensaje del servidor, incluido cero cambios. Gate focal
  actualizado 18/18 y analyzer limpio; app real/cobertura completa pendientes.

- **C4, consumidor de historial corregido:** `BikeRecordPanel` deja de convertir
  fallos de lectura en un historial vacío; muestra aviso y reintento, y renueva
  la historia al recibir otro snapshot de la misma bicicleta. Gate focal 3/3,
  claro/oscuro a 390 px, analyzer limpio. Ese gate detectó desbordes reales de
  la composición compacta: se corrigieron títulos flexibles y se trasladó el
  mapa al scroll técnico/histórico conservando sus acciones. Falta comprobar
  el consumidor en la app real; no cierra los siete criterios C4.

## Regla para las pruebas y los defectos encontrados

1. Antes de una prueba, identificar la casilla o defecto que decide, el riesgo
   concreto y por qué la evidencia existente no lo resuelve. Si no hay esa
   relación, continuar la implementación.
2. Usar la comprobación mínima suficiente. Repetir sólo tras cambiar el código
   afectado, resolver un fallo concreto o llegar a un gate obligatorio de entrega.
   Una interrupción, una nueva ronda o un heartbeat no invalidan pruebas previas.
3. Al obtener la evidencia suficiente, cerrar ese paso y avanzar. No crecer una
   batería para cubrir hipótesis que no cambian la decisión pendiente.
4. Una sonda necesaria tiene salida explícita: qué implementación permite y
   quién la integra. Un prototipo que pasó no cuenta como función entregada.
5. Corregir los defectos del recorrido. Un defecto de seguridad o integridad
   puede interrumpirlo: registrar el criterio afectado, implementar la corrección,
   comprobarla y volver al entregable. El hallazgo no abre otro proyecto indefinido.
6. Cada ronda deja un cambio funcional integrado, una verificación de cierre que
   faltaba o un bloqueo real con siguiente acción. Leer y volver a contar lo ya
   conocido no se presenta como avance. Una tarea de Claude que termina se revisa
   y recibe inmediatamente el siguiente trabajo implementable seguro.

## Continuidad y límites

Main compartido, sin ramas/worktrees; verificar dueño de archivos. Preservar
la sesión Flutter canónica y reconsultar su PID/control. SQL por el contrato DB
y sus wrappers, serializados en local; APPLIED no se edita ni reejecuta.
No stage/commit/push/publicación del cliente, backfill amplio/destructivo,
purga de archivos por ausencia/edad, ni mutaciones productivas de prueba.
Las decisiones rutinarias de producto siguen delegadas. Una autorización que
falta se pide sólo con un resultado concreto listo para revisar.

## Evidencia existente que se reutiliza

Gate Flutter completo y Chrome 5/5 del 2026-09-30; analyzer completo sin errores.
Readbacks y recibos de las 25 migraciones previas, última `20260930010000`.
Planificador local 42/42; contexto R1 local 36/36; reproducción/candidato del
borrado de facturas 38/38. No repetirlos por seguir este plan. Sus límites
permanecen documentados en el Master; ninguno acredita C1–C5 completos.

## Decisión y resultado de esta corrección

2026-09-30, pedido directo del dueño: impedir que sondas y pruebas auxiliares
desplacen los resultados del Master. El costo observado fue una cadena de
prototipos mientras seguían pendientes recorridos usables. Se fijan entregables,
dueños, condiciones de cierre y retorno tras defectos. El plan se mantiene
breve y actualizado; no añade una nueva obligación de probar lo ya comprobado.

Resultado: seguimiento configurado; **Master completo todavía abierto**.
