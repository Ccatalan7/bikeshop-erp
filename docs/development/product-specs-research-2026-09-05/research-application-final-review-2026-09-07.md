# Aplicador final: revisión independiente, sólo lectura

Revisión de Claude sobre el candidato final. **No edité ningún archivo del
aplicador, no corrí SQL, no toqué producción, migraciones, fill, git ni
runtime.** Corrí sólo Python de esta revisión.

Leídos completos: `scripts/inventory/prepare_product_spec_registration.py`,
`scripts/inventory/apply_product_spec_research.py`,
`scripts/inventory/sql/product_spec_application_candidate.sql`,
`test/scripts/test_product_spec_application.py`,
`docs/development/product-specs-research-2026-09-05/research-application-readiness-2026-09-07.md`,
y las partes de `prepare_product_spec_application.py`,
`simulate_product_spec_research.py`, `product_spec_session.py` y
`supabase/migrations/20260907023000_product_spec_research_snapshot.sql` de las
que dependen las afirmaciones de abajo.

Reproduje la batería existente antes de buscar nada:

```
uv run --with "jsonschema[format-nongpl]==4.26.0" python -m unittest \
  discover -s test/scripts -p "test_product_spec_application.py"
→ Ran 24 tests in 0.919s — OK
```

Los 24 pasan. Lo que sigue es lo que **no** cubren.

## F-1 · Un rechazo definitivo del servidor se le presenta al operador como una escritura incierta

`ApplicationSession.application` captura `urllib.error.URLError` — y
`HTTPError` **hereda** de `URLError` — y lo convierte todo en el mismo
`SessionUnavailable('Application response unavailable; recover the same
operation ID')`, con `from None`, que además descarta el mensaje del servidor.

La prueba de transporte existente
(`test_timeout_has_no_retry_or_credential_output`) sólo ejercita un
`URLError` genérico. Un 403 del propio aplicador —`El saneamiento global
todavía no habilita el llenado`, `Aplicación no disponible`, `Comando de ficha
inválido`— entra por la misma rama.

Reproducción (sólo Python, sin red, con las clases reales del proyecto):

```
HTTP 403 (ACL / readiness refusal     ) -> 'Application response unavailable; recover the same operation ID'
HTTP 400 (invalid command             ) -> 'Application response unavailable; recover the same operation ID'
HTTP 404 (application not registered  ) -> 'Application response unavailable; recover the same operation ID'
timeout                                  -> 'Application response unavailable; recover the same operation ID'
```

**Consecuencia.** El estado final es seguro: no hay reintento automático, y
`--recover-only` termina en `This operation has no applied receipt`. El daño es
de diagnóstico y de procedimiento. Ante una negativa de ACL o de readiness —que
**demuestra** que no se escribió nada— al operador se le dice que su escritura
quedó incierta y que recupere la operación. En una ventana de cambio, esa
diferencia decide si se investiga el permiso o se sale a buscar un recibo que no
existe. Y la razón exacta que el servidor sí envió se pierde.

**Corrección sugerida.** Separar `HTTPError` de los fallos de transporte:
un 4xx distinto de 408/429 es determinista y debe propagarse como un error de
estado con el `code`/`message` de PostgREST; sólo timeouts, 5xx y errores de
socket justifican el texto de incertidumbre. Es una rama `except`, no un cambio
de contrato. Sigue sin exponerse ningún credencial: el cuerpo de PostgREST no
los contiene, y la prueba existente que verifica que el token no aparece en el
mensaje se conserva tal cual.

## F-2 · El recibo aplicado por otra sesión se reporta como aplicado por ésta

`apply_or_recover` calcula `recovered_existing_receipt` a partir del `status`
leído **antes** de llamar a `APPLY`, no del resultado de `APPLY`. Si otra sesión
aplica entre esas dos llamadas, el servidor devuelve correctamente su recibo con
`replayed: true` —sin volver a ejecutar nada— y el cliente informa
`recovered_existing_receipt: False`.

```
server said replayed=True; client reported recovered_existing_receipt=False
```

**Consecuencia.** Ninguna escritura de más: el servidor es idempotente y la
prueba lo confirma. Lo que se pierde es la trazabilidad de quién aplicó. El
archivo de salida y la línea impresa afirman una aplicación propia donde hubo una
recuperación ajena, y `replayed` viene en la respuesta de `APPLY` y se descarta.

**Corrección sugerida.** Derivar el campo del resultado de `APPLY`
(`replayed`), no del `status` previo.

## F-3 · La llave del candado del registrador se arma con texto, no con uuid

El aplicador arma su llave con casts —
`hashtextextended(tenant::text||':spec_research:'||p_application_id::text,0)` —
que es exactamente la corrección que se aplicó tras la revisión anterior. El
registrador la arma con los **literales del bundle**:

```
perform pg_advisory_xact_lock(hashtextextended({tenant}||':spec_research:'||{id},0));
```

Hoy coinciden: `operation_id` es un `uuid5` (canónico por construcción) y
`tenant_id` viene del snapshot del servidor. Pero coinciden **por convención, no
por construcción**, y es la misma clase de divergencia ya corregida una vez en
este mismo archivo. Ni `command['tenant_id']`, ni `product_id`, ni `actor_id`
pasan por la comprobación de canonicidad que `registration_sql` **sí** aplica a
las identidades de readiness (`str(UUID(x)) != x`) y `prepare` a
`definition_id`.

**Severidad honesta: baja.** El registrador también toma `for update` sobre la
fila de la aplicación, así que el bloqueo de fila serializa igual. Es
endurecimiento, no un agujero: `{tenant}::uuid::text||':spec_research:'||{id}::uuid::text`.

## F-4 · El vínculo propuesta↔revisión es la única comprobación que el RPC no rehace

El RPC vuelve a verificar contra estado vivo casi todo: preimagen completa por
hash y por huellas, `spec_revision`, `updated_at`, `template_id`,
`contract_version`, el preview canónico recalculado, la plantilla activa de cada
efecto, la resolución de opciones a IDs únicos, la identidad fuera del parche y
la conservación de toda observación no incluida.

La aprobación es la excepción:

```
application.proposal#>>'{review,reviewed_proposal_sha256}' is distinct from command->>'proposal_sha256'
```

Compara dos campos que **el mismo registrador escribió en la misma sentencia**.
No recalcula ningún digest sobre `application.proposal`. Quien pueda registrar
puede hacerlos concordar; la defensa real es el `prepare()` fresco del
registrador Python y `bundle_sha256`.

No lo llamo defecto: el readiness ya dice que el registrador es una frontera
privilegiada que requiere la misma revisión que el writer, y esta revisión lo
confirma en el código. Lo señalo porque es el **único** punto donde el servidor
acepta una afirmación del cliente privilegiado sin poder contrastarla, y conviene
que esté dicho en el documento y no sólo implícito.

## Lo que verifiqué y encontré sólido

No asumo que las 24 + 26 + 8 + 42 pruebas de root cubran lo que falta; esto es lo
que comprobé por mi cuenta, leyendo, y que **no** produjo hallazgo:

- **Preimagen.** `snapshot_sha256` se calcula sobre `{fingerprints, product,
  editor}` y `fingerprints.facts_sha256` cubre las observaciones, así que el
  hash es transitivo sobre todo el preimagen. El RPC compara además las cuatro
  huellas por separado, `spec_revision` y `updated_at`.
- **Conservación.** Sospeché que las observaciones con `subject_scope` no nulo
  quedaran fuera del control `untouched_before/untouched_after`. **Es falso**:
  la consulta del snapshot filtra sólo `tenant_id`, `subject_type` y
  `subject_id`, sin filtro de scope, y el `for update` tampoco lo filtra. La
  comprobación cubre exactamente lo que el snapshot proyecta, y el snapshot
  proyecta todo lo del producto.
- **Producto completo.** El snapshot proyecta columnas seleccionadas, pero
  `fingerprints.product_sha256` es sobre `to_jsonb(product)` —la fila entera— y
  el cliente compara ese hash contra `before_product_text`/`after_product_text`.
  Una columna ajena no puede moverse sin que el recibo lo delate.
- **Exactitud numérica.** El recibo se reparsea con `parse_int`/`parse_float` a
  tuplas etiquetadas, así que un número no se confunde con un texto idéntico ni
  pasa por un binario flotante.
- **Doble registro del mismo comando.** `unique(tenant_id,command_sha256)` en
  `product_spec_research_applications` lo cierra; mi preocupación de que dos
  `operation_id` distintos registraran el mismo comando no aplica.
- **ACL.** Las tres tablas tienen RLS habilitada **sin una sola policy** y todos
  los privilegios revocados de `public`, `anon`, `authenticated` y también de
  `service_role`. Las tres funciones son `security definer`, con `revoke` a los
  cuatro roles y `grant execute` sólo a `authenticated`; `service_role` no puede
  ejecutar `apply`. Ningún cliente puede fabricar ni habilitar su propio permiso.
- **Recuperación.** El camino de repetición devuelve el recibo **antes** de
  comprobar readiness y revocación, así que revocar no borra un recibo ya
  emitido; y compara `command_sha256`, `actor_id` y `tenant_id` antes de
  devolverlo.
- **Identidad.** `apply` exige `tenant_id=user_tenant_id()` **y**
  `actor_id=auth.uid()` sobre la fila registrada; el cliente rechaza otro
  proyecto o actor antes de tocar la red.
- **Marca.** Sigue fuera: `identity_patch` sólo admite `model`,
  `manufacturer_sku` y `gtin` en el RPC, y el preparador levanta excepción si
  aparece `brand`.

## Un límite de recuperación, dicho y no reportado como defecto

Las tres funciones filtran por `auth.uid()`. Si el actor registrado deja de
poder autenticarse, su recibo **no es recuperable por ninguna vía concedida**:
las tablas no son legibles ni por `authenticated` ni por `service_role`. Queda
sólo la vía privilegiada de base de datos. Es coherente con el diseño y con la
identidad como eje, pero conviene que el runbook lo diga antes de operar, porque
es el escenario en que alguien buscará el recibo con prisa.

## Reproducción

`uv run --with "jsonschema[format-nongpl]==4.26.0" python <probe>` sobre un
script de esta revisión que reutiliza las fixtures del propio proyecto
(`test_product_spec_application.ApplicationPreparationTest`) y una
`ApplicationSession` construida con `object.__new__` y un opener simulado, igual
que hace `ApplicationTransportTest`. Ambas pruebas pasan, es decir: ambos huecos
quedan demostrados. No hay red, ni credenciales, ni SQL.

## Alcance de esta revisión

Sólo lectura. No corrí SQL local —la sesión es de root—, así que las 42 pruebas
SQL con rollback, el recorrido y las tres contenciones reales entre dos sesiones
quedan como evidencia de root y no como afirmación mía. No reproduje
concurrencia: sigo sin llamar prueba de concurrencia a nada que no ejecute dos
transacciones. Nada de lo anterior habilita fill, registro ni despliegue.
