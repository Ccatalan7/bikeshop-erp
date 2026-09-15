# Habilitación por componente: decisión de integración

El primer paquete contempla nueve plantillas publicadas: guardabarros, cintas
de manillar, piezas de dirección, luces, candados, protecciones personales,
ruedas de aprendizaje, reparación de cámaras y reparación tubeless. Sólo añade
`member_profiles` sobre la colección existente `kit_members`. Conserva cada
campo, definición, opción, ayuda y regla; no modifica asignaciones ni hechos.
La preimagen del 14 de septiembre a las 23:15:34 UTC tiene cero vinculaciones
efectivas y explícitas para estas nueve plantillas en el tenant auditado.
Esa población cambió después: lectura productiva del 15-09 00:25 UTC confirma
68 productos en siete de esas familias (candados 31, luces 20, cintas 7,
tapabarros 4, piezas de dirección 3, ruedas de aprendizaje 2 y protección
personal 1). El despliegue conservó los datos y la lectura autenticada posterior
de los 68 productos confirmó esa conservación; no reutilizar el cero como estado vivo.

El compilador es `scripts/inventory/compile_member_profile_enablement.py`.
Los artefactos tienen prefijo `member-profile-enablement-2026-09-14-`.
Las 29 comprobaciones Dart y 18 casos SQL de avance, repetición y rollback
pasan. La verificación productiva falla antes del cambio, como corresponde.
**Aplicado y verificado el 15-09 a las 00:37:56 UTC:** migración
`20260915004000_product_spec_member_profile_enablement`, SHA
`0d22876b2490781d2ccb781c56f121b4f96f6f57c550bbeca743d59bdbd8e766`.
La ronda 215 de Claude concluyó aprobando este delta exacto de metadatos, sin
bloqueantes; véase `member-profile-enablement-final-review-2026-09-14.md`.
El verificador incorpora además las nueve revisiones exactas sugeridas por el
revisor: falló antes del despliegue y pasó después, junto a los 18 casos.
El recibo está en `.tmp/db/migration-receipts/20260915004000.receipt`.

Lectura autenticada posterior a las 00:42:16 UTC: **68 productos conservados
íntegramente, cero perfiles persistidos y cero productos rellenados**. Evidencia
en `.tmp/product-spec-catalog/member-enablement-live-20260915/`.
La prueba real abrió una ficha de `accessory_mount` dentro de AE0317 y mostró
identificación, MPN, referencia, fijación, giro, material y color propios de esa
pieza. Se cerró el formulario sin guardar. `ui-discard-readback.json`, de las
01:10:38 UTC, confirmó producto, observaciones, referencias e historial intactos,
producto activo y cero perfiles. `member-support-desktop.png` es el frame válido.
Actualización 15-09: el selector muestra nombres de plantillas activas, respeta
la precedencia del tenant y conserva las claves internas y restricciones. AE0317
permitió seleccionar «Soporte de accesorio» y crear su ficha en borrador también
a 430×940; restaurado a 1821×944 y descartado sin guardar. La lectura autenticada
posterior confirmó producto, hechos, referencias e historial intactos y cero
perfiles. Evidencia: `.tmp/product-spec-catalog/family-labels-20260915/`,
`member-support-compact.png` y `discard-readback.json`. Queda la interacción
embebida. Estas pruebas no certifican compatibilidad mecánica.

## Resoluciones y exclusiones

- Luces conserva su arquitectura actual. La restricción efectiva de familia
  excluye `light` de `kit_members`; el validador productivo devuelve
  `row_option` bloqueante para una luz y admite `accessory_mount`. La sonda
  fue de sólo lectura. D3 del revisor quedó corregido: las opciones de la
  definición global no sustituyen las restricciones de uso de cada plantilla.
- Bicicletas, ruedas y rotor de cables BMX se excluyen de este primer paquete.
  Sus tablas declarativas también pueden contener identidad o medidas por
  pieza; revisar sólo tablas cuyo rol dice `contents` no alcanza para resolver
  la propiedad del dato. No se altera una tabla vigente por su nombre o rol.
- Kits de transmisión: la preimagen real corrigió aquella propuesta. Los tres
  prototipos nunca se publicaron y no necesitan campos legacy. El reemplazo
  de los once campos reales por `kit_members` está aplicado (`20260915023000`),
  revisado y probado con seis lecturas autenticadas y el editor real.
  [Adjudicación del kit](drivetrain-kit-members-adjudication-2026-09-15.md).
- Conjuntos de freno: se acepta separar circuito e identidad/medidas por pieza,
  pero la propuesta 214 no se puede implementar literalmente. Una posición
  coincidente no es un vínculo de identidad: debe existir referencia a una fila
  concreta. Tampoco se copia el espesor admitido por un cáliper al espesor real
  de un rotor. Las conexiones siguen requiriendo una pieza dueña identificada.
  El framework actual valida perfiles individualmente; no implementa la
  comparación entre tablas que esa propuesta atribuía a su guardia.

**Precisión de preimagen:** las cinco definiciones propuestas
`drivetrain_kit_member_evidence`, `drivetrain_kit_member_interfaces`,
`drivetrain_kit_member_fitments`, `brake_assembly_configurations` y
`brake_circuit_connections` no aparecen en el catálogo productivo capturado.
No se deben crear campos legacy sólo para conservar un prototipo nunca
publicado. El siguiente delta debe comprobar esa ausencia por ID/clave,
modificar o retirar las definiciones candidatas y conservar únicamente los
campos/observaciones que sí existen; el catálogo congelado anterior queda
como evidencia histórica, sin reescribirlo.

Estas resoluciones no declaran compatibilidad, cierre global ni autorización
de llenado. El número de familias habilitadas para perfiles se mide aparte de
las 68 plantillas entregadas, los sucesores originales y los productos llenados.
