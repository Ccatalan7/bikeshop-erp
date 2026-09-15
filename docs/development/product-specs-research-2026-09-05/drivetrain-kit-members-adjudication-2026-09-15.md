# Kit de transmisión: propiedad por pieza

Estado: aplicado y verificado el 15-09 a las 02:24:00 UTC mediante
`20260915023000_drivetrain_kit_member_ownership`. Revisión independiente 220
aprobada contra el SQL exacto `6de5a28f…`; verificador `f6ba8092…`.
Las seis lecturas autenticadas posteriores (02:25:22 UTC) conservaron producto,
observaciones, referencias e historial. Cero perfiles creados y cero llenado.

La preimagen productiva del 15-09 a las 01:58:40 UTC tiene una plantilla
global `drivetrain_kit` v3, doce campos y seis productos efectivos. Las seis
lecturas autenticadas tienen cero observaciones y cero perfiles. El cambio
no rellena productos ni modifica sus asignaciones.

Se conserva `spec_evidence_source`. Los once campos reales restantes pasan
a sección y rol legacy, sin perder sus IDs, ayudas, valores por defecto ni
observaciones. Se añade el `kit_members` compartido y su contrato de perfiles.
La versión resultante es 16: un cambio de contrato, once usos de campo
modificados y uno añadido. No se supone un incremento de uno.

El catálogo congelado de sucesores no representa producción. Sus tres
tablas prototipo de evidencia, interfaces y fitment nunca se publicaron;
el candidato comprueba su ausencia por ID y clave. Tampoco se añaden los
tres escalares que figuraban como legacy en ese prototipo y que no existen
como campos del kit. Esto no afirma que sus definiciones globales no existan.

Cada perfil conserva modelo exacto, MPN, referencia y hechos de su propia
plantilla. La edición no se concatena al modelo para suplir un campo ausente.
El mapa de interfaces propuesto por Claude describe capacidades de los
sucesores; no demuestra que todas estén activas en las plantillas actuales.
El kit no deriva conexiones ni veredictos de compatibilidad entre piezas.
Los miembros tampoco se proyectan al consumidor raíz. Esos límites no se
convierten en afirmaciones mecánicas por aprobar pruebas de representación.

Pruebas: doce Dart; once casos SQL sobre publicación y repetición exactas;
trece aserciones del guardado real con esta metadata y datos sintéticos.
Dos filas de igual modelo conservan perfiles y medidas diferentes; se
rechazan hechos de otra ficha, dos perfiles para una fila, cambios legacy y
hechos de prototipos no publicados. Un decimal legacy equivalente se acepta;
la lectura autenticada conserva el dato y su huella completa no cambia. El
payload raíz no incorpora la medida del miembro. Todo el escenario local
termina en rollback. La verificación productiva de sólo lectura falla antes
del cambio por metadata antigua, después de comprobar la ausencia de prototipos.

Compilador: `scripts/inventory/compile_drivetrain_kit_members.py`.
Prueba del agregado: `scripts/inventory/test_drivetrain_kit_members.py`.
Entradas y comprobaciones privadas:
`.tmp/product-spec-catalog/drivetrain-kit-members-20260915/`.
El paquete exacto se guarda como `drivetrain-kit-members-2026-09-15-packet.json`.
La recuperación parte de su preimagen y del backup legacy accesible; cualquier
reversión productiva requiere un cambio nuevo contra la revisión entonces vigente.

Corrección de la revisión 219, incorporada por Root: los nombres de familia
son presentación. Si falta uno, la familia permitida sigue seleccionable y
reconocible; no se afirma que su plantilla esté inactiva. Un error de carga
de nombres tampoco bloquea la ficha. Veintiséis pruebas pasan tras los dos
ajustes. La prueba real previa mostró nombres en escritorio y compacto;
las correcciones de fallo de nombres tienen pruebas de widget, no se han
simulado alterando metadata productiva.

Prueba real posterior a la publicación: AE0244 abrió el editor raíz sin los
once campos legacy vacíos. Una fuente explícitamente de prueba habilitó añadir
una fila; se abrió una ficha de Rodamiento con identidad, MPN, referencia y
los campos de su plantilla vigente. No se afirmó que ese rodamiento integre
el producto ni que su ficha antigua ya tenga todas las medidas del sucesor.
El formulario se cerró sin guardar; `ui-discard-readback.json`, de las
02:29:55 UTC, verificó producto, hechos, referencias e historial intactos y
cero perfiles. Frame: `family-labels-20260915/member-bearing-desktop.png`.

La entrega cuenta como un reemplazo adaptado de las 37 familias originales:
69/105 entregas de plantilla, 36 reemplazos pendientes. No equivale a activar
el prototipo congelado ni a cerrar comparaciones mecánicas entre piezas.
La evidencia Dart de esta entrega son los doce casos ejecutados por Root con
ambos defines de catálogo y casos D1; una batería por defecto no la sustituye.
