# Conjuntos de piezas: propiedad y límite de la ficha

Ficha nueva `component_set`, publicada y verificada con `20260915035000`.
Resuelve la representación de
una presentación comercial con piezas distintas, como PO02409001058 (cierres
de rueda y asiento, foto revisada) y NNV71 (tuercas y rodamientos, título del
inventario). Identificar la presentación no confirma medidas ni montaje.

La raíz declara únicamente fuente y contenido. Cada fila identifica una pieza
física y tiene perfil propio; no hay medidas, interfaces o compatibilidades
intrínsecas comunes en la raíz. Piezas diferentes en modelo, posición o medida
se separan. Una cantidad agrupa únicamente piezas idénticas. Ausencia de filas
significa contenido pendiente, nunca pieza única ni cantidad uno deducida.

Primera selección revisada: bearing, brake_caliper, brake_lever, brake_pad,
fastener, hub_small_part, seat_clamp y wheel_retention. Las ocho
plantillas globales están activas y no tienen perfiles propios en la captura
productiva. La selección excluye conjuntos recursivos y familias no revisadas;
una familia desconocida permanece pendiente. Esto no cierra los sucesores de
esas ocho familias ni introduce comparaciones mecánicas entre perfiles.

Reutiliza `kit_members` y `spec_evidence_source` sin modificar sus definiciones.
La migración agrega una plantilla y dos campos sin modificar productos.
La operación posterior asignó los dos productos revisados, con recibos y
lecturas autenticadas; no escribió hechos, referencias, perfiles o información
comercial. Es una familia adicional al plan
inicial de 105: no altera ese denominador ni cuenta como un original terminado.

Pruebas: 15 comprobaciones Dart (plantilla + 14 casos) y 14 casos SQL, aplicación
y repetición exacta, rechazo de deriva de plantilla y de definición compartida,
todo local con rollback. La publicación usa sus triggers nativos. El ensayo SQL
conserva formas y reglas exactas y cambia sólo UUID/claves para aislar fixtures;
la base local aún no tiene instalado el framework de perfiles productivo.
`test_component_set_profiles.py` lo añade sólo dentro del rollback y pasa 11
aserciones sobre el escritor autenticado: resuelve dos familias privadas distintas,
guarda dos perfiles con valores separados, rechaza la medida en la raíz, el
perfil de una familia ajena y contenido raíz en la pieza, y conserva perfiles
en una edición ordinaria. Son dueños de pieza sintéticos; no validan contenido
OEM ni sustituyen una comprobación de la app real. El alta de la segunda
plantilla sintética difiere restricciones hasta insertar sus campos y luego las
comprueba, sin desactivar los triggers del guardado o la publicación.
Se corrigió sólo el nombre esperado del error SQL (`row_shape`), sin cambiar
entradas ni dominio para hacer pasar el ensayo.

Artefactos: `component-set-2026-09-15-{catalog,cases,packet}.json`, compilador
`scripts/inventory/compile_component_set.py`, ensayo
`scripts/inventory/test_component_set.py`. Evidencia privada en
`.tmp/product-spec-catalog/component-set-20260915/`. Candidato SQL SHA-256
`a95602280314cc98ff2fe4de110c15215fa94eacd4db206d66baa47b3c142207`.
Claude224 revisó el candidato previo y añadió 17 fronteras en ambos motores.
Root acepta H1 y retira `rim_brake`: su unidad/presentación necesita adjudicación,
y ninguno de los dos productos objetivo la requiere. No se deduce que todos sus
productos sean conjuntos sólo por los campos defectuosos de la plantilla antigua.
La preimagen v2 confirma ocho dueños; nuevo caso rechaza `rim_brake`. La revisión
previa queda fijada en `reviewed-v1/`; este delta sólo reduce las opciones.
H2: una medida no debe escribirse como modelo para distinguir filas. Los perfiles
conservan sus IDs y ubicación; una etiqueta de pieza más clara sigue pendiente.
Cantidad y rol dependen de la declaración: no se afirma que el motor demuestre
que las piezas agrupadas son idénticas. Fuente vacía en una fila no acredita la
identidad ni montaje; ausencia de ficha hija no autoriza crear un perfil.
Lectura autenticada: plantilla v3, dos campos y ocho resoluciones de ficha hija
verificados; ninguna apunta a una familia ajena. La tanda separada
`assignment-component-sets-20260915` aplicó sólo dos vínculos de plantilla:
propuesta `0c4bfdc2e46b4ae8695a4a297bb511f11319ea97290c8e4293f06252bdbadb34`,
SQL `535b11dd8319990c6eee2fe3e1a351f8ba2b28e307d07613d0ba27e82395a49f`.
Los dos recibos están verificados a las 03:49:09 UTC.

En la app macOS, tema claro y ventana de escritorio, NNV71 abrió un borrador
con una fila de familia tornillería y su ficha propia. Mostró MPN, referencia
de esa pieza, tipo de fijación, material y contenido propios. Se salió por
Atrás del workspace sin Guardar; a las 04:02:35 UTC ambos productos conservaban
exactamente sus campos, cero observaciones y cero perfiles. Evidencia en
`component-set-20260915/fastener-piece-fields.png` y
`assignment-component-sets-20260915/ui-discard-readback.json`, bajo la carpeta
privada de pruebas. Esto comprueba un recorrido de escritorio; la interacción
embebida y otras familias de pieza siguen pendientes. La fuente raíz se muestra
después de Contenido aunque éste depende de ella: pendiente revisar ese orden.
Ningún llenado.
