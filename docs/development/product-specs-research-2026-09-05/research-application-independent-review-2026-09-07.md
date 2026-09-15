# Aplicador de investigación: revisión independiente

2026-09-07. Revisión sólo lectura de los cuatro archivos. No los edité y **no
corrí SQL local**, porque lo estás usando: todo lo que sigue sale de leer el
código y de comprobaciones que no tocan la base. Cuando algo no lo pude
ejecutar, lo digo.

**Veredicto: el diseño es sólido y el defecto que encontré es de los que no se
ven en verde.** Un defecto real de carrera, uno de precedencia que es decisión
tuya, y una lista de lo que las 41 pruebas sí demuestran y de lo que no.

## El defecto: la llave del lock del producto se arma con texto crudo

`apply_product_spec_research_v1` toma el candado por producto así:

```
pg_advisory_xact_lock(hashtextextended(tenant::text||':spec_fact:'||(command->>'product_id'),0))
```

y el otro escritor de hechos, `save_product_spec_facts_v1`, toma **el mismo
candado con la misma llave**, pero armada desde el uuid tipado:

```
pg_advisory_xact_lock(hashtextextended(v_tenant::text||':spec_fact:'||p_product_id::text,0))
```

`p_product_id::text` sale siempre en la forma canónica en minúsculas.
`command->>'product_id'` sale **tal cual venga en el JSON**. Postgres acepta un
uuid en mayúsculas, así que un comando con
`"F1112300-0000-4000-8000-000000000020"` produce una cadena distinta, un hash
distinto y **un candado distinto**. El producto que se bloquea con `for update`
sí es el correcto, porque ahí sí se castea; lo que se pierde es la exclusión
mutua con el otro escritor.

Y esa exclusión es la única que hay: `save_product_spec_facts_v1` **no toma
candado de fila sobre `products`** —sólo comprueba con un `select 1` que el
producto sea del tenant—, así que el `for update` del aplicador no lo detiene.
Con las llaves alineadas los dos se serializan; con las llaves divergentes
pueden correr a la vez sobre el mismo producto sin ningún candado compartido.

**Qué se rompe exactamente.** No es corrupción: si el otro escritor confirma
entre `before_state` y `after_state`, la comprobación de observaciones no
tocadas aborta, que es el comportamiento seguro. El problema es la ventana de
después: si confirma **entre la lectura de `after_state` y el commit de esta
transacción**, sobre hechos que este comando no toca, el recibo queda archivando
un `after_snapshot` que no es el estado que quedó en la tabla. El recibo deja de
ser el antes/después atómico que promete el comentario de la función.

**El arreglo es un cast**: `(command->>'product_id')::uuid::text` al construir la
llave, para que las dos partes hasheen la forma canónica. No lo toco: es tuyo.

Nota aparte de la misma familia: el candado de aplicación
(`':spec_research:'||p_application_id::text`) sí usa el parámetro tipado, así que
ese está bien. Es sólo el del producto.

## Precedencia: una lectura de mecánico se pierde ante una documental

El bucle protege el hecho **igual** —no roba confirmación, lectura ni fuente— y
eso está bien resuelto. Pero cuando el valor difiere no hay ninguna comprobación
sobre `old_fact.source` ni sobre `old_fact.confirmed`: el `on conflict do update`
pisa el valor, pone `source='research'`, `confirmed=false` y borra las lecturas.

O sea: una medición de taller, confirmada y con su lectura, la reemplaza una
lectura documental remota, y la ficha viva pasa a decir lo que dice el catálogo.
El dato viejo queda íntegro en `before_snapshot`, que es correcto y evita
atribuirlo al valor nuevo — pero eso es archivo, no precedencia.

Separaste la fuente `research` de `mechanic` justamente para no confundirlas;
esto es la otra mitad de esa decisión y hoy no está tomada en el código. No digo
que deba prohibirse: digo que hoy no hay regla y conviene que la haya, aunque
sea «una investigación no pisa un hecho confirmado por mecánico sin marcarlo
como conflicto».

## Concurrencia: qué está probado y qué no

Tienes razón en adelantarlo. La prueba de estado obsoleto cambia `cost` **en la
misma sesión** y después llama al RPC: demuestra que la comprobación de
preimagen dispara `40001` y que el fallo no deja rastro. Eso es una prueba de
*chequeo*, no de concurrencia; no hay dos transacciones simultáneas en ningún
punto del archivo.

Lo que sí verifiqué leyendo, y no está cubierto por ninguna prueba:

- El aplicador toma `products … for update` y `save_product_with_specs_v1`
  también (línea 506), así que ésos dos sí se serializan por la fila del
  producto. Es una protección real y no ejercitada.
- `save_product_spec_facts_v1` **no** toma esa fila, y depende del candado de
  aviso — el que puede divergir. Es el par peligroso.
- El orden de candados no puede formar ciclo con el publicador de metadata: éste
  toma las tablas de metadata y no toca `products`, y el aplicador toma
  `products` y luego esas tablas en `share`; `SELECT … FOR UPDATE` toma
  `ROW SHARE`, que **no** entra en conflicto con `SHARE`. No veo deadlock.

Lo que quedaría por probar de verdad: dos sesiones, mismo producto, una
aplicando y otra guardando por el camino normal, con el uuid en mayúsculas y en
minúsculas para ver la diferencia.

## Conservación, ACL y exactitud: lo que sí encontré bien

Lo verifiqué línea a línea y aguanta:

- **Ningún borrado implícito es posible.** Me preocupaba que una clave
  desapareciera de `preview->'values'` sin entrada individual en `changes`, así
  que fui a mirar: `candidate := editor->'values' || p_values_patch` es una
  unión, el preview rechaza de entrada un patch con `null`, cadena vacía o filas
  vacías, y devuelve `candidate` **sin filtrar**. Una clave no puede caerse. Las
  claves derivadas de una referencia sí entran, y ésas caen dentro del primer
  chequeo —difieren de la preimagen y exigen su `changes`—.
- **Tipos de dato**: los seis que existen —`number`, `boolean`, `text`,
  `single_select`, `multi_select`, `json`— están cubiertos por los brazos del
  `case`. Comprobado contra las 150 definiciones vivas y contra las 711 del
  congelado: ninguna cae fuera. Los brazos `single_line`/`multi_line` no
  corresponden a nada hoy; un tipo nuevo que no se agregue ahí entraría con sus
  cuatro columnas en NULL y sin error, así que ese `case` conviene que sea
  exhaustivo con `else raise`.
- **Identidad**: `brand` está en la lista del preview y **no** en la del
  comando, así que un cambio de marca previsualizado no puede aplicarse y además
  hace fallar la comparación de `expected_identity`. Cierra por los dos lados,
  como pediste.
- **Exactitud numérica**: la prueba con `9007199254740993.125` y con
  `0.100000000000000001` en una fila es la comprobación correcta —esas cifras no
  sobreviven a un `double`— y el GTIN `0000123` cubre el cero a la izquierda.
- **ACL**: las tres tablas revocadas también a `service_role`, el RPC revocado a
  `anon` y `service_role`, y pruebas de que un cliente autenticado no habilita su
  propia readiness ni registra su propio comando. La readiness se lee `for
  share`, así que no se puede deshabilitar por debajo a mitad de la operación.
- **Recibo**: se devuelve antes de mirar readiness o revocación, así que una
  respuesta perdida se recupera sin reescribir nada, y una revocación posterior
  no lo borra. El `||'replayed':true` pisa el `false` guardado.
- **Preservación del producto**: la comparación es `to_jsonb(before) - excepciones`
  contra `to_jsonb(after) - excepciones`, y las excepciones se calculan desde el
  propio parche. La prueba lo afirma sobre **todas** las columnas y no sólo
  precio y costo.

## Consecuencias que conviene tener escritas

- Revocar las tablas también a `service_role` significa que **ninguna
  herramienta operativa puede leer los recibos** sin una función definer que
  todavía no existe. Es coherente con que el registrador tampoco exista, pero es
  una pieza que falta para poder auditar después de aplicar.
- El RPC confía en el registrador para todo lo que no vuelve a comprobar: sólo
  re-verifica `product_id`, `status`, veredicto, sha de la propuesta revisada,
  que el revisor no sea el investigador, y `based_on`. Los `audit_sha256` y
  `review_sha256` de la readiness no se contrastan con nada aquí. Está bien como
  frontera, pero entonces el registrador es tan crítico como este archivo y no
  puede quedar sin su propia revisión independiente.
- `alter table spec_facts drop constraint … add constraint …` toma
  `ACCESS EXCLUSIVE` y revalida la tabla entera. En un candidato local no
  importa; en producción es una ventana que hay que planificar.

## Alcance de esta revisión

41 pruebas declaradas (13 Python, 28 SQL) que **no ejecuté**. Leí sus
afirmaciones y las cito por lo que dicen, no por haberlas visto pasar. No hay
migración desplegable, no hay fila de readiness sembrada, no hay registrador y
`enabled` nace en `false`: nada de esto habilita llenar productos hoy.

| Archivo | SHA-256 |
|---|---|
| `scripts/inventory/prepare_product_spec_application.py` | `47269217a30e03b6…` |
| `scripts/inventory/sql/product_spec_application_candidate.sql` | `c19786bde97bc74f…` |
| `test/scripts/test_product_spec_application.py` | `0139930eaac2c843…` |
| `supabase/tests/product_spec_research_application_candidate.sql` | `1611ecd5fb57bad7…` |
