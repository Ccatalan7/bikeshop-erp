# Doce plantillas nuevas aplicadas — 2026-09-07

Aplicadas y verificadas a las **22:34:13Z** mediante
`20260907222000_non_drivetrain_spec_templates.sql`. Se añadieron 12 plantillas,
93 definiciones, 186 opciones y 132 usos de campo. `spec_evidence_source`
se reutiliza sin cambios. No se escribieron productos, hechos, referencias
OEM ni mapeos de categorías. **Llenado y reasignaciones siguen en cero.**

Las familias son bottle, bottle_cage, lock, audible_signal, reflector, souvenir,
food_beverage, rider_apparel, rider_glove, rider_protection, helmet y
workshop_chemical. Esto activa sus esquemas de representación; no demuestra
que sus productos estén clasificados, completados o certificados. La app
seguirá resolviendo cada producto por su asignación y respaldo de categoría;
esta entrega no introduce un selector ni cambia esa asignación.

## Implementación y revisión

El compilador `scripts/inventory/compile_non_drivetrain_publication.py` toma el
catálogo congelado `16459826…`, casos y preimagen con hash fijado. Sólo inserta
metadatos nuevos. Un replay exige igualdad JSONB exacta de todas las columnas
administradas; una regla adicional, colisión, edición posterior o cambio de
la definición compartida detiene la operación. No se usan upserts que reparen
silenciosamente diferencias. Cinco regresiones locales prueban esos límites
y revierten todas sus transacciones.

Claude retiró PUB-D01: excluir luces del contenido de candados/protecciones no
se justificaba por la supuesta duplicación de especificaciones. Se preserva
contenido parcial con familia desconocida como `row_incomplete` no bloqueante.
Dos helpers aclaran el alcance de las piezas. Root también corrigió el alcance
inicialmente propuesto: las definiciones y opciones deben ser globales para
las referencias OEM globales. No se crea una segunda identidad por tienda.

La revisión independiente detectó contención JSONB donde se prometía igualdad
y la ausencia del fingerprint de `category_tech_mappings`; ambos defectos
quedaron corregidos y revisados antes de desplegar. Informe final
`non-drivetrain-publication-independent-review-2026-09-07.md`, SHA
`10b21f7f7e7b3db4c0ee232360d351aa0d01ddbd2921a22f922e696aa69ae564`.

## Evidencia

- Migración SHA `169aa2ec8e934a46b235bc162cc05d415759baf086b7a1332cb30169ba397186`.
- Verificador SHA `e0c0b96839819946ebc07ec32c12aacb7f14afb1fa734b6e7bd3e9dcdf1e53e8`:
  falló antes con error SQL y pasó después; también ejercita 37 borradores
  sintéticos sobre las plantillas reales, sin escribir productos.
- Historia remota **APPLIED** y recibo
  `.tmp/db/migration-receipts/20260907222000.receipt`.
- **49 pruebas Dart**, **37 casos SQL**, **5 ensayos del publicador** y
  **8 pruebas del lector autenticado** correctos; análisis del test sin problemas.
- Lectura con el actor real: 12 plantillas, 132 campos, 94 definiciones
  incluyendo la compartida, 186 opciones y referencias de las 12 familias.
  Evidencia privada: `.tmp/product-spec-catalog/non-drivetrain-authenticated-readback.json`.
- Comparación independiente posterior: productos, facts, mapeos, validador,
  ACL y políticas sin diferencias. Evidencia `.tmp/db/spec-nd-live-before.json`
  y `spec-nd-live-after.json`. El servidor conserva el motor 2600
  `ac0738d5c2039412b603dc71adc41721`.

El lector añadió una única consulta GET de metadatos con proyección fija,
lista limitada de UUIDs y autenticación existente. No admite otras tablas,
filtros arbitrarios, escritura ni redirección de credenciales. No se instaló
otra sesión nativa: `payroll` y su PID 90499 se preservaron. No hay afirmación
de verificación visual de estas nuevas fichas sobre productos todavía sin
asignar. La distribución macOS177/Android65 anterior sigue siendo la vigente.

## Recuperación y límites para el siguiente bloque

El backup legacy completo permanece en
`/Users/Claudio/Vinabike Backups/Product Specs Legacy/20260906T222802Z-pre-fill`.
La preimagen adicional de metadatos y fingerprint está en
`/Users/Claudio/Vinabike Backups/Product Specs Legacy/20260907T2220Z-new-family-metadata`;
no es otro snapshot completo de productos. Desactivar estas plantillas es
reversible mientras no tengan ligaduras. Después, la guarda de asignaciones
impide retirarlas sin resolver dependencias; nunca restaurar hechos antiguos
sobre cambios posteriores.

Las identidades UUID/code del vocabulario se asignaron una sola vez. Una
corrección posterior de etiqueta debe conservar ambas mediante un forward
revisado, no volver a generar identidad desde la etiqueta nueva. Tampoco se
desactiva una opción citada por una referencia OEM: el lector de referencias
exige opciones activas. El compilador de creación no es un migrador de nombres.

Los 93 campos son ahora globales y compartidos, aunque el catálogo congelado
105/711 aún diga `origin=new`: ese origen es histórico. Antes de otro bloque,
usar este packet y la preimagen viva; no intentar recrearlos ni modificar sus
reglas como si siguieran inéditos. El catálogo completo sigue siendo propuesta.

La base total contiene 1.665 productos: el adicional observado a las 22:31Z
pertenece a otro tenant y el lector autenticado lo rechazó con 403. Se excluye
de la investigación de Viñabike por alcance, no por falta de ficha. La lista
de la tienda sigue con 1.664 registros, sin altas/bajas ni cambios nominales
respecto del inventario previo. La siguiente captura debe filtrar explícitamente
el tenant antes de entregar IDs al lector; no interpretar el total de toda la
instancia como inventario de una tienda.
