# Adjudicación final del grupo de rueda

La revisión anterior aprobó un candidato cuya forma de rosca todavía mezclaba
unidad del diámetro y unidad del paso. **No se publicó ese candidato.** Al
contrastar con la regresión existente `rnd_root_metric_diameter_tpi_pitch` y
releer Park Tool, se corrigió antes de aplicar. El caso de eje 10 mm × 26 TPI
demuestra por qué ambas unidades deben poder declararse independientemente.
La vía literal OEM preservaba la observación, pero no justificaba limitar
la representación numérica de un caso conocido. No cambiar ni convertir
el nominal para hacerlo caber en el formulario.

El sucesor usa `interface_kind` roscada/sin rosca/literal y dos decisiones:
`diameter_unit` y `pitch_unit`. Cada una gobierna sólo sus propios valores.
El negativo sigue siendo dos unidades de paso dentro de una sola declaración;
un diámetro en mm con paso en TPI es positivo. Ambas fuentes publicadas pueden
guardarse en filas separadas sin convertirlas ni compararlas por redondeo.

Esta corrección requiere nuevos hashes, casos SQL/Dart y revisión final antes
de publicar `20260908001000`. La preimagen de las siete compartidas y el backup
permanecen válidos; el cambio sólo afecta una definición aún no publicada.

Otros límites: WS-1 se evita en `valve_small_part`; el token corto de las otras
cuatro familias propuestas sigue pendiente. La compatibilidad de reparación
es declaración por fuente/modelo/superficie, no aprobación de toda la familia.
Mr. Tuffy no aporta datos mecánicos primarios leídos en esta ronda: los casos
de protector son sintéticos. El material se rotula como superficie a reparar,
por lo que un forro de butilo no afirma que todo el neumático sea de butilo.

Fuente releída: [Park Tool, Basic Thread Concepts](https://www.parktool.com/en-us/blog/repair-help/basic-thread-concepts),
apartado de designación de diámetro y paso. No se adopta un par de apriete,
tolerancia ni procedimiento de reparación como regla universal.
