# Revisión de Claude y resolución — 2026-09-06

Conversación: **Diagnóstico fichas técnicas Viñabike**,
[chat](https://claude.ai/epitaxy/local_3946be48-2ee1-4f75-a046-95f15862b7ab).
Se verificaron Code, `bikeshop-erp`, Fable 5.1 y Ultracode. La opinión inicial
fue independiente; después se pidió una revisión de implementación sólo lectura.
Claude respondió sobre el estado del código de las 23:37 del 2026-09-05 PDT.
Codex volvió a leer su respuesta completa en la app antes de cerrar esta ronda.
Claude no editó nuestros archivos. Esta evidencia no es una segunda aprobación
suya del estado final posterior a las correcciones.

## Hallazgos aceptados

| Hallazgo de Claude | Resolución y evidencia |
|---|---|
| El nuevo requisito de modo convierte 18 cadenas publicadas con velocidades conocidas en fichas inválidas | Ausencia = pendiente no bloqueante en Dart/SQL. La proyección pública conserva hechos conocidos incompletos; los conflictos explícitos suprimen campos afectados. Regresión en pgTAP. La cifra es su lectura productiva de las 23:37, no un conteo permanente. |
| Ajustar stock genera un `updatedAt` del cliente que nunca coincide al guardar | Releer producto autoritativo después del ajuste; adoptar timestamp sólo si identidad/campos editables y revisión de ficha siguen iguales. Prueba de esa comparación; no se ajustó stock productivo para ensayarla. |
| Productos sin plantilla reciben una falsa advertencia de compatibilidad | `unmapped` queda fuera de la compuerta de conflictos. La falta de una ficha técnica no prueba un problema de una herramienta o accesorio. |
| Un campo bloqueado no nombra un requisito situado más abajo | Helpers con etiquetas concretas, fuente antes de declaraciones, plataforma en su sección y orden topológico dentro de cada grupo. |
| eGlide pierde la restricción exclusiva cuando la bici no tiene plataforma | Cautela explícita LINKGLIDE/CUES con prioridad inferior a la cobertura general. Plataforma contraria conocida mantiene incompatibilidad con el claim. Prueba específica. |

## Aportes adicionales incorporados

- Aviso no bloqueante para el borrador manual KMC 6/7/8 + 11/128. Se pide modelo
  y fuente; no se presenta el ancho como una imposibilidad física universal.
- Guardar otros datos no reescribe observaciones idénticas como `mechanic` ni
  elimina sus lecturas. pgTAP verifica fuente, lecturas y revisión sin cambios.
- La ayuda explica que retirar una referencia quita sus hechos automáticos y
  conserva las respuestas manuales. Se probó en la app.
- Un conflicto de recibo idempotente recibe un mensaje en español para reabrir,
  en lugar de exponer el error SQL crudo.
- X8 EU quedó con el alcance literal de su propia edición: todos los sistemas
  6/7/8. La enumeración Shimano/SRAM/Campagnolo no se trasladó desde la página
  estadounidense a la edición europea. X11 conserva sus tres marcas declaradas.

La multiplicidad de validaciones por fila del trigger diferido permanece como
limitación de rendimiento. Evitar escrituras de hechos idénticos reduce ese
trabajo, pero no convierte el trigger en una única evaluación por agregado.

## Qué no se convirtió en regla

La revisión mecánica sostuvo la separación entre ancho nominal, ancho sobre el
pasador y compatibilidad declarada. Park Tool y Sheldon Brown no respaldan un
oráculo universal ancho→velocidades. Se mantiene el diagnóstico de simplificar
la captura, sin implementar exclusiones por marca ni un producto cartesiano de
listas. La evidencia final está en [implementation-result.md](implementation-result.md).
