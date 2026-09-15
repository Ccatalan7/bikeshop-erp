# Checkpoint de publicación y continuidad — 2026-09-07

macOS **1.0.3 (177)** y Android **1.0.3+65 / código 2065** publicados y
verificados desde `f51f3777e3ef1c6cd54753d9b6a3d2d2b06840fd`.

- [Calificación completa, correcta](https://github.com/Ccatalan7/bikeshop-erp/actions/runs/34163176197): cuatro partes de pruebas, análisis y compilación web.
- [macOS publicado](https://github.com/Ccatalan7/bikeshop-erp/releases/tag/macos-v1.0.3-177): firma Ed25519, igualdad de manifiestos estable/inmutable, hash del ZIP y del instalador, identidad/versión del bundle y sello de código comprobados de forma independiente. Publicado a las 14:41:09 de Los Ángeles.
- [Android publicado](https://github.com/Ccatalan7/bikeshop-erp/actions/runs/34163218438): manifiesto retenido comprobado, paquete `com.vinabike.erp`, SHA/base exactos, tamaño 102188040 bytes y tres partes ordenadas del APK.
- Evidencia local: `.tmp/releases/checkpoint-20260907-evidence/`; estado y recibo de archivos en `.tmp/releases/checkpoint-20260907-live-status.json` y `checkpoint-20260907-source-receipt.json`.

## Estado del checkout

El release se preparó en `.tmp/releases/checkpoint-20260907`, rama
`smartpegas1.0`, limpia y sincronizada con el remoto. El checkout principal
conserva su HEAD `71926a11cb47edec16dd798e8e92048d301c1630`, los cambios del
operador y la investigación privada. Los 152 archivos de la publicación
coincidían con el principal al congelar el source. No ejecutar un reset/limpieza
para reconciliarlos; revisar el estado vivo y preservar los archivos privados.
La sesión canónica `payroll` continúa con PID 90499, sin reemplazo ni navegación.
Las correcciones de CI posteriores al primer commit fueron documentos y pruebas;
no hubo cambios adicionales de comportamiento ni escrituras de producción.

## Auditoría de adopción terminada antes del corte

Captura autenticada de 1.664 productos, incluyendo inactivos y servicios,
terminada a las 19:03:34Z; auditoría offline del catálogo propuesto a las 19:10Z.
Son instantáneas de esas horas, no un inventario actualizado después del release.

- Productos con ficha evaluados: 863.
- Productos con conflictos bloqueantes: 0.
- Productos con datos pendientes: 815.
- Observaciones retenidas como legacy: 813.
- Observaciones activas sin proyección: 0.
- Sin ficha: 801 (742 físicos y 59 servicios).
- Escrituras: cero; ni publicación del catálogo propuesto ni llenado autorizados por el simulador.

Artefacto: `.tmp/product-spec-catalog/catalog-adoption-audit-20260907T1910.json`,
SHA-256 `da965cf3950b689fc9b3bef6b35c958da97fc200c0ea041dfb323efdbd67dce4`.
Preimágenes: `.tmp/product-spec-catalog/adoption-snapshots-20260907T1900/`.
No publicar estas capturas ni el registro nominal del inventario en GitHub.

## Trabajo abierto

La infraestructura hasta la migración 2600 está aplicada y verificada. El
catálogo ampliado de 105 plantillas sigue como propuesta. Resolver la adopción
de observaciones legacy, asignaciones y los hallazgos A/W/ND y de consumidores;
adjudicar la revisión de Claude de 12 familias no transmisión, sin asumir que
la propuesta de excluir luces de ciertos kits es correcta. Cerrar el simulador
y el aplicador autenticado de specs con revisiones, fuentes y recibos de backup
antes de activar el llenado por familias. El saneamiento global y el llenado
siguen abiertos; el llenado aplicado continúa en **cero**.
