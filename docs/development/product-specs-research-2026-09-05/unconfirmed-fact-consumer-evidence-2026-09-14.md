# Evidencia para revisión independiente: observaciones sin confirmar

La cámara Chaoyang SKU 6927116185398 está sin plantilla y mantiene siete
observaciones de agosto: dos `inferred` y cinco `supplier_text`, todas con
`confirmed = false`. Snapshot autenticado v2 y sonda productiva de sólo lectura
en `.tmp/product-spec-catalog/assignment-existing-tube-20260914/`.

La sonda de la plantilla `tube` v6 devuelve los siete valores mediante
`spec_active_product_values_internal_v1`, cero campos ajenos y cero incidencias
de `spec_validate_draft_internal_v1`. Esto comprueba proyección/validación
estructural, no un veredicto emitido por un consumidor ni verdad del contenido.
No se asignó todavía la cámara ni se cambiaron sus observaciones.

La captura global de las 22:45 UTC contiene 1.653 observaciones: 1.127 de texto
de proveedor, 282 importadas, 229 inferidas, 14 lecturas del nombre y una de
mecánico; todas con `confirmed = false`. No asumir que ese booleano represente
por sí solo el estado epistemológico: el contrato §4.2 los distingue.

Puntos de entrada a revisar: la función de proyección activa,
`get_product_spec_contexts_v1`,
`BikeProductCompatibilityService._assessDetailedTubeCompatibility`, y la
proyección de fichas públicas/criterios de compras. El editor debe conservar la
observación y su procedencia. Un análisis debe separar verla de usarla como
evidencia para una afirmación positiva o negativa de compatibilidad.

Revisión solicitada cuando Claude tenga cuota: reproducir con fixture local
conversión a contexto y veredicto; determinar qué estados de origen soporta hoy
el contrato y si falta una guardia de confianza. Entregar hecho, hipótesis,
impacto y corrección mínima; no aplicar una regla masiva sobre `confirmed`, no
eliminar datos y no escribir producción. Todavía no se declara un defecto
concreto ni una nueva semántica aprobada.
