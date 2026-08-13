# Plan maestro de cierre de Nóminas

Estado: activo  
Superficie canónica: `/hr/payroll`  
Flujo OCR: `/hr/payroll/reconcile`

> **Enmienda de producto vigente — 2026-08-11.** El flujo OCR de cartola es una
> ayuda para preparar pagos, no el owner de una conciliación bancaria completa.
> Sólo lee, encuentra candidatos y precarga evidencia en el único
> `PayrollPaymentWorkspace`. No registra pagos, no compone efectivo/anticipos,
> no confirma semanas y no exige resolver los movimientos no utilizados. Esta
> enmienda reemplaza cualquier descripción histórica inferior que diga lo
> contrario.

## 1. Resultado terminal

Nóminas queda terminada cuando una persona autorizada puede, sin recurrir a
pantallas legacy ni estados “próximamente”:

1. revisar las obligaciones de una o varias semanas;
2. identificar el método canónico de cada trabajador;
3. registrar pagos por transferencia o efectivo con fecha, cuenta, referencia,
   actor y evidencia auditable;
4. registrar y aplicar anticipos, incluso cuando todavía no existe ninguno;
5. comprometer el borrador para reconocer obligaciones una sola vez y dejar que
   la semana pase automáticamente a `partial`/`paid` a medida que se registran
   sus resoluciones;
6. importar PDF, imagen o captura de cámara, revisar candidatos del OCR y usar
   los seleccionados como precarga del workspace de pago, sin bloquear por el
   resto de la cartola;
7. revisar el historial, cada pago y su evidencia;
8. completar los mismos flujos en desktop, tablet y teléfono;
9. usar la nueva composición integral de `MainLayout`, workspace chrome y
   módulo, sin mezclar barras o escalas legacy;
10. operar contra el contrato backend versionado instalado y verificado en el
    entorno objetivo.

Un fallback honesto de solo lectura puede proteger un despliegue incompatible,
pero no cuenta como módulo terminado en producción.

## 2. Reparto de autoridad

### Claude Design

- Es autoridad del looking: composición, ritmo, jerarquía, tipografía,
  superficies, color, iconografía, overlays, estados visuales y responsive.
- Trabaja con libertad visual y desde cero sobre la gramática canónica de
  Nóminas; el legacy no es precedente.
- Debe entregar frames integrales y estados, no recortes decorativos ni código
  que asuma un viewport ficticio.
- No edita el repositorio.

### Codex

- Es autoridad de UX operacional, lenguaje, contratos, navegación, integridad,
  concurrencia, idempotencia, seguridad y adaptación Flutter.
- Revisa las propuestas de Design; no copia literalmente decisiones que
  contradigan el proceso real, el shell, el ancho disponible o el backend.
- Implementa, prueba e integra.
- Traduce cada frame a componentes semánticos reutilizables sin hacer del layout
  particular de Nóminas una receta universal para otros módulos.

### Regla de continuidad

Un alcance puntual del usuario interrumpe sólo el bloque activo. Se corrige, se
verifica y el trabajo vuelve al primer bloque pendiente de este plan. No se
declara cierre por terminar un detalle aislado.

Este archivo es el ledger persistente de la ejecución. Al cerrar una ronda se
actualiza aquí qué quedó probado, qué depende todavía del entorno objetivo y
cuál es el primer bloque pendiente. Una corrección puntual nunca crea un plan
paralelo ni borra el puntero: después de verificarla se retoma automáticamente
el orden de la sección 8.

## 3. Principios UX no negociables

- El trabajo cotidiano es pagar y cerrar semanas. OCR es una utilidad
  secundaria para resolver acumulación; no es el CTA dominante permanente.
- `PayrollPaymentWorkspace` y `PayrollPaymentWorkspaceController` son el único
  editor de pago. La cola los abre en alcance persona/semana y OCR los abre en
  batch con semanas ordenadas por fecha descendente y personas agrupadas dentro
  de cada una; ambos hosts comparten controles, ecuaciones, borrador,
  validaciones, comando y resultado.
- El batch OCR es el cuarto paso de ancho completo de `Importar cartola`: todas
  las obligaciones positivas de todas las semanas abiertas permanecen visibles
  a la vez, con o sin calce OCR. La selección previa sólo precarga evidencia;
  nunca elimina trabajadores. Cada fila ofrece su método y resumen monetario,
  el detalle flexible se expande bajo esa misma fila y una sola acción registra
  el lote atómicamente. El side sheet queda reservado para el pago individual
  iniciado desde Nóminas.
- El workspace permite múltiples piernas por sueldo —transferencias, efectivo y
  anticipos, completos o parciales— con método, cuenta, fecha, referencia y
  evidencia propios. Reembolsos, gastos del negocio y otros conceptos no
  salariales son conceptos contables separados con descripción, cuenta y monto.
  Cada uno declara si ya estaba incluido en el total de nómina —cubre y
  reclasifica esa porción, sin aumentar el desembolso— o si se suma aparte. La
  decisión nunca se infiere y ningún modo cambia horas ni tarifa.
- OCR sólo sugiere y precarga calces directos. Las filas de cartola no elegidas
  son un resultado válido, no se clasifican por obligación y no bloquean la
  continuación al workspace de pago.
- Asistencias es dueña de los registros fuente y origina el snapshot semanal.
  Mientras siga en `draft`, el editor canónico de Nóminas permite ajustar horas
  y tarifa tanto en el preview como al reabrir el borrador, sin escribir esos
  ajustes en Asistencias ni en la tarifa maestra del trabajador. Create y update
  usan el mismo writer idempotente y versionado.
- `Confirmar semana` bloquea la edición del snapshot y reconoce las
  obligaciones. No
  existe una segunda confirmación manual: `partial` y `paid` se derivan de los
  movimientos y el último saldo en `$0` mueve la semana a Historial.
- Cada fila tiene una sola superficie de decisión:
  - `Pagado` clickeable abre pago/evidencia;
  - `Sin método ▾` abre configuración;
  - una obligación pendiente muestra una sola acción directa;
  - un bloqueo de backend o permisos muestra estado pasivo, no una acción falsa.
- Los encabezados usan `TOTAL`, no `GANADO`.
- Ninguna acción financiera usa un `GestureDetector` sin semántica, foco,
  teclado, hover y estado disabled.
- No hay autoavance después de registrar dinero. El resultado explica qué
  cambió y ofrece destinos explícitos.
- Un movimiento bancario extra, como una transferencia de `$22.000` a Vicente
  para gastos, jamás se convierte en sueldo por compartir destinatario.
- El actor que hoy registra el servidor es el usuario autenticado. Se muestra
  su nombre sin un selector falso; elegir otro entregador exige primero un
  campo backend auditable.
- El zoom es una preferencia global del usuario, no una heurística por ruta.
  La composición nace en `1.0`, funciona a `0.8` y separa escala de densidad.
- Modo claro se termina como familia antes de introducir dark mode. El navy del
  frame no es por sí mismo “dark mode”.

## 4. Estado confirmado

### Terminado y probado

- `/hr/payroll` usa `PayrollRedesignPage`; la lista legacy no es el árbol
  visual productivo.
- Cola de semanas horizontal, selección cardinal segura y recomposición móvil.
- Tabla desktop con columnas adaptativas y `TOTAL`.
- Una sola decisión en el extremo derecho:
  - `Pagado` clickeable;
  - menú tonal `Sin método`;
  - acción directa para transferencia/efectivo;
  - estados pasivos en solo lectura.
- `Importar cartola` quedó como utilidad OCR secundaria y recuperó contraste
  correcto sobre el chrome navy.
- Historial hidrata semanas pagadas/anuladas de forma lazy y ordena newest
  first.
- Composer de transferencia:
  - fecha y referencia;
  - selección entre múltiples métodos/cuentas canónicos de la familia
    transferencia, sin asumir el primero;
  - anticipos múltiples;
  - monto editable con formato CLP, máximo server-derived y saldo residual
    visible;
  - pagos completos o parciales sin sobrepasar la obligación disponible;
  - ecuación visible;
  - cierre protegido;
  - comando idempotente y versionado.
- Efectivo:
  - oculta la acción de anticipo cuando el saldo disponible es cero;
  - muestra como actor server-owned al usuario autenticado, sin selector que
    pueda falsificar la evidencia;
  - muestra Back antes y después de confirmar;
  - no autoavanza;
  - usa destinos explícitos.
- Anticipos ofrece `Registrar primer anticipo` cuando el libro está vacío.
- `PayrollSettlementEvidence` conserva cada pago y anticipo por separado, con
  origen, fechas, método/cuenta, referencia, actor, operación y evidencia de
  cartola cuando existe.
- `PayrollVoucherService` hidrata todas las semanas abiertas con una sola
  llamada por lote a `get_payroll_voucher_settlement_evidence(uuid[])`;
  Historial reutiliza el mismo contrato y no crea lectores paralelos.
- `PayrollPaymentEvidenceSurface` abre desde `Pagado` en desktop y mobile y
  desde cada línea de Historial. Expone totales, movimientos, actor, origen,
  referencia y varianza; un backend legacy se identifica honestamente como
  agregado sin respaldo detallado.
- La migración
  `20260729173000_add_payroll_settlement_evidence_read_model.sql` agrega el read
  model anterior y `payroll_beneficiary_aliases`: el alias normalizado es único
  por tenant, conserva actor/fechas, tiene RLS y no permite cambiar su
  tenant/trabajador/origen por update. La definición final está espejada en
  `supabase/sql/core_schema.sql`.
- Matching OCR, decisiones explícitas, efectivo persona por persona,
  fingerprints, tolerancia, version checks y apply atómico existen en código.
- El stepper OCR usa una sola regla de gating para navegación y apply:
  archivo → transferencias → efectivo → confirmación. Las etapas anteriores
  siguen disponibles y el primer bloqueo se explica en el footer.
- La captura declara capacidades reales antes de abrir el picker: cartola
  Banco de Chile, PDF con texto, OCR local de PDF escaneado/imagen cuando el
  host lo soporta y cámara sólo en Android/iPhone. No promete una entrada que
  vaya a fallar después del tap.
- La cartola real de aceptación se procesó con el extractor productivo:
  `embeddedPdfText`, 5 páginas y 96 movimientos. Recuperó las transferencias
  semanales esperadas, conservó la diferencia de `$250` como revisión y dejó
  el movimiento extra de `$22.000` fuera de sueldo sin decisión humana.
- El aprendizaje de alias bancario es explícito, opcional, tenant-scoped e
  idempotente. Nunca aprende sólo porque dos nombres se parezcan ni cambia una
  decisión ya aplicada.
- Una obligación de efectivo puede combinar múltiples anticipos con el efectivo
  nuevo restante; una cobertura total por anticipos no crea un pago de `$0`.
- El comprobante final distingue apply nuevo de replay, resume semanas y cada
  tipo de decisión, muestra import/operation IDs y enlaza a Semanas para revisar
  la evidencia aplicada.
- El host bloquea una repetición cuando la confirmación del servidor es ambigua
  hasta obtener una lectura autoritativa.
- Los pagos bancarios parciales exigen decisión y motivo explícitos, aplican
  sólo el importe observado y conservan el saldo restante. Un pago inferior
  nunca se auto-sugiere por tolerancia.
- Los rechazos de conciliación se clasifican como retry ambiguo, recarga por
  conflicto, corrección de configuración o revisión de permisos; sólo un
  resultado ambiguo ofrece repetir con las mismas claves idempotentes.
- Cuando OCR toca semanas en borrador, el último paso enumera exactamente qué
  borradores comprometerá. El cliente y el servidor exigen el mismo allow-list,
  el CTA distingue `Comprometer X semanas y aplicar conciliación` de
  `Aplicar conciliación`, y el recibo devuelve los IDs comprometidos.

### Verificación vigente

- Analyzer enfocado de las superficies cambiadas: limpio.
- Tests de queue, history, composer, evidencia y host redesign: verdes.
- Gate pgTAP enfocado sobre snapshot derivado de producción: 203 pruebas verdes
  para autorización y conciliación, incluida la política de aliases, lectura
  por lote, aislamiento de trabajadores y rechazo cross-tenant.
- Sesión nativa macOS compartida: única sesión de debug; se actualiza con hot
  reload/restart, no se inicia una segunda.
- El shell compacto usa una frontera temática completa para sus seis presets.
  La matriz renderizada cubre host light/dark, `ThemeMode.system`, header,
  drawer, modos, búsqueda, navegación/herramientas, badges, acciones fijadas y
  scrim; analyzer y 34 pruebas del bloque están verdes.
- El bloque OCR con compromiso explícito está verde con 61 pruebas Flutter y
  149 pruebas pgTAP enfocadas.
- El compositor de pagos parciales suma pruebas de formato, límites, saldo
  residual y split exacto; analyzer enfocado y 30 pruebas widget están verdes.

## 5. Bloqueadores P0 y dependencias de activación

### P0.1 — Backend versionado en el entorno objetivo

Producción aún expone el contrato legacy: falta `reconciliation_version`, las
tablas de conciliación, `payroll_beneficiary_aliases` y los RPC versionados,
incluido `get_payroll_voucher_settlement_evidence(uuid[])`. El fallback de
lectura está funcionando, pero confirma que el producto todavía no puede
operar.

Antes de desplegar:

1. reconciliar `hr_payroll_authorization_hardening.sql` con el contrato final:
   `confirm_payroll_voucher(uuid)` ya no pertenece a `authenticated`; el comando
   versionado es el writer autorizado;
2. ejecutar el gate local de producción derivada;
3. revisar las migraciones payroll en orden y sus grants finales;
   la última dependencia local es
   `20260729190000_learn_payroll_beneficiary_alias.sql`;
4. desplegar con el procedimiento guardado del contrato DB;
5. verificar presencia, firmas, grants, RLS y comportamiento;
6. abrir `/hr/payroll` y confirmar que
   `versionedMutationsAvailable == true`.

### P0.2 — Evidencia completa de pagos: implementada localmente

El modelo `PayrollSettlementEvidence`, la lectura versionada por lote, el panel
adaptativo y la integración de Queue/Historial ya conservan más de un pago
parcial y anticipos sin N+1. La migración agrega el RPC y los aliases de
beneficiarios, y el gate local derivado de producción está verde.

Este bloque no requiere otro diseño ni otro lector. Su única dependencia
pendiente es instalar y verificar la migración mediante P0.1. Hasta entonces,
el fallback legacy puede mostrar el total agregado, pero debe advertir que el
detalle auditable no está disponible y jamás inventar método, referencia,
cuenta o actor.

### P0.3 — Cierre honesto de OCR: implementado localmente

El flujo usa `Salir sin guardar`, confirma el descarte cuando existe un draft y
no simula persistencia. Una futura reanudación durable sería otro contrato
tenant-scoped; no es necesaria para que este flujo corto sea honesto y usable.

### P0.4 — Método faltante dentro de OCR: implementado localmente

El bloqueo lista a cada persona afectada, abre su ficha mediante `push`, vuelve
al mismo draft, refresca el contexto ERP sin perder decisiones válidas y
recalcula sólo lo dependiente. El servidor acepta el método recién configurado
únicamente cuando el snapshot anterior faltaba o ya era inválido; un snapshot
todavía válido no puede sustituirse silenciosamente.

### P0.5 — Handoff visual de Design: aceptado para los flujos actuales

Los frames aprobados de `Nóminas - Rediseño` siguen siendo la autoridad visual
de Semanas, pagos, Historial, Anticipos, OCR y responsive. Codex los adapta a
los contratos reales —sin duplicar logos, comprimir tablas o copiar acciones
ficticias— y conserva pendiente una nueva revisión de Design para cualquier
familia visual todavía no entregada, especialmente dark mode integral.

## 6. Bloques P1 — flujo completamente usable

### P1.1 — Semanas y compromiso

- Vacío con acción real a Asistencias.
- Razón del CTA deshabilitado visible también en densidad compacta.
- Compromiso con resumen de obligaciones y congelamiento irreversible
  claramente explicado.
- Semana draft, confirmed, partial, paid y voided.
- Ningún `Confirmar semana` posterior al compromiso: el último saldo en `$0`
  actualiza el estado y mueve la semana a Historial automáticamente.
- Refresco y fence de concurrencia después de cada comando.

### P1.2 — Transferencia

- La selección entre varios métodos/cuentas canónicos de la familia
  transferencia ya está implementada y probada; nunca se fija por posición.
- Montos parciales y completos ya están implementados: el CTA usa el monto
  realmente ingresado, el servidor recibe ese split y la línea conserva el
  saldo pendiente sin un segundo cierre.
- Fecha válida, referencia condicional, evidencia adjunta cuando corresponda.
- Resultado con saldo y destino explícito.

### P1.3 — Efectivo

- Fecha, importe y actor server-owned visibles; el actor autenticado ya se
  muestra como evidencia de solo lectura.
- Anticipos asignados en orden y con saldo decreciente.
- Back es visible antes y después de la confirmación; el flujo OCR protege el
  descarte de cualquier draft modificado.
- El efectivo OCR admite varios anticipos y sólo registra como efectivo nuevo
  el remanente; muestra como actor al usuario autenticado que registrará el
  servidor.
- Resultado con siguiente efectivo completo o `Volver a Nóminas`.
- Si se requiere seleccionar un entregador físico distinto, diseñar y migrar
  primero su contrato auditable.

### P1.4 — Anticipos

- El estado vacío real y `Registrar primer anticipo` ya están implementados.
- La creación actual ya persiste trabajador, método/cuenta, fecha, monto y
  referencia mediante el comando versionado.
- La superficie actual ordena por el nombre visible del trabajador, usa un
  selector buscable cuando la cardinalidad crece, conserva la persona al
  recomponer entre compact y desktop y permite iniciar un registro contextual
  con esa persona preseleccionada. Los métodos con nombres repetidos identifican
  además su cuenta contable; nunca se distinguen por posición.
- El ledger visible debe permanecer acotado y desplazable con muchas filas o
  poca altura. Una persona inactiva puede conservar historial, pero no puede
  recibir un CTA de nuevo anticipo.
- El backend fuente ya define el contrato estructurado
  `requested_advance | short_workweek | other`, explicación obligatoria y
  `work_ended_on` para semana corta en
  `20260801183000_add_structured_employee_advance_audit.sql`. La migración aún
  no está desplegada y la UI de creación todavía debe adoptar v3; una nota libre
  no reemplaza ese contrato.
- El mismo contrato vincula opcionalmente el comprobante original a `app_files`
  por actor + operation key. Conserva el SHA-256 calculado por el cliente, pero
  la frontera de confianza no depende de esa metadata: v3 comprueba el dueño
  real de Storage y fija el `object id`, `version` y `ETag` producidos por el
  servidor antes de volver inmutables el vínculo, la metadata y los bytes. Un
  upload todavía no reclamado por `app_files` permanece recuperable; la
  inmutabilidad comienza sólo después de validar metadata, actor y objeto.
  El coordinador cliente ordena `capability → carga confirmada → v3`, sin
  compensación destructiva ante respuestas ambiguas. La migración pasa 42
  contratos pgTAP locales. Un smoke real por Storage API + PostgREST confirmó
  upload `200`, metadata `201`, dueño/versión/ETag, bloqueo posterior y rechazo
  de overwrite/delete; su cleanup terminó con cero usuarios, tenants, metadata
  u objetos de prueba. Siguen pendientes la adopción desde la UI y el despliegue.
- `get_employee_advance_ledger_page_v2` ya enriquece la página acotada de v1 con
  motivo y evidencia. El cliente parsea v2 y degrada sólo ante ausencia real a
  v1 durante el rollout; producción aún no tiene la migración.
- Aplicación a semanas elegibles sin reescribir total/horas.
- Búsqueda/selector adaptativo cuando la lista de trabajadores crece, selección
  preservada al cambiar breakpoint y persona preseleccionada en acciones
  contextuales.

### P1.5 — OCR completo

- PDF con texto.
- PDF escaneado con OCR local cuando la plataforma lo soporte.
- Imagen y cámara en hosts compatibles.
- Matriz visible de capacidades por plataforma; sin botones que fallan después
  del tap.
- Cuenta bancaria ERP explícita y fingerprint enmascarado.
- Match por persona, alias, fecha y monto.
- Tolerancia porcentual y CLP.
- Sugerido, ambiguo, sin match, OCR incompleto, duplicado, ya resuelto,
  no-nómina y parcial.
- Vicente `$22.000` permanece fuera de sueldo salvo decisión humana explícita.
- Efectivo se pregunta manualmente.
- Impacto por semana antes de escribir.
- Cobertura completa de decisiones e idempotencia.
- Stepper sólo permite avanzar cuando la etapa anterior está válida.
- Apply atómico, retry exacto y comprobante final.

## 7. Bloques P2 — arquitectura visual integral

### P2.1 — MainLayout y workspace chrome

- Un solo bloque navy de 84 px: workspace tabs 40 + module command 44.
- Ningún logo duplicado.
- Toolbar derecha sin isla blanca.
- `expanded`, `rail` y `hidden` pertenecen al shell y persisten por
  usuario/workspace.
- El módulo sugiere rail; nunca lo fuerza.
- Overlay/toolbar reserva ancho; no tapa el canvas.
- Shell real probado con Nóminas, Sitio Web editor y otra tabla compleja.

### P2.2 — Sistema semántico

- Migrar literals de `PayrollTokens` a roles del sistema visual compartido.
- `AppearanceService` elige preset; no expone colores a módulos.
- Acciones, controles, estados y superficies consumen roles, no hex.
- Botones celestes/azules son roles funcionales, no colores aislados.
- Cambiar un rol de tema actualiza todos sus consumidores.

### P2.3 — Dark mode como familia

Sólo comienza cuando el modo claro y sus flujos están cerrados:

- cuatro pasos de superficie sin negro puro;
- matiz derivado del preset global;
- contraste AA;
- shell, canvas, cards, tablas, inputs, overlays, estados y gráficos;
- ningún módulo parcial;
- golden/contract tests light y dark en hosts integrales.

### P2.4 — Tablet y mobile

- Desktop tabla; teléfono tarjetas/tareas, no tabla comprimida.
- Una decisión por pantalla en pagos.
- CTA táctil mínimo 48/50.
- Bottom sheets y full-screen flows según altura útil/teclado.
- Safe areas, text scale y landscape.
- Retorno mediante `ReturnNavigation.close`.
- Pagado/evidencia disponible también en mobile.

### P2.5 — Historial y Anticipos a escala

- Historial compacto mantiene ledger escaneable, no repite cuatro cards por
  persona.
- Anticipos no comprime N personas en una fila de `Expanded`; usa selector,
  wrap/scroll controlado o búsqueda según cardinalidad aprobada por Design.

## 8. Orden de ejecución

Puntero vigente: **ledger/paginación real de Anticipos e Historial, en paralelo
con la migración semántica de tema**.
El aprendizaje de aliases, captura, cartola real, pago bancario parcial,
recuperación tipada y allow-list explícito de compromiso OCR ya están cerrados
localmente. Asistencias ya origina el preview semanal; el mismo editor canónico
crea o actualiza el snapshot de Nóminas mediante
`save_payroll_voucher_draft`, con operación idempotente y versión esperada al
actualizar. `draft → confirmed` se expone como `Confirmar semana`, bloquea ese
editor y `partial/paid` permanecen estados automáticos. La ronda activa agrega
los read models paginados sin convertir la lista abierta actual en historial
ficticio.
El shell compacto ya fue corregido y certificado como frontera temática, pero
las superficies internas de Nóminas siguen oficialmente en migración
light/dark. La raíz debe resolver una sola vez `preset × brightness` hacia
`ColorScheme` y roles semánticos; cada superficie consume esos roles. Queda
prohibido resolver esta deuda con colores oscuros puntuales o con una clase
paralela `PayrollTokensDark`. Cada alcance puntual se resuelve y verifica y
luego vuelve a este puntero.

1. Cerrar handoff visual de Claude Design y reparar cualquier frame roto.
2. Terminar Semanas/Historial desktop con evidencia y estados.
3. Completar transferencia, efectivo, métodos y Anticipos.
4. Completar recuperación/persistencia honesta de OCR.
5. Reconciliar gate SQL, desplegar backend versionado y verificar.
6. Integrar MainLayout/workspace chrome y retirar duplicación local.
7. Implementar tablet/mobile de cada flujo, no al final como skin.
8. Migrar a roles semánticos y terminar light mode.
9. Implementar dark mode integral basado en preset.
10. Ejecutar la matriz completa de aceptación.

Los bloques 2–4 pueden avanzar contra acciones inyectadas y backend local
validado, pero ningún write productivo se habilita antes del bloque 5.

## 9. Matriz mínima de aceptación

### Anchos

- 1440×900 con rail.
- Canvas de aproximadamente 1116 con sidebar expandido.
- 900 y 899.
- Tablet 834 portrait/landscape.
- Phone 390 portrait y landscape crítico.
- Zoom global 0.8 y 1.0.
- Text scale 1.0 y 1.3.

### Interacción

- mouse/pointer/hover;
- teclado Tab, Shift+Tab, Enter, Space, Escape y flechas;
- foco visible;
- semantics y labels monetarios;
- pantalla táctil;
- teclado virtual;
- Back del sistema y acción visible de retorno.

### Datos y fallos

- cero, uno y muchos trabajadores/semanas/anticipos;
- montos cero, exactos, parciales y con diferencia;
- método faltante/inactivo/cuenta inválida;
- offline antes y después de enviar;
- timeout con commit ambiguo;
- conflicto de versión;
- permiso insuficiente;
- archivo ilegible/duplicado/cuenta distinta;
- apply replay idempotente.

### Gates

- analyzer enfocado;
- tests unitarios de matcher/parser/servicios;
- widget tests de cada superficie y ancho;
- tests DB sobre snapshot derivado de producción;
- verificación de grants/RLS/RPCs;
- revisión nativa macOS de la sesión compartida;
- revisión visual cruzada contra los frames de Claude Design;
- actualización de `canonical-ui-surfaces.md`.

## 10. Protocolo de preview

- Una sola sesión nativa macOS es dueña del preview.
- Cambios Dart compatibles: hot reload.
- Cambios de inicialización, providers, rutas o contratos: hot restart.
- Build/restart completo sólo cuando el runtime lo exige.
- Nunca abrir una sesión fresca mientras la sesión canónica siga sana.
- Antes de entregar una ronda, dejar la app abierta en Nóminas y anotar qué
  superficie debe revisar el usuario.
